/**
 * Local LLM Controller — Host half.
 *
 * Manages a llama-server child process for Qwen3.6-35B / Qwen3.5-9B
 * (vision/text × fast/long-context presets) and publishes its state through
 * the `local-llm` settings namespace, which also carries the action channel:
 *
 *   Client writes  { action: 'start'|'stop', model, mode, preset }  via
 *                   settingsScope
 *   Host listens to `settings/updated`, executes the action, clears it, and
 *   writes back { status, pid, lastError, logTail, action: null }.
 *
 * No private RPC is needed: the settings seam is the state/action bus.
 * Parameters match bat35_utf8.txt / bat9_utf8.txt /
 * docs/local-model-invocation.md §2 §7.
 *
 * Machine-specific values (llama.cpp dir, port, API key, model file paths,
 * provider keys) are NOT hardcoded here — they come from two sources, merged
 * over the defaults below (file config wins over settings config):
 *
 *   1. `~/.dsh/local-llm.config.json` — optional legacy file (pre-card config),
 *      e.g. { "llamaDir": "F:/llama.cpp", "port": 55555, "apiKey": "" }
 *   2. the `local-llm.config` section of settings.yaml — the card form writes
 *      here; it is the primary config surface.
 *
 * Config is re-read on every start (card edits apply to the next launch).
 * The DSH provider entries (llm-pi-ai.providers) are written ONLY by the
 * card's「添加到模型列表」button — no background bootstrap since v1.0.6.
 */

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

export const name = 'local-llm-controller'

export const inject = ['settings', 'timer', 'subprocess']

export function apply(ctx) {
  // ---- config defaults (overridable via local-llm.config.json / settings.yaml) ----
  const DEF = {
    llamaDir: '', // author-machine path removed — fresh users must set it in the card
    serverExe: 'llama-server.exe', // linux/mac: llama-server
    port: 55555, // random 5-digit default; override via config if taken
    apiKey: '', // empty = no auth (127.0.0.1 loopback only); set to require a key
    settingsNs: 'llm-pi-ai', // namespace holding the DSH providers
    curlPath: null, // auto-detect; set to override
    server: {
      ngl: 99, // GPU layers; 0 for CPU-only builds
      threads: 20,
      batchThreads: 20,
      parallel: 1,
    },
    models: {
      '35b': {
        dir: '{llamaDir}/qwen3.6-35B-A3B', // folder containing model GGUF + mmproj
        alias: 'qwen3.6-35b-a3b',
        providerKey: 'qwen36-local',
      },
      '9b': {
        dir: '{llamaDir}/qwen3.5-9B',
        alias: 'qwen3.5-9b',
        providerKey: 'qwen35-local',
      },
    },
  }
  const READY_TIMEOUT_MS = 90000
  const POLL_MS = 2000

  // ---- settings namespace (state/action bus) ----
  const localSchema = (v) => {
    const src = (v && typeof v === 'object' && !Array.isArray(v)) ? v : {}
    return {
      model: src.model === '9b' ? '9b' : '35b',
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

  // ---- merge user config over defaults ----
  // sources: settings.yaml `local-llm.config` (advanced) + ~/.dsh/local-llm.config.json (installer)
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
  // ---- merge user config over defaults (re-evaluated on every start) ----
  // sources: settings.yaml `local-llm.config` (card UI writes here) +
  // ~/.dsh/local-llm.config.json (installer), file config wins per key.
  function resolveConfig() {
    const savedNow = scope.get()
    const yamlCfg = (savedNow && savedNow.config && typeof savedNow.config === 'object') ? savedNow.config : {}
    const fileCfg = readFileConfig() || {}
    const u = Object.assign({}, yamlCfg, fileCfg) // file config wins
    const serverCfg = Object.assign({}, DEF.server, (u.server && typeof u.server === 'object') ? u.server : {})
    const llamaDir = u.llamaDir || DEF.llamaDir
    const resolvePath = (s) => s.replace(/\{llamaDir\}/g, llamaDir)
    const modCfg = {}
    for (const key of ['35b', '9b']) {
      const d = DEF.models[key]
      const o = (u.models && u.models[key] && typeof u.models[key] === 'object') ? u.models[key] : {}
      // Until llamaDir is set keep the template visible in the card form
      // (e.g. "{llamaDir}/qwen3.6-35B-A3B") instead of a path starting with "/".
      const defaultDir = llamaDir ? resolvePath(d.dir) : d.dir
      modCfg[key] = {
        dir: o.dir ? resolvePath(o.dir) : defaultDir,
        alias: o.alias || d.alias,
        providerKey: o.providerKey || d.providerKey,
      }
    }
    return {
      llamaDir,
      serverExe: u.serverExe || DEF.serverExe,
      port: Number.isInteger(u.port) ? u.port : DEF.port,
      apiKey: typeof u.apiKey === 'string' ? u.apiKey : DEF.apiKey,
      settingsNs: u.settingsNs || DEF.settingsNs,
      curlPath: typeof u.curlPath === 'string' && u.curlPath ? u.curlPath : null,
      server: serverCfg,
      models: modCfg,
    }
  }
  let CFG = resolveConfig()

  // ---- model catalogue (35b: bat35_utf8 §7 presets; 9b: bat9_utf8) ----
  // file/mmproj/alias/providerKey come from CFG (re-resolved per start);
  // the rest is model behaviour fixed by the validated bat parameters.
  const MODELS = {
    '35b': {
      vision: true,
      fa: 'on',
      moeMode: true,
      sampling: { temp: '1.0', topK: '20', topP: '0.95', minP: '0.0' },
      reasoningBudget: '2048',
      presets: {
        'text:fast':   { ctx: 32768,  moe: 20 },
        'text:long':   { ctx: 131072, moe: 22 },
        'vision:fast': { ctx: 32768,  moe: 24, mmproj: true },
        'vision:long': { ctx: 98304,  moe: 24, mmproj: true },
      },
    },
    '9b': {
      vision: true,
      fa: 'auto',
      moeMode: false,
      sampling: { temp: '0.8', topK: '40', topP: '0.95', minP: '0.05' },
      reasoningBudget: null,
      presets: {
        'text:fast':   { ctx: 32768, mmproj: false },
        'text:long':   { ctx: 65536, mmproj: false },
        'vision:fast': { ctx: 32768, mmproj: true },
        'vision:long': { ctx: 65536, mmproj: true },
      },
    },
  }

  // ---- state ----
  let model = '35b'
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
    model = saved.model
    mode = saved.mode
    preset = saved.preset
  }

  function note(tag, e) {
    const msg = tag + ': ' + ((e && e.message) || String(e))
    console.log('[local-llm] ' + msg)
  }

  function publishState() {
    const patch = {
      model,
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
   * Resolve the GGUF files inside one model folder: the vision projector is the
   * file whose name contains "mmproj"; the model is any other .gguf. File names
   * don't matter (quant labels, "Uncensored" suffixes, ...). Throws on failure.
   */
  function resolveModelFiles(key) {
    const dir = CFG.models[key].dir
    if (!dir) throw new Error('未配置模型文件夹（models.' + key + '.dir）')
    let names
    try {
      names = fs.readdirSync(dir)
    } catch (e) {
      throw new Error('模型文件夹不存在: ' + dir)
    }
    const ggufs = names.filter((n) => /\.gguf$/i.test(n)).sort()
    if (!ggufs.length) throw new Error('模型文件夹中没有 .gguf 文件: ' + dir)
    const mmproj = ggufs.find((n) => /mmproj/i.test(n))
    const model = ggufs.find((n) => !/mmproj/i.test(n))
    if (!model) throw new Error('模型文件夹中找不到模型 GGUF（只有一个 mmproj?）: ' + dir)
    return {
      file: dir + '/' + model,
      mmproj: mmproj ? dir + '/' + mmproj : null,
    }
  }

  function buildArgv(m, mo, p) {
    const M = MODELS[m]
    if (!M) return null
    const key = mo + ':' + p
    const pr = M.presets[key]
    if (!pr) return null
    let files
    try {
      files = resolveModelFiles(m)
    } catch (e) {
      throw e
    }
    const argv = [CFG.llamaDir + '/' + CFG.serverExe, '-m', files.file]
    if (M.vision && pr.mmproj && files.mmproj) argv.push('--mmproj', files.mmproj, '--image-min-tokens', '1024')
    argv.push('-a', CFG.models[m].alias, '--port', String(CFG.port), '--host', '127.0.0.1')
    if (CFG.apiKey) argv.push('--api-key', CFG.apiKey)
    argv.push('-ngl', String(CFG.server.ngl), '-fa', M.fa,
      '-t', String(CFG.server.threads), '-tb', String(CFG.server.batchThreads),
      '-np', String(CFG.server.parallel))
    argv.push('--cache-type-k', 'q8_0', '--cache-type-v', 'q8_0')
    if (M.moeMode) argv.push('-ncmoe', String(pr.moe))
    if (M.reasoningBudget) argv.push('--reasoning-budget', M.reasoningBudget)
    argv.push('--temp', M.sampling.temp, '--top-k', M.sampling.topK, '--top-p', M.sampling.topP, '--min-p', M.sampling.minP)
    argv.push('-c', String(pr.ctx), '--metrics', '--slots')
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
   * Write (upsert) both model providers into llm-pi-ai from the CURRENT
   * effective config — port, key and model entries included. Triggered ONLY
   * by the card's「添加到模型列表」button (no background/auto writes; the
   * configurable-provider directory updates live, no DSH restart).
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
      for (const key of ['35b', '9b']) {
        const M = MODELS[key]
        const mc = CFG.models[key]
        if (!M || !mc) continue
        providers[mc.providerKey] = {
          displayName: key === '35b' ? 'Qwen3.6-35B-A3B Local' : 'Qwen3.5-9B Local',
          api: 'openai-completions',
          baseURL: 'http://127.0.0.1:' + CFG.port + '/v1',
          headers: { authorization: 'Bearer ' + (CFG.apiKey || 'dsh-local-llm') },
          defaultInput: ['text', 'image'],
          reasoning: 'high',
          models: [{
            id: mc.alias,
            name: key === '35b' ? 'Qwen3.6-35B-A3B' : 'Qwen3.5-9B',
            contextWindow: 32768,
            maxTokens: key === '35b' ? 12288 : 8192,
            reasoningEfforts: { off: 'none', high: 'high' },
          }],
        }
        writes.push(mc.providerKey)
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
   * Sync the active model's DSH provider (llm-pi-ai.providers.<key>) with the
   * CURRENT effective config: baseURL port, authorization header (API key),
   * and the preset's contextWindow. Runs on every ready transition — changing
   * the card's port/key just needs a stop+start, and the configurable-provider
   * directory updates live (no DSH restart). Never creates a missing provider:
   * registration is the card's「添加到模型列表」button only.
   */
  function syncProviderConfig() {
    const mc = CFG.models[model]
    const M = MODELS[model]
    const key = mode + ':' + preset
    const pr = M && M.presets[key]
    if (!M || !pr || !mc) return
    try {
      const desc = ctx.settings.describe().find((d) => d.ns === CFG.settingsNs)
      if (!desc) { note('provider sync: namespace ' + CFG.settingsNs + ' not registered'); return }
      const section = (desc.user && typeof desc.user === 'object') ? desc.user : { providers: {} }
      const providers = (section.providers && typeof section.providers === 'object' && !Array.isArray(section.providers))
        ? section.providers
        : {}
      if (providers !== section.providers) section.providers = providers
      const provider = providers[mc.providerKey]
      if (!provider || typeof provider !== 'object') { note('provider sync: missing provider ' + mc.providerKey); return }
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
        if (models[0].contextWindow !== pr.ctx) { models[0].contextWindow = pr.ctx; changes.push('contextWindow=' + pr.ctx) }
      } else {
        note('provider sync: ' + mc.providerKey + ' models shape unexpected; skipped')
      }
      if (!changes.length) return
      ctx.settings.replace(CFG.settingsNs, section)
        .then(() => console.log('[local-llm] provider synced (' + mc.providerKey + '): ' + changes.join(', ')))
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
      lastError = '模型 ' + m + ' 不支持 ' + mo + '/' + p + ' 组合'
      publishState()
      return
    }
    starting = true
    model = m
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
  // model bubble click → scope.set('model', ...) — re-delivered the action and
  // re-ran the branch. The clear write re-enters this handler with
  // action === null and is a no-op by design.
  ctx.on('settings/updated', (ns, next) => {
    if (ns !== 'local-llm') return
    const action = next && next.action
    if (action === 'start') {
      const m = next.model === '9b' ? '9b' : '35b'
      const mo = next.mode === 'vision' ? 'vision' : 'text'
      const p = next.preset === 'long' ? 'long' : 'fast'
      start(m, mo, p)
    } else if (action === 'add-providers') {
      syncProvidersToDsh()
    } else if (action === 'stop') {
      stop()
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
