#requires -Version 7
<#
.SYNOPSIS
  "装得下"边界扫描（reference/04-context.md 第①问）——唯一变量 = (卸载档, ctx)。
  方法：每个配置点启动 server（-LogPath 捕获 stderr）→ 读空闲 ded/shared →
        解析 llama-server 日志里 CUDA0 model / KV / compute buffer size（精确显存账）→ 短生成复核。
  判据：shared 从基线跳升 = KV/图缓冲溢出到系统内存 → 该 ctx 在该卸载档下"装不下"（硬信号）。
        "装得下"不等于"能用"，能撑多深见 prefill_profile.ps1。
  用法：
    .\scan_maxctx.ps1 -ModelPath <gguf> -Alias m -NcmoeList 20,22 -CtxList 65536,98304,131072
    仅当模型是 dense 时用 -NcpuFfnList 代替 -NcmoeList。
#>
param(
  [Parameter(Mandatory)][string]$ModelPath,
  [string]$Alias = 'model',
  [string]$LlamaDir = '',                 # 空 = 取 $env:LLAMA_CPP_DIR
  [int[]]$NcmoeList = @(),                # MoE：要扫的 -ncmoe（空则用 0）
  [int[]]$NcpuFfnList = @(),              # dense：要扫的 -ncffn（空则用 0）
  [int[]]$CtxList = @(65536, 98304),      # 要验证的上下文（先算账再只验边界 2-3 点）
  [string]$Kv = 'q8_0',
  [int]$Threads = 0,                      # 0 = 用上游 auto（物理核数）
  [int]$ReasoningBudget = 0,              # 0 = 按硬规则取 ctx/2
  [int]$GpuId = 0,
  [int]$Reps = 3,
  [string]$LogDir = '',                   # 空 = <WorkDir>\logs
  [string]$WorkDir = ''                   # 空 = 取 $env:DSH_WORK_DIR，否则当前目录
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'start_server.ps1')
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
if (-not $LogDir) { $LogDir = Join-Path $WorkDir 'logs' }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Get-LogBuffers {
  param([string]$Path)
  $r = [ordered]@{ model = -1; kv = -1; cmpg = -1; cpu = -1 }
  if (-not (Test-Path $Path)) { return $r }
  foreach ($l in (Get-Content $Path -ErrorAction SilentlyContinue)) {
    if     ($l -match 'CUDA0\s+model buffer size\s*=\s*([\d\.]+)')   { $r.model = [math]::Round([double]$matches[1]) }
    elseif ($l -match 'CUDA0\s+KV buffer size\s*=\s*([\d\.]+)')      { $r.kv    = [math]::Round([double]$matches[1]) }
    elseif ($l -match 'CUDA0\s+compute buffer size\s*=\s*([\d\.]+)') { $r.cmpg  = [math]::Round([double]$matches[1]) }
    elseif ($l -match '(?:CPU|Host)\s+model buffer size\s*=\s*([\d\.]+)') { $r.cpu = [math]::Round([double]$matches[1]) }
  }
  return $r
}

# GPU 总量从 nvidia-smi 取（不硬编码卡型）
$total = 0
$q = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
if ($q) { $total = [int](($q | Select-Object -First 1) -replace '[^\d]', '') }

$meta = Get-GgufMeta -ModelPath $ModelPath
$mode = if ($NcpuFfnList.Count -gt 0 -and $NcmoeList.Count -eq 0) { 'ncffn' } else { 'ncmoe' }
if ($mode -eq 'ncmoe' -and -not $meta.isMoE) { Write-Warning "模型 dense（expert_count=0），建议改用 -NcpuFfnList（reference/02-offload.md）" }
$vals = if ($NcmoeList.Count -gt 0) { $NcmoeList } elseif ($NcpuFfnList.Count -gt 0) { $NcpuFfnList } else { @(0) }

Write-Host "===== maxctx scan  mode=$mode vals=$($vals -join ',')  kv=$Kv  threads=$(if($Threads -gt 0){$Threads}else{'auto'}) =====" -ForegroundColor Yellow
Write-Host ("GPU total = $total MiB ; idle now: {0}" -f (Get-Vram -GpuId $GpuId))
Write-Host "[meta] isMoE=$($meta.isMoE) block=$($meta.block_count) perLayer=$($meta.perLayerMB)MB kv/token(f16)=$($meta.kvBytesPerTokenF16)B kvLayers=$($meta.kvLayers)"

$rows = @()
foreach ($N in $vals) {
  foreach ($C in $CtxList) {
    $rb = if ($ReasoningBudget -gt 0) { $ReasoningBudget } else { [int]($C / 2) }
    Write-Host "`n########## $mode=$N ctx=$C kv=$Kv rb=$rb ##########" -ForegroundColor Cyan
    $sp = $null
    $log = Join-Path $LogDir "maxctx_${mode}${N}_${Kv}_c$C.err.log"
    try {
      $sw0 = [System.Diagnostics.Stopwatch]::StartNew()
      $sp = Start-LlamaServer -ModelPath $ModelPath -Alias $Alias -LlamaDir $LlamaDir -Ngl 99 `
        -ContextSize $C -CacheTypeK $Kv -CacheTypeV $Kv -Fa 'on' `
        -MoeMode $(if($mode -eq 'ncmoe'){'ncmoe'}else{'none'}) -Ncmoe $(if($mode -eq 'ncmoe'){$N}else{0}) `
        -NcpuFfn $(if($mode -eq 'ncffn'){$N}else{0}) `
        -Threads $Threads -ReasoningBudget $rb -GpuId $GpuId -SkipHelpCheck -LogPath $log
      $sw0.Stop()
      Start-Sleep -Seconds 2
      $idle = Get-Vram -GpuId $GpuId
      $b = Get-LogBuffers -Path $log
      $sum = if ($b.model -ge 0 -and $b.kv -ge 0 -and $b.cmpg -ge 0) { $b.model + $b.kv + $b.cmpg } else { -1 }
      Write-Host ("load={0}s idle: {1}  bufs: model={2} kv={3} compute={4} sum={5} headroom={6}" -f `
        [math]::Round($sw0.Elapsed.TotalSeconds,1),$idle,$b.model,$b.kv,$b.cmpg,$sum,($total - $sum))

      $null = Invoke-Short -server $sp -NPredict 16      # 弃用（graph 捕获）
      $t = @()
      for ($r = 1; $r -le $Reps; $r++) { $m = Invoke-Short -server $sp -NPredict 160; $t += $m.tps; Start-Sleep -Milliseconds 150 }
      $avg = [math]::Round(($t | Measure-Object -Average).Average, 1)
      $v2 = Get-Vram -GpuId $GpuId
      $sh = 0; if ($v2 -match 'shared=(\d+)') { $sh = [int]$matches[1] }
      $dd = 0; if ($v2 -match 'ded=(\d+)')    { $dd = [int]$matches[1] }
      # 判据：shared 是否相对基线跳升（基线在本次扫描第一个点之前读一次最可靠；这里用固定阈值做粗判）
      $verdict = if ($sh -le 250) { 'FIT' } elseif ($sh -le 700) { 'PARTIAL' } else { 'SPILL' }
      Write-Host ("$mode=$N ctx=$C short=[{0}] avg={1} t/s  ded={2} shared={3}  => {4}" -f `
        ($t -join '/'),$avg,$dd,$sh,$verdict) -ForegroundColor $(if($sh -le 250){'Green'}else{'Red'})
      $rows += [pscustomobject]@{ mode=$mode; offload=$N; ctx=$C; kv=$Kv; ded=$dd; shared=$sh;
        model=$b.model; kvbuf=$b.kv; compute=$b.cmpg; sum=$sum; tps=$avg; verdict=$verdict }
    } catch {
      Write-Host "$mode=$N ctx=$C ERROR: $($_.Exception.Message)" -ForegroundColor Red
      $rows += [pscustomobject]@{ mode=$mode; offload=$N; ctx=$C; kv=$Kv; ded=-1; shared=-1;
        model=-1; kvbuf=-1; compute=-1; sum=-1; tps=-1; verdict="ERROR: $($_.Exception.Message)" }
    } finally {
      if ($sp) { Stop-LlamaServer $sp; $sp = $null }
      Start-Sleep -Seconds 3
    }
  }
}
Write-Host "`n================ SUMMARY (kv=$Kv) ================" -ForegroundColor Yellow
$rows | Format-Table -AutoSize
$out = Join-Path $WorkDir "data\maxctx_$(($Alias -replace '[^\w\-]','_')).json"
$rows | ConvertTo-Json -Depth 4 | Set-Content $out -Encoding UTF8
Write-Host "[done] saved $out" -ForegroundColor Yellow
