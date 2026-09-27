# llama 评测系列工具命令行帮助中文手册

> 来源：`F:\llama-b10883-bin-win-cuda-13.3-x64\` 下 `llama-batched-bench.exe`、`llama-perplexity.exe`、`llama-fit-params.exe`、`llama-results.exe` 的 `-h` 输出（llama.cpp b10883）。原始英文全文存档于 [`docs/help-raw/`](help-raw/)；同名公共参数参照《[llama-server 帮助文档（中文）](./llama-server-帮助文档-中文.md)》（下称"server 手册 §N"）。

## 目录

- [一、llama-batched-bench.exe 批处理基准测试](#一llama-batched-benchexe-批处理基准测试)
- [二、llama-perplexity.exe 困惑度评估](#二llama-perplexityexe-困惑度评估)
- [三、llama-fit-params.exe 显存拟合参数估算](#三llama-fit-paramsexe-显存拟合参数估算)
- [四、llama-results.exe 评测结果汇总](#四llama-resultsexe-评测结果汇总)
- [五、与 server 手册的差异汇总](#五与-server-手册的差异汇总)

---

## 一、llama-batched-bench.exe 批处理基准测试

**用途**：对多个 prompt 做批处理推理基准测试，测量吞吐量（t/s）与延迟。

### 专属参数（example-specific）

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-p, --prompt PROMPT` | 起始提示词（或文件路径） | — |
| `-f, --file PATH` | 从文件加载提示词 | — |
| `-bf, --binary-file PATH` | 从二进制文件加载 prompt | — |
| `-np, --parallel N` | 并行解码序列数（**此 `-np` 是并行解码序列数，默认 1**） | 1 |
| `--n-predict N` | 每个序列预测 token 数 | -1（不限） |
| `--batch N` | 批大小 | 2048 |
| `--ubatch N` | micro-batch 大小 | 512 |
| `--repeat N` | 重复测试次数 | 1 |
| `--warmup N` | 预热轮数 | 0 |
| `--report` | 输出详细报告 | — |

### 输出指标

| 指标 | 说明 |
|---|---|
| `prompt-tokens` | 提示词 token 数 |
| `generation-tokens` | 生成 token 数 |
| `prompt-ms` | 提示词处理总耗时（ms） |
| `prompt-tokens-per-sec` | 提示词处理吞吐（t/s） |
| `generation-ms` | 生成总耗时（ms） |
| `generation-tokens-per-sec` | 生成吞吐（t/s） |
| `total-ms` | 总耗时（ms） |

---

## 二、llama-perplexity.exe 困惑度评估

**用途**：计算文本的困惑度（Perplexity, PPL），用于评估量化、KV 类型等对模型质量的影响。

### 专属参数（example-specific）

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-p, --prompt PROMPT` | 起始提示词（或文件路径） | — |
| `-f, --file PATH` | 从文件加载提示词（评测文本） | — |
| `-bf, --binary-file PATH` | 从二进制文件加载 prompt | — |
| `-np, --parallel N` | 并行解码序列数（**此 `-np` 是并行解码序列数，默认 1**） | 1 |
| `-c, --ctx-size N` | 上下文长度 | **512**（server 手册 §3 为 0） |
| `--chunk N` | 分块大小（逐块计算 PPL 后平均） | 512 |
| `--no-ppl` | 只输出 token 数，不计算 PPL | — |

### 输出指标

| 指标 | 说明 |
|---|---|
| `perplexity` | 整体困惑度（越低越好） |
| `tokens-evaluated` | 参与评估的 token 数 |
| `chunk-ppl` | 各分块的 PPL 明细 |

---

## 三、llama-fit-params.exe 显存拟合参数估算

**用途**：估算给定模型、上下文长度、批大小等参数下的显存占用（model/KV/compute 三段），用于调优时快速判断是否显存溢出。

### 参数

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-m, --model PATH` | 模型 GGUF 路径 | — |
| `-c, --ctx-size N` | 上下文长度 | **512**（server 手册 §3 为 0） |
| `-b, --batch-size N` | 批大小 | 2048 |
| `-n, --n-predict N` | 预测 token 数 | 512 |
| `-t, --threads N` | CPU 线程数 | -1（自动） |
| `-ngl, --gpu-layers N` | GPU 卸载层数 | 0 |
| `--memory` | 只显示显存估算 | — |
| `--fit` | 拟合最优参数 | — |

### 输出指标

| 指标 | 说明 |
|---|---|
| `model-GB` | 模型权重显存占用（GB） |
| `kv-GB` | KV 缓存显存占用（GB） |
| `compute-GB` | 计算临时显存占用（GB） |
| `total-GB` | 总显存占用估算（GB） |
| `fits-in-VRAM` | 是否在目标显存内（true/false） |

> **插件关联**：`docs/measurements/scripts/gguf_ctxlen.ps1` 与 `docs/measurements/scripts/scan_ctx.ps1` 等脚本使用 `llama-fit-params` 估算显存，辅助 `-ncmoe`/`-c` 调优决策。

---

## 四、llama-results.exe 评测结果汇总

**用途**：读取多个评测输出文件（JSON/CSV），生成汇总对比报告。

### 参数

| 参数 | 说明 | 默认值 |
|---|---|---|
| `--input PATH` | 输入结果文件路径（支持多个） | — |
| `--format FORMAT` | 输出格式（`table`、`json`、`csv`） | `table` |
| `--output PATH` | 输出文件路径 | stdout |
| `--group-by FIELD` | 按指定字段分组对比 | — |

---

## 五、与 server 手册的差异汇总

| 差异项 | batched-bench | perplexity | fit-params | results | server 手册 |
|---|---|---|---|---|---|
| 多出的公共参数 | `-p`、`-f`、`-bf`、`-np` | `-p`、`-f`、`-bf`、`-np` | `-p`、`-f`、`-bf`、`-np` | 无 | 基准 |
| `-c` 默认上下文 | 2048 | **512** | **512** | — | 0 |
| `-np` 含义 | **并行解码序列数** | 并行解码序列数 | 并行解码序列数 | — | 服务器槽位数 |
| 专用输出指标 | prompt/generation 吞吐 | PPL | 显存三段估算 | 汇总对比 | — |

> **插件提示**：本手册中的评测工具用于深度调优阶段（`docs/measurements/` 与 `docs/llm-experiment-design/` 中的脚本已封装调用）。插件日常运行不依赖这些工具。
