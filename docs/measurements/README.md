# 本地模型调优全历程终版存档（分模型索引）

> 本文为最终定稿（2026-08 复核）。数据均已复核，被推翻/污染的章节已删除或压缩为一条修正说明。**注意：各表数值受跨会话负载影响（±10-15%），跨表对比以同会话内部对比为准。**

***

## 0. 最终结论速览

| 模型                          | 架构            | 量级       | 推荐配置                                                        | 速度（干净环境）                           | 最长安全上下文               | 能力    |
| --------------------------- | ------------- | -------- | ----------------------------------------------------------- | ---------------------------------- | --------------------- | ----- |
| **35B**（Uncensored-IQ4\_NL） | qwen35moe MoE | 18.42 GB | `-ncmoe 20` + KV q8\_0 + **32K** + rb 2048                  | \~70-74 t/s                        | \~53-65K（119K≈54）     | 同档    |
| **35B UD MTP**（IQ4\_NL ）    | qwen35moe MoE | 17.26 GB | `-ncmoe 20` + MTP n=2 @32K                                  | \~40（无 MTP）→ **51-53**（MTP+30-40%） | 48K（MTP 模式）+700MB 显存  | 同档    |
| **9B**（Q6\_K）               | dense         | 7.16 GB  | `-ngl 99` + **MTP n=3** @32K                                | 56（无 MTP）→ **\~88-107**（+60%）      | \~98K 无掉速             | 复杂题略弱 |
| **27B**（IQ3\_XXS）           | qwen35 dense  | 10.18 GB | b10883 复核：**64K** `-ngl 99`+q4\_0 无损；80K→`-ncffn 16`，96-128K→`-ncffn 24` | \~33（≤64K）；-ncffn 平台 14-18 | ~~32K~~ **64K**（断崖 64↔80K，勘误见 [27b-iq3xxs.md §9.2](27b-iq3xxs.md)）；`-ncffn 24` 撑 96K\~128K | 同档    |
| **27B XL**（Q2\_K\_XL）       | qwen35 dense  | 9.15 GB  | `-ngl 99` + KV q4\_0 + **MTP n=2** + rb 2048 | \~37（无 MTP）→ **51-57**（MTP+32-42%） | 无 MTP=96K；**MTP n=2=64K** | 同档    |
|  **35B UD**（IQ4\_NL）        | qwen35moe MoE | 16.80 GB | `-ncmoe 18` + KV q4\_0 + **32K**；长上下文 `-ncmoe 20 -c 131072` | 62-66 t/s                          | 32K（速度）\~ 160K（q4\_0） | 同档    |
| **Occamy-1.0**（IQ4\_NL）    | qwen35moe MoE | 18.42 GB | `-ncmoe 20` + KV q8\_0 + **32K** + **`-t 14`**；长上下文 `-ncmoe 22 -c 131072` | **73 t/s**（长生成）/ 78（短生成）；`-t 14` 比默认 20 快 +18.8% | **q8\_0 = 131072（128K）@ `-ncmoe 22`**；q8\_0=80K @ `-ncmoe 20` | 同档    |

> **Occamy-1.0** 是对 Qwen3.6-35B-A3B **后训练检查点继续做 co-work 智能体训练**得到的模型
> （论文 [arXiv:2609.11977](https://arxiv.org/abs/2609.11977)），与 UD-IQ4\_NL **架构完全相同**
> （qwen35moe / 40 层 / 256 专家 / 10 KV 层 / ctx 262144 / 无 MTP）。完整对比见
> [`occamy_vs_ud_report.md`](occamy_vs_ud_report.md)。

**选型结论**：

- **长上下文场景** → 首选 MoE 35B（MoE 稀疏激活，上下文几乎不掉速；dense 在 32K 就断崖）。
- **短上下文/省显存/省事** → 27B（更小更快配置简单）或 9B（有 MTP 大提速）。
- **能力上**：同档案的 dense（27B）与 MoE（35B）在难题上**同档**，单靠几道题分不出高低；要稳定区分需完整题库统计。

***

## 分模型报告

| 模型 | 报告 | 原章节 |
|---|---|---|
| Qwen3.6-35B-A3B-Uncensored-IQ4\_NL（18.42GB，用户日常配置） | [35b-uncensored-iq4nl.md](35b-uncensored-iq4nl.md) | §2 |
| Qwen3.6-35B-A3B-UD-TPM-IQ4\_NL（带 MTP，17.26GB） | [35b-ud-tpm-iq4nl.md](35b-ud-tpm-iq4nl.md) | §3 |
| Qwen3.5-9B-Q6\_K（dense，带 MTP，7.16GB） | [9b-q6k.md](9b-q6k.md) | §4 |
| Qwen3.8-27B IQ3\_XXS（10.18GB，含 `-ncffn` 实测） | [27b-iq3xxs.md](27b-iq3xxs.md) | §5 + §9 |
| Qwen3.8-27B-UD-Q2\_K\_XL（9.15GB，dense） | [27b-ud-q2kxl.md](27b-ud-q2kxl.md) | §6.8 |
| Qwen3.6-35B-A3B-UD-IQ4\_NL（16.80GB，无 TPM） | [35b-ud-iq4nl.md](35b-ud-iq4nl.md) | §6 |
| Occamy-1.0 vs UD-35B 完整对比 | [occamy_vs_ud_report.md](occamy_vs_ud_report.md) ＋ 测量明细 [occamy_measurements.md](occamy_measurements.md) | 原 §10 |

***

## 测量基线与通用约束

**环境**：RTX 4070 SUPER 12GB（12282 MiB）、i5-13600KF（6P+8E，20 线程）、llama.cpp b10488（`qwen35moe` 架构，混合 MoE+SSM，40 层仅 10 层有 KV：full\_attention\_interval=4，2 KV heads × 256 维）。

**固定参数**（所有测试一致）：`-ngl 99 -fa on -t 20 -tb 20 -np 1 --temp 0.6 --top-k 20 --top-p 0.95 --min-p 0.0 --repeat-penalty 1 --presence-penalty 0 --slots --metrics`，纯文本（不加载 mmproj），`--reasoning-budget 2048`。端口 55555 / apiKey 留空（header `Bearer dsh-local-llm`）。

> 完整测量方法（四件套 / 深填充 / 可靠性规则）见 [../llm-experiment-design/SKILL.md](../llm-experiment-design/SKILL.md)，本目录只保留实测记录。

***

## 7. 横向能力对比（跨模型）

- **9B(Q6) vs 27B(Q3) vs 35B(IQ4\_NL,-ncmoe20)**：基础题 9B 92%/27B 96%/35B 96%（无区分度）；GAIA 类复杂题 9B 88%/27B 100%/35B 100%（拉开 9B）。
- **27B vs 35B**：计算/编程/LeetCode 上均同档（多次复测无法稳定区分）。
- 结论：**9B 在复杂多跳/反事实核查上明显弱**；**27B ≈ 35B 能力同档**，27B 更小更快更省显存（短上下文）+ 配置简单，35B 长上下文优势显著。
- **MoE vs dense 差异**：MoE 长上下文不掉速（≤53k ≈70-74→119k≈54）；dense 在 32K 断崖。长上下文首选 MoE。
- **速度修正**：35B 早前误测 22 t/s（环境污染），干净环境 \~70 t/s；27B IQ3\_XXS \~33 t/s，**27B Q2\_K\_XL \~37 t/s（更小更快）**。
- **公平性**：同构同参、同题同 prompt、objective 判定（reference 程序生成标准答案，勿手算）；任何非预期差距重复 ≥3 次。

***

***

## 8. 脚本与留档文件（D:\DSH\WORK1\llama.cpp）

**通用（模型/版本无关）**：`start_server.ps1`（启动器）、`scan_offload.ps1`（dense -ngl / MoE -ncmoe 同构）、`bench_capability.ps1`（能力验证 runner）、`gguf_keys_ctx.ps1`（元数据提取）、`write_bat_gbk.ps1`（UTF-8→GBK+CRLF）。
**多模型横向对比**：`agent_hard_3model.ps1`、`agent_27b_vs_35b_leetcode.ps1`、`lc_harness.py`、`agent_27b_vs_35b_hard.ps1`、`agent_compare_9b_27b.ps1`、`repeat_27b_l3.ps1`/`repro_27b_l3.ps1`/`repro_27b_l1.ps1`（单题复现）。
**本次 UD-35B**：`scan_ud_ncmoe_down.ps1`（ncmoe 扫描）、`scan_ud35b_ctx.ps1`（上下文扫描）、`agent_ud_vs_uncensored.ps1`（模型能力对比）、`kv_q8_q4_ability.ps1`（KV 能力对照）、`deep192k_ncmoe.ps1`（192K 深填充对照）。
**本次 27B Q2\_K\_XL**：`scan_27b_xl_ctx.ps1`（q8\_0/q4\_0 上下文断崖扫描）、`deep_27b_xl.ps1`（chat 多轮深填充）、`deep_ctx_xl.ps1`（/completion 定深填充，prefill/墙钟可用性）、`agent_27b_q2_vs_q3.ps1`（2-bit vs 3-bit 能力对比）、`bench_27b_xl_mtp.ps1`（MTP 开关+ n-max + 接受率 + GPU util + 显存增量）、`scan_27b_xl_mtp_ctx.ps1`（MTP n=2 上下文断崖扫描）、`deep_27b_xl_mtp.ps1`（MTP n=2 深填充/墙钟可用性）、`gguf_mtp.ps1`（MTP 头张量检测）。
**历史/专用（参考用）**：`bench_35b_*`/`bench_9b_*`/`vision_*`/`bench_ngram*` 等各模型一次性基准。
**本次 -ncffn 新参数（b10883）**：`gguf_ffn_probe.ps1`（GGUF 张量名 vs -ncffn regex 命中验证）、`scan_27b_ncffn.ps1`（32K N 网格吞吐+四件套）、`bench_27b_ncffn_rescue.ps1`（大上下文 N=0 vs N 救援对照）、`bench_27b_ncffn_mtp.ps1`（MTP×ncffn+接受率）、`deep_27b_ncffn.ps1`（定深填充 prefill/墙钟可用性）、`bench_27b_ncffn_capability.ps1`（temp=0 贪心跨后端一致性）、`bench_27b_ncffn_quality.ps1`（temp 0.6 客观判分）。`start_server.ps1` 已升级支持 `-NcpuFfn`/`-LogPath`。原始数据：`docs\raw\ncffn_scan_raw_log.txt`。

\*\*docs\**：本索引与各分模型报告、`ctx_scan_raw_log.txt`（原始输出，本目录）；其余原始日志留存于工作区 `D:\DSH\WORK1\llama.cpp\docs\raw\`。
\*\*data\**：测试材料与基准结果；\*\*picture\*\*：视觉测试图。

***
