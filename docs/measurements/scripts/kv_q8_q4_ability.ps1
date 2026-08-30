#requires -Version 7
<#
.SYNOPSIS
  KV 量化能力对照：同一模型 UD-35B（ncmoe 18）在 q8_0 vs q4_0 KV 下，能力是否变化。
  唯一变量 = KV 类型（q8_0 / q4_0）。同题同 prompt 同判定。
  这是 skill 2.2/3.2 的 KV 量化对照：判定 q4_0（更省显存、上下文更高）是否损伤能力。
#>
param(
  [string]$LlamaDir='F:\llama-b10488-bin-win-cuda-13.3-x64',
  [int]$Ctx=32768, [int]$Budget=2048, [int]$MaxTokens=8192, [int]$Repeats=2,
  [int]$Ncmoe=18
)
$ErrorActionPreference='Continue'
. 'D:\DSH\WORK1\llama.cpp\scripts\start_server.ps1'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8

$ModelUD='F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-UD-IQ4_NL.gguf'

$ChainQ=@"
请只输出结果（不要额外解释）。x1=17; x2=x1*3+4; x3=x2*2-7; x4=x3*3+1; x5=x4*2-5。请给出 x5 的数值。（提示：逐步精确计算。）
"@
$ProfitQ=@"
某公司：售价 P 元/件，月销量=6000-50P 件；月固定成本=36000 元；每件可变成本=40 元。
要求：(1) 写出月利润关于 P 的函数；(2) 求利润最大的售价 P；(3) 求此时最大月利润。
"@
$LogicQ=@"
请只输出结果。A 线日产量 1200 件，次品率 2%；A 线合格品按 3:2 分给 B、C 线；B 再加工次品率 3%，C 再加工次品率 5%；最终只统计 B、C 合格品。问 B、C 合格品数之和是多少件（取整数）？
"@
$OdometerQ=@"
请只输出结果。一个数被 7 除余 3，被 5 除余 2，被 3 除余 1；这个数在 100~200 之间且是质数。问：这个数是多少？
"@
$DefUser=@"
你是一名安全审计员。某公司权限登记表（每人：职位/是否加权限组/参与系统/入职年）：
王磊：安全工程师；加过「数据库组」；订单、支付；2018
李娜：运维工程师；加过「风控组」；订单；2019
张斌：安全工程师；加过「数据库组」；订单、支付；2017
陈静：数据平台负责人；加过「限权组」；支付；2016
刘洋：安全工程师；未加组；订单、支付；2019
赵敏：安全工程师；加过「审计组」；订单、支付；2016
背景：「限权组」「风控组」是高敏感限权组，凡加入过这两组之一的人一律不得接触核心数据库；「数据库组」是研发组。
【任务】选出唯一满足全部条件的人：(1)安全工程师；(2)从未加入限权/风控组；(3)系统同时含订单+支付；(4)入职≥5年。给姓名并逐条说明。
"@
$ToolQ=@"
你是一个自动化运维 Agent，可用工具：list_jobs()；get_job_detail(job_id) 返回含 artifact_key；find_secret(artifact_key) 用 key 换 secret（必须先拿 key）；store_secret(name,value)；notify(msg) 群发邮件（不需要）；archive(job_id) 停任务（不需要）。
【任务】对 list_jobs() 返回的第一个 job，严格 3 步：1) get_job_detail 拿 artifact_key；2) find_secret 拿 secret；3) store_secret 存为 CHAT_SECRET。给出调用链并说明为什么不用 notify/archive。
"@
$ContraQ=@"
阅读简讯，它多处自相矛盾，请找出所有矛盾点并判断哪种更可能是笔误：「阳光科技宣布融资。CEO李伟三年前加入公司。融资金额5000万元。李伟称公司去年才创立，他是初创核心成员。旗舰产品定价299元/月，试用需499元/月。发布会定于上午10点，最终晚间8点落幕。公司称员工200人，但财务显示核心团队仅12人。」列出所有矛盾点，逐条给冲突原文，判断哪处更可能是笔误。
"@
$SchedQ=@"
你是值班调度员。3 台设备 S1,S2,S3；4 任务 T1-T4；2 工程师甲乙。
T1：2h，仅S1，需网络。T2：3h，需数据库，必须 T1 开始后开始。T3：2h，S2或S3，需网络。T4：4h，S1或S2，需数据库。
设备：同时每台只能一任务。工程师：同刻只能一任务，每任务须有工程师在场。技能：甲会网络+数据库，乙会网络。乙迟到1小时，甲随时开始。
【任务】给出让所有任务当晚24:00前完成的排班表，说明总耗时与设备/工程师是否冲突；若在乙迟到下不可行，给最小改动方案。
"@

$Questions=@(
  @{id='e1-链式';type='精确链式';prompt=$ChainQ;checks=@(@{pat='615|61 ?5|=615';desc='x5=615'})},
  @{id='e2-利润';type='二次优化';prompt=$ProfitQ;checks=@(@{pat='80|P=80';desc='P=80'},@{pat='44000|4\.4万|44,000';desc='利润=44000'},@{pat='-50|50P|P²|二次';desc='含二次项'})},
  @{id='e3-产线';type='多步计算';prompt=$LogicQ;checks=@(@{pat='1131|113 ?1';desc='合格=1131'})},
  @{id='e4-剩余';type='数论';prompt=$OdometerQ;checks=@(@{pat='157|15 ?7';desc='答案=157'})},
  @{id='h1-选人';type='多跳排雷';prompt=$DefUser;checks=@(@{pat='王磊|张斌|赵敏';desc='候选人'},@{pat='风控组|限权组';desc='排除敏感组'},@{pat='订单';desc='订单'},@{pat='支付';desc='支付'},@{pat='2018|2017|2016';desc='入职年'})},
  @{id='h2-工具链';type='依赖链';prompt=$ToolQ;checks=@(@{pat='get_job_detail|list_jobs';desc='get_job_detail'},@{pat='find_secret';desc='find_secret'},@{pat='store_secret';desc='store_secret'},@{pat='artifact_key';desc='artifact_key'},@{pat='notify';desc='notify不用'},@{pat='archive';desc='archive不用'})},
  @{id='h3-矛盾';type='反事实核查';prompt=$ContraQ;checks=@(@{pat='三年前|去年';desc='时间矛盾'},@{pat='299|499';desc='价格矛盾'},@{pat='上午|晚间|10点|8点';desc='时间地点矛盾'},@{pat='200人|12人';desc='规模矛盾'},@{pat='笔误|更可能';desc='判断笔误'})},
  @{id='h4-调度';type='条件调度';prompt=$SchedQ;checks=@(@{pat='T[1-4]';desc='覆盖任务'},@{pat='S[1-3]';desc='覆盖设备'},@{pat='甲|乙';desc='覆盖工程师'},@{pat='迟到|1小时';desc='处理迟到'},@{pat='依赖|T2';desc='处理依赖'},@{pat='24:00|完成|冲突|不可行';desc='判断'})}
)

function Invoke-Checklist($response,$checks){
  $passed=0;$total=$checks.Count
  foreach($c in $checks){if($response -match $c.pat){$passed++}}
  $score=if($total-gt0){[math]::Round($passed*100/$total,0)}else{0}
  return @{passed=$passed;total=$total;score=$score}
}

function Run-KV($Label,$CacheTypeK,$CacheTypeV){
  $results=@();$s=$null
  try{
    $s=Start-LlamaServer -ModelPath $ModelUD -Alias 'ud35b' -LlamaDir $LlamaDir -Ngl 99 -ContextSize $Ctx -CacheTypeK $CacheTypeK -CacheTypeV $CacheTypeV -Fa 'on' -MoeMode 'ncmoe' -Ncmoe $Ncmoe -ReasoningBudget $Budget -Threads 20 -SkipHelpCheck
    Write-Host "`n======== [kv=$Label] ctx=$($s.ctx) ncmoe=$Ncmoe ========"
    $w=Invoke-Short -server $s -NPredict 16
    foreach($q in $Questions){
      $sc=@();$tk=@();$ans=@()
      for($r=1;$r-le$Repeats;$r++){
        $body=@{model='ud35b';messages=@(@{role='user';content=$q.prompt});max_tokens=$MaxTokens;temperature=0.6;top_k=20;top_p=0.95;min_p=0.0}|ConvertTo-Json -Depth 5
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
    }
  }catch{Write-Host "[$Label] FATAL: $($_.Exception.Message)"}
  finally{Stop-LlamaServer $s}
  return $results
}

Write-Host "================ UD35B KV CAPABILITY COMPARE (q8_0 vs q4_0) ================"
Write-Host "config: ctx=$Ctx ncmoe=$Ncmoe rb=$Budget temp0.6 repeats=$Repeats  (唯一变量=KV类型)"
$rQ8=Run-KV 'q8_0' 'q8_0' 'q8_0'
$rQ4=Run-KV 'q4_0' 'q4_0' 'q4_0'

Write-Host "`n`n================ SUMMARY ================"
Write-Host ("{0,-12}| {1,-10}| {2,-10}" -f 'Question','q8_0','q4_0')
Write-Host ('-'*34)
for($i=0;$i-lt$Questions.Count;$i++){
  $a=if($rQ8[$i]){"$($rQ8[$i].avg)%"}else{'na'}
  $b=if($rQ4[$i]){"$($rQ4[$i].avg)%"}else{'na'}
  Write-Host ("{0,-12}| {1,-10}| {2,-10}" -f $Questions[$i].type,$a,$b)
}
$avg8=if($rQ8){[math]::Round(($rQ8|Measure-Object avg -Average).Average,0)}else{'na'}
$avg4=if($rQ4){[math]::Round(($rQ4|Measure-Object avg -Average).Average,0)}else{'na'}
Write-Host ('-'*34)
Write-Host ("{0,-12}| {1,-10}| {2,-10}" -f 'AVERAGE',"$avg8%","$avg4%")
Write-Host "`n[done] KV q8_0 vs q4_0 compare complete"
