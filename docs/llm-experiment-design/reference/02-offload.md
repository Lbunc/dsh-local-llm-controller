# 02 · 统一卸载框架（第 2.0–2.1 步）

## 2.0 必要性判定门

每个维度**先过判定门**：满足才扫，不满足用默认值跳过。判定依据全部来自 `00-probe.md` 的运行时事实。

| 维度 | 判定门（满足才扫） | 不满足时的默认 |
|---|---|---|
| **卸载** | 权重 + 目标上下文 KV 超显存 | 不超 → 见下两行 |
| → MoE 路径 `-ncmoe` | `isMoE` 且超显存 | MoE 放得下 → `-ncmoe 0` |
| → MoE 专家缓存 `-cmoe` | `isMoE` 且 `--help` 同时支持 `--moe-cache-mib` 与 `--load-mode none` | 缺任一 → 只走 `-ncmoe` 路径 |
| → dense 路径 `-ncffn` | 非 MoE 且（权重超显存 **或** KV 量化后仍溢出） | dense 放得下且 KV 不溢 → `-ngl 99`，**不加** `-ncffn` |
| **KV 量化** | KV/token × 目标上下文 > 显存余量的显著比例 | 占比低 → 默认 `q8_0`，不扫 |
| **上下文极限** | 用户实际需要 > 32K | 只用短上下文 → 固定 32K |
| **reasoning-budget** | 有思考模式 | 无思考 → 跳过 |
| **线程 `-t`/`-tb`** | 有权重或专家被卸载到 CPU | 全 GPU → 跳过 |
| **投机解码** | GPU 有空闲（util 未饱和）且 `--help` 支持 | GPU 饱和或无支持 → 跳过 |
| `--parallel` / `--cont-batching` | — | 永远跳过（单实例流程） |

## 2.1 卸载的本质与统一判据

**本质：把一部分计算踢到 CPU，腾出显存给 KV，避免 KV 溢出到 shared。**

判据（三件同时满足才算好档）：

1. **空闲 `shared` ≈ 基线**（硬信号，唯一可靠的溢出判据）
2. 深填充（≥ 20k tokens）的 prefill 速度不崩
3. 长生成（≥ 1500 tokens）的 decode t/s 可接受

> 单看任何一项都会选错档；只有 `shared` 是确定性物理信号。

配套脚本：`scripts/scan_offload.ps1`（`-ncmoe` / `-ncffn` / `-ngl` 同构，参数化 `-OffloadMode`）。

---

## 2.1a MoE 路径：`-ncmoe N`

含义：前 N 层的**专家权重**留在 CPU，attention 仍在 GPU。

**方向**：从大往小减（卸载越来越少）找断崖。步进按"每 N 层专家权重"的量级决定（用 `perLayerMB` 估）。

**断崖形态**：N 小于阈值 → 权重 + KV 超显存 → KV 落 shared → 速度断崖；N 越大腾越多显存，同填充速度略降。

### ★★ `-ncmoe` 是双面旋钮，不是单一"最优值"

| 方向 | 效果 | 代价 |
|---|---|---|
| N ↑ | 腾更多显存给 KV → **能撑更长上下文** | decode 变慢 |
| N ↓ | decode 变快 | 长上下文装不下 |

### ★★ 两阶段取值法（必守）

1. **第一阶段（短/基线上下文扫描）得到的"断崖档"只是快速参考值**。
   它回答的是"在基线上下文下最快是多少"，**不是长上下文的答案**。
2. **第二阶段：长上下文要从参考值之上一点点往上摸**（参考值 → +1 → +2 …），
   每档用「`shared` 回落到基线 + 分段 prefill 不崩」确认，够用即停。
3. **★方向是往上加，不是往下减。** 往上加是"用一点 decode 换上下文"，往下减是"用上下文的可用性换 decode"——后者经常直接把长上下文变成不可用。
4. **换算**：每多卸载 1 层 ≈ 省下"每层权重大小" ≈ 换来「每层权重大小 ÷ 每层 KV 的 ctx 边际成本」的上下文长度。
   两个量都从 `00-probe.md` 算出，不要写死。

### ★ 判据必须用长生成或深填充

**短生成会选错档**：一个轻微溢出的档在短生成下可能反而最快，深填充却会崩。

- L1（`llama-bench`）短测同样会骗人：**严重**溢出看得出（速度断崖），**轻微**溢出看不出。
- 最终判定必须回 L2 看 `shared`（`08-measurement.md`）。

---

## 2.1a′ MoE 专家缓存路径：`-cmoe` + `--moe-cache-mib`（实测验证的高效推理路径）

**语义（`--help` 取证，非推测）**：

| 参数 | 语义 |
|---|---|
| `-cmoe, --cpu-moe` | 将**所有** MoE 专家权重留在 CPU（对照：`-ncmoe N` 只留前 N 层） |
| `--moe-cache-mib N` | GPU 上为 CPU 侧 MoE 专家分配的**缓存**大小（MiB），**一次性预分配、非按需增长**；多卡按 `--tensor-split` 风格分配 |
| `--load-mode none` | `read()` 拷入进程私有匿名内存 → `cudaHostRegister` pin → 真 DMA 上传；`mmap` 的文件页无法 pin，驱动退化为 staging bounce buffer（多一次完整拷贝且更难异步） |

缓存语义为「上传到 GPU 再计算」：CPU **不**并行计算未命中专家。上游还有 `--moe-cache-hybrid / --moe-cache-profile / --moe-cache-audit` 等扩展参数，是否并入当前构建以 `--help` 为准。

**与 `-ncmoe` 的本质区别**：`-ncmoe` 是**静态分层切分**（前 N 层专家永远在 CPU，decode 瓶颈在 CPU 权重带宽）；`-cmoe` + cache 是**动态热点缓存**（全部专家在 CPU，GPU 用固定 MiB 预算缓存热点专家，decode 转 GPU/传输瓶颈）。实测（等显存 A/B 同会话对照）decode 在短/中/长上下文全档领先且 CPU 大幅释放；代价是 prefill 略慢（缓存搬运开销）、GPU 占用升高。完整实测样例见 [`../../measurements/08-occamy-cmoe.md`](../../measurements/08-occamy-cmoe.md)。

### ★ 部署硬约束

1. **B 臂必须带 `--load-mode none`**：mmap 文件页无法 pin，缓存上传只能走 bounce buffer。这是参数语义决定的约束，不是可调项。
2. **缓存上限随上下文下调**：KV 占用随 ctx 线性增长，缓存必须按同额度让位；超过等显存上限即溢出 → `shared` 跳升、decode 跌回 CPU 水平。上限由逐点探测得出（见下表第 3 步），不靠公式外推（可用「底座 + KV(ctx) + cache ≤ 信封」的账目做核对）。
3. **宿主内存参数必须显式设置**：`--cache-ram` 默认值在小型宿主内存机器上可能是 OOM 坑；**对照实验显式写 `--cache-ram 0`**（该缓存只吃宿主内存、不影响 t/s 与显存，设 0 去掉一个内存压力变量），并按需压低 `--ctx-checkpoints`。

### ★★ 实验设计：等显存 A/B 同会话对照（ABAB）

以 `-ncmoe` 最优档为 A 臂（基线），`-cmoe` + cache 为 B 臂，复用 `start_server.ps1` 与四件套 harness：

| 步骤 | 内容 | 判据 |
|---|---|---|
| 1. 探查 | `--help` 确认 `--moe-cache-mib` 与 `--load-mode none` 存在 | 缺任一 → 只走 `-ncmoe` |
| 2. 定 A 臂 | 按 2.1a 两阶段法选出 A 臂 `-ncmoe N` | `shared` 回基线 + 深填充不崩 + 长生成可接受 |
| 3. 找 B 臂上限 | **只加载不推理**逐点逼近（~25 s/点）：cache 由小到大试到溢出，回退一档 | `shared` 基线跳升或 dedicated 反降 = 溢出 |
| 4. 等显存校核 | B 臂 idle dedicated ≈ A 臂 idle dedicated（差在测量噪声内） | 等显存对比成立，否则调 cache 重校 |
| 5. ABAB 对照 | 同一份 prompt、同会话内 A/B 前后相邻交替，每臂 ≥3 次（如 1500-token 生成） | **同时记录 decode t/s 与 prefill pps**（B 用 prefill 换 decode，只看 decode 会误判） |
| 6. 资源画像 | 四件套记 gpu% / cpu% 快照 | B 转 GPU/传输密集、CPU 释放属预期，写入权衡 |
| 7. 逐档重复 | 每个目标上下文档位重复 3–5 步（缓存上限随 ctx 重算） | 无翻转点 → B 全档推荐；出现翻转 → 写明分界档位 |

**结论判据**：B 臂 decode 领先幅度须远超状态噪声（±2%）且方向在所有重复中一致；prefill 差距与 CPU/GPU 占用变化记入权衡。**回退 `-ncmoe` 的唯一理由**：需要比 `-cmoe` 方案等显存上限更长的上下文弹性——`-ncmoe` 靠继续加大 N 换上下文，`-cmoe` 的缓存被显存卡死后没有这个弹性。

---

## 2.1b dense 路径：`-ncffn N`

含义：`--n-cpu-ffn N` 把**前 N 层的 dense FFN 权重**留在 CPU，attention / norm 仍按 `-ngl 99` 在 GPU。
它是 `-ncmoe` 的 dense 对应物。

### ★ 不要走"减少 `-ngl`"这条路

减少 `-ngl` 会把 **attention 一起踢下 GPU**（attention 每步必读，代价远大于只卸 FFN），
而 `-ncffn` 只牺牲 decode 期的 FFN 权重带宽。

### ★ `-ncffn` 不是提速参数

在短上下文下它是**纯负收益**（多了一层 CPU↔GPU 的权重读取开销）。

**唯一价值 = 大上下文的"溢出救援"**：

| 情况 | 观察 | 动作 |
|---|---|---|
| 目标 ctx 下 `shared` 未跳升 | 没有溢出 | **不需要** `-ncffn` |
| 目标 ctx 下 `shared` 明显跳升且 t/s 崩塌 | 溢出 | 加 `-ncffn`，从小到大试 |

- **机制**：CPU 瓶颈**只在 decode**（矩阵×向量、权重带宽 bound）；
  **prefill 是矩阵×矩阵，权重读取被 batch 摊薄，几乎不掉速** → 所以救援点在"能装下"与"能用"上可以同时成立。
- **取样规则**：N 不必整除，按"溢出多少补多少"选**最小可用 N**（从小到大试，够用即停）。
- **与投机解码不叠加**：投机解码的 draft 缓冲会额外占显存，可能把 `-ncffn` 刚腾出的余量吃回去、`shared` 重新跳升 → 救援目标被破坏。
  **救援场景选纯 `-ncffn`**（`07-speculative.md` 同理：两者在显存紧张时只能选一个）。
- **顺序**：**先试 KV 量化省显存**，KV 仍溢出才动 `-ncffn`。

---

## 2.1c 通用操作顺序

```
1. 算账（04-context.md 的预算公式）：权重 + KV(ctx) + compute(ctx) 是否超显存？
     不超 → 不扫卸载，-ngl 99 直接用
     超   → 继续
2. 先省 KV：q8_0 / q4_0（03-kv-quant.md）
3. 仍超 → 走对应卸载路径：
     MoE   → -ncmoe 粗扫找断崖 → 长上下文从断崖档往上摸
             （--help 支持 --moe-cache-mib 时加测 `-cmoe` 对照臂，等显存 ABAB 定夺，见 2.1a′）
     dense → -ncffn 救援（溢出多少补多少）
4. 每档判定：shared 回落基线 + 深填充不崩 + 长生成 t/s 可接受
```

配套脚本：

```
pwsh scripts/scan_offload.ps1 -ModelPath <gguf> -Alias m -LlamaDir <dir> -OffloadMode ncmoe -Start 16 -End 26 -Step 2
pwsh scripts/scan_offload.ps1 -ModelPath <gguf> -Alias m -LlamaDir <dir> -OffloadMode ncffn -Start 8  -End 24 -Step 4
```
