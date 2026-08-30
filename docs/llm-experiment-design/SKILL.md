---
name: llm-experiment-design
description: >-
  Use when setting up, benchmarking, or performance-tuning a local LLM
  served with llama.cpp (or similar) on user hardware — designing and running
  experiments via a necessity-gated scan (layer offload for dense, MoE expert
  offload, KV cache, context limit, reasoning budget, threads, speculative
  decode), measuring with a four-signal harness (t/s + VRAM dedicated/shared
  + GPU util + CPU util), verifying results, and delivering a launcher + DSH
  config. Model/version-agnostic: driven by runtime probing (GGUF metadata +
  llama-server --help + nvidia-smi), not hardcoded size. Includes a
  capability-verification phase (agent + coding tasks with quantitative
  scoring). Covers the full pipeline from model-characteristic research to
  final archive.
whenToUse: >-
  The user brings a new local model (GGUF) and wants it served/tuned, asks to
  benchmark speed, explore context limits, find optimal offload params, or
  compare configurations. Applies to both dense and MoE models. Not for
  API-only models or pure code tasks.
metadata:
  version: 3
  scope: llama.cpp on Windows/NVIDIA, single GPU, MoE and dense models, single-instance
---

# 本地大模型性能实验设计（Local LLM Experiment Design）

把一次"新模型调优"组织成 **特性探查 → 基线 → 必要性驱动扫描 → 四件套测量（含能力验证） → 校验存档 → 交付恢复** 六段流程。**规则全部基于运行时探查的特性，不预设模型规模**；文末案例速查仅作参照。

## 核心原则

1. **运行时探查驱动，不预设规模**：不假设"这是 9B/35B"或"这是 MoE"；所有分流判断来自 GGUF 元数据 + `--help` 参数可用性 + `nvidia-smi`。脚本参数化，不出现具体 B 数作为条件。
2. **先研究，再动手**：测试前先 `web_search` 收集公开特性 + `llama-server --help` 探查参数（第 0 步强制）。多数弯路（KV 溢出、卸载断崖、思考截断）在文档/社区有线索。
3. **针对性有效**：每个扫描维度先过必要性判定门，确认真的会动才扫，否则用默认跳过。
4. **一次只变一个变量**：每实验只改一个参数，其余全固定；先粗扫找断崖，再细扫定位。
5. **物理信号优先于速度读数**：t/s 波动 ±10%，而 shared 显存分配是确定性的，作为判定溢出的硬依据。
6. **测量可重复**：关键点 ≥2 次重复；异常必重测并记修正，不解释就存档等于没测。
7. **测完必恢复**：杀测试子进程、释放 55555，不留脏状态。

---

## 第 0 步（强制）：web_search + llama-server --help 探查

动手前必须执行两件事。

### 0a. web_search 收集模型特性
搜索词至少覆盖：`<模型> GGUF/llama.cpp`（已知坑）、`<模型> architecture/context/rope`（架构/原生上下文）、`<模型> sampling recommended`（推荐采样）、`<模型> thinking/reasoning`（思考模式）、`<模型> quantization`（量化档）。

### 0b. llama-server --help 参数探查（强制）
llama.cpp 版本迭代快，参数语义会变。**对每个要用的参数逐一在 `--help` 输出里确认存在**（web 信息可能滞后）。探查清单：

| 类别 | 参数 | 用途 |
|---|---|---|
| 架构 | `-ngl` `-cmoe` `-ncmoe` `-fa` | 层/专家卸载、flash-attn |
| 缓存 | `--cache-type-k` `--cache-type-v` `-c` `-ub` `-b` | KV 量化、上下文、batch |
| 线程 | `-t` `-tb` `-np` | CPU 线程、并行槽 |
| 采样 | `--temp` `--top-k` `--top-p` `--min-p` | 采样参数（必备默认 0.6/20/0.95/0） |
| 惩罚 | `--repeat-penalty` `--presence-penalty` | 重复/存在惩罚（必备默认 1/0） |
| 思考 | `--reasoning-budget`（确认确切名） | 思考上限 |
| 投机 | `--spec-type` `--spec-draft-n-max` `--draft-*` | MTP/ngram/draft |
| 其他 | `--mlock` `--mmap` `--metrics` `--slots` `--api-key` | 内存、监控、鉴权 |

任一参数缺失即报错退出，不静默跑错。

### 0c. GGUF 元数据提取
用 `gguf_keys_ctx.ps1` 读：架构、`block_count`、`embedding_length`、`head_count_kv`、`key_length`/`value_length`、`context_length`、`expert_count`、`full_attention_interval`、rope。

**关键派生量**（由元数据算出，不查表不写死）：
- `isMoE = (expert_count > 0)`
- `每层权重 ≈ 文件大小 / block_count`（卸载步进粒度）
- `KV/token ≈ KV层数 × head_count_kv × key_len × 2 × 量化字节`
- `有思考模式 = chat template 含 enable_thinking`

---

## 第 1 步：环境清单与基线（含部署约束）

### 1a. 部署约束（固定，写进所有脚本）
- **端口 = 55555**：测试前确认插件 slot 处于 `stopped`，否则端口冲突；测完必须释放。
- **apiKey 留空**：server 不传 `--api-key`（不校验），客户端 header 发 `Bearer dsh-local-llm`。
- **必备采样/惩罚**：`--temp 0.6 --top-k 20 --top-p 0.95 --min-p 0.0 --repeat-penalty 1 --presence-penalty 0 --slots --metrics`。
- **最小上下文 = 32K**：所有 n_ctx ≥ 32768；上下文扫描起点 32768。
- **单实例**：`-np 1` 固定；不扫 `--parallel`/`--cont-batching`；KV 池可激进吃满。

### 1b. 硬件清单
GPU 显存总量与当前占用（`nvidia-smi`，多卡按目标卡 PCI ID 过滤，勿取 `-First 1`）、CPU 核/线程数、llama.cpp 版本。

### 1c. 流程
1. **关后台**：提醒用户关浏览器等占显存/CPU 程序（同时污染显存读数与 t/s）。
2. **加载验证**：确认 `/props` 的 n_ctx、chat template；发短请求确认对话正常。
3. **基线**：32K 下短生成稳态 t/s + 空闲 shared + 空闲 CPU。记录"干净环境基线"，后续所有实验据此对比。

---

## 第 2 步：必要性驱动扫描（判定门过滤，每项独立成实验）

### 2.0 必要性判定门（核心）
每个维度先过判定门，**满足才扫，不满足用默认跳过**。判定依据全部来自运行时探查的特性：

| 维度 | 判定门（满足才扫） | 跳过时的默认 |
|---|---|---|
| **卸载（统一框架，见 2.1）** | 权重 + 目标上下文 KV 超显存 | 不超 → 见下两行 |
| → MoE 路径 `-ncmoe` | `isMoE` 且超显存 | MoE 放得下 → `-ncmoe 0` |
| → dense 路径 `-ngl` 减小 | 非 MoE 且（权重超显存 **或** KV 量化后仍溢出） | dense 放得下且 KV 不溢 → `-ngl 99` |
| **KV 量化 q8_0** | KV/token × 目标上下文 > 显存余量 30% | 占比低 → 默认 q8_0 不扫 |
| **上下文极限** | 用户实际需要 >32K 长上下文 | 只用短上下文 → 固定 32K |
| **reasoning-budget** | 有思考模式（模板含 enable_thinking） | 无思考 → 跳过 |
| **-t/-tb 线程** | 有权重或专家卸载到 CPU | 全 GPU → 跳过 |
| **spec 解码** | GPU 有空闲(util<80%) 且 `--help` 支持 | GPU 饱和或无支持 → 跳过 |
| ~~`--parallel`/`--cont-batching`~~ | — | 单实例，永远跳过 |

### 2.1 统一卸载框架（dense -ngl / MoE -ncmoe 同构）
本质：**把部分计算踢到 CPU，腾显存给 KV，避免 KV 溢出到 shared**。判据：shared 显存回落到基线 = 最优。共用 `scan_offload.ps1`，参数化 `OffloadMode`。

**MoE（`-ncmoe N`，前 N 层专家放 CPU，attention 仍 GPU）**
- 方向：从大往小减（卸载越来越少）找断崖。步进按每 N 层专家权重大小（如每 2 层 ~0.9GB → 步进 2）。
- 断崖形态：N 小于阈值时权重+KV 超显存 → KV 落 shared → 速度断崖；N 越大腾越多显存，同填充速度略降。
- **★ncmoe ↔ 上下文上限**：N 越大 → GPU 权重越少 → 给 KV 腾显存越多 → 能撑的上下文越高（35B 实测 18→19→20 shared 递减）。**但长上下文速度掉**（192K 仅 23 t/s）。
- 判据：空闲 shared ≈ 基线；速度取长上下文（≥20k）值。

**dense（`-ngl` 从模型实际层数 n 往下减）**
- 方向：n → n-1 → n-2… 卸载越来越多。步进按每层权重（小模型可能 ~150MB → 步进 1-2 层）。
- **代价高于 MoE**：dense 每层含 attention+FFN，每步必读所有卸载层；MoE 专家只在被激活时才算。故 dense 应**先试 KV 量化省显存，KV 仍溢出才动 -ngl**。
- 判据：同上，shared 回落基线 = 最优。

### 2.2 KV 缓存量化（--cache-type-k/v）
- q8_0 省一半 KV 显存，质量损失通常可忽略 → 默认推荐。
- **★q4_0 也值得扫**：再省一半 KV，且把上下文断崖大幅推高（35B 实测 80K→160K）。**判定关键 = q4_0 是否损伤能力**：用阶段 B 能力题 q8_0 vs q4_0 同题对照（唯一变量=KV 类型）。UD-35B 实测 q4_0 能力 100% 等同 q8_0 → 能力无损，故优先 q4_0。
- **排序**：q8_0/f16 对照确定下限；q8_0/q4_0 对照确定是否上 q4_0。

### 2.3 上下文极限扫描（既测"能装下"也测"能用"）
- **判据（物理信号）**：每点启动后读 `Get-Counter '\GPU Adapter Memory(*)\Shared Usage'`（带 `(*)`，多卡按目标卡过滤）；shared 从基线跳升 = 溢出开始。t/s 只作辅助。
- **方法**：C 取 32K→64K→96K→128K 等比步进（起点 32K），每点：重启 server → 空闲显存 → 2×短测试 → 深填充测试（填充≈ C-8000）。
- **同填充对照**：固定同一填充深度，对比不同 C——证明 C 本身是否影响速度（未溢出时无影响，掉速随对话长度走）。
- **★可用上下文（区分"能装下" vs "能用"）**：MoE/大模型的极限上下文常**不可用**——context 越大 prefill 越慢，一次请求可能 prefill 就耗数分钟。**每点必须同时记录 prefill**（`timings.prompt_per_second` / `prompt_ms` / 总墙钟 `prompt_ms+predicted_ms`）。判断"可用上下文"不能只看 shared/生成速度：
  - **达到该上下文的 fill-time**：深填充（≈C-8000）能否在可接受时间完成（填不满/超时 = 不可用）。
  - **一次实际请求的总墙钟**：即使生成仍快，若 prefill 极慢，该上下文对真实交互不可用。
  - **结论**：最大可用上下文 = 生成速度可接受 **且** prefill/fill-time 可接受；"KV 能装下"只决定显存上限，不决定可用上限。
- **硬断崖**：某 C 点 shared 暴涨（>1GB）+ t/s 崩塌即死区，断崖在上一可看点与崩溃点之间。

### 2.4 思考预算（--reasoning-budget）
有思考模式必设上限：无预算时复杂题可能思考 9000+ tokens，吃掉 max_tokens 导致答案截断。**硬规则：DSH/客户端 maxTokens 必须 > reasoning_budget + 期望答案长度**。请求级 budget 常被忽略，用 server 启动参数 `--reasoning-budget N`。

### 2.5 CPU 线程（-t/-tb）
仅有 CPU 卸载时才扫（全 GPU 跳过）。固定卸载量，扫 -t。判据：CPU 接近 100% 且 t/s 不再升 = CPU 瓶颈；CPU 未满 = 瓶颈在别处（结合 GPU util + shared 显存判定）。

### 2.6 投机解码（MTP/ngram/draft）
判定门：GPU 有空闲（util<80%）且 `--help` 支持才扫。专项测量见 3.2。

---

## 第 3 步：测量规范（四件套 + 阶段 A/B）

> **每个测试点都必须同时记录四件套：t/s + 显存（ded/shared）+ GPU 利用率 + CPU 占用率** + 生成/prefill 分解。单一指标无法判定瓶颈。

### 3.0 四件套采集（★含 prefill 监控——决定"可用上下文"）
- **生成 t/s**：`timings.predicted_per_second`；每点 ≥2 次取稳态（首请求含 CUDA graph 捕获偏慢，弃用）。
- **prefill（必测）**：`timings.prompt_per_second` + `prompt_n` + `prompt_ms`，及一次请求**总墙钟** `prompt_ms + predicted_ms`。记录整条 `timings` 而非只取 predicted。
  - **core 教训**：大模型的**极限上下文可能"KV 能装下"但实际不可用**——context 越大 prefill 越慢，一次请求可能在 prefill 耗掉数分钟。**"能填满" ≠ "可用"**。单看 predicted 会高估可用上下文。
- **显存**：`Get-Counter ...Dedicated/Shared Usage`（多卡按目标卡过滤）。shared 跳升 = KV/编码器溢出（物理信号）。
- **GPU 利用率**：`nvidia-smi --query-gpu=utilization.gpu ... -l 1`，取生成阶段尾部均值（生成 500+ tokens 保证采样窗）。>90% = GPU-bound；<80% = 其他瓶颈。
- **CPU 占用率**：`Get-Counter '\Processor(_Total)\% Processor Time'`。CPU 接近 100% = CPU 卸载瓶颈。

### 3.1 阶段 A：吞吐扫描（稳定填充）
测试 prompt 用多轮对话（user 短问 + assistant 长答）填充，**结尾必须是问题**（纯重复文本会直接 EOS）。前缀复用陷阱：连续请求共享前缀时 `prompt_n` 是增量，eval t/s 仍是全深度。

### 3.2 投机解码专项
除四件套外**必须**额外记录：①**接受率**（`/metrics` 的 `spec_decode_num_accepted_tokens_total / num_draft_tokens_total`，>0.65 值得深挖，<0.5 无收益）；②**GPU 利用率**（原理是"draft 便宜+验证批量分摊"——GPU 必须有空闲才有收益，>90% 必无效）；③**显存增量**（MTP/draft 额外占显存，须对比开/关 spec 的空闲 ded）；④**开关对照**（关键结论重复 3 次）；⑤**n-max 扫描**（2/3/4/5 都要扫，接受率随 n 衰减）。

### 3.3 阶段 B：能力验证（agent + 编程，可量化）★新增
吞吐扫描确定最优参数后，跑能力题库验证模型能力 + 关键配置变更（如 KV q8_0 vs q4_0、reasoning-budget）是否影响能力。**能力题输出长度不确定，不能混进吞吐测量**（破坏 t/s 可重复性）。

**agent 题**（考验多步推理/规划/长程依赖/自我纠错）：多步规划、工具调用编排、长程依赖、自我纠错。
**编程题**（考验代码生成/调试/算法/系统设计）：算法实现（LRU/并查集/TTL 缓存）、调试题、重构题、系统设计。

**关键**：编程题自带 test cases（pwsh 跑生成代码验证），agent 题自带 checklist——能力测试**可打分**，不是主观判断。reasoning 模型思考可能很长，maxTokens 须留够（联动 2.4）。

### 3.4 进程与脚本规范
- server 必须后台 job 启动（Start-Process 子进程会随 pwsh 被杀连坐）；清理一律 job_kill + 验证端口释放（55555 必须释放，否则插件起不来）。
- Windows 用 **pwsh 7**（不要 powershell 5.1——UTF-8 无 BOM 中文脚本按 GBK 解析报错）。

---

## 第 4 步：可靠性校验与存档

- **异常必重测**：非单调、与物理信号矛盾、孤立低值 → 干净环境重测（后台负载污染最常见）。修正后更新结论，旧数据标注"已修正"保留。
- **物理信号 > 速度读数**：shared 显存、分配行为是确定性的；t/s 只用来量化掉速幅度。
- **存档格式**：`docs\` 下报告 md（方案/数据总表/结论/异常重测记录/能力题打分）+ 原始日志 txt；脚本留档可复跑。
- **与插件解耦**：skill 只沉淀通用实验方法。最终部署/启动产物（插件的 launch 配置、provider 设置）由 DSH 插件接口负责，实验结论已写入报告，不在此重复。

---

## 案例速查（worked example，非规则——规则见上文判定门）

### Qwen3.6-35B-A3B（MoE+SSM 混合）
MoE（expert_count>0），40 层仅 10 层有 KV（interval=4，2 KV heads×256），原生 ctx 262144。走 MoE 卸载路径；最优 `-ncmoe 20`（断崖 <20）。掉速曲线（干净环境）：≤53k ≈ 70-74 t/s → 119k ≈ 54。
- **★UD 变体（16.8GB）**：`-ncmoe` 越大上下文极限越高（18→19→20，shared 递减）；但**极限上下文常不可用**——192K 下 ncmoe 20 虽填满（180K），一次请求 wall **263.6s**（prefill 占大头），生成 23 t/s 实际不可用。教训：**判"可用上下文"必须看 prefill/总墙钟**；普通 32K-128K 用 ncmoe 18（更快），超高上下文才加大 ncmoe。

### Qwen3.5-9B（dense，含思考模式）
dense（expert_count=0），Q6_K ~6.5GB < 12GB 显存；**有思考模式**（默认开启，不设 budget 时思考吃光 max_tokens 导致 content 空，需 `reasoning_effort=none` 或 server `--reasoning-budget`）。**MTP 大幅收益**：dense 全 GPU、MTP util 74-78%（未饱和），n=3 最优，+60-74%。

### 关键教训
①速度测量必须先干净环境（浏览器污染）；②不要只测短生成（MoE 优势在长上下文稳态）；③shared 显存是 KV 溢出唯一可靠信号；④思考截断根因是 maxTokens 没留够预算余量；⑤**prefill 决定"可用上下文"——大上下文能装下≠能用**；⑥投机收益取决于 GPU 空闲度（饱和则无效）。

---

## 可选：多模型横向能力对比

> **可选模块**，不改变主流程。仅当用户想"多个模型谁更强 / 差距多大"时用。

**难点**不是测出分数，而是**让分数可信**——强模型间差距小，易被噪声淹没。**核心 = 让差异可复现、可归因**。若单轮测出差距但复测消失，大概率是题目歧义或随机波动。

**公平性三条硬规则**：
1. **同构同参**：所有模型用同一套判定参数与上下文/KV/卸载配置；**唯一变量 = 模型**（MoE 按其特性用它的卸载参数，记录注明）。
2. **同题同 prompt**：完全相同的题目文本；题目须**无歧义**（必要时给显式正反例）。
3. **objective 判定**：计算/代码题用**参考实现程序生成标准答案**（不手写、不预设），跑 test cases 判定；checklist 题判分前先人工核对判定正则。

**题目分级**：基础题（无区分度，粗筛弱者）→ 中档题（淘汰明显弱者）→ 难题（多跳精确计算/多步约束/长上下文依赖/条件调度，答案唯一需程序判定）→ 进阶难题（LeetCode/算法困难题，防题目歧义与随机波动）。

**关键教训**：①速度必须干净环境；②不要只测短生成；③题目歧义会制造假差距（merge-intervals）；④单次 FAIL 可能是随机波动（任何非预期差距重复 ≥3 次）；⑤手写标准答案易错（用 reference 程序）。

**MoE vs dense 差异**：MoE 长上下文不掉速（≤53k≈70-74→119k≈54）；dense 在 32K 断崖。能力上同档案两者**同档**，需完整题库统计非单次几题可比。

**具体用例**：9B(Q6) vs 27B(Q3) vs 35B(IQ4_NL,-ncmoe20)：基础题 9B 92%/27B 96%/35B 96%；复杂题 9B 88%/27B 100%/35B 100%。结论：9B 复杂多跳/反事实核查明显弱；27B ≈ 35B 能力同档，27B 更小更快更省显存（短上下文）+ 配置简单，35B 长上下文优势显著。

---

## 可复用脚本（`docs/measurements/scripts/`）

**通用（模型/版本无关）**：`start_server.ps1`（启动器）、`scan_offload.ps1`（dense -ngl / MoE -ncmoe 同构）、`bench_capability.ps1`（能力验证）、`gguf_keys_ctx.ps1`（元数据）、`write_bat_gbk.ps1`（GBK+CRLF 写 bat）。

**多模型横向对比**：`agent_hard_3model.ps1`（GAIA 类）、`agent_27b_vs_35b_leetcode.ps1`（LeetCode）、`lc_harness.py`（判分）、`agent_27b_vs_35b_hard.ps1`（精确计算）、`agent_compare_9b_27b.ps1`（简单粗筛）、`repeat_27b_l3.ps1`/`repro_27b_l3.ps1`/`repro_27b_l1.ps1`（单题复现）。

**本次 UD-35B（16.8GB）**：`scan_ud_ncmoe_down.ps1`（ncmoe 扫描）、`scan_ud35b_ctx.ps1`（上下文扫描）、`agent_ud_vs_uncensored.ps1`（模型能力对比）、`kv_q8_q4_ability.ps1`（KV 能力对照）、`deep192k_ncmoe.ps1`（192K 深填充对照）。

**历史/专用（参考用）**：`bench_35b_*`/`bench_9b_*`/`vision_*`/`bench_ngram*` 等各模型一次性基准。
