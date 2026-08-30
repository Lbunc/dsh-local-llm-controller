#requires -Version 7
# UD-35B(-ncmoe 18) context-limit scan. KV-type parameterized (q8_0 / q4_0).
# Judge via shared-signal (baseline ~150MB) + t/s. Model arch qwen35moe, 40 layers, 10 KV layers.
param(
  [string]$ModelPath='F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-UD-IQ4_NL.gguf',
  [string]$LlamaDir='F:\llama-b10488-bin-win-cuda-13.3-x64',
  [string]$Contexts='32768,49152,65536,81920,98304,114688,131072',
  [string]$CacheTypeK='q8_0', [string]$CacheTypeV='q8_0',
  [int]$Ncmoe=18, [int]$Budget=2048, [int]$GpuId=0
)
$ErrorActionPreference='Continue'
. 'D:\DSH\WORK1\llama.cpp\scripts\start_server.ps1'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
Write-Host "===== UD35B ctx scan kv=$CacheTypeK ncmoe=$Ncmoe ctxs=$Contexts =====" -ForegroundColor Yellow
foreach($C in ($Contexts.Split(',')|ForEach-Object{[int]$_})){
  Write-Host "================ ctx=$C ================"
  $s=$null
  try{
    $s=Start-LlamaServer -ModelPath $ModelPath -Alias 'ud35b' -LlamaDir $LlamaDir -Ngl 99 -ContextSize $C -CacheTypeK $CacheTypeK -CacheTypeV $CacheTypeV -Fa 'on' -MoeMode 'ncmoe' -Ncmoe $Ncmoe -ReasoningBudget $Budget -Threads 20 -SkipHelpCheck
    $vid=Get-Vram -GpuId $GpuId
    $w=Invoke-Short -server $s -NPredict 16
    $t=@(); for($r=1;$r-le 3;$r++){ $m=Invoke-Short -server $s -NPredict 160; $t+=$m.tps; Start-Sleep -Milliseconds 150 }
    $avg=[math]::Round(($t|Measure-Object -Average).Average,1)
    $vr=Get-Vram -GpuId $GpuId
    Write-Host "[ctx=$C] idle_vram=$vid  short_tps=[$($t-join'/')] avg=$avg  run_vram=$vr"
    if($vr -match 'shared=(\d+)'){ $sh=[int]$matches[1]; if($sh -gt 300){ Write-Host "  -> ⚠️ shared=$sh MB (溢出信号)" } else { Write-Host "  -> shared=$sh MB OK" } }
  }catch{Write-Host "[ctx=$C] ERROR: $($_.Exception.Message)"}
  finally{Stop-LlamaServer $s; Start-Sleep 1}
}
Write-Host "[done] UD35B ctx scan ($CacheTypeK) complete"
