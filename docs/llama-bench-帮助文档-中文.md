# llama-bench 命令行帮助中文手册

> 来源：`F:\llama-b10883-bin-win-cuda-13.3-x64\llama-bench.exe -h` 的原始输出（llama.cpp b10883，Windows CUDA 13.3 x64 发行版）。
> 原文分为 `options`（运行与输出控制）和 `test parameters`（测试参数）两块，末尾附多值扫描规则；本文档在此基础上按用途细分，参数名与取值保持英文原文。
> 注意：该发行版运行 `-h` 时会先打印后端加载日志（`ggml_cuda_init ...`、`load_backend ...`），随后才是 usage 文本——那些是运行时日志，不属于帮助内容。部分默认值与本机相关（如 `-t` 默认 14 即本机自动检测的线程数）。

本手册用于**深度调优阶段的吞吐基准测试**。插件日常运行不依赖 llama-bench，但 `docs/measurements/scripts/bench_ncmoe.ps1` 等脚本通过它验证 `-ncmoe N` 对速度的影响。

## 目录

1. [帮助、设备与运行控制](#一帮助设备与运行控制)
2. [输出与进度](#二输出与进度)
3. [显存适配与 RPC](#三显存适配与-rpc)
4. [模型来源](#四模型来源)
5. [基准负载参数（测什么）](#五基准负载参数测什么)
6. [计算与加载配置（怎么跑）](#六计算与加载配置怎么跑)
7. [多值扫描语法（参数组合）](#七多值扫描语法参数组合)
8. [与 llama-server 参数的对应关系](#八与-llama-server-参数的对应关系)

---

## 一、帮助、设备与运行控制

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-h, --help` | 打印本帮助并退出 | — |
| `--list-devices` | 列出可用计算设备并退出 | — |
| `-v, --verbose` | 详细输出 | 关闭 |
| `--numa <distribute|isolate|numactl>` | NUMA 优化模式 | 禁用 |
| `-r, --repetitions <n>` | 每个测试项的重复次数 | 5 |
| `--prio <-1|0|1|2|3>` | 进程/线程优先级（-1=low，0=normal，1=medium，2=high，3=realtime） | 0 |
| `--delay <0...N>` | 每个测试项之间的间隔（秒） | 0 |
| `--no-warmup` | 跳过基准测试前的预热运行 | 关闭（默认会预热） |

## 二、输出与进度

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-o, --output <csv|json|jsonl|md|sql>` | 输出到 stdout 的格式 | md（Markdown 表格） |
| `-oe, --output-err <csv|json|jsonl|md|sql>` | 输出到 stderr 的格式 | none |
| `--progress` | 打印测试进度指示 | 关闭 |

## 三、显存适配与 RPC

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-fitt, --fit-target <MiB>` | 自动调整参数使模型适配显存，并给每个设备保留该余量（MiB） | off |
| `-fitc, --fit-ctx <n>` | `--fit-target` 可设置的最小上下文长度 | 4096 |
| `-rpc, --rpc <rpc_servers>` | 注册 RPC 设备（host:port，逗号分隔） | — |

## 四、模型来源

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-m, --model <filename>` | 本地模型文件路径 | `models/7B/ggml-model-q4_0.gguf` |
| `-hf, -hfr, --hf-repo <user>/<model>[:quant]` | Hugging Face 模型仓库；quant 可选、不区分大小写，默认 `Q4_K_M`，仓库没有 Q4_K_M 时退回第一个文件。例：`ggml-org/GLM-4.7-Flash-GGUF:Q4_K_M` | 不使用 |
| `-hff, --hf-file <file>` | Hugging Face 模型文件名；指定后覆盖 `--hf-repo` 中的 quant | 不使用 |
| `-hft, --hf-token <token>` | Hugging Face 访问令牌 | HF_TOKEN 环境变量值 |
| `--offline` | 离线模式：强制使用缓存，禁止网络访问 | 禁用 |

## 五、基准负载参数（测什么）

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-p, --n-prompt <n>` | 提示词处理（prefill/PP）测试的 token 数 | 512 |
| `-n, --n-gen <n>` | 文本生成（decode/TG）测试的 token 数 | 128 |
| `-pg <pp,tg>` | PP+TG 联合测试组合（一次请求先处理 pp 个再生成 tg 个，可多组逗号分隔） | 空 |
| `-d, --n-depth <n>` | 测试开始前预先填入 KV 缓存的历史上下文深度（token 数） | 0 |
| `-embd, --embeddings <0|1>` | 以 embedding 模式加载测试（1 = 启用嵌入） | 0 |

> **★llama-bench 没有 `-c` 参数**：上下文长度只能由 `-p`（提示词长度）+ `-n`（生成长度）+ `-d`（预填 KV 深度）共同表达。旧模板中若带 `-c` 会直接报错。

## 六、计算与加载配置（怎么跑）

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-t, --threads <n>` | 生成使用的 CPU 线程数 | 本机为 14（自动检测） |
| `-C, --cpu-mask <hex,hex>` | CPU 亲和性掩码 | 0x0 |
| `--cpu-strict <0|1>` | 严格 CPU 绑定 | 0 |
| `--poll <0...100>` | 等待任务时的轮询强度（0 = 不轮询） | 50 |
| `-b, --batch-size <n>` | 逻辑最大批大小 | 2048 |
| `-ub, --ubatch-size <n>` | 物理最大批大小 | 512 |
| `-ngl, --n-gpu-layers <n>` | 存入显存的层数 | -1（尽量全部卸载） |
| `-ncmoe, --n-cpu-moe <n>` | 前 N 层的 MoE 专家权重留在 CPU | 0 |
| `-sm, --split-mode <none|layer|row|tensor>` | 多 GPU 切分方式 | layer |
| `-mg, --main-gpu <i>` | 主 GPU 编号 | 0 |
| `-ts, --tensor-split <ts0/ts1/..>` | 各 GPU 的模型分配比例 | 0 |
| `-dev, --device <dev0/dev1/...>` | 指定卸载设备 | auto |
| `-fa, --flash-attn <on|off|auto>` | Flash Attention 开关 | auto |
| `-ctk, --cache-type-k <t>` | KV 缓存 K 的数据类型 | f16 |
| `-ctv, --cache-type-v <t>` | KV 缓存 V 的数据类型 | f16 |
| `-nkvo, --no-kv-offload <0|1>` | 禁用 KV 缓存卸载（1 = 禁用） | 0（即默认启用） |
| `-lm, --load-mode <auto|none|mmap|mlock|mmap+mlock|dio>` | 模型加载模式（含义同 llama-server） | auto |
| `-lzm, --lazy-mode <on|auto|off>` | 大张量按需读取模式（含义同 llama-server） | auto |
| `-ot --override-tensor <张量名模式>=<buffer类型>;...` | 覆盖指定张量的 buffer 类型 | 禁用 |
| `-nopo, --no-op-offload <0|1>` | 禁用 host 张量运算的设备卸载（1 = 禁用） | 0（即默认启用卸载） |
| `--no-host <0|1>` | 绕过 host buffer（1 = 启用） | 0 |

## 七、多值扫描语法（参数组合）

原文结尾说明（这是 llama-bench 的核心用法）：

> Multiple values can be given for each parameter by separating them with ',' or by specifying the parameter multiple times. Ranges can be given as 'first-last' or 'first-last+step' or 'first-last*mult'.

**译文：** 每个参数都可以给出多个值——用逗号 `,` 分隔，或重复指定该参数多次；还支持范围语法：`first-last`、`first-last+step`、`first-last*mult`。

用法示例：

```powershell
# 对同一模型扫描不同层数与不同提示长度（自动做笛卡尔组合）
.\llama-bench.exe -m my.gguf -ngl 0,20,99 -p 512,4096,32768

# 范围写法：-p 从 512 到 32768，步进 1024（+step）或倍增（*mult）
.\llama-bench.exe -m my.gguf -p 512-32768+1024 -n 128-1024*2

# KV 类型对比实验 + 多模型对比
.\llama-bench.exe -m A.gguf,B.gguf -ctk q8_0 -ctv q4_0 -fa on -o md
```

提示：多值会显著增加测试项数量（总耗时 = 组合数 × 每项 `-r` 重复次数），可先用 `-r 1 --progress` 快速摸底。

> **★归档首选 `-o csv`**：列里直接带 `n_cpu_moe` / `n_depth` / `type_k` / `type_v` / `n_threads` / `n_gpu_layers` / `flash_attn` / `load_mode` / `avg_ts` / `stddev_ts`，即**每条记录自带全部实验条件**。

## 八、与 llama-server 参数的对应关系

llama-bench 复用了 llama.cpp 的公共参数体系，以下参数含义与 `llama-server` 完全相同（详见《[llama-server 帮助文档（中文）](./llama-server-帮助文档-中文.md)》对应章节）：

| llama-bench | llama-server | 含义 | server 文档章节 |
|---|---|---|---|
| `-t / -C / --cpu-strict / --poll / --numa / --prio` | 同名 | 线程与 CPU 调度 | 二 |
| `-b / -ub` | `-b / -ub` | 批大小 | 三 |
| `-fa / -ctk / -ctv` | 同名 | Flash Attention、KV 类型 | 三 / 五 |
| `-ngl / -sm / -ts / -mg / -dev / -ncmoe / -ot` | 同名 | 显存卸载与多卡 | 六 |
| `-lm / -lzm` | 同名 | 加载模式 | 七 |
| `-nkvo / --no-host / -nopo` | `-kvo / --no-host / --no-op-offload`（开关方向一致） | KV 卸载、host buffer、运算卸载 | 五 / 六 |
| `-fitt / -fitc` | 同名 | 显存自适应 | 六 |
| `-rpc` | `--rpc` | RPC 分布式 | 七 |
| `-hf / -hff / -hft / --offline / -m` | 同名 | 模型来源 | 七 |

不同点：llama-bench **没有**采样、投机解码、HTTP/网络、WebUI、模板等服务器参数，取而代之的是负载定义参数（第五节）与重复/输出控制（第一、二节）。

---

## 与插件的关联

| 参数/特性 | 在插件调优中的用途 |
|---|---|
| `-ncmoe N` | 扫描 MoE 专家层卸载数量，找到速度与显存的平衡点（`docs/measurements/scripts/bench_ncmoe.ps1`） |
| `-o csv` | 归档实验结果，每条记录自带全部实验条件 |
| `-d 深度扫描` | 测试长上下文深度下的吞吐衰减 |
| `-fitt` | 显存自适应（**注意：不能替代 `-ncmoe`，超额 MoE 必须显式扫卸载档**） |
| `-p + -n + -d` | 表达上下文长度（llama-bench 无 `-c` 参数） |

> **调优提示**：`-ngl` 与 `-ncmoe` 在多值扫描时是**全局笛卡尔积**（如 `-ngl 0,99 -ncmoe 20,22` = 4 组），无法给每个模型各自独立的 `-ncmoe`。多模型对比时（`-m A.gguf,B.gguf`），`-ncmoe` 对所有模型生效。
