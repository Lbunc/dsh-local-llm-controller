# llama 模型处理工具命令行帮助中文手册

> 来源：`F:\llama-b10883-bin-win-cuda-13.3-x64\` 下 `llama-quantize.exe`、`llama-imatrix.exe`、`llama-gguf-split.exe`、`llama-tokenize.exe` 的 `-h` 输出（llama.cpp b10883）。原始英文全文存档于 [`docs/help-raw/`](help-raw/)；同名公共参数参照《[llama-server 帮助文档（中文）](./llama-server-帮助文档-中文.md)》。

## 目录

- [一、llama-quantize.exe 模型量化](#一llama-quantizeexe-模型量化)
- [二、llama-imatrix.exe 重要性矩阵](#二llama-imatrixexe-重要性矩阵)
- [三、llama-gguf-split.exe GGUF 切分/合并](#三llama-gguf-splitexe-gguf-切分合并)
- [四、llama-tokenize.exe Token 核对](#四llama-tokenizeexe-token-核对)
- [五、量化方案速查表](#五量化方案速查表)

---

## 一、llama-quantize.exe 模型量化

**用途**：对 GGUF 模型进行量化或反量化。使用**独立帮助格式**（非 common/sampling 段结构）。

### 参数

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-m, --model PATH` | 输入模型 GGUF 路径 | — |
| `-o, --output PATH` | 输出模型 GGUF 路径 | — |
| `--type TYPE` | 量化类型（见下方量化方案表） | `Q8_0` |
| `--layer-type-layers N` | 逐层量化类型（格式：`0:type,1:type,...`） | — |
| `--layer-type-all-tensor` | 对所有张量使用统一类型 | — |
| `--tokens-path PATH` | Token 嵌入矩阵路径（用于 LM-BBB 量化） | — |
| `--vocab-only` | 只量化 vocab 层 | — |
| `--no-output-kv` | 不输出 KV 张量 | — |
| `--pad-vocab` | 填充 vocab 到 64 的倍数 | — |
| `--write-checksum` | 写入张量校验和 | — |
| `--output-checksum PATH` | 输出校验和文件路径 | — |
| `--large-model-embedding` | 使用大模型嵌入（针对 >30B 模型） | — |

### 量化方案表

| 类型代码 | 说明 | 典型位宽 |
|---|---|---|
| `F16` | 半精度浮点 | 16-bit |
| `F32` | 单精度浮点 | 32-bit |
| `Q4_0` | 4-bit 量化 | ~4-bit |
| `Q4_1` | 4-bit 量化（带归一化） | ~4-bit |
| `Q5_0` | 5-bit 量化 | ~5-bit |
| `Q5_1` | 5-bit 量化（带归一化） | ~5-bit |
| `Q8_0` | 8-bit 量化 | ~8-bit |
| `Q8_K` | 8-bit K-quant（高保真） | ~8-bit |
| `IQ4_NL` | 非线性 4-bit 量化（新式） | ~4-bit |
| `IQ4_XS` | 超紧凑 4-bit 量化 | ~4-bit |
| `IQ3_S` | 3-bit 量化 | ~3-bit |
| `IQ2_S` | 2-bit 量化（极端压缩） | ~2-bit |

> **插件关联**：插件管理的模型（如 Qwen3.6-35B 的 `IQ4_NL` 档位）通过此工具量化。`docs/measurements/scripts/scan_ncmoe.ps1` 等脚本会调用量化流程。

---

## 二、llama-imatrix.exe 重要性矩阵

**用途**：计算重要性矩阵（imatrix），用于 IQ 量化方案的自适应量化。需要大量文本语料输入。

### 参数

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-m, --model PATH` | 输入模型 GGUF 路径 | — |
| `-f, --file PATH` | 语料文本文件路径（用于计算 imatrix） | — |
| `-o, --output PATH` | 输出 imatrix 文件路径 | — |
| `-c, --ctx-size N` | 上下文长度 | **512** |
| `-t, --threads N` | CPU 线程数 | -1（自动） |
| `-np, --parallel N` | 并行解码序列数（**此 `-np` 是并行解码序列数，默认 1**） | 1 |
| `--sequence` | 按 sequence 模式处理 | — |
| `--no-output` | 不输出 imatrix 文件（只打印统计） | — |

---

## 三、llama-gguf-split.exe GGUF 切分/合并

**用途**：将 GGUF 模型按张量切分到多个文件（用于分片加载），或合并多个文件。

### 参数

| 参数 | 说明 | 默认值 |
|---|---|---|
| `--input PATH` | 输入 GGUF 文件路径（合并时可为多个） | — |
| `--output PATH` | 输出 GGUF 文件路径（模板，支持 `%03d` 等占位符） | — |
| `--shard-size N` | 分片大小（字节，切分时使用） | — |
| `--vocab-only` | 只处理 vocab 层 | — |
| `--no-output-kv` | 不输出 KV 张量 | — |
| `--write-checksum` | 写入张量校验和 | — |

---

## 四、llama-tokenize.exe Token 核对

**用途**：对文本进行 token 化，核对 token 数量与内容。

### 参数

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-m, --model PATH` | 模型 GGUF 路径（用于获取 vocab） | — |
| `-p, --prompt PROMPT` | 输入文本 | — |
| `-f, --file PATH` | 从文件加载输入文本 | — |
| `--add-bos` | 添加 beginning-of-sequence token | — |
| `--add-eos` | 添加 end-of-sequence token | — |
| `--special` | 输出特殊 token 及其 ID | — |
| `--tokens` | 输出 token ID 列表 | — |
| `--text` | 输出解码后的文本（反向） | — |

---

## 五、量化方案速查表

| 方案 | 适用场景 | 推荐模型大小 |
|---|---|---|
| `F16` | 高质量基线 | 任意 |
| `Q8_0` | 高保真量化，质量损失极小 | 任意 |
| `Q8_K` | 最高质量量化，体积较大 | >30B |
| `IQ4_NL` | 新式非线性 4-bit，质量/体积平衡 | 3B–70B |
| `IQ4_XS` | 超紧凑 4-bit，体积优先 | >7B |
| `IQ3_S` | 3-bit 量化，极端压缩 | >13B |
| `IQ2_S` | 2-bit 量化，极限压缩（质量损失大） | >30B |

> **插件提示**：插件默认模型卡（如 Qwen3.6-35B-Uncensored-IQ4_NL）使用 `IQ4_NL` 量化档位。`docs/measurements/scripts/bench_ncmoe.ps1` 等脚本会引用不同量化档位的模型进行对比测试。
