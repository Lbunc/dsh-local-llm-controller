/**
 * Local LLM Controller — Host half.
 *
 * Manages a llama-server child process for Qwen3.6-35B / Qwen3.5-9B
 * (vision/text × fast/long-context presets) and publishes its state through
 * the `local-llm` settings namespace, which also carries the action channel:
 *
 *   Client writes  { action: 'start'|'stop', model, mode, preset }  via
 *                   settingsScope
 *   Host listens to `settings/updated`, executes, and writes back
 *   { status, pid, lastError, logTail, action: null }.
 *
 * No private RPC is needed: the settings seam is the state/action bus.
 * Parameters match bat35_utf8.txt / bat9_utf8.txt /
 * docs/local-model-invocation.md §2 §7.
 *
 * Machine-specific values (llama.cpp dir, port, API key, model file paths,
 * provider keys) are NOT hardcoded here — they come from the
 * `local-llm.config` section of settings.yaml, merged over the defaults
 * below. See README.md → 配置. Config is read at boot; restart DSH to apply.
 */

export const name = 'local-llm-controller'

export const inject = ['settings', 'timer', 'subprocess']

export function apply(ctx) {
  // ---- config defaults (overridable via settings.yaml local-llm.config) ----
  const DEF = {
    llamaDir: 'F:/llama-b10488-bin-win-cuda-13.3-x64',
    serverExe: 'llama-server.exe', // linux/mac: llama-server
    port: 21113,
    apiKey: 'ffsz1122', // must equal the DSH provider's apiKeyEnv value
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
        file: '{llamaDir}/qwen3.6-35B-A3B/Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf',
        mmproj: '{llamaDir}/qwen3.6-35B-A3B/mmproj-Qwen3.6-35B-A3B-Uncensored-f16.gguf',
        alias: 'qwen3.6-35b-a3b',
        providerKey: 'qwen36-local',
      },
      '9b': {
        file: '{llamaDir}/qwen3.5-9B/Qwen3.5-9B-Uncensored-Q4_K_M.gguf',
        mmproj: '{llamaDir}/qwen3.5-9B/mmproj-Qwen3.5-9B-Uncensored-BF16.gguf',
        alias: 'qwen3.5-9b',
        providerKey: 'qwen-local',
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
      action: (src.action === 'start' || src.action === 'stop') ? src.action : null,
      lastError: typeof src.lastError === 'string' ? src.lastError : null,
      logTail: typeof src.logTail === 'string' ? src.logTail : null,
      config: (src.config && typeof src.config === 'object') ? src.config : undefined,
    }
  }
  localSchema.toJSON = () => ({ type: 'object', dict: {} })

  const scope = ctx.settings.register('local-llm', localSchema)
  const saved = scope.get()

  // ---- merge user config over defaults ----
  const u = (saved && saved.config && typeof saved.config === 'object') ? saved.config : {}
  const serverCfg = Object.assign({}, DEF.server, (u.server && typeof u.server === 'object') ? u.server : {})
  const llamaDir = u.llamaDir || DEF.llamaDir
  const resolvePath = (s) => s.replace(/\{llamaDir\}/g, llamaDir)
  const modCfg = {}
  for (const key of ['35b', '9b']) {
    const d = DEF.models[key]
    const o = (u.models && u.models[key] && typeof u.models[key] === 'object') ? u.models[key] : {}
    modCfg[key] = {
      file: o.file ? resolvePath(o.file) : resolvePath(d.file),
      mmproj: o.mmproj ? resolvePath(o.mmproj) : resolvePath(d.mmproj),
      alias: o.alias || d.alias,
      providerKey: o.providerKey || d.providerKey,
    }
  }
  const CFG = {
    llamaDir,
    serverExe: u.serverExe || DEF.serverExe,
    port: Number.isInteger(u.port) ? u.port : DEF.port,
    apiKey: typeof u.apiKey === 'string' ? u.apiKey : DEF.apiKey,
    settingsNs: u.settingsNs || DEF.settingsNs,
    curlPath: typeof u.curlPath === 'string' && u.curlPath ? u.curlPath : null,
    server: serverCfg,
    models: modCfg,
  }
  const SERVER_EXE = CFG.llamaDir + '/' + CFG.serverExe
  const HEALTH_URL = 'http://127.0.0.1:' + CFG.port + '/health'

  // ---- model catalogue (35b: bat35_utf8 §7 presets; 9b: bat9_utf8) ----
  // file/mmproj/alias/providerKey come from config; the rest is model
  // behaviour fixed by the validated bat parameters.
  const MODELS = {
    '35b': {
      file: CFG.models['35b'].file,
      mmproj: CFG.models['35b'].mmproj,
      alias: CFG.models['35b'].alias,
      providerKey: CFG.models['35b'].providerKey,
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
      file: CFG.models['9b'].file,
      mmproj: CFG.models['9b'].mmproj,
      alias: CFG.models['9b'].alias,
      providerKey: CFG.models['9b'].providerKey,
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
    }
    scope.update(patch).catch((e) => note('state publish failed', e))
  }

  // ---- subprocess helpers ----
  function buildArgv(m, mo, p) {
    const M = MODELS[m]
    if (!M) return null
    const key = mo + ':' + p
    const pr = M.presets[key]
    if (!pr) return null
    const argv = [SERVER_EXE, '-m', M.file]
    if (M.vision && pr.mmproj) argv.push('--mmproj', M.mmproj, '--image-min-tokens', '1024')
    argv.push('-a', M.alias, '--port', String(CFG.port), '--host', '127.0.0.1', '--api-key', CFG.apiKey)
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
      try {
        h = ctx.subprocess.spawn({
          argv: [curl, '-s', '-m', '3', '-H', 'Authorization: Bearer ' + CFG.apiKey, HEALTH_URL],
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

  function syncContextWindow() {
    const M = MODELS[model]
    const key = mode + ':' + preset
    const pr = M && M.presets[key]
    if (!M || !pr) return
    try {
      const desc = ctx.settings.describe().find((d) => d.ns === CFG.settingsNs)
      if (!desc || !desc.user) { note('contextWindow: no user section for ' + CFG.settingsNs); return }
      const section = desc.user
      const provider = section && section.providers && section.providers[M.providerKey]
      const models = provider && provider.models
      if (!Array.isArray(models) || !models[0]) { note('contextWindow: unexpected shape'); return }
      models[0].contextWindow = pr.ctx
      ctx.settings.replace(CFG.settingsNs, section)
        .then(() => console.log('[local-llm] contextWindow synced to ' + pr.ctx + ' for ' + M.providerKey))
        .catch((e) => note('contextWindow sync failed', e))
    } catch (e) {
      note('contextWindow sync threw', e)
    }
  }

  function start(m, mo, p) {
    if (starting || status === 'starting' || status === 'ready' || status === 'stopping') return
    if (!buildArgv(m, mo, p)) {
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
          argv: buildArgv(m, mo, p),
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
          syncContextWindow()
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

  // ---- action channel ----
  ctx.on('settings/updated', (ns, next) => {
    if (ns !== 'local-llm') return
    const action = next && next.action
    if (action === 'start') {
      const m = next.model === '9b' ? '9b' : '35b'
      const mo = next.mode === 'vision' ? 'vision' : 'text'
      const p = next.preset === 'long' ? 'long' : 'fast'
      start(m, mo, p)
    } else if (action === 'stop') {
      stop()
    }
  })

  // ---- lifecycle ----
  ctx.effect(() => () => {
    stopPolling()
    if (proc) { try { proc.terminate() } catch (e) { /* noop */ } }
  })
}
