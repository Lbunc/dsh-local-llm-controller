$ErrorActionPreference = 'Continue'
$h = @{ Authorization = 'Bearer ffsz1122'; 'Content-Type' = 'application/json' }
$p4 = [System.IO.File]::ReadAllText('{work-dir}\prompt_4k.txt', [System.Text.Encoding]::UTF8)

function Get-Vram {
  $d = -1; $s = -1
  try { $c1 = Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop; $d = [math]::Round(($c1.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0) } catch { }
  try { $c2 = Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop; $s = [math]::Round(($c2.CounterSamples | Where-Object { $_.CookedValue -gt 0 } | Select-Object -First 1).CookedValue / 1MB, 0) } catch { }
  return "ded=$d shared=$s"
}

Write-Output "idle: $(Get-Vram)"

for ($i = 1; $i -le 2; $i++) {
  $body = @{ prompt = 'Explain the water cycle in detail, step by step.'; n_predict = 96; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0 } | ConvertTo-Json
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/completion' -Method Post -Headers $h -Body $body -TimeoutSec 120
  Write-Output "short#$($i): gen=$($r.timings.predicted_n)t eval=$([math]::Round($r.timings.predicted_per_second,1))/s"
}

$rounds = 9
$msgs = @()
for ($i = 1; $i -le $rounds; $i++) {
  $msgs += @{ role = 'user'; content = "Please provide a detailed explanation of topic number $i, covering background, history, current state and future outlook. Write as much detail as possible." }
  $msgs += @{ role = 'assistant'; content = "Here is my detailed explanation of topic $i : $p4" }
}
$msgs += @{ role = 'user'; content = 'Based on all the discussions above, write a brief conclusion paragraph of 100 words.' }
$body = @{ model = 'qwen35'; messages = $msgs; max_tokens = 128; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0; reasoning_effort = 'high' } | ConvertTo-Json -Depth 6
$r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $body -TimeoutSec 300
$t = $r.timings
Write-Output "deep: prompt=$($t.prompt_n)t gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s"

# real-world: relative-riddle question with thinking on
$q = '爸爸的妈妈和我的姐姐结婚了，我的女儿应该叫姐姐的儿子什么？请仔细推理。'
$body = @{ model = 'qwen35'; messages = @(@{ role = 'user'; content = $q }); max_tokens = 4000; temperature = 1.0; top_k = 20; top_p = 0.95; min_p = 0.0; reasoning_effort = 'high' } | ConvertTo-Json -Depth 6
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $body -TimeoutSec 300
$sw.Stop()
$m = $r.choices[0].message
Write-Output "riddle: total=$($r.usage.completion_tokens)t think=$([bool]$m.reasoning_content) content_len=$($m.content.Length) wall=$([math]::Round($sw.Elapsed.TotalSeconds,1))s"

Write-Output "after: $(Get-Vram)"
Write-Output '########## final verify done ##########'
