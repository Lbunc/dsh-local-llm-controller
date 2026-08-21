# dsh-local-llm-controller

DSH（DeepSeek Harness）插件：在「设置 → 插件」页面一键启停本地 [llama.cpp](https://github.com/ggml-org/llama.cpp) `llama-server`，把本地大模型接入 DSH 作为会话模型。

支持 **双模型 × 双模式 × 双预设**：

| 模型 | 文本/快速 | 文本/长上下文 | 视觉/快速 | 视觉/长上下文 |
|---|---|---|---|---|
| Qwen3.6-35B-A3B（IQ4_NL） | 32K | 128K | 32K + mmproj | 96K + mmproj |
| Qwen3.5-9B（Q4_K_M） | 32K | 64K | 32K + mmproj | 64K + mmproj |

## 项目定位

本插件**只负责 DSH 与 llama.cpp 之间的连接与控制**：从设置页启停 `llama-server`、回传状态、同步 contextWindow。它**不包含** llama-server 本体，也不负责模型量化与下载：

- `llama-server` 是上游 [llama.cpp](https://github.com/ggml-org/llama.cpp) 项目的产物，需自行构建或下载对应版本；
- GGUF / mmproj 模型文件来自社区量化发布（如 Hugging Face），下载后在配置里指好路径即可。

## 功能特性

- 设置 → 插件 → Local LLM Controller 卡片：选模型/模式/预设 → 启动/停止
- 状态实时回写（未运行/启动中/运行中/停止中/错误 + PID + 最近日志）
- 启动前端口占用探测：端口已有服务时明确报错，绝不覆盖
- 就绪轮询（`GET /health`，90s 超时），就绪后自动把 `contextWindow` 同步到 DSH provider
- 停止时按进程树终止（Windows `taskkill /T`）；DSH 退出自动清理子进程
- 不会自动切换 DSH 的默认模型

## 工作原理

```
设置卡片 (Client) ──settingsScope 写 action/model/mode/preset──▶ Host
   Host: 探测端口 → spawn llama-server.exe（llamaDir/port/apiKey 可配置）
        → 轮询 /health → ready → 同步 contextWindow 到 llm-pi-ai.providers
        → 停止 → 进程树 terminate
   状态经 settings/updated 事件回写卡片（status/pid/lastError/logTail）
```

插件自身**零私有 RPC**：状态与动作全部走 settings 命名空间（`local-llm`）。

## 前置条件

| 项 | 要求 |
|---|---|
| DSH | ≥ 0.1.0-rc.7，含 web profile |
| llama.cpp | `llama-server` 可执行文件，来自上游项目 [llama.cpp](https://github.com/ggml-org/llama.cpp)（作者验证：0.1.2-dev build 10488，CUDA 13.3 构建；CPU 构建亦可运行 9B，见下文 `server.ngl`） |
| 模型文件 | 两个 GGUF + 两个 mmproj（路径可自定义，见配置） |
| 硬件 | 作者环境 RTX 4070 SUPER 12GB + 32GB 内存（i5-13600KF）验证通过；128K 长上下文需要充足内存（KV 缓存已量化 q8_0） |
| 网络工具 | `curl`（健康检查用，Windows 自带，Linux 需安装） |

模型文件（文件名与目录均可自行决定，改配置即可）：

| 文件 | 说明 | 体积参考 |
|---|---|---|
| `Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf` | 35B MoE 4bit | ~20GB |
| `mmproj-Qwen3.6-35B-A3B-Uncensored-f16.gguf` | 35B 视觉投影 | ~1.5GB |
| `Qwen3.5-9B-Uncensored-Q4_K_M.gguf` | 9B dense 4bit | ~6GB |
| `mmproj-Qwen3.5-9B-Uncensored-BF16.gguf` | 9B 视觉投影 | ~700MB |

> 任意 GGUF + 对应 mmproj 均可，只要在 `local-llm.config.models` 里把路径指对。

## 安装

1. 获取插件：`git clone <本仓库>` 或直接复制本目录到任意位置。

2. 加入 DSH profile（`dsh plugin` 会把参数转发给 profile 目录下的 pnpm）：

   ```bash
   # 假设仓库在 D:/dsh-local-llm-controller
   dsh plugin --profile web add D:/dsh-local-llm-controller
   ```

   等价的手工做法：在 `~/.dsh/profiles/web/package.json` 的 `dependencies` 加
   `"dsh-local-llm-controller": "link:D:/dsh-local-llm-controller"`，然后在
   `~/.dsh/profiles/web` 下执行 `pnpm install`。

3. 在 `~/.dsh/profiles/web/cordis.patch.yml` 追加注册行：

   ```yaml
   - insert:
       - id: local-llm-controller
         name: 'dsh-local-llm-controller'
   ```

4. 按下一节配置 `~/.dsh/settings.yaml`。

5. 重启 DSH Web。

## 配置（安装时必读）

所有配置都写在 `~/.dsh/settings.yaml`，**修改后需重启 DSH 生效**（settings 在启动时装载）。

### 1) `local-llm.config` —— 插件自身配置

| 字段 | 默认值 | 说明 |
|---|---|---|
| `llamaDir` | `F:/llama-b10488-bin-win-cuda-13.3-x64` | llama.cpp 可执行文件所在目录（**必须改成你自己的**） |
| `serverExe` | `llama-server.exe` | 可执行文件名；Linux/macOS 用 `llama-server` |
| `port` | `21113` | 服务端口；必须与 provider 的 `baseURL` 一致 |
| `apiKey` | `ffsz1122` | `--api-key`；**必须与 DSH 的 `apiKeyEnv` 指向的环境变量值一致**（见 2） |
| `settingsNs` | `llm-pi-ai` | contextWindow 同步目标 settings namespace |
| `curlPath` | 自动探测 | 手动指定 curl 可执行文件（一般不填） |
| `server.ngl` | `99` | GPU 卸载层数；CPU-only 构建请设 `0` |
| `server.threads` / `server.batchThreads` | `20` / `20` | 线程数，按你的 CPU 调整 |
| `server.parallel` | `1` | 并发槽位 |
| `models.35b.file` / `mmproj` | 见下表 | 35B GGUF / mmproj 路径 |
| `models.35b.alias` | `qwen3.6-35b-a3b` | 服务别名（llama-server `-a`） |
| `models.35b.providerKey` | `qwen36-local` | DSH provider key（contextWindow 同步目标） |
| `models.9b.file` / `mmproj` / `alias` / `providerKey` | 见下表 | 9B 对应项 |

默认模型路径（基于 `llamaDir`，若你的目录结构不同，在 `models.*` 里覆盖）：

| key | 默认 file | 默认 mmproj |
|---|---|---|
| `35b` | `{llamaDir}/qwen3.6-35B-A3B/Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf` | `{llamaDir}/qwen3.6-35B-A3B/mmproj-Qwen3.6-35B-A3B-Uncensored-f16.gguf` |
| `9b` | `{llamaDir}/qwen3.5-9B/Qwen3.5-9B-Uncensored-Q4_K_M.gguf` | `{llamaDir}/qwen3.5-9B/mmproj-Qwen3.5-9B-Uncensored-BF16.gguf` |

配置示例（`{llamaDir}` 占位符在 `file`/`mmproj` 里可用，会被替换为 `llamaDir`）：

```yaml
local-llm:
  model: 35b          # 上次选择的模型，卡片会回读
  mode: text
  preset: fast
  status: stopped     # 以下为运行时状态，插件自动维护，不用手写
  action: null
  pid: null
  lastError: null
  logTail: ""
  config:
    llamaDir: 'F:/llama-b10488-bin-win-cuda-13.3-x64'
    port: 21113
    apiKey: 'ffsz1122'      # 与 DSH_LOCAL_LLM_KEY 一致
    server:
      ngl: 99
      threads: 20
    models:
      35b:
        # file / mmproj 缺省即 {llamaDir}/qwen3.6-35B-A3B/...，可只覆盖需要的
        alias: qwen3.6-35b-a3b
        providerKey: qwen36-local
      9b:
        file: 'F:/models/Qwen3.5-9B-Uncensored-Q4_K_M.gguf'
        mmproj: 'F:/models/mmproj-Qwen3.5-9B-Uncensored-BF16.gguf'
        alias: qwen3.5-9b
        providerKey: qwen-local
```

### 2) DSH provider —— 会话模型接入

在 `llm-pi-ai.providers` 下注册两个 OpenAI 兼容 provider（名字与 `models.*.providerKey` 对应）：

```yaml
llm-pi-ai:
  providers:
    qwen-local:                     # 9B
      displayName: Qwen3.5-9B test
      api: openai-completions
      baseURL: http://127.0.0.1:21113/v1
      apiKeyEnv: DSH_LOCAL_LLM_KEY
      defaultInput: [ text, image ]
      reasoning: high
      models:
        - id: qwen3.5-9b
          name: Qwen3.5-9B Uncensored
          contextWindow: 32768      # 插件就绪后自动同步，此处只是初始值
          maxTokens: 8192
          reasoningEfforts:
            off: none
            high: high
    qwen36-local:                   # 35B
      displayName: Qwen3.6-35B-A3B Local
      api: openai-completions
      baseURL: http://127.0.0.1:21113/v1
      apiKeyEnv: DSH_LOCAL_LLM_KEY
      defaultInput: [ text, image ]
      reasoning: high
      models:
        - id: qwen3.6-35b-a3b
          name: Qwen3.6-35B-A3B Uncensored
          contextWindow: 32768
          maxTokens: 12288          # 必须 > 35B 的 --reasoning-budget 2048 + 期望答案长度
          reasoningEfforts:
            off: none
            high: high
```

要点：

- `apiKeyEnv` 指向的环境变量值 **必须与 `local-llm.config.apiKey` 相同**（同一把钥匙）。
- `contextWindow` 由插件在每次就绪时自动同步为当前预设的上下文长度，不需要手工维护。
- 两个 provider 可共用同一个 `baseURL`/端口，靠 `-a` 别名区分当前加载的模型。

### 3) 环境变量

| 变量 | 值 |
|---|---|
| `DSH_LOCAL_LLM_KEY` | 与 `local-llm.config.apiKey` 相同（如 `ffsz1122`） |

## 使用

1. 打开 DSH Web → 设置 → 插件 → **Local LLM Controller** 卡片。
2. 选模型（35B / 9B）、模式（文本 / 视觉）、预设（快速 / 长上下文）。
3. 点「启动」：状态依次为 启动中… → 运行中（PID xxxx）；首次加载 40~90s 属正常。
4. 在会话中选择对应 provider/model（如 `qwen36-local / qwen3.6-35b-a3b`）即可对话。
5. 点「停止」释放端口；错误状态会显示原因和最近日志。

## 预设矩阵（n_ctx 与关键参数）

| 模型 | 快速 | 长上下文 | 备注 |
|---|---|---|---|
| 35B 文本 | 32768 · ncmoe 20 | 131072 · ncmoe 22 | `-fa on`，temp 1.0 / top-k 20，`--reasoning-budget 2048` |
| 35B 视觉 | 32768 · ncmoe 24 | 98304 · ncmoe 24 | 追加 mmproj + `--image-min-tokens 1024` |
| 9B 文本 | 32768 | 65536 | `-fa auto`，temp 0.8 / top-k 40 / min-p 0.05 |
| 9B 视觉 | 32768 | 65536 | 追加 mmproj(BF16) |

公共参数：`-ngl 99 -t 20 -tb 20 -np 1 --cache-type-k/v q8_0 --metrics --slots`（前四项可在 `config.server` 调整）。

## 实测数据与结论（35B，llama.cpp b10488）

> 来源：作者在 RTX 4070 SUPER 12GB（12282 MiB）+ 32GB 内存 + i5-13600KF（6P+8E，20 线程）上的完整扫描实验
> （`llama.cpp b10488`，CUDA 13.3 构建）。数据为干净环境复测结果。以下全部为 **35B 实测**；9B 未做专项扫描。
> 完整报告、原始数据与全部测试脚本（脱敏版，路径以 `{llama-home}` / `{work-dir}` / `{dsh-home}` 占位）见
> [docs/measurements/](docs/measurements/)。

### 上下文 vs 速度（ncmoe 20，纯文本）

| 上下文 C | 空闲 shared (MiB) | short t/s | deep t/s（填充深度） |
|---|---|---|---|
| 40960 | 142 | 66.2 | 64.1（30.8k） |
| 49152 | 147~151 | 69.3 / 81.0 | 72.7 / 74.3（39.5k） |
| 57344 | 151~159 | 71.1 / 82.8 | 69.9 / 70.7（43.9k） |
| 65536 | 159~180 | 79.0 / 84.0 | 69.3 / 69.8（52.7k） |
| 81920 | **303** | 83.5 | 63.5（70.3k） |

**结论**：57344~65536 仅掉速 ~4-6%；81920 起 KV 缓冲溢出共享内存（shared 跳升至 303MB），不再建议。`shared 空闲值 = KV 溢出的最可靠物理信号`。

### 视觉编码器（mmproj f16 858MB，-c 32768）

| 配置 | 空闲 ded/shared (MiB) | 小图编码 | 大图编码 | 文本 deep t/s | 结论 |
|---|---|---|---|---|---|
| ncmoe 20 @32K | 11801~11847 / **703~1072** | 8.7~10.7s | 73~81.5s | 66~67.8 | mmproj 落共享内存，不可用 |
| ncmoe 22 @32K | 11531~11633 / 147~148 | 2.7s | 18.6~23.2s | 60.7~61.2 | 可用，编码时 shared 涨 |
| **ncmoe 24 @32K** | 10661~10733 / 132~149 | **2.9s** | **11.8~11.9s** | 61.9~62.6 | **最优**：无溢出 |
| **ncmoe 24 @96K** | 11455 / 198 | — | **15.2s** | 49.5 | **综合最优**：3× 上下文 |
| ncmoe 24 @128K | 11794 / 308 | — | 48.9s | 39.1 | 显存紧，编码退化 |

**结论**：视觉分水岭是 **ncmoe 24**（mmproj 858MB + 编码期缓冲需 ~1.6GB 显存余量，只有 N=24 满足）；图片 token 开销：小图 ≈1024、大图（4.2MB 照片）≈3032。这就是预设矩阵里 35B 视觉档位取 24 的依据。

### 机制与结论

1. **KV 溢出机制**：KV 缓冲启动时按层分配；权重 + KV 超过 12GB 时部分 KV 层落共享内存，生成时每步跨 PCIe 读 KV → 速度骤降（ncmoe<20 时 25 t/s、196608 时 19.6 t/s）。
2. **ncmoe 机制**：`-ncmoe N` = 前 N 层专家放 CPU，其余 GPU。N 越大腾出显存越多（每 2 层 ~0.9GB），同填充速度略降 ~3-5%。ncmoe 22 可开 131072（腾 ~955MB 显存）；**196608 是硬断崖**。
3. **掉速曲线是模型特性**：≈74（≤40k）→ 70（53k）→ 63（70k）→ 60（88k）→ 54（119k）t/s，任何配置都躲不开；上下文配置本身只在溢出点之后才影响速度。
4. **档位选择理由**：32K 远低于任何溢出点（~70+ t/s 全程）；长上下文 128K = ncmoe 22 的可靠上限；视觉取 ncmoe 24。思考预算 2048 + maxTokens 12288 保证答案不被截断（无预算时复杂题思考 9000+ tokens、130s+、答案被截断）。

## 已知限制

- 端口被占用（`/health` 返回 ok）时报错并拒绝启动，不覆盖已有服务。
- 配置修改需重启 DSH；本插件不提供热重载。
- 插件不自动切换 DSH 默认模型（`agent-default-model` 请自行管理）。
- 只管理本机单个 llama-server 实例的生命周期，无多实例/负载均衡。
- 健康检查用 `/health`：该构建下模型加载完成前也可能返回 ok，就绪判定以 `/health` 为准。

## 常见问题

| 现象 | 排查 |
|---|---|
| 启动后立即报错/提前退出 | 看卡片日志尾部：`llamaDir`/模型路径错误、显存不足（35B 长上下文 ≥ 20GB 内存）、`serverExe` 不存在 |
| 一直「启动中…」直到超时 | 模型体积大加载慢属正常；确认 `/health` 可达、curl 可用 |
| CPU-only 机器 | `config.server.ngl: 0`；9B 可行，35B 128K 需大内存 |
| contextWindow 没有同步 | 检查 `settingsNs` 与 `models.*.providerKey` 是否与 yaml 实际键一致 |
| 停止后端口仍占用 | 有其他进程占用 21113（可用 `netstat -ano` 查） |

## License

MIT
