$ErrorActionPreference = 'Continue'
$dir = '{llama-home}'
$h = @{ Authorization = 'Bearer ffsz1122'; 'Content-Type' = 'application/json' }
$p4 = [System.IO.File]::ReadAllText('{work-dir}\prompt_4k.txt', [System.Text.Encoding]::UTF8)

function Start-Server([int]$N) {
  $argsList = @('-m', '.\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf',
    '-a', 'qwen35', '--port', '21113', '--host', '127.0.0.1', '--api-key', 'ffsz1122',
    '-ngl', '99', '-c', '32768', '-fa', 'on',
    '--cache-type-k', 'q8_0', '--cache-type-v', 'q8_0',
    '-ncmoe', "$N", '-t', '20', '-tb', '20', '-np', '1',
    '--temp', '1.0', '--top-k', '20', '--top-p', '0.95', '--min-p', '0.0',
    '--metrics', '--slots')
  $p = Start-Process -FilePath "$dir\llama-server.exe" -ArgumentList $argsList `
    -WindowStyle Hidden -PassThru -WorkingDirectory $dir
  for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Seconds 3
    try { Invoke-RestMethod -Uri 'http://127.0.0.1:21113/props' -Headers $h -TimeoutSec 3 | Out-Null; return $p } catch { }
  }
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  throw "server not ready"
}

function Chat([object[]]$msgs, [int]$maxTok) {
  $body = @{ model = 'qwen35'; messages = $msgs; max_tokens = $maxTok; temperature = 1.0;
    top_k = 20; top_p = 0.95; min_p = 0.0; reasoning_effort = 'high' } | ConvertTo-Json -Depth 6
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $r = Invoke-RestMethod -Uri 'http://127.0.0.1:21113/v1/chat/completions' -Method Post -Headers $h -Body $body -TimeoutSec 300
  $sw.Stop()
  return @{ r = $r; wall = $sw.Elapsed.TotalSeconds }
}

foreach ($N in 20, 22, 24) {
  Write-Output "########## ncmoe=$N (THINKING ON) ##########"
  $p = Start-Server $N
  try {
    # short context baseline
    $res = Chat @(@{ role = 'user'; content = 'Explain the water cycle in detail.' }) 200
    $t = $res.r.timings
    $m = $res.r.choices[0].message
    Write-Output "SHORT: gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s think=$([bool]$m.reasoning_content)"

    # build 7-round conversation (~30k tokens)
    $msgs = @()
    for ($i = 1; $i -le 7; $i++) {
      $msgs += @{ role = 'user'; content = "Please provide a detailed explanation of topic number $i, covering background, history, current state and future outlook. Write as much detail as possible." }
      $msgs += @{ role = 'assistant'; content = "Here is my detailed explanation of topic $i : $p4" }
    }
    # 26k context: 6 rounds + long essay task
    $q26 = @{ role = 'user'; content = 'Based on all the discussions above, write a comprehensive analysis essay of at least 600 words. Cover the common themes, key differences, and your overall assessment.' }
    $msgs26 = $msgs[0..($msgs.Count - 3)] + $q26
    $res = Chat $msgs26 1024
    $t = $res.r.timings
    $m = $res.r.choices[0].message
    Write-Output "CTX26K: prompt=$($t.prompt_n)t gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s think=$([bool]$m.reasoning_content) content_len=$($m.content.Length) wall=$([math]::Round($res.wall,1))s"

    # ~30.8k context: 7 rounds + long follow-up
    $q30 = @{ role = 'user'; content = 'Now write a detailed follow-up analysis of at least 500 words, focusing on practical applications and real-world implications.' }
    $msgs30 = $msgs + $q30
    $res = Chat $msgs30 1024
    $t = $res.r.timings
    $m = $res.r.choices[0].message
    Write-Output "CTX30K: prompt=$($t.prompt_n)t gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s think=$([bool]$m.reasoning_content) content_len=$($m.content.Length) wall=$([math]::Round($res.wall,1))s"

    # near-limit: 7 rounds + short conclusion
    $q31 = @{ role = 'user'; content = 'Add a brief conclusion paragraph.' }
    $msgs31 = $msgs + $q31
    $res = Chat $msgs31 400
    $t = $res.r.timings
    $m = $res.r.choices[0].message
    Write-Output "CTX31K: prompt=$($t.prompt_n)t gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s think=$([bool]$m.reasoning_content) content_len=$($m.content.Length) wall=$([math]::Round($res.wall,1))s"
  } catch {
    Write-Output "ncmoe=$N ERROR: $($_.Exception.Message)"
  }
  $vram = (nvidia-smi --query-gpu=memory.used --format=csv,noheader)
  Write-Output "VRAM: ${vram}MiB"
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 5
}
Write-Output '########## benchmark done ##########'
