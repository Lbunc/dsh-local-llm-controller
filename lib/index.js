/**
 * Local LLM Controller — Host half (DSH 0.1.7-rc.1 plugin API).
 *
 * Manages a llama-server child process for TWO model SLOTS (A/B) — each slot is
 * a model folder plus a chosen GGUF and its own eight launch-parameter groups
 * (text/vision × fast/long-context).
 *
 * 0.1.7 architecture: the plugin is a class extending TypertRemoteService, so
 * the browser card reaches it through Typert Remote (`ctx.remote.localLlm.*`)
 * instead of the 0.1.5 settings action bus (settings/updated is dead). All
 * user-tunable fields live in `static Config` marked volatile — config edits
 * never restart the plugin row.
 *
 *   Remote methods:  getState / start / stop / saveConfig / listSlotFiles /
 *                    addProviders
 *
 * Config sources, in override order (file wins, as before):
 *   1. loader row config (settings.yaml `local-llm-controller` section, all
 *      volatile) — schema defaults on a fresh install,
 *   2. ~/.dsh/local-llm.config.json — written by the card's「保存配置」
 *      (remote saveConfig), re-read on every start.
 * Config is re-resolved on every start (card edits apply to the next launch).
 *
 * The DSH provider entries (llm-pi-ai.providers) are written ONLY by the
 * card's「添加到模型列表」button (remote addProviders) through
 * settings.mutate('llm-pi-ai', …) — a whole-dict replace that also drops the
 * legacy `dsh-local-*` keys. Both slots share ONE provider (`dsh-local`), one
 * entry per slot's chosen GGUF in its models list — one local server endpoint
 * (port) serves whichever slot is running, so a single provider with both
 * models keeps the model picker honest.
 *
 * Automatic arguments: -m, -a (alias), --port, --host, --api-key, and — when
 * the started mode is vision — --mmproj + --image-min-tokens from the same
 * folder's mmproj file. Machine-specific values (llama.cpp dir, port, API key,
 * model folders) are never hardcoded; they live in the config sources above.
 */

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import z from '@deepseek-ai/schemastery'
import { TypertRemoteService } from '@deepseek-ai/dsh-typert-protocol'

// ---------------------------------------------------------------------------
// Pure helpers (unit-tested in test/logic.test.mjs — semantics frozen)
// ---------------------------------------------------------------------------

/** The eight parameter groups: 2 slots × text/vision × fast/long-context. */
export const PRESET_GROUPS = ['text:fast', 'text:long', 'vision:fast', 'vision:long']

/** Derive a display alias + provider key from a GGUF file name. */
export function deriveModelNames(file) {
  const alias = (file || '').replace(/\.gguf$/i, '') || ''
  const slug = alias.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '')
  return { alias, providerKey: 'dsh-local-' + (slug || 'model') }
}

/** Basic launch-parameter rows prefilled for a fresh parameter group. */
export function defaultPresetArgs(group) {
  const ctx = group.indexOf('long') >= 0 ? 131072 : 32768
  return [
    { flag: '-ngl', value: '99' },
    { flag: '-fa', value: 'on' },
    { flag: '-t', value: '20' },
    { flag: '-tb', value: '20' },
    { flag: '-np', value: '1' },
    { flag: '--cache-type-k', value: 'q8_0' },
    { flag: '--cache-type-v', value: 'q8_0' },
    { flag: '--temp', value: '1.0' },
    { flag: '--top-k', value: '20' },
    { flag: '--top-p', value: '0.95' },
    { flag: '--min-p', value: '0.0' },
    { flag: '--repeat-penalty', value: '1' },
    { flag: '--presence-penalty', value: '0' },
    { flag: '-c', value: String(ctx) },
    { flag: '--metrics', value: '' },
    { flag: '--slots', value: '' },
  ]
}

/** Normalize one raw argument row to { flag, value } or drop it when invalid. */
export function normalizeArgRow(row) {
  if (!row || typeof row !== 'object') return null
  const flag = typeof row.flag === 'string' ? row.flag.trim() : ''
  if (!flag) return null
  const value = typeof row.value === 'string' ? row.value : (row.value == null ? '' : String(row.value))
  return { flag, value }
}

/** Normalize a raw presets object to all eight groups. An ABSENT group
 *  (fresh install, or a config predating the group) is seeded from the
 *  default template — that is the "installed defaults" moment. A STORED
 *  group — INCLUDING one that lacks rows the template later gained, and one
 *  the user emptied — is the user's state and is kept verbatim. Template
 *  updates never backfill stored groups: an upgrade must not silently change
 *  parameters the user already tuned. */
export function normalizePresets(raw) {
  const out = {}
  for (const g of PRESET_GROUPS) {
    const rows = (raw && raw[g] && Array.isArray(raw[g])) ? raw[g] : null
    out[g] = rows ? rows.map(normalizeArgRow).filter(Boolean) : defaultPresetArgs(g)
  }
  return out
}

/** Find the value of a flag (e.g. -c) inside parameter rows; null when absent. */
export function argValue(rows, flag) {
  if (!Array.isArray(rows)) return null
  for (const r of rows) if (r && r.flag === flag) return r.value || null
  return null
}

// ---------------------------------------------------------------------------
// Module constants + file helpers
// ---------------------------------------------------------------------------

/** The single llm-pi-ai provider shared by both slots — stable key so model
 *  renames on the models page and repeated「添加到模型列表」presses keep one
 *  coherent local provider; one entry per slot's chosen model inside it. */
const PROVIDER_KEY = 'dsh-local'
const PROVIDER_NAME = 'Local LLM'

/** Cordis service key AND Typert Remote namespace (they must stay equal —
 *  TypertRemoteService binds both to the same name). */
const SERVICE_KEY = 'localLlm'

/** Marker property written by the TS `Remote` decorator; hand-written here
 *  because this plugin is plain JS (no decorators). Same shape, version 1. */
const REMOTE_METHOD_DESCRIPTOR = '@deepseek-ai/dsh-typert-protocol/remote-methods'

const READY_TIMEOUT_MS = 90000
const POLL_MS = 2000

/** Loader-config defaults (also the schema defaults below). */
const DEF = {
  llamaDir: '', // author-machine path removed — fresh users must set it in the card
  serverExe: 'llama-server.exe', // linux/mac: llama-server
  port: 55555,
  apiKey: '', // empty = no auth (127.0.0.1 loopback only); set to require a key
  settingsNs: 'llm-pi-ai', // namespace holding the DSH providers
  curlPath: '', // empty = auto-detect; set to override
}

/** Volatile schema fields resolve to frozen `{ get() }` references (cosmokit
 *  createVolatile — every read path wraps, including schema defaults); the
 *  official pattern reads them with `.get()` (dsh-llm-pi-ai/lib/index.js
 *  L2544 `config.providers.get()`). The write symbol is module-private, so
 *  the reference is detected by its frozen+get shape. */
function unwrapVolatile(value) {
  if (value !== null && typeof value === 'object' && Object.isFrozen(value) && typeof value.get === 'function') {
    return value.get()
  }
  return value
}

/** The card's config file (override layer; written by remote saveConfig). */
function configFilePath() {
  return path.join(process.env.DSH_HOME || path.join(os.homedir(), '.dsh'), 'local-llm.config.json')
}

function readFileConfig() {
  try {
    const p = configFilePath()
    if (!fs.existsSync(p)) return null
    const raw = JSON.parse(fs.readFileSync(p, 'utf8'))
    return raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : null
  } catch (e) {
    console.log('[local-llm] local-llm.config.json ignored: ' + ((e && e.message) || String(e)))
    return null
  }
}

/** Enumerate the selectable model .gguf file names inside one model folder
 *  ([] on any failure). mmproj / vision-projector files are excluded: they
 *  are wired automatically in vision mode, never a selectable model. */
function listModelFiles(dir) {
  if (!dir) return []
  try {
    return fs.readdirSync(dir).filter((n) => /\.gguf$/i.test(n) && !/mmproj/i.test(n)).sort()
  } catch (e) {
    return []
  }
}

/** The vision-projector (.mmproj) file name inside a folder, if any. */
function findMmproj(dir) {
  if (!dir) return null
  try {
    const names = fs.readdirSync(dir).filter((n) => /\.gguf$/i.test(n) && /mmproj/i.test(n)).sort()
    return names.length ? names[0] : null
  } catch (e) {
    return null
  }
}

/** Plain-JS stand-in for the typert-protocol `Remote` decorator: write the
 *  same versioned prototype descriptor the decorator's addInitializer/mark
 *  path produces (frozen { version: 1, methods: [{ method, invocation }] }).
 *  The Gateway's source-mode discovery reads it via remoteMethods(service). */
function markRemote(prototype, methods) {
  Object.defineProperty(prototype, REMOTE_METHOD_DESCRIPTOR, {
    configurable: true,
    value: Object.freeze({
      version: 1,
      methods: Object.freeze(methods.map((method) => Object.freeze({
        method,
        invocation: Object.freeze({ kind: 'direct' }),
      }))),
    }),
  })
}

// ---------------------------------------------------------------------------
// Config schema — every field volatile (edits never restart the row)
// ---------------------------------------------------------------------------

const presetRowSchema = z.object({
  flag: z.string().default(''),
  value: z.string().default(''),
})

const slotSchema = z.object({
  dir: z.string().default(''),
  file: z.string().default(''),
  alias: z.string().default(''),
  presets: z.dict(z.array(presetRowSchema)).default({}),
})

const Config = z.object({
  llamaDir: z.string().default(DEF.llamaDir).volatile(),
  serverExe: z.string().default(DEF.serverExe).volatile(),
  port: z.number().default(DEF.port).volatile(),
  apiKey: z.string().default(DEF.apiKey).volatile(),
  settingsNs: z.string().default(DEF.settingsNs).volatile(),
  curlPath: z.string().default(DEF.curlPath).volatile(),
  slots: z.object({ a: slotSchema, b: slotSchema }).default({}).volatile(),
})

// ---------------------------------------------------------------------------
// LocalLlmService
// ---------------------------------------------------------------------------

var LocalLlmService = class LocalLlmService extends TypertRemoteService {
  static inject = ['subprocess', 'timer', 'settings']
  static Config = Config

  constructor(ctx, config) {
    // Registers the Cordis service AND binds the Typert Remote namespace
    // (bindTypertRemote uses this.name as the wire namespace).
    super(ctx, SERVICE_KEY)
    this.config = config

    // ---- runtime state (memory only; the card polls getState) ----
    this.CFG = this.resolveConfig()
    this.slot = 'a'
    this.status = 'stopped' // stopped | starting | ready | stopping | error
    this.mode = 'text'
    this.preset = 'fast'
    this.proc = null
    this.pollHandle = null
    this.starting = false
    this.lastError = null
    this.logTail = ''
    this.curlPath = null
    this.serverPid = null

    // ---- lifecycle ----
    ctx.effect(() => () => {
      this.stopPolling()
      if (this.proc) { try { this.proc.terminate() } catch (e) { /* noop */ } }
    })
  }

  // ---- Remote methods -----------------------------------------------------

  /** Full card snapshot: launch state + the effective config (with the
   *  folder enumeration the config zone renders). All JSON-safe. */
  getState() {
    return {
      status: this.status,
      slot: this.slot,
      mode: this.mode,
      preset: this.preset,
      // The DSH subprocess handle keeps the child's identity provider-private
      // (SubprocessHandle no longer carries a pid field), so the server's PID
      // is resolved out-of-band by resolveServerPid() — not from the handle.
      pid: this.proc ? (this.serverPid ?? null) : null,
      lastError: this.lastError,
      logTail: this.logTail.slice(-2000),
      config: this.CFG,
    }
  }

  /** Launch one slot with the selected mode/preset. Returns quickly; the
   *  card follows the transition through getState polling. */
  start(slot, mode, preset) {
    const m = slot === 'b' ? 'b' : 'a'
    const mo = mode === 'vision' ? 'vision' : 'text'
    const p = preset === 'long' ? 'long' : 'fast'
    this.startSlot(m, mo, p)
    return null
  }

  stop() {
    if (this.status === 'stopped' || this.status === 'stopping') return null
    this.status = 'stopping'
    this.stopPolling()
    const h = this.proc
    this.proc = null
    this.serverPid = null
    if (!h) {
      this.status = 'stopped'
      return null
    }
    try { h.terminate() } catch (e) { /* noop */ }
    Promise.race([
      h.done.then(() => { this.status = 'stopped' }),
      this.ctx.timer.timeout(10000).then(() => { if (this.status === 'stopping') this.status = 'stopped' }),
    ]).catch(() => { /* noop */ })
    return null
  }

  /** Card「保存配置」: persist the draft to ~/.dsh/local-llm.config.json
   *  (the file layer wins over the loader config, as before) and re-resolve
   *  the effective config so folder enumeration / derived alias follow. */
  saveConfig(config) {
    const src = (config && typeof config === 'object' && !Array.isArray(config)) ? config : {}
    const cfg = {
      llamaDir: typeof src.llamaDir === 'string' ? src.llamaDir.trim() : '',
      serverExe: typeof src.serverExe === 'string' && src.serverExe.trim() ? src.serverExe.trim() : DEF.serverExe,
      port: Number.isInteger(src.port) ? src.port : DEF.port,
      apiKey: typeof src.apiKey === 'string' ? src.apiKey.trim() : '',
      settingsNs: typeof src.settingsNs === 'string' && src.settingsNs ? src.settingsNs : DEF.settingsNs,
      slots: {},
    }
    for (const key of ['a', 'b']) {
      const s = (src.slots && src.slots[key] && typeof src.slots[key] === 'object') ? src.slots[key] : {}
      cfg.slots[key] = {
        dir: typeof s.dir === 'string' ? s.dir.trim() : '',
        file: typeof s.file === 'string' ? s.file : '',
        alias: typeof s.alias === 'string' ? s.alias : '',
        presets: normalizePresets(s.presets),
      }
    }
    try {
      fs.writeFileSync(configFilePath(), JSON.stringify(cfg, null, 2) + '\n', 'utf8')
    } catch (e) {
      throw new Error('保存配置失败: ' + ((e && e.message) || String(e)))
    }
    this.CFG = this.resolveConfig()
    console.log('[local-llm] config saved to ' + configFilePath())
    return { ok: true, config: this.CFG }
  }

  /** Card directory box (debounced): enumerate one folder's GGUF files and
   *  its vision projector without saving anything. */
  listSlotFiles(dir) {
    return {
      files: listModelFiles(dir),
      mmproj: findMmproj(dir),
    }
  }

  /** Card「添加到模型列表」: write the SHARED provider `dsh-local` into
   *  llm-pi-ai from the CURRENT effective config — port, key, and one model
   *  entry per slot whose GGUF was chosen (id = the slot's derived alias;
   *  contextWindow from that slot's text:fast `-c`). A whole-dict mutate
   *  (full replace) so legacy `dsh-local-*` providers are dropped.
   *
   *  The provider always carries an `authorization` header: pi-ai's
   *  OpenAI-completions client refuses any request without an API key or an
   *  Authorization header, even when the server itself accepts unauthenticated
   *  requests (getClientApiKey in @earendil-works/pi-ai). With no card key a
   *  harmless placeholder is used; llama-server ignores it unless it was
   *  started with a matching --api-key. */
  async addProviders() {
    const desc = this.ctx.settings.describe().find((d) => d.ns === this.CFG.settingsNs)
    if (!desc) throw new Error('add-providers: namespace ' + this.CFG.settingsNs + ' not registered')
    const current = (desc.value && typeof desc.value === 'object'
      && desc.value.providers && typeof desc.value.providers === 'object'
      && !Array.isArray(desc.value.providers)) ? desc.value.providers : {}
    const providers = Object.assign({}, current)
    const seen = new Set()
    const models = []
    for (const key of ['a', 'b']) {
      const sl = this.CFG.slots[key]
      if (!sl || !sl.file || !sl.alias || seen.has(sl.alias)) continue
      seen.add(sl.alias)
      const ctxValue = argValue(sl.presets['text:fast'], '-c')
      models.push({
        id: sl.alias,
        name: sl.alias,
        contextWindow: ctxValue ? Number(ctxValue) : 32768,
        // Output cap: must cover the thinking budget plus the answer
        // (SKILL.md 2.4) — a reasoning model on 8192 can spend the whole
        // allowance on thinking and return empty content.
        maxTokens: 16384,
        // Four thinking levels: llama-server (b10488+) honors a per-request
        // reasoning_effort in the none/low/medium/high family. minimal /
        // xhigh / max are provider dialects llama does not necessarily map.
        reasoningEfforts: { off: 'none', low: 'low', medium: 'medium', high: 'high' },
      })
    }
    if (!models.length) {
      throw new Error('add-providers: no slot has a chosen model file yet; nothing written')
    }
    providers[PROVIDER_KEY] = {
      displayName: PROVIDER_NAME,
      api: 'openai-completions',
      baseURL: 'http://127.0.0.1:' + this.CFG.port + '/v1',
      headers: { authorization: 'Bearer ' + (this.CFG.apiKey || 'dsh-local-llm') },
      defaultInput: ['text', 'image'],
      reasoning: 'high',
      // Raise the DSH request-image budget well above the default
      // 2048×2048 / 1MiB so realistic screenshots pass through
      // UNtranscoded (PNG/JPEG arrive directly at llama-server, whose
      // STB decoder cannot read the WebP that DSH's cheap re-encode
      // would produce). Images above 16MiB / 4096² still get resized,
      // which is acceptable headroom for local serving.
      requestImagePixelBudget: 16777216, // 4096×4096
      requestImageMaxBytes: 16777216, // 16 MiB
      models,
    }
    // Drop legacy per-model providers (pre-single-provider `dsh-local-*`
    // keys) so the models page never keeps orphan entries from old designs.
    const stale = Object.keys(providers).filter((k) => k !== PROVIDER_KEY && k.indexOf('dsh-local-') === 0)
    for (const k of stale) delete providers[k]
    await this.ctx.settings.mutate(this.CFG.settingsNs, [{ op: 'set', path: ['providers'], value: providers }], desc.revision)
    console.log('[local-llm] add-providers: wrote ' + PROVIDER_KEY + ' (' + models.length + ' model(s)) into ' + this.CFG.settingsNs + (stale.length ? '; removed stale ' + stale.join(', ') : '') + ' (models page updates live)')
    return { ok: true, models: models.length, removed: stale }
  }

  // ---- internals ----------------------------------------------------------

  note(tag, e) {
    const msg = tag + ': ' + ((e && e.message) || String(e))
    console.log('[local-llm] ' + msg)
  }

  /** Effective config: loader row config (schema-resolved, all volatile)
   *  overridden by the card's config file. */
  resolveConfig() {
    const src = (this.config && typeof this.config === 'object') ? this.config : {}
    const rowCfg = {}
    for (const key of ['llamaDir', 'serverExe', 'port', 'apiKey', 'settingsNs', 'curlPath', 'slots']) {
      rowCfg[key] = unwrapVolatile(src[key])
    }
    const fileCfg = readFileConfig() || {}
    const u = Object.assign({}, rowCfg, fileCfg) // file config wins
    const llamaDir = u.llamaDir || DEF.llamaDir
    const resolvePath = (s) => s.replace(/\{llamaDir\}/g, llamaDir)
    const slots = {}
    for (const key of ['a', 'b']) {
      const o = (u.slots && u.slots[key] && typeof u.slots[key] === 'object') ? u.slots[key] : {}
      const dir = o.dir ? resolvePath(o.dir) : ''
      const file = typeof o.file === 'string' ? o.file : ''
      const alias = (typeof o.alias === 'string' && o.alias) ? o.alias : (file ? deriveModelNames(file).alias : '')
      slots[key] = {
        dir,
        file,
        files: listModelFiles(dir),
        mmproj: findMmproj(dir),
        alias,
        presets: normalizePresets(o.presets),
      }
    }
    return {
      llamaDir,
      serverExe: u.serverExe || DEF.serverExe,
      port: Number.isInteger(u.port) ? u.port : DEF.port,
      apiKey: typeof u.apiKey === 'string' ? u.apiKey : DEF.apiKey,
      settingsNs: u.settingsNs || DEF.settingsNs,
      curlPath: typeof u.curlPath === 'string' && u.curlPath ? u.curlPath : null,
      slots,
    }
  }

  /**
   * Resolve the GGUF files inside one slot's model folder: the vision
   * projector is the file whose name contains "mmproj"; the model is the
   * user-chosen file (config `slots.<key>.file`, a filename inside the folder)
   * when it exists in the folder, otherwise the first non-mmproj .gguf.
   * Throws on failure.
   */
  resolveModelFiles(key) {
    const dir = this.CFG.slots[key].dir
    if (!dir) throw new Error('未配置模型文件夹（slot ' + key + ' .dir）')
    let names
    try {
      names = fs.readdirSync(dir)
    } catch (e) {
      throw new Error('模型文件夹不存在: ' + dir)
    }
    const ggufs = names.filter((n) => /\.gguf$/i.test(n)).sort()
    if (!ggufs.length) throw new Error('模型文件夹中没有 .gguf 文件: ' + dir)
    const mmproj = ggufs.find((n) => /mmproj/i.test(n))
    const chosen = this.CFG.slots[key].file
    const model = (chosen && ggufs.indexOf(chosen) >= 0 && !/mmproj/i.test(chosen)) ? chosen : ggufs.find((n) => !/mmproj/i.test(n))
    if (!model) throw new Error('模型文件夹中找不到模型 GGUF（只有一个 mmproj?）: ' + dir)
    return {
      file: dir + '/' + model,
      mmproj: mmproj ? dir + '/' + mmproj : null,
    }
  }

  buildArgv(slotKey, mo, p) {
    const sl = this.CFG.slots[slotKey]
    if (!sl) return null
    const rows = sl.presets[mo + ':' + p]
    if (!rows) return null
    const files = this.resolveModelFiles(slotKey)
    const argv = [this.CFG.llamaDir + '/' + this.CFG.serverExe, '-m', files.file]
    // vision mode auto-wires the folder's mmproj, if present
    if (mo === 'vision' && files.mmproj) argv.push('--mmproj', files.mmproj, '--image-min-tokens', '1024')
    argv.push('-a', sl.alias || ('slot-' + slotKey), '--port', String(this.CFG.port), '--host', '127.0.0.1')
    if (this.CFG.apiKey) argv.push('--api-key', this.CFG.apiKey)
    for (const r of rows) {
      argv.push(r.flag)
      if (r.value) argv.push(r.value)
    }
    return argv
  }

  readLogTail() {
    let t = ''
    if (this.proc) {
      try { if (this.proc.collected.stderr) t += this.proc.collected.stderr.readFrom(0).text } catch (e) { /* noop */ }
      try { if (this.proc.collected.stdout) t += this.proc.collected.stdout.readFrom(0).text } catch (e) { /* noop */ }
    }
    return t
  }

  stopPolling() {
    if (this.pollHandle) { try { this.pollHandle() } catch (e) { /* noop */ } this.pollHandle = null }
  }

  fail(reason) {
    this.status = 'error'
    this.lastError = reason
    this.logTail = this.readLogTail()
    this.stopPolling()
    if (this.proc) { try { this.proc.terminate() } catch (e) { /* noop */ } }
  }

  async resolveCurl() {
    if (this.curlPath) return this.curlPath
    if (this.CFG.curlPath) { this.curlPath = this.CFG.curlPath; return this.curlPath }
    try {
      this.curlPath = await this.ctx.subprocess.resolveExecutable('curl')
    } catch (e) {
      this.curlPath = process.platform === 'win32' ? 'C:/Windows/System32/curl.exe' : 'curl'
    }
    return this.curlPath
  }

  probeHealth() {
    return this.resolveCurl().then((curl) => new Promise((resolve) => {
      let h
      const argv = [curl, '-s', '-m', '3']
      if (this.CFG.apiKey) argv.push('-H', 'Authorization: Bearer ' + this.CFG.apiKey)
      argv.push('http://127.0.0.1:' + this.CFG.port + '/health')
      try {
        h = this.ctx.subprocess.spawn({
          argv,
          cwd: this.CFG.llamaDir,
          stdio: { stdin: 'ignore', stdout: { maxBytes: 4096 }, stderr: { maxBytes: 4096 } },
          graceMs: 5000,
        })
      } catch (e) {
        resolve(false)
        return
      }
      h.done.then(() => {
        const out = (h.collected.stdout ? h.collected.stdout.readFrom(0).text : '') || ''
        resolve(out.indexOf('"ok"') >= 0)
      }, () => resolve(false))
    }), () => false)
  }

  /** Capture one helper process's stdout text (rejects on spawn failure). */
  runCapture(argv) {
    return new Promise((resolve, reject) => {
      let h
      try {
        h = this.ctx.subprocess.spawn({
          argv,
          cwd: this.CFG.llamaDir,
          stdio: { stdin: 'ignore', stdout: { maxBytes: 65536 }, stderr: { maxBytes: 65536 } },
          graceMs: 5000,
        })
      } catch (e) {
        reject(e)
        return
      }
      h.done.then(
        () => resolve((h.collected.stdout ? h.collected.stdout.readFrom(0).text : '') || ''),
        reject
      )
    })
  }

  /**
   * Resolve the llama-server PID by asking the OS which process LISTENs on
   * the configured port. The upgraded DSH subprocess handle keeps the child's
   * identity provider-private (SubprocessHandle no longer exposes a pid
   * field, and SubprocessOutcome carries only exit facts), so the port —
   * which the start path just verified free — is the reliable marker: the
   * listener on it IS the server we spawned. Returns null when the OS query
   * is unavailable; the card then simply omits the PID.
   */
  async resolveServerPid() {
    try {
      if (process.platform === 'win32') {
        // Locale-independent primary: PowerShell TCP-table query.
        try {
          const ps = await this.ctx.subprocess.resolveExecutable('powershell')
          const out = await this.runCapture([ps, '-NoProfile', '-NonInteractive', '-Command',
            '(Get-NetTCPConnection -LocalPort ' + this.CFG.port + ' -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess'])
          const n = parseInt(String(out).trim(), 10)
          if (Number.isInteger(n) && n > 0) return n
        } catch (e) { /* fall through to netstat */ }
        // Fallback: netstat -ano (its LISTENING state word is English on the
        // vast majority of locales; PowerShell above covers the rest).
        const netstat = await this.ctx.subprocess.resolveExecutable('netstat')
        const out = await this.runCapture([netstat, '-ano', '-p', 'tcp'])
        const m = new RegExp(':' + this.CFG.port + '\\s+\\S+\\s+LISTENING\\s+(\\d+)').exec(String(out))
        if (m) {
          const n = parseInt(m[1], 10)
          if (Number.isInteger(n) && n > 0) return n
        }
      } else {
        try {
          const lsof = await this.ctx.subprocess.resolveExecutable('lsof')
          const out = await this.runCapture([lsof, '-t', '-i', 'TCP:' + this.CFG.port, '-s', 'TCP:LISTEN'])
          const n = parseInt(String(out).trim().split(/\s+/)[0], 10)
          if (Number.isInteger(n) && n > 0) return n
        } catch (e) { /* no lsof: PID stays null */ }
      }
    } catch (e) {
      this.note('pid resolve failed', e)
    }
    return null
  }

  /**
   * Sync the shared DSH provider (llm-pi-ai.providers.dsh-local) with the
   * CURRENT effective config: baseURL port, authorization header (API key),
   * and — when the running slot's model entry exists — its contextWindow from
   * the active parameter group. Runs on every ready transition; changing the
   * card's port/key just needs a stop+start, and the configurable-provider
   * directory updates live (no DSH restart). Never creates the provider:
   * registration is the card's「添加到模型列表」button only. Model id/name are
   * left alone — the match key is the running slot's derived alias, so a
   * rename on the models page survives the sync.
   */
  syncProviderConfig() {
    const sl = this.CFG.slots[this.slot]
    const rows = sl && sl.presets[this.mode + ':' + this.preset]
    if (!sl || !rows) return
    const ctxValue = argValue(rows, '-c')
    const write = async () => {
      const desc = this.ctx.settings.describe().find((d) => d.ns === this.CFG.settingsNs)
      if (!desc) { this.note('provider sync: namespace ' + this.CFG.settingsNs + ' not registered'); return }
      const current = (desc.value && typeof desc.value === 'object'
        && desc.value.providers && typeof desc.value.providers === 'object'
        && !Array.isArray(desc.value.providers)) ? desc.value.providers : {}
      const providers = Object.assign({}, current)
      const provider = providers[PROVIDER_KEY]
      if (!provider || typeof provider !== 'object') { this.note('provider sync: missing provider ' + PROVIDER_KEY + ' (press「添加到模型列表」)'); return }
      const changes = []
      const newBase = 'http://127.0.0.1:' + this.CFG.port + '/v1'
      if (provider.baseURL !== newBase) { provider.baseURL = newBase; changes.push('baseURL=' + newBase) }
      const expectedAuth = 'Bearer ' + (this.CFG.apiKey || 'dsh-local-llm')
      const curHeaders = (provider.headers && typeof provider.headers === 'object') ? provider.headers : {}
      if (curHeaders.authorization !== expectedAuth) {
        provider.headers = Object.assign({}, curHeaders, { authorization: expectedAuth })
        changes.push('authorization header ' + expectedAuth)
      }
      if (sl.alias) {
        const models = provider.models
        if (Array.isArray(models)) {
          const entry = models.find((m) => m && m.id === sl.alias)
          if (entry) {
            if (ctxValue && entry.contextWindow !== Number(ctxValue)) { entry.contextWindow = Number(ctxValue); changes.push('contextWindow=' + ctxValue) }
          } else {
            this.note('provider sync: ' + PROVIDER_KEY + ' has no model id "' + sl.alias + '" — press「添加到模型列表」after changing the slot model file')
          }
        } else {
          this.note('provider sync: ' + PROVIDER_KEY + ' models shape unexpected; skipped')
        }
      }
      if (!changes.length) return
      await this.ctx.settings.mutate(this.CFG.settingsNs, [{ op: 'set', path: ['providers'], value: providers }], desc.revision)
      console.log('[local-llm] provider synced (' + PROVIDER_KEY + '): ' + changes.join(', '))
    }
    write().catch((e) => this.note('provider sync failed', e))
  }

  startSlot(m, mo, p) {
    if (this.starting || this.status === 'starting' || this.status === 'ready' || this.status === 'stopping') return
    this.CFG = this.resolveConfig() // re-read card/installer config before each launch
    if (!this.CFG.llamaDir) {
      this.status = 'error'
      this.lastError = '未配置 llama.cpp 目录（卡片「配置」区必填）'
      return
    }
    let argv
    try {
      argv = this.buildArgv(m, mo, p)
    } catch (e) {
      this.status = 'error'
      this.lastError = '模型文件解析失败: ' + ((e && e.message) || String(e))
      return
    }
    if (!argv) {
      this.status = 'error'
      this.lastError = '模槽 ' + m + ' 无可用的启动参数（' + mo + '/' + p + '）'
      return
    }
    console.log('[local-llm] spawn argv: ' + argv.join(' '))
    this.starting = true
    this.slot = m
    this.mode = mo
    this.preset = p
    this.lastError = null
    this.logTail = ''
    this.serverPid = null
    this.probeHealth().then((occupied) => {
      if (occupied) {
        this.status = 'error'
        this.lastError = '端口 ' + this.CFG.port + ' 已有服务在运行（/health 返回 ok）'
        return
      }
      let h
      try {
        h = this.ctx.subprocess.spawn({
          argv,
          cwd: this.CFG.llamaDir,
          stdio: { stdin: 'ignore', stdout: { maxBytes: 65536 }, stderr: { maxBytes: 65536 } },
          graceMs: 8000,
        })
      } catch (e) {
        this.status = 'error'
        this.lastError = '启动失败: ' + ((e && e.message) || String(e))
        return
      }
      this.proc = h
      this.status = 'starting'
      h.done.then((out) => {
        if (this.status === 'starting') {
          this.fail('llama-server 提前退出 (exit=' + out.exitCode + ', signal=' + out.signal + ')')
        } else if (this.status === 'ready') {
          this.status = 'stopped'
          this.proc = null
          this.lastError = 'llama-server 已退出 (exit=' + out.exitCode + ')'
        }
      }, () => { /* noop */ })
      this.beginPolling()
    }).catch((e) => {
      this.status = 'error'
      this.lastError = '启动流程异常: ' + ((e && e.message) || String(e))
    }).finally(() => { this.starting = false })
  }

  beginPolling() {
    this.stopPolling()
    let busy = false
    let elapsed = 0
    this.pollHandle = this.ctx.timer.interval(() => {
      if (busy || this.status !== 'starting') return
      busy = true
      this.probeHealth().then((ok) => {
        busy = false
        if (this.status !== 'starting') return
        elapsed += POLL_MS
        if (ok) {
          this.stopPolling()
          this.status = 'ready'
          this.syncProviderConfig()
          // The subprocess handle no longer exposes the child's pid — resolve
          // it from the port listener so the card shows a real PID instead of
          // null. The card sees it on its next getState poll.
          this.resolveServerPid().then((pid) => {
            if (pid != null && this.status === 'ready' && this.proc) {
              this.serverPid = pid
            }
          }).catch(() => {})
        } else if (elapsed >= READY_TIMEOUT_MS) {
          this.fail('启动超时（' + (READY_TIMEOUT_MS / 1000) + 's 未就绪）')
        }
      })
    }, POLL_MS)
  }
}

// Pure-JS replacement for the `Remote` decorator (see markRemote above):
// the Gateway's source-mode discovery reads these markers off the prototype.
markRemote(LocalLlmService.prototype, [
  'getState',
  'start',
  'stop',
  'saveConfig',
  'listSlotFiles',
  'addProviders',
])

export default LocalLlmService
