# DSH 本地模型「上下文用了 1/3 就自动压缩」根因报告

| | |
|---|---|
| 现象发生时间 | 2026-09-27 19:36–19:38 (+08:00) |
| 样本会话 | `session-62d164b8-2c56-4f8f-b91d-6ece94884b44`（cwd `D:\DSH\plug`） |
| Agent 预设 | `local-agent`（本地工作模式，`agent-preset/selected` @ seq 4，19:11:58） |
| 路由模型 | `dsh-local / occamy-1.0-IQ4_NL`，`reasoningEffort: high`，请求 `maxTokens=16384` |
| 声明窗口 | `contextWindow: 131072` |
| 软件版本 | DSH `0.1.7-rc.2` / `dsh-compaction-basic` `0.1.7-rc.2` / `dsh-local-llm-controller` `2.1.0` |
| 严重度 | 中（可用性）；同配置的 32768 档为 **高**（自动压缩完全停用） |
| 覆盖范围 | 自动压缩阈值（§1-§5）、摘要调用输出上限（§4.1）、**手动 `/compact`（§7）** |

---

## 1. 结论

自动压缩的阈值不是由 `thresholdRatio`（0.8）决定的，而是被另一条约束压到了 **49152 token = 窗口的 37.5%**：

```
threshold = min( contextWindow × thresholdRatio ,  contextWindow − 请求maxTokens − headroomTokens )
          = min( 131072 × 0.8 = 104857       ,  131072 − 16384 − 65536 = 49152 )
          = 49152                                                        ↑ 生效项
```

`min()` 右侧的 `headroomTokens` 是一个**不随模型窗口缩放的插件级常量 65536**（为百万级窗口的云端模型标定）。在 131072 的窗口上它独占 50%，导致 `thresholdRatio` 完全失效。

代码位置：`@deepseek-ai/dsh-compaction-basic/lib/index.js`
- L63 `const headroomTokens = config.headroomTokens ?? 65536;`
- L128-133 `messageBudget / pressureBudget / thresholdTokens`
- L757-759 `reservedCompletionTokens()` = 请求 `config.maxTokens ?? info.defaultMaxTokens ?? 0`

---

## 2. 根因链

1. **常量而非比例。** `resolveConfig()` 在插件加载时执行一次，此刻既不持有 `ctx` 也不知道路由模型；`headroomTokens` 只能取裸常量 65536。模型信息只在 `resolveCompactSpec()` 里作为 `min()` 的**另一个操作数**出现，从不反馈进 headroom。
2. **唯一的按模型通道未被使用。** `resolveTargetPolicy()` L103 只从 `modelPolicies`（按 `provider/model` 精确匹配）取值。「本地工作模式」预设的 `compaction-basic` **没有任何 config**，`modelPolicies` 为空数组 → 所有路由共享 65536。
3. **headroom 的真实语义 = 摘要请求的输出预算。** L64 `maxTokens = config.maxTokens ?? headroomTokens`，而 L318/L335 把这个值作为 `maxTokens` 发给摘要调用；该调用（L305-323）**原样重放整段对话前缀**（system + tools + 保留消息 + 压缩指令）到**同一个模型、同一个窗口**。因此阈值必须为「一次完整请求的输出」留空——设计正确，但它随「待压缩历史长度」增长，被写成了固定常数。
4. **窗口尺寸踩中结构死区。** 要让 `0.8` 重新获胜需 `headroom ≤ 0.2W − reserved`。131072 档为 `≤ 9830`，32768 档为 `≤ −39322`（无解）。即：**W ≤ 2×headroom 的模型，无论怎么调都无法用掉窗口的 50% 以上。**

---

## 3. 实测证据（session 日志逐条对齐）

| seq | 事件 | 数据 | 对应阈值 49152 |
|---|---|---|---|
| 15 / 20 | `assistant/message` usage | inputTokens 3076 → 10717 | system + tools 固定开销 ≈ **10.7k**（阈值内含） |
| 157 | usage totalTokens **52682** | 越线 | 触发压缩前评估 |
| 163–171 | `compaction/prune` ×5 | 剪去 6599/1641/1324/1484/1105 = 12153 | 剪枝后回到线下 → **不发** `compaction/start`（L942-946 正常分支） |
| 194 | usage totalTokens **52249** | 越线 | 再次评估 |
| 198 | `compaction/prune` | −1135 | 仍 ≥49152 |
| 200→201 | `compaction/start` → `compaction/end` | **error: "summarization produced no text summary content"**（3 秒返回，19:36:18→19:36:21） | 摘要失败，见 §4.1 |
| 204 | usage totalTokens **51159** | 仍越线 | |
| 208 | `compaction/prune` | −1456 | 仍 ≥49152 |
| 210→211→213 | start → **summary** → end | 摘要落地 19:38:01 | 压缩成功 |
| 216 | usage `inputTokens 38490 / cacheReadTokens 2560` | 51k → 41.5k | **全量 re-prefill**，见 §4.3 |

52249 与 51159 均紧贴 49152 上沿，公式与观测一致，无第三种解释需要排除。

---

## 4. 连带缺陷

### 4.1 摘要请求的 65536 会**越过**模型自己的 16384

`dsh-llm/lib/index.js` L2170 只在 `config.maxTokens === void 0` 时用 `info.defaultMaxTokens` 填充，注释 L2154 明写 **"no clamping or aliasing is performed"**。于是同一模型两类请求不对称：

| | 请求 maxTokens | 命中路径 | 实发值 |
|---|---|---|---|
| 普通对话轮 | 省略（日志 `adapterDefaults.maxTokens: true`） | 填模型条目 | **16384** |
| 压缩摘要轮 | 显式 65536 | 跳过填充 | **65536** |

结果：occamy 一生中要求输出最多的一次，正是那次——prompt 已 ~49k、`reasoning_effort=high`、带 40+ 工具 schema。llama.cpp 不报错，只把 `n_predict` 静夹到 `n_ctx − n_len`；模型只吐 reasoning 不吐正文 → §3 的空摘要。另一条会话 `session-b8c0765d` 的 `"summarization truncated at the token cap (incomplete checkpoint)"` 同源。

### 4.2 32768 档（Qwen3.6-35B-A3B）自动压缩**完全停用**

`32768 − 16384 − 65536 < 0` → `resolveCompactSpec` L130-131 抛 `TargetPressureConfigError` → L844-849 只 `ctx.logger.warn("step compaction failed: …; continuing the turn")` 后放行。表现为**静默不压缩**，一路涨到 llama-server 报窗口超限。降级程度取决于是否配了 `-c 131072` 的 long 预设。

### 4.3 提前触发放大了本地专属成本

`-np 1` 单 slot + 前缀 KV cache 下，任何历史重写都是全量 re-prefill（seq216 实测 38490 token / cacheRead 仅 2560）。触发点从 80% 提前到 37.5%，等于把这种大 prefill 的频率放大约 2 倍。云端此成本由厂商承担，故此缺陷在云端不可见。

### 4.4 配置来源的耦合风险（附带发现）

`contextWindow` 由插件从 `-c` 反写：`addProviders` 固定读 **`text:fast`** 的 `-c`（`lib/index.js:394`），`syncProviderConfig` 读**当前激活参数组**的 `-c`（`:685`）。同一模型 id 服务 fast(32768)/long(131072) 两组，若用 fast 组启动 occamy，DSH 仍会按上次同步的 131072 估算 → 直接溢出。

---

## 5. 影响面（用户现有全部路由）

断点公式：`thresholdRatio` 获胜 ⟺ `W ≥ 5 × (reserved + 65536)`

| 路由 | W | reserved | headroom 项 | 0.8W | 生效阈值 | 占窗口 | 判定 |
|---|---|---|---|---|---|---|---|
| zai `glm-5.3` | 1,000,000 | 131,072 | 803,392 | 800,000 | 800,000 | **80.0%** | ✅ 正常 |
| `deepseek-official` | 1,000,000 | 256,000 | 678,464 | 800,000 | 678,464 | 67.9% | ⚠️ 被压 |
| modelscope（默认 262144/32768） | 262,144 | 32,768 | 163,840 | 209,715 | 163,840 | 62.5% | ⚠️ 被压 |
| **`dsh-local / occamy-1.0-IQ4_NL`** | 131,072 | 16,384 | **49,152** | 104,857 | 49,152 | **37.5%** | ❌ 本缺陷 |
| **`dsh-local / Qwen3.6-35B-A3B`** | 32,768 | 16,384 | **−49,152** | 26,214 | — | **抛错** | ❌❌ 压缩停用 |

> 云端「正常」的本质是**分母效应 + 出厂配置恰好越过断点**：`glm-5.3` 的 1M/128k 正是常量 65536 唯一不 binding 的形状；65536 在 1M 里占 6.6%、131k 里占 50%、32.7k 里占 200%。云端即使被压到 62~68% 也只被感知为「上下文还很宽裕」，故该默认值从未被反证。

---

## 6. 修复

### 6.1 用户侧（唯一有效旋钮 = `headroomTokens`）

文件：`C:\Users\98160\.dsh\local-bundles\user-agent-presets\cordis.patch.yml` L154-155
（`profiles/web/node_modules/@local/dsh-user-agent-presets` 是指向它的 junction）；改后**重启 DSH**。

```yaml
- id: compaction-basic
  name: '@deepseek-ai/dsh-compaction-basic'
  config:
    headroomTokens: 8192     # ← 关键；同时把摘要上限带到 8192
    maxTokens: 8192          # ← 摘要输出上限，显式写死，勿依赖 L64 继承
    thresholdRatio: 0.8
    retainRatio: 0.16
    modelPolicies:
      - provider: dsh-local
        model: occamy-1.0-IQ4_NL          # → min(104857, 106496) = 80% ✅
        headroomTokens: 8192
        maxTokens: 8192
      - provider: dsh-local
        model: Qwen3.6-35B-A3B-UD-IQ4_NL  # → 32768−6144−2048 = 24576 = 75% ✅
        headroomTokens: 2048
        maxTokens: 4096
```

配套：把 `profiles/web/cordis.patch.yml` L145-157 中 Qwen3.6 条目的 `maxTokens: 16384` 手改为 `6144`（`syncProviderConfig` 只回写 `contextWindow`，不覆盖该字段；但**不要再按卡上「添加到模型列表」**——`addProviders` 会把 16384 写回）。

`headroomTokens` 与 `maxTokens` 的键继承有三处分叉（L64 顶层、L71 policy、L107 合并），**两个键都显式写**是唯一无歧义的配法——`maxTokens` 一项还额外决定手动压缩能否用，见 §7.4。

### 6.2 已排除的替代方案

| 方案 | 结论 |
|---|---|
| 只降模型 `maxTokens` | ❌ 131k 档天花板 = `1 − 65536/W` = **50%**；reserved 取 0 也只能到 50%。且它是**每轮对话**的输出上限，在 `reasoning: high` 下压到 4096 会截断正常回答（插件 L395-398 正是为此硬编码 16384）；对摘要那次的 65536 完全无效。32768 档无论取多少都必抛错。 |
| 提高 `-c` / `contextWindow` | ⚠️ 可行但不划算：跑到 70% 需 `W ≥ 273k`，让 0.8 获胜需 `W ≥ 409.6k`，q8_0 KV 显存代价远高于改一个数字。 |
| `retainRatio` / `retainTokens` | 只影响压缩后保留的原文尾巴，不影响触发时机。 |
| 路由摘要到云端（`summarizationProvider: modelscope` + `summarizationModel`） | ✅ 可选叠加项：彻底消除空摘要与本地 prefill 成本；代价是摘要调用无法复用本地 KV cache。 |

---

## 7. 手动压缩 `/compact`：不受阈值数学影响，但受同一个窗口限制且**更脆弱**

### 7.1 阈值数学完全不参与（一个反直觉的好消息）

`/compact`（[dsh-command-compact](C:/Users/98160/AppData/Roaming/npm/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-command-compact/lib/index.js) L55）→ `compactNow`（compaction-basic L985-1011）→ `selectCompactableRange(session, measure, 0)` → `compactSurfaceRegion`。**整条路径不调 `resolveCompactSpec`**，`contextWindow` / `thresholdRatio` / `headroomTokens` 一个都不参与。因此：

- §1 的「37.5% 提前触发」管不着它 —— 任何时刻按都会真压；
- §4.2 的「32768 档必抛 `TargetPressureConfigError`、自动压缩停用」也管不着它 —— **`/compact` 在 Qwen3.6-35B 上照样可用**；
- `retainTokens = 0`：只保留最后一个 surface 节点，其余全部进摘要（自动路径留 `messageBudget × 0.16` = 18350 的原文尾巴）。

### 7.2 它仍然打进同一个窗口

摘要调用是同一个 `summarizeWithLlm`：重放**除 system 头外的全部历史 + 40 多个工具 schema + 末尾压缩指令**，并带 `max_tokens = config.maxTokens`（默认 65536，见 §4.1）。安全线：

```
历史 token + 摘要 max_tokens  ≤  contextWindow
```

| 历史规模（W=131072） | 摘要请求 prompt + 65536 | 结果 |
|---|---|---|
| < 60k | < 126k | ✅ 能压 |
| **> 65k** | **> 131072** | ❌ llama.cpp 静夹 `n_predict` 或直接 400 → 只吐 reasoning 无正文 → `summarization produced no text summary content` → `/compact` 报 *"Compaction could not produce a useful summary"*（command-compact L32-35） |

也就是说：**窗口越满，`/compact` 越容易失败——恰好在最需要它的时刻。**

### 7.3 三个把它推近悬崖的放大因素

1. **`compactNow` 不 prune。** 对比 `context-overflow` 分支 L927-931、`pressure` 分支 L942-945 都会先 `prune.pruneSession` 再压；手动路径**没有这一步**。预设里 `thresholdChars: 4096` 的大工具结果原样进摘要 prompt——§3 实测一次 prune 省 12153 token（占窗口 **9.3%**）。
2. **尾巴留 0、重放却是全量**：`selectCompactableRange(…, 0)` 只决定「替换什么」，`buildSummarizationInput`（L578）仍把整段历史发给模型。
3. **前置条件**：`agent.runMaintenance` 且不得存在 open turn（L457），否则 `ManualCompactionError("busy")` → *"Compaction is unavailable because … the agent is not idle."*

### 7.4 对 §6 修复方案的约束：`maxTokens: 8192` 不是可选项

| 配法 | 自动路径 | 手动 `/compact` |
|---|---|---|
| 只改 `headroomTokens: 8192` | 阈值推到 104857，但 104k 历史 + 65536 摘要 → **必然溢出**；摘要失败不重试（§3 的 seq200→201 就是实例），下一轮从头再来 | 历史 > 65k 即失败 |
| `headroomTokens: 8192` + `maxTokens: 8192`（§6.1 采用） | 104857 = 80% 触发 ✅ | 安全线抬到 ~122k 历史 ✅ |

两条路径共用同一个 `summarize()`，溢出时都走 `summarizeCompaction` L584-594 的 `compaction/summary-error` waterfall；没有插件接管就原样抛出——**两边都没有兜底**，差别仅在于自动路径失败前已经 prune 过一轮。

### 7.5 云端为何从未暴露这条

1M 窗口 + 摘要 65536 要历史涨到 ~935k 才溢出；`session-0c304915` 里三次手动 `/compact`（`compaction/start` 带 `sourceCommandId`、`turn: null`）全部成功落地，正是这条路径在云端健康的证据。

---

## 8. 给上游的修改建议

1. `headroomTokens` 默认值改为随窗口缩放，例如 `clamp(floor(0.1 × contextWindow), 4096, 65536)`，或在 `resolveCompactSpec` 里取 `min(headroomTokens, contextWindow − reserved)` 后再算阈值。
2. `TargetPressureConfigError` 在窗口不足时不应导致**静默不压缩**（L844-849）；应降级为「按可用比例强制启用」并明确告警，否则本地小窗口用户拿不到任何保护。
3. 摘要请求的 `maxTokens` 应默认**继承被路由模型的 `defaultMaxTokens`**（而非顶层 `headroomTokens` 常量），并受 `contextWindow − prompt − reserved` 约束；`config.maxTokens` 与 `headroomTokens` 的隐式继承（L64/L71/L107）建议拆为两个必填键，消除三种分叉。
4. 摘要返回空正文时应带**自动降级重试**（缩小 `maxTokens` 或去掉 `reasoningEffort` 再试一次），当前一次失败即 `compaction/end.error` 落盘，下一轮从头再来。
5. `dsh-local-llm-controller` 侧：`addProviders` 读 `text:fast` 而 `syncProviderConfig` 读激活组，两者不一致会让 `contextWindow` 与实际 `-c` 脱钩；建议以「运行中进程的真实 `-c`」为唯一真源，并在 fast/long 使用不同 `contextWindow` 时拆成两个模型 id。
6. `compactNow` 应在 `selectCompactableRange` 之前先调 `prune.pruneSession`，与 `context-overflow` 分支（L927-931）对齐；否则手动压缩永远比自动压缩多背一截未剪枝的大工具结果。
7. 摘要请求的 `max_tokens` 应按剩余窗口推导（`min(config.maxTokens, W − prompt − reserved)`），而不是无条件发出常量；否则「上下文越满 → 越需要压缩 → 压缩请求越容易溢出」形成正反馈。
