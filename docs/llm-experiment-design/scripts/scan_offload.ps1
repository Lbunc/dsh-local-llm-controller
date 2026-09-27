#requires -Version 7
<#
.SYNOPSIS
  统一卸载扫描（dense -ngl / MoE -ncmoe 同构）—— SKILL.md 第 2.1 步
  落地：判定门（据 GGUF expert_count 确认 mode 与架构匹配）、四件套（t/s + ded/shared + GPU util + CPU util）、
        端口 55555 / apiKey dsh-local-llm（via start_server）、最小上下文 32K。
  用法：
    MoE  : .\scan_offload.ps1 -ModelPath <你的.gguf> -Alias <名> -LlamaDir <llama.cpp 目录> -OffloadMode ncmoe -Start 16 -End 26 -Step 2
    dense: .\scan_offload.ps1 -ModelPath <你的.gguf> -Alias <名> -LlamaDir <llama.cpp 目录> -OffloadMode ngl  -Start 99 -End 90 -Step 1
#>
param(
  [Parameter(Mandatory)][string]$ModelPath,
  [Parameter(Mandatory)][string]$Alias,
  [string]$LlamaDir = '',                        # 空 = 取 $env:LLAMA_CPP_DIR
  [ValidateSet('ngl','ncmoe','ncffn')][string]$OffloadMode = 'ncmoe',
  [int]$Start, [int]$End, [int]$Step = 2,        # ngl: Start>=End 递减；ncmoe: Start<=End 递增
  [int]$ContextSize = 32768,                      # 最小 32K（SKILL.md 1a）
  [int]$DeepFillRounds = 0,                        # 0 = 自动 max(2,(C-8000)/4500)
  [int]$GpuId = 0,
  [int]$Threads = 0, [int]$ReasoningBudget = 0, [string]$SpecType = '', [int]$SpecDraftNMax = 0,
  [string]$FillTextPath = '',   # 空 = 用内置合成语料自动生成到 <WorkDir>\data\fill_text.txt
  [string]$WorkDir = ''            # 空 = 取 $env:DSH_WORK_DIR，否则当前目录
)
. (Join-Path $PSScriptRoot 'start_server.ps1')
$ErrorActionPreference = 'Continue'

# SKILL 硬规则：思考预算 = 上下文的一半（未显式指定时自动取）
if ($ReasoningBudget -le 0) { $ReasoningBudget = [int]($ContextSize / 2) }
$LlamaDir = Resolve-LlamaDir $LlamaDir

# --- 判定门：读 GGUF meta 确认 OffloadMode 与架构匹配（reference/02-offload.md）---
$meta = Get-GgufMeta -ModelPath $ModelPath
if ($OffloadMode -eq 'ncmoe' -and -not $meta.isMoE) { throw "判定门：OffloadMode=ncmoe 但模型 dense（expert_count=0），应使用 -OffloadMode ngl" }
if ($OffloadMode -eq 'ncffn' -and $meta.isMoE)     { throw "判定门：OffloadMode=ncffn 但模型是 MoE，应使用 -OffloadMode ncmoe" }
if ($OffloadMode -eq 'ngl' -and $meta.isMoE)       { Write-Warning "判定门：OffloadMode=ngl 用于 MoE 模型（MoE 通常用 -ncmoe 卸载专家更优）" }
if ($ContextSize -lt 32768) { throw "ContextSize $ContextSize < 32768（最小上下文约束）" }

# 默认范围（未传时按 mode 给合理默认）
if (-not $Start) { $Start = if ($OffloadMode -eq 'ngl') { 99 } else { 16 } }
if (-not $End)   { $End   = if ($OffloadMode -eq 'ngl') { 90 } else { 26 } }

# 生成卸载值序列（ngl 递减 / ncmoe,ncffn 递增）
$vals = [System.Collections.ArrayList]::new()
if ($OffloadMode -eq 'ngl') {
  if ($Start -lt $End) { throw "ngl 模式需 Start>=End（从大往小减，卸载增多）" }
  for ($v=$Start; $v -ge $End; $v-=$Step) { [void]$vals.Add($v) }
} else {
  if ($Start -gt $End) { throw "$OffloadMode 模式需 Start<=End（从小往大增，卸载增多）" }
  for ($v=$Start; $v -le $End; $v+=$Step) { [void]$vals.Add($v) }
}
Write-Host "===== scan_offload mode=$OffloadMode vals=$($vals -join ',') ctx=$ContextSize gpu=$GpuId =====" -ForegroundColor Yellow
Write-Host "[meta] isMoE=$($meta.isMoE) block=$($meta.block_count) expert=$($meta.expert_count) perLayer=$($meta.perLayerMB)MB kvLayers=$($meta.kvLayers)" -ForegroundColor Yellow

$fillText = Get-FillText -FillTextPath $FillTextPath -TargetTokens 4000

foreach ($v in $vals) {
  $tag = "$OffloadMode=$v"
  Write-Host "`n########## $tag ctx=$ContextSize ##########" -ForegroundColor Cyan
  $sp = $null
  try {
    $sp = switch ($OffloadMode) {
      'ncmoe' { Start-LlamaServer -ModelPath $ModelPath -Alias $Alias -LlamaDir $LlamaDir -ContextSize $ContextSize -Ngl 99 -Ncmoe $v -MoeMode ncmoe -Threads $Threads -ReasoningBudget $ReasoningBudget -SpecType $SpecType -SpecDraftNMax $SpecDraftNMax -GpuId $GpuId }
      'ncffn' { Start-LlamaServer -ModelPath $ModelPath -Alias $Alias -LlamaDir $LlamaDir -ContextSize $ContextSize -Ngl 99 -NcpuFfn $v -MoeMode none -Threads $Threads -ReasoningBudget $ReasoningBudget -SpecType $SpecType -SpecDraftNMax $SpecDraftNMax -GpuId $GpuId }
      default { Start-LlamaServer -ModelPath $ModelPath -Alias $Alias -LlamaDir $LlamaDir -ContextSize $ContextSize -Ngl $v -MoeMode none -Threads $Threads -ReasoningBudget $ReasoningBudget -SpecType $SpecType -SpecDraftNMax $SpecDraftNMax -GpuId $GpuId }
    }
    Write-Host "$tag applied_ctx=$($sp.ctx)"
    Start-Sleep -Seconds 2
    Write-Host "$tag idle: $(Get-Vram -GpuId $GpuId) cpu=$(Get-CpuUtil)"

    # --- short test（短上下文稳态 t/s，首请求含 graph 捕获弃用，取第 2 次）---
    $s1 = Invoke-Short $sp      # 弃用（graph 捕获）
    $s2 = Invoke-Short $sp
    Write-Host "$tag short: gen=$($s2.n)t eval=$($s2.tps)/s"

    # --- deep test（深填充 eval t/s + 四件套 util 采样，eval 阶段够长）---
    $rounds = if ($DeepFillRounds -gt 0) { $DeepFillRounds } else { [math]::Max(2, [math]::Floor(($ContextSize - 8000) / 4500)) }
    if ($fillText) {
      $msgs = @()
      for ($i=1; $i -le $rounds; $i++) {
        $msgs += @{ role='user'; content="Please provide a detailed explanation of topic number $i, covering background, history, current state and future outlook. Write as much detail as possible." }
        $msgs += @{ role='assistant'; content="Here is my detailed explanation of topic $i : $fillText" }
      }
      $msgs += @{ role='user'; content='Based on all the discussions above, write a brief conclusion paragraph of 100 words.' }
      $body = @{ model=$Alias; messages=$msgs; max_tokens=128; temperature=1.0; top_k=20; top_p=0.95; min_p=0.0 } | ConvertTo-Json -Depth 6
      $samp = Start-UtilSampler -GpuId $GpuId -IntervalSec 1
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $timeout = [math]::Max(360, [int](($ContextSize / 600) * 1.6 + 90))
      try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$($sp.port)/v1/chat/completions" -Method Post -Headers $sp.headers -Body $body -TimeoutSec $timeout
        $sw.Stop(); $t = $r.timings
        $utilOut = Stop-UtilSampler $samp; $samp = $null
        $gu = Get-UtilTailMean $utilOut -Tail 10
        $cu = Get-UtilTailMean $utilOut -Tail 10 -Cpu
        Write-Host "$tag deep(rounds=$rounds): prompt=$($t.prompt_n)t gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s wall=$([math]::Round($sw.Elapsed.TotalSeconds,1))s gpu_util=$gu cpu_util=$cu"
      } catch {
        $sw.Stop(); if ($samp) { Stop-UtilSampler $samp | Out-Null; $samp = $null }
        Write-Host "$tag deep ERROR: $($_.Exception.Message)"
      }
    }
    Write-Host "$tag after: $(Get-Vram -GpuId $GpuId)"
    Stop-LlamaServer $sp; $sp = $null
    Start-Sleep -Seconds 3
  } catch {
    Write-Host "$tag ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($sp) { try { Stop-LlamaServer $sp } catch {} }
  }
}
Write-Host "`n===== scan_offload done (mode=$OffloadMode) =====" -ForegroundColor Yellow
