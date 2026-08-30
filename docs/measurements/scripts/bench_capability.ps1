#requires -Version 7
<#
.SYNOPSIS
  能力验证 runner（SKILL.md 第 3.3 步 阶段 B）—— agent + 编程题库，可量化打分。
  落地：连本地 server（端口 55555 via start_server），发题，编程题自动跑 test cases，agent 题 checklist 匹配。
  与吞吐扫描分离（能力题输出长度不定，不混 t/s 测量）。reasoning 模型须留够 maxTokens（联动 SKILL.md 2.4）。
  用法：
    .\bench_capability.ps1 -ModelPath F:\...\xxx.gguf -Alias qwen35 -LlamaDir F:\llama-b10488 -ContextSize 32768 -ReasoningBudget 2048 -MaxTokens 8192
    （仅列出题库不跑：-ListOnly）
  扩展题库：在 $AgentQuestions / $CodingQuestions 数组追加 hashtable（见下方结构）。
#>
param(
  [Parameter(Mandatory)][string]$ModelPath,
  [Parameter(Mandatory)][string]$Alias,
  [Parameter(Mandatory)][string]$LlamaDir,
  [int]$ContextSize = 32768,
  [int]$ReasoningBudget = 0,        # 有思考模式时设（联动 2.4）
  [int]$MaxTokens = 4096,           # 能力题须留够（>reasoning_budget+答案）
  [int]$Ncmoe = -1,                 # MoE 卸载（auto 模式据 GGUF）
  [int]$Threads = 0,
  [int]$GpuId = 0,
  [int]$TimeoutSec = 600,
  [switch]$ListOnly
)
. "$PSScriptRoot\start_server.ps1"
$ErrorActionPreference = 'Continue'

# ===========================================================================
# 题库（种子：2 agent + 2 编程；可扩展）
# ===========================================================================

$AgentQuestions = @(
  # 题型1：多步规划（考验分解/约束覆盖/顺序）
  @{
    id = 'agent-plan'
    type = '多步规划'
    prompt = @"
你是项目经理。目标：3 天内组织一场 20 人线下技术沙龙，总预算 5000 元。
约束：①必须含场地/餐饮/讲师礼品 ②餐饮预算≤1500 ③须安排签到与反馈环节 ④须有雨天备选方案。
请给出分步骤执行计划，用编号列出，覆盖所有约束。
"@
    # checklist：每项正则匹配响应即通过 1 项；steps 项要求编号步骤数≥6
    checks = @(
      @{ pat='\d+[.、)]\s'; desc='有编号步骤结构' }
      @{ pat='场地'; desc='含场地' }
      @{ pat='餐'; desc='含餐饮' }
      @{ pat='礼品|纪念'; desc='含讲师礼品' }
      @{ pat='签到'; desc='含签到环节' }
      @{ pat='反馈'; desc='含反馈环节' }
      @{ pat='雨|备选|Plan B|B 计划'; desc='含雨天备选' }
      @{ pat='1500|预算'; desc='含预算约束' }
    )
    minSteps = 6
  },
  # 题型2：工具调用编排（考验编排/顺序/无冗余）
  @{
    id = 'agent-tools'
    type = '工具调用编排'
    prompt = @"
你有这些工具：search(query) 搜索网页；notes(title,content) 存笔记；calc(expr) 计算；sendmail(to,subject,body) 发邮件。
任务：查"ACME 公司"最新财报，算其市盈率，把结果存为笔记"ACME_PE"，并邮件同事张三(pe@x.com)告知结果。
请给出按顺序的工具调用编排，说明每步输入输出，不要实际执行。
"@
    checks = @(
      @{ pat='search'; desc='用 search' }
      @{ pat='calc'; desc='用 calc' }
      @{ pat='notes'; desc='用 notes' }
      @{ pat='sendmail|send_mail'; desc='用 sendmail' }
      @{ pat='张三|pe@x.com'; desc='含收件人' }
      @{ pat='市盈率|PE|p/e'; desc='含市盈率概念' }
    )
    # 顺序检查：search 出现位置 < calc < (notes/sendmail)
    orderCheck = @('search','calc')
  }
)

$CodingQuestions = @(
  # 题型3：算法实现（LRU cache）
  @{
    id = 'code-lru'
    type = '算法实现'
    lang = 'python'
    prompt = @"
实现一个 LRU 缓存类 LRUCache，支持 get(key) 和 put(key,value)：
- 容量 capacity 在构造时给定
- get(key) 返回 value，不存在返回 -1
- put(key,value) 写入；若超容量则淘汰最久未用的
只输出一个 ```python 代码块，含 LRUCache 类，不要写测试。
"@
    # test 代码 append 在模型输出后；exit 0 且 stdout 含 PASS = 通过
    test = @'
c = LRUCache(2)
c.put(1,1); c.put(2,2)
assert c.get(1)==1
c.put(3,3)            # 淘汰 key 2
assert c.get(2)==-1
c.put(4,4)            # 淘汰 key 1
assert c.get(1)==-1
assert c.get(3)==3
assert c.get(4)==4
print("PASS")
'@
  },
  # 题型4：算法实现（有效括号）
  @{
    id = 'code-paren'
    type = '算法实现'
    lang = 'python'
    prompt = @"
实现函数 isValid(s: str) -> bool，判断字符串 s 中的括号 '()[]{}' 是否有效匹配（同类型正确嵌套、空串为 True）。
只输出一个 ```python 代码块，含 isValid 函数，不要写测试。
"@
    test = @'
assert isValid("()")==True
assert isValid("()[]{}")==True
assert isValid("(]")==False
assert isValid("([)]")==False
assert isValid("{[]}")==True
assert isValid("")==True
assert isValid("(")==False
print("PASS")
'@
  }
)

if ($ListOnly) {
  Write-Host "===== 题库清单 =====" -ForegroundColor Yellow
  Write-Host "[Agent 题]"
  $AgentQuestions | ForEach-Object { Write-Host "  $($_.id) [$($_.type)] checks=$($_.checks.Count) minSteps=$($_.minSteps)" }
  Write-Host "[编程题]"
  $CodingQuestions | ForEach-Object { Write-Host "  $($_.id) [$($_.type)] lang=$($_.lang)" }
  return
}

# ===========================================================================
# 判定函数
# ===========================================================================
function Invoke-Checklist {
  param([string]$response, $checks, [int]$minSteps, [string[]]$orderCheck)
  $passed = 0; $total = $checks.Count; $detail = @()
  foreach ($c in $checks) {
    if ($response -match $c.pat) { $passed++; $detail += "  [Y] $($c.desc)" } else { $detail += "  [N] $($c.desc)" }
  }
  if ($minSteps -gt 0) {
    $total++
    $stepCount = ([regex]::Matches($response, '\d+[.、)]\s')).Count
    if ($stepCount -ge $minSteps) { $passed++; $detail += "  [Y] 编号步骤数=$stepCount ≥ $minSteps" }
    else { $detail += "  [N] 编号步骤数=$stepCount < $minSteps" }
  }
  if ($orderCheck -and $orderCheck.Count -ge 2) {
    $total++
    $positions = $orderCheck | ForEach-Object { $idx = $response.IndexOf($_); if ($idx -lt 0) { [int]::MaxValue } else { $idx } }
    $ordered = $true
    for ($i=1; $i -lt $positions.Count; $i++) { if ($positions[$i] -lt $positions[$i-1]) { $ordered = $false } }
    if ($ordered -and ($positions[0] -ne [int]::MaxValue)) { $passed++; $detail += "  [Y] 顺序 $($orderCheck -join '→') 正确" }
    else { $detail += "  [N] 顺序 $($orderCheck -join '→') 不正确或缺失" }
  }
  $score = if ($total -gt 0) { [math]::Round($passed * 100 / $total, 0) } else { 0 }
  return @{ passed=$passed; total=$total; score=$score; detail=$detail }
}

function Test-CodingAnswer {
  param([string]$response, [string]$testCode, [string]$lang='python')
  # 提取第一个 ```python 代码块
  $m = [regex]::Match($response, '```(?:python|py)?\s*\n(.*?)```', [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if (-not $m.Success) { return @{ ok=$false; reason='未找到 ```python 代码块' } }
  $code = $m.Groups[1].Value
  $tmp = [System.IO.Path]::GetTempFileName() + '.py'
  try {
    [System.IO.File]::WriteAllText($tmp, $code + "`n" + $testCode, [System.Text.Encoding]::UTF8)
    $pyExe = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $pyExe) { $pyExe = (Get-Command py -ErrorAction SilentlyContinue).Source }
    if (-not $pyExe) { return @{ ok=$false; reason='python 不可用（PATH 无 python/py），编程题无法自动校验' } }
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $pyExe; $pinfo.Arguments = "`"$tmp`""
    $pinfo.UseShellExecute = $false; $pinfo.RedirectStandardOutput = $true; $pinfo.RedirectStandardError = $true
    $proc = New-Object System.Diagnostics.Process; $proc.StartInfo = $pinfo
    $proc.Start() | Out-Null
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    if (-not $proc.WaitForExit(30000)) { try { $proc.Kill() } catch {}; return @{ ok=$false; reason='test 执行超时(30s)' } }
    if ($proc.ExitCode -eq 0 -and $stdout -match 'PASS') { return @{ ok=$true; reason="test PASS" } }
    else { return @{ ok=$false; reason="test 失败 exit=$($proc.ExitCode); stderr: $(($stderr -split "`n")[0..2] -join ' | ')" } }
  } finally { if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } }
}

# ===========================================================================
# 主流程：启动 server → 跑题库 → 打分 → 停 server
# ===========================================================================
Write-Host "===== bench_capability: $ModelPath alias=$Alias ctx=$ContextSize rb=$ReasoningBudget maxTok=$MaxTokens =====" -ForegroundColor Yellow
$sp = $null
$results = @()
try {
  $sp = Start-LlamaServer -ModelPath $ModelPath -Alias $Alias -LlamaDir $LlamaDir -ContextSize $ContextSize -ReasoningBudget $ReasoningBudget -Ncmoe $Ncmoe -Threads $Threads -GpuId $GpuId
  Write-Host "[server] applied_ctx=$($sp.ctx) isMoE=$($sp.meta.isMoE)"

  # agent 题
  foreach ($q in $AgentQuestions) {
    Write-Host "`n----- [$($q.id)] $($q.type) -----" -ForegroundColor Cyan
    $body = @{ model=$Alias; messages=@(@{ role='user'; content=$q.prompt }); max_tokens=$MaxTokens; temperature=0.6; top_k=20; top_p=0.95; min_p=0.0 } | ConvertTo-Json -Depth 5
    try {
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $r = Invoke-RestMethod -Uri "http://127.0.0.1:$($sp.port)/v1/chat/completions" -Method Post -Headers $sp.headers -Body $body -TimeoutSec $TimeoutSec
      $sw.Stop()
      $resp = $r.choices[0].message.content
      $ck = Invoke-Checklist -response $resp -checks $q.checks -minSteps $q.minSteps -orderCheck $q.orderCheck
      Write-Host "  gen=$($r.usage.completion_tokens)t wall=$([math]::Round($sw.Elapsed.TotalSeconds,1))s 打分=$($ck.score)% ($($ck.passed)/$($ck.total))"
      $ck.detail | ForEach-Object { Write-Host $_ }
      $results += @{ id=$q.id; type=$q.type; score=$ck.score; passed=$ck.passed; total=$ck.total; tokens=$r.usage.completion_tokens; respHead=($resp.Substring(0,[math]::Min(200,$resp.Length))+'...') }
    } catch {
      Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
      $results += @{ id=$q.id; type=$q.type; score=0; passed=0; total=$q.checks.Count; error=$_.Exception.Message }
    }
  }

  # 编程题
  foreach ($q in $CodingQuestions) {
    Write-Host "`n----- [$($q.id)] $($q.type) -----" -ForegroundColor Cyan
    $body = @{ model=$Alias; messages=@(@{ role='user'; content=$q.prompt }); max_tokens=$MaxTokens; temperature=0.2; top_k=20; top_p=0.95; min_p=0.0 } | ConvertTo-Json -Depth 5
    try {
      $r = Invoke-RestMethod -Uri "http://127.0.0.1:$($sp.port)/v1/chat/completions" -Method Post -Headers $sp.headers -Body $body -TimeoutSec $TimeoutSec
      $resp = $r.choices[0].message.content
      $t = Test-CodingAnswer -response $resp -testCode $q.test -lang $q.lang
      if ($t.ok) { Write-Host "  gen=$($r.usage.completion_tokens)t 判定=PASS（$($t.reason)）" -ForegroundColor Green }
      else { Write-Host "  gen=$($r.usage.completion_tokens)t 判定=FAIL（$($t.reason)）" -ForegroundColor Red }
      $results += @{ id=$q.id; type=$q.type; pass=$t.ok; reason=$t.reason; tokens=$r.usage.completion_tokens }
    } catch {
      Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
      $results += @{ id=$q.id; type=$q.type; pass=$false; error=$_.Exception.Message }
    }
  }
} catch {
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
} finally {
  if ($sp) { try { Stop-LlamaServer $sp } catch {} }
}

# ===========================================================================
# 汇总
# ===========================================================================
Write-Host "`n===== 能力验证汇总 =====" -ForegroundColor Yellow
Write-Host "题目ID        | 类型       | 判定        | 分数/通过"
Write-Host "-------------|------------|-------------|----------"
foreach ($res in $results) {
  if ($res.type -eq '算法实现') {
    $verdict = if ($res.pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0,-13}| {1,-11}| {2,-12}| {3}" -f $res.id, $res.type, $verdict, $res.reason)
  } else {
    Write-Host ("{0,-13}| {1,-11}| {2,-12}| {3}% ({4}/{5})" -f $res.id, $res.type, 'CHECKLIST', $res.score, $res.passed, $res.total)
  }
}
$agentAvg = if (($results | Where-Object { $_.type -ne '算法实现' } | Measure-Object score -Average).Average) { [math]::Round(($_.Average),0) } else { 0 }
$codePass = ($results | Where-Object { $_.type -eq '算法实现' -and $_.pass }).Count
$codeTotal = ($results | Where-Object { $_.type -eq '算法实现' }).Count
Write-Host "`n[总结] agent 题平均分=$agentAvg% | 编程题通过=$codePass/$codeTotal" -ForegroundColor Yellow
Write-Host "===== bench_capability done =====" -ForegroundColor Yellow
