#requires -Version 7
<#
.SYNOPSIS
  GGUF 运行时探查（第 0 步，reference/00-probe.md）—— 判定门的唯一依据来源。
  输出：架构 / 层数 / 专家数 / KV 头数与维度 / 原生上下文 / full_attention_interval /
        派生量（isMoE、KV 层数、KV/token、每层权重、每层 KV 的 ctx 边际成本）/
        能力标记（是否含思考模板、是否含 MTP(nextn) 张量、是否含视觉投影器）。
  用法： .\gguf_probe.ps1 -Path <你的.gguf> [-Json]
  不预设模型规模：所有数值都从文件本身读出或由元数据算出。
#>
param(
  [Parameter(Mandatory)][string]$Path,
  [switch]$Json
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Path)) { throw "GGUF not found: $Path" }

$WANT = @('architecture','block_count','expert_count','expert_used_count','head_count','head_count_kv',
          'key_length','value_length','context_length','full_attention_interval','rope_freq_base',
          'rope_scaling_type','embedding_length','nextn_predict_layers','clip.has_vision_encoder')

$fs = [System.IO.File]::OpenRead($Path)
$meta = [ordered]@{}
$tensorNames = [System.Collections.Generic.List[string]]::new()
try {
  $br = New-Object System.IO.BinaryReader($fs)
  $magic = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
  if ($magic -ne 'GGUF') { throw "不是 GGUF 文件（magic=$magic）" }
  $ver = $br.ReadUInt32()
  $tensorCount = $br.ReadUInt64()
  $kvCount = $br.ReadUInt64()

  function Read-Str($r) { $n = $r.ReadUInt64(); return [System.Text.Encoding]::UTF8.GetString($r.ReadBytes([int]$n)) }
  function Skip-Val($r, [int]$t) {
    switch ($t) {
      0 { [void]$r.ReadByte() }   1 { [void]$r.ReadSByte() }  2 { [void]$r.ReadUInt16() }
      3 { [void]$r.ReadInt16() }  4 { [void]$r.ReadUInt32() } 5 { [void]$r.ReadInt32() }
      6 { [void]$r.ReadSingle() } 7 { [void]$r.ReadByte() }   8 { [void](Read-Str $r) }
      10 { [void]$r.ReadUInt64() } 11 { [void]$r.ReadInt64() } 12 { [void]$r.ReadDouble() }
      9 {
        $et = [int]$r.ReadUInt32(); $cnt = [long]$r.ReadUInt64()
        $step = switch ($et) { 0 {1} 1 {1} 2 {2} 3 {2} 4 {4} 5 {4} 6 {4} 7 {1} 10 {8} 11 {8} 12 {8} default {-1} }
        if ($et -eq 8) { for ($i=0; $i -lt $cnt; $i++) { $l=[long]$r.ReadUInt64(); [void]$r.ReadBytes([int]$l) } }
        elseif ($step -gt 0) { [void]$r.BaseStream.Seek($cnt*$step,'Current') }
        else { for ($i=0; $i -lt $cnt; $i++) { Skip-Val $r $et } }
      }
      default { throw "unknown gguf type $t" }
    }
  }
  function Read-Val($r, [int]$t) {
    switch ($t) {
      0 { return $r.ReadByte() }   1 { return $r.ReadSByte() }  2 { return $r.ReadUInt16() }
      3 { return $r.ReadInt16() }  4 { return $r.ReadUInt32() } 5 { return $r.ReadInt32() }
      6 { return $r.ReadSingle() } 7 { return $r.ReadByte() }   8 { return (Read-Str $r) }
      10 { return $r.ReadUInt64() } 11 { return $r.ReadInt64() } 12 { return $r.ReadDouble() }
      9 { Skip-Val $r $t; return $null }
      default { throw "unknown gguf type $t" }
    }
  }

  for ($i = 0; $i -lt $kvCount; $i++) {
    $key = Read-Str $br
    $type = [int]$br.ReadUInt32()
    $base = ($key -split '\.')[-1]
    if ($WANT -contains $base) {
      $v = Read-Val $br $type
      if ($null -ne $v) { $meta[$base] = $v }
    } elseif ($base -eq 'tokenizer.chat_template' -or $key -like '*chat_template*') {
      $v = Read-Val $br $type
      if ($v -is [string]) { $meta['chat_template_len'] = $v.Length; $meta['chat_template_has_thinking'] = ($v -match 'enable_thinking|thinking') }
    } else {
      Skip-Val $br $type
    }
  }
  # 张量名扫描：能力标记（MTP / 视觉）只能从张量名判定
  for ($i = 0; $i -lt $tensorCount; $i++) {
    $tn = Read-Str $br
    $tensorNames.Add($tn)
    $nd = [int]$br.ReadUInt32()
    [void]$br.ReadBytes(8 * $nd)      # dims (uint64 each)
    [void]$br.ReadUInt32()            # ggml type
    [void]$br.ReadUInt64()            # offset
  }
}
finally { $fs.Dispose() }

# ---- 派生量（不查表、不写死）----
$arch     = "$($meta['architecture'])"
$blocks   = [int]($meta['block_count'])
$experts  = [int]($meta['expert_count'])
$isMoE    = $experts -gt 0
$interval = if ($meta.Contains('full_attention_interval')) { [int]$meta['full_attention_interval'] } else { 1 }
if ($interval -lt 1) { $interval = 1 }
$kvLayers = [int][math]::Ceiling($blocks / $interval)
$hk       = if ($meta.Contains('head_count_kv')) { [int]$meta['head_count_kv'] } else { 0 }
$kl       = if ($meta.Contains('key_length'))    { [int]$meta['key_length'] }    else { 0 }
$vl       = if ($meta.Contains('value_length'))  { [int]$meta['value_length'] }  else { $kl }
$kvBytesF16 = $kvLayers * $hk * ($kl + $vl) * 2
$sizeMB     = [math]::Round((Get-Item $Path).Length / 1MB, 1)
$perLayerMB = if ($blocks -gt 0) { [math]::Round($sizeMB / $blocks, 1) } else { 0 }
$hasMTP     = ($tensorNames | Where-Object { $_ -match '\.nextn\.' } | Select-Object -First 1) -ne $null
$hasVision  = (($tensorNames | Where-Object { $_ -match 'v\.blk\.|mm\.|vision|clip' } | Select-Object -First 1) -ne $null) `
              -or ("$($meta['clip.has_vision_encoder'])") -match 'True|1'

$out = [ordered]@{
  file = (Get-Item $Path).FullName; sizeMB = $sizeMB; ggufVersion = $ver; tensorCount = $tensorCount
  architecture = $arch; block_count = $blocks; isMoE = $isMoE
  expert_count = $(if($meta.Contains('expert_count')){$experts}else{$null})
  expert_used_count = $meta['expert_used_count']
  head_count_kv = $hk; key_length = $kl; value_length = $vl
  context_length = $(if($meta.Contains('context_length')){[int]$meta['context_length']}else{$null})
  full_attention_interval = $interval; kvLayers = $kvLayers
  kvBytesPerTokenF16 = $kvBytesF16; perLayerMB = $perLayerMB
  chat_template_has_thinking = $meta['chat_template_has_thinking']
  hasMTP = $hasMTP; hasVision = $hasVision
  nextLayerOffloadArg = $(if($isMoE){'-ncmoe (MoE expert offload)'}else{'-ncffn (dense FFN offload)'})
}

if ($Json) { $out | ConvertTo-Json -Depth 4; exit 0 }
Write-Host "===== GGUF probe: $(Split-Path -Leaf $Path) =====" -ForegroundColor Yellow
$out.GetEnumerator() | ForEach-Object { "  {0,-26} = {1}" -f $_.Key, $_.Value }
Write-Host ""
Write-Host "判定门输入：" -ForegroundColor Cyan
Write-Host "  卸载路径         : $(if($isMoE){'MoE -> -ncmoe'}else{'dense -> -ncffn（不要用减少 -ngl 代替）'})"
Write-Host "  思考预算         : $(if($meta['chat_template_has_thinking']){'有思考模式 -> --reasoning-budget = n_ctx/2（硬规则）'}else{'未探测到思考模式'})"
Write-Host "  MTP              : $(if($hasMTP){'★含 nextn 张量 -> 必须做「无 MTP vs 带 MTP」配对测试，并先问用户 draft KV 档'}else{'无'})"
Write-Host "  视觉             : $(if($hasVision){'★含视觉 -> 必须依次问用户「要不要做视觉测试」「mmproj 放 GPU 还是 CPU」'}else{'无'})"
Write-Host "  KV 边际成本(估)  : $([math]::Round($kvBytesF16/1MB*1024,2)) MiB/1K tokens (f16，q8_0 约一半；实际还要加 compute buffer)"
