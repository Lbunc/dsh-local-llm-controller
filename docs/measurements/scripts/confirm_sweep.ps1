$ErrorActionPreference = 'Continue'
$dir = '{llama-home}'
$h = @{ Authorization = 'Bearer ffsz1122'; 'Content-Type' = 'application/json' }
$p4 = [System.IO.File]::ReadAllText('{work-dir}\prompt_4k.txt', [System.Text.Encoding]::UTF8)

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

function Test-Short {
  $body = @{ prompt = 'Explain the water cycle in detail, step by step.'; n_predict = 96; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0 } | ConvertTo-Json
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/completion' -Method Post -Headers $h -Body $body -TimeoutSec 120
  return [math]::Round($r.timings.predicted_per_second, 1)
}

function Test-Deep([int]$C) {
  $rounds = [math]::Max(2, [math]::Floor(($C - 8000) / 4500))
  $msgs = @()
  for ($i = 1; $i -le $rounds; $i++) {
    $msgs += @{ role = 'user'; content = "Please provide a detailed explanation of topic number $i, covering background, history, current state and future outlook. Write as much detail as possible." }
    $msgs += @{ role = 'assistant'; content = "Here is my detailed explanation of topic $i : $p4" }
  }
  $msgs += @{ role = 'user'; content = 'Based on all the discussions above, write a brief conclusion paragraph of 100 words.' }
  $body = @{ model = 'qwen35'; messages = $msgs; max_tokens = 128; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0; reasoning_effort = 'high' } | ConvertTo-Json -Depth 6
  $timeout = [math]::Max(360, [int](($C / 600) * 1.6 + 90))
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $body -TimeoutSec $timeout
  $t = $r.timings
  return "rounds=$rounds prompt=$($t.prompt_n)t gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s"
}

$points = @(
  @{ N = 20; C = 49152 },
  @{ N = 20; C = 57344 },
  @{ N = 20; C = 65536 }
)

foreach ($pt in $points) {
  $N = $pt.N; $C = $pt.C
  Write-Output "########## CONFIRM2 ncmoe=$N CTX=$C ##########"
  $res = Start-CtxServer $C $N
  if (-not $res) { Write-Output "C=$C SERVER NOT READY"; continue }
  Start-Sleep -Seconds 2
  Write-Output "C=$C idle: $(Get-Vram)"
  $s1 = Test-Short; Start-Sleep -Milliseconds 500; $s2 = Test-Short
  Write-Output "C=$C short: $s1 / $s2 t/s"
  try { Write-Output "C=$C deep#1: $(Test-Deep $C)" } catch { Write-Output "C=$C DEEP ERROR: $($_.Exception.Message)" }
  try { Write-Output "C=$C deep#2: $(Test-Deep $C)" } catch { Write-Output "C=$C DEEP ERROR: $($_.Exception.Message)" }
  Write-Output "C=$C after: $(Get-Vram)"
  Stop-Process -Id $res.p.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
}
Write-Output '########## confirm sweep done ##########'
