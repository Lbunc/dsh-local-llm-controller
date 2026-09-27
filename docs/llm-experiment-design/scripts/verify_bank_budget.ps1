#requires -Version 7
<#
.SYNOPSIS
  跑题前的预算校验（reference/04-context.md + reference/05-reasoning-budget.md）—— 跨设备可用。
  做两件事：
    1) 用 server 的 /tokenize 精确量出**每道题 prompt 的真实 token 数**（不靠字符估算）
    2) 校验 prompt_tokens + max_tokens ≤ n_ctx，并把最长的题做一次深填充，读 shared 确认深填充下不溢出
  用法：
    .\verify_bank_budget.ps1 -LlamaDir <dir> -Specs @('m|<模型路径>|ncmoe:20') -Ctx 65536 [-Tier hard]
  输出：<WorkDir>\data\bank_budget_verify.json
#>
param(
  [Parameter(Mandatory)][string[]]$Specs,
  [string]$LlamaDir = '',
  [ValidateSet('base','hard')][string]$Tier = 'hard',
  [int]$Ctx = 65536,
  [int]$ReasoningBudget = 0,
  [int]$Threads = 0,
  [string]$Kv = 'q8_0',
  [int]$GpuId = 0,
  [string]$WorkDir = ''              # 空 = 取 $env:DSH_WORK_DIR，否则当前目录
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'start_server.ps1')
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ($ReasoningBudget -le 0) { $ReasoningBudget = [int]($Ctx / 2) }
$LlamaDir = Resolve-LlamaDir $LlamaDir
$BankJson = Join-Path $BankDir "10q$(if($Tier -eq 'hard'){'_hard'}).json"
$bank = Get-Content $BankJson -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host "题库 = $BankJson（$($bank.items.Count) 题）  ctx=$Ctx rb=$ReasoningBudget"

$report = @()
foreach ($spec in $Specs) {
  $p = $spec.Split('|'); $name = $p[0]; $model = $p[1]; $off = $p[2]
  $om = ($off -split ':')[0]; $ov = 0
  if (($off -split ':').Count -gt 1) { $ov = [int]($off -split ':')[1] }
  Write-Host "`n########## $name  ($off)  ctx=$Ctx ##########" -ForegroundColor Cyan

  $srvArgs = @{ ModelPath=$model; Alias=$name; LlamaDir=$LlamaDir; ContextSize=$Ctx
                CacheTypeK=$Kv; CacheTypeV=$Kv; Fa='on'; Threads=$Threads
                ReasoningBudget=$ReasoningBudget; GpuId=$GpuId; SkipHelpCheck=$true
                LogPath=(Join-Path $WorkDir "logs\budget_$Tier`_$name.server.log") }
  switch ($om) {
    'ncmoe' { $srvArgs.Ngl = 99; $srvArgs.MoeMode = 'ncmoe'; $srvArgs.Ncmoe = $ov }
    'ncffn' { $srvArgs.Ngl = 99; $srvArgs.MoeMode = 'none';  $srvArgs.NcpuFfn = $ov }
    'ngl'   { $srvArgs.Ngl = $ov; $srvArgs.MoeMode = 'none' }
    default { throw "未知卸载档 '$om'" }
  }

  $s = $null
  try {
    $s = Start-LlamaServer @srvArgs
    $idle = Get-Vram -GpuId $GpuId
    Write-Host "idle VRAM: $($idle -join ' | ')" -ForegroundColor Green

    $tokRows = @()
    foreach ($it in $bank.items) {
      $body = @{ content = $it.prompt } | ConvertTo-Json -Depth 3
      $r = Invoke-RestMethod -Uri "http://127.0.0.1:$($s.port)/tokenize" -Method Post -Headers $s.headers -Body $body -TimeoutSec 600
      $n = $r.tokens.Count
      $need = $n + [int]$it.max_tokens
      $fit = if ($need -le $Ctx) { 'OK' } else { 'OVER' }
      $tokRows += [pscustomobject]@{ qid=$it.qid; prompt_tokens=$n; max_tokens=[int]$it.max_tokens; need=$need; fit=$fit }
      Write-Host ("  {0,-5} prompt_tokens={1,7}  + max_tokens {2,6} = {3,7} / {4}  [{5}]" -f `
        $it.qid, $n, [int]$it.max_tokens, $need, $Ctx, $fit) -ForegroundColor $(if($fit -eq 'OK'){'Gray'}else{'Red'})
    }

    # 深填充校验：用 prompt 最长的那道题做一次真实深填充，读 shared
    $long = $bank.items | Sort-Object { -$_.prompt.Length } | Select-Object -First 1
    Write-Host "深填充（$($long.qid), $($long.prompt.Length) 字符）..." -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $body = @{ model=$name; messages=@(@{role='user';content=$long.prompt}); max_tokens=64
               temperature=0.6; top_k=20; top_p=0.95; min_p=0.0 } | ConvertTo-Json -Depth 6
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:$($s.port)/v1/chat/completions" -Method Post `
         -Headers $s.headers -Body $body -TimeoutSec 7200
    $sw.Stop()
    $after = Get-Vram -GpuId $GpuId
    Write-Host ("  prompt_n={0} prompt_ms={1} prompt_pps={2}  wall={3}s" -f `
      $r.timings.prompt_n, [int]$r.timings.prompt_ms, [math]::Round($r.timings.prompt_per_second,1), [math]::Round($sw.Elapsed.TotalSeconds,1))
    Write-Host ("  深填充后 VRAM: {0}" -f ($after -join ' | ')) -ForegroundColor Green
    $report += [pscustomobject]@{ model=$name; offload=$off; ctx=$Ctx; rb=$ReasoningBudget
      idle=($idle -join ' | '); post=($after -join ' | ')
      deep_qid=$long.qid; deep_prompt_n=$r.timings.prompt_n
      deep_prompt_pps=[math]::Round($r.timings.prompt_per_second,1); tokens=$tokRows }
  } catch {
    Write-Host "$name FATAL: $($_.Exception.Message)" -ForegroundColor Red
  } finally {
    Stop-LlamaServer $s
    Start-Sleep -Seconds 4
  }
}

$out = Join-Path $WorkDir "data\bank_budget_verify.json"
$report | ConvertTo-Json -Depth 6 | Set-Content $out -Encoding UTF8
Write-Host "`n[done] saved $out" -ForegroundColor Yellow
Write-Host "判据：① 全部 fit=OK；② 深填充后 shared 相对基线不跳升（跳升=该 ctx 在该卸载档下已溢出）" -ForegroundColor Cyan
