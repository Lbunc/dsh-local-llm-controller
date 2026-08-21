#Requires -Version 5.1
<#
.SYNOPSIS
  dsh-local-llm-controller 一键安装向导（Windows）

.DESCRIPTION
  自动完成三件事，全程问答式，绝大多数提示直接回车即可：
    1. 把插件注册进 DSH profile（dsh plugin add）
    2. 在 cordis.patch.yml 追加注册行（已存在则跳过）
    3. 写入配置 ~/.dsh/local-llm.config.json（llama.cpp 目录 / 端口 / 密钥）

  插件启动时会自动在 DSH settings 里补建两个 provider（qwen36-local /
  qwen-local），无需手写 provider 配置。完成后重启 DSH Web 即可。

.PARAMETER ProfileName
  DSH profile 名（默认 web）

.PARAMETER LlamaDir
  llama.cpp 目录（含 llama-server.exe）。不传则交互询问。

.PARAMETER Port
  服务端口（默认 21113）

.PARAMETER ApiKey
  API 密钥。留空 = 无鉴权（仅监听 127.0.0.1 回环，推荐）。
  设置后需保证环境变量 DSH_LOCAL_LLM_KEY 的值与之相同。

.PARAMETER ServerExe
  llama-server 可执行文件名（默认按平台：llama-server.exe / llama-server）

.PARAMETER SkipChecks
  跳过 llama-server.exe 与默认模型文件的本地检查

.EXAMPLE
  .\install.ps1                      # 交互式安装
  .\install.ps1 -LlamaDir F:\llama.cpp -ApiKey ''   # 非交互
#>
[CmdletBinding()]
param(
  [string]$ProfileName = 'web',
  [string]$LlamaDir = '',
  [string]$Port = '',
  [string]$ApiKey = '',
  [string]$ServerExe = '',
  [switch]$SkipChecks
)
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) { Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Info([string]$Text) { Write-Host "   $Text" }
function Write-Ok([string]$Text) { Write-Host "   OK: $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "   !: $Text" -ForegroundColor Yellow }

$DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }
$ProfileDir = Join-Path $DshHome "profiles\$ProfileName"
$PluginDir = $PSScriptRoot
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

Write-Host ''
Write-Host '==== dsh-local-llm-controller 一键安装 ====' -ForegroundColor Cyan

# ---- 1) 检查 profile ----
Write-Step '检查 DSH profile'
if (-not (Test-Path $ProfileDir)) {
  Write-Error "找不到 DSH profile: $ProfileDir`n请先安装 DSH 并至少启动过一次 web profile。"
}
Write-Ok $ProfileDir

# ---- 2) llama.cpp 目录 ----
Write-Step 'llama.cpp 目录'
if (-not $LlamaDir) {
  $LlamaDir = Read-Host '   llama.cpp 目录（包含 llama-server.exe 的文件夹）'
}
if (-not $LlamaDir) { Write-Error '未提供 llama.cpp 目录，安装中止。' }
$LlamaDir = $LlamaDir.TrimEnd('\', '/')
Write-Ok $LlamaDir

# ---- 3) 端口与密钥 ----
if (-not $Port) {
  $Port = Read-Host '   服务端口 [回车 = 21113]'
}
if (-not $Port) { $Port = 21113 }
$PortInt = 0
if (-not [int]::TryParse([string]$Port, [ref]$PortInt)) { Write-Error "端口不是数字: $Port" }

if (-not $PSBoundParameters.ContainsKey('ApiKey')) {
  $ApiKey = Read-Host '   API 密钥 [回车 = 无鉴权（仅本机回环，推荐）]'
}

# ---- 4) 可执行文件名 ----
if (-not $ServerExe) {
  if ($IsWindows -or $env:OS -match 'Windows') { $ServerExe = 'llama-server.exe' } else { $ServerExe = 'llama-server' }
}

# ---- 5) 本地文件检查 ----
if (-not $SkipChecks) {
  Write-Step '检查本地文件'
  $exe = Join-Path $LlamaDir $ServerExe
  if (-not (Test-Path $exe)) {
    Write-Warn "未找到 $exe —— 请确认 llama.cpp 目录正确（可继续安装，启动时会报错）"
  } else {
    Write-Ok "找到 $exe"
  }
  $defaultModels = @(
    @('qwen3.6-35B-A3B', 'Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf'),
    @('qwen3.6-35B-A3B', 'mmproj-Qwen3.6-35B-A3B-Uncensored-f16.gguf'),
    @('qwen3.5-9B', 'Qwen3.5-9B-Uncensored-Q4_K_M.gguf'),
    @('qwen3.5-9B', 'mmproj-Qwen3.5-9B-Uncensored-BF16.gguf')
  )
  foreach ($m in $defaultModels) {
    $p = Join-Path $LlamaDir (Join-Path $m[0] $m[1])
    if (-not (Test-Path $p)) {
      Write-Warn "未找到默认模型文件 $p （若你的目录结构不同，可忽略，启动前改 local-llm.config.json 即可）"
    }
  }
}

# ---- 6) 写入 local-llm.config.json ----
Write-Step '写入配置 local-llm.config.json'
$cfg = @{ llamaDir = $LlamaDir; port = $PortInt }
if ($ApiKey) { $cfg.apiKey = $ApiKey }
$cfgPath = Join-Path $DshHome 'local-llm.config.json'
[System.IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json), $Utf8NoBom)
Write-Ok $cfgPath

# ---- 7) 注册依赖 ----
Write-Step '注册插件到 DSH profile'
$dshCmd = Get-Command dsh -ErrorAction SilentlyContinue
if (-not $dshCmd) {
  Write-Warn '未在 PATH 中找到 dsh 命令，跳过自动注册。请手动执行：'
  Write-Warn "  cd $ProfileDir"
  Write-Warn "  dsh plugin --profile $ProfileName add $PluginDir"
} else {
  Push-Location $ProfileDir
  try {
    & dsh plugin --profile $ProfileName add $PluginDir 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dsh plugin add 退出码非零' }
    Write-Ok '依赖已注册'
  } catch {
    Write-Warn "自动注册失败（$($_.Exception.Message)），请手动执行："
    Write-Warn "  cd $ProfileDir"
    Write-Warn "  dsh plugin --profile $ProfileName add $PluginDir"
  } finally {
    Pop-Location
  }
}

# ---- 8) cordis.patch.yml ----
Write-Step '检查 cordis.patch.yml 注册行'
$patchPath = Join-Path $ProfileDir 'cordis.patch.yml'
$block = "`n# Local LLM Controller (installed by install.ps1)`n- insert:`n    - id: local-llm-controller`n      name: 'dsh-local-llm-controller'`n"
if (Test-Path $patchPath) {
  $content = [System.IO.File]::ReadAllText($patchPath)
  if ($content -match 'local-llm-controller') {
    Write-Ok '已包含注册行，跳过'
  } else {
    [System.IO.File]::AppendAllText($patchPath, $block, $Utf8NoBom)
    Write-Ok "已追加注册行 -> $patchPath"
  }
} else {
  [System.IO.File]::WriteAllText($patchPath, $block, $Utf8NoBom)
  Write-Ok "已创建 $patchPath"
}

# ---- 9) 完成 ----
Write-Host ''
Write-Host '==== 安装完成，接下来 ====' -ForegroundColor Green
Write-Host '  1. 重启 DSH Web（停止 dsh web 后重新运行，或 dsh web 重启）'
Write-Host '  2. 打开设置 → 插件 → Local LLM Controller'
Write-Host '  3. 选模型（35B/9B）、模式、预设，点「启动」，状态变为 运行中 即可在会话中使用'
if ($ApiKey) {
  Write-Host ''
  Write-Warn "你设置了 API 密钥，请确保环境变量 DSH_LOCAL_LLM_KEY 的值 = $ApiKey"
  Write-Warn "（当前值: '$env:DSH_LOCAL_LLM_KEY'；可在系统环境变量或启动 DSH 的终端里设置）"
} else {
  Write-Host ''
  Write-Host '  说明：未设置密钥时 llama-server 仅监听 127.0.0.1，本机进程可访问；如需对外提供服务请设置密钥。'
}
Write-Host ''
