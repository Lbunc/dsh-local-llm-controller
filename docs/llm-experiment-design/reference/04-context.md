# 04 · 上下文三问：装得下 / 能用 / 好用（第 2.3 步）

> **报上下文必须给三元组**：`(KV 类型, ctx, 可用深度)` + 该深度的 prefill pps 与 decode t/s。
> 只报"最大 ctx"是错的口径——标称 ctx 只是显存上限，"能撑多深"才是可用指标。
> 三个问题缺一不可，且**必须与卸载档一起报**（同一 ctx 干净还是溢出取决于卸载档）。

## ① 装得下（先算账，再验证）

```
可用显存 ≈ GPU 总量 − 系统/桌面保留 − CUDA context
总占用   = model + KV(ctx) + compute(ctx)
```

- `KV/token = kvLayers × head_count_kv × (key_length + value_length) × 量化字节`
  （`kvLayers` 由 `full_attention_interval` 折算，见 `00-probe.md`）
- ★ **compute buffer 也随 ctx 增长**，不能忽略：
  → **上下文边际成本 ≈ KV/token + compute 增量**，**不是 KV 单项**。
  两个量都从本机实测得到（分别量两个 ctx 点即可解出增量），不要照抄其他机器的值。
- 先算账：`llama-fit-params -fitp on` 会打印 `model / context / compute` 三段估算。
  → **预测上限 → 只验证边界 2–3 个点**，不要盲扫 5–6 点。

> ★ `llama-fit-params` 是**预算计算器，不是求解器**：
> 不传卸载参数时它假设权重全进显存，**不会替你挑卸载档**。卸载档必须显式扫（`02-offload.md`）。

**判定（物理信号）**：读 GPU 的 `Dedicated` / `Shared` 显存计数（多卡按目标卡过滤）。

- `shared` 从基线跳升 = 开始溢出（KV / 图缓冲落到系统内存）
- ded 饱和后，增量会转移到 shared
- t/s 只作辅助佐证

**硬断崖**：某点 `shared` 暴涨（量级远超基线）+ t/s 崩塌 = 死区；断崖在上一可看点与崩溃点之间。

配套脚本：

```
pwsh scripts/scan_maxctx.ps1 -ModelPath <gguf> -Alias m -NcmoeList 20,22 -CtxList 65536,98304,131072
```

## ② 能用（分段 prefill 降级剖析 —— 标配方法）

**问题**：全量深填充是 all-or-nothing——只得到"超时"，**得不到拐点**，而且每次都要重跑一遍长填充。

**方法**：按固定档（十几 K tokens 为一档）**逐步加深对话**（前缀复用），每档记录：

- 该档增量 `prompt_n` / `prompt_per_second` / `prompt_ms`
- 该档墙钟
- 该档 `shared`

**判据**：

1. 先取一个**健康档参照**（同模型、短 ctx 下的首档 prefill pps）。
2. 当某档 pps 相对参照**明显掉档**（用 `-PpsFloor` 之类的阈值参数化），即判"不可用"并停止。

**产出 = 崩溃深度**（从多深开始不可用）。这是"能用"的唯一量化答案。

配套脚本：

```
pwsh scripts/prefill_profile.ps1 -ModelPath <gguf> -Alias m -Ncmoe 20 -Ctx 131072 -StageTokens 16000
```

## ③ 好用（该深度的 decode + 整轮墙钟）

- 每档同时记 eval t/s：**即便不崩，decode 也会随深度缓降**。
- **一次真实请求总墙钟 = prompt_ms + predicted_ms**。
- ★ **"能填满" ≠ "能用"**：一个能把上下文填到接近上限的配置，若单次请求墙钟达到分钟级、生成速度低到不可接受，就是**实际不可用**。

**结论口径**：

> **最大可用上下文** = 生成速度可接受 **且** prefill / 填充时间可接受。
> "KV 能装下"只决定**显存上限**，不决定**可用上限**。

## ④ 长上下文题必须先量真实 token 数

跑长上下文相关测试（尤其是能力题库里的长文档题）之前，**必须用 `/tokenize` 量出 prompt 的真实 token 数**，再决定 `max_tokens`。

- 不要用"字符数 ÷ 常数"估算：不同语种 / 不同内容（代码、公式、表格）差异很大。
- 预算约束：`prompt_tokens + max_tokens ≤ n_ctx`。

配套脚本：

```
pwsh scripts/verify_bank_budget.ps1 -LlamaDir <dir> -Specs @('m|<gguf>|ncmoe:20') -Ctx 65536
```

该脚本做两件事：① 逐题量真实 prompt token 数并校验预算；② 用最长的那道题做一次真实深填充，读 `shared` 确认深填充下不溢出。

## 2.3e 本步完成判据

- [ ] 预算已算账，只验证了边界 2–3 点
- [ ] 每个点都记了 `shared`（硬信号），并注明了对应卸载档
- [ ] 分段 prefill 已做，**崩溃深度**已给出
- [ ] 该深度下的 decode t/s 与整轮墙钟已给出
- [ ] 结论写成三元组 `(KV 类型, ctx, 可用深度)`，未只报"最大 ctx"
- [ ] 长上下文相关测试的 prompt token 数已用 `/tokenize` 实测
