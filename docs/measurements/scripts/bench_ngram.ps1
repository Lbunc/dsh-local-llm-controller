param([string]$Spec = 'ngram-simple')
$ErrorActionPreference = 'Continue'
$dir = 'F:\llama-b10488-bin-win-cuda-13.3-x64'
$h = @{ Authorization = 'Bearer ffsz1122'; 'Content-Type' = 'application/json' }
$p4 = [System.IO.File]::ReadAllText('D:\DSH\WORK1\llama.cpp\data\prompt_4k.txt', [System.Text.Encoding]::UTF8)
$logDir = 'D:\DSH\WORK1\llama.cpp\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Get-Vram {
  $d = -1; $s = -1
  try { $c1 = Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop; $d = [math]::Round(($c1.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0) } catch { }
  try { $c2 = Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop; $s = [math]::Round(($c2.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0) } catch { }
  return "ded=$d shared=$s"
}

$tag = $Spec -replace '[^a-z0-9]', '_'
$argsList = @('-m', '.\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf',
  '-a', 'qwen35', '--port', '21113', '--host', '127.0.0.1', '--api-key', 'ffsz1122',
  '-ngl', '99', '-c', '32768', '-fa', 'on',
  '--cache-type-k', 'q8_0', '--cache-type-v', 'q8_0',
  '-ncmoe', '20', '-t', '20', '-tb', '20', '-np', '1',
  '--reasoning-budget', '2048',
  '--temp', '1.0', '--top-k', '20', '--top-p', '0.95', '--min-p', '0.0',
  '--metrics', '--slots')
$argsList += '--spec-type', $Spec
if ($Spec -eq 'ngram-simple') { $argsList += '--spec-ngram-simple-size-n', '4', '--spec-ngram-simple-size-m', '3', '--spec-ngram-simple-min-hits', '1' }
if ($Spec -eq 'ngram-mod') { $argsList += '--spec-ngram-mod-n-min', '1', '--spec-ngram-mod-n-max', '3', '--spec-ngram-mod-n-match', '24' }

$p = Start-Process -FilePath "$dir\llama-server.exe" -ArgumentList $argsList `
  -WindowStyle Hidden -PassThru -WorkingDirectory $dir `
  -RedirectStandardOutput "$logDir\spec_$tag.out.log" -RedirectStandardError "$logDir\spec_$tag.err.log"
$ready = $false
for ($i = 0; $i -lt 80; $i++) {
  Start-Sleep -Seconds 3
  try { Invoke-RestMethod -Uri 'http://127.0.0.1:21113/props' -Headers $h -TimeoutSec 3 | Out-Null; $ready = $true; break } catch { }
}
if (-not $ready) {
  Write-Output "SPEC=$Spec SERVER NOT READY"
  Get-Content "$logDir\spec_$tag.err.log" -ErrorAction SilentlyContinue | Select-Object -Last 6
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  exit 1
}
Write-Output "SPEC=$Spec idle: $(Get-Vram)"

$shorts = @()
for ($i = 1; $i -le 3; $i++) {
  $body = @{ prompt = 'Explain the water cycle in detail, step by step.'; n_predict = 200; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0 } | ConvertTo-Json
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/completion' -Method Post -Headers $h -Body $body -TimeoutSec 120
  $shorts += [math]::Round($r.timings.predicted_per_second, 1)
  Start-Sleep -Milliseconds 400
}
Write-Output "SPEC=$Spec short: $($shorts -join ' / ') t/s"

$msgs = @()
for ($i = 1; $i -le 5; $i++) {
  $msgs += @{ role = 'user'; content = "Please provide a detailed explanation of topic number $i, covering background, history, current state and future outlook. Write as much detail as possible." }
  $msgs += @{ role = 'assistant'; content = "Here is my detailed explanation of topic $i : $p4" }
}
$msgs += @{ role = 'user'; content = 'Based on all the discussions above, write a brief conclusion paragraph of 100 words.' }
$body = @{ model = 'qwen35'; messages = $msgs; max_tokens = 256; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0; reasoning_effort = 'high' } | ConvertTo-Json -Depth 6
$r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $body -TimeoutSec 300
$t = $r.timings
Write-Output "SPEC=$Spec deep: prompt=$($t.prompt_n)t gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s"

try {
  $m = Invoke-WebRequest -Uri 'http://127.0.0.1:21113/metrics' -Headers $h -TimeoutSec 5 -UseBasicParsing
  $m.Content -split "`n" | Where-Object { $_ -match 'spec_decode_(num_draft_tokens|num_accepted_tokens|num_drafts)_total \d' } | ForEach-Object { Write-Output "SPEC=$Spec metric: $_" }
} catch { }
Write-Output "SPEC=$Spec after: $(Get-Vram)"
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Write-Output "SPEC=$Spec done"
