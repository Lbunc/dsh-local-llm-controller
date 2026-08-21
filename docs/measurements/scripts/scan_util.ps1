$ErrorActionPreference = 'Continue'
$dir = '{llama-home}'
$h = @{ Authorization = 'Bearer ffsz1122'; 'Content-Type' = 'application/json' }
$p4 = [System.IO.File]::ReadAllText('{work-dir}\prompt_4k.txt', [System.Text.Encoding]::UTF8)
$sampDir = '{work-dir}'

function Get-Vram {
  $d = -1; $s = -1
  try { $c1 = Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop; $d = [math]::Round(($c1.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0) } catch { }
  try { $c2 = Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop; $s = [math]::Round(($c2.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0) } catch { }
  return "ded=$d shared=$s"
}

function Start-CtxServer([int]$C, [int]$N) {
  $budget = [math]::Floor($C / 2)
  $argsList = @('-m', '.\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf',
    '-a', 'qwen35', '--port', '21113', '--host', '127.0.0.1', '--api-key', 'ffsz1122',
    '-ngl', '99', '-c', "$C", '-fa', 'on',
    '--cache-type-k', 'q8_0', '--cache-type-v', 'q8_0',
    '-ncmoe', "$N", '-t', '20', '-tb', '20', '-np', '1',
    '--reasoning-budget', "$budget",
    '--temp', '1.0', '--top-k', '20', '--top-p', '0.95', '--min-p', '0.0',
    '--metrics', '--slots')
  $p = Start-Process -FilePath "$dir\llama-server.exe" -ArgumentList $argsList `
    -WindowStyle Hidden -PassThru -WorkingDirectory $dir
  for ($i = 0; $i -lt 70; $i++) {
    Start-Sleep -Seconds 3
    try {
      $pr = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/props' -Headers $h -TimeoutSec 3
      return @{ p = $p; ctx = $pr.default_generation_settings.n_ctx }
    } catch { }
  }
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  return $null
}

function Get-GpuUtilAvg([int]$genSec) {
  $samples = Get-Content "$sampDir\samp_util.txt" -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\d+$' }
  if (-not $samples) { return 'n/a' }
  $n = [math]::Min($samples.Count, $genSec + 3)
  $tail = $samples | Select-Object -Last $n
  $vals = $tail | ForEach-Object { [int]$_ }
  $avg = ($vals | Measure-Object -Average).Average
  return [math]::Round($avg, 0)
}

function ChatDeep([int]$rounds, [int]$maxTok) {
  $msgs = @()
  for ($i = 1; $i -le $rounds; $i++) {
    $msgs += @{ role = 'user'; content = "Please provide a detailed explanation of topic number $i, covering background, history, current state and future outlook. Write as much detail as possible." }
    $msgs += @{ role = 'assistant'; content = "Here is my detailed explanation of topic $i : $p4" }
  }
  $msgs += @{ role = 'user'; content = 'Based on all the discussions above, write a brief conclusion paragraph of 100 words.' }
  $body = @{ model = 'qwen35'; messages = $msgs; max_tokens = $maxTok; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0; reasoning_effort = 'high' } | ConvertTo-Json -Depth 6
  $timeout = 600
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $body -TimeoutSec $timeout
  return $r
}

Write-Output "########## phase1: fill-speed curve + GPU util (ncmoe=22 C=131072) ##########"
$res = Start-CtxServer 131072 22
if (-not $res) { Write-Output "SERVER NOT READY"; exit 1 }
Write-Output "applied_n_ctx=$($res.ctx) idle: $(Get-Vram)"

foreach ($fill in 60000, 90000, 120000) {
  $rounds = [math]::Max(2, [math]::Floor($fill / 4500))
  $samp = Start-Process -FilePath 'nvidia-smi' `
    -ArgumentList @('--query-gpu=utilization.gpu', '--format=csv,noheader,nounits', '-l', '1') `
    -RedirectStandardOutput "$sampDir\samp_util.txt" -WindowStyle Hidden -PassThru
  try {
    $r = ChatDeep $rounds 256
    $t = $r.timings
    $genSec = [math]::Ceiling($t.predicted_ms / 1000) + 1
    $util = Get-GpuUtilAvg $genSec
    Write-Output "fill=$fill rounds=$rounds prompt=$($t.prompt_n)t gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s gpu_util=$util% wall_gen=$([math]::Round($t.predicted_ms/1000,1))s"
  } catch {
    Write-Output "fill=$fill ERROR: $($_.Exception.Message)"
  }
  Stop-Process -Id $samp.Id -Force -ErrorAction SilentlyContinue
}
Stop-Process -Id $res.p.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Write-Output "########## phase2: hard-cliff probes (idle shared) ##########"
foreach ($C in 163840, 180224) {
  $r2 = Start-CtxServer $C 22
  if (-not $r2) { Write-Output "C=$C SERVER NOT READY"; continue }
  Start-Sleep -Seconds 2
  Write-Output "C=$C applied_n_ctx=$($r2.ctx) idle: $(Get-Vram)"
  try {
    $body = @{ prompt = 'Explain the water cycle in detail, step by step.'; n_predict = 96; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0 } | ConvertTo-Json
    $rs = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/completion' -Method Post -Headers $h -Body $body -TimeoutSec 120
    Write-Output "C=$C short: gen=$($rs.timings.predicted_n)t eval=$([math]::Round($rs.timings.predicted_per_second,1))/s"
  } catch { Write-Output "C=$C SHORT ERROR: $($_.Exception.Message)" }
  Stop-Process -Id $r2.p.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
}
Write-Output '########## util scan done ##########'
