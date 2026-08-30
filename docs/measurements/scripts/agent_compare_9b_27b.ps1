#requires -Version 7
<#
.SYNOPSIS
  Fair agent-ability comparison: Qwen3.5-9B (Q6_K) vs Qwen3.8-27B (IQ3_XXS).
  Same arch (qwen35), same context (32768), same KV (q4_0), same sampling
  (temp 0.6/topk 20/topp 0.95/minp 0/repeat 1/presence 0), same reasoning-budget 2048.
  6 agent questions, each run 2x, score = checklist hit-rate. Only variable = model.
#>
param(
  [string]$LlamaDir = 'F:\llama-b10488-bin-win-cuda-13.3-x64',
  [int]$Ctx = 32768,
  [int]$Budget = 2048,
  [int]$MaxTokens = 8192,
  [int]$GpuId = 0,
  [int]$Repeats = 2
)
$ErrorActionPreference = 'Continue'
. 'D:\DSH\WORK1\llama.cpp\scripts\start_server.ps1'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Model9B  = 'F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.5-9B\Qwen3.5-9B-Q6_K.gguf'
$Model27B = 'F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.8-27B\Qwen3.8-27B-UD-IQ3_XXS.gguf'

# ---- 6 agent questions (shared by both models) ----
$LongDocA = @"
【公司员工档案】
名字：王强，部门：销售部，入职年份：2021，项目经历：参与过B项目，未参与A项目。
名字：李梅，部门：技术部，入职年份：2019，项目经历：负责过A项目，担任技术负责人。
名字：赵成，部门：市场部，入职年份：2022，项目经历：参与过B项目。
名字：孙丽，部门：技术部，入职年份：2020，项目经历：参与过A项目，作为核心成员。
名字：周涛，部门：销售部，入职年份：2018，项目经历：负责过A项目。
【问题】哪位员工同时满足：a) 入职满3年；b) 不在销售部；c) 负责过A项目？请给出姓名，并说明每条线索依据。
"@

$BuggyCode = @"
以下是一段有 bug 的 LRU 缓存实现（Python）。缓存容量 capacity=2。
它的问题是：get() 在缓存未命中且缓存已满时，会错误地把新读到的 key 放进缓存并淘汰旧项，
导致 get 操作改变了缓存状态，违反了「get 不应改变缓存内容」的语义。
def get(key):
    if key in cache:
        return cache[key]
    else:
        return -1

请：
1) 指出上述 bug（get 改变了缓存状态）；
2) 给出「正确」的 LRU 实现（put 才淘汰，get 命中时才提升最近使用序）；
3) 一句话说明修正原理。
"@

$AgentQuestions = @(
  @{
    id='q1-plan-event'; type='多步规划'
    prompt=@"
你是项目经理。目标：3 天内组织一场 20 人线下技术沙龙，总预算 5000 元。
约束：①必须含场地/餐饮/讲师礼品 ②餐饮预算≤1500 ③须安排签到与反馈环节 ④须有雨天备选方案。
请给出分步骤执行计划，用编号列出，覆盖所有约束。
"@
    checks=@(
      @{pat='\d+[.、)]\s';desc='编号步骤'}
      @{pat='场地';desc='含场地'}
      @{pat='餐';desc='含餐饮'}
      @{pat='礼品|纪念';desc='含礼品'}
      @{pat='签到';desc='含签到'}
      @{pat='反馈';desc='含反馈'}
      @{pat='雨|备选|Plan B|B 计划';desc='雨天备选'}
      @{pat='1500|预算';desc='预算约束'}
    ); minSteps=6
  },
  @{
    id='q2-plan-launch'; type='多步规划'
    prompt=@"
一个 SaaS 产品计划 5 天后上线，但昨天核心数据库出现性能告警。
约束：①必须先定位数据库瓶颈 ②上线前须完成压测 ③须给客户准备回滚预案 ④上线窗口只能选工作日夜间 1 点。
请给出分步骤行动计划，编号列出，覆盖所有约束。
"@
    checks=@(
      @{pat='\d+[.、)]\s';desc='编号步骤'}
      @{pat='数据库|瓶颈|索引|慢查询';desc='定位数据库瓶颈'}
      @{pat='压测|压力测试|性能测试';desc='压测'}
      @{pat='回滚|回退|rollback';desc='回滚预案'}
      @{pat='夜间|凌晨|1 ?点|01:00';desc='夜间窗口'}
      @{pat='工作日';desc='工作日'}
      @{pat='上线';desc='上线'}
    ); minSteps=6
  },
  @{
    id='q3-tools'; type='工具调用编排'
    prompt=@"
你有这些工具：search(query) 搜索网页；notes(title,content) 存笔记；calc(expr) 计算；sendmail(to,subject,body) 发邮件。
任务：查"ACME 公司"最新财报，算其市盈率，把结果存为笔记"ACME_PE"，并邮件同事张三(pe@x.com)告知结果。
请给出按顺序的工具调用编排，说明每步输入输出，不要实际执行。
"@
    checks=@(
      @{pat='search';desc='search'}
      @{pat='calc';desc='calc'}
      @{pat='notes';desc='notes'}
      @{pat='send_mail|sendmail';desc='sendmail'}
      @{pat='张三|pe@x.com';desc='收件人'}
      @{pat='市盈率|PE|P/E';desc='市盈率'}
    ); orderCheck=@('search','calc')
  },
  @{
    id='q4-longdoc'; type='长程依赖推理'
    prompt=$LongDocA
    checks=@(
      @{pat='李梅|孙丽|李|孙';desc='点出技术部员工'}
      @{pat='李梅';desc='点出李梅'}
      @{pat='不在销售|非销售|技术部';desc='排除销售部'}
      @{pat='满3年|3年|2020|2019|2018';desc='入职满3年依据'}
      @{pat='A项目';desc='负责过A项目'}
      @{pat='销售部|王强|周涛';desc='排除销售部人'}
    ); minSteps=0
  },
  @{
    id='q5-debug'; type='自我纠错'
    prompt=$BuggyCode
    checks=@(
      @{pat='get|读取';desc='提到get'}
      @{pat='改变|状态|不该|不应该|语义';desc='指出get改状态bug'}
      @{pat='put|写';desc='给出正确方案'}
      @{pat='淘汰|LRU|最近|用';desc='正确的LRU淘汰'}
      @{pat='原理|因为|所以|目的是';desc='说明原理'}
    ); minSteps=0
  },
  @{
    id='q6-pool'; type='逻辑数值推理'
    prompt=@"
水池问题：A管6小时注满，B管8小时注满，C管12小时排空。三管同开几小时注满？
请给出推理过程，最后单独一行写答案。
"@
    checks=@(
      @{pat='1/6|16|0\.16|1/8|18';desc='用到速率'}
      @{pat='4\.8|4\.8小时|4 小时 48|24/5';desc='答案4.8'}
      @{pat='4\.8|4.8小时|24/5|4小时48';desc='答案行'}
    ); minSteps=0
  }
)

# ---- checklist scoring ----
function Invoke-Checklist {
  param([string]$response, $checks, [int]$minSteps, [string[]]$orderCheck)
  $passed=0;$total=$checks.Count;$detail=@()
  foreach($c in $checks){ if($response -match $c.pat){$passed++;$detail+="  [Y] $($c.desc)"}else{$detail+="  [N] $($c.desc)"} }
  if($minSteps -gt 0){ $total++; $n=([regex]::Matches($response,'\d+[.、)]\s')).Count; if($n-ge$minSteps){$passed++;$detail+="  [Y] 步骤$n≥$minSteps"}else{$detail+="  [N] 步骤$n<$minSteps"} }
  if($orderCheck -and $orderCheck.Count-ge2){ $total++; $pos=$orderCheck|ForEach-Object{$i=$response.IndexOf($_);if($i-lt0){[int]::MaxValue}else{$i}}; $ok=$true; for($i=1;$i-lt$pos.Count;$i++){if($pos[$i]-lt$pos[$i-1]){$ok=$false}}; if($ok-and($pos[0]-ne[int]::MaxValue)){$passed++;$detail+="  [Y] 顺序 $($orderCheck-join'→')"}else{$detail+="  [N] 顺序不正确"} }
  $score=if($total-gt0){[math]::Round($passed*100/$total,0)}else{0}
  return @{passed=$passed;total=$total;score=$score;detail=$detail}
}

function Run-Model {
  param([string]$Model, [string]$Label, $ModelPath)
  $results = @()
  $server = $null
  try {
    $server = Start-LlamaServer -ModelPath $ModelPath -Alias $Label -LlamaDir $LlamaDir `
      -Ngl 99 -ContextSize $Ctx -CacheTypeK 'q4_0' -CacheTypeV 'q4_0' -Fa 'on' -MoeMode 'none' `
      -ReasoningBudget $Budget -Threads 20 -ThreadsBatch 20 -SkipHelpCheck
    Write-Host "`n======== [server up] $Label ctx=$($server.ctx) ========"
    $warm = Invoke-Short -server $server -NPredict 16
    foreach($q in $AgentQuestions){
      $scores=@(); $details=@(); $tokens=@()
      for($r=1;$r-le$Repeats;$r++){
        $body=@{ model=$Label; messages=@(@{role='user';content=$q.prompt}); max_tokens=$MaxTokens; temperature=0.6; top_k=20; top_p=0.95; min_p=0.0 } | ConvertTo-Json -Depth 5
        try{
          $resp=Invoke-RestMethod -Uri "http://127.0.0.1:$($server.port)/v1/chat/completions" -Method Post -Headers $server.headers -Body $body -TimeoutSec 600
          $out=$resp.choices[0].message.content
          $ck=Invoke-Checklist -response $out -checks $q.checks -minSteps $q.minSteps -orderCheck $q.orderCheck
          $scores+=$ck.score; $tokens+=$resp.usage.completion_tokens
          if($r-eq1){$details=$ck.detail}
        }catch{$scores+=0; $tokens+=0; $details+=("  ERR: "+$_.Exception.Message)}
      }
      $avg=if($scores.Count){[math]::Round(($scores|Measure-Object -Average).Average,0)}else{0}
      $results+=@{id=$q.id;type=$q.type;avg=$avg;scores=($scores-join'/');tokens=($tokens-join'/');detail=$details}
      Write-Host ("[$Label] {0,-16} avg={1}%  runs=[{2}]  tok=[{3}]" -f $q.id,$avg,($scores-join'/'),($tokens-join'/'))
    }
  } catch { Write-Host "[$Label] FATAL: $($_.Exception.Message)" }
  finally { Stop-LlamaServer $server }
  return $results
}

Write-Host "================ AGENT COMPARE: 9B-Q6 vs 27B-Q3 ================"
Write-Host "config: ctx=$Ctx kv=q4_0 ngl=99 rb=$Budget temp0.6/topk20/topp0.95/minp0/repeat1/presence0  repeats=$Repeats"
$r9  = Run-Model -Model 'qwen35-9b'  -Label 'qwen35-9b'  -ModelPath $Model9B
$r27 = Run-Model -Model 'qwen38-27b' -Label 'qwen38-27b' -ModelPath $Model27B

Write-Host "`n`n================ SUMMARY ================"
Write-Host ("{0,-16}| {1,-12}| {2,-12}" -f 'Question','9B-Q6','27B-Q3')
Write-Host ('-'*46)
for($i=0;$i-lt$AgentQuestions.Count;$i++){
  $t=$AgentQuestions[$i].type
  $a=if($r9[$i]){$r9[$i].avg}else{'na'}
  $b=if($r27[$i]){$r27[$i].avg}else{'na'}
  Write-Host ("{0,-16}| {1,-12}| {2,-12}" -f $t,$a,$b)
}
$avg9=if($r9){[math]::Round(($r9|Measure-Object avg -Average).Average,0)}else{'na'}
$avg27=if($r27){[math]::Round(($r27|Measure-Object avg -Average).Average,0)}else{'na'}
Write-Host ('-'*46)
Write-Host ("{0,-16}| {1,-12}| {2,-12}" -f 'AVERAGE',"$avg9%","$avg27%")
Write-Host "`n[done] agent compare complete"
