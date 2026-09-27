# llama CLI 系列工具命令行帮助中文手册

> 来源：`F:\llama-b10883-bin-win-cuda-13.3-x64\` 下 `llama.exe`、`llama-cli.exe`、`llama-completion.exe` 的 `-h` 输出（llama.cpp b10883）。原始英文全文存档于 [`docs/help-raw/`](help-raw/)；同名公共参数参照《[llama-server 帮助文档（中文）](./llama-server-帮助文档-中文.md)》（下称"server 手册 §N"）。

## 目录

- [一、llama.exe 统一入口](#一llamaexe-统一入口)
- [二、llama-cli.exe 命令行对话](#二llama-clieexe-命令行对话)
- [三、llama-completion.exe 自动补全](#三llama-completioneexe-自动补全)
- [四、与 server 手册的差异汇总](#四与-server-手册的差异汇总)

---

## 一、llama.exe 统一入口

**用途**：llama.cpp 的统一可执行入口，通过子命令调用不同工具。支持 `download` 子命令从 Hugging Face 拉取模型。

### 子命令

| 子命令 | 说明 | 对应工具 |
|---|---|---|
| `llama download` | 从 Hugging Face 下载模型 | `llama.exe` 内置 |
| `llama run` / `llama chat` | 交互式对话 | `llama-cli.exe` |
| `llama completion` | 自动补全 | `llama-completion.exe` |

### `download` 子命令参数

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-hf, --huggingface REPO` | Hugging Face 仓库（用户名/仓库名） | — |
| `-o, --output PATH` | 输出路径 | 当前目录 |
| `--branch BRANCH` | 分支名 | `main` |
| `--token TOKEN` | Hugging Face 访问令牌 | — |
| `--no-prompt` | 不显示下载确认提示 | — |

---

## 二、llama-cli.exe 命令行对话

**用途**：命令行交互式对话工具。common 段（86 项）与 sampling 段（34 项）与 server 手册逐字一致，以下为工具专属段（example-specific）。

### 专属参数（example-specific）

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-p, --prompt PROMPT` | 起始提示词（文本或文件路径） | — |
| `-f, --file PATH` | 从文件加载提示词 | — |
| `-bf, --binary-file PATH` | 从二进制文件加载 prompt | — |
| `-np, --parallel N` | 并行解码序列数（**注意：此 `-np` 是并行解码序列数，默认 1**，与 server 的"服务器槽位数"同名不同义） | 1 |
| `--input-prefix PREFIX` | 输入前缀字符串 | — |
| `--input-suffix SUFFIX` | 输入后缀字符串 | — |
| `--bot-name NAME` | Bot 名称（对话中显示） | `Assistant` |
| `--user-name NAME` | 用户名称（对话中显示） | `User` |
| `--color` | 输出是否使用颜色 | 自动 |
| `--no-color` | 禁用输出颜色 | — |
| `--interactive-first` | 先进入用户输入模式（先让用户说话） | — |
| `--no-history` | 禁用对话历史 | — |
| `--no-prompt` | 不显示 prompt 提示符 | — |

### 交互命令（运行时输入）

| 命令 | 说明 |
|---|---|
| `/exit` 或 `quit` | 退出对话 |
| `/reset` | 重置对话历史 |
| `/save PATH` | 保存对话到文件 |
| `/load PATH` | 从文件加载对话历史 |
| `/set PARAM VALUE` | 运行时设置参数（如 `/set temp 0.8`） |
| `/help` | 显示帮助 |

---

## 三、llama-completion.exe 自动补全

**用途**：生成 Bash/Zsh/PowerShell 的命令行自动补全脚本。

### 参数

| 参数 | 说明 | 默认值 |
|---|---|---|
| `--shell SHELL` | 目标 shell 类型（`bash`、`zsh`、`fish`、`powershell`） | `bash` |
| `--output PATH` | 输出文件路径 |  stdout |

---

## 四、与 server 手册的差异汇总

| 差异项 | llama-cli | llama-completion | server 手册 |
|---|---|---|---|
| 多出的公共参数 | `-p/--prompt`、`-f/--file`、`-bf/--binary-file`、`-np/--parallel` | 无 | 基准 |
| `--temp` 默认值 | 0.80（同 server） | — | 0.80 |
| `-c` 默认上下文 | 512（server 为 0=读取模型元数据） | — | 0 |
| `-np` 含义 | **并行解码序列数**（server 中为服务器槽位数） | — | 服务器槽位数 |
| 交互命令 | 有（`/exit`、`/reset` 等） | — | — |

> **插件提示**：本手册中的 `llama-cli` 用于快速验证聊天模板与采样参数，不用于插件日常运行（插件使用 `llama-server`）。深度调优时可能用到 `-p/--prompt` 进行单轮推理测试。
