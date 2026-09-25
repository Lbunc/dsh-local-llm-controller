<div align="center">

# 🚀 dsh-local-llm-controller

<img src="images/wallpaper.jpg" alt="dsh-local-llm-controller" width="100%">

**A DSH plugin: start/stop a local llama.cpp server from the settings page — make your local model the DSH session model**

The control card lives in Settings → Plugins → Local LLM Controller

**English** | [简体中文](README.md)

[![npm version](https://img.shields.io/npm/v/dsh-local-llm-controller?color=blue)](https://www.npmjs.com/package/dsh-local-llm-controller)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/Lbunc/dsh-local-llm-controller/blob/main/LICENSE)
[![llama.cpp](https://img.shields.io/badge/llama.cpp-upstream-8B5CF6)](https://github.com/ggml-org/llama.cpp)
[![DSH 0.1.7-rc.2](images/badge-dsh.svg)](https://www.npmjs.com/package/@deepseek-ai/dsh)

</div>

***

> ⚠️ **DSH changed massively under the hood in 0.1.7-rc.1 — only plugin v2.1.0+ is compatible (RC release branch only; other branches are not guaranteed to work).**

## ✨ Features

- ⚡ **One-click start/stop of a local `llama-server`**: launch/stop right from the Settings → Plugins card; status, error reason and recent logs show on the same card; DSH reaps plugin child processes on restart
- 📁 **Slot A / B model folders**: all model GGUFs in a folder are auto-scanned into a pickable list; the **mmproj** (vision projector) is auto-detected and auto-attached in vision mode
- 🎛️ **8 launch-parameter groups** (slot × text/vision × fast/long): rows of `flag + value` freely addable/removable, basics prefilled; `-m` / `-a` / `--port` / `--host` / `--api-key` and vision-mode `--mmproj` are managed by the plugin
- 🧩 **One-click session hookup**: 「Add to model list」 writes the picked model into the DSH model page (provider `dsh-local`), ready to pick at the bottom of any session

> 🧩 This plugin only connects **DSH ↔ llama.cpp**: it ships neither `llama-server` nor models — those come from upstream [llama.cpp](https://github.com/ggml-org/llama.cpp) and community quantizations (e.g. Hugging Face).

## 🚀 Quick start

### Install

**DSH built-in plugin manager (recommended)**: sidebar **Settings → Plugins → Add plugin**, enter any address from the table below → pick the install source → **Install** → enable. **No DSH Web restart needed** after install.

**Command line**: `dsh plugin --profile web add "<address>"` (upgrade = rerun the same command; prints `Already up to date` when already current)

| Address form | Notes |
| :- | :- |
| `dsh-local-llm-controller` | Package name — installs the latest release from the npm registry |
| `D:\path\to\dsh-local-llm-controller` | Local folder. Live `link:`, first choice for development; takes effect after `git pull` + DSH restart |
| `D:\path\to\dsh-local-llm-controller-2.1.0.tgz` | Release `.tgz` package |
| `https://github.com/Lbunc/dsh-local-llm-controller` | GitHub repo. Installs the latest push, may be unstable |

<p align="center"><img src="images/plugin-manager-add.png" width="420" alt="DSH plugin manager: Add plugin dialog with dsh-local-llm-controller entered"></p>

> [!TIP]
> - 🛠️ If `dsh` is not on PATH (`@deepseek-ai/dsh` not installed globally), fetch the CLI on the fly with Node's built-in npx: `npx @deepseek-ai/dsh plugin --profile web add dsh-local-llm-controller`
> - 🔍 Check for a newer version first: `dsh plugin --profile web outdated` (no output = up to date); install a pinned version: `dsh plugin --profile web add dsh-local-llm-controller@2.1.0`
> - 📦 Seeing `Issues with peer dependencies found` during install/upgrade is expected (this plugin's peers are provided by the DSH host, not installed with the package) and does not affect usage.

### Usage flow

1. **Open the card** and fill in the config area:
   - `llama.cpp directory`: where `llama-server.exe` lives (required)
   - `Port`: default 55555 (「Add to model list」writes the current value into the provider baseURL)
   - `API key`: blank = no auth (loopback only); a placeholder auth header is still written (pi-ai client requires one), and a set value is used on both sides

   <p align="center"><img src="images/setting-plug.png" width="420" alt="Settings → Plugins (config card)"></p>

2. **Slot A / B config**: enter a **model folder path** each (containing model GGUFs; add an mmproj for vision) → click **「Save config」**.
3. **Add the model to the model list**: after saving, all model GGUFs in the folder become bubbles (mmproj never appears — it is wired automatically in vision mode) → pick one → **「Save config」** → **「Add to model list」**. The model name is **derived** from the file name; rename / change the display name on **Settings → Models**.

   <p align="center"><img src="images/setting-model.png" width="420" alt="Settings → Models (after Add to model list)"></p>

4. **Launch parameters** (8 groups = slot × text/vision × fast/long): the group being edited is shown as「Launch args (current combo)」; each row is a `flag` + `value` pair of inputs, with **+ add row** and **× delete row**. Basics are prefilled (`-ngl`/`-t`/`-c`/sampling…); see the recommended sets in 「📐 Recommended launch parameters」 below and the [llama.cpp docs](https://github.com/ggml-org/llama.cpp). `-m`/`-a`/`--port`/`--host`/`--api-key` and vision-mode `--mmproj` are managed automatically — never add them manually.

   <p align="center"><img src="images/params.png" width="420" alt="Launch parameter rows (one of 8 groups)"></p>

5. **Launch zone**: choose slot A/B → mode (text/vision) → preset (fast/long) → click **「Start」**.
6. **Chat**: once the status turns Running, pick the local model at the bottom of a session; **「Stop」** releases the port; errors show the reason and recent logs on the card.

   <p align="center"><img src="images/useing.png" width="420" alt="Pick the local model in a session to chat"></p>

### ⚠️ Notes

- **After switching the model file in the same slot**: the Provider Key changes with the file name — the old key in **Settings → Models** is **never overwritten/removed automatically**; delete the old entry manually, then click「Add to model list」to write the new one.
- **Vision images**: the image decoder of old llama-server builds **does not support WebP**. This plugin raises DSH's image-request budget to 16MiB / 4096², so regular **PNG/JPEG screenshots and large images pass through untouched**; **WebP source files** must be converted to PNG/JPEG first.
- The **mmproj** (vision projector) in the model folder is auto-detected and auto-attached in vision mode; its file name must contain `mmproj`.
- To pin a Provider Key (so switching model files does not break existing model selections): rename the model on **Settings → Models** — the plugin keeps using the derived key as-is; models-page edits do not write back into the plugin config.

### Uninstall

1. **Before uninstalling**: if a model is running, click **「Stop」** on the card first (optional — DSH reaps plugin children on restart); if the **default model** or a preset is set to a local model (provider `dsh-local`), switch it back to a cloud model first, or the default model dangles.
2. **Plugin manager**: the **Uninstall** button on the plugin row; **command line**: `dsh plugin --profile web remove dsh-local-llm-controller` (bundle registration and the `link:` dependency are purged automatically).
3. Refresh the page — the card disappears (no DSH restart needed).

The command automatically cleans the profile's bundle registration and dependency (`profiles/web/package.json`, `pnpm-lock.yaml`). The following are **not** auto-removed (verified on v2.1.0 / DSH 0.1.7-rc.1):

| Leftovers (optional cleanup)                                         | Notes                                                                                                                                                       |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `~/.dsh/local-llm.config.json`                                       | **The card config** (llama.cpp dir, port and all 8 launch-parameter groups). Keep it if you plan to reinstall; delete only when fully abandoning the plugin |
| `llm-pi-ai.providers.dsh-local` (in `profiles/web/cordis.patch.yml`) | The model-page entry written by 「Add to Model List」; still usable when running the same port manually, delete if truly unused                               |
| The version-exempt line in `pnpm-workspace.yaml`                     | One line of install metadata (`dsh-local-llm-controller@…`) that remove does not recycle; harmless, ignore it                                               |

> [!NOTE]
> 🔄 **Upgrading from v2.0.x**: the old `local-llm` section in `settings.yaml` was renamed into `settings.yaml.imported` during the one-time DSH 0.1.7 import; nothing reads it anymore, no action needed.

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

## 📖 Further reading

- [Tuning Report Archive (35B / 9B / 27B)](docs/measurements/ctx_scan_report.md): Multi-model real-world measurements, tuning conclusions, hardware selection advice, and the long-context safe-ceiling summary.
- **[llm-experiment-design · DSH Tuning Skill](docs/llm-experiment-design/SKILL.md)**: The Skill for deep-tuning a new GGUF — it schedules scripts and interprets results via the standard pipeline: runtime probing → necessity-gated scans → four-signal measurements → capability verification, and delivers a reproducible set of optimal launch parameters (MoE + dense both supported).

## 📄 License

<div align="center">

[MIT](LICENSE)

</div>
