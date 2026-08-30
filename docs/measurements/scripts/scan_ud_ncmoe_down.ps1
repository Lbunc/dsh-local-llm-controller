#requires -Version 7
<#
.SYNOPSIS
  新模型 Qwen3.6-35B-A3B-UD-IQ4_NL 从 ncmoe 20 往下降扫描（模型比 Uncensored 小 1.6GB，
  应容纳更多专家在 GPU → 最优 -ncmoe 应 <=20）。找"共享显存回落基线 + 速度最高"点。
  固定：32K, q8_0 KV, ngl 99, threads 20, rb 2048。唯一变量 = -ncmoe。
.WHATIF
  每个点：加载 → 空闲四件套 → short（弃首请求）→ deep 填充（四件套 util）。端口 55555。
#>
param(
  [string]$ModelPath = 'F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-UD-IQ4_NL.gguf',
  [int[]]$NcmoeVals = @(20,18,16,14),
  [int]$ContextSize = 32768,
  [int]$GpuId = 0,
  [string]$FillTextPath = 'D:\DSH\WORK1\llama.cpp\data\prompt_4k.txt'
)
$ErrorActionPreference = 'Continue'
. 'D:\DSH\WORK1\llama.cpp\scripts\start_server.ps1'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$fillText = ''
if (Test-Path $FillTextPath) { $fillText = [System.IO.File]::ReadAllText($FillTextPath, [System.Text.Encoding]::UTF8) }
else { Write-Warning "FillTextPath 不存在: $FillTextPath" }

Write-Host "===== UD35B ncmoe DOWN-scan vals=$($NcmoeVals -join ',') ctx=$ContextSize =====" -ForegroundColor Yellow

foreach ($N in $NcmoeVals) {
  Write-Host "`n########## ncmoe=$N ##########" -ForegroundColor Cyan
  $sp = $null
  try {
    $sp = Start-LlamaServer -ModelPath $ModelPath -Alias ud35b -LlamaDir 'F:\llama-b10488-bin-win-cuda-13.3-x64' -ContextSize $ContextSize -Ncmoe $N -MoeMode ncmoe -Threads 20 -ReasoningBudget 2048 -GpuId $GpuId
    Write-Host "ncmoe=$N applied_ctx=$($sp.ctx) idle: $(Get-Vram -GpuId $GpuId) cpu=$(Get-CpuUtil)"

    $s1 = Invoke-Short $sp
    $s2 = Invoke-Short $sp
    Write-Host "ncmoe=$N short: gen=$($s2.n)t eval=$($s2.tps)/s"

    if ($fillText) {
      $rounds = [math]::Max(2, [math]::Floor(($ContextSize - 8000) / 4500))
      $msgs = @()
      for ($i=1; $i -le $rounds; $i++) {
        $msgs += @{ role='user'; content="Please provide a detailed explanation of topic number $i, covering background, history, current state and future outlook. Write as much detail as possible." }
        $msgs += @{ role='assistant'; content="Here is my detailed explanation of topic $i : $fillText" }
      }
      $msgs += @{ role='user'; content='Based on all the discussions above, write a brief conclusion paragraph of 100 words.' }
      $body = @{ model='ud35b'; messages=$msgs; max_tokens=128; temperature=1.0; top_k=20; top_p=0.95; min_p=0.0 } | ConvertTo-Json -Depth 6
      $samp = Start-UtilSampler -GpuId $GpuId -IntervalSec 1
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $timeout = [math]::Max(360, [int](($ContextSize / 600) * 1.6 + 90))
      try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$($sp.port)/v1/chat/completions" -Method Post -Headers $sp.headers -Body $body -TimeoutSec $timeout
        $sw.Stop(); $t = $r.timings
        $utilOut = Stop-UtilSampler $samp; $samp = $null
        $gu = Get-UtilTailMean $utilOut -Tail 10
        $cu = Get-UtilTailMean $utilOut -Tail 10 -Cpu
        Write-Host "ncmoe=$N deep(rounds=$rounds): prompt=$($t.prompt_n)t gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s wall=$([math]::Round($sw.Elapsed.TotalSeconds,1))s gpu_util=$gu cpu_util=$cu"
      } catch {
        $sw.Stop(); if ($samp) { Stop-UtilSampler $samp | Out-Null; $samp = $null }
        Write-Host "ncmoe=$N deep ERROR: $($_.Exception.Message)"
      }
    }
    Write-Host "ncmoe=$N after: $(Get-Vram -GpuId $GpuId)"
    Stop-LlamaServer $sp; $sp = $null
    Start-Sleep -Seconds 3
  } catch {
    Write-Host "ncmoe=$N ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($sp) { try { Stop-LlamaServer $sp } catch {} }
  }
}
Write-Host "`n===== UD35B ncmoe DOWN-scan done =====" -ForegroundColor Yellow
