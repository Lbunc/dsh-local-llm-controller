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
| `Qwen3.6-35B-A3B-IQ4_NL.gguf` | 35B MoE 4bit | ~20GB |
| `mmproj-Qwen3.6-35B-A3B-f16.gguf` | 35B 视觉投影 | ~1.5GB |
| `Qwen3.5-9B-Q4_K_M.gguf` | 9B dense 4bit | ~6GB |
| `mmproj-Qwen3.5-9B-BF16.gguf` | 9B 视觉投影 | ~700MB |

> 任意 GGUF + 对应 mmproj 均可，只要在 `local-llm.config.models` 里把路径指对。

## 安装

> **关于 `dsh plugin`**：`dsh plugin --profile <名字> <参数>` 只是把参数**原样转发给 profile
> 目录下的 pnpm**（等价于在 profile 里执行 `pnpm add xxx`，装依赖）。DSH 启动时只加载
> `dsh.profile.bundles` 里声明的包 + `cordis.patch.yml` 注册的插件，**不会自动发现
> node_modules 里装了什么**——所以第三方插件永远需要两步：装依赖 + 写注册行。
> 别人的"一行命令"要么是官方 bundle 插件（已经声明在 bundles 里，只需装依赖），
> 要么是把这两步合并成一句话。本仓库的 `install.ps1` 就是把这两步 + 配置合并成一条命令。

### 方式 A：一键安装（推荐，Windows）

1. 下载/克隆本仓库，进入目录。
2. 运行安装向导（PowerShell 7 或 Windows PowerShell 5.1 均可）：

   ```powershell
   .\install.ps1
   ```

   跟着提示走，只需回答 llama.cpp 目录（其余直接回车即可）：

   ```
   == llama.cpp 目录
      llama.cpp 目录（包含 llama-server.exe 的文件夹）: F:\llama.cpp
   == 服务端口 [回车 = 67913]
   == API 密钥 [回车 = 无鉴权（仅本机回环，推荐）]
   ```

   脚本会自动完成：把插件本体复制到 `~/.dsh/profiles/<名字>/plugins/`（与 git 仓库解耦）
   → 在 profile package.json 注册依赖 `link:./plugins/dsh-local-llm-controller`（相对路径，
   profile 整体搬迁不断链）→ 刷新 node_modules → 追加 `cordis.patch.yml` 注册行（幂等）
   → 写入配置 `~/.dsh/local-llm.config.json` → 检查 llama-server.exe 与默认模型文件。
   重复运行会询问是否用仓库版本覆盖已安装的本体（`-Force` 直接覆盖）。

   非交互模式（适合脚本化）：

   ```powershell
   .\install.ps1 -LlamaDir F:\llama.cpp
   ```

3. **重启 DSH Web**，打开 设置 → 插件 → Local LLM Controller 即可使用。

> 插件启动时会**自动补建** `llm-pi-ai.providers.qwen36-local / qwen35-local` 两个 provider
> （缺失才建，已有配置不动），所以你不必手写 provider 配置。

### 方式 B：手动安装

1. 获取插件：`git clone <本仓库>` 或直接复制本目录到任意位置。

2. 把插件本体复制到 profile 内（以 `web` profile 为例）：

   ```powershell
   $dst = "$HOME\.dsh\profiles\web\plugins\dsh-local-llm-controller"
   New-Item -ItemType Directory -Force -Path $dst | Out-Null
   Copy-Item .\lib $dst\lib -Recurse -Force
   Copy-Item .\package.json, .\README.md, .\LICENSE $dst\ -Force
   ```

3. 在 `~/.dsh/profiles/web/package.json` 的 `dependencies` 加（相对路径）：

   ```json
   "dsh-local-llm-controller": "link:./plugins/dsh-local-llm-controller"
   ```

   然后在 profile 目录下刷新依赖：

   ```bash
   cd ~/.dsh/profiles/web && pnpm install   # 或 dsh plugin --profile web install
   ```

4. 在 `~/.dsh/profiles/web/cordis.patch.yml` 追加注册行：

   ```yaml
   - insert:
       - id: local-llm-controller
         name: 'dsh-local-llm-controller'
   ```

5. 重启 DSH Web（provider 由插件自动补建，无需手写；如需自定义见下节）。

## 配置

**推荐方式：插件卡片内配置**（设置 → 插件 → Local LLM Controller → 展开「配置」区），
llama.cpp 目录、端口、密钥、两个模型文件夹都是表单，保存后下次启动生效，不用碰任何文件。

配置按优先级合并（后者覆盖前者），修改后**下次启动生效**：

1. 卡片「配置」表单 / `settings.yaml` 的 `local-llm.config` 段（同一处，卡片就是写这里）
2. `~/.dsh/local-llm.config.json` —— install.ps1 写入（`{llamaDir}` 占位符在 `dir` 里可用）

### 1) 配置字段

| 字段 | 默认值 | 说明 |
|---|---|---|
| `llamaDir` | `F:/llama-b10488-bin-win-cuda-13.3-x64` | llama.cpp 可执行文件所在目录（**必须改成你自己的**） |
| `serverExe` | `llama-server.exe` | 可执行文件名；Linux/macOS 用 `llama-server` |
| `port` | `67913` | 服务端口；必须与 provider 的 `baseURL` 一致 |
| `apiKey` | 空（无鉴权） | 留空 = 不设 `--api-key`，仅监听 127.0.0.1 回环；设置后须与 `DSH_LOCAL_LLM_KEY` 一致 |
| `settingsNs` | `llm-pi-ai` | contextWindow 同步目标 settings namespace |
| `curlPath` | 自动探测 | 手动指定 curl 可执行文件（一般不填） |
| `server.ngl` | `99` | GPU 卸载层数；CPU-only 构建请设 `0` |
| `server.threads` / `server.batchThreads` | `20` / `20` | 线程数，按你的 CPU 调整 |
| `server.parallel` | `1` | 并发槽位 |
| `models.35b.dir` | `{llamaDir}/qwen3.6-35B-A3B` | 35B 模型文件夹（内含模型 GGUF + mmproj） |
| `models.35b.alias` | `qwen3.6-35b-a3b` | 服务别名（llama-server `-a`） |
| `models.35b.providerKey` | `qwen36-local` | DSH provider key（contextWindow 同步目标） |
| `models.9b.dir` / `alias` / `providerKey` | `{llamaDir}/qwen3.5-9B` / `qwen3.5-9b` / `qwen35-local` | 9B 对应项 |

**模型文件夹约定**：插件启动时在文件夹内自动识别——文件名含 `mmproj` 的 `.gguf` 是视觉投影，
其余 `.gguf` 是模型本体（量化标签、"Uncensored" 后缀等都不影响）。文件夹不存在或没有
`.gguf` 时会明确报错。

配置示例：

```yaml
local-llm:
  config:
    llamaDir: 'F:/llama-b10488-bin-win-cuda-13.3-x64'
    port: 67913
    apiKey: ''              # 留空=无鉴权；设置后与 DSH_LOCAL_LLM_KEY 一致
    server:
      ngl: 99
      threads: 20
    models:
      35b:
        dir: '{llamaDir}/qwen3.6-35B-A3B'   # 缺省即此值，可不写
        alias: qwen3.6-35b-a3b
        providerKey: qwen36-local
      9b:
        dir: 'F:/models/qwen3.5-9B'          # 自定义目录示例
        alias: qwen3.5-9b
        providerKey: qwen35-local
```

### 2) DSH provider —— 会话模型接入（自动，无需手写）

插件启动时会检查 `llm-pi-ai.providers`，缺失的 `qwen36-local` / `qwen35-local` **自动补建**
（只补缺失项，不覆盖你已有的配置），所以正常使用**不需要写这一段**。下面是补建结果的参考
结构，想自定义（如改 displayName、maxTokens）时按此格式手工改即可：

```yaml
llm-pi-ai:
  providers:
    qwen35-local:                     # 9B
      displayName: Qwen3.5-9B Local
      api: openai-completions
      baseURL: http://127.0.0.1:67913/v1
      defaultInput: [ text, image ] # 设置了 apiKey 时才有 apiKeyEnv: DSH_LOCAL_LLM_KEY
      reasoning: high
      models:
        - id: qwen3.5-9b
          name: Qwen3.5-9B
          contextWindow: 32768      # 插件就绪后自动同步，此处只是初始值
          maxTokens: 8192
          reasoningEfforts:
            off: none
            high: high
    qwen36-local:                   # 35B
      displayName: Qwen3.6-35B-A3B Local
      api: openai-completions
      baseURL: http://127.0.0.1:67913/v1
      defaultInput: [ text, image ]
      reasoning: high
      models:
        - id: qwen3.6-35b-a3b
          name: Qwen3.6-35B-A3B
          contextWindow: 32768
          maxTokens: 12288          # 必须 > 35B 的 --reasoning-budget 2048 + 期望答案长度
          reasoningEfforts:
            off: none
            high: high
```

要点：

- **默认无鉴权**：`config.apiKey` 留空时，补建的 provider 不带 `apiKeyEnv`，请求不带
  Authorization 头；llama-server 也只监听 `127.0.0.1` 且不设 `--api-key`。本机回环场景足够安全。
- **设置了 `apiKey` 时**：插件会给补建的 provider 加上 `apiKeyEnv: DSH_LOCAL_LLM_KEY`，此时
  环境变量 `DSH_LOCAL_LLM_KEY` 的值必须与 `config.apiKey` 相同（同一把钥匙）。
- `contextWindow` 由插件在每次就绪时自动同步为当前预设的上下文长度，不需要手工维护。
- 两个 provider 可共用同一个 `baseURL`/端口，靠 `-a` 别名区分当前加载的模型。

### 3) 环境变量

| 变量 | 何时需要 | 值 |
|---|---|---|
| `DSH_LOCAL_LLM_KEY` | 仅当配置了 `apiKey` 时 | 与 `local-llm.config.apiKey` 相同 |

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

> 环境：RTX 4070 SUPER 12GB + 32GB 内存 + i5-13600KF（20 线程），CUDA 13.3 构建，干净环境复测。
> 以下为 **35B 实测**（9B 未做专项扫描）；完整报告、原始数据与测试脚本（脱敏版）见
> [docs/measurements/](docs/measurements/)。

| 配置 | 空闲 shared (MiB) | 大图编码 | 深填充 t/s | 结论 |
|---|---|---|---|---|
| ncmoe 20 @ 32K | ~150 | — | ~70 | 基准：远低于溢出点，全程不掉速 |
| ncmoe 20 @ 64K | 159~180 | — | ~70（52.7k） | 仍可用，仅掉速 ~4-6% |
| ncmoe 20 @ 80K | **303** | — | 63.5（70.3k） | KV 开始溢出共享内存，不再建议 |
| ncmoe 22 @ 128K | 227~260 | — | 45~54（118.6k） | 长上下文档：ncmoe 22 的可靠上限（196608 是硬断崖，19.6 t/s） |
| ncmoe 24 @ 32K 视觉 | 132~149 | **11.8s** | 62 | 视觉最优：mmproj 完整进 GPU，无溢出 |
| ncmoe 24 @ 96K 视觉 | 198 | **15.2s** | 49.5 | 综合最优：3× 上下文 + 可用图片速度 |
| ncmoe 24 @ 128K 视觉 | 308 | 48.9s | 39.1 | 显存紧，图片编码退化 |

**结论**：KV 缓冲启动时按层分配，权重 + KV 超过 12GB 时部分 KV 层落共享内存，生成时每步跨 PCIe 读 KV 导致速度骤降——`空闲 shared 值 = 溢出的最可靠信号`，这也是预设矩阵档位（32K 稳妥 / 128K=ncmoe 22 上限 / 视觉必须 ncmoe 24）的选定依据；掉速曲线（74→70→63→60→54 t/s @40k→53k→70k→88k→119k 填充）是模型特性，任何配置都躲不开，上下文配置只在溢出点之后才影响速度。

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
| 停止后端口仍占用 | 有其他进程占用 67913（可用 `netstat -ano` 查） |

## License

MIT
