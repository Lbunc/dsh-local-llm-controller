---
name: llm-experiment-design
description: >-
  Use when setting up, benchmarking, or performance-tuning a local LLM served
  with llama.cpp (or similar) on user hardware: designing and running experiments
  through a necessity-gated scan (MoE expert offload, dense FFN offload, KV cache
  quantization, context limit, reasoning budget, threads, speculative decode),
  measuring with a four-signal harness (t/s + VRAM dedicated/shared + GPU util +
  CPU util), verifying quality and capability, and archiving results. Model- and
  version-agnostic: every branch is driven by runtime probing (GGUF metadata,
  server --help, nvidia-smi) rather than hardcoded sizes. Covers the pipeline from
  model-characteristic research to a verified, archived conclusion.
whenToUse: >-
  The user brings a new local model (GGUF) and wants it served or tuned, asks to
  benchmark speed, explore context limits, find optimal offload parameters, or
  compare configurations or models. Applies to both dense and MoE models.
  Not for API-only models or pure code tasks.
metadata:
  version: 5
  scope: llama.cpp, single GPU, single instance, MoE and dense models, Windows/PowerShell 7
---

# 本地大模型性能实验设计（索引）

**把一次"新模型调优"组织成六段流程。所有分流都来自运行时探查的事实，不预设模型规模。**

> 本文件是**索引**。细节在 `reference/` 下的子文档里，**按需读取**；脚本在 `scripts/`；冻结题库在 `bank/`。
> 本 skill 只沉淀**通用方法**：不含任何具体机器 / 模型的实测数值与案例（那些属于当次报告）。

## 目录

| 段 | 子文档 | 内容 |
|---|---|---|
| 0 | [`reference/00-probe.md`](reference/00-probe.md) | 资料检索、参数存在性探查、GGUF 派生量、上游默认值取证、四个能力标记的分流 |
| 1 | [`reference/01-environment.md`](reference/01-environment.md) | 部署约束、硬件清单、干净基线、视觉模型的两个必问项 |
| 2.0–2.1 | [`reference/02-offload.md`](reference/02-offload.md) | 必要性判定门、统一卸载框架（MoE `-ncmoe` / dense `-ncffn`）、两阶段取值法 |
| 2.2 | [`reference/03-kv-quant.md`](reference/03-kv-quant.md) | KV 量化档取舍、KL 与 PPL 的分工 |
| 2.3 | [`reference/04-context.md`](reference/04-context.md) | 上下文三问：装得下 / 能用 / 好用 |
| 2.4 | [`reference/05-reasoning-budget.md`](reference/05-reasoning-budget.md) | **硬规则 `-rb = -c/2`**、`max_tokens` 算法、截断语义 |
| 2.5 | [`reference/06-threads.md`](reference/06-threads.md) | 线程数取证与测法 |
| 2.6 / 3.3 | [`reference/07-speculative.md`](reference/07-speculative.md) | MTP / draft：必测项、必问项、专项测量 |
| 3.0–3.2 / 3.5 | [`reference/08-measurement.md`](reference/08-measurement.md) | 三层测量阶梯、工具准入、四件套、窗口规则、harness 缺陷清单 |
| 3.4 | [`reference/09-capability-bank.md`](reference/09-capability-bank.md) | 能力题库用法、区分度门、同轴复现检验、答案键验证、判分 |
| 4 | [`reference/10-reliability.md`](reference/10-reliability.md) | 可靠性校验、对照组门、存档、多模型横向对比 |

## 核心不变量（所有实验都必须满足）

1. **运行时探查驱动，不预设规模**
   不假设模型规模或架构。分流依据 = GGUF 元数据 + 本机 `--help` + `nvidia-smi`（`00-probe.md`）。
   脚本必须参数化：不得把模型名、路径、量化档写死为条件。

2. **必要性判定门：满足才扫，否则跳过**
   每个维度先过门（`02-offload.md` 2.0）。不要因为"可以扫"就去扫。

3. **一次只变一个变量**
   每实验只改一个参数，其余全固定。先粗扫找断崖，再细扫定位。

4. **物理信号优先于速度读数**
   显存 `shared` 的分配行为是确定性的，是判定溢出的**唯一硬信号**；t/s 只用于量化幅度。

5. **分层测量，不上升层级**
   能用 L1（`llama-bench` 单进程多值）回答的，绝不进 L2（server 四件套）；只有"装得下 / 能用 / 质量"才上升。
   **每个带数字的结论必须标注层级**（`08-measurement.md`）。

6. **★思考预算 = 上下文的一半**
   `--reasoning-budget = n_ctx / 2`（硬规则）。且 `-rb` **不是硬截断** → `max_tokens` 必须另算并给足
   （`05-reasoning-budget.md`）。

7. **★测量缺陷不得记成模型特性**
   截断记"未产出"不判 0；harness 缺陷清单（`08-measurement.md` 8.3）命中即修。

8. **★能力结论必须过区分度门**
   全对 / 全 0 → 只能写"测不出差异"。差异题少时做**同轴复现检验**，报告样本数 n（`09-capability-bank.md`）。

9. **★题库是冻结资产，跑题时禁止联网**
   `bank/*.json` 自包含（prompt / 官方答案键 / 判分规格 / 用例）。建库与验键是一次性活动。

10. **★测完必恢复**
    杀掉测试进程、释放端口、确认显存回落。不留脏状态。

## 跨设备使用

本 skill **不硬编码任何工作目录、模型路径或 llama.cpp 安装位置**。

| 需要的东西 | 如何提供 | 默认 |
|---|---|---|
| llama.cpp 二进制目录 | `-LlamaDir <dir>` | 环境变量 `LLAMA_CPP_DIR` |
| 输出与日志目录 | `-WorkDir <dir>` | 环境变量 `DSH_WORK_DIR`，否则当前目录 |
| 模型文件 | `-ModelPath <gguf>` | 无默认，必填 |
| 题库 / 脚本 | 相对 skill 根目录自动解析 | `$PSScriptRoot` 推导，无需配置 |

脚本自行创建 `<WorkDir>/logs` 与 `<WorkDir>/data`；填充语料由内置合成器生成（不依赖任何外部语料文件）。

## 脚本索引（`scripts/`）

| 脚本 | 用途 | 关键参数 |
|---|---|---|
| `gguf_probe.ps1` | GGUF 运行时探查 + 能力标记 | `-Path <gguf>` `-Json` |
| `start_server.ps1` | 服务启动库（其他脚本 dot-source 它） | 见文件头；含 `Get-GgufMeta` / `Get-Vram` / `Get-CpuUtil` / `Start-UtilSampler` |
| `scan_offload.ps1` | 统一卸载扫描 | `-OffloadMode ncmoe\|ncffn\|ngl` `-Start` `-End` `-Step` |
| `scan_maxctx.ps1` | "装得下"边界扫描 | `-NcmoeList` / `-NcpuFfnList` `-CtxList` |
| `prefill_profile.ps1` | "能用多深"分段 prefill 剖析 | `-Ctx` `-StageTokens` `-PpsFloor` |
| `bench_decode_util.ps1` | decode 相四件套 + 线程扫描 | `-Threads` 列表 |
| `run_bank.ps1` | 能力题库 runner（两档通用） | `-Tier base\|hard` `-Specs` `-Only` `-MaxTokensOverride` |
| `grade_bank.py` | 程序化判分（8 种题型）+ 区分度门 | `--bank` `--answers` `--out` |
| `recover_bank_json.py` | 从逐题日志还原结果（中断不重跑） | `--logs` `--bank` `--out-dir` |
| `verify_bank_budget.ps1` | 跑题前预算校验（真实 token 数 + 深填充 `shared`） | `-Ctx` `-Specs` |

`-Specs` 统一格式：`'名字|模型路径|卸载档'`，卸载档为 `ncmoe:N` / `ncffn:N` / `ngl:N` / `none`。

## 题库索引（`bank/`）

| 文件 | 内容 |
|---|---|
| `10q.json` + `10q.md` | 基础 10 题（逻辑 / 推理 / 算术 / 编程），带官方答案键与判分规格 |
| `10q_hard.json` + `10q_hard.md` | 困难 10 题（近期竞赛数学 / 研究生科学 / 叙事推理 / 约束逻辑 / 长上下文 / 近期编程） |
| `reprobe_zebra_6x6.json` | 区分度轴复现检验用题库（同轴、互不共享解实例） |

题库为**机器可读的权威副本**：跑题与判分只依赖它，不需要任何源数据或网络。

## 快速开始

```powershell
# 1) 探查模型（决定后续走哪些分支）
pwsh scripts/gguf_probe.ps1 -Path <model.gguf>

# 2) 干净基线与硬件清单（reference/01-environment.md）
#    —— 人工确认环境已清空后，用一个短请求记录稳态 t/s 与空闲 shared

# 3) 按判定门选维度扫描（例：MoE 卸载断崖）
pwsh scripts/scan_offload.ps1 -ModelPath <model.gguf> -Alias m -LlamaDir <dir> `
     -OffloadMode ncmoe -Start 16 -End 26 -Step 2

# 4) 上下文能力（装得下 → 能用）
pwsh scripts/scan_maxctx.ps1      -ModelPath <model.gguf> -Alias m -NcmoeList 20,22 -CtxList 65536,131072
pwsh scripts/prefill_profile.ps1  -ModelPath <model.gguf> -Alias m -Ncmoe 22 -Ctx 131072

# 5) 能力验证（跑题前先校验预算）
pwsh scripts/verify_bank_budget.ps1 -LlamaDir <dir> -Ctx 65536 -Specs @('m|<model.gguf>|ncmoe:22')
pwsh scripts/run_bank.ps1          -LlamaDir <dir> -Tier hard -Ctx 65536 -Specs @('m|<model.gguf>|ncmoe:22')
python scripts/grade_bank.py       --bank bank/10q_hard.json --answers "<WorkDir>/data/bank_hard_answers_*.json"
```
