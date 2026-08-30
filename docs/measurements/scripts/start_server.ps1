#requires -Version 7
<#
.SYNOPSIS
  通用 llama-server 启动器（函数库）——模型/版本无关，运行时探查驱动。
  对齐 SKILL.md 第 1a 部署约束：端口 55555 / apiKey 留空(与插件一致) / 最小上下文 32K / 单实例 -np 1。
  必备采样/惩罚参数（SKILL.md 1a）：--temp 0.6 --top-k 20 --top-p 0.95 --min-p 0.0 --repeat-penalty 1 --presence-penalty 0 --slots --metrics。
  用法：在被扫描脚本顶部 dot-source 本文件，然后调用 Start-LlamaServer。
        本文件作为函数库，在单个 pwsh 调用内 启动-测试-清理，避免 pwsh 退出导致子进程连坐。
#>
$ErrorActionPreference = 'Stop'

# --- 部署约束常量（与 SKILL.md 1a 对齐，勿随意改动）---
$script:DEFAULT_PORT     = 55555
$script:DEFAULT_APIKEY   = ''           # 留空：与插件 config.apiKey:"" 一致；server 不传 --api-key 不校验
$script:DEFAULT_AUTHTOKEN = 'dsh-local-llm'  # 客户端 header（与 provider 一致），server 不校验也能连
$script:MIN_CONTEXT      = 32768
$script:DEFAULT_TIMEOUT  = 210          # /props 就绪超时秒

# ---------------------------------------------------------------------------
# GGUF 元数据提取（自包含，不依赖外部脚本）—— 提取判定门所需键
# ---------------------------------------------------------------------------
function Get-GgufMeta {
  param([Parameter(Mandatory)][string]$ModelPath)
  if (-not (Test-Path $ModelPath)) { throw "GGUF not found: $ModelPath" }
  $finfo = Get-Item $ModelPath
  $fs = [System.IO.File]::OpenRead($ModelPath)
  $meta = @{}
  try {
    $br = New-Object System.IO.BinaryReader($fs)
    [void]$br.ReadBytes(4)                 # magic GGUF
    [void]$br.ReadUInt32()                 # version
    [void]$br.ReadUInt64()                 # tensor count
    $kvCount = $br.ReadUInt64()

    # 想提取的 basename 集合（架构无关：llama.*/qwen.*/... 的最后一段）
    $want = @('architecture','block_count','expert_count','head_count_kv',
              'key_length','value_length','context_length','full_attention_interval')

    function Read-GGUFStr($r) { $n = $r.ReadUInt64(); [System.Text.Encoding]::UTF8.GetString($r.ReadBytes([int]$n)) }
    function Skip-GGUFVal($r, [int]$t) {
      switch ($t) {
        0 { [void]$r.ReadByte() }
        1 { [void]$r.ReadSByte() }
        2 { [void]$r.ReadUInt16() }
        3 { [void]$r.ReadInt16() }
        4 { [void]$r.ReadUInt32() }
        5 { [void]$r.ReadInt32() }
        6 { [void]$r.ReadSingle() }
        7 { [void]$r.ReadByte() }
        8 { [void](Read-GGUFStr $r) }
        10 { [void]$r.ReadUInt64() }
        11 { [void]$r.ReadInt64() }
        12 { [void]$r.ReadDouble() }
        9 {
          $et = [int]$r.ReadUInt32(); $cnt = [long]$r.ReadUInt64()
          $step = switch ($et) { 0 {1}; 1 {1}; 2 {2}; 3 {2}; 4 {4}; 5 {4}; 6 {4}; 7 {1}; 10 {8}; 11 {8}; 12 {8}; default {-1} }
          if ($et -eq 8) { for ($i=0; $i -lt $cnt; $i++) { $l=[long]$r.ReadUInt64(); [void]$r.ReadBytes([int]$l) } }
          elseif ($step -gt 0) { [void]$r.BaseStream.Seek($cnt*$step,'Current') }
          else { for ($i=0; $i -lt $cnt; $i++) { Skip-GGUFVal $r $et } }
        }
        default { throw "unknown gguf type $t" }
      }
    }
    for ($i = 0; $i -lt $kvCount; $i++) {
      $key = Read-GGUFStr $br
      $type = [int]$br.ReadUInt32()
      $base = ($key -split '\.')[-1]
      if ($want -contains $base) {
        $v = $null
        switch ($type) {
          0 { $v = $br.ReadByte() }
          1 { $v = $br.ReadSByte() }
          2 { $v = $br.ReadUInt16() }
          3 { $v = $br.ReadInt16() }
          4 { $v = $br.ReadUInt32() }
          5 { $v = $br.ReadInt32() }
          6 { $v = $br.ReadSingle() }
          7 { $v = $br.ReadByte() }
          8 { $v = Read-GGUFStr $br }
          10 { $v = $br.ReadUInt64() }
          11 { $v = $br.ReadInt64() }
          12 { $v = $br.ReadDouble() }
          9 {
            $et=[int]$br.ReadUInt32(); $cnt=[long]$br.ReadUInt64()
            $step=switch($et){0{1};1{1};2{2};3{2};4{4};5{4};6{4};7{1};10{8};11{8};12{8};default{-1}}
            if($et-eq 8){for($j=0;$j-lt $cnt;$j++){$l=[long]$br.ReadUInt64();[void]$br.ReadBytes([int]$l)}}
            elseif($step-gt 0){[void]$br.BaseStream.Seek($cnt*$step,'Current')}
            else{for($j=0;$j-lt $cnt;$j++){Skip-GGUFVal $br $et}}
          }
          default { Skip-GGUFVal $br $type }
        }
        if ($null -ne $v) { $meta[$base] = $v }
      } else {
        Skip-GGUFVal $br $type
      }
    }
  } finally { $fs.Dispose() }

  # 派生量
  $bc = [int]$meta['block_count']
  $ec = if ($meta.ContainsKey('expert_count')) { [int]$meta['expert_count'] } else { 0 }
  $hkv = if ($meta.ContainsKey('head_count_kv')) { [int]$meta['head_count_kv'] } else { 0 }
  $kl = if ($meta.ContainsKey('key_length')) { [int]$meta['key_length'] } else { 0 }
  $vl = if ($meta.ContainsKey('value_length')) { [int]$meta['value_length'] } else { 0 }
  $fai = if ($meta.ContainsKey('full_attention_interval')) { [int]$meta['full_attention_interval'] } else { 1 }
  $ctxN = if ($meta.ContainsKey('context_length')) { [int]$meta['context_length'] } else { 0 }
  # KV 层数估算：full_attention_interval=N 表示每 N 层 1 个 KV 层
  $kvLayers = if ($fai -gt 0) { [math]::Max(1, [math]::Floor($bc / $fai)) } else { $bc }

  return @{
    architecture = $meta['architecture']
    block_count = $bc
    expert_count = $ec
    head_count_kv = $hkv
    key_length = $kl
    value_length = $vl
    context_length = $ctxN
    full_attention_interval = $fai
    kvLayers = $kvLayers
    isMoE = ($ec -gt 0)
    fileSizeMB = [math]::Round($finfo.Length / 1MB, 1)
    perLayerMB = if ($bc -gt 0) { [math]::Round($finfo.Length / 1MB / $bc, 1) } else { 0 }
    # KV/token 字节（f16 基准）：kvLayers × head_count_kv × (key_len+val_len) × 2
    kvBytesPerTokenF16 = $kvLayers * $hkv * ($kl + $vl) * 2
  }
}

# ---------------------------------------------------------------------------
# llama-server --help 参数探查（SKILL.md 0b）—— 返回缺失参数列表
# ---------------------------------------------------------------------------
function Test-ServerHelp {
  param([Parameter(Mandatory)][string]$LlamaDir, [string[]]$RequiredFlags)
  $exe = Join-Path $LlamaDir 'llama-server.exe'
  if (-not (Test-Path $exe)) { throw "llama-server.exe not found in $LlamaDir" }
  $help = & $exe '--help' 2>&1 | Out-String
  $missing = @()
  foreach ($f in $RequiredFlags) { if ($help -notlike "*$f*") { $missing += $f } }
  return $missing
}

# ---------------------------------------------------------------------------
# 四件套采集函数（SKILL.md 3.0）
# ---------------------------------------------------------------------------
function Get-Vram {
  param([int]$GpuId = -1)
  $d = -1; $s = -1
  try {
    $c = Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop
    $samps = $c.CounterSamples | Where-Object { $_.CookedValue -gt 0 }
    if ($GpuId -ge 0) { $samps = $samps | Where-Object { $_.InstanceName -like "*$GpuId*" } }
    if ($samps) { $d = [math]::Round((($samps | Measure-Object CookedValue -Maximum).Maximum) / 1MB, 0) }
  } catch {}
  try {
    $c2 = Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop
    $samps2 = $c2.CounterSamples | Where-Object { $_.CookedValue -gt 0 }
    if ($GpuId -ge 0) { $samps2 = $samps2 | Where-Object { $_.InstanceName -like "*$GpuId*" } }
    if ($samps2) { $s = [math]::Round((($samps2 | Measure-Object CookedValue -Maximum).Maximum) / 1MB, 0) }
  } catch {}
  return "ded=$d shared=$s"
}

function Get-CpuUtil {
  try { $c = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop; return [math]::Round($c.CounterSamples[0].CookedValue, 0) } catch { return -1 }
}

# 后台周期采样 GPU util + CPU util，返回 job；Stop-UtilSampler 收集采样行 "gpu=X cpu=Y" 取尾部均值
function Start-UtilSampler {
  param([int]$GpuId = 0, [int]$IntervalSec = 1)
  $job = Start-Job -ScriptBlock {
    param($g, $iv)
    while ($true) {
      $gu = -1
      try { $line = nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -i $g 2>$null | Select-Object -First 1; $gu = [int]$line } catch {}
      $cu = -1
      try { $c = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop; $cu = [math]::Round($c.CounterSamples[0].CookedValue,0) } catch {}
      Write-Output "gpu=$gu cpu=$cu"
      Start-Sleep -Seconds $iv
    }
  } -ArgumentList $GpuId, $IntervalSec
  return $job
}

function Stop-UtilSampler {
  param($job)
  if ($job) { Stop-Job $job -ErrorAction SilentlyContinue; $out = Receive-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue; return $out }
}

# 从 sampler 输出行解析尾部均值（SKILL.md：取生成阶段尾部均值）
function Get-UtilTailMean {
  param([string[]]$Lines, [int]$Tail = 10, [switch]$Cpu)
  $pat = if ($Cpu) { 'cpu=(\d+)' } else { 'gpu=(\d+)' }
  $vals = $Lines | Select-Object -Last $Tail | ForEach-Object { if ($_ -match $pat) { [int]$matches[1] } } | Where-Object { $_ -ge 0 }
  if ($vals) { return [math]::Round(($vals | Measure-Object -Average).Average, 0) } else { return -1 }
}

# ---------------------------------------------------------------------------
# 通用 server 启动（核心）
# ---------------------------------------------------------------------------
function Start-LlamaServer {
  param(
    [Parameter(Mandatory)][string]$ModelPath,
    [Parameter(Mandatory)][string]$Alias,
    [Parameter(Mandatory)][string]$LlamaDir,
    [int]$Port = $script:DEFAULT_PORT,
    [string]$ApiKey = $script:DEFAULT_APIKEY,   # 默认留空 → 不传 --api-key（与插件一致）
    [int]$Ngl = 99,
    [int]$ContextSize = $script:MIN_CONTEXT,
    [string]$CacheTypeK = 'q8_0',
    [string]$CacheTypeV = 'q8_0',
    [string]$Fa = 'on',
    [int]$Threads = 0,           # 0 = 不加 -t/-tb
    [int]$ThreadsBatch = 0,
    [ValidateSet('auto','none','ncmoe')][string]$MoeMode = 'auto',
    [int]$Ncmoe = -1,            # MoeMode=ncmoe 必填
    [int]$ReasoningBudget = 0,   # 0 = 不加
    [string]$SpecType = '',      # 空 = 不加投机解码
    [int]$SpecDraftNMax = 0,
    # 必备采样/惩罚参数（SKILL.md 1a 默认值）
    [float]$Temp = 0.6, [int]$TopK = 20, [float]$TopP = 0.95, [float]$MinP = 0.0,
    [float]$RepeatPenalty = 1.0, [float]$PresencePenalty = 0.0,
    [int]$GpuId = -1,
    [int]$ReadyTimeoutSec = $script:DEFAULT_TIMEOUT,
    [switch]$SkipHelpCheck
  )

  # 校验：部署约束
  if ($ContextSize -lt $script:MIN_CONTEXT) { throw "ContextSize $ContextSize 小于最小值 $($script:MIN_CONTEXT)（SKILL.md 1a）" }
  if (-not (Test-Path $ModelPath)) { throw "ModelPath not found: $ModelPath" }
  $exe = Join-Path $LlamaDir 'llama-server.exe'
  if (-not (Test-Path $exe)) { throw "llama-server.exe not found in $LlamaDir" }

  # 读 GGUF 元数据（判定门依据）
  $meta = Get-GgufMeta -ModelPath $ModelPath
  Write-Host "[meta] arch=$($meta.architecture) block=$($meta.block_count) expert=$($meta.expert_count) isMoE=$($meta.isMoE) ctx=$($meta.context_length) kvLayers=$($meta.kvLayers) perLayer=$($meta.perLayerMB)MB kv/token(f16)=$($meta.kvBytesPerTokenF16)B"

  # MoE 路径决策（auto 模式据 expert_count 自动）
  $useNcmoe = $false; $ncmoeVal = 0
  switch ($MoeMode) {
    'none'  { }
    'ncmoe' { if (-not $meta.isMoE) { throw "MoeMode=ncmoe 但 expert_count=0（dense 模型，应走 -ngl 路径）" }; if ($Ncmoe -lt 0) { throw "MoeMode=ncmoe 需 -Ncmoe N" }; $useNcmoe = $true; $ncmoeVal = $Ncmoe }
    'auto'  { if ($meta.isMoE -and $Ncmoe -ge 0) { $useNcmoe = $true; $ncmoeVal = $Ncmoe } }
  }

  # --help 参数探查（SKILL.md 0b，强制，可 -SkipHelpCheck 跳过）
  if (-not $SkipHelpCheck) {
    $req = @('-m','-a','--port','--host','-ngl','-c','-fa','--cache-type-k','--cache-type-v','-np','--metrics','--slots',
             '--temp','--top-k','--top-p','--min-p','--repeat-penalty','--presence-penalty')
    if ($ApiKey) { $req += '--api-key' }
    if ($useNcmoe) { $req += '-ncmoe' }
    if ($Threads -gt 0) { $req += '-t','-tb' }
    if ($ReasoningBudget -gt 0) { $req += '--reasoning-budget' }
    if ($SpecType) { $req += '--spec-type','--spec-draft-n-max' }
    $missing = Test-ServerHelp $LlamaDir $req
    if ($missing.Count -gt 0) { Write-Warning "[help] llama-server --help 缺失参数: $($missing -join ', ')（版本可能不支持，启动可能失败）" }
  }

  # 组装启动参数（必备采样/惩罚参数 + 条件参数）
  $a = [System.Collections.ArrayList]@()
  [void]$a.AddRange(@('-m',$ModelPath,'-a',$Alias,'--port',"$Port",'--host','127.0.0.1',
    '-ngl',"$Ngl",'-c',"$ContextSize",'-fa',$Fa,'--cache-type-k',$CacheTypeK,'--cache-type-v',$CacheTypeV,
    '-np','1','--metrics','--slots',
    '--temp',"$Temp",'--top-k',"$TopK",'--top-p',"$TopP",'--min-p',"$MinP",
    '--repeat-penalty',"$RepeatPenalty",'--presence-penalty',"$PresencePenalty"))
  if ($ApiKey) { [void]$a.AddRange(@('--api-key',$ApiKey)) }
  if ($Threads -gt 0) { [void]$a.AddRange(@('-t',"$Threads")); [void]$a.AddRange(@('-tb',"$(if($ThreadsBatch -gt 0){$ThreadsBatch}else{$Threads})")) }
  if ($useNcmoe) { [void]$a.AddRange(@('-ncmoe',"$ncmoeVal")) }
  if ($ReasoningBudget -gt 0) { [void]$a.AddRange(@('--reasoning-budget',"$ReasoningBudget")) }
  if ($SpecType) { [void]$a.AddRange(@('--spec-type',$SpecType)); if ($SpecDraftNMax -gt 0) { [void]$a.AddRange(@('--spec-draft-n-max',"$SpecDraftNMax")) } }

  # 客户端 header：ApiKey 非空用 ApiKey，否则用与 provider 一致的 dsh-local-llm（server 不校验也能连）
  $authToken = if ($ApiKey) { $ApiKey } else { $script:DEFAULT_AUTHTOKEN }
  Write-Host "[start] port=$Port ctx=$ContextSize ngl=$Ngl ncmoe=$(if($useNcmoe){$ncmoeVal}else{'-'}) threads=$(if($Threads-gt 0){$Threads}else{'-'}) rb=$(if($ReasoningBudget-gt 0){$ReasoningBudget}else{'-'}) spec=$(if($SpecType){$SpecType}else{'-'}) apikey=$(if($ApiKey){'set'}else{'empty(dsh-local-llm header)'})"
  $p = Start-Process -FilePath $exe -ArgumentList $a -WindowStyle Hidden -PassThru -WorkingDirectory $LlamaDir
  $h = @{ Authorization = "Bearer $authToken"; 'Content-Type' = 'application/json' }
  for ($i = 0; $i -lt [int]($ReadyTimeoutSec / 3); $i++) {
    Start-Sleep -Seconds 3
    try {
      $pr = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/props" -Headers $h -TimeoutSec 3
      return @{ p=$p; ctx=[int]$pr.default_generation_settings.n_ctx; port=$Port; apiKey=$ApiKey; authToken=$authToken; headers=$h; meta=$meta; useNcmoe=$useNcmoe; ncmoeVal=$ncmoeVal; args=$a }
    } catch {}
  }
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  throw "server $ReadyTimeoutSec 秒内未就绪（port $Port）——检查模型路径/显存/参数"
}

function Stop-LlamaServer {
  param($server)
  if ($server -and $server.p) { Stop-Process -Id $server.p.Id -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 2
  if ($server) {
    try { Invoke-RestMethod -Uri "http://127.0.0.1:$($server.port)/props" -Headers $server.headers -TimeoutSec 2 | Out-Null; Write-Warning "[stop] port $($server.port) 仍被占用！" } catch { Write-Host "[stop] port $($server.port) 已释放" }
  }
}

# 便利：短测试（/completion 端点，测短上下文稳态 t/s；请求级 sampling 用 1.0 测纯吞吐多样性，不覆盖 server 默认）
function Invoke-Short {
  param($server, [int]$NPredict = 96)
  $body = @{ prompt='Explain the water cycle in detail, step by step.'; n_predict=$NPredict; temperature=1.0; top_k=20; top_p=0.95; min_p=0.0 } | ConvertTo-Json
  $r = Invoke-RestMethod -Uri "http://127.0.0.1:$($server.port)/completion" -Method Post -Headers $server.headers -Body $body -TimeoutSec 120
  $t = $r.timings
  return @{ n=$t.predicted_n; tps=[math]::Round($t.predicted_per_second,1) }
}

Write-Host "[start_server.ps1 loaded] dot-source 后调用: Start-LlamaServer -ModelPath <gguf> -Alias <name> -LlamaDir <dir> [-Ncmoe N] [-Ngl N] [-Threads N] [-ReasoningBudget N] [-SpecType draft-mtp]  (apiKey 默认留空，必备采样/惩罚参数已内置)" -ForegroundColor Cyan
