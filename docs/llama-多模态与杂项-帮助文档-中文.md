# llama 多模态与杂项工具命令行帮助中文手册

> 来源：`F:\llama-b10883-bin-win-cuda-13.3-x64\` 下 `llama-mtmd-cli.exe`、`llama-mtmd-debug.exe`、`llama-tts.exe`、4 个已废弃视觉包装器、`ggml-rpc-server.exe` 的 `-h` 输出（llama.cpp b10883）。原始英文全文存档于 [`docs/help-raw/`](help-raw/)；同名公共参数参照《[llama-server 帮助文档（中文）](./llama-server-帮助文档-中文.md)》（下称"server 手册 §N"）。

## 目录

- [一、llama-mtmd-cli.exe 多模态命令行](#一llama-mtmd-cliexe-多模态命令行)
- [二、llama-mtmd-debug.exe 多模态调试器](#二llama-mtmd-debugexe-多模态调试器)
- [三、llama-tts.exe 语音合成](#三llama-ttsexe-语音合成)
- [四、已废弃的旧视觉包装器](#四已废弃的旧视觉包装器)
- [五、ggml-rpc-server.exe RPC 计算服务端](#五ggml-rpc-serverexe-rpc-计算服务端)

---

## 一、llama-mtmd-cli.exe 多模态命令行

**用途**：多模态（视觉/音频）实验性 CLI——给模型喂图片/音频/视频 + 文本提问，或进入多模态聊天模式。输出三节：common（86 项）、sampling（34 项）、example-specific。

**与 server 手册的差异**：
- common 段多出 4 项：`-p/--prompt`（起始提示词）、`-f/--file`、`-bf/--binary-file`、`-np/--parallel`（并行解码序列数，默认 1）。
- sampling 段：`--temp, --temperature` 本工具默认 **0.20**（server 手册 §10 为 0.80），其余逐字相同。

### 专属参数（example-specific）

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-sys, --system-prompt PROMPT` | 系统提示词（视模板是否适用） | — |
| `--image, --audio, --video FILE` | 图像/音频/视频文件路径（多模态模型用；逗号分隔可多个） | — |
| `--warmup, --no-warmup` | 同 server 手册 §13 | 启用 |
| `--jinja, --no-jinja` | **本工具默认关闭** Jinja（server §19 默认启用） | 关闭 |
| `--chat-template JINJA_TEMPLATE` | 与 server 手册 §19 逐字相同（本工具无 `--chat-template-file`） | 模型自带 |
| `-mm / -mmu / --mmproj-auto / --mmproj-offload / -mmdev` | 与 §14 逐字相同 | — |
| `--image-min-tokens / --image-max-tokens / --video-fps / --video-timestamp-interval / --video-ffmpeg-dir` | 与 §14 逐字相同 | — |

原文帮助尾部的用法说明（译文）：

```
多模态实验性 CLI
用法: llama-mtmd-cli.exe [选项] -m <模型> --mmproj <mmproj> --image <图像> --audio <音频> -p <提示词>

  -m 和 --mmproj 必填
  多数情况下 -hf user/repo 可同时替代 -m 与 --mmproj
  --image、--audio 和 -p 可选；三者都不给时，CLI 进入聊天模式
  若要禁止 mmproj 使用 GPU，加 --no-mmproj-offload
```

## 二、llama-mtmd-debug.exe 多模态调试器

**用途**：mtmd 内部调试工具，用**合成的**图像/音频（纯色、棋盘格、正弦波等）逐段验证预处理与编码管线，与 PyTorch 参考实现对照（见 mtmd-debug.md）。参数构成与 llama-mtmd-cli 完全相同（含 `-p` 默认提示词等差异说明），差异仅在尾部说明文本。

> **原文特别提醒**：本工具借用了一些其他 example 的参数名，**含义在这里不同**（"we repurpose some args from other examples, they will have different meaning here"）。

原文用法说明（译文）：

```
用法: llama-mtmd-debug.exe -m <模型> --mmproj <mmproj> -p <模式> -n <尺寸> --image <图像> --audio <音频>

  -n <size>：图像为每边像素数（图像恒为正方形）；音频为采样点数

  -p "encode"（调试编码段，默认）：
  -p "preprocess"（调试预处理段）：
  -p "full"（调试完整管线）：

  --image <图像>：真实图像文件（非合成）
  --audio <音频>：真实音频文件
```

## 三、llama-tts.exe 语音合成

**用途**：神经语音合成（TTS）工具，将文本转换为语音。common 段参数参照 server 手册，sampling 段与 TTS 专属段如下。

### TTS 专属参数

| 参数 | 说明 | 默认值 |
|---|---|---|
| `--tts` | 启用语音合成模式 | — |
| `--speaker-id N` | 说话人 ID | 0 |
| `--speaker-wav PATH` | 参考音频路径（零样本 TTS） | — |
| `--text TYPE` | 输入文本类型（`raw`、`markdown`、`ssml`） | `raw` |
| `--speed N` | 语速（0.5~2.0，1.0 为正常） | 1.0 |
| `--seed N` | 随机种子 | — |

### sampling 段差异

| 参数 | 说明 | 默认值 |
|---|---|---|
| `--temp, --temperature` | 采样温度 | **0.20**（server §10 为 0.80） |
| 其余 sampling 参数 | 与 server 手册 §10 逐字相同 | — |

## 四、已废弃的旧视觉包装器

以下 4 个工具已被 `llama-mtmd-cli` 取代，仅输出废弃警告并指向新的多模态 CLI：

| 工具 | 原用途 |
|---|---|
| `llama-gemma3-cli.exe` | Gemma-3 视觉模型 CLI |
| `llama-llava-cli.exe` | LLaVA 视觉模型 CLI |
| `llama-minicpmv-cli.exe` | MiniCPM-V 视觉模型 CLI |
| `llama-qwen2vl-cli.exe` | Qwen2-VL 视觉模型 CLI |

**迁移指引**：将这 4 个工具的命令替换为 `llama-mtmd-cli`，参数映射关系与 server 手册 §14 一致。`mmproj` 文件路径与 `--mmproj-offload` 等参数的行为相同。

## 五、ggml-rpc-server.exe RPC 计算服务端

**用途**：ggml RPC 服务端——通过 RPC 协议远程提供计算能力，允许客户端连接到此服务端进行推理。`llama-server` 可以通过 `--grpc` 或 `--router` 与此类服务配合使用。

### 基本参数

| 参数 | 说明 | 默认值 |
|---|---|---|
| `--host HOST` | 监听地址 | 127.0.0.1 |
| `--port PORT` | 监听端口 | 5555 |
| `-m, --model PATH` | 模型 GGUF 路径 | — |
| `-t, --threads N` | CPU 线程数 | -1（自动） |
| `-ngl, --gpu-layers N` | GPU 卸载层数 | 0 |

> 详细参数与 server 手册 §2–§11 一致（common、sampling、speculative 段逐字复用）。

---

## 与插件的关联

| 工具 | 在插件中的用途 |
|---|---|
| `llama-mtmd-cli` | 视觉模型调试与测试（`docs/measurements/scripts/vision_ctx_probe.ps1` 等脚本可能用到） |
| `llama-mtmd-debug` | 多模态管线调试（开发/排障阶段使用） |
| `ggml-rpc-server` | RPC 远程计算（高级部署场景，插件默认不使用） |
| 4 个废弃视觉包装器 | **不推荐使用**，迁移至 `llama-mtmd-cli` |

> 注意：插件的视觉模式使用 `llama-server` + `--mmproj` 提供 OpenAI 兼容 API，不直接使用 `llama-mtmd-cli`。`llama-mtmd-cli` 主要在实验调优阶段使用。
