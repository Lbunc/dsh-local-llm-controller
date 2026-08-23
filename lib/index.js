/**
 * Local LLM Controller — Host half.
 *
 * Manages a llama-server child process for TWO model SLOTS (A/B) — each slot is
 * a model folder plus a chosen GGUF and its own eight launch-parameter groups
 * (text/vision × fast/long-context) — and publishes its state through the
 * `local-llm` settings namespace, which also carries the action channel:
 *
 *   Client writes  { action: 'start'|'stop', model: 'a'|'b', mode, preset }
 *   Host listens to `settings/updated`, executes the action, clears it, and
 *   writes back { status, pid, lastError, logTail, action: null }.
 *
 * No private RPC is needed: the settings seam is the state/action bus.
 * Model-behaviour parameters are NOT hardcoded (no 35B/9B catalogue): each
 * launch uses the parameter-group rows the user edited in the card; the
 * README carries the recommended parameter sets for the validated models.
 * Automatic arguments: -m, -a (alias), --port, --host, --api-key, and — when
 * the started mode is vision — --mmproj + --image-min-tokens from the same
 * folder's mmproj file.
 *
 * Machine-specific values (llama.cpp dir, port, API key, model folders,
 * provider keys) are NOT hardcoded either — they live in the
 * `local-llm.config` section of settings.yaml (the card form):
 *   { llamaDir, port, apiKey, slots: { a/b: { dir, file, alias, providerKey,
 *     presets: { 'text:fast'|'text:long'|'vision:fast'|'vision:long':
 *       [{ flag, value }, ...] } } } }
 * Config is re-read on every start (card edits apply to the next launch).
 * The DSH provider entries (llm-pi-ai.providers) are written ONLY by the
 * card's「添加到模型列表」button — no background bootstrap since v1.0.6.
 */

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

export const name = 'local-llm-controller'

export const inject = ['settings', 'timer', 'subprocess']

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

/** Normalize a raw presets object to all eight groups, prefilling templates. */
export function normalizePresets(raw) {
  const out = {}
  for (const g of PRESET_GROUPS) {
    const rows = (raw && raw[g] && Array.isArray(raw[g])) ? raw[g] : null
    out[g] = (rows && rows.length) ? rows.map(normalizeArgRow).filter(Boolean) : defaultPresetArgs(g)
  }
  return out
}

/** Find the value of a flag (e.g. -c) inside parameter rows; null when absent. */
export function argValue(rows, flag) {
  if (!Array.isArray(rows)) return null
  for (const r of rows) if (r && r.flag === flag) return r.value || null
  return null
}

export function apply(ctx) {
  // ---- config defaults ----
  const DEF = {
    llamaDir: '', // author-machine path removed — fresh users must set it in the card
    serverExe: 'llama-server.exe', // linux/mac: llama-server
    port: 55555, // random 5-digit default; override via config if taken
    apiKey: '', // empty = no auth (127.0.0.1 loopback only); set to require a key
    settingsNs: 'llm-pi-ai', // namespace holding the DSH providers
    curlPath: null, // auto-detect; set to override
  }
  const READY_TIMEOUT_MS = 90000
  const POLL_MS = 2000

  // ---- settings namespace (state/action bus) ----
  const localSchema = (v) => {
    const src = (v && typeof v === 'object' && !Array.isArray(v)) ? v : {}
    return {
      slot: src.slot === 'b' ? 'b' : 'a',
      mode: src.mode === 'vision' ? 'vision' : 'text',
      preset: src.preset === 'long' ? 'long' : 'fast',
      status: typeof src.status === 'string' ? src.status : 'stopped',
      pid: typeof src.pid === 'number' ? src.pid : null,
      action: (src.action === 'start' || src.action === 'stop' || src.action === 'add-providers') ? src.action : null,
      lastError: typeof src.lastError === 'string' ? src.lastError : null,
      logTail: typeof src.logTail === 'string' ? src.logTail : null,
      config: (src.config && typeof src.config === 'object') ? src.config : undefined,
    }
  }
  localSchema.toJSON = () => ({ type: 'object', dict: {} })

  const scope = ctx.settings.register('local-llm', localSchema)
  const saved = scope.get()

  // ---- user config: settings.yaml local-llm.config + ~/.dsh/local-llm.config.json ----
  function readFileConfig() {
    try {
      const p = path.join(process.env.DSH_HOME || path.join(os.homedir(), '.dsh'), 'local-llm.config.json')
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

  function resolveConfig() {
    const savedNow = scope.get()
    const yamlCfg = (savedNow && savedNow.config && typeof savedNow.config === 'object') ? savedNow.config : {}
    const fileCfg = readFileConfig() || {}
    const u = Object.assign({}, yamlCfg, fileCfg) // file config wins
    const llamaDir = u.llamaDir || DEF.llamaDir
    const resolvePath = (s) => s.replace(/\{llamaDir\}/g, llamaDir)
    const slots = {}
    for (const key of ['a', 'b']) {
      const o = (u.slots && u.slots[key] && typeof u.slots[key] === 'object') ? u.slots[key] : {}
      const dir = o.dir ? resolvePath(o.dir) : ''
      const file = typeof o.file === 'string' ? o.file : ''
      let alias = typeof o.alias === 'string' ? o.alias : ''
      let providerKey = typeof o.providerKey === 'string' ? o.providerKey : ''
      if (!alias && file) {
        const d = deriveModelNames(file)
        alias = d.alias
        providerKey = providerKey || d.providerKey
      }
      slots[key] = {
        dir,
        file,
        files: listModelFiles(dir),
        alias,
        providerKey,
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
  let CFG = resolveConfig()

  // ---- state ----
  let slot = 'a'
  let status = 'stopped' // stopped | starting | ready | stopping | error
  let mode = 'text'
  let preset = 'fast'
  let proc = null
  let pollHandle = null
  let starting = false
  let lastError = null
  let logTail = ''
  let curlPath = null

  if (saved) {
    slot = saved.slot
    mode = saved.mode
    preset = saved.preset
  }

  function note(tag, e) {
    const msg = tag + ': ' + ((e && e.message) || String(e))
    console.log('[local-llm] ' + msg)
  }

  function publishState() {
    const patch = {
      slot,
      mode,
      preset,
      status,
      pid: proc ? proc.pid : null,
      action: null,
      lastError,
      logTail: logTail.slice(-2000),
      config: CFG, // current effective config, lets the card render its form
    }
    scope.update(patch).catch((e) => note('state publish failed', e))
  }

  // ---- subprocess helpers ----
  /**
   * Resolve the GGUF files inside one slot's model folder: the vision
   * projector is the file whose name contains "mmproj"; the model is the
   * user-chosen file (config `slots.<key>.file`, a filename inside the folder)
   * when it exists in the folder, otherwise the first non-mmproj .gguf.
   * Throws on failure.
   */
  function resolveModelFiles(key) {
    const dir = CFG.slots[key].dir
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
    const chosen = CFG.slots[key].file
    const model = (chosen && ggufs.indexOf(chosen) >= 0 && !/mmproj/i.test(chosen)) ? chosen : ggufs.find((n) => !/mmproj/i.test(n))
    if (!model) throw new Error('模型文件夹中找不到模型 GGUF（只有一个 mmproj?）: ' + dir)
    return {
      file: dir + '/' + model,
      mmproj: mmproj ? dir + '/' + mmproj : null,
    }
  }

  function buildArgv(slotKey, mo, p) {
    const sl = CFG.slots[slotKey]
    if (!sl) return null
    const rows = sl.presets[mo + ':' + p]
    if (!rows) return null
    let files
    try {
      files = resolveModelFiles(slotKey)
    } catch (e) {
      throw e
    }
    const argv = [CFG.llamaDir + '/' + CFG.serverExe, '-m', files.file]
    // vision mode auto-wires the folder's mmproj, if present
    if (mo === 'vision' && files.mmproj) argv.push('--mmproj', files.mmproj, '--image-min-tokens', '1024')
    argv.push('-a', sl.alias || ('slot-' + slotKey), '--port', String(CFG.port), '--host', '127.0.0.1')
    if (CFG.apiKey) argv.push('--api-key', CFG.apiKey)
    for (const r of rows) {
      argv.push(r.flag)
      if (r.value) argv.push(r.value)
    }
    return argv
  }

  function readLogTail() {
    let t = ''
    if (proc) {
      try { if (proc.collected.stderr) t += proc.collected.stderr.readFrom(0).text } catch (e) { /* noop */ }
      try { if (proc.collected.stdout) t += proc.collected.stdout.readFrom(0).text } catch (e) { /* noop */ }
    }
    return t
  }

  function stopPolling() {
    if (pollHandle) { try { pollHandle() } catch (e) { /* noop */ } pollHandle = null }
  }

  function fail(reason) {
    status = 'error'
    lastError = reason
    logTail = readLogTail()
    stopPolling()
    if (proc) { try { proc.terminate() } catch (e) { /* noop */ } }
    publishState()
  }

  async function resolveCurl() {
    if (curlPath) return curlPath
    if (CFG.curlPath) { curlPath = CFG.curlPath; return curlPath }
    try {
      curlPath = await ctx.subprocess.resolveExecutable('curl')
    } catch (e) {
      curlPath = process.platform === 'win32' ? 'C:/Windows/System32/curl.exe' : 'curl'
    }
    return curlPath
  }

  function probeHealth() {
    return resolveCurl().then((curl) => new Promise((resolve) => {
      let h
      const argv = [curl, '-s', '-m', '3']
      if (CFG.apiKey) argv.push('-H', 'Authorization: Bearer ' + CFG.apiKey)
      argv.push('http://127.0.0.1:' + CFG.port + '/health')
      try {
        h = ctx.subprocess.spawn({
          argv,
          cwd: CFG.llamaDir,
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

  /**
   * Write (upsert) both SLOT providers into llm-pi-ai from the CURRENT
   * effective config — port, key and model entries included, names derived
   * from each slot's chosen GGUF. Triggered ONLY by the card's
   * 「添加到模型列表」button (no background/auto writes; the configurable-
   * provider directory updates live, no DSH restart).
   *
   * The provider always carries an `authorization` header: pi-ai's
   * OpenAI-completions client refuses any request without an API key or an
   * Authorization header, even when the server itself accepts unauthenticated
   * requests (getClientApiKey in @earendil-works/pi-ai). With no card key a
   * harmless placeholder is used; llama-server ignores it unless it was
   * started with a matching --api-key.
   */
  function syncProvidersToDsh() {
    try {
      const desc = ctx.settings.describe().find((d) => d.ns === CFG.settingsNs)
      if (!desc) {
        note('add-providers: namespace ' + CFG.settingsNs + ' not registered')
        return
      }
      // Fresh installs have no stored section at all — build a minimal one.
      const section = (desc.user && typeof desc.user === 'object')
        ? desc.user
        : { providers: {} }
      const providers = (section.providers && typeof section.providers === 'object' && !Array.isArray(section.providers))
        ? section.providers
        : {}
      if (providers !== section.providers) section.providers = providers
      const writes = []
      for (const key of ['a', 'b']) {
        const sl = CFG.slots[key]
        if (!sl || !sl.providerKey) continue
        const name = sl.alias || ('Slot ' + key.toUpperCase())
        const ctxValue = argValue(sl.presets['text:fast'], '-c')
        providers[sl.providerKey] = {
          displayName: name + ' Local',
          api: 'openai-completions',
          baseURL: 'http://127.0.0.1:' + CFG.port + '/v1',
          headers: { authorization: 'Bearer ' + (CFG.apiKey || 'dsh-local-llm') },
          defaultInput: ['text', 'image'],
          reasoning: 'high',
          models: [{
            id: name,
            name,
            contextWindow: ctxValue ? Number(ctxValue) : 32768,
            maxTokens: 8192,
            reasoningEfforts: { off: 'none', high: 'high' },
          }],
        }
        writes.push(sl.providerKey)
      }
      if (!writes.length) return
      ctx.settings.replace(CFG.settingsNs, section)
        .then(() => console.log('[local-llm] add-providers: wrote ' + writes.join(', ') + ' into ' + CFG.settingsNs + ' (models page updates live)'))
        .catch((e) => note('add-providers failed', e))
    } catch (e) {
      note('add-providers threw', e)
    }
  }

  /**
   * Sync the active slot's DSH provider (llm-pi-ai.providers.<key>) with the
   * CURRENT effective config: baseURL port, authorization header (API key),
   * and the active parameter group's contextWindow. Runs on every ready
   * transition — changing the card's port/key just needs a stop+start, and
   * the configurable-provider directory updates live (no DSH restart). Never
   * creates a missing provider: registration is the card's「添加到模型列表」button only.
   */
  function syncProviderConfig() {
    const sl = CFG.slots[slot]
    const rows = sl && sl.presets[mode + ':' + preset]
    if (!sl || !sl.providerKey || !rows) return
    const ctxValue = argValue(rows, '-c')
    try {
      const desc = ctx.settings.describe().find((d) => d.ns === CFG.settingsNs)
      if (!desc) { note('provider sync: namespace ' + CFG.settingsNs + ' not registered'); return }
      const section = (desc.user && typeof desc.user === 'object') ? desc.user : { providers: {} }
      const providers = (section.providers && typeof section.providers === 'object' && !Array.isArray(section.providers))
        ? section.providers
        : {}
      if (providers !== section.providers) section.providers = providers
      const provider = providers[sl.providerKey]
      if (!provider || typeof provider !== 'object') { note('provider sync: missing provider ' + sl.providerKey); return }
      const newBase = 'http://127.0.0.1:' + CFG.port + '/v1'
      const changes = []
      if (provider.baseURL !== newBase) { provider.baseURL = newBase; changes.push('baseURL=' + newBase) }
      const expectedAuth = 'Bearer ' + (CFG.apiKey || 'dsh-local-llm')
      const curHeaders = (provider.headers && typeof provider.headers === 'object') ? provider.headers : {}
      if (curHeaders.authorization !== expectedAuth) {
        provider.headers = Object.assign({}, curHeaders, { authorization: expectedAuth })
        changes.push('authorization header ' + expectedAuth)
      }
      const models = provider.models
      if (Array.isArray(models) && models[0]) {
        if (models[0].id !== sl.alias) { models[0].id = sl.alias; models[0].name = sl.alias; changes.push('model id=' + sl.alias) }
        if (ctxValue && models[0].contextWindow !== Number(ctxValue)) { models[0].contextWindow = Number(ctxValue); changes.push('contextWindow=' + ctxValue) }
      } else {
        note('provider sync: ' + sl.providerKey + ' models shape unexpected; skipped')
      }
      if (!changes.length) return
      ctx.settings.replace(CFG.settingsNs, section)
        .then(() => console.log('[local-llm] provider synced (' + sl.providerKey + '): ' + changes.join(', ')))
        .catch((e) => note('provider sync failed', e))
    } catch (e) {
      note('provider sync threw', e)
    }
  }

  function start(m, mo, p) {
    if (starting || status === 'starting' || status === 'ready' || status === 'stopping') return
    CFG = resolveConfig() // re-read card/installer config before each launch
    if (!CFG.llamaDir) {
      status = 'error'
      lastError = '未配置 llama.cpp 目录（卡片「配置」区必填）'
      publishState()
      return
    }
    let argv
    try {
      argv = buildArgv(m, mo, p)
    } catch (e) {
      status = 'error'
      lastError = '模型文件解析失败: ' + ((e && e.message) || String(e))
      publishState()
      return
    }
    if (!argv) {
      status = 'error'
      lastError = '模槽 ' + m + ' 无可用的启动参数（' + mo + '/' + p + '）'
      publishState()
      return
    }
    starting = true
    slot = m
    mode = mo
    preset = p
    lastError = null
    logTail = ''
    probeHealth().then((occupied) => {
      if (occupied) {
        status = 'error'
        lastError = '端口 ' + CFG.port + ' 已有服务在运行（/health 返回 ok）'
        publishState()
        return
      }
      let h
      try {
        h = ctx.subprocess.spawn({
          argv,
          cwd: CFG.llamaDir,
          stdio: { stdin: 'ignore', stdout: { maxBytes: 65536 }, stderr: { maxBytes: 65536 } },
          graceMs: 8000,
        })
      } catch (e) {
        status = 'error'
        lastError = '启动失败: ' + ((e && e.message) || String(e))
        publishState()
        return
      }
      proc = h
      status = 'starting'
      publishState()
      h.done.then((out) => {
        if (status === 'starting') {
          fail('llama-server 提前退出 (exit=' + out.exitCode + ', signal=' + out.signal + ')')
        } else if (status === 'ready') {
          status = 'stopped'
          proc = null
          lastError = 'llama-server 已退出 (exit=' + out.exitCode + ')'
          publishState()
        }
      }, () => { /* noop */ })
      beginPolling()
    }).catch((e) => {
      status = 'error'
      lastError = '启动流程异常: ' + ((e && e.message) || String(e))
      publishState()
    }).finally(() => { starting = false })
  }

  function beginPolling() {
    stopPolling()
    let busy = false
    let elapsed = 0
    pollHandle = ctx.timer.interval(() => {
      if (busy || status !== 'starting') return
      busy = true
      probeHealth().then((ok) => {
        busy = false
        if (status !== 'starting') return
        elapsed += POLL_MS
        if (ok) {
          stopPolling()
          status = 'ready'
          syncProviderConfig()
          publishState()
        } else if (elapsed >= READY_TIMEOUT_MS) {
          fail('启动超时（' + (READY_TIMEOUT_MS / 1000) + 's 未就绪）')
        }
      })
    }, POLL_MS)
  }

  function stop() {
    if (status === 'stopped' || status === 'stopping') return
    status = 'stopping'
    stopPolling()
    const h = proc
    proc = null
    publishState()
    if (!h) {
      status = 'stopped'
      publishState()
      return
    }
    try { h.terminate() } catch (e) { /* noop */ }
    Promise.race([
      h.done.then(() => { status = 'stopped'; publishState() }),
      ctx.timer.timeout(10000).then(() => { if (status === 'stopping') { status = 'stopped'; publishState() } }),
    ])
  }

  // ---- boot state reconciliation ----
  // This process owns no child handle yet; a persisted 'running/starting/
  // stopping' status belongs to the previous DSH session (whose process tree
  // is already gone — DSH shutdown force-terminates what it spawned), so
  // publishing the clean stopped state once reparses the document. Without
  // it the card keeps showing a dead process as running (Start disabled,
  // Stop a no-op, the plugin looks 'broken').
  publishState()

  // ---- action channel ----
  // An action is a one-shot command: once dispatched it is cleared from the
  // raw layer immediately (consume-and-clear). Relying on publishState alone
  // left a stale `action` in the raw layer for branches that never transition
  // start/stop (add-providers), so the very next local-llm commit — e.g. a
  // slot bubble click → scope.set('slot', ...) — re-delivered the action and
  // re-ran the branch. The clear write re-enters this handler with
  // action === null and is a no-op by design.
  ctx.on('settings/updated', (ns, next) => {
    if (ns !== 'local-llm') return
    const action = next && next.action
    if (action === 'start') {
      const m = next.slot === 'b' ? 'b' : 'a'
      const mo = next.mode === 'vision' ? 'vision' : 'text'
      const p = next.preset === 'long' ? 'long' : 'fast'
      start(m, mo, p)
    } else if (action === 'add-providers') {
      syncProvidersToDsh()
    } else if (action === 'stop') {
      stop()
    } else if (next && next.config && typeof next.config === 'object') {
      // Config edit (card「保存配置」): re-resolve the effective config so the
      // enumeration published to the card form (slots.<key>.files) follows the
      // folder the user just saved, then re-publish. The deep compare stops
      // the write-back (publishState → settings/updated → same config) from
      // ping-ponging.
      const fresh = resolveConfig()
      if (JSON.stringify(fresh) !== JSON.stringify(CFG)) {
        CFG = fresh
        publishState()
      }
    }
    if (action === 'start' || action === 'stop' || action === 'add-providers') {
      scope.update({ action: null }).catch((e) => note('action clear failed', e))
    }
  })

  // ---- lifecycle ----
  ctx.effect(() => () => {
    stopPolling()
    if (proc) { try { proc.terminate() } catch (e) { /* noop */ } }
  })
}
