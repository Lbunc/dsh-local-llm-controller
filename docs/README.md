# `dsh-local-llm-controller` 文档索引

## 目录结构

| 目录 | 内容 |
|---|---|
| [`llm-experiment-design/`](llm-experiment-design/) | 本地大模型性能实验设计的**方法论**（六段流程：探查→环境→卸载→KV量化→采样→思考→能力分流→评测→归档）。以 GGUF 元数据与运行时探查驱动，不预设模型规模 |
| [`measurements/`](measurements/) | 历次调优的**实测存档**：跨模型共同经验 + 35B / 9B / 27B / Occamy 每模型一份报告（编号 00-08），入口为 [`measurements/README.md`](measurements/README.md)（结论速览 + 分模型报告表 + 测量基线 + 横向对比 + 留存说明）。属于具体实验记录，随版本冻结 |
| [`llama-帮助文档/`](llama-帮助文档/) | llama.cpp 全套中文帮助手册（索引 + 6 套分册），入口为 [`llama-帮助文档/llama-工具手册索引.md`](llama-帮助文档/llama-工具手册索引.md)：[`llama-server`](llama-帮助文档/llama-server-帮助文档-中文.md)（22 章全量逐参数，插件启动参数的**权威参考**）/ [`llama-bench`](llama-帮助文档/llama-bench-帮助文档-中文.md)（多值扫描语法、显存适配、与 server 参数对应表）/ [`CLI 系列`](llama-帮助文档/llama-CLI系列-帮助文档-中文.md)（`llama.exe` / `llama-cli.exe` / `llama-completion.exe`）/ [`评测系列`](llama-帮助文档/llama-评测系列-帮助文档-中文.md)（`llama-batched-bench.exe` / `llama-perplexity.exe` / `llama-fit-params.exe` / `llama-results.exe`）/ [`模型处理`](llama-帮助文档/llama-模型处理-帮助文档-中文.md)（`llama-quantize.exe` / `llama-imatrix.exe` / `llama-gguf-split.exe` / `llama-tokenize.exe`）/ [`多模态与杂项`](llama-帮助文档/llama-多模态与杂项-帮助文档-中文.md)（`llama-mtmd-cli.exe` / `llama-mtmd-debug.exe` / `llama-tts.exe` / 废弃视觉包装器 / `ggml-rpc-server.exe`） |

## 快速定位

- **配置启动参数** → 见 [`llama-帮助文档/llama-server-帮助文档-中文.md`](llama-帮助文档/llama-server-帮助文档-中文.md)（插件自动管理的参数：`-m`、`-a`、`--port`、`--host`、`--api-key`、`--mmproj` 无需填写）
- **调优吞吐基准** → 见 [`llama-帮助文档/llama-bench-帮助文档-中文.md`](llama-帮助文档/llama-bench-帮助文档-中文.md)（多值扫描语法、`-ncmoe` 注意事项）
- **模型量化/切分/token 核对** → 见 [`llama-帮助文档/llama-模型处理-帮助文档-中文.md`](llama-帮助文档/llama-模型处理-帮助文档-中文.md)
- **设计一次新模型调优** → 见 `llm-experiment-design/SKILL.md`（方法与可复跑脚本都在这里）
- **看某个模型的实测结论** → 见 [`measurements/README.md`](measurements/README.md) 分模型报告索引（跨模型共同经验 + 35B 三个变体 / 9B / 27B 两个量化 / Occamy 两份）
