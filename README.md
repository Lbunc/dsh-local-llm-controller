<div align="center">

# 🚀 dsh-local-llm-controller

<img src="images/wallpaper.jpg" alt="dsh-local-llm-controller" width="100%">

**DSH 插件：设置页一键启停本地 llama.cpp，让本地大模型成为 DSH 会话模型**

[![npm version](https://img.shields.io/npm/v/dsh-local-llm-controller?color=blue)](https://www.npmjs.com/package/dsh-local-llm-controller)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/Lbunc/dsh-local-llm-controller/blob/main/LICENSE)
[![llama.cpp](https://img.shields.io/badge/llama.cpp-upstream-8B5CF6)](https://github.com/ggml-org/llama.cpp)

[English](README.en.md) | **简体中文**

</div>

***

## ✨ 概览

在 DSH（DeepSeek Harness）的「设置 → 插件」页面一键启停本地 [llama.cpp](https://github.com/ggml-org/llama.cpp) `llama-server`，把本地大模型直接接入 DSH 作为会话模型。

**v2.0 起**：不再绑定特定模型——两个**模型槽位 A/B**（各选各的文件夹与模型文件）、每个槽位 **8 组可编辑启动参数**（文本/视觉 × 快速/长上下文），模型名与 Provider 键由所选 GGUF 自动派生，模型页可重命名。

> 🌐 卡片界面文案跟随 DSH Web 的语言设置（简体中文 / English），无需额外配置。

***

## 🆕 v2.0：安装后的使用流程

> 与 v1.x 的差异：双模型（35B/9B）→ **双槽位 A/B**；内建预设 → **8 组可编辑启动参数行**；模型名/Provider 键 → 文件派生、模型页可改名。

### 使用流程

1. **展开卡片**，在配置区填：
   - `llama.cpp 目录`：`llama-server.exe` 所在文件夹（必填）
   - `端口`：默认 55555（「添加到模型列表」按当前值写入 provider 的 baseURL）
   - `密钥`：留空 = 无鉴权（仅回环）；留空也会写入占位鉴权头（pi-ai 客户端要求）

   <p align="center"><img src="images/setting-plug.png" width="420" alt="设置 → 插件（配置卡片）"></p>

2. **槽位 A / B 配置**：各填一个**模型文件夹路径**（内含模型 GGUF，含视觉的还要有 mmproj）→ 点「**保存配置**」。
3. **添加模型到模型列表**：保存后文件夹内所有模型 GGUF 变成气泡（mmproj 不会出现在列表，视觉时自动挂载）→ 点选一个→ 点「**保存配置**」→ 点「**添加到模型列表**」。模型名由文件名**自动派生**；要改名/改显示名去 **设置 → 模型** 页改。

   <p align="center"><img src="images/setting-model.png" width="420" alt="设置 → 模型（添加到模型列表后出现）"></p>

4. **启动参数**（8 组 = 槽位 × 文本/视觉 × 快速/长上下文）：「启动参数（当前组合）」显示正在编辑哪一组，每行 = `参数` + `值` 两个输入框，支持 **+ 添加参数行** 与 × **删除行**。基础参数已预填（`-ngl`/`-t`/`-c`/采样…），推荐的高级参数组合见项目文档与 [llama.cpp 参数](https://github.com/ggml-org/llama.cpp)；`-m`/`-a`/`--port`/`--host`/`--api-key` 及视觉时的 `--mmproj` 由插件自动管理，无需在参数行里添加。

   <p align="center"><img src="images/params.png" width="420" alt="启动参数行（8 组之一）"></p>

5. **启动区**：选槽位 A/B → 选模式（文本/视觉）→ 选预设（快速/长上下文）→ 点「**启动**」
6. **对话**：状态变「运行中」后，会话底部选择对应的本地模型即可；「停止」释放端口；出错时卡片显示原因与最近日志。

   <p align="center"><img src="images/useing.png" width="420" alt="会话中选择本地模型对话"></p>

### ⚠️ 注意事项

- **同一插槽换模型文件后**：Provider Key 随文件名变化——旧键在「设置 → 模型」里**不会自动覆写/删除**，需要**手动删除旧条目**后，再点「添加到模型列表」写入新条目。
- **视觉图片**：llama-server（旧构建）的图片解码器**不支持 WebP**。本插件已把 DSH 的图片请求预算提高到 16MiB / 4096²，常规 **PNG/JPEG 截图/大图会原样直达**；**WebP 源文件**请先转成 PNG/JPEG 再发。
- 模型文件夹里的 **mmproj**（视觉投影器）自动识别、视觉模式自动挂载，且必须在文件名中包含 `mmproj`。
- 想固定 Provider Key（免去每次换文件后重选模型）：在「设置 → 模型」里把对应模型改名后，插件内使用派生键即可——模型页的修改不回写插件配置。

> 🧩 本插件只负责 **DSH ↔ llama.cpp 的连接与控制**：不包含 `llama-server` 本体，也不负责下载模型——分别来自上游 [llama.cpp](https://github.com/ggml-org/llama.cpp) 与社区量化发布（如 Hugging Face）。

***

## 📦 安装

### 方式一：一条命令（推荐）

```bash
# dsh 已在环境变量（全局安装过 @deepseek-ai/dsh）
dsh plugin --profile web add dsh-local-llm-controller

# dsh 命令未全局安装（@deepseek-ai/dsh 不在 PATH）时，用 npx 临时拉取 CLI（Node 自带，无需额外安装）：
npx @deepseek-ai/dsh plugin --profile web add dsh-local-llm-controller
```

装完**重启 DSH Web**（本包声明了 `dsh.bundle`，注册自动完成，无需手动配置）。卡片出现在 **设置 → 插件 → Local LLM Controller**。

### 🗑️ 卸载

1. 模型在运行就先在卡片点「停止」（不点也行——DSH 重启时插件自行清理子进程）。
2. 一条命令卸载（注册自动移除，无需改文件）：
   ```bash
   dsh plugin --profile web remove dsh-local-llm-controller
   ```
3. 重启 DSH Web，卡片即消失。

| 卸载后的残留（可选清理）                      | 说明                               |
| --------------------------------- | -------------------------------- |
| `settings.yaml` 的 `local-llm` 段   | 插件写的状态/配置，留着无害，想干净就删             |
| `llm-pi-ai.providers.*`（派生键的本地条目） | **建议保留**：改用手动方式跑同端口服务时仍可用；确实不用再删 |
| `~/.dsh/local-llm.config.json`    | 旧安装脚本时代的遗留，可删                    |
| 模型文件 / llama.cpp 本体               | 与插件无关，保留                         |

***

## 📐 推荐启动参数（8 套，v1.x 实测基准）

> 插件自动管理的参数无需手动添加：`-m` / `-a` / `--port` / `--host` / `--api-key`（有密钥时），以及视觉模式的 `--mmproj` / `--image-min-tokens`。下面每行一套，按「当前组合」粘贴进对应启动参数组即可；也可用于手动运行 `llama-server`。

**35B**（Qwen3.6-35B-A3B，MoE）：

```
35B · 文本 · 快速    : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 32768 -ncmoe 20 --reasoning-budget 2048 --metrics --slots
35B · 文本 · 长上下文 : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 131072 -ncmoe 22 --reasoning-budget 2048 --metrics --slots
35B · 视觉 · 快速    : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 32768 -ncmoe 24 --reasoning-budget 2048 --metrics --slots
35B · 视觉 · 长上下文 : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 98304 -ncmoe 24 --reasoning-budget 2048 --metrics --slots
```

**9B**（Qwen3.5-9B，Dense）：

```
9B · 文本 · 快速    : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 32768 --metrics --slots
9B · 文本 · 长上下文 : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 65536 --metrics --slots
9B · 视觉 · 快速    : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 32768 --metrics --slots
9B · 视觉 · 长上下文 : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 65536 --metrics --slots
```

> 📌 35B 的 `-ncmoe`（MoE 专家卸载数）与 `--reasoning-budget` 为实测优化项；长上下文可靠上限 `-c 131072`（35B，ncmoe 22）/ `-c 65536`（9B）——`-c 196608` 是硬断崖（KV 溢出共享内存）。更完整的实测数据、选型结论与实验方法见下方「推荐阅读」。

***

## 📚 推荐阅读

- [本地模型调优全历程终版存档](docs/measurements/ctx_scan_report.md)：35B / 9B / 27B 多模型实测对比、调优结论、选型建议与长上下文安全上限汇总。
- [**llm-experiment-design · DSH 调优 Skill**](docs/llm-experiment-design/SKILL.md)：给新 GGUF 做深度调优用的 Skill——按「运行时探查 → 必要性驱动扫描 → 四件套测量 → 能力验证」流程安排脚本与判读，最终输出一套可复现的最优启动参数（MoE/dense 通用）。

***

## 📄 License

[MIT](LICENSE)
