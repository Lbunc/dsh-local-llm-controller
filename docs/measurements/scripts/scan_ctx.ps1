param(
  [int]$N = 22,
  [int]$Rounds = 0,
  [int[]]$Ctxs = @(65536, 98304, 131072, 147456)
)
$ErrorActionPreference = 'Continue'
$dir = '{llama-home}'
$h = @{ Authorization = 'Bearer ffsz1122'; 'Content-Type' = 'application/json' }
$p4 = [System.IO.File]::ReadAllText('{work-dir}\prompt_4k.txt', [System.Text.Encoding]::UTF8)

function Get-Vram {
  $d = -1; $s = -1
  try {
    $c1 = Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop
    $d = [math]::Round(($c1.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0)
  } catch { $d = -1 }
  try {
    $c2 = Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop
    $s = [math]::Round(($c2.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0)
  } catch { $s = -1 }
  return "ded=$d shared=$s"
}

function Start-CtxServer([int]$C) {
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

function Test-Short {
  $body = @{ prompt = 'Explain the water cycle in detail, step by step.'; n_predict = 96; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0 } | ConvertTo-Json
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/completion' -Method Post -Headers $h -Body $body -TimeoutSec 120
  $t = $r.timings
  return "short: gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s"
}

function Test-Deep([int]$C) {
  $rounds = $Rounds
  if ($rounds -le 0) { $rounds = [math]::Max(2, [math]::Floor(($C - 8000) / 4500)) }
  $msgs = @()
  for ($i = 1; $i -le $rounds; $i++) {
    $msgs += @{ role = 'user'; content = "Please provide a detailed explanation of topic number $i, covering background, history, current state and future outlook. Write as much detail as possible." }
    $msgs += @{ role = 'assistant'; content = "Here is my detailed explanation of topic $i : $p4" }
  }
  $msgs += @{ role = 'user'; content = 'Based on all the discussions above, write a brief conclusion paragraph of 100 words.' }
  $body = @{ model = 'qwen35'; messages = $msgs; max_tokens = 128; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0; reasoning_effort = 'high' } | ConvertTo-Json -Depth 6
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $timeout = [math]::Max(360, [int](($C / 600) * 1.6 + 90))
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $body -TimeoutSec $timeout
  $sw.Stop()
  $t = $r.timings
  return "deep(rounds=$rounds): prompt=$($t.prompt_n)t gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s wall=$([math]::Round($sw.Elapsed.TotalSeconds,1))s"
}

foreach ($C in $Ctxs) {
  Write-Output "########## ncmoe=$N CTX=$C budget=$([math]::Floor($C/2)) ##########"
  $res = Start-CtxServer $C
  if (-not $res) { Write-Output "C=$C SERVER NOT READY"; continue }
  Write-Output "C=$C applied_n_ctx=$($res.ctx)"
  Start-Sleep -Seconds 2
  Write-Output "C=$C idle: $(Get-Vram)"
  try { Write-Output "C=$C $(Test-Short)" } catch { Write-Output "C=$C SHORT ERROR: $($_.Exception.Message)" }
  try { Write-Output "C=$C $(Test-Deep $C)" } catch { Write-Output "C=$C DEEP ERROR: $($_.Exception.Message)" }
  Write-Output "C=$C after: $(Get-Vram)"
  Stop-Process -Id $res.p.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
}
Write-Output "########## ncmoe=$N scan done ##########"
