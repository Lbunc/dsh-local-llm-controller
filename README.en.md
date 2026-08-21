<div align="center">

# 🚀 dsh-local-llm-controller

**A DSH plugin: start & stop a local llama.cpp server from the settings page, so any local LLM can serve as a DSH session model**

[![npm version](https://img.shields.io/npm/v/dsh-local-llm-controller?color=blue)](https://www.npmjs.com/package/dsh-local-llm-controller)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/Lbunc/dsh-local-llm-controller/blob/main/LICENSE)
[![llama.cpp](https://img.shields.io/badge/llama.cpp-upstream-8B5CF6)](https://github.com/ggml-org/llama.cpp)

**English** | [简体中文](README.md)

</div>

---

## ✨ Overview

Start and stop a local [llama.cpp](https://github.com/ggml-org/llama.cpp) `llama-server` right from the **Settings → Plugins** page of DSH (DeepSeek Harness), wiring any local model in as a DSH session model.

<details>
<summary><b>Supported matrix (2 models × 2 modes × 2 presets)</b></summary>

| Model | Text / Fast | Text / Long | Vision / Fast | Vision / Long |
| --- | --- | --- | --- | --- |
| **Qwen3.6-35B-A3B** (IQ4_NL) | 32K | 128K | 32K + mmproj | 96K + mmproj |
| **Qwen3.5-9B** (Q4_K_M) | 32K | 64K | 32K + mmproj | 64K + mmproj |

</details>

**Getting started in three steps**: fill in the `llama.cpp` directory and port on the card → pick model / mode / preset → hit **Start**. Pick a local model in the session selector to chat; **Stop** releases the port. Status (running / error / PID / log) is shown live on the card.

> 🌐 The card UI follows the DSH Web language setting (English / 简体中文) — no extra config needed.

| ① Settings → Plugins (config card) | ② Settings → Models (auto-registered) |
| :---: | :---: |
| <img src="setting-plug.png" width="380" alt="Settings → Plugins"> | <img src="setting-model.png" width="380" alt="Settings → Models"> |

| ③ Session model selector |
| :---: |
| <img src="useing.png" width="220" alt="Session model selector"> |

> 🧩 This plugin only handles the **DSH ↔ llama.cpp connection & control**. It ships neither `llama-server` nor model files — those come from upstream [llama.cpp](https://github.com/ggml-org/llama.cpp) and community quant releases (e.g. Hugging Face).

---

## 🖥️ Requirements

| Item | Requirement |
| --- | --- |
| **DSH** | ≥ 0.1.0-rc.7 with a web profile |
| **llama.cpp** | `llama-server` binary (verified: 0.1.2-dev build 10488, CUDA 13.3; CPU builds work too — set `ngl: 0`) |
| **Model files** | Two GGUF + two mmproj files (paths configured on the card) |
| **Hardware** | Verified on RTX 4070 SUPER 12GB + 32GB RAM (i5-13600KF); the 128K preset needs plenty of RAM |
| **OS** | Windows first-class (Linux/macOS: change `serverExe` to `llama-server`) |

**Recommended model files** (size reference):

| File | Purpose | Size |
| --- | --- | --- |
| `Qwen3.6-35B-A3B` (IQ4_NL GGUF) | 35B main model | ~20GB |
| `mmproj` (Qwen3.6-35B-A3B) | 35B vision projector | ~1.5GB |
| `Qwen3.5-9B` (Q4_K_M GGUF) | 9B main model | ~6GB |
| `mmproj` (Qwen3.5-9B) | 9B vision projector | ~700MB |

---

## 📦 Installation

### Option 1: one command (recommended)

```bash
# dsh is on your PATH (globally installed @deepseek-ai/dsh)
dsh plugin --profile web add dsh-local-llm-controller

# Equivalent if dsh is not on PATH (you run DSH via dlx/npx):
pnpm dlx @deepseek-ai/dsh plugin --profile web add dsh-local-llm-controller
```

**Restart DSH Web** and you are done — this package declares `dsh.bundle`, so DSH registers it automatically. **No config lines to add by hand.**

### ✏️ First use (everything on the card, nothing to edit by hand)

1. Open **Settings → Plugins → Local LLM Controller** and expand the card.
2. Fill in the «Config» section:

   | Field | Notes |
   | --- | --- |
   | `llama.cpp directory` | Folder containing `llama-server.exe` (required) |
   | `Port` | Default `55555`; saved changes re-sync the provider's `baseURL` on the **next start** |
   | `API key` | Leave empty = no auth (loopback only); otherwise match `DSH_LOCAL_LLM_KEY` |
   | `35B / 9B folders` | Model folders; defaults are `llama.cpp dir\qwen3.6-35B-A3B` / `...\qwen3.5-9B` |

   > 🔍 Files are **auto-detected** in the folder: the file containing `mmproj` is the vision projector, the other is the main model — file names and quant suffixes do not matter.

3. **Save config** → pick model (35B/9B), mode (text/vision), preset (fast/long-context) → **Start** (first load takes 40–90s, that's normal).
4. Once status shows **running**, pick **Qwen3.5-9B Local** or **Qwen3.6-35B-A3B Local** in the session and chat.
5. **Stop** releases the port; on error the card shows the reason and recent logs.

> ⚙️ Advanced parameters (`ngl`, thread counts, model aliases, provider customization, …) remain available through the `local-llm.config` section of `settings.yaml` — field names are in the source comments.

### 🗑️ Uninstall

1. If a model is running, press **Stop** on the card first (optional — DSH kills child processes on restart anyway).
2. One command (registration is removed automatically):

   ```bash
   dsh plugin --profile web remove dsh-local-llm-controller
   ```

3. Restart DSH Web — the card is gone.

| Leftovers after uninstall (optional cleanup) | Notes |
| --- | --- |
| `local-llm` section in `settings.yaml` | Plugin-written state/config; harmless to keep |
| `llm-pi-ai.providers.qwen36-local / qwen35-local` | **Keep if you'll keep serving the same port manually**; delete when no longer needed |
| `~/.dsh/local-llm.config.json` | Legacy from the old installer era; safe to delete |
| Model files / llama.cpp itself | Unrelated to the plugin; keep them |

---

## 🧪 Test environment

| Item | Value |
| --- | --- |
| GPU | RTX 4070 SUPER 12GB (12282 MiB) |
| CPU | i5-13600KF (6P + 8E, 20 threads) |
| RAM | 32GB |
| llama.cpp | 0.1.2-dev (build 10488), CUDA 13.3 |
| DSH | 0.1.0-rc.7 (web profile) |
| Models | Qwen3.6-35B-A3B (IQ4_NL, 18.4GB) + f16 mmproj; Qwen3.5-9B (Q4_K_M) + BF16 mmproj |
| Method | Clean-environment reruns: `/health` + `/props` (auth) readiness, `/completion` deep-fill throughput, nvidia-smi VRAM & GPU utilization sampling |

---

## 📊 Benchmark summary (35B)

| Config | Free shared (MiB) | Big image encode | Deep-fill speed | Verdict |
| --- | --- | --- | --- | --- |
| ncmoe 20 @ 32K | ~150 | — | ~70 t/s | ✅ Baseline: far from the overflow point, no slowdown |
| ncmoe 20 @ 80K | **303** | — | 63.5 t/s | ⚠️ KV spill begins — not recommended |
| ncmoe 22 @ 128K | 227~260 | — | 45~54 t/s | 📌 Long-context ceiling for ncmoe 22 (196608 is a hard cliff) |
| **ncmoe 24 @ 32K vision** | 132~149 | **11.8s** | 62 t/s | 🏆 Best for vision: mmproj fully on GPU |
| **ncmoe 24 @ 96K vision** | 198 | **15.2s** | 49.5 t/s | 🏆 Best overall: 3× context + usable image speed |

**Conclusion**: KV buffers are allocated per layer; once weights + KV exceed 12GB some KV layers fall into shared memory and every generated token crosses PCIe → throughput collapse. **Free shared memory is the most reliable spill signal.** Preset choices: 32K text is safe / 128K is ncmoe 22's ceiling / vision requires ncmoe 24. The slowdown curve (74→70→63→60→54 t/s as fill grows 40k→53k→70k→88k→119k) is model behavior — no config escapes it.

📚 Full report, raw data, and test scripts (redacted) live in [docs/measurements/](docs/measurements/).

---

## 📄 License

[MIT](LICENSE)
