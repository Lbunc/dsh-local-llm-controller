param([int]$C = 131072, [int]$N = 24)
$ErrorActionPreference = 'Continue'
$dir = '{llama-home}'
$h = @{ Authorization = 'Bearer ffsz1122'; 'Content-Type' = 'application/json' }
$p4 = [System.IO.File]::ReadAllText('{work-dir}\llama.cpp\data\prompt_4k.txt', [System.Text.Encoding]::UTF8)
$bigImg = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes('{work-dir}\llama.cpp\picture\sample_photo.jpg'))

function Get-Vram {
  $d = -1; $s = -1
  try { $c1 = Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop; $d = [math]::Round(($c1.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0) } catch { }
  try { $c2 = Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop; $s = [math]::Round(($c2.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0) } catch { }
  return "ded=$d shared=$s"
}

$budget = [math]::Floor($C / 2)
$argsList = @('-m', '.\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf',
  '--mmproj', '.\qwen3.6-35B-A3B\mmproj-Qwen3.6-35B-A3B-Uncensored-f16.gguf',
  '-a', 'qwen35', '--port', '21113', '--host', '127.0.0.1', '--api-key', 'ffsz1122',
  '-ngl', '99', '-c', "$C", '-fa', 'on',
  '--cache-type-k', 'q8_0', '--cache-type-v', 'q8_0',
  '-ncmoe', "$N", '-t', '20', '-tb', '20', '-np', '1',
  '--reasoning-budget', "$budget",
  '--temp', '1.0', '--top-k', '20', '--top-p', '0.95', '--min-p', '0.0',
  '--image-min-tokens', '1024', '--metrics', '--slots')
$p = Start-Process -FilePath "$dir\llama-server.exe" -ArgumentList $argsList `
  -WindowStyle Hidden -PassThru -WorkingDirectory $dir
$ready = $false
for ($i = 0; $i -lt 80; $i++) {
  Start-Sleep -Seconds 3
  try { Invoke-RestMethod -Uri 'http://127.0.0.1:21113/props' -Headers $h -TimeoutSec 3 | Out-Null; $ready = $true; break } catch { }
}
if (-not $ready) { Write-Output "N=$N C=$C SERVER NOT READY"; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; exit 1 }
Write-Output "N=$N C=$C idle: $(Get-Vram)"

$bodyImg = @{
  model = 'qwen35'
  messages = @(@{
    role = 'user'
    content = @(
      @{ type = 'text'; text = 'Describe this image briefly in one sentence.' },
      @{ type = 'image_url'; image_url = @{ url = "data:image/jpeg;base64,$bigImg" } }
    )
  })
  max_tokens = 128
  reasoning_effort = 'none'
} | ConvertTo-Json -Depth 8
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $bodyImg -TimeoutSec 300
  $t = $r.timings
  Write-Output "N=$N C=$C big: prompt=$($t.prompt_n)t promptEval=$([math]::Round($t.prompt_ms/1000,1))s eval=$([math]::Round($t.predicted_per_second,1))/s wall=$([math]::Round($sw.Elapsed.TotalSeconds,1))s"
} catch { Write-Output "N=$N C=$C big ERROR: $($_.Exception.Message)" }

$msgs = @()
$rounds = [math]::Max(2, [math]::Floor(($C - 8000) / 4500))
for ($i = 1; $i -le $rounds; $i++) {
  $msgs += @{ role = 'user'; content = "Please provide a detailed explanation of topic number $i, covering background, history, current state and future outlook. Write as much detail as possible." }
  $msgs += @{ role = 'assistant'; content = "Here is my detailed explanation of topic $i : $p4" }
}
$msgs += @{ role = 'user'; content = 'Based on all the discussions above, write a brief conclusion paragraph of 100 words.' }
$bodyDeep = @{ model = 'qwen35'; messages = $msgs; max_tokens = 128; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0; reasoning_effort = 'high' } | ConvertTo-Json -Depth 6
$timeout = [math]::Max(360, [int](($C / 600) * 1.6 + 90))
try {
  $r2 = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $bodyDeep -TimeoutSec $timeout
  $t2 = $r2.timings
  Write-Output "N=$N C=$C deep: prompt=$($t2.prompt_n)t gen=$($t2.predicted_n)t eval=$([math]::Round($t2.predicted_per_second,1))/s"
} catch { Write-Output "N=$N C=$C deep ERROR: $($_.Exception.Message)" }
Write-Output "N=$N C=$C after: $(Get-Vram)"
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Write-Output "N=$N C=$C done"
