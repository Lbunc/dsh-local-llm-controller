# dev-reset.ps1 — 开发环专用：一键回到「全新安装」状态（30 秒模拟新用户）
#
# 干什么：
#   1. 备份当前 settings.yaml -> settings.yaml.dev-bak
#   2. 删除插件写入的设置段（local-llm / llm-pi-ai），
#      并把 agent-default-model 恢复为 deepseek 默认（若指向 qwen-local）
#   3. dsh plugin remove 卸载插件
#   4. dsh plugin add <RepoPath> 用 file:link 重装（= 仓库本体，免 npm 发版）
#
# 之后：重启 DSH Web -> 按新用户流程验证：
#   空卡片 -> 填 llama.cpp 目录/端口 -> 保存配置 -> 「添加到模型列表」
#   -> 选模型/预设 -> 启动 -> 会话对话。
#
# 本脚本是纯开发工具：不在 package.json 的 files 里，不会被 npm 打包发布。

param(
  [string]$RepoPath = (Split-Path -Parent $MyInvocation.MyCommand.Path),
  [string]$DshHome   = ($env:DSH_HOME ? $env:DSH_HOME : (Join-Path $HOME '.dsh'))
)

$ErrorActionPreference = 'Stop'
$Profile  = Join-Path $DshHome 'profiles\web'
$Settings = Join-Path $DshHome 'settings.yaml'

if (-not (Test-Path $Settings)) { throw "settings.yaml 不存在: $Settings" }
if (-not (Test-Path (Join-Path $RepoPath 'package.json'))) { throw "仓库路径无效: $RepoPath" }

Write-Host "==> 1/4 备份 settings.yaml -> settings.yaml.dev-bak"
Copy-Item $Settings (Join-Path $DshHome 'settings.yaml.dev-bak') -Force

Write-Host "==> 2/4 清理插件设置段（local-llm / llm-pi-ai / agent-default-model）"
$text = [System.IO.File]::ReadAllText($Settings)
# 删除顶层段：键 + 其下所有缩进行
$blockRe = '(?m)^(local-llm|llm-pi-ai):\r?\n(?:[ \t][^\r\n]*\r?\n?)*'
$text = [regex]::Replace($text, $blockRe, '')
# agent-default-model 若指向 qwen provider，恢复 deepseek 默认
$m = [regex]::Match($text, '(?m)^agent-default-model:\r?\n(?:[ \t][^\r\n]*\r?\n?)*')
if ($m.Success -and $m.Value -match 'qwen') {
  $text = $text.Replace($m.Value, "agent-default-model:`n  provider: deepseek-official`n  model: deepseek-v4-flash-vision-exp`n  reasoningEffort: max`n")
}
[System.IO.File]::WriteAllText($Settings, $text, [System.Text.UTF8Encoding]::new($false))

Write-Host "==> 3/4 卸载插件（reconcile 会移除 bundles 行）"
Push-Location $Profile
try {
  dsh plugin --profile web remove dsh-local-llm-controller 2>$null
  if ($LASTEXITCODE -ne 0) { Write-Warning "插件当前未安装，直接重装（可忽略）" }

  Write-Host "==> 4/4 用 file:link 重装仓库本体 = $RepoPath"
  dsh plugin --profile web add $RepoPath
  if ($LASTEXITCODE -ne 0) { throw 'file:link 重装失败' }
} finally {
  Pop-Location
}

Write-Host ""
Write-Host "✅ 全新安装状态已就绪。下一步："
Write-Host "   1) 重启 DSH Web（Host 变更需要）"
Write-Host "   2) 卡片应为空配置 -> 填 llama.cpp 目录/端口 -> 保存配置"
Write-Host "   3) 点「添加到模型列表」-> 设置→模型出现两个 Qwen provider"
Write-Host "   4) 选模型/预设 -> 启动 -> 会话对话"
Write-Host "   回滚设置：用 settings.yaml.dev-bak 覆盖 settings.yaml"
