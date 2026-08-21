#Requires -Version 5.1
<#
.SYNOPSIS
  dsh-local-llm-controller 一键安装向导（Windows）

.DESCRIPTION
  自动完成四件事，全程问答式，绝大多数提示直接回车即可：
    1. 把插件本体复制到 profile 的 plugins/ 目录（与 git 仓库解耦）
    2. 在 profile package.json 注册依赖（link:./plugins/dsh-local-llm-controller）
    3. 在 cordis.patch.yml 追加注册行（已存在则跳过）
    4. 写入配置 ~/.dsh/local-llm.config.json（llama.cpp 目录 / 端口 / 密钥）

  插件启动时会自动在 DSH settings 里补建两个 provider（qwen36-local /
  qwen-local），无需手写 provider 配置。完成后重启 DSH Web 即可。
  重新运行本脚本会询问是否用仓库版本覆盖已安装的本体（-Force 直接覆盖）。

.PARAMETER ProfileName
  DSH profile 名（默认 web）

.PARAMETER LlamaDir
  llama.cpp 目录（含 llama-server.exe）。不传则交互询问。

.PARAMETER Port
  服务端口（默认 67913）

.PARAMETER ApiKey
  API 密钥。留空 = 无鉴权（仅监听 127.0.0.1 回环，推荐）。
  设置后需保证环境变量 DSH_LOCAL_LLM_KEY 的值与之相同。

.PARAMETER ServerExe
  llama-server 可执行文件名（默认按平台：llama-server.exe / llama-server）

.PARAMETER SkipChecks
  跳过 llama-server.exe 与默认模型文件的本地检查

.PARAMETER Force
  已安装过本体时直接用仓库版本覆盖（默认询问）

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
  [switch]$SkipChecks,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) { Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Info([string]$Text) { Write-Host "   $Text" }
function Write-Ok([string]$Text) { Write-Host "   OK: $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "   !: $Text" -ForegroundColor Yellow }
function Test-Interactive {
  return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
}
function Ask([string]$Prompt, [string]$Default = '') {
  if (Test-Interactive) {
    $v = Read-Host $Prompt
    if ($v) { return $v }
  }
  return $Default
}

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
  $LlamaDir = Ask '   llama.cpp 目录（包含 llama-server.exe 的文件夹）'
}
if (-not $LlamaDir) { Write-Error '未提供 llama.cpp 目录，安装中止。非交互模式请用 -LlamaDir 参数。' }
$LlamaDir = $LlamaDir.TrimEnd('\', '/')
Write-Ok $LlamaDir

# ---- 3) 端口与密钥 ----
if (-not $Port) {
  $Port = Ask '   服务端口' '67913'
}
if (-not $Port) { $Port = 67913 }
$PortInt = 0
if (-not [int]::TryParse([string]$Port, [ref]$PortInt)) { Write-Error "端口不是数字: $Port" }

if (-not $PSBoundParameters.ContainsKey('ApiKey')) {
  $ApiKey = Ask '   API 密钥（回车 = 无鉴权，仅本机回环）'
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
  # 模型目录检查（文件名不限，只要有 gguf 即可，用户可自定义路径）
  $modelDirs = @('qwen3.6-35B-A3B', 'qwen3.5-9B')
  foreach ($d in $modelDirs) {
    $dir = Join-Path $LlamaDir $d
    if (-not (Test-Path $dir)) {
      Write-Warn "未找到模型目录 $dir （可忽略：只要 local-llm.config.json 里的路径正确即可）"
    } elseif (-not (Get-ChildItem $dir -Filter '*.gguf' -ErrorAction SilentlyContinue)) {
      Write-Warn "模型目录 $dir 下没有 .gguf 文件（可忽略：只要 local-llm.config.json 里的路径正确即可）"
    } else {
      Write-Ok "找到模型目录 $dir"
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

# ---- 7) 安装插件本体到 profile/plugins 并注册依赖 ----
Write-Step '安装插件本体到 profile'
$BodyDir = Join-Path $ProfileDir 'plugins\dsh-local-llm-controller'
$installed = Test-Path (Join-Path $BodyDir 'lib\index.js')
$skipCopy = $false
if ($installed -and -not $Force) {
  $ans = Ask '   检测到已安装的本体，是否用仓库版本覆盖？[y/N]'
  if ($ans -notmatch '^[yY]') { $skipCopy = $true }
}
if (-not $skipCopy) {
  New-Item -ItemType Directory -Force -Path $BodyDir | Out-Null
  Copy-Item (Join-Path $PluginDir 'lib') (Join-Path $BodyDir 'lib') -Recurse -Force
  foreach ($f in @('package.json', 'README.md', 'LICENSE')) {
    $src = Join-Path $PluginDir $f
    if (Test-Path $src) { Copy-Item $src $BodyDir -Force }
  }
  Write-Ok "本体已复制 -> $BodyDir"
} else {
  Write-Ok '保留已安装的本体'
}

# 注册依赖：package.json -> "dsh-local-llm-controller": "link:./plugins/dsh-local-llm-controller"
$pkgPath = Join-Path $ProfileDir 'package.json'
if (Test-Path $pkgPath) {
  $text = [System.IO.File]::ReadAllText($pkgPath)
  $depKey = 'dsh-local-llm-controller'
  $depVal = 'link:./plugins/dsh-local-llm-controller'
  if ($text -match '"dsh-local-llm-controller"\s*:\s*"[^"]*"') {
    $text = [regex]::Replace($text, '"dsh-local-llm-controller"\s*:\s*"[^"]*"', ('"{0}": "{1}"' -f $depKey, $depVal))
    Write-Ok '依赖已指向 profile 内本体'
  } elseif ($text -match '"dependencies"\s*:\s*\{\s*\}') {
    # 空 dependencies 块：整体替换（避免 ",}" 非法 JSON）
    $insert = "`n    `"$depKey`": `"$depVal`"`n  }"
    $text = [regex]::Replace($text, '"dependencies"\s*:\s*\{\s*\}', ('"dependencies": {' + $insert), 1)
    Write-Ok '已添加依赖行'
  } elseif ($text -match '"dependencies"\s*:\s*\{') {
    # 非空 dependencies 块：在开头插入一行
    $insert = "`n    `"$depKey`": `"$depVal`","
    $text = [regex]::Replace($text, '"dependencies"\s*:\s*\{', ('"dependencies": {' + $insert), 1)
    Write-Ok '已添加依赖行'
  } else {
    Write-Warn 'package.json 没有 dependencies 块，请手动添加：'
    Write-Warn "  `"$depKey`": `"$depVal`""
  }
  [System.IO.File]::WriteAllText($pkgPath, $text, $Utf8NoBom)
} else {
  Write-Warn "未找到 $pkgPath，请确认 profile 已初始化"
}

# 刷新 node_modules（junction 指向 profile/plugins 下的本体）
$dshCmd = Get-Command dsh -ErrorAction SilentlyContinue
if ($dshCmd) {
  Push-Location $ProfileDir
  try {
    & dsh plugin --profile $ProfileName install 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'pnpm install 退出码非零' }
    Write-Ok 'node_modules 已刷新'
  } catch {
    Write-Warn "自动刷新失败（$($_.Exception.Message)），请手动执行："
    Write-Warn "  cd $ProfileDir"
    Write-Warn "  pnpm install"
  } finally {
    Pop-Location
  }
} else {
  Write-Warn '未在 PATH 中找到 dsh 命令，请手动执行：'
  Write-Warn "  cd $ProfileDir"
  Write-Warn "  pnpm install"
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
Write-Host ''
Write-Host "  插件本体位于: $BodyDir（与 git 仓库解耦，clone 目录可随意移动/删除）"
Write-Host '  更新本体：重新运行本脚本（询问覆盖），或直接替换 lib/ 后重启 DSH'
if ($ApiKey) {
  Write-Host ''
  Write-Warn "你设置了 API 密钥，请确保环境变量 DSH_LOCAL_LLM_KEY 的值 = $ApiKey"
  Write-Warn "（当前值: '$env:DSH_LOCAL_LLM_KEY'；可在系统环境变量或启动 DSH 的终端里设置）"
} else {
  Write-Host ''
  Write-Host '  说明：未设置密钥时 llama-server 仅监听 127.0.0.1，本机进程可访问；如需对外提供服务请设置密钥。'
}
Write-Host ''
