<div align="center">

# 🚀 dsh-local-llm-controller

<img src="images/wallpaper.jpg" alt="dsh-local-llm-controller" width="100%">

**A DSH plugin: start/stop a local llama.cpp server from the settings page — make your local model the DSH session model**

[![npm version](https://img.shields.io/npm/v/dsh-local-llm-controller?color=blue)](https://www.npmjs.com/package/dsh-local-llm-controller)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/Lbunc/dsh-local-llm-controller/blob/main/LICENSE)
[![llama.cpp](https://img.shields.io/badge/llama.cpp-upstream-8B5CF6)](https://github.com/ggml-org/llama.cpp)
[![DSH Artifact](https://www.dsh.so/badge/dsh-local-llm-controller.svg)](https://www.dsh.so/artifact/dsh-local-llm-controller/)
[![Install on DSH](https://www.dsh.so/badge/install/dsh-local-llm-controller.svg)](https://www.dsh.so/artifact/dsh-local-llm-controller/)

**English** | [简体中文](README.md)

</div>

***

## ✨ Overview

Start/stop a local [llama.cpp](https://github.com/ggml-org/llama.cpp) `llama-server` right from the DSH (DeepSeek Harness) **Settings → Plugins** page, hooking your local model into DSH as a session model.

> ⚠️⚠️⚠️ DSH changed a lot under the hood in `0.1.7-rc.1` — upgrade the plugin to `v2.1.0` or later to ensure compatibility.

***

## 🥳 usage after install

### Usage flow

1. **Slot A / B config**: enter a **model folder path** each (containing model GGUFs; add an mmproj for vision) → click **「Save config」**.
2. **Launch zone**: choose slot A/B → mode (text/vision) → preset (fast/long) → click **「Start」**.

### ⚠️ Notes

- **This plugin targets the DSH RC release branch only** (currently verified on `0.1.7-rc.1`; other branches are not guaranteed to work).
- **After switching the model file in the same slot**: the Provider Key changes with the file name — the old key in **Settings → Models** is **never overwritten/removed automatically**; delete the old entry manually, then click「Add to model list」to write the new one.
- **Vision images**: the image decoder of old llama-server builds **does not support WebP**. This plugin raises DSH's image-request budget to 16MiB / 4096², so regular **PNG/JPEG screenshots and large images pass through untouched**; **WebP source files** must be converted to PNG/JPEG first.
- The **mmproj** (vision projector) in the model folder is auto-detected and auto-attached in vision mode; its file name must contain `mmproj`.
- To pin a Provider Key (so switching model files does not break existing model selections): rename the model on **Settings → Models** — the plugin keeps using the derived key as-is; models-page edits do not write back into the plugin config.

> 🧩 This plugin only connects **DSH ↔ llama.cpp**: it ships neither `llama-server` nor models — those come from upstream [llama.cpp](https://github.com/ggml-org/llama.cpp) and community quantizations (e.g. Hugging Face).

***

## 📦 Installation

### One command (recommended)

```bash
# dsh is on PATH (globally installed @deepseek-ai/dsh)
dsh plugin --profile web add dsh-local-llm-controller

# when dsh CLI is not globally installed (@deepseek-ai/dsh not on PATH), use npx (bundled with Node, no extra install) to fetch the CLI on the fly:
npx @deepseek-ai/dsh plugin --profile web add dsh-local-llm-controller
```

Then **restart DSH Web** — the package declares `dsh.bundle`, registration is automatic, no manual config rows. The card appears at **Settings → Plugins → Local LLM Controller**.

### 🧩 Plugin manager (GUI)

Open the **Plugins** page in the DSH Web sidebar → click **「Add plugin」** → enter the package name `dsh-local-llm-controller` → pick an install source → click **「Install」**, then **restart DSH Web** the same way.

<p align="center"><img src="images/plugin-manager-add.png" width="420" alt="DSH plugin manager: Add plugin dialog with dsh-local-llm-controller entered"></p>

### ⬆️ Upgrade

One command upgrades to the latest version (`add` re-resolves the version and updates the dependency; it prints `Already up to date` when nothing changed):

```bash
dsh plugin --profile web add dsh-local-llm-controller
```

Then **restart DSH Web** (host-side code loads at startup). Other common forms:

| Goal                                                     | Command                                                       |
| -------------------------------------------------------- | ------------------------------------------------------------- |
| Check for a newer version first (no output = up to date) | `dsh plugin --profile web outdated`                           |
| Install a specific version                               | `dsh plugin --profile web add dsh-local-llm-controller@2.1.0` |
| Installed via `link:` for development (not from npm)     | No upgrade command — `git pull` and restart DSH               |

> Seeing `Issues with peer dependencies found` during install/upgrade is expected (this plugin's peers are provided by the DSH host and are not installed with the package) and does not affect usage.

### 🗑️ Uninstall

1. If a model is running, click **「Stop」** on the card first (optional — DSH reaps plugin children on restart).
2. If the **default model** or a preset is set to a local model (provider `dsh-local`), switch it back to a cloud model before uninstalling, or the default model dangles.
3. One command removes it (bundle registration and the `link:` dependency are purged automatically):
   ```bash
   dsh plugin --profile web remove dsh-local-llm-controller
   ```
4. Restart DSH Web — the card disappears.

The command automatically cleans the profile's bundle registration and dependency (`profiles/web/package.json`, `pnpm-lock.yaml`). The following are **not** auto-removed (verified on v2.1.0 / DSH 0.1.7-rc.1):

| Leftovers (optional cleanup)                                   | Notes                                                                                                      |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `~/.dsh/local-llm.config.json`                                 | **The card config** (llama.cpp dir, port and all 8 launch-parameter groups). Keep it if you plan to reinstall; delete only when fully abandoning the plugin |
| `llm-pi-ai.providers.dsh-local` (in `profiles/web/cordis.patch.yml`) | The model-page entry written by 「Add to Model List」; still usable when running the same port manually, delete if truly unused |
| The version-exempt line in `pnpm-workspace.yaml`               | One line of install metadata (`dsh-local-llm-controller@…`) that remove does not recycle; harmless, ignore it |

> Upgrading from v2.0.x: the old `local-llm` section in `settings.yaml` was renamed into `settings.yaml.imported` during the one-time DSH 0.1.7 import; nothing reads it anymore, no action needed.

***

## 📐 Recommended launch parameters (8 sets, v1.x measured baseline)

> Parameters the plugin manages automatically — never add them manually: `-m` / `-a` / `--port` / `--host` / `--api-key` (when a key is set) and vision-mode `--mmproj` / `--image-min-tokens`. Each line below is one set — paste it into the matching launch-parameter group, or use it to run `llama-server` manually.

**35B** (Qwen3.6-35B-A3B, MoE):

```
35B · text · fast        : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 32768 -ncmoe 20 --reasoning-budget 2048 --metrics --slots
35B · text · long        : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 131072 -ncmoe 22 --reasoning-budget 2048 --metrics --slots
35B · vision · fast      : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 32768 -ncmoe 24 --reasoning-budget 2048 --metrics --slots
35B · vision · long      : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 98304 -ncmoe 24 --reasoning-budget 2048 --metrics --slots
```

**9B** (Qwen3.5-9B, Dense):

```
9B · text · fast        : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 32768 --metrics --slots
9B · text · long        : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 65536 --metrics --slots
9B · vision · fast      : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 32768 --metrics --slots
9B · vision · long      : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 65536 --metrics --slots
```

> 📌 For the 35B, `-ncmoe` (MoE expert offload count) and `--reasoning-budget` are measured optimizations; reliable long-context ceilings are `-c 131072` (35B, ncmoe 22) / `-c 65536` (9B) — `-c 196608` is the hard cliff (KV spills into shared memory). For full measurements, model-selection conclusions, and the experiment methodology, see **Further reading** below.

***

## 📖 Further reading

- [Tuning Report Archive (35B / 9B / 27B)](docs/measurements/ctx_scan_report.md): Multi-model real-world measurements, tuning conclusions, hardware selection advice, and the long-context safe-ceiling summary.
- **[llm-experiment-design · DSH Tuning Skill](docs/llm-experiment-design/SKILL.md)**: The Skill for deep-tuning a new GGUF — it schedules scripts and interprets results via the standard pipeline: runtime probing → necessity-gated scans → four-signal measurements → capability verification, and delivers a reproducible set of optimal launch parameters (MoE + dense both supported).

***

## 📄 License

[MIT](LICENSE)
