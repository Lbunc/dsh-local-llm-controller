#requires -Version 7
# 192K deep-fill comparison: ncmoe 18/19/20 (q4_0 KV). Fill to ~C-8000 then steady-state eval t/s.
# Verifies "larger -ncmoe => higher context ceiling" (more experts on CPU frees VRAM for KV).
param(
  [string]$ModelPath='F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-UD-IQ4_NL.gguf',
  [int]$Ctx = 196608  # 192K
)
$ErrorActionPreference='Continue'
. 'D:\DSH\WORK1\llama.cpp\scripts\start_server.ps1'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$p4 = [System.IO.File]::ReadAllText('D:\DSH\WORK1\llama.cpp\data\prompt_4k.txt',[System.Text.Encoding]::UTF8)
$rounds = [math]::Max(2, [math]::Floor(($Ctx - 8000) / 4500))
Write-Host "===== 192K deep-fill ncmoe compare ctx=$Ctx rounds=$rounds =====" -ForegroundColor Yellow
foreach($N in 18,19,20){
  Write-Host "`n########## ncmoe=$N ##########" -ForegroundColor Cyan
  $s=$null
  try{
    $s=Start-LlamaServer -ModelPath $ModelPath -Alias 'ud35b' -LlamaDir 'F:\llama-b10488-bin-win-cuda-13.3-x64' -Ngl 99 -ContextSize $Ctx -CacheTypeK 'q4_0' -CacheTypeV 'q4_0' -Fa 'on' -MoeMode 'ncmoe' -Ncmoe $N -ReasoningBudget 2048 -Threads 20 -SkipHelpCheck
    Write-Host "idle: $(Get-Vram) cpu=$(Get-CpuUtil)"
    $msgs=@()
    for($i=1;$i-le$rounds;$i++){ $msgs+=@{role='user';content="Please provide a detailed explanation of topic number $i, covering background, history, current state and future outlook. Write as much detail as possible."}; $msgs+=@{role='assistant';content="Here is my detailed explanation of topic $i : $p4"} }
    $msgs+=@{role='user';content='Based on all the discussions above, write a brief conclusion paragraph of 100 words.'}
    $body=@{model='ud35b';messages=$msgs;max_tokens=128;temperature=1.0;top_k=20;top_p=0.95;min_p=0.0}|ConvertTo-Json -Depth 6
    $samp=Start-UtilSampler -GpuId 0 -IntervalSec 1
    $sw=[System.Diagnostics.Stopwatch]::StartNew()
    $timeout=[math]::Max(600,[int](($Ctx/600)*1.6+90))
    $r=Invoke-RestMethod -Uri "http://127.0.0.1:55555/v1/chat/completions" -Method Post -Headers $s.headers -Body $body -TimeoutSec $timeout
    $sw.Stop(); $t=$r.timings
    $utilOut=Stop-UtilSampler $samp
    $gu=Get-UtilTailMean $utilOut -Tail 10; $cu=Get-UtilTailMean $utilOut -Tail 10 -Cpu
    Write-Host "ncmoe=$N deep: prompt=$($t.prompt_n)t gen=$($t.predicted_n)t eval=$([math]::Round($t.predicted_per_second,1))/s wall=$([math]::Round($sw.Elapsed.TotalSeconds,1))s gpu_util=$gu cpu_util=$cu after: $(Get-Vram)"
  }catch{Write-Host "ncmoe=$N ERROR: $($_.Exception.Message)"}
  finally{Stop-LlamaServer $s; Start-Sleep 3}
}
Write-Host "`n===== done =====" -ForegroundColor Yellow
