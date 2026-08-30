#requires -Version 7
<#
.SYNOPSIS
  UD-35B vs Uncensored-35B 能力对比（同一题库，唯一变量=模型）。
  题库含：4 道高压精确链式 + 4 道 GAIA 风格 agent 难题。objective 判定（reference 程序/checklist）。
  同构同参：32K, q8_0 KV, ngl 99, rb 2048, temp0.6/topk20/topp0.95/minp0/repeat1/presence0。
  两模型 MoE 分别按各自最优 -ncmoe：Uncensored=20, UD=18（记录注明）。
#>
param(
  [string]$LlamaDir = 'F:\llama-b10488-bin-win-cuda-13.3-x64',
  [int]$Ctx = 32768, [int]$Budget = 2048, [int]$MaxTokens = 8192, [int]$Repeats = 2
)
$ErrorActionPreference = 'Continue'
. 'D:\DSH\WORK1\llama.cpp\scripts\start_server.ps1'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ModelUD  = 'F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-UD-IQ4_NL.gguf'
$ModelRef = 'F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf'

# ============ 4 HARD exact-chain questions (objective numeric answers) ============
$ChainQ = @"
请只输出结果（不要额外解释）。x1=17; x2=x1*3+4; x3=x2*2-7; x4=x3*3+1; x5=x4*2-5。请给出 x5 的数值。（提示：逐步精确计算。）
"@
$ProfitQ = @"
某公司：售价 P 元/件，月销量=6000-50P 件；月固定成本=36000 元；每件可变成本=40 元。
要求：(1) 写出月利润关于 P 的函数；(2) 求利润最大的售价 P；(3) 求此时最大月利润。（提示：二次函数顶点 P=-b/(2a)。）
"@
$LogicQ = @"
请只输出结果。A 线日产量 1200 件，次品率 2%；A 线合格品按 3:2 分给 B、C 线；B 再加工次品率 3%，C 再加工次品率 5%；最终只统计 B、C 合格品。问 B、C 合格品数之和是多少件（取整数）？
"@
$OdometerQ = @"
请只输出结果。一个数被 7 除余 3，被 5 除余 2，被 3 除余 1；这个数在 100~200 之间且是质数。问：这个数是多少？（中国剩余定理）请只输出这个数。
"@

# ============ 4 HARD GAIA-style agent questions ============
$DefUser = @"
你是一名安全审计员。某公司权限登记表（每人：职位 / 是否加过权限组 / 参与系统 / 入职年）：
王磊：安全工程师；加过「数据库组」；订单、支付；2018
李娜：运维工程师；加过「风控组」；订单；2019
张斌：安全工程师；加过「数据库组」；订单、支付；2017
陈静：数据平台负责人；加过「限权组」；支付；2016
刘洋：安全工程师；未加组；订单、支付；2019
赵敏：安全工程师；加过「审计组」；订单、支付；2016
背景：「限权组」「风控组」是高敏感限权组，凡加入过这两组之一的人一律不得接触核心数据库；「数据库组」是研发组。
【任务】选出**唯一**满足全部条件的人：(1) 安全工程师；(2) 从未加入过限权组/风控组；(3) 系统同时含订单+支付；(4) 入职≥5年。给姓名并逐条说明，对每个看似满足实际不满足的人说明被哪条排除。
"@
$ToolQ = @"
你是一个自动化运维 Agent，可用工具：list_jobs() 返回任务列表（含 job_id）；get_job_detail(job_id) 返回含关键字段 artifact_key；find_secret(artifact_key) 用 key 换取 secret（必须先拿到 key）；store_secret(name,value) 持久化；notify(msg) 会群发邮件（本次不需要）；archive(job_id) 会停任务（本次不需要）；query_logs(job_id) 备用；health() 备用。
【任务】对 list_jobs() 返回的第一个 job，严格 3 步：1) get_job_detail 拿 artifact_key；2) 用其调 find_secret 拿 secret；3) 用 store_secret 存为 CHAT_SECRET。请给出严格 3 步调用链，并说明为什么不用 notify 和 archive。
"@
$ContraQ = @"
阅读简讯，它多处自相矛盾，请找出**所有**矛盾点，并判断哪种更可能是笔误：「阳光科技今日宣布完成融资。创始人兼CEO李伟**三年前**加入公司。本轮由A轮领投，融资金额**5000万元**。李伟称公司**去年**才正式创立，他是初创核心成员。本轮估值约10亿元。旗舰产品定价**299元/月**，并称试用用户需支付**499元/月**。发布会定于**上午10点**，最终在**晚间8点**落幕。公司称员工**200人**，但财务显示**核心团队仅12人**。」列出所有矛盾点，逐条给出直接冲突的两处原文，判断哪处更可能是笔误。
"@
$SchedQ = @"
你是值班调度员。3 台设备 S1,S2,S3；4 任务 T1-T4；2 工程师 甲、乙。
T1：耗时2h，仅可用S1，需技能「网络」。
T2：耗时3h，需「数据库」，必须 T1 开始后才能开始（硬依赖）。
T3：耗时2h，可用S2或S3，需「网络」。
T4：耗时4h，可用S1或S2，需「数据库」。
设备约束：同一时刻每台设备只能跑一个任务。工程师：同一工程师同一时刻只能干一个任务，每任务须有工程师在场。技能：甲会网络+数据库，乙会网络。另外：乙迟到1小时上班，甲可随时开始。
【任务】给出让所有任务当晚 24:00 前完成的排班表（谁、什么设备、起止时间），说明总耗时与设备/工程师是否冲突；若在乙迟到约束下不可行，给出**最小改动**方案。
"@

$Questions = @(
  @{ id='e1-链式'; type='精确链式'; prompt=$ChainQ; checks=@(@{pat='615|61 ?5|=615';desc='x5=615'}) },
  @{ id='e2-利润'; type='二次优化'; prompt=$ProfitQ; checks=@(@{pat='80|P=80';desc='P=80'},@{pat='44000|4\.4万|44,000';desc='利润=44000'},@{pat='-50|50P|P²|二次';desc='含二次项'}) },
  @{ id='e3-产线'; type='多步计算'; prompt=$LogicQ; checks=@(@{pat='1131|113 ?1';desc='合格=1131'}) },
  @{ id='e4-剩余'; type='数论'; prompt=$OdometerQ; checks=@(@{pat='157|15 ?7';desc='答案=157'}) },
  @{ id='h1-选人'; type='多跳排雷'; prompt=$DefUser; checks=@(
      @{pat='王磊';desc='点名王磊'},@{pat='2018|2017|2016';desc='入职年份'},@{pat='风控组|限权组';desc='排除敏感组'},
      @{pat='订单';desc='含订单'},@{pat='支付';desc='含支付'},@{pat='安全工程师';desc='职位'} ) },
  @{ id='h2-工具链'; type='依赖链'; prompt=$ToolQ; checks=@(
      @{pat='get_job_detail|list_jobs';desc='get_job_detail'},@{pat='find_secret';desc='find_secret'},@{pat='store_secret';desc='store_secret'},
      @{pat='artifact_key';desc='artifact_key'},@{pat='notify';desc='notify不用'},@{pat='archive';desc='archive不用'} ) },
  @{ id='h3-矛盾'; type='反事实核查'; prompt=$ContraQ; checks=@(
      @{pat='三年前|去年';desc='时间矛盾'},@{pat='299|499';desc='价格矛盾'},@{pat='上午|晚间|10点|8点';desc='时间地点矛盾'},
      @{pat='200人|12人';desc='规模矛盾'},@{pat='笔误|更可能';desc='判断笔误'} ) },
  @{ id='h4-调度'; type='条件调度'; prompt=$SchedQ; checks=@(
      @{pat='T[1-4]';desc='覆盖任务'},@{pat='S[1-3]';desc='覆盖设备'},@{pat='甲|乙';desc='覆盖工程师'},
      @{pat='迟到|1小时';desc='处理迟到'},@{pat='依赖|T2';desc='处理依赖'},@{pat='24:00|完成|冲突|不可行';desc='判断'} ) }
)

function Invoke-Checklist($response,$checks){
  $passed=0;$total=$checks.Count;$detail=@()
  foreach($c in $checks){if($response -match $c.pat){$passed++;$detail+="  [Y] $($c.desc)"}else{$detail+="  [N] $($c.desc)"}}
  $score=if($total-gt0){[math]::Round($passed*100/$total,0)}else{0}
  return @{passed=$passed;total=$total;score=$score;detail=$detail}
}

function Run-Model($ModelPath,$Label,$Ncmoe){
  $results=@();$s=$null
  try{
    $s=Start-LlamaServer -ModelPath $ModelPath -Alias $Label -LlamaDir $LlamaDir -Ngl 99 -ContextSize $Ctx -CacheTypeK 'q8_0' -CacheTypeV 'q8_0' -Fa 'on' -MoeMode 'ncmoe' -Ncmoe $Ncmoe -ReasoningBudget $Budget -Threads 20 -SkipHelpCheck
    Write-Host "`n======== [up] $Label ctx=$($s.ctx) ncmoe=$Ncmoe ========"
    $w=Invoke-Short -server $s -NPredict 16
    foreach($q in $Questions){
      $sc=@();$tk=@();$ans=@()
      for($r=1;$r-le$Repeats;$r++){
        $body=@{model=$Label;messages=@(@{role='user';content=$q.prompt});max_tokens=$MaxTokens;temperature=0.6;top_k=20;top_p=0.95;min_p=0.0}|ConvertTo-Json -Depth 5
        try{
          $resp=Invoke-RestMethod -Uri "http://127.0.0.1:$($s.port)/v1/chat/completions" -Method Post -Headers $s.headers -Body $body -TimeoutSec 600
          $out=$resp.choices[0].message.content
          $ck=Invoke-Checklist $out $q.checks
          $sc+=$ck.score;$tk+=$resp.usage.completion_tokens
          $ans+=($out -replace "`n",' ').Substring(0,[math]::Min(80,$out.Length))
        }catch{$sc+=0;$tk+=0;$ans+='ERR'}
      }
      $avg=if($sc.Count){[math]::Round(($sc|Measure-Object -Average).Average,0)}else{0}
      $results+=@{id=$q.id;type=$q.type;avg=$avg;scores=($sc-join'/');tokens=($tk-join'/');ans=$ans}
      Write-Host ("[$Label] {0,-10} avg={1}% runs=[{2}] tok=[{3}]" -f $q.id,$avg,($sc-join'/'),($tk-join'/'))
      $ans|ForEach-Object{Write-Host "     >> $_"}
    }
  }catch{Write-Host "[$Label] FATAL: $($_.Exception.Message)"}
  finally{Stop-LlamaServer $s}
  return $results
}

Write-Host "================ UD-35B vs UNCENSOR-35B CAPABILITY COMPARE ================"
Write-Host "config: ctx=$Ctx kv=q8_0 ngl99 rb=$Budget temp0.6 repeats=$Repeats  (UD -ncmoe 18 / Uncensored -ncmoe 20)"
$rUD = Run-Model $ModelUD   'ud35b'     18
$rRef= Run-Model $ModelRef  'uncensored' 20

Write-Host "`n`n================ SUMMARY ================"
Write-Host ("{0,-12}| {1,-12}| {2,-12}" -f 'Question','UD(18)','Uncens(20)')
Write-Host ('-'*38)
for($i=0;$i-lt$Questions.Count;$i++){
  $a=if($rUD[$i]){"$($rUD[$i].avg)%"}else{'na'}
  $b=if($rRef[$i]){"$($rRef[$i].avg)%"}else{'na'}
  Write-Host ("{0,-12}| {1,-12}| {2,-12}" -f $Questions[$i].type,$a,$b)
}
$avgUD=if($rUD){[math]::Round(($rUD|Measure-Object avg -Average).Average,0)}else{'na'}
$avgRef=if($rRef){[math]::Round(($rRef|Measure-Object avg -Average).Average,0)}else{'na'}
Write-Host ('-'*38)
Write-Host ("{0,-12}| {1,-12}| {2,-12}" -f 'AVERAGE',"$avgUD%","$avgRef%")
Write-Host "`n[done] UD vs Uncensored compare complete"
