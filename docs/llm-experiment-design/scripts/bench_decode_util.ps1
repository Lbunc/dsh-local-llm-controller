#requires -Version 7
<#
.SYNOPSIS
  decode 相四件套 + CPU 线程扫描（修正首轮四件套的采样窗口污染）。
  首轮问题：采样窗口套在"深填充"调用上，而该调用墙钟被 prefill 主导（如 prompt_ms=27398 vs
  生成 128 tokens≈1.6s）→ 测到的是 prefill 画像（GPU 87% / CPU 12%），decode 只占 5%。
  本脚本改为：**极短 prompt（~40 tokens）+ 长生成（GenTokens=1500）** → 窗口由 decode 主导。
  每点记录：t/s、GPU util（尾部均值）、CPU 总占用、llama-server 真实 cores_busy（进程 CPU 差/墙钟）、
            内核态占比、显存 ded/shared、SM 时钟、功耗。
  必要性判定门（SKILL 2.5）：存在 CPU 专家卸载（-ncmoe>0）→ 必须扫 -t。
  用法示例（spec = "ncmoe:kv:threads"）：
    -Specs @('20:q8_0:20','20:q8_0:16','20:q8_0:12','20:q8_0:8','20:q8_0:4','19:q4_0:20')
#>
param(
  [Parameter(Mandatory)][string]$ModelPath,
  [Parameter(Mandatory)][string]$LlamaDir,
  [string]$Alias='model',
  [string]$WorkDir='',       # 空 = 取 $env:DSH_WORK_DIR，否则当前目录
  [string[]]$Specs=@('20:q8_0:20'),
  [int]$Ctx=32768, [int]$Budget=2048, [int]$GenTokens=1500, [int]$GpuId=0,
  [string]$PromptText='Explain in great detail how a modern CPU pipeline works, covering fetch, decode, rename, issue, execute, and retire stages.'
)
$ErrorActionPreference='Continue'
. (Join-Path $PSScriptRoot 'start_server.ps1')
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$rows=@()

foreach($spec in $Specs){
  $p=$spec.Split(':'); $N=[int]$p[0]; $kv=$p[1]; $T=if($p.Count -gt 2){[int]$p[2]}else{20}
  Write-Host "`n########## spec=$spec  (ncmoe=$N kv=$kv threads=$T) ##########" -ForegroundColor Cyan
  $s=$null
  try{
    $s=Start-LlamaServer -ModelPath $ModelPath -Alias $Alias -LlamaDir $LlamaDir -Ngl 99 -ContextSize $Ctx `
       -CacheTypeK $kv -CacheTypeV $kv -Fa 'on' -MoeMode 'ncmoe' -Ncmoe $N `
       -ReasoningBudget $Budget -Threads $T -GpuId $GpuId -SkipHelpCheck
    $r=[ordered]@{spec=$spec;ncmoe=$N;kv=$kv;threads=$T}
    $iv=Get-Vram -GpuId $GpuId
    $r.idle_vram=$iv
    $w=Invoke-Short -server $s -NPredict 16      # warmup，弃用
    $proc=[System.Diagnostics.Process]::GetProcessById($s.p.Id)
    $samp=Start-UtilSampler -GpuId $GpuId -IntervalSec 1
    $body=@{prompt=$PromptText;n_predict=$GenTokens;temperature=1.0;top_k=20;top_p=0.95;min_p=0.0}|ConvertTo-Json
    $c0=$proc.TotalProcessorTime.TotalSeconds; $t0=Get-Date
    $resp=Invoke-RestMethod -Uri "http://127.0.0.1:$($s.port)/completion" -Method Post -Headers $s.headers -Body $body -TimeoutSec 900
    $wall=((Get-Date)-$t0).TotalSeconds
    $proc.Refresh(); $cores=($proc.TotalProcessorTime.TotalSeconds-$c0)/$wall
    $u=Stop-UtilSampler $samp; $samp=$null
    $r.tps=[math]::Round($resp.timings.predicted_per_second,1)
    $r.gen=$resp.timings.predicted_n
    $r.prompt_n=$resp.timings.prompt_n
    $r.gpu=Get-UtilTailMean $u -Tail 12
    $r.cpu_total=Get-UtilTailMean $u -Tail 12 -Cpu
    $r.cores_busy=[math]::Round($cores,2)
    $r.wall=[math]::Round($wall,1)
    $ut=(Get-Counter '\Process(llama-server)\% User Time' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
    $kt=(Get-Counter '\Process(llama-server)\% Privileged Time' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
    $r.user_pct=[math]::Round($ut,0); $r.priv_pct=[math]::Round($kt,0)
    $r.run_vram=(Get-Vram -GpuId $GpuId)
    $clk=(nvidia-smi --query-gpu=clocks.sm,clocks.max.sm,power.draw,power.limit,temperature.gpu --format=csv,noheader,nounits) -split ','
    $r.sm_clk=$clk[0].Trim(); $r.sm_max=$clk[1].Trim(); $r.power=$clk[2].Trim(); $r.plimit=$clk[3].Trim(); $r.temp=$clk[4].Trim()
    $ncpu=[Environment]::ProcessorCount
    Write-Host ("[spec=$spec] prompt={0}t gen={1}t  {2} t/s | GPU={3}%  CPU_total={4}%  cores_busy={5}/{6}  user={7}% priv={8}% | sm={9}/{10}MHz  pwr={11}/{12}W  {13}C | idle={14} run={15}" -f `
      $r.prompt_n,$r.gen,$r.tps,$r.gpu,$r.cpu_total,$r.cores_busy,$ncpu,$r.user_pct,$r.priv_pct,$r.sm_clk,$r.sm_max,$r.power,$r.plimit,$r.temp,$r.idle_vram,$r.run_vram)
    $rows += [pscustomobject]$r
  }catch{ Write-Host "[spec=$spec] ERROR: $($_.Exception.Message)" -ForegroundColor Red }
  finally{ if($samp){try{Stop-UtilSampler $samp|Out-Null}catch{}}; Stop-LlamaServer $s; Start-Sleep 2 }
}

Write-Host "`n================ DECODE-PHASE UTIL SUMMARY ================" -ForegroundColor Yellow
Write-Host ("{0,-12} {1,-6} {2,-8} {3,-9} {4,-6} {5,-11} {6,-9} {7,-10}" -f 'spec','t/s','GPU%','CPU_total%','cores','user/priv','sm_clk','power')
Write-Host ('-'*80)
foreach($r in $rows){
  Write-Host ("{0,-12} {1,-6} {2,-8} {3,-9} {4,-6} {5,-11} {6,-9} {7,-10}" -f $r.spec,$r.tps,$r.gpu,$r.cpu_total,$r.cores_busy,"$($r.user_pct)/$($r.priv_pct)","$($r.sm_clk)",$r.power)
}
$rows | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $WorkDir "data\decode_util_$Alias.json") -Encoding UTF8
Write-Host "`n[done] decode-phase util scan complete" -ForegroundColor Yellow
