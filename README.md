<div align="center">

# 🚀 dsh-local-llm-controller

<img src="images/wallpaper.jpg" alt="dsh-local-llm-controller" width="100%">

**DSH 插件：设置页一键启停本地 llama.cpp，让本地大模型成为 DSH 会话模型**

[![npm version](https://img.shields.io/npm/v/dsh-local-llm-controller?color=blue)](https://www.npmjs.com/package/dsh-local-llm-controller)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/Lbunc/dsh-local-llm-controller/blob/main/LICENSE)
[![llama.cpp](https://img.shields.io/badge/llama.cpp-upstream-8B5CF6)](https://github.com/ggml-org/llama.cpp)
[![DSH Artifact](https://www.dsh.so/badge/dsh-local-llm-controller.svg)](https://www.dsh.so/artifact/dsh-local-llm-controller/)
[![Install on DSH](https://www.dsh.so/badge/install/dsh-local-llm-controller.svg)](https://www.dsh.so/artifact/dsh-local-llm-controller/)

[English](README.en.md) | **简体中文**

</div>

***

## ✨ 概览

在 DSH（DeepSeek Harness）的「设置 → 插件」页面一键启停本地 [llama.cpp](https://github.com/ggml-org/llama.cpp) `llama-server`，把本地大模型直接接入 DSH 作为会话模型。

> ⚠️⚠️⚠️ DSH在`0.1.7-rc.1` 版本进行了大量底层改动，请把插件升级到`v2.1.0`及之后的版本，以确保兼容性。

***

##  🥳 安装后的使用流程

### 使用流程

1. **槽位 A / B 配置**：各填一个**模型文件夹路径**（内含模型 GGUF，含视觉的还要有 mmproj）→ 点「**保存配置**」。
2. **启动区**：选槽位 A/B → 选模式（文本/视觉）→ 选预设（快速/长上下文）→ 点「**启动**」

### ⚠️ 注意事项

- **本插件只适配 DSH 的 RC 正式分支**（当前验证版本 `0.1.7-rc.1`；其他分支不保证兼容）。
- **同一插槽换模型文件后**：Provider Key 随文件名变化——旧键在「设置 → 模型」里**不会自动覆写/删除**，需要**手动删除旧条目**后，再点「添加到模型列表」写入新条目。
- **视觉图片**：llama-server（旧构建）的图片解码器**不支持 WebP**。本插件已把 DSH 的图片请求预算提高到 16MiB / 4096²，常规 **PNG/JPEG 截图/大图会原样直达**；**WebP 源文件**请先转成 PNG/JPEG 再发。
- 模型文件夹里的 **mmproj**（视觉投影器）自动识别、视觉模式自动挂载，且必须在文件名中包含 `mmproj`。
- 想固定 Provider Key（免去每次换文件后重选模型）：在「设置 → 模型」里把对应模型改名后，插件内使用派生键即可——模型页的修改不回写插件配置。

> 🧩 本插件只负责 **DSH ↔ llama.cpp 的连接与控制**：不包含 `llama-server` 本体，也不负责下载模型——分别来自上游 [llama.cpp](https://github.com/ggml-org/llama.cpp) 与社区量化发布（如 Hugging Face）。

***

## 📦 安装

### 一条命令（推荐）

```bash
# dsh 已在环境变量（全局安装过 @deepseek-ai/dsh）
dsh plugin --profile web add dsh-local-llm-controller

# dsh 命令未全局安装（@deepseek-ai/dsh 不在 PATH）时，用 npx 临时拉取 CLI（Node 自带，无需额外安装）：
npx @deepseek-ai/dsh plugin --profile web add dsh-local-llm-controller
```

装完**重启 DSH Web**（本包声明了 `dsh.bundle`，注册自动完成，无需手动配置）。卡片出现在 **设置 → 插件 → Local LLM Controller**。

### 🧩 插件管理器（图形界面）

DSH Web 侧边栏打开「**插件**」页 → 点「**添加插件**」→ 输入包名 `dsh-local-llm-controller` → 选择安装源 → 点「**安装**」，装完同样**重启 DSH Web**。

<p align="center"><img src="images/plugin-manager-add.png" width="420" alt="DSH 插件管理器：添加插件对话框，输入 dsh-local-llm-controller"></p>

### ⬆️ 升级

一条命令升到最新版（`add` 会重新解析版本并更新依赖，已是最新时提示 `Already up to date`）：

```bash
dsh plugin --profile web add dsh-local-llm-controller
```

装完**重启 DSH Web**（宿主侧代码在启动时加载）。其他常用形式：

| 目的                          | 命令                                                            |
| --------------------------- | ------------------------------------------------------------- |
| 先看有没有新版（无输出 = 已是最新）         | `dsh plugin --profile web outdated`                           |
| 装指定版本                       | `dsh plugin --profile web add dsh-local-llm-controller@2.1.0` |
| 用 `link:` 开发方式安装的（非 npm 安装） | 无需升级命令，`git pull` 后重启 DSH 即可                                  |

> 安装/升级时若出现 `Issues with peer dependencies found` 警告属正常现象（本插件的 peer 由 DSH 宿主提供，不随包安装），不影响使用。

### 🗑️ 卸载

1. 模型在运行就先在卡片点「停止」（不点也行——DSH 重启时插件自行清理子进程）。
2. 若已把「默认模型」或某个预设设成本地模型（provider `dsh-local`），先改回云端模型再卸载，否则默认模型悬空。
3. 一条命令卸载（bundle 注册与 `link:` 依赖自动移除）：
   ```bash
   dsh plugin --profile web remove dsh-local-llm-controller
   ```
4. 重启 DSH Web，卡片即消失。

卸载命令会自动清掉 profile 的 bundle 注册和依赖（`profiles/web/package.json`、`pnpm-lock.yaml`），以下内容**不会**被自动删除（v2.1.0 / DSH 0.1.7-rc.1 实测）：

| 卸载后的残留（可选清理）                             | 说明                                                                 |
| ---------------------------------------- | ------------------------------------------------------------------ |
| `~/.dsh/local-llm.config.json`           | **卡片配置**（llama.cpp 目录、端口与 8 组启动参数）。打算重装就别删；彻底弃用再删                  |
| `llm-pi-ai.providers.dsh-local`（`profiles/web/cordis.patch.yml`） | 「添加到模型列表」写入的模型页条目；改手动跑同端口服务时仍可用，不用就删                               |
| `pnpm-workspace.yaml` 的版本豁免行             | remove 不回收的一行安装元数据（`dsh-local-llm-controller@…`），无害，可不管 |

> 从 v2.0.x 升级的用户：旧版写在 `settings.yaml` 的 `local-llm` 段已随 DSH 0.1.7 的一次性导入改名进 `settings.yaml.imported`，无程序再读它，不用处理。

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
- **[llm-experiment-design · DSH 调优 Skill](docs/llm-experiment-design/SKILL.md)**：给新 GGUF 做深度调优用的 Skill——按「运行时探查 → 必要性驱动扫描 → 四件套测量 → 能力验证」流程安排脚本与判读，最终输出一套可复现的最优启动参数（MoE/dense 通用）。

***

## 📄 License

[MIT](LICENSE)
