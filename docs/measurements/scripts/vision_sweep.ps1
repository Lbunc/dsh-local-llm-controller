$ErrorActionPreference = 'Continue'
$dir = '{llama-home}'
$h = @{ Authorization = 'Bearer ffsz1122'; 'Content-Type' = 'application/json' }
$p4 = [System.IO.File]::ReadAllText('{work-dir}\llama.cpp\data\prompt_4k.txt', [System.Text.Encoding]::UTF8)
$smallImg = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes('{work-dir}\llama.cpp\picture\test_circle.png'))
$bigImg = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes('{work-dir}\llama.cpp\picture\sample_photo.jpg'))

function Get-Vram {
  $d = -1; $s = -1
  try { $c1 = Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop; $d = [math]::Round(($c1.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0) } catch { }
  try { $c2 = Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop; $s = [math]::Round(($c2.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0) } catch { }
  return "ded=$d shared=$s"
}

function Start-VisionServer([int]$N) {
  $argsList = @('-m', '.\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf',
    '--mmproj', '.\qwen3.6-35B-A3B\mmproj-Qwen3.6-35B-A3B-Uncensored-f16.gguf',
    '-a', 'qwen35', '--port', '21113', '--host', '127.0.0.1', '--api-key', 'ffsz1122',
    '-ngl', '99', '-c', '32768', '-fa', 'on',
    '--cache-type-k', 'q8_0', '--cache-type-v', 'q8_0',
    '-ncmoe', "$N", '-t', '20', '-tb', '20', '-np', '1',
    '--reasoning-budget', '2048',
    '--temp', '1.0', '--top-k', '20', '--top-p', '0.95', '--min-p', '0.0',
    '--image-min-tokens', '1024', '--metrics', '--slots')
  $p = Start-Process -FilePath "$dir\llama-server.exe" -ArgumentList $argsList `
    -WindowStyle Hidden -PassThru -WorkingDirectory $dir
  for ($i = 0; $i -lt 80; $i++) {
    Start-Sleep -Seconds 3
    try {
      $pr = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/props' -Headers $h -TimeoutSec 3
      return @{ p = $p; ctx = $pr.default_generation_settings.n_ctx }
    } catch { }
  }
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  return $null
}

function Test-TextShort {
  $body = @{ prompt = 'Explain the water cycle in detail, step by step.'; n_predict = 96; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0 } | ConvertTo-Json
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/completion' -Method Post -Headers $h -Body $body -TimeoutSec 120
  return [math]::Round($r.timings.predicted_per_second, 1)
}

function Test-Image([string]$b64, [string]$mime, [string]$label) {
  $body = @{
    model = 'qwen35'
    messages = @(@{
      role = 'user'
      content = @(
        @{ type = 'text'; text = 'Describe this image briefly in one sentence.' },
        @{ type = 'image_url'; image_url = @{ url = "data:$mime;base64,$b64" } }
      )
    })
    max_tokens = 128
  } | ConvertTo-Json -Depth 8
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $body -TimeoutSec 300
  $sw.Stop()
  $t = $r.timings
  $content = $r.choices[0].message.content
  if ($content -is [array]) { $content = ($content | ForEach-Object { $_.text }) -join '' }
  return "${label}: prompt=$($t.prompt_n)t gen=$($t.predicted_n)t promptEval=$([math]::Round($t.prompt_ms/1000,1))s eval=$([math]::Round($t.predicted_per_second,1))/s wall=$([math]::Round($sw.Elapsed.TotalSeconds,1))s content_len=$($content.Length)"
}

function Test-DeepText {
  $msgs = @()
  for ($i = 1; $i -le 5; $i++) {
    $msgs += @{ role = 'user'; content = "Please provide a detailed explanation of topic number $i, covering background, history, current state and future outlook. Write as much detail as possible." }
    $msgs += @{ role = 'assistant'; content = "Here is my detailed explanation of topic $i : $p4" }
  }
  $msgs += @{ role = 'user'; content = 'Based on all the discussions above, write a brief conclusion paragraph of 100 words.' }
  $body = @{ model = 'qwen35'; messages = $msgs; max_tokens = 128; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0; reasoning_effort = 'high' } | ConvertTo-Json -Depth 6
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $body -TimeoutSec 300
  $t = $r.timings
  return "deepText: prompt=$($t.prompt_n)t gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s"
}

foreach ($N in 20, 22, 24) {
  Write-Output "########## VISION ncmoe=$N ##########"
  $res = Start-VisionServer $N
  if (-not $res) { Write-Output "N=$N SERVER NOT READY (crash at load?)"; continue }
  Write-Output "N=$N applied_n_ctx=$($res.ctx) idle: $(Get-Vram)"
  $s1 = Test-TextShort; Start-Sleep -Milliseconds 500; $s2 = Test-TextShort
  Write-Output "N=$N textShort: $s1 / $s2 t/s"
  try { Write-Output "N=$N $(Test-Image $smallImg 'image/png' 'small#1')" } catch { Write-Output "N=$N small#1 ERROR: $($_.Exception.Message)" }
  try { Write-Output "N=$N $(Test-Image $bigImg 'image/jpeg' 'big#1')" } catch { Write-Output "N=$N big#1 ERROR: $($_.Exception.Message)" }
  try { Write-Output "N=$N $(Test-DeepText)" } catch { Write-Output "N=$N DEEP ERROR: $($_.Exception.Message)" }
  try { Write-Output "N=$N $(Test-Image $smallImg 'image/png' 'small#2')" } catch { Write-Output "N=$N small#2 ERROR: $($_.Exception.Message)" }
  Write-Output "N=$N after: $(Get-Vram)"
  Stop-Process -Id $res.p.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
}
Write-Output '########## vision sweep done ##########'
