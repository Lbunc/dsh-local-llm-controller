<div align="center">

# dsh-local-llm-controller

<img src="images/wallpaper.jpg" alt="dsh-local-llm-controller" width="100%">

**DSH 插件：在设置页一键启停本地 llama.cpp 服务，使本地大模型成为 DSH 会话模型**

配置卡片位于 设置 → 插件 → 本地大模型控制器

[English](README.en.md) | **简体中文**

[![npm version](https://img.shields.io/npm/v/dsh-local-llm-controller?color=blue)](https://www.npmjs.com/package/dsh-local-llm-controller)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/Lbunc/dsh-local-llm-controller/blob/main/LICENSE)
[![llama.cpp](https://img.shields.io/badge/llama.cpp-upstream-8B5CF6)](https://github.com/ggml-org/llama.cpp)
[![DSH 0.1.7-rc.2](images/badge-dsh.svg)](https://www.npmjs.com/package/@deepseek-ai/dsh)
[![Type: DSH Plugin](https://img.shields.io/badge/Type-DSH%20Plugin-8A2BE2.svg)](https://github.com/topics/dsh-plugin)

</div>

***

> **兼容性说明**：DSH 0.1.7-rc.1 进行了大规模底层重构，本插件自 v2.1.0 起适配该架构（仅适配 RC 分支，其余分支不作保证）。

## 特性

- **一键启停本地服务**：在设置 → 插件卡片上启动或停止 llama-server，状态、错误原因与最近日志同卡显示；DSH 重启时插件自动清理子进程。
- **双槽位模型管理**：槽位 A / B 各绑定一个模型文件夹，自动扫描其中全部 GGUF 生成候选列表；视觉投影器（mmproj）自动识别，视觉模式自动挂载。
- **八组启动参数**：按槽位 × 文本/视觉 × 快速/长上下文划分，参数行自由增删，基础参数预填。
- **一键接入会话**：将选中模型写入 DSH 模型页，会话底部即可选用本地模型对话。
- **本地压缩引擎**（v2.1.2）：以子路径导出形式提供 DSH 内置压缩引擎的本地替代实现，面向 32k~150k 本地窗口，详见「本地压缩引擎」。

> 本插件仅承担 DSH 与 llama.cpp 之间的连接与控制：不包含 llama-server 本体，也不负责模型下载。二者分别来自上游 [llama.cpp](https://github.com/ggml-org/llama.cpp) 与社区量化发布（如 Hugging Face）。

## 快速开始

### 安装

推荐通过 DSH 内置插件管理器安装：侧边栏 设置 → 插件 → 添加插件，输入下表任意一种地址，选择安装源后安装并启用。安装完成后无需重启 DSH Web。

也可使用命令行安装（重复执行同一命令即为升级；已是最新版本时提示 Already up to date）：

```text
dsh plugin --profile web add <地址>
```

| 地址形式 | 说明 |
| :- | :- |
| dsh-local-llm-controller | 包名，从 npm registry 安装最新发布版 |
| 本地文件夹路径 | link 活链，开发调试首选，拉取更新后重启 DSH 生效 |
| releases tgz 包路径 | 离线安装发布包 |
| GitHub 仓库地址 | 安装远程最新推送，可能不稳定 |

<p align="center"><img src="images/plugin-manager-add.png" width="420" alt="DSH 插件管理器：添加插件对话框，输入 dsh-local-llm-controller"></p>

常用命令：

```text
dsh plugin --profile web outdated                                       # 检查更新，无输出即已是最新
dsh plugin --profile web add dsh-local-llm-controller@2.1.2             # 安装指定版本
npx @deepseek-ai/dsh plugin --profile web add dsh-local-llm-controller  # 未全局安装 dsh CLI 时的等价调用
```

> [!NOTE]
> 安装或升级时出现 peer 依赖警告属正常现象：本插件的 peer 依赖由 DSH 宿主提供，不随包安装，不影响使用。

### 使用流程

1. **配置基础连接**：打开配置卡片，填写下表字段后保存配置。

   | 配置项 | 说明 |
   | :- | :- |
   | llama.cpp 目录 | llama-server 可执行文件所在文件夹，必填 |
   | 端口 | 默认 55555，添加到模型列表时写入 provider 的 baseURL |
   | 密钥 | 留空表示无鉴权（仅回环）；留空时同样写入占位鉴权头（客户端协议要求） |

   <p align="center"><img src="images/setting-plug.png" width="420" alt="设置 → 插件（配置卡片）"></p>

2. **配置槽位**：槽位 A / B 各填写一个模型文件夹路径（含模型 GGUF；视觉场景还需包含 mmproj 文件），点击保存配置。
3. **写入模型列表**：保存后文件夹内全部模型 GGUF 显示为候选气泡（mmproj 不出现在列表中，视觉模式自动挂载）。选择一个模型，保存配置，点击「添加到模型列表」。模型名由文件名自动派生，如需修改名称请前往 设置 → 模型 页操作。写入条目每次启动就绪后按当前预设组自动同步（切换快速/长上下文并重新启动即更新），取值如下：

   | 写入条目 | 取值 |
   | :- | :- |
   | contextWindow | 槽位快速参数组的 -c 值 |
   | maxTokens | 上述 -c 值的四分之一（v2.1.2 起由二分之一下调：预留过大会压低压缩阈值，见「本地压缩引擎」） |

4. **启动参数**：共八组（槽位 × 文本/视觉 × 快速/长上下文），编辑区标题显示当前组合；每行为参数与值两个输入框，支持增删行。基础参数已预填，推荐组合见「推荐启动参数」。下表参数由插件自动管理，无需手动添加：

   | 由插件管理的参数 | 适用场景 |
   | :- | :- |
   | -m / -a / --port / --host / --api-key | 全部场景（配置密钥后启用鉴权头） |
   | --mmproj / --image-min-tokens | 视觉模式 |

   <p align="center"><img src="images/params.png" width="420" alt="启动参数行（8 组之一）"></p>

5. **启动**：选择槽位（A/B）、模式（文本/视觉）、预设（快速/长上下文），点击「启动」。

   <p align="center"><img src="images/setting-model.png" width="420" alt="设置 → 模型（添加到模型列表后出现）"></p>

6. **对话**：状态转为运行中后，在会话底部选择对应本地模型；点击「停止」释放端口；出错时卡片显示原因与最近日志。

   <p align="center"><img src="images/useing.png" width="420" alt="会话中选择本地模型对话"></p>

### 注意事项

- 同一槽位更换模型文件后，Provider Key 随文件名变化：设置 → 模型 页的旧条目不会被自动覆写或删除，需手动删除后重新写入。
- 旧版 llama-server 的图片解码器不支持 WebP。本插件已将 DSH 的图片请求预算提升至 16 MiB / 4096²，常规 PNG/JPEG 截图与大图可原样直达；WebP 源文件请先转换为 PNG/JPEG 再发送。
- 视觉投影器文件须在文件名中包含 mmproj 方可被自动识别。
- 如需固定 Provider Key（更换模型文件后无需重选模型），可在 设置 → 模型 页为对应模型改名；模型页的修改不回写插件配置。

### 卸载

1. 模型运行中先在卡片点击「停止」（可选，DSH 重启时插件自动清理子进程）；若默认模型或某预设已设为本地模型，先改回云端模型再卸载，避免默认模型悬空。
2. 通过插件管理器的卸载按钮，或执行以下命令（bundle 注册与 link 依赖自动移除）：

   ```text
   dsh plugin --profile web remove dsh-local-llm-controller
   ```

3. 刷新页面，卡片消失，无需重启 DSH。

卸载命令会自动清理 profile 的 bundle 注册与依赖声明，以下内容不会被自动删除（v2.1.0 / DSH 0.1.7-rc.1 实测）：

| 残留项（可选清理） | 说明 |
| :- | :- |
| ~/.dsh/local-llm.config.json | 卡片配置（llama.cpp 目录、端口与八组启动参数）。计划重装则保留 |
| profile 补丁中的 llm-pi-ai.providers.dsh-local | 「添加到模型列表」写入的模型页条目；手动运行同端口服务时仍可用，不用则删 |
| pnpm-workspace.yaml 的版本豁免行 | 卸载不回收的安装元数据，无害 |

> [!NOTE]
> 从 v2.0.x 升级：旧版 settings.yaml 中的 local-llm 配置段已随 DSH 0.1.7 的一次性导入更名为 settings.yaml.imported，无程序读取，无需处理。

## 推荐启动参数

> 数据为 v1.x 实测基准。以下每行一套，粘贴进对应启动参数组即可，也可用于手动运行 llama-server。由插件管理的参数无需手动添加（见「使用流程」第 4 步）。

**35B（Qwen3.6-35B-A3B，MoE）**：

```text
35B · 文本 · 快速    : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 32768 -ncmoe 20 --reasoning-budget 2048 --metrics --slots
35B · 文本 · 长上下文 : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 131072 -ncmoe 22 --reasoning-budget 2048 --metrics --slots
35B · 视觉 · 快速    : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 32768 -ncmoe 24 --reasoning-budget 2048 --metrics --slots
35B · 视觉 · 长上下文 : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 98304 -ncmoe 24 --reasoning-budget 2048 --metrics --slots
```

**9B（Qwen3.5-9B，Dense）**：

```text
9B · 文本 · 快速    : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 32768 --metrics --slots
9B · 文本 · 长上下文 : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 65536 --metrics --slots
9B · 视觉 · 快速    : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 32768 --metrics --slots
9B · 视觉 · 长上下文 : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 65536 --metrics --slots
```

| 实测结论 | 说明 |
| :- | :- |
| -ncmoe（MoE 专家卸载数）与 --reasoning-budget | 35B 的两项实测优化点 |
| 长上下文可靠上限 | 35B（ncmoe 22）：131072；9B：65536 |
| 196608 | 硬性上限，KV 缓存溢出共享内存 |

更完整的实测数据、选型结论与实验方法见「推荐阅读」。

## 推荐阅读

- [本地模型调优实测存档（分模型报告）](docs/measurements/README.md)：35B / 9B / 27B / Occamy 每模型一份实测报告，含结论速览、横向能力对比、复现脚本与原始日志说明。
- [Occamy-1.0 vs Qwen3.6-35B-A3B 完整对比](docs/measurements/occamy_vs_ud_report.md)：同底座 35B MoE 的能力、速度与上下文同会话 A/B 对比，含 decode 提升 17% 对 prefill 提升 32% 的量化结论。
- [llm-experiment-design · DSH 调优 Skill](docs/llm-experiment-design/SKILL.md)：面向新 GGUF 深度调优的 Skill，按「运行时探查 → 必要性驱动扫描 → 四件套测量 → 能力验证」流程输出可复现的最优启动参数（MoE 与 Dense 通用）。

## 本地压缩引擎（v2.1.2）

本插件以子路径导出形式提供压缩引擎 LocalCompactionEngine，继承官方 CompactionEngine 基类，用于替换 DSH 内置压缩引擎。面向 32k~150k 本地上下文窗口，解决内置引擎的两类问题：触发阈值被固定预留量压低乃至静默停用；压缩后占用仍然偏高，下一轮再次触发压缩形成正反馈。

### 包名与存在形式

| 项 | 说明 |
| :- | :- |
| 引擎入口 | 子路径导出 dsh-local-llm-controller/compaction |
| 导出类 | LocalCompactionEngine，继承 @deepseek-ai/dsh-compaction 的 CompactionEngine |
| 替换对象 | @deepseek-ai/dsh-compaction-basic（DSH 内置压缩引擎） |
| 运行时注册 | 引擎注册为 ctx.compaction，手动 /compact 命令自动兼容 |
| 宿主依赖 | @deepseek-ai/dsh-* 以 >=0.1.7-rc.1 声明，由 DSH 宿主提供，DSH 升级无需修改版本号 |

### 与 DSH 默认压缩的区别

| 维度 | DSH 默认（dsh-compaction-basic） | 本引擎 |
| :- | :- | :- |
| 触发阈值 | min(0.8W, W − maxTokens − 65536)，预留量为固定常数 | min(0.7W, W − reserved − margin)，随窗口比例缩放 |
| 小窗口表现 | 32768 窗口公式为负，自动压缩静默停用；131072 窗口阈值降至 37.5%，频繁提前压缩 | 32768 窗口阈值 22937、131072 窗口阈值 91750，均约 70% |
| 二次触发 | 摘要与保留尾部之和可能高于阈值，下一轮再次压缩 | 尾部封顶构造保证压缩后占用远低于阈值，从构造上消除正反馈 |
| 摘要调用 | 固定 65536 token 预算 | 三级降级（见下），输出预算按剩余空间动态推导 |
| 工具结果修剪 | 可选 | 压缩前强制执行，修剪后占用达标即跳过 LLM 摘要 |
| 适用场景 | 百万级云端窗口 | 32k~150k 本地窗口 |

### 核心机制

| 机制 | 说明 |
| :- | :- |
| 比例阈值 | threshold = min(0.7W, W − reserved − margin)，margin = clamp(0.05W, 1024, 8192) |
| 尾部封顶 | tail ≤ min(0.16 × (W − reserved), threshold − summaryUpper − margin) |
| 摘要降级 | 本地路由模型摘要（复用 KV 前缀缓存，自动重试，默认共 2 次尝试）→ 云端摘要目标（可选）→ 截断式检查点兜底（确定性构造，不依赖模型，会话不卡死） |
| 前置修剪 | 压缩前先修剪旧工具结果，修剪后占用低于阈值则完全跳过 LLM 摘要 |
| 溢出恢复 | 请求窗口溢出时自动恢复，手动压缩路径兼容 |
| 运行日志 | 全程携带 [local-compaction] 前缀，覆盖压力检查、压缩提交、摘要降级、溢出恢复 |

### 接入方式：创建自定义 agent 模式

本引擎无法在安装后自动替换官方预设内置的压缩组：官方补丁机制的寻址范围不覆盖预设内部的插件列表。使用方式为在 DSH 中创建自定义 agent 模式（预设），并在其插件列表中声明压缩组：

```yaml
- id: compaction
  name: cordis:group
  group: true
  isolate:
    compaction: true
    toolResultPruner: true
  config:
    - id: local-compaction
      name: 'dsh-local-llm-controller/compaction'
    - id: command-compact
      name: '@deepseek-ai/dsh-command-compact'
    - id: tool-result-pruner
      name: '@deepseek-ai/dsh-compaction-tool-result-pruner'
      config:
        thresholdChars: 4096
        headChars: 2048
        tailChars: 512
```

> isolate 字段必须保留：引擎通过 ctx.get 读取工具结果修剪器，两者需处于同一 isolate realm。

预设可通过用户层补丁文件声明（以 link 依赖注册进 profile 并列入 dsh.profile.bundles），也可通过 Web 设置编辑器创建。回落与停用：将压缩子行的 name 改回 @deepseek-ai/dsh-compaction-basic 即恢复官方引擎；修改后需重启 DSH 生效（bundle 补丁文件不参与热重载）。

引擎子行的可选配置：

| 配置键 | 说明 |
| :- | :- |
| thresholdRatio / retainRatio / summaryReserveTokens | 阈值与预留相关参数 |
| summarizationProvider / summarizationModel | 成对配置的云端摘要目标 |
| compactionRetries / maxOverflowRetries | 压缩与溢出恢复的重试次数 |
| auto | 自动压缩开关 |

### 实测验证

| 预设档 | 窗口 | 行为 |
| :- | :- | :- |
| fast | 32768 | 受控实测：占用 13116 tokens 压缩至 7103，此后稳定运行，无二次触发 |
| long | 131072 | 真实会话：93313、91924、93973 三次越线均由工具结果修剪单独化解（最低降至 69189），未调用 LLM 摘要；93290 再次越线后触发压缩，本地模型摘要约 1817 tokens，占用降至 44479，此后低位稳定运行 |

单元测试 21/21 通过（npm test）。

## 许可

<div align="center">

[MIT](LICENSE)

</div>
