# 本地模型调优实测存档（分模型索引）

> 各表数值受跨会话负载影响（±10-15%），跨表对比以同会话内部对比为准。跨模型通用的测量教训与方法论统一收录在 [00-测试项目共同经验.md](00-测试项目共同经验.md)。

***

## 0. 最终结论速览

| 模型 | 架构 | 量级 | 推荐配置 | 速度（干净环境） | 最长安全上下文 | 报告 |
| --- | --- | --- | --- | --- | --- | --- |
| **35B**（Uncensored-IQ4_NL） | qwen35moe MoE | 18.42 GB | `-ncmoe 20` + KV q8_0 + **32K** + rb 2048 | ~70-74 t/s | ~53-65K（119K≈54） | [01](01-35B-Uncensored.md) |
| **35B UD MTP**（IQ4_NL） | qwen35moe MoE | 17.26 GB | `-ncmoe 20` + MTP n=2 @32K | ~40（无 MTP）→ **51-53**（MTP +30-40%） | 48K（MTP 模式）+700MB 显存 | [02](02-35B-UD-MTP.md) |
| **9B**（Q6_K） | dense | 7.16 GB | `-ngl 99` + **MTP n=3** @32K | 56（无 MTP）→ **~88-107**（+60%） | ~98K 无掉速 | [03](03-9B-Q6K.md) |
| **27B**（IQ3_XXS） | qwen35 dense | 10.18 GB | b10883 复核：**64K** `-ngl 99` + q4_0 无损；80K → `-ncffn 16`，96-128K → `-ncffn 24` | ~33（≤64K）；-ncffn 平台 14-18 | **64K**（断崖 64↔80K，勘误见 [04 §5.2](04-27B-IQ3XXS.md)）；`-ncffn 24` 撑 96K~128K | [04](04-27B-IQ3XXS.md) |
| **27B XL**（Q2_K_XL） | qwen35 dense | 9.15 GB | `-ngl 99` + KV q4_0 + **MTP n=2** + rb 2048 | ~37（无 MTP）→ **51-57**（MTP +32-42%） | 无 MTP = 96K；**MTP n=2 = 64K** | [05](05-27B-XL-Q2K.md) |
| **35B UD**（IQ4_NL） | qwen35moe MoE | 16.80 GB | `-ncmoe 18` + KV q4_0 + **32K**；长上下文 `-ncmoe 20 -c 131072` | 62-66 t/s | 32K（速度）~ 160K（q4_0） | [06](06-35B-UD.md) |
| **Occamy-1.0**（IQ4_NL） | qwen35moe MoE | 18.42 GB | `-ncmoe 20` + KV q8_0 + **32K** + **`-t 14`**；长上下文 `-ncmoe 22 -c 131072` | **73 t/s**（长生成）/ 78（短生成）；`-t 14` 比默认 20 快 +18.8% | q8_0 = 131072（128K）@ `-ncmoe 22`；q8_0 = 80K @ `-ncmoe 20` | [07](07-occamy-ncmoe.md) |
| **Occamy `-cmoe`**（专家缓存） | 同上 | 同上 | `-cmoe --moe-cache-mib N --load-mode none`（N 按等显存上限取值，见 [08 §4/§5](08-occamy-cmoe.md)） | 同显存三档全部领先 `-ncmoe` 方案：32K +25.4% / 128K +13.2% / 256K +8.3%（6 样本方向一致） | 与 `-ncmoe` 方案同量级（b11702 复核） | [08](08-occamy-cmoe.md) |

> **Occamy-1.0** 是对 Qwen3.6-35B-A3B **后训练检查点继续做 co-work 智能体训练**得到的模型
> （论文 [arXiv:2609.11977](https://arxiv.org/abs/2609.11977)），与 UD-IQ4_NL **架构完全相同**
> （qwen35moe / 40 层 / 256 专家 / 10 KV 层 / ctx 262144 / 无 MTP）。
> `-ncmoe` 与 `-cmoe` 两套方案的完整对照见 [08-occamy-cmoe.md](08-occamy-cmoe.md)。

**选型结论**：

- **长上下文场景** → 首选 MoE 35B（MoE 稀疏激活，上下文几乎不掉速；dense 在 32K 就断崖）。
- **短上下文/省显存/省事** → 27B（更小更快配置简单）或 9B（有 MTP 大提速）。
- **能力上**：同档案的 dense（27B）与 MoE（35B）在难题上**同档**，单靠几道题分不出高低；要稳定区分需完整题库统计。

***

## 分模型报告

| 文档 | 模型 / 主题 |
| --- | --- |
| [00-测试项目共同经验.md](00-测试项目共同经验.md) | 跨模型通用测量教训：采样窗口污染、脚本与编码缺陷、测量方法论、MoE 卸载断崖、本机硬件特性、视觉预设部署经验 |
| [01-35B-Uncensored.md](01-35B-Uncensored.md) | Qwen3.6-35B-A3B-Uncensored-IQ4_NL（18.42 GB，用户日常配置） |
| [02-35B-UD-MTP.md](02-35B-UD-MTP.md) | Qwen3.6-35B-A3B-UD-TPM-IQ4_NL（带 MTP，17.26 GB） |
| [03-9B-Q6K.md](03-9B-Q6K.md) | Qwen3.5-9B-Q6_K（dense，带 MTP，7.16 GB） |
| [04-27B-IQ3XXS.md](04-27B-IQ3XXS.md) | Qwen3.8-27B IQ3_XXS（10.18 GB，含 `-ncffn` 实测） |
| [05-27B-XL-Q2K.md](05-27B-XL-Q2K.md) | Qwen3.8-27B-UD-Q2_K_XL（9.15 GB，dense） |
| [06-35B-UD.md](06-35B-UD.md) | Qwen3.6-35B-A3B-UD-IQ4_NL（16.80 GB，无 TPM） |
| [07-occamy-ncmoe.md](07-occamy-ncmoe.md) | Occamy-1.0 IQ4_NL 调优与部署存档（`-ncmoe` 方案，含视觉预设实测） |
| [08-occamy-cmoe.md](08-occamy-cmoe.md) | Occamy-1.0 `-cmoe` 缓存方案（三档部署配置，×16 链路复核） |

每份模型报告统一采用四段结构：§0 简介 → §1 索引 → §2 最佳推荐参数 → §3~§7 有效测试记录。

***

## 测量基线与通用约束

| 项目 | 内容 |
| --- | --- |
| GPU | RTX 4070 SUPER 12GB（12282 MiB） |
| CPU | i5-13600KF（6P+8E，20 线程 / 14 物理核） |
| llama.cpp | b10488 / b10883（00~07 号文档）；b11702（08 号文档） |
| 端口 / 鉴权 | 55555 / apiKey 留空（header `Bearer dsh-local-llm`） |

**固定参数**（所有测试一致）：`-ngl 99 -fa on -t 20 -tb 20 -np 1 --temp 0.6 --top-k 20 --top-p 0.95 --min-p 0.0 --repeat-penalty 1 --presence-penalty 0 --slots --metrics`，纯文本（不加载 mmproj），`--reasoning-budget 2048`。

> **口径注意**：08 号文档测于 b11702 且经 PCIe ×16 链路修复复核，与 00~07 号文档（b10488/b10883）的数值不可直接跨版本对比。完整测量方法（四件套 / 深填充 / 可靠性规则）见 [../llm-experiment-design/SKILL.md](../llm-experiment-design/SKILL.md)，本目录只保留实测记录。

***

## 横向能力对比（跨模型）

- **9B(Q6) vs 27B(Q3) vs 35B(IQ4_NL,-ncmoe20)**：基础题 9B 92% / 27B 96% / 35B 96%（无区分度）；GAIA 类复杂题 9B 88% / 27B 100% / 35B 100%（拉开 9B）。
- **27B vs 35B**：计算/编程/LeetCode 上均同档（多次复测无法稳定区分）。
- 结论：**9B 在复杂多跳/反事实核查上明显弱**；**27B ≈ 35B 能力同档**，27B 更小更快更省显存（短上下文）+ 配置简单，35B 长上下文优势显著。
- **MoE vs dense 差异**：MoE 长上下文不掉速（≤53k ≈70-74 → 119k≈54）；dense 在 32K 断崖。长上下文首选 MoE。
- **速度修正**：35B 早前误测 22 t/s（环境污染），干净环境 ~70 t/s；27B IQ3_XXS ~33 t/s，**27B Q2_K_XL ~37 t/s（更小更快）**。
- **公平性**：同构同参、同题同 prompt、objective 判定（reference 程序生成标准答案，勿手算）；任何非预期差距重复 ≥3 次。
