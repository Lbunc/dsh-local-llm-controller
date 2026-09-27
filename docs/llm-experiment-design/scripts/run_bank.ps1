#requires -Version 7
<#
.SYNOPSIS
  能力题库 runner（reference/09-capability-bank.md）—— 两档冻结题库通用，跨设备可用。
  题库来自本 skill 的 bank\ 目录（自包含：prompt / 官方答案键 / 判分规格 / 代码题用例），跑题时**不联网**。
  用法：
    .\run_bank.ps1 -LlamaDir <llama.cpp 目录> -Specs @('m|<模型A路径>|ncmoe:20','n|<模型B路径>|ncffn:16')
    .\run_bank.ps1 -Tier base -Only Q8,Q9 -MaxTokensOverride 24576        # 只补跑未完成的题（原地合并）
  说明：
    - Specs 格式 '名字|模型路径|卸载档'，卸载档为 ncmoe:N / ncffn:N / ngl:N / none
    - ctx 默认 65536（困难库固定 64K）；rb 默认 ctx/2（硬规则），max_tokens 取自题库，可 -MaxTokensOverride
    - 结果 JSON：<WorkDir>\data\bank_<tier>_answers_<名字>.json ；逐题日志：<WorkDir>\logs\bank_<tier>_<名字>_<qid>.txt
    - 中断/截断后**只补跑未完成的题**；已完成的题用 recover_bank_json.py 从日志还原，不重跑模型
#>
param(
  [Parameter(Mandatory)][string[]]$Specs,
  [string]$LlamaDir = '',                 # 空 = 取 $env:LLAMA_CPP_DIR
  [ValidateSet('base','hard')][string]$Tier = 'hard',
  [int]$Ctx = 65536,
  [int]$ReasoningBudget = 0,              # 0 = 按硬规则取 Ctx/2
  [int]$Threads = 0,                      # 0 = 上游 auto
  [string]$Kv = 'q8_0',
  [string]$CacheTypeV = '',               # 空 = 同 Kv
  [int]$GpuId = 0,
  [string[]]$Only = @(),                  # 只跑指定题号；结果原地合并进已有答案文件
  [int]$MaxTokensOverride = 0,
  [string]$WorkDir = ''                  # 空 = 取 $env:DSH_WORK_DIR，否则当前目录
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'start_server.ps1')
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- 硬规则与默认值 ---
if ($ReasoningBudget -le 0) { $ReasoningBudget = [int]($Ctx / 2) }
if (-not $CacheTypeV) { $CacheTypeV = $Kv }
$LlamaDir = Resolve-LlamaDir $LlamaDir
$BankJson = Join-Path $BankDir "10q$(if($Tier -eq 'hard'){'_hard'}).json"
if (-not (Test-Path $BankJson)) { throw "冻结题库不存在: $BankJson" }
$bank = Get-Content $BankJson -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host "题库 = $BankJson（$($bank.items.Count) 题）  ctx=$Ctx rb=$ReasoningBudget kv=$Kv t=$(if($Threads -gt 0){$Threads}else{'auto'})"
Write-Host "结果目录 WorkDir = $WorkDir"

foreach ($spec in $Specs) {
  $p = $spec.Split('|')
  if ($p.Count -lt 3) { throw "Specs 格式应为 '名字|模型路径|卸载档'，收到: $spec" }
  $name = $p[0]; $model = $p[1]; $off = $p[2]
  $om = ($off -split ':')[0]; $ov = 0
  if (($off -split ':').Count -gt 1) { $ov = [int]($off -split ':')[1] }
  if (-not (Test-Path $model)) { throw "模型不存在: $model" }
  Write-Host "`n########## $name  ($off) ##########" -ForegroundColor Cyan

  $srvArgs = @{ ModelPath=$model; Alias=$name; LlamaDir=$LlamaDir; ContextSize=$Ctx
                CacheTypeK=$Kv; CacheTypeV=$CacheTypeV; Fa='on'; Threads=$Threads
                ReasoningBudget=$ReasoningBudget; GpuId=$GpuId; SkipHelpCheck=$true
                LogPath=(Join-Path $WorkDir "logs\bank_$Tier`_$name.server.log") }
  switch ($om) {
    'ncmoe' { $srvArgs.Ngl = 99; $srvArgs.MoeMode = 'ncmoe'; $srvArgs.Ncmoe = $ov }
    'ncffn' { $srvArgs.Ngl = 99; $srvArgs.MoeMode = 'none';  $srvArgs.NcpuFfn = $ov }
    'ngl'   { $srvArgs.Ngl = $ov; $srvArgs.MoeMode = 'none' }
    'none'  { $srvArgs.Ngl = 99;  $srvArgs.MoeMode = 'none' }
    default { throw "未知卸载档 '$om'（应为 ncmoe:N / ncffn:N / ngl:N / none）" }
  }

  $s = $null
  try {
    $s = Start-LlamaServer @srvArgs
    Write-Host "started: $(Get-Vram -GpuId $GpuId)"
    $null = Invoke-Short -server $s -NPredict 16        # 预热，弃用
    $items = if ($Only.Count -gt 0) { $bank.items | Where-Object { $Only -contains $_.qid } } else { $bank.items }
    if ($MaxTokensOverride -gt 0) { Write-Host "max_tokens 覆盖为 $MaxTokensOverride" -ForegroundColor Yellow }
    $res = @()
    foreach ($it in $items) {
      $mt = if ($MaxTokensOverride -gt 0) { $MaxTokensOverride } else { $it.max_tokens }
      if ($it.prompt.Length / 3.5 + $mt -gt $Ctx) {
        Write-Warning "$($it.qid): prompt 约 $([int]($it.prompt.Length/3.5)) tokens + max_tokens $mt 可能超过 ctx $Ctx —— 先用 verify_bank_budget.ps1 量真实 token 数"
      }
      $body = @{ model=$name; messages=@(@{role='user';content=$it.prompt}); max_tokens=$mt
                 temperature=0.6; top_k=20; top_p=0.95; min_p=0.0 } | ConvertTo-Json -Depth 6
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $rec = [ordered]@{ qid=$it.qid; axis=$it.axis; label=$it.label; gtype=$it.gtype; max_tokens=$mt }
      try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$($s.port)/v1/chat/completions" -Method Post `
             -Headers $s.headers -Body $body -TimeoutSec 7200
        $sw.Stop()
        $ch = $r.choices[0]; $msg = $ch.message
        $think = if ($msg.reasoning_content) { $msg.reasoning_content } else { '' }
        $rec.content = $msg.content; $rec.thinking = $think; $rec.finish = $ch.finish_reason
        $rec.gen = $r.timings.predicted_n
        $rec.prompt_tokens = $r.timings.prompt_n
        $rec.prompt_tps = [math]::Round($r.timings.prompt_per_second, 1)
        $rec.tps = [math]::Round($r.timings.predicted_per_second, 1)
        $rec.wall = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        $rec.usage = $r.usage
        $f = Join-Path $WorkDir ("logs\bank_{0}_{1}_{2}.txt" -f $Tier, $name, $it.qid)
        ("=== {0} {1} {2} finish={3} prompt_n={4} gen={5} wall={6}s tps={7} ===`n--- thinking ---`n{8}`n--- content ---`n{9}" -f `
          $name, $it.qid, $it.label, $ch.finish_reason, $rec.prompt_tokens, $rec.gen, $rec.wall, $rec.tps, $think, $msg.content) |
          Set-Content $f -Encoding UTF8
        $flat = ($msg.content -replace '\s+', ' '); if ($flat.Length -gt 60) { $flat = $flat.Substring(0, 60) }
        Write-Host ("{0,-8} {1,-4} finish={2,-8} p={3,6} gen={4,6} wall={5,7}s tps={6,5} | {7}" -f `
          $name, $it.qid, $ch.finish_reason, $rec.prompt_tokens, $rec.gen, $rec.wall, $rec.tps, $flat)
      } catch {
        $sw.Stop(); $rec.error = $_.Exception.Message; $rec.wall = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        Write-Host ("{0,-8} {1,-4} ERROR: {2}" -f $name, $it.qid, $_.Exception.Message) -ForegroundColor Red
      }
      $res += [pscustomobject]$rec
      Start-Sleep -Milliseconds 200
    }

    # --- 写结果：-Only 时原地合并（替换已有的 + **追加原本没有的**），否则整份覆盖 ---
    $out = Join-Path $WorkDir "data\bank_${Tier}_answers_$name.json"
    if ($Only.Count -gt 0 -and (Test-Path $out)) {
      $old = Get-Content $out -Raw -Encoding UTF8 | ConvertFrom-Json
      $seen = @{}; $merged = @()
      foreach ($o in $old) {
        $seen[$o.qid] = $true
        if ($Only -contains $o.qid) {
          $n = $res | Where-Object { $_.qid -eq $o.qid } | Select-Object -First 1
          $merged += if ($n) { $n } else { $o }
        } else { $merged += $o }
      }
      foreach ($n in $res) { if (-not $seen.ContainsKey($n.qid)) { $merged += $n } }
      $merged | ConvertTo-Json -Depth 8 | Set-Content $out -Encoding UTF8
      Write-Host "merged $($Only -join ',') into $out (now $($merged.Count) items)" -ForegroundColor Green
    } else {
      $res | ConvertTo-Json -Depth 8 | Set-Content $out -Encoding UTF8
      Write-Host "saved $out" -ForegroundColor Green
    }
  } catch {
    Write-Host "$name FATAL: $($_.Exception.Message)" -ForegroundColor Red
  } finally {
    Stop-LlamaServer $s
    Start-Sleep -Seconds 4
  }
}
Write-Host "`n[done] bank run (tier=$Tier)" -ForegroundColor Yellow
