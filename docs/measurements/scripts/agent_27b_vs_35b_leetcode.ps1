#requires -Version 7
<#
.SYNOPSIS
  LeetCode-style HARD algorithm compare: 27B vs 35B.
  Uses lc_harness.py (reference-verified, objective) to grade model-generated code.
  Covers correctness across 30 random + 1 large case per problem, plus LFU state correctness.
#>
param(
  [string]$LlamaDir = 'F:\llama-b10488-bin-win-cuda-13.3-x64',
  [int]$Ctx = 32768, [int]$Budget = 2048, [int]$MaxTokens = 8192, [int]$Ncmoe35B = 20
)
$ErrorActionPreference = 'Continue'
. 'D:\DSH\WORK1\llama.cpp\scripts\start_server.ps1'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Model27B = 'F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.8-27B\Qwen3.8-27B-UD-IQ3_XXS.gguf'
$Model35B = 'F:\llama-b10488-bin-win-cuda-13.3-x64\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf'
$Harness = 'D:\DSH\WORK1\llama.cpp\scripts\lc_harness.py'

function Invoke-Harness($code){
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName='python'; $psi.Arguments="`"$Harness`""
  $psi.UseShellExecute=$false; $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
  $p=New-Object Diagnostics.Process; $p.StartInfo=$psi; $p.Start()|Out-Null
  $p.StandardInput.Write($code); $p.StandardInput.Close()
  $out=$p.StandardOutput.ReadToEnd(); $err=$p.StandardError.ReadToEnd()
  $p.WaitForExit(60000)
  return @{out=$out;err=$err}
}

$qs = @(
  @{ id='L1-merge-intervals'; desc='合并区间'; prompt=@"
实现函数 merge(intervals: list[list[int]]) -> list[list[int]]。
合并规则（LeetCode 56 标准）：仅当两个区间**重叠或相接**（后一个的 start ≤ 前一个的 end）时合并；两个区间之间若**有空隙**（start > 前一个的 end），则**不合并**，保留为两个区间。返回按起点升序。

示例：
- merge([[1,3],[2,6],[8,10],[15,18]]) = [[1,6],[8,10],[15,18]]
- merge([[1,4],[4,5]]) = [[1,5]]   # 相接(4≤4)，合并
- merge([[1,4],[5,6]]) = [[1,4],[5,6]]   # 有空隙(5>4)，不合并

只输出一个 ```python 代码块，含 merge 函数，不要写测试。
"@ },
  @{ id='L2-trapping-rain'; desc='接雨水'; prompt=@"
实现函数 trap(height: list[int]) -> int，计算能接住的雨水总量。height[i] 是位置 i 的高度。

示例：trap([0,1,0,2,1,0,1,3,2,1,2,1]) = 6
要求 O(n) 时间。
只输出一个 ```python 代码块，含 trap 函数，不要写测试。
"@ },
  @{ id='L3-lfu-cache'; desc='LFU缓存'; prompt=@"
实现 LFUCache 类，构造传入 capacity，含 get(key) 和 put(key,value)：
- get(key)：命中返回 value 并递增该 key 的频率；未命中返回 -1
- put(key,value)：若 key 已存在则更新 value、递增频率；若缓存已满，先淘汰**频率最低**的 key；频率相同则淘汰**最久未使用**（LRU 次序）的 key
- 缓存容量 capacity 为 0 时，get 返回 -1，put 不存任何值
只输出一个 ```python 代码块，含 LFUCache 类（含 get/put），不要写测试。
"@ }
)

function Run-Model($ModelPath,$Label,$MoeMode,$Ncmoe){
  $s=$null;$res=@()
  try{
    $s=Start-LlamaServer -ModelPath $ModelPath -Alias $Label -LlamaDir $LlamaDir -Ngl 99 -ContextSize $Ctx -CacheTypeK 'q4_0' -CacheTypeV 'q4_0' -Fa 'on' -MoeMode $MoeMode -Ncmoe $Ncmoe -ReasoningBudget $Budget -Threads 20 -ThreadsBatch 20 -SkipHelpCheck
    Write-Host "`n======== [up] $Label ========"
    $w=Invoke-Short -server $s -NPredict 16
    foreach($q in $qs){
      $body=@{model=$Label;messages=@(@{role='user';content=$q.prompt});max_tokens=$MaxTokens;temperature=0.2;top_k=20;top_p=0.95;min_p=0.0}|ConvertTo-Json -Depth 5
      try{
        $r=Invoke-RestMethod -Uri "http://127.0.0.1:$($s.port)/v1/chat/completions" -Method Post -Headers $s.headers -Body $body -TimeoutSec 600
        $out=$r.choices[0].message.content
        $m=[regex]::Match($out,'```(?:python|py)?\s*\n(.*?)```',[Text.RegularExpressions.RegexOptions]::Singleline)
        $code=if($m.Success){$m.Groups[1].Value}else{$out}
        $h=Invoke-Harness $code
        $ok = $h.out -match '"ok":\s*true'
        Write-Host ("[{0}] {1,-20} {2}  tok={3}" -f $Label,$q.id,$(if($ok){'PASS'}else{'FAIL'}),$r.usage.completion_tokens)
        $dt = if($h.out -match '"large_time":\s*([0-9.]+)'){ "ls:"+$matches[1]+"s" } else { '' }
        Write-Host "    -> $dt  $(if($h.err){'err:'+$h.err.Substring(0,[math]::Min(90,$h.err.Length))}else{''})"
        if(-not $ok){ $det=[regex]::Match($h.out,'"details":\s*(\{.*\})').Groups[1].Value; Write-Host "    details: $($det.Substring(0,[math]::Min(160,$det.Length)))" }
        $res+=@{id=$q.id;ok=$ok;out=$h.out}
      }catch{Write-Host "[$Label] $($q.id) ERR: $($_.Exception.Message)";$res+=@{id=$q.id;ok=$false;out=$_.Exception.Message}}
    }
  }catch{Write-Host "[$Label] FATAL: $($_.Exception.Message)"}
  finally{Stop-LlamaServer $s}
  return $res
}

Write-Host "================ 27B vs 35B LeetCode-HARD (auto verify) ================"
Write-Host "config: ctx=$Ctx ngl99 q4_0 rb=$Budget  (35B -ncmoe $Ncmoe35B)"
$r27=Run-Model $Model27B 'qwen38-27b' 'none' -1
$r35=Run-Model $Model35B 'qwen36-35b' 'ncmoe' $Ncmoe35B

Write-Host "`n================ SUMMARY ================"
Write-Host ("{0,-20}| {1,-9}| {2,-9}" -f 'Problem','27B-Q3','35B-ncmoe20')
Write-Host ('-'*40)
for($i=0;$i-lt$qs.Count;$i++){
  Write-Host ("{0,-20}| {1,-9}| {2,-9}" -f $qs[$i].id,$(if($r27[$i].ok){'PASS'}else{'FAIL'}),$(if($r35[$i].ok){'PASS'}else{'FAIL'}))
}
$p27=($r27|Where-Object ok).Count;$t27=$r27.Count
$p35=($r35|Where-Object ok).Count;$t35=$r35.Count
Write-Host ('-'*40)
Write-Host ("{0,-20}| {1,-9}| {2,-9}" -f 'TOTAL',"$p27/$t27","$p35/$t35")
Write-Host "[done] leetcode hard compare complete"
