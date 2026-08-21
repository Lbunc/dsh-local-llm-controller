# dsh-local-llm-controller

在 DSH（DeepSeek Harness）的「设置 → 插件」页面一键启停本地 [llama.cpp](https://github.com/ggml-org/llama.cpp) `llama-server`，把本地大模型直接接入 DSH 作为会话模型。

| 模型 | 文本 / 快速 | 文本 / 长上下文 | 视觉 / 快速 | 视觉 / 长上下文 |
|---|---|---|---|---|
| Qwen3.6-35B-A3B（IQ4_NL） | 32K | 128K | 32K + mmproj | 96K + mmproj |
| Qwen3.5-9B（Q4_K_M） | 32K | 64K | 32K + mmproj | 64K + mmproj |

**安装后：** 插件卡着里填好 llama.cpp 目录与端口 → 选模型/模式/预设 → 点「启动」→ 会话顶部选本地模型即可对话；点「停止」释放端口。状态（运行中/错误/PID/日志）实时显示在卡片上。

| 设置 → 插件（卡片与配置表单） | 设置 → 模型（自动注册的本地提供方） |
|---|---|
| ![设置 → 插件](setting-plug.png) | ![设置 → 模型](setting-model.png) |

| 会话模型选择器（本地模型可选） |
|---|
| ![会话模型选择器](useing.png) |

这个插件只负责 DSH 与 llama.cpp 之间的连接和控制，**不包含** llama-server 本体、**不负责**下载模型——那两样分别来自上游 [llama.cpp](https://github.com/ggml-org/llama.cpp) 和社区量化发布（如 Hugging Face）。

---

## 环境需求

| 项 | 要求 |
|---|---|
| DSH | ≥ 0.1.0-rc.7，含 web profile |
| llama.cpp | `llama-server` 可执行文件（作者验证：0.1.2-dev build 10488，CUDA 13.3 构建；CPU 构建也能跑 9B，配置里把 `ngl` 设为 0） |
| 模型文件 | 两个 GGUF + 两个 mmproj（文件名/目录随意，路径在卡片里配） |
| 硬件 | 作者环境 RTX 4070 SUPER 12GB + 32GB 内存（i5-13600KF）验证通过；128K 长上下文需要充足内存 |
| 系统 | Windows 为主（Linux/macOS 改一下 `serverExe` 为 `llama-server` 即可） |

推荐模型文件（体积参考）：

| 文件 | 用途 | 体积 |
|---|---|---|
| Qwen3.6-35B-A3B（IQ4_NL GGUF） | 35B 主模型 | ~20GB |
| mmproj（Qwen3.6-35B-A3B） | 35B 视觉投影 | ~1.5GB |
| Qwen3.5-9B（Q4_K_M GGUF） | 9B 主模型 | ~6GB |
| mmproj（Qwen3.5-9B） | 9B 视觉投影 | ~700MB |

---

## 安装

### 方式一：一条命令（推荐）

打开终端，执行：

```bash
dsh plugin --profile web add dsh-local-llm-controller
```

如果你的电脑上 `dsh` 不在环境变量里（比如你平时是用 `pnpm dlx` 临时运行 DSH 的），用这行等价命令：

```bash
pnpm dlx @deepseek-ai/dsh plugin --profile web add dsh-local-llm-controller
```

装完**重启 DSH Web** 即可——本包声明了 `dsh.bundle`，安装时 DSH 会自动完成注册（放进 bundles，无需手动添加任何配置行）。

### 方式二：手动安装（不装联网包时）

跟着做，每一步都说明白了：

1. 把**整个插件文件夹**下载或复制到电脑上（例如 `D:\dsh-local-llm-controller`）。
2. 打开 DSH 的 profile 文件夹。Windows 默认路径是 `C:\Users\你的用户名\.dsh\profiles\web`，在里面**新建**一个 `plugins` 文件夹。
3. 把整个插件文件夹复制进 `plugins`，得到 `...\profiles\web\plugins\dsh-local-llm-controller`（里面要有 `lib`、`package.json` 这些文件）。
4. 用记事本打开 profile 文件夹里的 `package.json`，在 `"dependencies": { ... }` 的花括号里加一行（注意如果上一行末尾没有逗号，请给上一行补一个逗号）：

   ```json
   "dsh-local-llm-controller": "link:./plugins/dsh-local-llm-controller"
   ```

5. 打开 PowerShell，输入下面两行（让 DSH 认识这个插件）：

   ```powershell
   cd $env:USERPROFILE\.dsh\profiles\web
   pnpm install
   ```

6. 用记事本打开同目录里的 `cordis.patch.yml`，在文件最末尾加三行（意思是"让 DSH 加载这个插件"）：

   ```yaml
   - insert:
       - id: local-llm-controller
         name: 'dsh-local-llm-controller'
   ```

   如果你用的是方式一（npm 一条命令），**不需要**做这一步——注册已经自动完成了。

7. 重启 DSH Web。

### 第一次使用（全部在卡片里配置，不用碰任何文件）

1. 打开 设置 → 插件 → **Local LLM Controller**，展开卡片。
2. 在「配置」区填好：

   | 表单项 | 说明 |
   |---|---|
   | llama.cpp 目录 | `llama-server.exe` 所在的文件夹，必填 |
   | 端口 | 默认 67913；如果 DSH 的 provider 配置过端口，用同一个 |
   | 密钥 | 留空 = 无鉴权（只监听本机 127.0.0.1）；需要密钥时填写并保证与 `DSH_LOCAL_LLM_KEY` 一致 |
   | 35B 文件夹 / 9B 文件夹 | 各模型所在的文件夹；默认是 `llama.cpp 目录\qwen3.6-35B-A3B` 和 `llama.cpp 目录\qwen3.5-9B` |

   > 插件会在文件夹里自动识别：文件名含 `mmproj` 的是视觉投影，其余一个是主模型——文件名、量化后缀都不影响。

3. 点「保存配置」→ 选模型（35B/9B）、模式（文本/视觉）、预设（快速/长上下文）→ 点「启动」。首次加载等 40~90 秒属正常。
4. 状态变「运行中」后，在会话里选 **Qwen3.5-9B Local** 或 **Qwen3.6-35B-A3B Local** 即可对话。
5. 点「停止」释放端口；出错时卡片会显示原因和最近日志。

> 更多高级参数（`ngl`、线程数、模型别名、provider 自定义等）仍支持通过 `settings.yaml` 的 `local-llm.config` 段配，字段表见 `docs/` 或源码注释。

---

## 测试环境

作者实测环境（数据均来自此配置）：

| 项 | 值 |
|---|---|
| GPU | RTX 4070 SUPER 12GB（12282 MiB） |
| CPU | i5-13600KF（6P + 8E，20 线程） |
| 内存 | 32GB |
| llama.cpp | 0.1.2-dev（build 10488），CUDA 13.3 构建 |
| DSH | 0.1.0-rc.7（web profile） |
| 模型 | Qwen3.6-35B-A3B（IQ4_NL，18.4GB）+ f16 mmproj；Qwen3.5-9B（Q4_K_M）+ BF16 mmproj |
| 方法 | 干净环境复测：`/health` + `/props`（鉴权）确认就绪，`/completion` 深填充测速，nvidia-smi 采样显存与 GPU 利用率 |

---

## 简要数据与结论（35B 实测）

| 配置 | 空闲 shared (MiB) | 大图编码 | 深填充速度 | 结论 |
|---|---|---|---|---|
| ncmoe 20 @ 32K | ~150 | — | ~70 t/s | 基准：远离溢出点，全程不掉速 |
| ncmoe 20 @ 80K | **303** | — | 63.5 t/s | KV 开始溢出共享内存，不再建议 |
| ncmoe 22 @ 128K | 227~260 | — | 45~54 t/s | 长上下文档：ncmoe 22 的可靠上限（196608 是硬断崖） |
| **ncmoe 24 @ 32K 视觉** | 132~149 | **11.8s** | 62 t/s | 视觉最优：mmproj 完整进 GPU |
| **ncmoe 24 @ 96K 视觉** | 198 | **15.2s** | 49.5 t/s | 综合最优：3× 上下文 + 可用图片速度 |

**结论**：KV 缓冲按层分配，权重 + KV 超 12GB 时部分 KV 层落共享内存，生成时每步跨 PCIe 读 KV → 速度骤降，**空闲 shared 值是最可靠的溢出信号**。因此档位取舍为：文本 32K 稳妥 / 长上下文 128K = ncmoe 22 上限 / 视觉必须 ncmoe 24。掉速曲线（74→70→63→60→54 t/s，随填充 40k→53k→70k→88k→119k 增长）是模型特性，任何配置都躲不开。完整报告、原始数据与测试脚本（脱敏版）见 [docs/measurements/](docs/measurements/)。

---

## License

MIT
