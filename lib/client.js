/**
 * Local LLM Controller — browser half.
 *
 * Bundle format: window.__ModuleLoader__.load({ id, factory(require) }) —
 * the shell provides the CJS shim and pre-registered modules (react, ...).
 * State/actions ride the `local-llm` settings namespace via ctx.settingsScope:
 * subscribe() replaces polling, set() writes choices and action commands.
 */
window.__ModuleLoader__.load({
  id: 'dsh-local-llm-controller',
  factory: (require) => {
    var module = { exports: {} }
    var exports = module.exports
    Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' })
    let React = require('react')
    let h = React.createElement

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

      React.useEffect(() => props.scope.subscribe(() => setSnap(props.scope.getSnapshot())), [])

      const st = snap && snap.status === 'ready' && snap.value
        ? snap.value
        : { status: 'stopped', mode: 'text', preset: 'fast', pid: null, lastError: null, logTail: null, config: null }
      const running = st.status === 'starting' || st.status === 'ready' || st.status === 'stopping'
      const statusText = { stopped: '未运行', starting: '启动中…', ready: '运行中', stopping: '停止中…', error: '错误' }[st.status] || st.status
      const scope = props.scope

      // initialize the config form from the effective config the host publishes
      React.useEffect(() => {
        if (cfgDraft !== null) return
        const c = st.config
        if (!c || typeof c !== 'object') return
        setCfgDraft({
          llamaDir: c.llamaDir || '',
          port: c.port != null ? String(c.port) : '',
          apiKey: c.apiKey || '',
          dir35b: (c.models && c.models['35b'] && c.models['35b'].dir) || '',
          dir9b: (c.models && c.models['9b'] && c.models['9b'].dir) || '',
        })
      }, [st.config, cfgDraft])

      const choose = (field, value) => { scope.set(field, value).catch(() => {}) }
      const chooseModel = (m) => { scope.set('model', m).catch(() => {}) }
      const doStart = () => { scope.set('action', 'start').catch(() => {}) }
      const doStop = () => { scope.set('action', 'stop').catch(() => {}) }

      const setCfg = (field, v) => setCfgDraft((d) => (d ? Object.assign({}, d, { [field]: v }) : d))
      const saveConfig = () => {
        if (!cfgDraft) return
        const cfg = {
          llamaDir: cfgDraft.llamaDir.trim(),
          apiKey: cfgDraft.apiKey.trim(),
          models: {
            '35b': { dir: cfgDraft.dir35b.trim() },
            '9b': { dir: cfgDraft.dir9b.trim() },
          },
        }
        const n = Number(cfgDraft.port)
        if (cfgDraft.port.trim() !== '' && Number.isInteger(n)) cfg.port = n
        scope.set('config', cfg).then(() => {
          setCfgSaved(true)
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
            h('div', { className: 'dsh-llm-desc' }, '本地大模型 35B/9B · 视觉/非视觉 × 快速/长上下文')
          ),
          chevron
        ),
        open ? h('div', { className: 'dsh-llm-body' },
          h('div', { className: 'dsh-llm-bubble-group' },
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, '模型'),
              h('button', { className: 'dsh-llm-bubble' + (st.model === '35b' ? ' on' : ''), disabled: running, onClick: () => chooseModel('35b') }, '35B'),
              h('button', { className: 'dsh-llm-bubble' + (st.model === '9b' ? ' on' : ''), disabled: running, onClick: () => chooseModel('9b') }, '9B')
            ),
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, '模式'),
              h('button', { className: 'dsh-llm-bubble' + (st.mode === 'text' ? ' on' : ''), disabled: running, onClick: () => choose('mode', 'text') }, '文本'),
              h('button', { className: 'dsh-llm-bubble' + (st.mode === 'vision' ? ' on' : ''), disabled: running, onClick: () => choose('mode', 'vision') }, '视觉')
            ),
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, '预设'),
              h('button', { className: 'dsh-llm-bubble' + (st.preset === 'fast' ? ' on' : ''), disabled: running, onClick: () => choose('preset', 'fast') }, '快速 ' + ctxLabel(st.model, st.mode, 'fast')),
              h('button', { className: 'dsh-llm-bubble' + (st.preset === 'long' ? ' on' : ''), disabled: running, onClick: () => choose('preset', 'long') }, '长上下文 ' + ctxLabel(st.model, st.mode, 'long'))
            )
          ),
          h('div', { className: 'dsh-llm-bubble-group' },
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, '配置'),
              h('span', { className: 'dsh-llm-desc' }, '模型文件夹内自动识别 GGUF 与 mmproj')
            ),
            cfgRow('llamaDir', 'llama.cpp 目录', '如 F:/llama.cpp'),
            cfgRow('port', '端口', '默认 67913'),
            cfgRow('apiKey', '密钥', '留空 = 无鉴权'),
            cfgRow('dir35b', '35B 文件夹', '如 {llamaDir}/qwen3.6-35B-A3B'),
            cfgRow('dir9b', '9B 文件夹', '如 {llamaDir}/qwen3.5-9B'),
            h('div', { className: 'dsh-llm-bubble-row' },
              h('button', { className: 'dsh-llm-btn', disabled: !cfgDraft, onClick: saveConfig }, '保存配置'),
              cfgSaved ? h('span', { className: 'dsh-llm-notice' }, '已保存 · 下次启动生效') : null
            )
          ),
          h('div', { className: 'dsh-llm-bubble-row' },
            h('button', { className: 'dsh-llm-btn primary', disabled: running || st.status === 'error', onClick: doStart }, '启动'),
            h('button', { className: 'dsh-llm-btn danger', disabled: !running, onClick: doStop }, '停止')
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
      slots.inject('settings.plugin.item', () => slots.register(
        { name: 'settings.plugin.item', key: 'local-llm' },
        () => h(Panel, { scope })
      ))
    }

    return module.exports
  }
})
