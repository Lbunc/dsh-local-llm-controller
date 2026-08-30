#requires -Version 7
<#
.SYNOPSIS
  3-model agent comparison on 4 HARD GAIA-style questions.
  9B-Q6 / 27B-Q3 / 35B-IQ4_NL(all-MoE, -ncmoe 20).
  Same config: 32K, kv-q4_0, ngl 99, rb 2048, temp0.6/topk20/topp0.95/minp0/repeat1/presence0.
  Each q run 2x; score = checklist hit-rate. Only variable = model (+-ncmoe for 35B MoE).
#>
param(
  [string]$LlamaDir = 'F:\llama-b10488-bin-win-cuda-13.3-x64',
  [int]$Ctx = 32768,
  [int]$Budget = 2048,
  [int]$MaxTokens = 8192,
  [int]$Repeats = 2,
  [int]$Ncmoe35B = 20
)
$ErrorActionPreference = 'Continue'
. 'D:\DSH\WORK1\llama.cpp\scripts\start_server.ps1'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Model9B  = 'F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.5-9B\Qwen3.5-9B-Q6_K.gguf'
$Model27B = 'F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.8-27B\Qwen3.8-27B-UD-IQ3_XXS.gguf'
$Model35B = 'F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf'

# ============ 4 HARD questions ============
$DefUser = @"
你是一名安全审计员。以下是某公司系统权限登记表（每人4维属性：当前职位 / 是否加过任意权限组 / 参与的系统 / 入职年限）。

王磊：安全工程师；加过「数据库组」；参与系统：订单、支付；入职2018
李娜：运维工程师；加过「风控组」；参与系统：订单；入职2019
张斌：安全工程师；加过「数据库组」；参与系统：订单、支付；入职2017
陈静：数据平台负责人；加过「限权组」；参与系统：支付；入职2016
刘洋：安全工程师；未加任何权限组；参与系统：订单、支付；入职2019
赵敏：安全工程师；加过「审计组」；参与系统：订单、支付；入职2016

背景说明（重要）：「限权组」和「风控组」是**高敏感限权组**，凡**加入过**这两组之一的人，**一律不得**接触核心数据库。「数据库组」是研发组，不含敏感语义。

【任务】请选出**唯一**满足以下全部条件的人：
(1) 职位是「安全工程师」；
(2) **从未加入过**「限权组」或「风控组」；
(3) 参与的系统**同时包含**「订单」和「支付」；
(4) 入职 ≥ 5 年。

请给出姓名，并逐条说明依据；对每一个**看似满足但实际不满足**的人，说明他被哪一条条件排除。
"@

$ToolQ = @"
你是一个自动化运维 Agent，可用以下 8 个工具。注意：这些工具**有依赖**，且其中有两个工具是**这次任务不需要的干扰项**（用了会引入副作用）。

工具：
- `list_jobs()`：返回所有运行中的任务列表，含 job_id。
- `get_job_detail(job_id)`：返回该 job 的 detail（内含关键字段 `artifact_key`）。
- `find_secret(artifact_key)`：用 artifact_key 换取一个 secret 值（**必须先拿到 artifact_key**）。
- `store_secret(name, value)`：把 secret 持久化。
- `notify(msg)`：发送通知（副作用：会群发邮件，**本次不需要**）。
- `archive(job_id)`：归档任务（副作用：会停掉该任务，**本次不需要**）。
- `query_logs(job_id)`：返回日志（备用工具）。
- `health()`：健康检查（备用工具）。

【任务】对「list_jobs() 返回的第一个 job」，按以下精确流程执行：
1) 先 `get_job_detail` 拿到这个 job 的 `artifact_key`；
2) 用这个 `artifact_key` 调用 `find_secret` 拿到 secret；
3) 用 `store_secret` 把它存为名字「CHAT_SECRET」。

请给出**严格 3 步**的工具调用链（第1步输出是第2步入参来源，第2步输出是第3步入参），并**明确说明为什么不用** `notify` 和 `archive` 这两个工具。
"@

$ContraQ = @"
阅读下面这篇简讯，它**多处自相矛盾**。请找出**所有**矛盾点，并判断哪一种情况更可能是笔误。

「阳光科技有限公司今日宣布完成新一轮融资。公司创始人兼CEO李伟**三年前**加入公司，此前曾在某大厂任职。本轮融资由A轮领投，融资金额为**5000万元**。李伟表示，公司**去年**才正式创立，他本人是初创核心成员。本轮估值约10亿元。会上宣布旗舰产品定价**299元/月**，并称**试用用户需支付499元/月**。发布会定于**上午10点**举行，最终在**晚间8点**落幕。公司称员工规模达**200人**，但财务数据又显示**核心团队仅12人**。」

【任务】列出所有矛盾点，逐条给出直接冲突的两处原文；对每一条，判断哪一处更可能是笔误并简要说明。
"@

$SchedQ = @"
你是值班调度员。现有 3 台设备（S1, S2, S3）和 4 个任务（T1-T4），及 2 名工程师（甲、乙）。

任务约束：
- T1：耗时 2h，仅可用 S1，需技能「网络」。
- T2：耗时 3h，需技能「数据库」，**必须在 T1 开始后才能开始**（硬依赖）。
- T3：耗时 2h，可用 S2 或 S3，需技能「网络」。
- T4：耗时 4h，可用 S1 或 S2，需技能「数据库」。

设备约束：同一时刻每台设备只能跑一个任务。
工程师约束：同一个工程师同一时刻只能干一个任务；每个任务必须随时有一名工程师在场。
技能：甲会「网络+数据库」，乙会「网络」。

另外：乙**迟到 1 小时**上班，甲可随时开始。

【任务】给出一个让所有任务**当晚 24:00 前完成**的排班表（每任务：谁、用什么设备、起止时间），并说明总耗时与设备/工程师是否存在冲突。若在乙迟到约束下不可行，请给出**最小改动**方案。
"@

$AgentQuestions = @(
  @{ id='h1-选人排雷'; type='多跳排雷'; prompt=$DefUser
    checks=@(
      @{pat='王磊';desc='点名王磊'}
      @{pat='2018|2017|2016';desc='入职≥5年依据'}
      @{pat='风控组|限权组';desc='排除限权/风控组'}
      @{pat='订单|支付';desc='含订单+支付系统'}
      @{pat='安全工程师';desc='职位条件'}
      @{pat='刘洋|李娜|陈静|赵敏|张斌';desc='排除反例'}
    ); minSteps=0 },
  @{ id='h2-工具依赖链'; type='依赖链'; prompt=$ToolQ
    checks=@(
      @{pat='get_job_detail|list_jobs';desc='用get_job_detail'}
      @{pat='find_secret';desc='用find_secret'}
      @{pat='store_secret';desc='用store_secret'}
      @{pat='artifact_key';desc='引用artifact_key'}
      @{pat='notify';desc='提到notify不用'}
      @{pat='archive';desc='提到archive不用'}
      @{pat='副作用|群发|停掉';desc='说明副作用'}
    ); orderCheck=@('get_job_detail','find_secret') },
  @{ id='h3-矛盾核查'; type='反事实核查'; prompt=$ContraQ
    checks=@(
      @{pat='三年前|去年';desc='找到时间矛盾'}
      @{pat='299|499';desc='找到价格矛盾'}
      @{pat='上午|晚间|10点|8点';desc='找到时间地点矛盾'}
      @{pat='200人|12人';desc='找到规模矛盾'}
      @{pat='笔误|可能|更可能';desc='判断笔误'}
      @{pat='矛盾|冲突|不一致';desc='归纳矛盾'}
    ); minSteps=0 },
  @{ id='h4-调度排班'; type='条件调度'; prompt=$SchedQ
    checks=@(
      @{pat='T[1-4]';desc='覆盖任务'}
      @{pat='S[1-3]';desc='覆盖设备'}
      @{pat='甲|乙';desc='覆盖工程师'}
      @{pat='迟到|1小时|乙';desc='处理迟到'}
      @{pat='依赖|T2|必须在|之后';desc='处理依赖'}
      @{pat='总耗时|24:00|完成|冲突|不可行';desc='给出耗时/判断'}
    ); minSteps=0 }
)

function Invoke-Checklist($response,$checks,$minSteps,$orderCheck){
  $passed=0;$total=$checks.Count;$detail=@()
  foreach($c in $checks){if($response -match $c.pat){$passed++;$detail+="  [Y] $($c.desc)"}else{$detail+="  [N] $($c.desc)"}}
  if($minSteps -gt 0){$total++;$n=([regex]::Matches($response,'\d+[.、)]\s')).Count;if($n-ge$minSteps){$passed++;$detail+="  [Y] 步骤$n"}else{$detail+="  [N] 步骤$n"}}
  if($orderCheck -and $orderCheck.Count-ge2){$total++;$pos=$orderCheck|ForEach-Object{$i=$response.IndexOf($_);if($i-lt0){[int]::MaxValue}else{$i}};$ok=$true;for($i=1;$i-lt$pos.Count;$i++){if($pos[$i]-lt$pos[$i-1]){$ok=$false}};if($ok-and$pos[0]-ne[int]::MaxValue){$passed++;$detail+="  [Y] 顺序$($orderCheck-join'→')"}else{$detail+="  [N] 顺序"}}
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
      $sc=@();$tk=@()
      for($r=1;$r-le$Repeats;$r++){
        $body=@{model=$Label;messages=@(@{role='user';content=$q.prompt});max_tokens=$MaxTokens;temperature=0.6;top_k=20;top_p=0.95;min_p=0.0}|ConvertTo-Json -Depth 5
        try{
          $resp=Invoke-RestMethod -Uri "http://127.0.0.1:$($s.port)/v1/chat/completions" -Method Post -Headers $s.headers -Body $body -TimeoutSec 600
          $out=$resp.choices[0].message.content
          $ck=Invoke-Checklist $out $q.checks $q.minSteps $q.orderCheck
          $sc+=$ck.score;$tk+=$resp.usage.completion_tokens
        }catch{$sc+=0;$tk+=0}
      }
      $avg=if($sc.Count){[math]::Round(($sc|Measure-Object -Average).Average,0)}else{0}
      $results+=@{id=$q.id;type=$q.type;avg=$avg;scores=($sc-join'/');tokens=($tk-join'/')}
      Write-Host ("[$Label] {0,-14} avg={1}% runs=[{2}] tok=[{3}]" -f $q.id,$avg,($sc-join'/'),($tk-join'/'))
    }
  }catch{Write-Host "[$Label] FATAL: $($_.Exception.Message)"}
  finally{Stop-LlamaServer $s}
  return $results
}

Write-Host "================ 3-MODEL AGENT COMPARE (HARD) ================"
Write-Host "config: ctx=$Ctx kv=q4_0 ngl99 rb=$Budget temp0.6/topk20/topp0.95/minp0/repeat1/presence0 repeats=$Repeats  (35B -ncmoe $Ncmoe35B)"
$r9  = Run-Model $Model9B  'qwen35-9b'  'none' -1
$r27 = Run-Model $Model27B 'qwen38-27b' 'none' -1
$r35 = Run-Model $Model35B 'qwen36-35b' 'ncmoe' $Ncmoe35B

Write-Host "`n`n================ SUMMARY ================"
Write-Host ("{0,-16}| {1,-9}| {2,-9}| {3,-9}" -f 'Question','9B-Q6','27B-Q3','35B-ncmoe20')
Write-Host ('-'*47)
for($i=0;$i-lt$AgentQuestions.Count;$i++){
  $t=$AgentQuestions[$i].type
  $a=if($r9[$i]){$r9[$i].avg}else{'na'}
  $b=if($r27[$i]){$r27[$i].avg}else{'na'}
  $c=if($r35[$i]){$r35[$i].avg}else{'na'}
  Write-Host ("{0,-16}| {1,-9}| {2,-9}| {3,-9}" -f $t,$a,$b,$c)
}
$avg9=if($r9){[math]::Round(($r9|Measure-Object avg -Average).Average,0)}else{'na'}
$avg27=if($r27){[math]::Round(($r27|Measure-Object avg -Average).Average,0)}else{'na'}
$avg35=if($r35){[math]::Round(($r35|Measure-Object avg -Average).Average,0)}else{'na'}
Write-Host ('-'*47)
Write-Host ("{0,-16}| {1,-9}| {2,-9}| {3,-9}" -f 'AVERAGE',"$avg9%","$avg27%","$avg35%")
Write-Host "`n[done] 3-model hard compare complete"
