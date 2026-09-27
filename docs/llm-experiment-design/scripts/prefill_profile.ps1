#requires -Version 7
<#
.SYNOPSIS
  分段 prefill 降级剖析（staged prefill profile）—— 精确定位"从多深开始不可用"。
  动机：全量深填充是 all-or-nothing（超时只知道"不可用"，不知道拐点在哪）。
  方法：固定 (KV, ctx) 与 -ncmoe，按 ~16K tokens 为一档逐步加深对话（前缀复用），
        每档记录该档增量 prefill 的 pps / prompt_n / 墙钟；pps 掉到阈值以下即判定拐点。
  判据：健康档取"同模型短 ctx 首档"作参照；某档 pps 相对参照明显掉档 = 该深度不可用（阈值参数 -PpsFloor）。
        每档还要读一次 shared（KV 溢出物理信号）。
  用途：给出"最大可用上下文 = 生成速度可接受 且 prefill 可接受"的深度边界（SKILL reference/04-context.md）。
#>
param(
  [Parameter(Mandatory)][string]$ModelPath,
  [string]$LlamaDir='',            # 空 = 取 $env:LLAMA_CPP_DIR
  [string]$Alias='model',
  [int]$Ncmoe=0, [int]$Ctx=98304, [string]$Kv='q8_0',
  [int]$StageTokens=16000, [int]$ReasoningBudget=0, [int]$GpuId=0,
  [int]$Threads=0,
  [double]$PpsFloor=300,
  [string]$FillTextPath='',  # 空 = 用内置合成语料自动生成
  [string]$WorkDir=''          # 空 = 取 $env:DSH_WORK_DIR，否则当前目录
)
$ErrorActionPreference='Continue'
. (Join-Path $PSScriptRoot 'start_server.ps1')
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
# SKILL 硬规则：思考预算 = 上下文的一半（未显式指定时自动取）
if ($ReasoningBudget -le 0) { $ReasoningBudget = [int]($Ctx / 2) }
$fillText = Get-FillText -FillTextPath $FillTextPath -TargetTokens 4000

Write-Host "===== PREFILL PROFILE $Alias ncmoe=$Ncmoe kv=$Kv ctx=$Ctx stage=$StageTokens =====" -ForegroundColor Yellow
$s=$null
try{
  $s=Start-LlamaServer -ModelPath $ModelPath -Alias $Alias -LlamaDir $LlamaDir -Ngl 99 -ContextSize $Ctx `
     -CacheTypeK $Kv -CacheTypeV $Kv -Fa 'on' -MoeMode $(if($Ncmoe -gt 0){'ncmoe'}else{'none'}) -Ncmoe $Ncmoe `
     -ReasoningBudget $ReasoningBudget -Threads $Threads -GpuId $GpuId -SkipHelpCheck
  Write-Host "idle: $(Get-Vram -GpuId $GpuId)  applied_ctx=$($s.ctx)"
  $target = $Ctx - 8000
  $msgs=@(); $depth=0; $blk=0; $stop=$false
  while(-not $stop -and $depth -lt $target){
    # append one stage worth of filler (user短问 + assistant长答 ≈ 4.5k tokens each pair)
    $pairs=[math]::Max(1,[math]::Ceiling($StageTokens/4500))
    for($i=1;$i-le $pairs;$i++){
      $blk++
      $msgs+=@{role='user';content="Please provide a detailed explanation of topic number $blk, covering background, history, current state and future outlook. Write as much detail as possible."}
      $msgs+=@{role='assistant';content="Here is my detailed explanation of topic $blk : $fillText"}
    }
    $msgs+=@{role='user';content='Reply with exactly one short sentence summarizing the last topic.'}
    $body=@{model=$Alias;messages=$msgs;max_tokens=24;temperature=1.0;top_k=20;top_p=0.95;min_p=0.0}|ConvertTo-Json -Depth 8
    $sw=[System.Diagnostics.Stopwatch]::StartNew()
    try{
      $r=Invoke-RestMethod -Uri "http://127.0.0.1:$($s.port)/v1/chat/completions" -Method Post -Headers $s.headers -Body $body -TimeoutSec 900
      $sw.Stop(); $t=$r.timings
      $depth += [int]$t.prompt_n      # prompt_n 是增量（前缀复用），累计得真实深度
      $vram=Get-Vram -GpuId $GpuId
      $sh=0; if($vram -match 'shared=(\d+)'){ $sh=[int]$matches[1] }
      $flag = if($t.prompt_per_second -lt $PpsFloor){' <== PREFILL 掉档(不可用)'} else {''}
      Write-Host ("stage depth={0,7}t inc={1,6}t pps={2,7} prompt_ms={3,8} wall={4,6}s shared={5,5}MB eval={6}/s{7}" -f `
        $depth,$t.prompt_n,[math]::Round($t.prompt_per_second,1),$t.prompt_ms,[math]::Round($sw.Elapsed.TotalSeconds,1),$sh,[math]::Round($t.predicted_per_second,1),$flag)
      # drop the trailing probe question so the next stage appends cleanly
      $msgs=$msgs[0..($msgs.Count-2)]
      if($t.prompt_per_second -lt $PpsFloor){ $stop=$true }
    }catch{
      $sw.Stop()
      Write-Host ("stage ERROR after {0}s: {1}" -f [math]::Round($sw.Elapsed.TotalSeconds,1),$_.Exception.Message) -ForegroundColor Red
      $stop=$true
    }
  }
  Write-Host "final depth reached = $depth t (target $target)" -ForegroundColor Yellow
}catch{ Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red }
finally{ Stop-LlamaServer $s; Start-Sleep 1 }
Write-Host "[done] prefill profile $Alias $Kv ctx=$Ctx" -ForegroundColor Yellow
