#requires -Version 7
<#
.SYNOPSIS
  High-pressure exact computation / multi-hop chain questions to differentiate STRONG models
  (27B-Q3 dense vs 35B-IQ4_NL MoE -ncmoe20). Each q has a precise numeric/symbolic answer
  that accumulates error across many steps -> reveals which model is more robust.
  Same config as before. Each q run 3x. Only variable = model.
#>
param(
  [string]$LlamaDir = 'F:\llama-b10488-bin-win-cuda-13.3-x64',
  [int]$Ctx = 32768, [int]$Budget = 2048, [int]$MaxTokens = 8192, [int]$Repeats = 3,
  [int]$Ncmoe35B = 20
)
$ErrorActionPreference = 'Continue'
. 'D:\DSH\WORK1\llama.cpp\scripts\start_server.ps1'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Model27B = 'F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.8-27B\Qwen3.8-27B-UD-IQ3_XXS.gguf'
$Model35B = 'F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf'

# ---- 4 HARD exact-chain questions ----

$ChainQ = @"
请只输出结果（不要额外解释）。

已知：
x1 = 17
x2 = x1 * 3 + 4
x3 = x2 * 2 - 7
x4 = x3 * 3 + 1
x5 = x4 * 2 - 5

请给出 x5 的数值。

（提示：务必逐步精确计算，避免中间舍入。）
"@

$MultiVarQ = @"
某公司产品定价与成本的逻辑：
- 若售价 P 元/件，则每月销量 = 6000 − 50·P  件。
- 每月固定成本 = 36000 元；每件可变成本 = 40 元。
- 公司希望**每月利润最大**。

要求：
(1) 写出利润关于 P 的函数（含 P² 项）；
(2) 计算使利润最大的售价 P；
(3) 计算此时的最大月利润。

（请给出数值结果；若涉及二次函数，用 P = −b/(2a) 求顶点。）
"@

$LogicQ = @"
请只输出结果。

一个工厂的三条产线生产同一种零件，逐级质检：
- A 线日产量 1200 件，次品率 2%；
- A 线的合格品按 3:2 分给 B 线和 C 线；
- B 线再加工后次品率 3%，C 线再加工后次品率 5%；
- 最终只统计 B、C 两个产线的合格品。

问：一天下来，B 线和 C 线的合格品数**之和**是多少件？（取整数）

（提示：先算 A 线合格品，再按 3:2 分配，再各自乘各自合格率。）
"@

$OdometerQ = @"
请只输出结果。

一个数字被 7 除余 3，被 5 除余 2，被 3 除余 1。这个数在 100 到 200 之间，且是质数。

问：这个数是多少？

（提示：中国剩余定理；100~200 间满足三同余且为质数的数。）请只输出这个数。
"@

$AgentQuestions = @(
  @{ id='e1-链式乘法'; type='精确链式'; prompt=$ChainQ
    checks=@(@{pat='615|61 ?5|＝?615';desc='x5=615'}) ; minSteps=0 },
  @{ id='e2-利润最大化'; type='二次优化'; prompt=$MultiVarQ
    checks=@(@{pat='80|P=80|80 ?元';desc='P=80'},@{pat='44000|4\.4万|44,000|4400 ?0';desc='利润=44000'},@{pat='-50|50P|P²|二次';desc='含二次项'}) ; minSteps=0 },
  @{ id='e3-产线良品'; type='多步计算'; prompt=$LogicQ
    checks=@(@{pat='1131|113 ?1|11 ?31';desc='合格=1131'}) ; minSteps=0 },
  @{ id='e4-剩余定理'; type='数论'; prompt=$OdometerQ
    checks=@(@{pat='157|15 ?7';desc='答案=157'}) ; minSteps=0 }
)

function Invoke-Checklist($response,$checks,$minSteps,$orderCheck){
  $passed=0;$total=$checks.Count;$detail=@()
  foreach($c in $checks){if($response -match $c.pat){$passed++;$detail+="  [Y] $($c.desc)"}else{$detail+="  [N] $($c.desc)"}}
  if($minSteps -gt 0){$total++;$n=([regex]::Matches($response,'\d+[.、)]\s')).Count;if($n-ge$minSteps){$passed++;$detail+="  [Y] 步骤$n"}else{$detail+="  [N] 步骤$n"}}
  $score=if($total-gt0){[math]::Round($passed*100/$total,0)}else{0}
  return @{passed=$passed;total=$total;score=$score;detail=$detail}
}

function Run-Model($ModelPath,$Label,$MoeMode,$Ncmoe){
  $results=@();$s=$null
  try{
    $s=Start-LlamaServer -ModelPath $ModelPath -Alias $Label -LlamaDir $LlamaDir -Ngl 99 -ContextSize $Ctx -CacheTypeK 'q4_0' -CacheTypeV 'q4_0' -Fa 'on' -MoeMode $MoeMode -Ncmoe $Ncmoe -ReasoningBudget $Budget -Threads 20 -ThreadsBatch 20 -SkipHelpCheck
    Write-Host "`n======== [up] $Label ctx=$($s.ctx) moe=$MoeMode ncmoe=$Ncmoe ========"
    $w=Invoke-Short -server $s -NPredict 16
    foreach($q in $AgentQuestions){
      $sc=@();$tk=@();$ans=@()
      for($r=1;$r-le$Repeats;$r++){
        $body=@{model=$Label;messages=@(@{role='user';content=$q.prompt});max_tokens=$MaxTokens;temperature=0.6;top_k=20;top_p=0.95;min_p=0.0}|ConvertTo-Json -Depth 5
        try{
          $resp=Invoke-RestMethod -Uri "http://127.0.0.1:$($s.port)/v1/chat/completions" -Method Post -Headers $s.headers -Body $body -TimeoutSec 600
          $out=$resp.choices[0].message.content
          $ck=Invoke-Checklist $out $q.checks $q.minSteps $q.orderCheck
          $sc+=$ck.score;$tk+=$resp.usage.completion_tokens
          $ans+=($out -replace "`n",' ').Substring(0,[math]::Min(90,$out.Length))
        }catch{$sc+=0;$tk+=0;$ans+='ERR'}
      }
      $avg=if($sc.Count){[math]::Round(($sc|Measure-Object -Average).Average,0)}else{0}
      $results+=@{id=$q.id;type=$q.type;avg=$avg;scores=($sc-join'/');tokens=($tk-join'/');ans=$ans}
      Write-Host ("[$Label] {0,-14} avg={1}% runs=[{2}] tok=[{3}]" -f $q.id,$avg,($sc-join'/'),($tk-join'/'))
      $ans|ForEach-Object{Write-Host "     >> $_"}
    }
  }catch{Write-Host "[$Label] FATAL: $($_.Exception.Message)"}
  finally{Stop-LlamaServer $s}
  return $results
}

Write-Host "================ 27B vs 35B HIGH-PRESSURE (exact chain) ================"
Write-Host "config: ctx=$Ctx kv=q4_0 ngl99 rb=$Budget temp0.6 repeats=$Repeats  (35B -ncmoe $Ncmoe35B)"
$r27 = Run-Model $Model27B 'qwen38-27b' 'none' -1
$r35 = Run-Model $Model35B 'qwen36-35b' 'ncmoe' $Ncmoe35B

Write-Host "`n`n================ SUMMARY ================"
Write-Host ("{0,-16}| {1,-10}| {2,-10}" -f 'Question','27B-Q3','35B-ncmoe20')
Write-Host ('-'*38)
for($i=0;$i-lt$AgentQuestions.Count;$i++){
  $a=if($r27[$i]){"$($r27[$i].avg)%"}else{'na'}
  $b=if($r35[$i]){"$($r35[$i].avg)%"}else{'na'}
  Write-Host ("{0,-16}| {1,-10}| {2,-10}" -f $AgentQuestions[$i].type,$a,$b)
}
$avg27=if($r27){[math]::Round(($r27|Measure-Object avg -Average).Average,0)}else{'na'}
$avg35=if($r35){[math]::Round(($r35|Measure-Object avg -Average).Average,0)}else{'na'}
Write-Host ('-'*38)
Write-Host ("{0,-16}| {1,-10}| {2,-10}" -f 'AVERAGE',"$avg27%","$avg35%")
Write-Host "`n[done] high-pressure 27b vs 35b complete"
