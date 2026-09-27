# llama.cpp 工具手册中文索引

> 来源：`F:\llama-b10883-bin-win-cuda-13.3-x64\`，共 22 个 exe，全部 `-h` 输出已翻译归档。
> 原始英文帮助全文存档：[`docs/help-raw/`](help-raw/)（每个 exe 一个 `.txt`），另有逐参数比对报告 [`_diff_report.txt`](help-raw/_diff_report.txt) 与工具专属段落汇总 [`_example_specific_all.txt`](help-raw/_example_specific_all.txt)。

本索引作为插件 `docs/` 下 llama-server 手册的**补充参考**，列出全部 llama.cpp 工具的中文手册覆盖范围。插件主要使用 `llama-server`，其余工具（`llama-bench`、`llama-perplexity` 等）在深度调优时参考本章。

## 手册清单

| 手册 | 覆盖的程序 |
|---|---|
| [llama-server 帮助文档（中文）](./llama-server-帮助文档-中文.md) | `llama-server.exe`（22 章，全量逐参数翻译） |
| [llama-bench 帮助文档（中文）](./llama-bench-帮助文档-中文.md) | `llama-bench.exe` |
| [llama CLI 系列 帮助文档（中文）](./llama-CLI系列-帮助文档-中文.md) | `llama.exe`（统一入口，含 `download` 子命令）、`llama-cli.exe`、`llama-completion.exe` |
| [llama 评测系列 帮助文档（中文）](./llama-评测系列-帮助文档-中文.md) | `llama-batched-bench.exe`、`llama-perplexity.exe`、`llama-fit-params.exe`、`llama-results.exe` |
| [llama 模型处理工具 帮助文档（中文）](./llama-模型处理-帮助文档-中文.md) | `llama-quantize.exe`、`llama-imatrix.exe`、`llama-gguf-split.exe`、`llama-tokenize.exe` |
| [llama 多模态与杂项 帮助文档（中文）](./llama-多模态与杂项-帮助文档-中文.md) | `llama-mtmd-cli.exe`、`llama-mtmd-debug.exe`、`llama-tts.exe`、4 个已废弃视觉包装器、`ggml-rpc-server.exe` |

## 结构与阅读方法

- **llama-server 手册是"母本"**：它逐字翻译了完整的 `common params`（第 1–9 章）、`sampling params`（第 10 章）、`speculative params`（第 11 章）及服务器专属段（第 12–22 章）。
- 其余大多数工具的 `-h` 由**相同的公共段 + 工具专属段**组成。经逐参数哈希/文本比对：
  - 公共段内容与 server 手册**逐字一致**，各工具仅统一多出 4 项：`-p/--prompt`、`-f/--file`、`-bf/--binary-file`、`-np/--parallel`（注意：此 `-np` 是"并行解码序列数，默认 1"，与 server 的"服务器槽位数"同名不同义）。
  - 个别工具的个别**默认值**不同（如 imatrix/perplexity 的 `-c` 默认 512、mtmd 系列 `--temp` 默认 0.20、tts 的重复惩罚默认等），已在各手册"差异项"小节完整列出并翻译。
  - `llama-quantize`、`llama-gguf-split`、`ggml-rpc-server`、`llama-bench` 使用独立帮助格式，已全部逐条翻译。
- 4 个旧视觉包装器（gemma3/llava/minicpmv/qwen2vl-cli）仅输出废弃警告，指向 `llama-mtmd-cli`。

## 与插件的关联

| 工具 | 在插件中的用途 |
|---|---|
| `llama-server` | **核心**：插件启动的进程，提供 OpenAI 兼容 API |
| `llama-bench` | 深度调优时做吞吐量基准测试（`docs/llm-experiment-design/` 中有使用脚本） |
| `llama-perplexity` | 评估量化/KV 类型对模型质量的影响 |
| `llama-fit-params` | 估算 model/KV/compute 三段显存占用 |
| `llama-cli` | 快速验证聊天模板与采样参数 |
| `llama-gguf-split` | 模型切分/合并 |
| `llama-quantize` | 量化模型 |
| `llama-imatrix` | 重要性矩阵（用于 IQ 量化） |
| `llama-tokenize` | token 数量核对 |

> 注：`docs/help-raw/` 目录下的原始输出文件（`.txt`、`.out`、`.err`）为英文原文存档，供需要对照英文原文时查阅。
