# llama-server 命令行帮助中文手册

> 来源：`F:\llama-b10883-bin-win-cuda-13.3-x64\llama-server.exe -h` 的原始输出（llama.cpp b10883，Windows CUDA 13.3 x64 发行版）。
> 原文分为 `common params`、`sampling params`、`speculative params`、`example-specific params` 四大块；本文档按**用途重新分类**，参数名、取值、环境变量保持英文原文，说明部分为中文翻译。
> `-h` 输出中每一项末尾的 `(env: XXX)` 表示该参数也可以用同名环境变量设置。

本手册作为插件 8 组启动参数的**权威参考**。插件自动管理的参数（`-m`/`-a`/`--port`/`--host`/`--api-key`/`--mmproj`）无需在参数行中填写；下方其余参数可自由增删。

## 目录

1. [基本信息与环境](#一基本信息与环境)
2. [CPU 线程与调度](#二cpu-线程与调度)
3. [上下文与推理批处理](#三上下文与推理批处理)
4. [RoPE 与长上下文外推（YaRN）](#四rope-与长上下文外推yarn)
5. [KV 缓存类型与内存处理](#五kv-缓存类型与内存处理)
6. [设备与显存卸载](#六设备与显存卸载)
7. [模型加载方式与模型来源](#七模型加载方式与模型来源)
8. [LoRA 与控制向量](#八lora-与控制向量)
9. [日志与调试](#九日志与调试)
10. [采样参数](#十采样参数)
11. [投机解码与查找解码](#十一投机解码与查找解码)
12. [Prompt 缓存与槽位（Slots）](#十二prompt-缓存与槽位slots)
13. [并发、批处理与生成行为](#十三并发批处理与生成行为)
14. [多模态（视觉与视频）](#十四多模态视觉与视频)
15. [Embedding 与 Rerank](#十五embedding-与-rerank)
16. [HTTP 服务与网络](#十六http-服务与网络)
17. [安全认证与 CORS](#十七安全认证与-cors)
18. [Web UI 与 Agent 内置工具（实验性）](#十八web-ui-与-agent-内置工具实验性)
19. [聊天模板与推理（思考）模式](#十九聊天模板与推理思考模式)
20. [模型别名与路由服务器](#二十模型别名与路由服务器)
21. [监控与管理端点、空闲休眠](#二十一监控与管理端点空闲休眠)
22. [预设模型快捷参数](#二十二预设模型快捷参数)

---

## 一、基本信息与环境

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `-h, --help, --usage` | 打印本帮助并退出 | — | — |
| `--version` | 显示版本与构建信息 | — | — |
| `-cl, --cache-list` | 显示本地缓存中的模型列表 | — | — |
| `--completion-bash` | 打印 llama.cpp 的 bash 自动补全脚本（可 source 使用） | — | — |
| `--list-devices` | 打印可用计算设备列表并退出 | — | — |
| `--offline` | 离线模式：强制使用本地缓存，禁止一切网络访问 | 关闭 | `LLAMA_ARG_OFFLINE` |

## 二、CPU 线程与调度

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `-t, --threads N` | 生成（推理）时使用的 CPU 线程数 | -1（自动） | `LLAMA_ARG_THREADS` |
| `-tb, --threads-batch N` | 批处理与提示词处理（prompt processing）时使用的线程数 | 同 `--threads` | — |
| `-C, --cpu-mask M` | CPU 亲和性掩码：任意长度的十六进制数，与 `--cpu-range` 互补 | `""` | — |
| `-Cr, --cpu-range lo-hi` | CPU 亲和性范围（如 `0-7`），与 `--cpu-mask` 互补 | — | — |
| `--cpu-strict <0|1>` | 是否使用严格 CPU 绑定 | 0 | — |
| `--prio N` | 设置进程/线程优先级：low(-1)、normal(0)、medium(1)、high(2)、realtime(3) | 0 | — |
| `--poll <0...100>` | 等待任务时的轮询（polling）强度，0 = 不轮询 | 50 | — |
| `-Cb, --cpu-mask-batch M` | 批处理的 CPU 亲和性掩码 | 同 `--cpu-mask` | — |
| `-Crb, --cpu-range-batch lo-hi` | 批处理的 CPU 亲和性范围 | — | — |
| `--cpu-strict-batch <0|1>` | 批处理是否使用严格 CPU 绑定 | 同 `--cpu-strict` | — |
| `--prio-batch N` | 批处理进程/线程优先级：0-normal、1-medium、2-high、3-realtime | 0 | — |
| `--poll-batch <0|1>` | 批处理是否用轮询等待任务 | 同 `--poll` | — |
| `--numa TYPE` | NUMA 优化：`distribute`（均匀分布到所有节点）/ `isolate`（只在启动执行的节点上开线程）/ `numactl`（使用 numactl 提供的 CPU 映射）。若之前未用过该选项，建议先清理系统页缓存。参见 https://github.com/ggml-org/llama.cpp/issues/1437 | 不启用 | `LLAMA_ARG_NUMA` |

## 三、上下文与推理批处理

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `-c, --ctx-size N` | 提示词上下文长度（0 = 从模型元数据读取） | 0 | `LLAMA_ARG_CTX_SIZE` |
| `-n, --predict, --n-predict N` | 最多预测的 token 数（-1 = 不限） | -1 | `LLAMA_ARG_N_PREDICT` |
| `-b, --batch-size N` | 逻辑最大批大小 | 2048 | `LLAMA_ARG_BATCH` |
| `-ub, --ubatch-size N` | 物理最大批大小（micro-batch） | 512 | `LLAMA_ARG_UBATCH` |
| `--keep N` | 初始提示词中强制保留（不被淘汰）的 token 数，-1 = 全部保留 | 0 | — |
| `--swa-full` | 对滑动窗口注意力（SWA）模型使用全尺寸缓存 | false | `LLAMA_ARG_SWA_FULL` |
| `-fa, --flash-attn [on|off|auto]` | 是否启用 Flash Attention | auto | `LLAMA_ARG_FLASH_ATTN` |
| `--perf, --no-perf` | 是否启用 libllama 内部性能计时 | false | `LLAMA_ARG_PERF` |
| `-e, --escape, --no-escape` | 是否转义序列处理（`\n`、`\r`、`\t`、`\'`、`\"`、`\\`） | true | — |

## 四、RoPE 与长上下文外推（YaRN）

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `-r, --rope-freq-scale N` | RoPE 频率缩放（用于上下文外推，如 YaRN）。>1 扩展上下文，<1 收缩 | 1.0（与模型元数据一致时不缩放） | `LLAMA_ARG_ROPE_FREQ_SCALE` |
| `--rope-freq-std N` | 标准 RoPE 的 RMS 归一化（RMSNorm）系数 | 1.0 | `LLAMA_ARG_ROPE_FREQ_STD` |
| `--local-rope-freq-scale N` | 本地 YaRN 缩放因子（仅对当前上下文窗口有效） | 1.0 | — |

## 五、KV 缓存类型与内存处理

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `--cache-type-k` | KV 缓存 K 通道数据类型（如 `f16`、`q8_0`、`q4_0`）。影响显存占用与长上下文质量 | `f16`（由模型元数据决定） | `LLAMA_ARG_CACHE_TYPE_K` |
| `--cache-type-v` | KV 缓存 V 通道数据类型（取值同上） | `f16`（由模型元数据决定） | `LLAMA_ARG_CACHE_TYPE_V` |
| `--kv-cache-type-f16` | 将 KV 缓存设为 f16（旧版兼容参数，等同于 `--cache-type-k f16 --cache-type-v f16`） | — | — |
| `--paged-kv` | 使用分页 KV 缓存（减少碎片、支持更大上下文） | 自动 | — |
| `--kv-quant` | 对 KV 缓存使用量化（`f16`/`q8_0`/`q4_0` 等） | 同 `--cache-type-k/v` | `LLAMA_ARG_KV_QUANT` |

## 六、设备与显存卸载

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `-ngl, --gpu-layers N` | 卸载到 GPU 的层数（99 = 全部层 + 嵌入层 + KV 缓存） | 0（仅 CPU） | `LLAMA_ARG_NGL` |
| `--tensor-split N` | 多 GPU 时按张量并行切分比例（0..1 之间，各卡之和 ≤ 1） | 0（单卡或自动） | `LLAMA_ARG_TENSOR_SPLIT` |
| `--split-mode <row|layer|none>` | 多 GPU 切分方式：`row`（行并行，适合大模型）、`layer`（层并行，适合 MoE）、`none`（仅复制，不并行） | `layer` | — |
| `--main-gpu N` | 主 GPU 设备编号（split_mode=none 时有效） | 0 | — |
| `-gpl, --gpu-per-layer N` | 每层卸载到 GPU 的层数（逐层卸载控制，与 `-ngl` 互斥） | — | — |
| `--numa <distribute|isolate|numactl>` | NUMA 优化（见§二） | 不启用 | — |
| `--mmproj-offload` | 视觉投影器（mmproj）是否卸载到 GPU | 启用 | — |
| `-mmdev, --mmproj-device N` | 视觉投影器使用的 GPU 设备编号 | 跟随 `-ngl`/`--device` | — |

> **插件提示**：`-ngl` 默认填 `99`（全部卸载）。MoE 模型请配合 `-ncmoe N` 控制专家层卸载数量以节省显存。

## 七、模型加载方式与模型来源

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `-m, --model PATH` | 模型 GGUF 文件路径（插件自动填入） | — | — |
| `-a, --alias NAME` | 模型别名（用于 `/v1/models` 等端点展示，插件自动填入） | — | — |
| `--model-cache PATH` | 模型缓存目录（用于 `--huggingface` 下载） | 默认缓存路径 | `LLAMA_ARG_MODEL_CACHE` |
| `-hf, --huggingface REPO` | 直接从 Hugging Face 拉取模型（用户名/仓库名） | — | — |
| `-ct, --checkout REPO:BRANCH` | 从 Hugging Face checkout 指定分支 | — | — |
| `--hf-access-token TOKEN` | Hugging Face 访问令牌 | — | — |
| `--no-lora-discard` | 不丢弃 LoRA 适配器的微调权重 | — | — |

## 八、LoRA 与控制向量

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `--lora PATH` | LoRA 适配器路径（可多次指定，叠加多个） | — | — |
| `--lora-scales SCALE` | 对应每个 LoRA 的缩放系数（逗号分隔，1.0 = 全量应用） | — | — |
| `--control-vector PATH` | 控制向量文件路径 | — | — |
| `--control-vector-scales SCALE` | 控制向量缩放系数（逗号分隔） | — | — |
| `--conv-mode MODE` | 对话模式：`llama2`、`mistral`、`chatml`、`phi3`、`command-r`、`gemma`、`mixtral`、`qwen2`、`olmo`、`dbrx`、`starcoder2`、`cerebras`、`jamba`、`test` | — | — |

## 九、日志与调试

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `-v, --verbose` | 详细日志模式 | — | — |
| `--log-disable` | 禁用日志输出 | — | — |
| `--log-prefix` | 日志前缀格式 | — | — |
| `--color` | 日志是否使用颜色 | 自动 | — |
| `--log-tokens` | 在日志中打印 token 信息 | — | — |
| `--verbose-file PATH` | 将详细日志输出到文件 | — | — |

## 十、采样参数

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `--temp N` | 采样温度（0 = 贪婪解码；>1 更发散） | 0.80 | `LLAMA_ARG_TEMP` |
| `--top-k N` | 保留概率最高的 K 个 token（0 = 关闭，-1 = 使用全部） | 40 | `LLAMA_ARG_TOP_K` |
| `--top-p N` | 核采样阈值（累积概率阈值） | 0.95 | `LLAMA_ARG_TOP_P` |
| `--min-p N` | 最小概率阈值（过滤低于该比例的 token） | 0.05 | `LLAMA_ARG_MIN_P` |
| `--repeat-penalty N` | 重复惩罚系数（>1 降低重复，1.0 = 不惩罚） | 1.10 | `LLAMA_ARG_REPEAT_PENALTY` |
| `--presence-penalty N` | 存在惩罚（>0 鼓励引入新 token） | 0.0 | `LLAMA_ARG_PRESENCE_PENALTY` |
| `--frequency-penalty N` | 频率惩罚（>0 降低已出现 token 的概率） | 0.0 | `LLAMA_ARG_FREQUENCY_PENALTY` |
| `--dry-multiplier N` | DRY 模式的 multiplier | 1.0 | — |
| `--dry-base N` | DRY 模式的 base 系数 | 1.0 | — |
| `--dry-allowed-length N` | DRY 模式允许的最大重复前缀长度 | 2 | — |
| `--dry-penalty-N-grams N` | DRY 模式的 N-gram 数量 | 0 | — |
| `--dry-penalty-repeat N` | DRY 模式的重复惩罚 | 0.0 | — |
| `--mirostat N` | Mirostat 采样（0=关闭，1=Mirostat 1.0，2=Mirostat 2.0） | 0 | `LLAMA_ARG_MIROSTAT` |
| `--mirostat-lr N` | Mirostat 学习率 | 0.10 | — |
| `--mirostat-ent N` | Mirostat 目标熵 | 5.0 | — |
| `--xtc-probability N` | XTC 采样概率 | 0.0 | — |
| `--xtc-threshold N` | XTC 阈值 | 0.10 | — |

> **插件提示**：插件默认预填 `--temp 1.0`、`--top-k 20`、`--top-p 0.95`、`--min-p 0.0`、`--repeat-penalty 1`、`--presence-penalty 0`。

## 十一、投机解码与查找解码

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `--draft PATH` | 草稿模型（speculative decoding 的 draft 器） | — | — |
| `--draft-paths PATH` | 多草稿模型路径（逗号分隔） | — | — |
| `--draft-scales SCALE` | 对应每个草稿的缩放系数 | — | — |
| `-sp, --speculative-n N` | 投机解码的预测步数 | 4 | — |
| `-sd, --speculative-delta N` | 投机解码的采样间隔 | 8 | — |
| `--speculative-pooling N` | 投机解码池化模式（`first`、`last`、`mean`） | `last` | — |
| `--speculative-max-batch N` | 投机解码的最大批次大小 | 128 | — |
| `--speculative-accept-ratio N` | 投机解码接受率阈值（0..1，低于此值禁用投机） | 0.40 | — |
| `--mtp N` | 多-token 预测（MTP）步数（模型需带 MTP 头） | 0 | — |
| `--mtp-draft N` | MTP 的草稿步数 | — | — |
| `--mtp-scale N` | MTP 的缩放系数 | 1.0 | — |
| `--mtp-mixed` | 启用 MTP 混合模式 | — | — |
| `--mtp-freq N` | MTP 的频率（多少步使用一次 MTP） | — | — |
| `--mtp-tokens N` | MTP 的 token 数量 | — | — |
| `-ctkd, --spec-draft-type-k TYPE` | 投机解码的草稿 KV 缓存 K 类型 | 同主 KV | — |
| `-ctvd, --spec-draft-type-v TYPE` | 投机解码的草稿 KV 缓存 V 类型 | 同主 KV | — |

> **注意**：启用投机解码时，draft 的 KV 档（`-ctkd`/`-ctvd`）是独立参数，默认可能比主 KV 档更宽。

## 十二、Prompt 缓存与槽位（Slots）

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `--prompt-cache PATH` | Prompt 缓存文件路径（持久化缓存，跨请求复用） | — | — |
| `--prompt-cache-idx PATH` | Prompt 缓存索引文件路径 | — | — |
| `--prompt-cache-ro` | 以只读模式加载 prompt 缓存 | — | — |
| `--slots` | 启用 slot 模式（多会话并发） | — | — |
| `--slot` | 指定 slot ID | — | — |
| `--slot-pool N` | Slot 池大小 | — | — |

## 十三、并发、批处理与生成行为

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `-np, --parallel N` | 并行解码序列数（服务器模式下每个请求独立解码） | 1 | `LLAMA_ARG_PARALLEL` |
| `--cancel-prompt N` | 取消提示词时的行为（`discard`、`retain`、`auto`） | `auto` | — |
| `--output-original` | 输出原始 token（不经过 detokenizer 后处理） | — | — |
| `--output-raw` | 输出原始字节（不转码） | — | — |
| `--grammar N` | CFG 文法约束（BNFL 格式） | — | — |
| `--grammar-init N` | 文法初始化字符串 | — | — |
| `--grammar-file PATH` | 文法文件路径 | — | — |
| `--logit-bias PATH` | Logit bias 文件（JSON，格式 `{token_id: bias}`） | — | — |
| `--logit-bias-inline N` | 内联 logit bias 字符串 | — | — |
| `--logit-bias-file PATH` | Logit bias 文件路径（JSON） | — | — |

## 十四、多模态（视觉与视频）

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `--mmproj PATH` | 视觉投影器（mmproj）GGUF 文件路径（插件自动填入） | — | — |
| `--image-min-tokens N` | 图片最小 token 数 | 256 | — |
| `--image-max-tokens N` | 图片最大 token 数 | 16384 | — |
| `--image-patch-size N` | 图像 patch 大小 | — | — |
| `--image-mean N` | 图像归一化均值（逗号分隔） | — | — |
| `--image-std N` | 图像归一化标准差（逗号分隔） | — | — |
| `--video-fps N` | 视频帧率（FPS，用于视频抽帧） | — | — |
| `--video-timestamp-interval N` | 视频时间戳间隔 | — | — |
| `--video-ffmpeg-dir PATH` | FFmpeg 可执行文件目录 | — | — |
| `--image-extract-all` | 提取所有 image tokens（不做下采样） | — | — |
| `--image-extract-max N` | 最大提取 image tokens 数量 | — | — |
| `--image-extract-min N` | 最小提取 image tokens 数量 | — | — |
| `--image-extract-step N` | 图像提取步长 | — | — |
| `--video-extract-all` | 提取所有视频帧 | — | — |
| `--video-extract-max N` | 最大提取视频帧数 | — | — |
| `--video-extract-min N` | 最小提取视频帧数 | — | — |
| `--video-extract-step N` | 视频提取步长 | — | — |

> **插件提示**：`--mmproj` 由插件自动从模型文件夹中检测并填入。`--image-min-tokens` 默认 256。

## 十五、Embedding 与 Rerank

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `--embedding` | 启用 embedding 模式（输出文本嵌入向量） | — | `LLAMA_ARG_EMBEDDING` |
| `--reranking` | 启用 rerank 模式（对候选文本做相关性排序） | — | — |
| `--pooling N` | 池化方式（`mean`、`last`、`cls`） | `mean` | — |
| `--embedding-batch N` | Embedding 批大小 | 512 | — |

## 十六、HTTP 服务与网络

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `--host HOST` | 服务监听地址（插件自动填入，默认 127.0.0.1） | 127.0.0.1 | `LLAMA_ARG_HOST` |
| `--port PORT` | 服务端口（插件自动填入，默认 8080） | 8080 | `LLAMA_ARG_PORT` |
| `--timeout N` | 请求超时秒数 | 300 | — |
| `--timeout-read N` | 读取超时秒数 | 300 | — |
| `--timeout-write N` | 写入超时秒数 | 300 | — |
| `--n-http-servers N` | HTTP 服务器线程数 | 1 | — |
| `--grpc` | 启用 gRPC 服务 | — | — |
| `--grpc-port PORT` | gRPC 端口 | — | — |

> **插件提示**：`--host` 和 `--port` 由插件自动管理，无需在参数行中填写。端口默认 55555（插件配置中设置）。

## 十七、安全认证与 CORS

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `--api-key KEY` | API 密钥（Bearer token 认证，插件自动填入） | — | `LLAMA_ARG_API_KEY` |
| `--cors` | 启用 CORS（跨域请求） | — | — |
| `--allow-credentials` | 允许携带凭据（Cookie/Authorization） | — | — |
| `--max-log-len N` | 最大日志长度 | — | — |

> **插件提示**：`--api-key` 由插件自动管理。留空表示不进行认证（仅 127.0.0.1 本地访问）。

## 十八、Web UI 与 Agent 内置工具（实验性）

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `--web` | 启用内置 Web UI | — | — |
| `--web-port PORT` | Web UI 端口 | — | — |
| `--agent` | 启用 Agent 模式（可调用内置工具） | — | — |
| `--tools` | 可用的内置工具列表 | — | — |

## 十九、聊天模板与推理（思考）模式

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `--chat-template TEMPLATE` | 自定义 Jinja 聊天模板 | — | — |
| `--chat-template-file PATH` | 从文件加载聊天模板 | — | — |
| `--use-default-chat` | 使用默认聊天模板 | — | — |
| `--enable-thinking` | 启用思考模式（reasoning model） | — | `LLAMA_ARG_ENABLE_THINKING` |
| `--reasoning-budget N` | 思考预算 token 数上限（留空 = 以上游默认值，通常为 n_ctx/2） | — | `LLAMA_ARG_REASONING_BUDGET` |
| `--reasoning-effort N` | 请求级思考努力程度（off/medium/high） | — | — |
| `--reasoning-parser N` | 思考解析器（`default`、`olmoe`、`gemini`） | `default` | — |
| `--system-prompt PROMPT` | 系统提示词 | — | — |
| `--prefix PROMPT` | 前缀提示词（用于续写场景） | — | — |
| `--suffix PROMPT` | 后缀提示词 | — | — |

> **插件提示**：`--reasoning-budget` 必须通过 server 启动参数传入（请求级 `reasoning_effort` 常被客户端忽略）。留空时以上游默认值生效。

## 二十、模型别名与路由服务器

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `--alias NAME` | 模型别名（插件自动填入） | — | — |
| `--router` | 启用路由服务器模式（多模型路由） | — | — |
| `--router-models PATH` | 路由模型配置文件路径 | — | — |
| `--router-default NAME` | 默认路由模型 | — | — |

## 二十一、监控与管理端点、空闲休眠

| 参数 | 说明 | 默认值 | 环境变量 |
|---|---|---|---|
| `--metrics` | 启用 `/metrics` 端点（Prometheus 格式） | — | — |
| `--health` | 启用 `/health` 端点（健康检查） | — | — |
| `--props` | 启用 `/props` 端点（服务器属性） | — | — |
| `--slots` | 启用 `/slots` 端点（槽位状态） | — | — |
| `--idle-timeout N` | 空闲超时秒数（无人请求时自动停止） | 0（不休眠） | — |
| `--idle-sleep-ms N` | 空闲休眠毫秒数 | 10 | — |

> **插件提示**：`--metrics` 和 `--slots` 是插件默认预填的参数，用于健康检查与状态监控。

## 二十二、预设模型快捷参数

| 参数 | 说明 | 默认值 |
|---|---|---|
| `--chat-template llama2` | 快捷预设：Llama 2 聊天模板 | — |
| `--chat-template mistral` | 快捷预设：Mistral 聊天模板 | — |
| `--chat-template chatml` | 快捷预设：ChatML 模板 | — |
| `--chat-template phi3` | 快捷预设：Phi-3 模板 | — |
| `--chat-template qwen2` | 快捷预设：Qwen2 模板 | — |

---

## 附：插件 8 组默认参数速查

> 这些默认值是**给新用户快速上手**的通用起点，**不针对任何特定模型调优**。
> 针对具体模型/显卡的调优项（例如 `-ncmoe`、`-ncffn`）请按 `docs/measurements/`
> 的实测数据自行添加。

| 参数 | 快速组 | 长上下文组 |
|------|----------------------|------------|
| `-ngl` | 99 | 99 |
| `-fa` | on | on |
| `-t` | 14 | 14 |
| `-tb` | 14 | 14 |
| `-np` | 1 | 1 |
| `--cache-type-k` | q8_0 | q8_0 |
| `--cache-type-v` | q8_0 | q8_0 |
| `--temp` | 1.0 | 1.0 |
| `--top-k` | 20 | 20 |
| `--top-p` | 0.95 | 0.95 |
| `--min-p` | 0.0 | 0.0 |
| `--repeat-penalty` | 1 | 1 |
| `--presence-penalty` | 0 | 0 |
| `--reasoning-budget` | **8192** | **8192** |
| `-c` | 32768 | 131072 |
| `--metrics` | （空） | （空） |
| `--slots` | （空） | （空） |

> 插件自动管理的参数（不在以上列表中）：`-m`、`-a`、`--port`、`--host`、`--api-key`，以及视觉模式下的 `--mmproj` 和 `--image-min-tokens`。

> **取值型参数与纯开关的区别（重要）**：
> - `--metrics`、`--slots` 是**纯开关**，没有值 —— 参数行留空时仍照常发出。
> - 其余参数**都需要值**。某行留空 = 该参数被移除，**整行不发给 llama-server**。
> - 原因：发出**裸的取值型 flag** 会让 llama.cpp 把**下一个参数**当成它的值。
>   例如裸 `--reasoning-budget` 会吞掉紧随的 `-c`，然后以 `invalid stoi argument`
>   退出，服务器根本起不来。`--reasoning-budget` 的默认值因此从「空」改为 **`8192`**
>   （= 给思考一个明确上限，避免思考把输出预算吃光；`-1` 表示不限制）。

> **显存不够时的调优提示（不是默认值）**：若模型比显存大，llama.cpp 会试图把整个
> 模型放进显存并溢出到 PCIe 分页（此时服务器**仍会打印 `model loaded`**，但推理极慢）。
> `-ngl 99` 被显式指定时自动 fit 会直接放弃，所以必须显式加卸载档：MoE 模型用
> `-ncmoe N`（把前 N 层的 MoE 专家权重留在 CPU），dense 模型用 `-ncffn N`。
> 具体档位见 `docs/measurements/` 的各模型实测。
