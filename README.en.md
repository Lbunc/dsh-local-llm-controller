<div align="center">

# dsh-local-llm-controller

<img src="images/wallpaper.jpg" alt="dsh-local-llm-controller" width="100%">

**A DSH plugin: start/stop a local llama.cpp server from the settings page — make your local model the DSH session model**

The control card lives in Settings → Plugins → Local LLM Controller

**English** | [简体中文](README.md)

[![npm version](https://img.shields.io/npm/v/dsh-local-llm-controller?color=blue)](https://www.npmjs.com/package/dsh-local-llm-controller)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/Lbunc/dsh-local-llm-controller/blob/main/LICENSE)
[![llama.cpp](https://img.shields.io/badge/llama.cpp-upstream-8B5CF6)](https://github.com/ggml-org/llama.cpp)
[![DSH 0.1.7-rc.2](images/badge-dsh.svg)](https://www.npmjs.com/package/@deepseek-ai/dsh)
[![Type: DSH Plugin](https://img.shields.io/badge/Type-DSH%20Plugin-8A2BE2.svg)](https://github.com/topics/dsh-plugin)

</div>

***

> **Compatibility note**: DSH 0.1.7-rc.1 introduced massive internal changes. Plugin v2.1.0 and later target this architecture (RC branch only; other branches are not guaranteed to work).

## Features

- **One-click local server control**: launch or stop llama-server from the Settings → Plugins card; status, error reason and recent logs show on the same card. DSH reaps plugin child processes on restart.
- **Dual-slot model management**: slots A / B each bind a model folder; all GGUFs inside are auto-scanned into a pickable list. The vision projector (mmproj) is auto-detected and auto-attached in vision mode.
- **Eight launch-parameter groups**: organized by slot × text/vision × fast/long, with freely editable rows and prefilled basics.
- **One-click session hookup**: writes the picked model into the DSH model page (see the entry table in the usage flow), ready to pick at the bottom of any session.
- **Local compaction engine** (v2.1.2): shipped as a subpath export, a local replacement for the DSH built-in compaction engine targeting 32k~150k windows. See "Local compaction engine".

> This plugin only connects DSH ↔ llama.cpp: it ships neither the llama-server binary nor models. Those come from upstream [llama.cpp](https://github.com/ggml-org/llama.cpp) and community quantizations (e.g. Hugging Face).

## Quick start

### Install

Recommended: the DSH built-in plugin manager. Sidebar **Settings → Plugins → Add plugin**, enter any address from the table below, pick the install source, then install and enable. No DSH Web restart is needed afterwards.

Command line (rerunning the same command upgrades; prints Already up to date when current):

```text
dsh plugin --profile web add <address>
```

| Address form | Notes |
| :- | :- |
| dsh-local-llm-controller | Package name — installs the latest release from the npm registry |
| Local folder path | Live link, first choice for development; takes effect after pulling updates and restarting DSH |
| Release tgz package path | Offline install from a published package |
| GitHub repository URL | Installs the latest push; may be unstable |

<p align="center"><img src="images/plugin-manager-add.png" width="420" alt="DSH plugin manager: Add plugin dialog with dsh-local-llm-controller entered"></p>

Common commands:

```text
dsh plugin --profile web outdated                                       # check updates; no output = up to date
dsh plugin --profile web add dsh-local-llm-controller@2.1.2             # install a pinned version
npx @deepseek-ai/dsh plugin --profile web add dsh-local-llm-controller  # equivalent when the dsh CLI is not installed globally
```

> [!NOTE]
> Seeing peer-dependency warnings during install/upgrade is expected: this plugin's peer dependencies are provided by the DSH host, not installed with the package. It does not affect usage.

### Usage flow

1. **Basic connection**: open the config card, fill in the fields below, then save.

   | Field | Notes |
   | :- | :- |
   | llama.cpp directory | Folder containing the llama-server executable; required |
   | Port | Default 55555; written into the provider baseURL by Add to model list |
   | API key | Blank = no auth (loopback only); a placeholder auth header is written either way (client protocol requirement) |

   <p align="center"><img src="images/setting-plug.png" width="420" alt="Settings → Plugins (config card)"></p>

2. **Slots**: enter a model folder path for each of slots A / B (containing the model GGUFs; add an mmproj for vision), then click Save config.
3. **Add to model list**: after saving, all model GGUFs in the folder become candidate bubbles (mmproj never appears — it is wired automatically in vision mode). Pick one, save, then click Add to model list. The model name is derived from the file name; rename on the Settings → Models page if needed. Entries re-sync to the active preset group on every start (switch fast/long and restart to update), with these values:

   | Written entry | Value |
   | :- | :- |
   | contextWindow | The slot's fast-group -c value |
   | maxTokens | One quarter of that -c value (reduced from one half in v2.1.2: an oversized reservation crushes the compaction threshold — see "Local compaction engine") |

4. **Launch parameters**: eight groups (slot × text/vision × fast/long); the group being edited is shown in the editor title. Each row is a flag/value pair with add and remove controls; basics are prefilled and recommended sets are in "Recommended launch parameters". The following are managed by the plugin — never add them manually:

   | Plugin-managed parameters | Applies to |
   | :- | :- |
   | -m / -a / --port / --host / --api-key | All modes (auth header enabled when a key is set) |
   | --mmproj / --image-min-tokens | Vision mode |

   <p align="center"><img src="images/params.png" width="420" alt="Launch parameter rows (one of 8 groups)"></p>

5. **Launch**: choose slot (A/B), mode (text/vision), preset (fast/long), then click Start.

   <p align="center"><img src="images/setting-model.png" width="420" alt="Settings → Models (after Add to model list)"></p>

6. **Chat**: once the status turns Running, pick the local model at the bottom of a session; Stop releases the port; errors show the reason and recent logs on the card.

   <p align="center"><img src="images/useing.png" width="420" alt="Pick the local model in a session to chat"></p>

### Notes

- After switching the model file in the same slot, the Provider Key changes with the file name: the old entry on the Settings → Models page is never overwritten or removed automatically. Delete it manually, then write the new one.
- The image decoder of old llama-server builds does not support WebP. This plugin raises DSH's image-request budget to 16 MiB / 4096², so regular PNG/JPEG screenshots and large images pass through untouched; convert WebP sources to PNG/JPEG before sending.
- The vision projector file must contain mmproj in its file name to be auto-detected.
- To pin a Provider Key (so switching model files does not break existing model selections), rename the model on the Settings → Models page; models-page edits do not write back into the plugin config.

### Uninstall

1. If a model is running, click Stop on the card first (optional — DSH reaps plugin children on restart). If the default model or a preset is set to a local model, switch it back to a cloud model before uninstalling, or the default model dangles.
2. Use the Uninstall button on the plugin row, or run (bundle registration and the link dependency are purged automatically):

   ```text
   dsh plugin --profile web remove dsh-local-llm-controller
   ```

3. Refresh the page — the card disappears. No DSH restart needed.

The command automatically cleans the profile's bundle registration and dependency declaration. The following are not auto-removed (verified on v2.1.0 / DSH 0.1.7-rc.1):

| Leftover (optional cleanup) | Notes |
| :- | :- |
| ~/.dsh/local-llm.config.json | The card config (llama.cpp directory, port, all eight launch-parameter groups). Keep it if you plan to reinstall |
| llm-pi-ai.providers.dsh-local in the profile patch | The model-page entry written by Add to model list; still usable when running the same port manually, delete if unused |
| The version-exempt line in pnpm-workspace.yaml | Install metadata that remove does not recycle; harmless |

> [!NOTE]
> Upgrading from v2.0.x: the old local-llm section in settings.yaml was renamed into settings.yaml.imported during the one-time DSH 0.1.7 import; nothing reads it anymore, no action needed.

## Recommended launch parameters

> Baseline measured on v1.x. Each line below is one set — paste it into the matching launch-parameter group, or use it to run llama-server manually. Plugin-managed parameters are never added manually (see usage flow step 4).

**35B** (Qwen3.6-35B-A3B, MoE):

```text
35B · text · fast        : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 32768 -ncmoe 20 --reasoning-budget 2048 --metrics --slots
35B · text · long        : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 131072 -ncmoe 22 --reasoning-budget 2048 --metrics --slots
35B · vision · fast      : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 32768 -ncmoe 24 --reasoning-budget 2048 --metrics --slots
35B · vision · long      : -ngl 99 -fa on -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 -c 98304 -ncmoe 24 --reasoning-budget 2048 --metrics --slots
```

**9B** (Qwen3.5-9B, Dense):

```text
9B · text · fast        : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 32768 --metrics --slots
9B · text · long        : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 65536 --metrics --slots
9B · vision · fast      : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 32768 --metrics --slots
9B · vision · long      : -ngl 99 -fa auto -t 20 -tb 20 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --temp 0.8 --top-k 40 --top-p 0.95 --min-p 0.05 -c 65536 --metrics --slots
```

| Measured conclusions | Notes |
| :- | :- |
| -ncmoe (MoE expert offload count) and --reasoning-budget | Two measured optimization points for the 35B |
| Reliable long-context ceiling | 131072 for the 35B (ncmoe 22); 65536 for the 9B |
| 196608 | Hard cliff — the KV cache spills into shared memory |

Full measurements, model-selection conclusions, and the experiment methodology are in "Further reading".

## Further reading

- [Tuning report archive (per-model reports)](docs/measurements/README.md): one report per model — 35B / 9B / 27B / Occamy — with a conclusions digest, cross-model capability comparison, and reproduction scripts & raw-log notes.
- [Occamy-1.0 vs Qwen3.6-35B-A3B comparison](docs/measurements/occamy_vs_ud_report.md): same-session A/B of two same-base 35B MoEs across capability, speed and context, quantified as +17% decode versus +32% prefill.
- [llm-experiment-design · DSH tuning skill](docs/llm-experiment-design/SKILL.md): a skill for deep-tuning a new GGUF, scheduling scripts and interpreting results through the pipeline of runtime probing → necessity-gated scans → four-signal measurements → capability verification, delivering a reproducible set of optimal launch parameters (MoE and dense both supported).

## Local compaction engine (v2.1.2)

The plugin ships a compaction engine, LocalCompactionEngine, as a subpath export. It extends the official CompactionEngine base class and replaces the DSH built-in compaction engine. Targeting 32k~150k local context windows, it fixes two failure modes of the built-in engine: the trigger threshold being crushed (or silently disabled) by a fixed reservation, and a feedback loop in which the post-compaction usage re-triggers compaction on the next turn.

### Package name and form

| Item | Notes |
| :- | :- |
| Engine entry | Subpath export dsh-local-llm-controller/compaction |
| Exported class | LocalCompactionEngine, extending CompactionEngine from @deepseek-ai/dsh-compaction |
| Replaces | @deepseek-ai/dsh-compaction-basic (the DSH built-in compaction engine) |
| Runtime registration | The engine registers as ctx.compaction; the manual /compact command stays compatible |
| Host dependencies | @deepseek-ai/dsh-* declared as >=0.1.7-rc.1, provided by the DSH host — future DSH upgrades require no version edits |

### Differences from the DSH default

| Aspect | DSH default (dsh-compaction-basic) | This engine |
| :- | :- | :- |
| Trigger threshold | min(0.8W, W − maxTokens − 65536) — a fixed-constant reservation | min(0.7W, W − reserved − margin) — proportional to the window |
| Small-window behavior | Formula goes negative at 32768 (auto-compaction silently disabled); at 131072 the threshold drops to 37.5%, firing far too early | Threshold 22937 at 32768 and 91750 at 131072 — both about 70% |
| Re-triggering | Summary plus retained tail can exceed the threshold again next turn | The capped-tail construction keeps the post-compaction usage well below the threshold, eliminating the feedback loop |
| Summarization call | Fixed 65,536-token budget | Three-tier fallback (below), output budget derived from remaining space |
| Tool-result pruning | Optional | Enforced before compaction; if the usage drops below the threshold, LLM summarization is skipped entirely |
| Intended window | Million-token cloud models | 32k~150k local windows |

### Core mechanisms

| Mechanism | Notes |
| :- | :- |
| Proportional threshold | threshold = min(0.7W, W − reserved − margin), margin = clamp(0.05W, 1024, 8192) |
| Capped tail | tail ≤ min(0.16 × (W − reserved), threshold − summaryUpper − margin) |
| Summary fallback | Local summarization on the routed model (reuses the KV prefix cache, auto-retry — 2 attempts total by default) → configured cloud summarization target (optional) → truncation-style checkpoint fallback (deterministic, model-free, the session never stalls) |
| Pre-pruning | Old tool results are pruned before compaction; if the usage drops below the threshold, LLM summarization is skipped entirely |
| Overflow recovery | Automatic recovery on request-window overflow; the manual compaction path stays compatible |
| Runtime logs | All lines carry the [local-compaction] prefix, covering pressure checks, compaction commits, summary fallback, and overflow recovery |

### Adoption: create a custom agent mode

The engine cannot automatically replace the compaction group built into the shipped presets: the official patch mechanism cannot address the plugin list inside a preset. To use it, create a custom agent mode (preset) in DSH and declare a compaction group in its plugin list:

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

> The isolate field must be kept: the engine reads the tool-result pruner through ctx.get, so both must share the same isolate realm.

Presets can be declared in a user-level patch file (registered into the profile as a link dependency and listed under dsh.profile.bundles) or created with the web settings editor. Fallback and disable: point the compaction child row's name back to @deepseek-ai/dsh-compaction-basic to restore the official engine; restart DSH to take effect (bundle patch files do not hot-reload).

Optional engine-row configuration:

| Key | Notes |
| :- | :- |
| thresholdRatio / retainRatio / summaryReserveTokens | Threshold and reservation parameters |
| summarizationProvider / summarizationModel | Cloud summarization target, configured as a pair |
| compactionRetries / maxOverflowRetries | Retry counts for compaction and overflow recovery |
| auto | Auto-compaction switch |

### Field results

| Preset | Window | Behavior |
| :- | :- | :- |
| fast | 32768 | Controlled test: compacted 13116 → 7103 tokens, then stable — no re-trigger |
| long | 131072 | Real session: three threshold crossings (93313 / 91924 / 93973) were each resolved by tool-result pruning alone (down to 69189 at the lowest), with no LLM summarization; at the next crossing (93290) compaction ran, producing a ~1817-token local summary and dropping the usage to 44479 tokens, stable afterwards |


## License

<div align="center">

[MIT](LICENSE)

</div>
