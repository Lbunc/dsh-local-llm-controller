$ErrorActionPreference = 'Continue'
$dir = '{llama-home}'
$h = @{ Authorization = 'Bearer ffsz1122'; 'Content-Type' = 'application/json' }
$body = @{ prompt = 'Explain the water cycle in detail, step by step.'; n_predict = 64; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0 } | ConvertTo-Json

foreach ($N in 16, 18, 20, 22, 24, 26) {
  Write-Output "===== ncmoe=$N ====="
  $argsList = @('-m', '.\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf',
    '-a', 'qwen35', '--port', '21113', '--host', '127.0.0.1', '--api-key', 'ffsz1122',
    '-ngl', '99', '-c', '32768', '-fa', 'on',
    '--cache-type-k', 'q8_0', '--cache-type-v', 'q8_0',
    '-ncmoe', "$N", '-t', '20', '-tb', '20', '-np', '1',
    '--temp', '1.0', '--top-k', '20', '--top-p', '0.95', '--min-p', '0.0',
    '--metrics', '--slots')
  $p = Start-Process -FilePath "$dir\llama-server.exe" -ArgumentList $argsList `
    -WindowStyle Hidden -PassThru -WorkingDirectory $dir
  $ready = $false
  for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Seconds 3
    try { Invoke-RestMethod -Uri 'http://127.0.0.1:21113/props' -Headers $h -TimeoutSec 3 | Out-Null; $ready = $true; break } catch { }
  }
  if (-not $ready) {
    Write-Output "N=$N NOT READY - skipping"
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    continue
  }
  $e1 = 0; $e2 = 0
  try {
    $r1 = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/completion' -Method Post -Headers $h -Body $body -TimeoutSec 60
    $r2 = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/completion' -Method Post -Headers $h -Body $body -TimeoutSec 60
    $e1 = [math]::Round($r1.timings.predicted_per_second, 1)
    $e2 = [math]::Round($r2.timings.predicted_per_second, 1)
  } catch { Write-Output "measure failed: $($_.Exception.Message)" }
  $vram = (nvidia-smi --query-gpu=memory.used --format=csv,noheader)
  $shared = 0
  try {
    Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop | ForEach-Object {
      $_.CounterSamples | Where-Object { $_.Path -match 'a4e5' } | ForEach-Object { $shared = [math]::Round($_.CookedValue / 1MB, 1) }
    }
  } catch { }
  Write-Output "N=$N eval=${e1}/${e2} t/s vram=${vram}MiB shared=${shared}MB"
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
}
Write-Output '===== scan done ====='
