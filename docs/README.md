# `dsh-local-llm-controller` 文档索引

## 目录结构

| 目录 | 内容 |
|---|---|
| [`llm-experiment-design/`](llm-experiment-design/) | 本地大模型性能实验设计的**方法论**（六段流程：探查→环境→卸载→KV量化→采样→思考→能力分流→评测→归档）。以 GGUF 元数据与运行时探查驱动，不预设模型规模 |
| [`measurements/`](measurements/) | 历次调优的**实测存档**：35B / 9B / 27B / Occamy 每模型一份报告，入口为 [`measurements/README.md`](measurements/README.md)（结论速览 + 目录 + 横向对比 + 复现脚本与原始日志说明）。属于具体实验记录，随版本冻结 |
| `llama-server-帮助文档-中文.md` | `llama-server.exe -h` 全量逐参数中文手册（22 章）——插件启动参数的**权威参考** |
| `llama-bench-帮助文档-中文.md` | `llama-bench.exe -h` 中文手册（多值扫描语法、显存适配、与 server 参数对应表） |
| `llama-工具手册索引.md` | llama.cpp 全部 6 套中文手册的索引与阅读方法 |
| `llama-CLI系列-帮助文档-中文.md` | `llama.exe` / `llama-cli.exe` / `llama-completion.exe` 中文手册 |
| `llama-评测系列-帮助文档-中文.md` | `llama-batched-bench.exe` / `llama-perplexity.exe` / `llama-fit-params.exe` / `llama-results.exe` 中文手册 |
| `llama-模型处理-帮助文档-中文.md` | `llama-quantize.exe` / `llama-imatrix.exe` / `llama-gguf-split.exe` / `llama-tokenize.exe` 中文手册 |
| `llama-多模态与杂项-帮助文档-中文.md` | `llama-mtmd-cli.exe` / `llama-mtmd-debug.exe` / `llama-tts.exe` / 废弃视觉包装器 / `ggml-rpc-server.exe` 中文手册 |

## 快速定位

- **配置启动参数** → 见 `llama-server-帮助文档-中文.md`（插件自动管理的参数：`-m`、`-a`、`--port`、`--host`、`--api-key`、`--mmproj` 无需填写）
- **调优吞吐基准** → 见 `llama-bench-帮助文档-中文.md`（多值扫描语法、`-ncmoe` 注意事项）
- **模型量化/切分/token 核对** → 见 `llama-模型处理-帮助文档-中文.md`
- **设计一次新模型调优** → 见 `llm-experiment-design/SKILL.md`（方法与可复跑脚本都在这里）
- **看某个模型的实测结论** → 见 [`measurements/README.md`](measurements/README.md) 分模型报告索引（35B 三个变体 / 9B / 27B 两个量化 / Occamy vs UD 对比）
