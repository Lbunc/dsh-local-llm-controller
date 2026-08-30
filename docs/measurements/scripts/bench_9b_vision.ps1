param([int]$C = 32768)
$ErrorActionPreference = 'Continue'
$dir = 'F:\llama-b10488-bin-win-cuda-13.3-x64'
$h = @{ Authorization = 'Bearer ffsz1122'; 'Content-Type' = 'application/json' }
$p4 = [System.IO.File]::ReadAllText('D:\DSH\WORK1\llama.cpp\data\prompt_4k.txt', [System.Text.Encoding]::UTF8)
$smallImg = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes('D:\DSH\WORK1\llama.cpp\picture\test_circle.png'))
$bigImg = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes('D:\DSH\WORK1\llama.cpp\picture\DSC_9125.jpg'))
$logOut = "D:\DSH\WORK1\llama.cpp\logs\9bvis_$C.out.log"
$logErr = "D:\DSH\WORK1\llama.cpp\logs\9bvis_$C.err.log"
Remove-Item $logOut, $logErr -Force -ErrorAction SilentlyContinue

function Get-Vram {
  $d = -1; $s = -1
  try { $c1 = Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop; $d = [math]::Round(($c1.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0) } catch { }
  try { $c2 = Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop; $s = [math]::Round(($c2.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0) } catch { }
  return "ded=$d shared=$s"
}

$argsList = @('-m', '.\qwen3.5-9B\Qwen3.5-9B-Q6_K.gguf',
  '--mmproj', '.\qwen3.5-9B\mmproj-Qwen3.5-9B-Uncensored-BF16.gguf',
  '-a', 'qwen9b', '--port', '21113', '--host', '127.0.0.1', '--api-key', 'ffsz1122',
  '-ngl', '99', '-c', "$C", '-fa', 'auto', '-t', '20', '-tb', '20', '-np', '1',
  '--temp', '0.8', '--top-k', '40', '--top-p', '0.95', '--min-p', '0.05',
  '--spec-type', 'draft-mtp', '--spec-draft-n-max', '3',
  '--image-min-tokens', '1024', '--metrics', '--slots')
$p = Start-Process -FilePath "$dir\llama-server.exe" -ArgumentList $argsList `
  -WindowStyle Hidden -PassThru -WorkingDirectory $dir `
  -RedirectStandardOutput $logOut -RedirectStandardError $logErr
$ready = $false
for ($i = 0; $i -lt 50; $i++) {
  Start-Sleep -Seconds 2
  try { Invoke-RestMethod -Uri 'http://127.0.0.1:21113/props' -Headers $h -TimeoutSec 3 | Out-Null; $ready = $true; break } catch { }
}
if (-not $ready) {
  Write-Output "VIS C=$C NOT READY"
  Get-Content $logErr -ErrorAction SilentlyContinue | Select-Object -Last 6 | ForEach-Object { Write-Output "  $_" }
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  exit 1
}
Write-Output "VIS C=$C ready idle: $(Get-Vram)"

$shorts = @()
for ($i = 1; $i -le 2; $i++) {
  $body = @{ prompt = 'Explain the water cycle in detail, step by step.'; n_predict = 200; temperature = 0.8; top_k = 40; top_p = 0.95; min_p = 0.0 } | ConvertTo-Json
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/completion' -Method Post -Headers $h -Body $body -TimeoutSec 120
  $shorts += [math]::Round($r.timings.predicted_per_second, 1)
  Start-Sleep -Milliseconds 400
}
Write-Output "VIS C=$C short: $($shorts -join ' / ') t/s"

function Test-Image([string]$b64, [string]$mime, [string]$label) {
  $body = @{
    model = 'qwen9b'
    messages = @(@{
      role = 'user'
      content = @(
        @{ type = 'text'; text = 'Describe this image briefly in one sentence.' },
        @{ type = 'image_url'; image_url = @{ url = "data:$mime;base64,$b64" } }
      )
    })
    max_tokens = 128
    reasoning_effort = 'none'
  } | ConvertTo-Json -Depth 8
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $body -TimeoutSec 300
  $sw.Stop()
  $t = $r.timings
  $content = $r.choices[0].message.content
  if ($content -is [array]) { $content = ($content | ForEach-Object { $_.text }) -join '' }
  return "${label}: prompt=$($t.prompt_n)t promptEval=$([math]::Round($t.prompt_ms/1000,1))s eval=$([math]::Round($t.predicted_per_second,1))/s wall=$([math]::Round($sw.Elapsed.TotalSeconds,1))s content_len=$($content.Length)"
}

try { Write-Output "VIS C=$C $(Test-Image $smallImg 'image/png' 'small')" } catch { Write-Output "VIS C=$C small ERROR: $($_.Exception.Message)" }
try { Write-Output "VIS C=$C $(Test-Image $bigImg 'image/jpeg' 'big')" } catch { Write-Output "VIS C=$C big ERROR: $($_.Exception.Message)" }

$msgs = @()
$rounds = [math]::Max(2, [math]::Floor(($C - 8000) / 4500))
for ($i = 1; $i -le $rounds; $i++) {
  $msgs += @{ role = 'user'; content = "Please provide a detailed explanation of topic number $i, covering background, history, current state and future outlook. Write as much detail as possible." }
  $msgs += @{ role = 'assistant'; content = "Here is my detailed explanation of topic $i : $p4" }
}
$msgs += @{ role = 'user'; content = 'Based on all the discussions above, write a brief conclusion paragraph of 100 words.' }
$body = @{ model = 'qwen9b'; messages = $msgs; max_tokens = 128; temperature = 0.8; top_k = 40; top_p = 0.95; min_p = 0.05; reasoning_effort = 'high' } | ConvertTo-Json -Depth 6
try {
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $body -TimeoutSec 300
  $t = $r.timings
  Write-Output "VIS C=$C deep: prompt=$($t.prompt_n)t gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s"
} catch { Write-Output "VIS C=$C deep ERROR: $($_.Exception.Message)" }

try {
  $m = Invoke-WebRequest -Uri 'http://127.0.0.1:21113/metrics' -Headers $h -TimeoutSec 5 -UseBasicParsing
  $draft = ($m.Content -split "`n" | Where-Object { $_ -match 'spec_decode_num_draft_tokens_total \d' } | Select-Object -First 1) -replace '.* (\d+)$', '$1'
  $acc = ($m.Content -split "`n" | Where-Object { $_ -match 'spec_decode_num_accepted_tokens_total \d' } | Select-Object -First 1) -replace '.* (\d+)$', '$1'
  $rate = if ([int]$draft -gt 0) { [math]::Round([int]$acc / [int]$draft * 100, 1) } else { 0 }
  Write-Output "VIS C=$C spec: draft=$draft accepted=$acc accept_rate=$rate%"
} catch { Write-Output "VIS C=$C metrics err" }
Write-Output "VIS C=$C after: $(Get-Vram)"
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Write-Output "VIS C=$C done"
