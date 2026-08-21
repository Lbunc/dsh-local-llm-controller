param([int]$N)
$ErrorActionPreference = 'Continue'
$dir = '{llama-home}'
$h = @{ Authorization = 'Bearer ffsz1122'; 'Content-Type' = 'application/json' }
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
if (-not $ready) { Write-Output "N=$N NOT READY"; Stop-Process -Id $p.Id -Force; exit 1 }

# short ctx
$body = @{ prompt = 'Explain the water cycle in detail, step by step.'; n_predict = 64; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0 } | ConvertTo-Json
$r1 = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/completion' -Method Post -Headers $h -Body $body -TimeoutSec 60
$r2 = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/completion' -Method Post -Headers $h -Body $body -TimeoutSec 60
Write-Output "N=$N short eval: $([math]::Round($r1.timings.predicted_per_second,1))/$([math]::Round($r2.timings.predicted_per_second,1)) t/s"

# 21k context
$p4 = [System.IO.File]::ReadAllText('{work-dir}\prompt_4k.txt', [System.Text.Encoding]::UTF8)
$msgs = @()
for ($i = 1; $i -le 5; $i++) {
  $msgs += @{ role = 'user'; content = "请详细解释主题 $i，内容越详细越好。" }
  $msgs += @{ role = 'assistant'; content = "好的，主题 $i 的详细解释如下：$p4" }
}
$msgs += @{ role = 'user'; content = '请用三句话总结我们刚才的对话内容。' }
$cb = @{ model = 'qwen35'; messages = $msgs; max_tokens = 64; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0 } | ConvertTo-Json -Depth 6
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$r3 = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $cb -TimeoutSec 140
$sw.Stop()
Write-Output "N=$N @21k ctx: prompt=$($r3.usage.prompt_tokens)t eval=$([math]::Round($r3.timings.predicted_per_second,1))/s wall=$([math]::Round($sw.Elapsed.TotalSeconds,1))s"
$vram = (nvidia-smi --query-gpu=memory.used --format=csv,noheader)
Write-Output "N=$N vram=${vram}MiB"
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Write-Output "N=$N done"
