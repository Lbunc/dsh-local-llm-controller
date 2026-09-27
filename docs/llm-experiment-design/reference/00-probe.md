# 00 · 特性探查（第 0 步，强制）

> 规则：**先研究，再动手**。所有后续分流都依据本步得到的运行时事实，不预设模型规模。
> 本步产出一份"特性清单"，它决定后面哪些维度要扫、哪些直接跳过。

## 0a. 公开资料检索

搜索词至少覆盖：

| 目的 | 搜索词 |
|---|---|
| 已知坑 | `<模型> GGUF llama.cpp` |
| 架构 / 原生上下文 | `<模型> architecture context rope` |
| 推荐采样 | `<模型> sampling recommended` |
| 思考模式 | `<模型> thinking reasoning` |
| 量化档差异 | `<模型> quantization` |

公开资料只用于**形成假设**；参数是否存在、语义如何，一律以本机 `--help` 与 GGUF 元数据为准（见 0b/0c）。

## 0b. 参数存在性探查（强制）

llama.cpp 迭代快，参数语义会变。**对每个要用到的参数，逐一在本机 `--help` 输出里确认存在**；缺失即报错退出，不静默跑错。

| 类别 | 参数 | 用途 |
|---|---|---|
| 架构 / 卸载 | `-ngl` `-cmoe` `-ncmoe` `-ncffn` `-fa` | 层 / 专家 / dense-FFN 卸载、flash-attn |
| 视觉 | `-mm` `--mmproj-offload` `--no-mmproj-offload` `-mmdev` `--image-min/max-tokens` | 投影器加载与卸载位置（触发 `01-environment.md` 两个必问项） |
| 投机 | `--spec-type` `--spec-draft-n-max` `--draft-*` `-ctkd` `-ctvd` | MTP / ngram / draft + draft KV 量化档（触发 `07-speculative.md` 必问项） |
| 缓存 | `--cache-type-k` `--cache-type-v` `-c` `-ub` `-b` | KV 量化、上下文、batch |
| 线程 | `-t` `-tb` `-np` | CPU 线程、并行槽 |
| 采样 | `--temp` `--top-k` `--top-p` `--min-p` | 采样参数 |
| 惩罚 | `--repeat-penalty` `--presence-penalty` | 重复 / 存在惩罚 |
| 思考 | `--reasoning-budget`（确认确切名） | 思考上限（取值规则见 `05-reasoning-budget.md`） |
| 其他 | `--mlock` `--mmap` `--metrics` `--slots` `--api-key` | 内存、监控、鉴权 |

配套脚本：`scripts/start_server.ps1` 内的 `Test-ServerHelp` 会对本次要用的参数做同样校验。

## 0c. GGUF 运行时探查

```
pwsh scripts/gguf_probe.ps1 -Path <model.gguf>          # 人读
pwsh scripts/gguf_probe.ps1 -Path <model.gguf> -Json    # 机器读
```

读出的原始键 → 派生量（**全部由元数据算出，不查表、不写死**）：

| 派生量 | 算法 | 用途 |
|---|---|---|
| `isMoE` | `expert_count > 0` | 决定卸载路径：MoE→`-ncmoe`，dense→`-ncffn` |
| `kvLayers` | `ceil(block_count / full_attention_interval)` | 算 KV/token |
| `KV/token` | `kvLayers × head_count_kv × (key_length + value_length) × 量化字节` | 显存账（`04-context.md`） |
| `perLayerMB` | `文件大小 / block_count` | 卸载步进粒度（`02-offload.md`） |
| 每层 KV 能换多少 ctx | 由上面两项相除得出 | "多卸一层能多撑多少上下文" |
| `has_thinking` | chat template 含思考开关 | 命中 → `--reasoning-budget = n_ctx/2`（硬规则） |
| `hasMTP` | 存在 `blk.*.nextn.*` 张量 | 命中 → **必测**"无 MTP vs 带 MTP" + 先问用户 draft KV 档 |
| `hasVision` | 存在 mmproj / vision / clip 张量或元数据 | 命中 → **必问**两个问题（`01-environment.md`） |

**分流后果**（后续只走命中的分支）：

```
isMoE?  ──是──▶ 卸载扫 -ncmoe
        └─否──▶ 卸载扫 -ncffn（不要用减少 -ngl 代替，见 02-offload.md）
has_thinking? ──是──▶ rb = n_ctx/2
hasMTP?       ──是──▶ 必测 MTP 配对 + 问 draft KV 档
hasVision?    ──是──▶ 必问「做不做视觉测试」「mmproj 放 GPU 还是 CPU」
```

## 0d. 上游默认值取证（扫描起点，不靠猜）

llama.cpp 对每个参数都有一个"自动"值。**先取证，再以它为扫描起点**，而不是从 0 或最大值开始。

| 要取证的对象 | 取证方式 | 得到 |
|---|---|---|
| 上游 auto | `llama-bench.exe -h` 中该项的 `(default: X)` | 本机自动解析值 |
| server 的 auto | **不传该参数**启动 server，读日志里的 `n_threads` 等 | server 实际取值 |
| 硬件拓扑 | `Get-CimInstance Win32_Processor`（或等价命令） | 物理核数 / 逻辑核数 |
| GPU 显存 | `nvidia-smi --query-gpu=...`（多卡按目标卡过滤，**不要取 `-First 1`**） | 显存总量与当前占用 |

规则：

1. **扫描起点取上游 auto**。
2. 若实测峰与 auto 不一致，**以实测为准**，并在报告中写明差异。
3. 显式传入的参数优先于自动调整：显式给出卸载参数后，`--fit` 一类自动机制会放弃调整（日志里会有 abort 记录）——即**自动机制不能替代显式扫档**。
4. 不要假设 auto 的语义（例如"线程数 = 逻辑核数"），一律取证后再用；`06-threads.md` 给出了一项常见的语义反直觉之处。

## 0e. 本步完成判据

- [ ] 公开资料已收集（至少 0a 的 5 类）
- [ ] 本次要用的每个参数都已在本机 `--help` 中确认存在
- [ ] GGUF 派生量已算出，四个能力标记（MoE/thinking/MTP/vision）已确定
- [ ] 上游 auto 值已取证，扫描起点已定
- [ ] 触发的"必问项"已问过用户（视觉 / draft KV）

未满足任一项就进入扫描，等于用假设代替事实。
