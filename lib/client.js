/**
 * Local LLM Controller — browser half.
 *
 * Bundle format: window.__ModuleLoader__.load({ id, factory(require) }) —
 * the shell provides the CJS shim and pre-registered modules (react, ...).
 * State/actions ride the `local-llm` settings namespace via ctx.settingsScope:
 * subscribe() replaces polling, set() writes choices and action commands.
 *
 * UI copy follows the DSH Web language setting through the `locale` service
 * (@deepseek-ai/dsh-client-locale): the card registers a `local-llm`
 * dictionary namespace (zh/en) and the slot entry declares `locale`, so the
 * render machinery injects the `t` seat and re-renders on every switch.
 */
window.__ModuleLoader__.load({
  id: 'dsh-local-llm-controller',
  factory: (require) => {
    var module = { exports: {} }
    var exports = module.exports
    Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' })
    let React = require('react')
    let h = React.createElement

    // ---- dictionaries (dsh-client-locale namespace `local-llm`) ----
    const MESSAGES = {
      zh: {
        'card.desc': '本地大模型 35B/9B · 视觉/非视觉 × 快速/长上下文',
        'status.stopped': '未运行',
        'status.starting': '启动中…',
        'status.ready': '运行中',
        'status.stopping': '停止中…',
        'status.error': '错误',
        'label.model': '模型',
        'label.mode': '模式',
        'label.preset': '预设',
        'label.config': '配置',
        'cfg.autoDetect': '模型文件夹内自动识别 GGUF 与 mmproj',
        'cfg.llamaDir': 'llama.cpp 目录',
        'cfg.llamaDir.ph': '如 F:/llama.cpp',
        'cfg.port': '端口',
        'cfg.port.ph': '默认 55555',
        'cfg.apiKey': '密钥',
        'cfg.apiKey.ph': '留空 = 无鉴权',
        'cfg.dir35b': '35B 文件夹',
        'cfg.dir35b.ph': '如 {llamaDir}/qwen3.6-35B-A3B',
        'cfg.dir9b': '9B 文件夹',
        'cfg.dir9b.ph': '如 {llamaDir}/qwen3.5-9B',
        'cfg.file35b': '35B 模型文件',
        'cfg.file9b': '9B 模型文件',
        'btn.save': '保存配置',
        'btn.saved': '已保存 · 下次启动生效',
        'btn.addProviders': '添加到模型列表',
        'btn.addProvidersSaved': '已写入 · 设置→模型可见',
        'btn.start': '启动',
        'btn.stop': '停止',
        'mode.text': '文本',
        'mode.vision': '视觉',
        'preset.fast': '快速',
        'preset.long': '长上下文',
      },
      en: {
        'card.desc': 'Local LLM 35B/9B · vision/text × fast/long-context',
        'status.stopped': 'Stopped',
        'status.starting': 'Starting…',
        'status.ready': 'Running',
        'status.stopping': 'Stopping…',
        'status.error': 'Error',
        'label.model': 'Model',
        'label.mode': 'Mode',
        'label.preset': 'Preset',
        'label.config': 'Config',
        'cfg.autoDetect': 'Auto-detects GGUF & mmproj in the model folder',
        'cfg.llamaDir': 'llama.cpp directory',
        'cfg.llamaDir.ph': 'e.g. F:/llama.cpp',
        'cfg.port': 'Port',
        'cfg.port.ph': 'default 55555',
        'cfg.apiKey': 'API key',
        'cfg.apiKey.ph': 'blank = no auth',
        'cfg.dir35b': '35B folder',
        'cfg.dir35b.ph': 'e.g. {llamaDir}/qwen3.6-35B-A3B',
        'cfg.dir9b': '9B folder',
        'cfg.dir9b.ph': 'e.g. {llamaDir}/qwen3.5-9B',
        'cfg.file35b': '35B model file',
        'cfg.file9b': '9B model file',
        'btn.save': 'Save config',
        'btn.saved': 'Saved · applies on next start',
        'btn.addProviders': 'Add to model list',
        'btn.addProvidersSaved': 'Written · visible in Settings → Models',
        'btn.start': 'Start',
        'btn.stop': 'Stop',
        'mode.text': 'Text',
        'mode.vision': 'Vision',
        'preset.fast': 'Fast',
        'preset.long': 'Long ctx',
      },
    }

    // ---- package CSS (injected once, mirrors official css-injection pattern) ----
    const CSS = `
.dsh-llm-card, .dsh-llm-card * { box-sizing: border-box; }
.dsh-llm-card { border: 1px solid var(--dsw-alias-border-l2); background: var(--dsw-alias-bg-layer-3); border-radius: 12px; list-style: none; transition: border-color .16s, background .16s; font-size: 13px; }
.dsh-llm-card.dsh-open { background: var(--dsw-alias-bg-layer-2); border-color: var(--dsw-alias-label-dimmed); }
.dsh-llm-header { appearance: none; width: 100%; font: inherit; color: inherit; text-align: left; cursor: pointer; background: none; border: 0; border-radius: 12px; align-items: center; gap: 12px; padding: 14px 16px; display: flex; }
.dsh-llm-header:focus-visible { outline: 2px solid var(--dsw-alias-brand-primary); outline-offset: -2px; }
.dsh-llm-headtext { flex-direction: column; flex: 1; gap: 4px; min-width: 0; display: flex; }
.dsh-llm-name-row { display: flex; align-items: baseline; gap: 6px; min-width: 0; }
.dsh-llm-name { color: var(--dsw-alias-label-primary); font-size: 15px; font-weight: 600; line-height: 1.4; flex: 0 1 auto; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.dsh-llm-desc { color: var(--dsw-alias-label-tertiary); font-size: 13px; line-height: 1.5; }
.dsh-llm-status { font-weight: 600; font-size: 12px; line-height: 1.4; flex: none; }
.dsh-llm-status.stopped { color: #9ca3af; }
.dsh-llm-status.starting { color: #f59e0b; }
.dsh-llm-status.ready { color: #22c55e; }
.dsh-llm-status.stopping { color: #f59e0b; }
.dsh-llm-status.error { color: #ef4444; }
.dsh-llm-chevron { color: var(--dsw-alias-label-tertiary); flex: none; display: block; transition: transform .16s; }
.dsh-llm-chevron.open { transform: rotate(180deg); }
.dsh-llm-body { border-top: 1px solid var(--dsw-alias-border-l2); margin: 0 16px; padding: 12px 0 8px; display: flex; flex-direction: column; gap: 10px; }
.dsh-llm-bubble-group { border: 1px dashed var(--dsw-alias-border-l2); border-radius: 12px; padding: 8px 10px; display: flex; flex-direction: column; gap: 8px; }
.dsh-llm-bubble-row { display: flex; align-items: center; gap: 6px; }
.dsh-llm-label { min-width: 40px; color: var(--dsw-alias-label-tertiary); font-size: 12px; }
.dsh-llm-bubble { border: 1px solid var(--dsw-alias-border-l2); border-radius: 999px; background: transparent; padding: 2px 13px; cursor: pointer; font-size: 12px; color: inherit; }
.dsh-llm-bubble.on { border-color: #3b82f6; color: #3b82f6; background: #eff6ff; font-weight: 600; }
.dsh-llm-bubble:disabled { opacity: 0.45; cursor: not-allowed; }
.dsh-llm-btn { border: 1px solid var(--dsw-alias-border-l2); border-radius: 8px; background: transparent; padding: 5px 14px; cursor: pointer; font-size: 13px; line-height: 1.5; }
.dsh-llm-btn:disabled { opacity: 0.45; cursor: not-allowed; }
.dsh-llm-btn.primary { background: #3b82f6; color: #fff; border-color: #3b82f6; }
.dsh-llm-btn.danger { background: #ef4444; color: #fff; border-color: #ef4444; }
.dsh-llm-notice { color: #f59e0b; font-size: 12px; }
.dsh-llm-error { color: var(--dsw-alias-label-error); font-size: 12px; white-space: pre-wrap; word-break: break-all; }
.dsh-llm-log { margin: 0; padding: 8px; background: rgba(127,127,127,0.09); border-radius: 8px; max-height: 150px; overflow: auto; font-size: 11px; line-height: 1.45; white-space: pre-wrap; word-break: break-all; }
.dsh-llm-cfg-row { display: flex; align-items: center; gap: 6px; }
.dsh-llm-input { flex: 1; min-width: 0; border: 1px solid var(--dsw-alias-border-l2); border-radius: 8px; background: var(--dsw-alias-bg-layer-1); color: inherit; font: inherit; font-size: 12px; line-height: 1.5; padding: 3px 8px; box-sizing: border-box; }
.dsh-llm-input:focus { outline: none; border-color: #3b82f6; }
.dsh-llm-wrap { flex-wrap: wrap; }
.dsh-llm-file-bubble { max-width: 240px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
`
    if (typeof document !== 'undefined' && document.querySelector('style[data-plugin-css="dsh-local-llm"]') === null) {
      const tag = document.createElement('style')
      tag.dataset.plugin = 'dsh-local-llm-controller'
      tag.dataset.pluginCss = 'dsh-local-llm'
      tag.textContent = CSS
      document.head.appendChild(tag)
    }

    // ---- component ----
    function Panel(props) {
      const [snap, setSnap] = React.useState(() => props.scope.getSnapshot())
      const [open, setOpen] = React.useState(false)
      const [cfgDraft, setCfgDraft] = React.useState(null)
      const [cfgSaved, setCfgSaved] = React.useState(false)
      const [providersSaved, setProvidersSaved] = React.useState(false)

      React.useEffect(() => props.scope.subscribe(() => setSnap(props.scope.getSnapshot())), [])

      // Locale `t` seat from the slot machinery; zh fallback if ever absent.
      const t = props.t || ((key) => MESSAGES.zh[key] || key)

      const st = snap && snap.status === 'ready' && snap.value
        ? snap.value
        : { status: 'stopped', mode: 'text', preset: 'fast', pid: null, lastError: null, logTail: null, config: null }
      const running = st.status === 'starting' || st.status === 'ready' || st.status === 'stopping'
      const statusText = t('status.' + st.status)
      const scope = props.scope

      // initialize the config form from the effective config the host publishes
      React.useEffect(() => {
        const c = st.config
        if (!c || typeof c !== 'object') return
        const m35 = (c.models && c.models['35b']) || {}
        const m9 = (c.models && c.models['9b']) || {}
        const files35b = Array.isArray(m35.files) ? m35.files : []
        const files9b = Array.isArray(m9.files) ? m9.files : []
        if (cfgDraft === null) {
          setCfgDraft({
            llamaDir: c.llamaDir || '',
            port: c.port != null ? String(c.port) : '',
            apiKey: c.apiKey || '',
            dir35b: m35.dir || '',
            dir9b: m9.dir || '',
            file35b: m35.file || '',
            file9b: m9.file || '',
            files35b,
            files9b,
          })
          return
        }
        // Draft already exists. When the host re-publishes after «保存配置»,
        // its enumeration is newer than the draft — but the init path above
        // skips non-null drafts, so the new model-file bubbles only appeared
        // after unmounting the card. Sync the enumeration lists back whenever
        // the draft's path matches the published one (that path is not
        // mid-edit); other draft fields are left untouched.
        setCfgDraft((d) => {
          let changed = false
          const nd = Object.assign({}, d)
          if (d.dir35b === (m35.dir || '') && d.files35b.join('|') !== files35b.join('|')) {
            nd.files35b = files35b
            changed = true
          }
          if (d.dir9b === (m9.dir || '') && d.files9b.join('|') !== files9b.join('|')) {
            nd.files9b = files9b
            changed = true
          }
          return changed ? nd : d
        })
      }, [st.config, cfgDraft])

      const choose = (field, value) => { scope.set(field, value).catch(() => {}) }
      const chooseModel = (m) => { scope.set('model', m).catch(() => {}) }
      const doStart = () => { scope.set('action', 'start').catch(() => {}) }
      const doStop = () => { scope.set('action', 'stop').catch(() => {}) }
      const doAddProviders = () => {
        scope.set('action', 'add-providers').then(() => {
          setProvidersSaved(true)
          setTimeout(() => setProvidersSaved(false), 3000)
        }).catch(() => {})
      }

      const setCfg = (field, v) => setCfgDraft((d) => (d ? Object.assign({}, d, { [field]: v }) : d))
      const saveConfig = () => {
        if (!cfgDraft) return
        const cfg = {
          llamaDir: cfgDraft.llamaDir.trim(),
          apiKey: cfgDraft.apiKey.trim(),
          models: {
            '35b': { dir: cfgDraft.dir35b.trim(), file: cfgDraft.file35b || '' },
            '9b': { dir: cfgDraft.dir9b.trim(), file: cfgDraft.file9b || '' },
          },
        }
        const n = Number(cfgDraft.port)
        if (cfgDraft.port.trim() !== '' && Number.isInteger(n)) cfg.port = n
        scope.set('config', cfg).then(() => {
          setCfgSaved(true)
          // Reset the draft so the init effect re-reads the host's next
          // publish — fresh folder enumeration + the values just saved.
          setCfgDraft(null)
          setTimeout(() => setCfgSaved(false), 3000)
        }).catch(() => {})
      }
      const cfgRow = (field, label, placeholder) => h('label', { className: 'dsh-llm-cfg-row' },
        h('span', { className: 'dsh-llm-label' }, label),
        h('input', {
          className: 'dsh-llm-input',
          value: cfgDraft ? cfgDraft[field] : '',
          placeholder: placeholder || '',
          spellCheck: false,
          onChange: (e) => setCfg(field, e.target.value),
        })
      )
      // One bubble per .gguf published by the host for this slot's model folder;
      // picking writes the chosen filename into the config draft (saved with
      // the rest of the form; '' = auto). Rendered only when the folder has
      // actually been enumerated (host found a readable folder).
      const modelFilesRow = (key, files) => {
        if (!files || !files.length) return null
        const field = 'file' + key
        return h('div', { className: 'dsh-llm-bubble-row dsh-llm-wrap' },
          h('span', { className: 'dsh-llm-label' }, t('cfg.file' + key)),
          files.map((f) => h('button', {
            key: f,
            className: 'dsh-llm-bubble dsh-llm-file-bubble' + (cfgDraft && cfgDraft[field] === f ? ' on' : ''),
            title: f,
            onClick: () => setCfg(field, f),
          }, f))
        )
      }

      const ctxLabel = (m, mo, p) => {
        if (m === '9b') return p === 'long' ? '64K' : '32K'
        return mo === 'vision' ? (p === 'long' ? '96K' : '32K') : (p === 'long' ? '128K' : '32K')
      }

      const chevron = h('svg', {
        className: 'dsh-llm-chevron' + (open ? ' open' : ''),
        width: 14, height: 14, viewBox: '0 0 14 14', fill: 'none',
        xmlns: 'http://www.w3.org/2000/svg',
        'aria-hidden': true,
      }, h('path', {
        d: 'M3 5.5L7 9.5L11 5.5',
        stroke: 'currentColor', strokeWidth: 1.5,
        strokeLinecap: 'round', strokeLinejoin: 'round',
      }))

      return h('div', { className: 'dsh-llm-card' + (open ? ' dsh-open' : '') },
        h('div', { className: 'dsh-llm-header', onClick: () => setOpen(!open) },
          h('div', { className: 'dsh-llm-headtext' },
            h('div', { className: 'dsh-llm-name-row' },
              h('span', { className: 'dsh-llm-name' }, 'Local LLM Controller'),
              h('span', { className: 'dsh-llm-status ' + st.status },
                statusText + (st.status === 'ready' ? (' · PID ' + st.pid) : '')
              )
            ),
            h('div', { className: 'dsh-llm-desc' }, t('card.desc'))
          ),
          chevron
        ),
        open ? h('div', { className: 'dsh-llm-body' },
          h('div', { className: 'dsh-llm-bubble-group' },
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, t('label.model')),
              h('button', { className: 'dsh-llm-bubble' + (st.model === '35b' ? ' on' : ''), disabled: running, onClick: () => chooseModel('35b') }, '35B'),
              h('button', { className: 'dsh-llm-bubble' + (st.model === '9b' ? ' on' : ''), disabled: running, onClick: () => chooseModel('9b') }, '9B')
            ),
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, t('label.mode')),
              h('button', { className: 'dsh-llm-bubble' + (st.mode === 'text' ? ' on' : ''), disabled: running, onClick: () => choose('mode', 'text') }, t('mode.text')),
              h('button', { className: 'dsh-llm-bubble' + (st.mode === 'vision' ? ' on' : ''), disabled: running, onClick: () => choose('mode', 'vision') }, t('mode.vision'))
            ),
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, t('label.preset')),
              h('button', { className: 'dsh-llm-bubble' + (st.preset === 'fast' ? ' on' : ''), disabled: running, onClick: () => choose('preset', 'fast') }, t('preset.fast') + ' ' + ctxLabel(st.model, st.mode, 'fast')),
              h('button', { className: 'dsh-llm-bubble' + (st.preset === 'long' ? ' on' : ''), disabled: running, onClick: () => choose('preset', 'long') }, t('preset.long') + ' ' + ctxLabel(st.model, st.mode, 'long'))
            )
          ),
          h('div', { className: 'dsh-llm-bubble-group' },
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, t('label.config')),
              h('span', { className: 'dsh-llm-desc' }, t('cfg.autoDetect'))
            ),
            cfgRow('llamaDir', t('cfg.llamaDir'), t('cfg.llamaDir.ph')),
            cfgRow('port', t('cfg.port'), t('cfg.port.ph')),
            cfgRow('apiKey', t('cfg.apiKey'), t('cfg.apiKey.ph')),
            cfgRow('dir35b', t('cfg.dir35b'), t('cfg.dir35b.ph')),
            modelFilesRow('35b', cfgDraft && cfgDraft.files35b),
            cfgRow('dir9b', t('cfg.dir9b'), t('cfg.dir9b.ph')),
            modelFilesRow('9b', cfgDraft && cfgDraft.files9b),
            h('div', { className: 'dsh-llm-bubble-row' },
              h('button', { className: 'dsh-llm-btn', disabled: !cfgDraft, onClick: saveConfig }, t('btn.save')),
              cfgSaved ? h('span', { className: 'dsh-llm-notice' }, t('btn.saved')) : null
            ),
            h('div', { className: 'dsh-llm-bubble-row' },
              h('button', { className: 'dsh-llm-btn', onClick: doAddProviders }, t('btn.addProviders')),
              providersSaved ? h('span', { className: 'dsh-llm-notice' }, t('btn.addProvidersSaved')) : null
            )
          ),
          h('div', { className: 'dsh-llm-bubble-row' },
            h('button', { className: 'dsh-llm-btn primary', disabled: running || st.status === 'error', onClick: doStart }, t('btn.start')),
            h('button', { className: 'dsh-llm-btn danger', disabled: !running, onClick: doStop }, t('btn.stop'))
          ),
          st.lastError ? h('div', { className: 'dsh-llm-error' }, st.lastError) : null,
          st.logTail ? h('pre', { className: 'dsh-llm-log' }, st.logTail) : null
        ) : null
      )
    }

    // ---- plugin ----
    exports.inject = ['settingsScope']

    exports.apply = function apply(ctx) {
      const slots = ctx.get('slots')
      if (slots === undefined) return
      const scope = ctx.settingsScope.bind({
        namespace: 'local-llm',
        decode: (section) => (section && typeof section === 'object') ? section : undefined,
      })
      // Register the card's dictionary namespace; ignore duplicates (module re-load).
      const locale = ctx.get('locale')
      if (locale) {
        try {
          locale.register('local-llm', { zh: MESSAGES.zh, en: MESSAGES.en })
        } catch (e) { /* already registered */ }
      }
      slots.inject('settings.plugin.item', () => slots.register(
        { name: 'settings.plugin.item', key: 'local-llm', locale: 'local-llm' },
        (props) => h(Panel, { scope, t: props.t })
      ))
    }

    return module.exports
  }
})
