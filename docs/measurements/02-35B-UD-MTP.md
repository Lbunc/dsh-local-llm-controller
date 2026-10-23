# 02 — Qwen3.6-35B-A3B-UD-TPM-IQ4_NL（17.26GB，带 MTP）

> **环境**：RTX 4070 SUPER 12GB（12282 MiB）· i5-13600KF（6P+8E，20 逻辑核 / 14 物理核）· llama.cpp b10488 · 32 GB RAM

---

## §0 简介

### 0.1 模型概览

| 项 | 值 |
|---|---|
| 全称 | `Qwen3.6-35B-A3B-UD-TPM-IQ4_NL.gguf` |
| 文件大小 | 17.26 GB（17,260 MB） |
| 架构 | qwen35moe（MoE）· 40 层 / 256 专家 / top-8 / 10 KV 层 / full_attention_interval 4 |
| KV 派生 | head_count_kv 2 · key=value=256 · f16 20480 B/token（q8_0=10240、q4_0=5120） |
| 上下文长度 | 262144（256K） |
| 量化 | IQ4_NL（3.9 bit/param，比 Uncensored 的 4.25 bit 更激进） |
| MTP / nextn 张量 | 有（`blk.40.nextn.*` → draft-mtp 投机可用，n=2） |
| chat_template | 7764 字符，含 `enable_thinking` + tool_call |
| 后训练定位 | Qwen3.6-35B-A3B 基线检查点经 co-work 智能体专项后训练的 UD（Uncensored-DPO）变体，带 MTP 投机头 |

### 0.2 架构要点

| 键 | 值 |
|---|---|
| architecture | qwen35moe（MoE） |
| block_count / expert_count | 40 / 256 |
| top-k / KV 层 | top-8 / 10 |
| full_attention_interval | 4 |
| head_count_kv / key=value | 2 / 256 |
| context_length | 262144（256K） |
| KV/token（f16） | 20480 B（q8_0=10240、q4_0=5120） |
| tensor_count | 733 + MTP 头张量 |
| MTP / nextn 张量 | 有（`blk.40.nextn.*` → draft-mtp 投机可用，n=2） |
| chat_template | 7764 字符，含 `enable_thinking` + tool_call |
| 量化 | IQ4_NL（3.9 bit/param） |
| 后训练定位 | Qwen3.6-35B-A3B 基线检查点经 co-work 智能体专项后训练的 UD 变体，带 MTP 投机头 |

### 0.3 模型画像

| 维度 | 35B-UD-MTP 实测表现 |
|---|---|
| 稳态 decode（32K / q8_0 / -ncmoe 20 + MTP n=2） | **~51 t/s**（long，MTP+30-40%） |
| prefill（32K / q8_0） | **~72-74 t/s**（short 稳态值域，见 §3.2） |
| 有效上下文（q8_0 / -ncmoe 20 + MTP n=2） | **约 48K**（MTP draft 缓冲 +700MB 挤占 KV 余量） |
| 极限上下文（无 MTP / -ncmoe 22 @96K） | **96K 可用**（MTP n=2 恰好补偿显存开销） |
| decode 期瓶颈 | CPU-bound：GPU 48-55%（MTP 后饱和），CPU 高负载（20 线程） |
| 能力评测 | 精确计算/多跳排雷/反事实核查/条件调度均 96–100%（单模型专项测评） |
| 后训练定位 | Qwen3.6-35B-A3B 基线检查点经 co-work 智能体专项后训练的 UD 变体，带 MTP 投机头 |

---

## §1 索引

| 章节 | 内容 |
|---|---|
| §2 | 最佳推荐参数（含文本/视觉分档命令与部署经验） |
| §3 | ncmoe × MTP × 上下文最优配置扫描 |
| §4 | 上下文极限与 MTP 显存开销（idle shared 物理信号） |
| §5 | 掉速曲线分析（MoE + MTP 双重约束） |
| §7 | 视觉预设（mmproj 部署结论） |

---

## §2 最佳推荐参数（35B-UD-MTP 单模型推荐配置）

> 以下参数为 Qwen3.6-35B-A3B-UD-TPM-IQ4_NL 在本机（RTX 4070 SUPER 12GB · i5-13600KF）实测得出的最优配置，按使用场景分档推荐。

### 2.1 推荐参数总览

| 场景 | 上下文 | KV 量化 | `-ncmoe` | MTP | `-t` | `-tb` | `-ngl` | `-fa` | `-rb` | 推荐度 |
|---|---|---|---|---|---|---|---|---|---|---|
| **日常使用（推荐默认）** | 32768 (32K) | q8_0 | 20 | n=2 | 14 | 14 | 99 | on | 2048 | ✅ 首选 |
| **长上下文（无 MTP）** | 98304 (96K) | q8_0 | 22 | 关 | 14 | 14 | 99 | on | 65536 | ⚠️ 边界 |
| **仅文本（高速，无 MTP）** | 32768 (32K) | q8_0 | 20 | 关 | 14 | 14 | 99 | on | — | ✅ 快速响应 |

### 2.2 推荐启动命令

**① 日常使用（推荐默认，32K / q8_0 / -ncmoe 20 + MTP n=2）：**
```
llama-server.exe -m .\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-UD-TPM-IQ4_NL.gguf -a ud35b-mtp
  --port 55555 --host 127.0.0.1
  -ngl 99 -c 32768 -fa on --cache-type-k q8_0 --cache-type-v q8_0
  -ncmoe 20 --spec-type draft-mtp --spec-draft-n-max 2
  -t 14 -tb 14 -np 1 --reasoning-budget 2048
  --temp 0.6 --top-k 20 --top-p 0.95 --min-p 0.0
  --repeat-penalty 1 --presence-penalty 0 --metrics --slots
```

**② 长上下文（96K / q8_0 / -ncmoe 22，关闭 MTP）：**
```
llama-server.exe -m .\qwen3.6-35B-A3B\Qwen3.6-35B-A3B-UD-TPM-IQ4_NL.gguf -a ud35b-mtp
  --port 55555 --host 127.0.0.1
  -ngl 99 -c 98304 -fa on --cache-type-k q8_0 --cache-type-v q8_0
  -ncmoe 22
  -t 14 -tb 14 -np 1 --reasoning-budget 65536
  --temp 0.6 --top-k 20 --top-p 0.95 --min-p 0.0
  --repeat-penalty 1 --presence-penalty 0 --metrics --slots
```

### 2.3 部署经验与约束

- **MTP 模式额外 +~700MB 显存**（draft 缓冲）→ N20+MTP 上下文极限降到 ~48K（无 MTP 时 96K）。
- **N22+MTP 恰好补偿 → 96K 可用**：MTP n=2 后 long ~41-45、deep 88k ~38、无溢出（3× 上下文）。
- **`-ncmoe` 选择**：最优值为 20（配合 MTP @32K）或 22（配合无 MTP @96K）。N<20 时断崖式下跌。
- **MTP 接受率**：n=2 时 70.5%（健康），批量有效分摊 GPU 工作（无 MTP util 58-61% → MTP 后 48-55%，验证批量有效分摊 GPU 工作）。
- **`-t/-tb` 线程**：默认 `n_threads = 物理核数 14`（见 `00-测试项目共同经验.md §5`）。

---

## §3 ncmoe × MTP × 上下文最优配置扫描

> 判定门：17.26 GB 权重 + MTP draft 缓冲 ~700MB + 32K KV 远超 12 GB → MoE 专家卸载 + MTP 双重约束。
> 唯一变量组合 = `-ncmoe` × `MTP n` × `上下文 C`。

### 3.1 MTP × ncmoe × 上下文最优（2026-08 最终）

| 推荐档位 | 参数 | 表现 | 适用场景 |
|---|---|---|---|
| **① 文本速度最快** | `-ncmoe 20 --spec-type draft-mtp --spec-draft-n-max 2` @32K | long ~51、deep ~53 t/s、接受率 70.5% | 短上下文高速响应 |
| **② 文本综合上下文** | `-ncmoe 22` + MTP n=2 @98304 | long ~41-45、deep 88k ~38、无溢出（3× 上下文） | 中长上下文综合场景 |

### 3.2 核心发现

- **无 MTP 同配置 ~40 t/s**（激进低比特解量化开销大，3.9 bit/param）→ MTP 为必选加速方案。
- **MTP 带来 +30-40%**：无 MTP util 58-61%（未饱和），MTP 后 48-55%，验证批量有效分摊 GPU 工作。首轮"MTP 无收益"是会话负载误判。
- **MTP n=2 后 long ~51、deep 22k ~53、接受率 70.5%**（健康范围 >65%）。

---

## §4 上下文极限与 MTP 显存开销（idle shared 物理信号）

> `idle shared` 从 32K 基线跳升 = KV 溢出的物理信号。以下为 35B-UD-MTP 单模型在各配置下的实测值。

### 4.1 MTP 模式上下文扫描（-ncmoe 20 / q8_0 / MTP n=2）

| ctx | idle ded (MiB) | idle shared (MiB) | short t/s | deep t/s | 判定 |
|---|---|---|---|---|---|
| 32768 | ~10585 | ~142 | 51.0-53.0 | — | ✅ 可容纳（MTP +700MB 缓冲） |
| 49152 | ~11200 | ~311 | 45.0-48.0 | — | ⚠️ 临界 |
| 65536 | ~11800 | **439** | 41.0-44.0 | — | ⚠️ 短测信号（冷启动分配） |
| 81920 | ~12100 | **786** | 35.0-38.0 | — | ⚠️ 起始溢出 |

**结论**：MTP n=2 + -ncmoe 20 @32K 为推荐默认（idle shared ~142 MB，零溢出）。短测 64K shared 显示 439 MB 为冷启动分配信号，深填充运行时 shared 仅 310 MB，不影响真实可用性。

### 4.2 无 MTP 模式上下文扫描（-ncmoe 22 / q8_0）

| ctx | idle ded (MiB) | idle shared (MiB) | short t/s | deep t/s | 判定 |
|---|---|---|---|---|---|
| 32768 | ~10585 | ~142 | 71.8 | — | ✅ 可容纳（基线） |
| 65536 | ~11637 | ~249 | 65.8 | — | ✅ 可容纳 |
| 98304 | ~11354 | **233** | 62.6 | 62.6 | ✅ 可容纳（上限） |
| 114688 | ~11573 | **249** | 65.8 | — | ⚠️ 边界 |

**结论**：无 MTP -ncmoe 22 @98304 为长上下文可用上限（idle shared 233 MB，零溢出）。深填充可容纳 98304 tokens。分段 prefill 验证方法（~17.6K tokens/档，前缀复用）见 [07-occamy-ncmoe.md §7.4.1](07-occamy-ncmoe.md)。

---

## §5 掉速曲线分析（MoE + MTP 双重约束）

### 5.1 掉速机制

35B-UD-MTP 为 MoE 架构 + MTP 投机解码，其掉速受三重因素制约：

| 制约因素 | 作用区间 | 表现 |
|---|---|---|
| **注意力成本** | ≤40K | 随 ctx 线性增长，decode t/s 缓慢下降（51→45） |
| **CPU 专家瓶颈** | >53K | 未完全卸载的 MoE 专家权重在 GPU/CPU 间回退，GPU util 90%+ + CPU 饱和 |
| **MTP draft 缓冲开销** | 全区间 | MTP n=2 额外 +896MB 显存挤占 KV 余量，将上下文上限从无 MTP 的 96K 压到 48K（短测信号）/ 64K（深填充可用） |

### 5.2 有 MTP vs 无 MTP 掉速对比

| 上下文 | -ncmoe 20 + MTP n=2 (q8_0) | -ncmoe 22 无 MTP (q8_0) |
|---|---|---|
| 32K | ~51 t/s（MTP+30-40%） | ~71.8 t/s |
| 64K | ~41-44 t/s（冷启动 shared 439 MB ⚠️） | ~65.8 t/s（shared 249 MB ✅） |
| 96K | ❌ 超时/深填充跑不完 | ~38-41 t/s（deep 88k，无溢出 ✅） |

**结论**：MTP 在 32K 提供 +30-40% 速度增益（51 vs 36.5-40），但额外显存开销将上下文上限从 96K 降到 ~48-64K。**不能同时要"最快"和"最高上下文"**。

---



---

## §7 视觉预设（mmproj 置于 CPU）

### 7.1 投影器位置：显存成本对照

| 用例 | 投影器 | 专用显存 (MiB) | Δ vs 基线 | idle shared | short ×3 均值 |
|---|---|---|---|---|---|
| A 纯文本（不加载） | — | 10585 | +10037 | 142 | 64.5 t/s |
| B 投影器置于 CPU | `-mmdev none` | 10585 | **+10037（= 0 额外）** | 142 | 65.2 t/s |
| C 投影器置于 GPU | `--mmproj-offload` | 11695 | +11147 (**+1110**) | 142 | 65.2 t/s |

**结论**：`-mmdev none`（或 `--no-mmproj-offload`）使投影器权重以 compute buffer 形式分配在 CPU，显存占用 ≈ 0 MiB。置于 GPU 的代价 ≈ 1110 MiB（含运行时开销），远大于文件本身。

### 7.2 视觉预设部署经验

> **⚠️ 已修正（2026-10）**：旧版"必须 N=24"的前提是将投影器置于 GPU（多花 1110 MiB）。后续在 Occamy-1.0 上实测出更省的方案：**投影器置于 CPU（`-mmdev none`）显存成本为 0**，无需为此退到 N=24（`-ncmoe 22` + 128K 仍零溢出）。该 CPU 方案尚未在 35B-Uncensored 上复测；N=24 数据本身有效，仅"必须"二字已不成立。

**通用部署经验（详见 `00-测试项目共同经验.md §7`）**：

视觉预设的通用部署经验已统一记录于 `00-测试项目共同经验.md §7`。


