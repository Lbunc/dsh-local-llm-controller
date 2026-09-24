/**
 * Local LLM Controller — browser half (DSH 0.1.7-rc.1 client API).
 *
 * Bundle format: window.__ModuleLoader__.load({ id, factory(require) }) —
 * the shell provides the CJS shim and pre-registered modules (react, ...).
 *
 * 0.1.7 data layer: the card talks to the host through Typert Remote —
 * `ctx.remote.$mount(contribution)` installs the `localLlm` namespace with
 * hand-written descriptors (same shape the official generated
 * typert.remote-client files carry), then calls
 * `ctx.remote.localLlm.getState()/start()/stop()/saveConfig()/listSlotFiles()/
 * addProviders()`. Invoke results are `{ ok, value } | { ok: false, error }`.
 *
 * State refresh: a 1.5s getState poll while the card is mounted (unmount
 * stops it) plus `ctx.remote.$on('settings/document-updated')` for an
 * immediate refresh after host-side settings writes (e.g. addProviders).
 *
 * Card mount point: the Plugins page's `plugins.row.config` keyed slot,
 * keyed `<package name>#<patch row id>` — the row detail page renders it as
 * this row's configuration page.
 *
 * Model-file enumeration: the directory box debounces 400ms then calls the
 * remote listSlotFiles(dir) — no host-side publish round-trip.
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

    const PKG = 'dsh-local-llm-controller'
    const ROW_ID = 'local-llm-controller'
    const NS = 'local-llm'
    /** Cordis service key AND Typert Remote namespace (bound together host-side). */
    const NAMESPACE = 'localLlm'
    const POLL_MS = 1500
    const LIST_DEBOUNCE_MS = 400

    const GROUPS = ['text:fast', 'text:long', 'vision:fast', 'vision:long']

    // ---- dictionaries (dsh-client-locale namespace `local-llm`) ----
    const MESSAGES = {
      zh: {
        'card.desc': '本地大模型双槽位 A/B · 视觉/非视觉 × 快速/长上下文',
        'status.stopped': '未运行',
        'status.starting': '启动中…',
        'status.ready': '运行中',
        'status.stopping': '停止中…',
        'status.error': '错误',
        'label.slot': '槽位',
        'slot.a': '槽位 A',
        'slot.b': '槽位 B',
        'label.mode': '模式',
        'label.preset': '预设',
        'label.config': '配置',
        'label.args': '启动参数（当前组合）',
        'args.flag': '参数',
        'args.value': '值',
        'btn.addArg': '添加参数行',
        'btn.delArg': '删',
        'cfg.autoDetect': '模型文件夹内自动识别 GGUF 与 mmproj；模型名由文件派生，可在模型页重命名',
        'cfg.llamaDir': 'llama.cpp 目录',
        'cfg.llamaDir.ph': '如 F:/llama.cpp',
        'cfg.port': '端口',
        'cfg.port.ph': '默认 55555',
        'cfg.apiKey': '密钥',
        'cfg.apiKey.ph': '留空 = 无鉴权',
        'cfg.dir': '模型文件夹',
        'cfg.dir.ph': '含 GGUF 的目录',
        'cfg.dirFor': '{slot} 的目录',
        'cfg.mmproj': '视觉投影器',
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
        'card.desc': 'Local LLM dual slot A/B · vision/text × fast/long-context',
        'status.stopped': 'Stopped',
        'status.starting': 'Starting…',
        'status.ready': 'Running',
        'status.stopping': 'Stopping…',
        'status.error': 'Error',
        'label.slot': 'Slot',
        'slot.a': 'Slot A',
        'slot.b': 'Slot B',
        'label.mode': 'Mode',
        'label.preset': 'Preset',
        'label.config': 'Config',
        'label.args': 'Launch args (current combo)',
        'args.flag': 'Flag',
        'args.value': 'Value',
        'btn.addArg': 'Add arg row',
        'btn.delArg': 'Del',
        'cfg.autoDetect': 'GGUF & mmproj auto-detected in the model folder; the model name derives from the file — rename it on the models page',
        'cfg.llamaDir': 'llama.cpp directory',
        'cfg.llamaDir.ph': 'e.g. F:/llama.cpp',
        'cfg.port': 'Port',
        'cfg.port.ph': 'default 55555',
        'cfg.apiKey': 'API key',
        'cfg.apiKey.ph': 'blank = no auth',
        'cfg.dir': 'Model folder',
        'cfg.dir.ph': 'folder containing GGUF',
        'cfg.dirFor': '{slot} folder',
        'cfg.mmproj': 'Vision projector',
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
.dsh-llm-notice.ok { color: #22c55e; }
.dsh-llm-error { color: var(--dsw-alias-label-error); font-size: 12px; white-space: pre-wrap; word-break: break-all; }
.dsh-llm-log { margin: 0; padding: 8px; background: rgba(127,127,127,0.09); border-radius: 8px; max-height: 150px; overflow: auto; font-size: 11px; line-height: 1.45; white-space: pre-wrap; word-break: break-all; }
.dsh-llm-cfg-row { display: flex; align-items: center; gap: 6px; }
.dsh-llm-input { flex: 1; min-width: 0; border: 1px solid var(--dsw-alias-border-l2); border-radius: 8px; background: var(--dsw-alias-bg-layer-1); color: inherit; font: inherit; font-size: 12px; line-height: 1.5; padding: 3px 8px; box-sizing: border-box; }
.dsh-llm-input:focus { outline: none; border-color: #3b82f6; }
.dsh-llm-wrap { flex-wrap: wrap; }
.dsh-llm-file-bubble { max-width: 240px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.dsh-llm-arg-row { display: flex; align-items: center; gap: 8px; }
.dsh-llm-arg-head { display: flex; align-items: center; gap: 8px; color: var(--dsw-alias-label-tertiary); font-size: 11px; padding: 0 2px; }
.dsh-llm-arg-head span:first-child { flex: 0 0 150px; }
.dsh-llm-arg-head span:last-child { flex: 1 1 auto; }
.dsh-llm-arg-flag { flex: 0 0 150px; min-width: 0; border: 1px solid var(--dsw-alias-border-l2); border-radius: 8px; background: var(--dsw-alias-bg-layer-1); color: inherit; font-family: ui-monospace, SFMono-Regular, Consolas, "Cascadia Mono", monospace; font-size: 12px; line-height: 1.5; padding: 4px 8px; box-sizing: border-box; }
.dsh-llm-arg-value { flex: 1 1 auto; min-width: 0; border: 1px solid var(--dsw-alias-border-l2); border-radius: 8px; background: var(--dsw-alias-bg-layer-1); color: inherit; font-family: ui-monospace, SFMono-Regular, Consolas, "Cascadia Mono", monospace; font-size: 12px; line-height: 1.5; padding: 4px 8px; box-sizing: border-box; }
.dsh-llm-arg-value:focus, .dsh-llm-arg-flag:focus { outline: none; border-color: #3b82f6; }
.dsh-llm-arg-del { flex: 0 0 auto; width: 28px; height: 28px; border: 1px solid var(--dsw-alias-border-l2); border-radius: 8px; background: transparent; color: var(--dsw-alias-label-tertiary); padding: 0; cursor: pointer; font-size: 15px; line-height: 1; opacity: 0.55; }
.dsh-llm-arg-del:hover { opacity: 1; color: #ef4444; border-color: #ef4444; }
.dsh-llm-args { gap: 6px; }
.dsh-llm-arg-add { justify-content: flex-start; }
`
    if (typeof document !== 'undefined' && document.querySelector('style[data-plugin-css="dsh-local-llm"]') === null) {
      const tag = document.createElement('style')
      tag.dataset.plugin = 'dsh-local-llm-controller'
      tag.dataset.pluginCss = 'dsh-local-llm'
      tag.textContent = CSS
      document.head.appendChild(tag)
    }

    // ---- Typert Remote contribution ----
    // Hand-written in the shape the official generated typert.remote-client
    // files carry (see dsh-plugin-manager/remote). $mount enforces
    // codec.mode === 'strict' on every parameter; the current gateway client
    // never CALLS codec.create(), so a pass-through schema keeps the shape
    // honest without needing zod (no build step bundles it) and keeps
    // working if a future version enables client-side validation.
    const IDENTITY_SCHEMA = {
      '~standard': { version: 1, vendor: PKG, validate: (value) => ({ value }) },
      parse: (value) => value,
    }
    const strictCodec = (typeSymbol) => ({ mode: 'strict', typeSymbol, create: () => IDENTITY_SCHEMA })

    function descriptor(method, parameterNames) {
      return {
        id: PKG + '#' + NAMESPACE + '/' + method,
        service: NAMESPACE,
        namespace: NAMESPACE,
        method,
        invocation: { kind: 'direct' },
        parameters: parameterNames.map((name) => ({
          name,
          wire: name,
          source: 'json',
          codec: strictCodec(PKG + '#' + method + ':' + name),
        })),
        result: { mode: 'strict', typeSymbol: PKG + '#' + method + ':result', create: () => IDENTITY_SCHEMA },
      }
    }

    const CONTRIBUTION = {
      package: PKG,
      descriptors: [
        descriptor('getState', []),
        descriptor('start', ['slot', 'mode', 'preset']),
        descriptor('stop', []),
        descriptor('saveConfig', ['config']),
        descriptor('listSlotFiles', ['dir']),
        descriptor('addProviders', []),
      ],
    }

    // ---- component ----
    function Panel(props) {
      const api = props.api
      const [s, setS] = React.useState(null)
      const [sel, setSel] = React.useState({ slot: 'a', mode: 'text', preset: 'fast' })
      const [open, setOpen] = React.useState(false)
      const [cfgDraft, setCfgDraft] = React.useState(null)
      const [cfgSaved, setCfgSaved] = React.useState(false)
      const [providersSaved, setProvidersSaved] = React.useState(false)
      const [actionError, setActionError] = React.useState(null)
      const listTimer = React.useRef(null)
      const sJson = React.useRef('')

      // Locale `t` seat from the slot machinery; zh fallback if ever absent.
      const t = props.t || ((key, vars) => {
        let str = MESSAGES.zh[key] || key
        if (vars) for (const k in vars) str = str.split('{' + k + '}').join(String(vars[k]))
        return str
      })

      // State refresh: 1.5s getState poll + settings/document-updated push.
      // Skip setState when the JSON snapshot is unchanged so the poll does
      // not re-render (and re-run the absorb effect) every 1.5s.
      const refresh = React.useCallback(() => {
        api.getState().then((value) => {
          const json = JSON.stringify(value ?? null)
          if (json === sJson.current) return
          sJson.current = json
          setS(value)
        }, () => {})
      }, [api])

      React.useEffect(() => {
        refresh()
        const timer = setInterval(refresh, POLL_MS)
        const off = api.onDocumentUpdated(() => refresh())
        return () => { clearInterval(timer); off() }
      }, [refresh])
      React.useEffect(() => () => { clearTimeout(listTimer.current) }, [])

      const st = s || { status: 'stopped', slot: 'a', mode: 'text', preset: 'fast', pid: null, lastError: null, logTail: null, config: null }
      const running = st.status === 'starting' || st.status === 'ready' || st.status === 'stopping'
      const statusText = t('status.' + st.status)
      // While a launch is live the host's slot/mode/preset are the truth; the
      // local selection draft drives the NEXT start otherwise.
      const eff = running ? { slot: st.slot, mode: st.mode, preset: st.preset } : sel

      // initialize the config form from the effective config the host serves
      const lastPublishedRef = React.useRef(null)
      React.useEffect(() => {
        const c = st.config
        if (!c || typeof c !== 'object') return
        // Only react to a NEW publish object. Draft edits (bubble click,
        // keystrokes) re-run this effect without a new publish — without this
        // guard the absorb below would overwrite the just-edited field with
        // the stale published value, making bubble selection impossible.
        if (c === lastPublishedRef.current) return
        lastPublishedRef.current = c
        const mkSlot = (src) => {
          const sc = (src && typeof src === 'object') ? src : {}
          return {
            dir: sc.dir || '',
            file: sc.file || '',
            files: Array.isArray(sc.files) ? sc.files : [],
            mmproj: sc.mmproj || '',
            presets: normalizePresets(sc.presets),
          }
        }
        if (cfgDraft === null) {
          setCfgDraft({
            llamaDir: c.llamaDir || '',
            port: c.port != null ? String(c.port) : '',
            apiKey: c.apiKey || '',
            slots: {
              a: mkSlot((c.slots || {}).a),
              b: mkSlot((c.slots || {}).b),
            },
          })
          return
        }
        // Draft exists: the host's re-publish after «保存配置» is the
        // authoritative copy — folder enumeration, derived alias/providerKey,
        // chosen file. Absorb those fields back whenever the draft's path
        // matches the published one (that slot is not mid-edit). Only when the
        // publish carries the enumeration (host-published CFG) — the transient
        // user-saved config shape (no files field, pre-derivation) never wipes
        // the draft.
        setCfgDraft((d) => {
          if (!d) return d
          let changed = false
          const nd = Object.assign({}, d)
          const syncSlot = (slotKey) => {
            const p = (c.slots || {})[slotKey] || {}
            const cur = d.slots && d.slots[slotKey]
            if (!cur) return
            if (cur.dir !== (p.dir || '')) return // path mid-edit: never touch
            if (!Array.isArray(p.files)) return // not a host publish: skip
            const pubFiles = p.files
            const pubFile = p.file || ''
            if (cur.files.join('|') !== pubFiles.join('|')) { cur.files = pubFiles; changed = true }
            if (cur.file !== pubFile) { cur.file = pubFile; changed = true }
            if (cur.mmproj !== (p.mmproj || '')) { cur.mmproj = p.mmproj || ''; changed = true }
          }
          syncSlot('a')
          syncSlot('b')
          return changed ? nd : d
        })
      }, [st.config, cfgDraft])

      const normalizePresets = (raw) => {
        const out = {}
        for (const g of GROUPS) {
          const rows = (raw && raw[g] && Array.isArray(raw[g])) ? raw[g] : []
          out[g] = rows.map((row) => ({
            flag: (row && typeof row.flag === 'string') ? row.flag : '',
            value: (row && typeof row.value === 'string') ? row.value : '',
          }))
        }
        return out
      }

      // Picking a model file writes the selection into the draft only — the
      // alias/providerKey are host-side derivations (never edited from the
      // card; rename the model on the models page instead).
      const pickFile = (slotKey, f) => setSlotField(slotKey, 'file', f)

      const choose = (field, value) => setSel((d) => Object.assign({}, d, { [field]: value }))
      const doStart = () => {
        setActionError(null)
        api.start(sel.slot, sel.mode, sel.preset).catch((e) => setActionError((e && e.message) || String(e)))
      }
      const doStop = () => {
        setActionError(null)
        api.stop().catch((e) => setActionError((e && e.message) || String(e)))
      }
      const doAddProviders = () => {
        setActionError(null)
        api.addProviders().then(() => {
          setProvidersSaved(true)
          setTimeout(() => setProvidersSaved(false), 3000)
        }).catch((e) => setActionError((e && e.message) || String(e)))
      }

      // Debounced folder enumeration: the directory box goes to the host's
      // remote listSlotFiles 400ms after the last keystroke and writes the
      // result (GGUF bubbles + mmproj) back into the draft.
      const queueListFiles = (slotKey, dir) => {
        clearTimeout(listTimer.current)
        listTimer.current = setTimeout(() => {
          api.listSlotFiles(dir).then((value) => {
            setCfgDraft((d) => {
              if (!d || !d.slots || !d.slots[slotKey]) return d
              const slots = Object.assign({}, d.slots)
              slots[slotKey] = Object.assign({}, slots[slotKey], {
                files: (value && Array.isArray(value.files)) ? value.files : [],
                mmproj: (value && value.mmproj) || '',
              })
              return Object.assign({}, d, { slots })
            })
          }, () => {})
        }, LIST_DEBOUNCE_MS)
      }

      const setCfg = (field, v) => setCfgDraft((d) => (d ? Object.assign({}, d, { [field]: v }) : d))
      const setSlotField = (slotKey, field, v) => {
        setCfgDraft((d) => {
          if (!d) return d
          const slots = Object.assign({}, d.slots)
          const sc = Object.assign({}, slots[slotKey])
          sc[field] = v
          slots[slotKey] = sc
          return Object.assign({}, d, { slots })
        })
        if (field === 'dir') queueListFiles(slotKey, (v || '').trim())
      }
      const setPresetRow = (slotKey, group, index, field, value) => setCfgDraft((d) => {
        if (!d) return d
        const slots = Object.assign({}, d.slots)
        const sc = Object.assign({}, slots[slotKey])
        const presets = Object.assign({}, sc.presets)
        const rows = presets[group].slice()
        rows[index] = Object.assign({}, rows[index], { [field]: value })
        presets[group] = rows
        sc.presets = presets
        slots[slotKey] = sc
        return Object.assign({}, d, { slots })
      })
      const addPresetRow = (slotKey, group) => setCfgDraft((d) => {
        if (!d) return d
        const slots = Object.assign({}, d.slots)
        const sc = Object.assign({}, slots[slotKey])
        const presets = Object.assign({}, sc.presets)
        presets[group] = presets[group].concat([{ flag: '', value: '' }])
        sc.presets = presets
        slots[slotKey] = sc
        return Object.assign({}, d, { slots })
      })
      const removePresetRow = (slotKey, group, index) => setCfgDraft((d) => {
        if (!d) return d
        const slots = Object.assign({}, d.slots)
        const sc = Object.assign({}, slots[slotKey])
        const presets = Object.assign({}, sc.presets)
        presets[group] = presets[group].filter((_, i) => i !== index)
        sc.presets = presets
        slots[slotKey] = sc
        return Object.assign({}, d, { slots })
      })

      const saveConfig = () => {
        if (!cfgDraft) return
        const cfg = {
          llamaDir: cfgDraft.llamaDir.trim(),
          apiKey: cfgDraft.apiKey.trim(),
          slots: {},
        }
        for (const key of ['a', 'b']) {
          const sc = cfgDraft.slots[key]
          cfg.slots[key] = {
            dir: (sc.dir || '').trim(),
            file: sc.file || '',
            presets: sc.presets,
          }
        }
        const n = Number(cfgDraft.port)
        if (cfgDraft.port.trim() !== '' && Number.isInteger(n)) cfg.port = n
        setActionError(null)
        api.saveConfig(cfg).then(() => {
          setCfgSaved(true)
          // The draft is NOT reset here: the next getState publish (fresh
          // enumeration + derived alias/providerKey) is absorbed into the
          // existing draft by the effect above, so no mid-edit flicker and
          // no lost selection.
          setTimeout(() => setCfgSaved(false), 3000)
        }).catch((e) => setActionError((e && e.message) || String(e)))
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

      // One bubble per model GGUF the host enumerated for a slot's model
      // folder. mmproj (vision projector) files are filtered out — they are
      // not a selectable model; the host wires them automatically in vision
      // mode.
      const slotPickRow = (slotKey) => {
        if (!cfgDraft || !cfgDraft.slots || !cfgDraft.slots[slotKey]) return null
        const sc = cfgDraft.slots[slotKey]
        const files = (sc.files || []).filter((f) => !/mmproj/i.test(f))
        const rows = []
        if (files.length) {
          rows.push(h('div', { className: 'dsh-llm-bubble-row dsh-llm-wrap' },
            h('span', { className: 'dsh-llm-label' }, t(slotKey === 'a' ? 'slot.a' : 'slot.b')),
            files.map((f) => h('button', {
              key: f,
              className: 'dsh-llm-bubble dsh-llm-file-bubble' + (sc.file === f ? ' on' : ''),
              title: f,
              onClick: () => pickFile(slotKey, f),
            }, f))
          ))
        }
        if (sc.mmproj) {
          rows.push(h('div', { className: 'dsh-llm-bubble-row' },
            h('span', { className: 'dsh-llm-label' }, t('cfg.mmproj')),
            h('span', { className: 'dsh-llm-desc' }, sc.mmproj)
          ))
        }
        return rows.length ? rows : null
      }

      // Both slots share ONE folder box that edits the ACTIVE slot's directory —
      // per-slot dirs stay separate in the saved config (switch the slot bubble
      // in the launch zone to edit the other slot's folder). The auto-detect
      // hint renders once for the section.
      const modelFolderSection = () => {
        if (!cfgDraft || !cfgDraft.slots || !cfgDraft.slots[eff.slot]) return null
        const active = eff.slot === 'b' ? 'b' : 'a'
        const sc = cfgDraft.slots[active]
        return h('div', { className: 'dsh-llm-bubble-group' },
          h('div', { className: 'dsh-llm-bubble-row' },
            h('span', { className: 'dsh-llm-label' }, t('cfg.dir')),
            h('span', { className: 'dsh-llm-desc' }, t('cfg.autoDetect'))
          ),
          h('label', { className: 'dsh-llm-cfg-row' },
            h('span', { className: 'dsh-llm-label' }, t('cfg.dirFor', { slot: t(active === 'a' ? 'slot.a' : 'slot.b') })),
            h('input', {
              className: 'dsh-llm-input',
              value: sc.dir,
              placeholder: t('cfg.dir.ph'),
              spellCheck: false,
              onChange: (e) => setSlotField(active, 'dir', e.target.value),
            })
          ),
          slotPickRow('a'),
          slotPickRow('b')
        )
      }

      // launch-parameter rows for the currently selected group (slot+mode+preset)
      const argRows = () => {
        if (!cfgDraft || !cfgDraft.slots) return null
        const sc = cfgDraft.slots[eff.slot]
        if (!sc || !sc.presets) return null
        const group = eff.mode + ':' + eff.preset
        const rows = sc.presets[group] || []
        const groupLabel = t(eff.slot === 'a' ? 'slot.a' : 'slot.b') + ' · ' +
          t(eff.mode === 'vision' ? 'mode.vision' : 'mode.text') + ' · ' +
          t(eff.preset === 'long' ? 'preset.long' : 'preset.fast')
        return h('div', { className: 'dsh-llm-bubble-group dsh-llm-args' },
          h('div', { className: 'dsh-llm-bubble-row' },
            h('span', { className: 'dsh-llm-label' }, t('label.args')),
            h('span', { className: 'dsh-llm-desc' }, groupLabel)
          ),
          h('div', { className: 'dsh-llm-arg-head' },
            h('span', {}, t('args.flag')),
            h('span', {}, t('args.value'))
          ),
          rows.map((row, i) => h('div', { className: 'dsh-llm-arg-row', key: i },
            h('input', {
              className: 'dsh-llm-arg-flag',
              value: row.flag,
              placeholder: t('args.flag'),
              spellCheck: false,
              onChange: (e) => setPresetRow(eff.slot, group, i, 'flag', e.target.value),
            }),
            h('input', {
              className: 'dsh-llm-arg-value',
              value: row.value,
              placeholder: row.value === '' && row.flag ? '—' : '',
              spellCheck: false,
              onChange: (e) => setPresetRow(eff.slot, group, i, 'value', e.target.value),
            }),
            h('button', { className: 'dsh-llm-arg-del', title: t('btn.delArg'), onClick: () => removePresetRow(eff.slot, group, i) }, '×')
          )),
          h('div', { className: 'dsh-llm-bubble-row dsh-llm-arg-add' },
            h('button', { className: 'dsh-llm-btn', onClick: () => addPresetRow(eff.slot, group) }, '+' + t('btn.addArg'))
          )
        )
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
                // The host resolves the PID out-of-band after the ready
                // transition (the subprocess handle no longer carries it) —
                // omit the fragment until it arrives instead of showing null.
                statusText + (st.status === 'ready' && st.pid != null ? (' · PID ' + st.pid) : '')
              )
            ),
            h('div', { className: 'dsh-llm-desc' }, t('card.desc'))
          ),
          chevron
        ),
        open ? h('div', { className: 'dsh-llm-body' },
          // ---- launch zone: slot → mode → preset (reused selection logic) ----
          h('div', { className: 'dsh-llm-bubble-group' },
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, t('label.slot')),
              h('button', { className: 'dsh-llm-bubble' + (eff.slot === 'a' ? ' on' : ''), disabled: running, onClick: () => choose('slot', 'a') }, t('slot.a')),
              h('button', { className: 'dsh-llm-bubble' + (eff.slot === 'b' ? ' on' : ''), disabled: running, onClick: () => choose('slot', 'b') }, t('slot.b'))
            ),
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, t('label.mode')),
              h('button', { className: 'dsh-llm-bubble' + (eff.mode === 'text' ? ' on' : ''), disabled: running, onClick: () => choose('mode', 'text') }, t('mode.text')),
              h('button', { className: 'dsh-llm-bubble' + (eff.mode === 'vision' ? ' on' : ''), disabled: running, onClick: () => choose('mode', 'vision') }, t('mode.vision'))
            ),
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, t('label.preset')),
              h('button', { className: 'dsh-llm-bubble' + (eff.preset === 'fast' ? ' on' : ''), disabled: running, onClick: () => choose('preset', 'fast') }, t('preset.fast')),
              h('button', { className: 'dsh-llm-bubble' + (eff.preset === 'long' ? ' on' : ''), disabled: running, onClick: () => choose('preset', 'long') }, t('preset.long'))
            ),
            h('div', { className: 'dsh-llm-bubble-row' },
              h('button', { className: 'dsh-llm-btn primary', disabled: running, onClick: doStart }, t('btn.start')),
              h('button', { className: 'dsh-llm-btn danger', disabled: !running, onClick: doStop }, t('btn.stop'))
            )
          ),
          // ---- config zone ----
          h('div', { className: 'dsh-llm-bubble-group' },
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, t('label.config'))
            ),
            cfgRow('llamaDir', t('cfg.llamaDir'), t('cfg.llamaDir.ph')),
            cfgRow('port', t('cfg.port'), t('cfg.port.ph')),
            cfgRow('apiKey', t('cfg.apiKey'), t('cfg.apiKey.ph'))
          ),
          modelFolderSection(),
          argRows(),
          h('div', { className: 'dsh-llm-bubble-row' },
            h('button', { className: 'dsh-llm-btn', disabled: !cfgDraft, onClick: saveConfig }, t('btn.save')),
            cfgSaved ? h('span', { className: 'dsh-llm-notice ok' }, t('btn.saved')) : null
          ),
          h('div', { className: 'dsh-llm-bubble-row' },
            h('button', { className: 'dsh-llm-btn', onClick: doAddProviders }, t('btn.addProviders')),
            providersSaved ? h('span', { className: 'dsh-llm-notice ok' }, t('btn.addProvidersSaved')) : null
          ),
          actionError ? h('div', { className: 'dsh-llm-error' }, actionError) : null,
          st.lastError ? h('div', { className: 'dsh-llm-error' }, st.lastError) : null,
          st.logTail ? h('pre', { className: 'dsh-llm-log' }, st.logTail) : null
        ) : null
      )
    }

    // ---- plugin ----
    // The client runner resolves services only when declared in the module's
    // inject list. `remote` (the Typert Remote client service, provided by
    // @deepseek-ai/dsh-api-remotes) backs $mount/$on and the mounted
    // `remote.localLlm` namespace; `slots` hosts the Plugins page slot; the
    // dsh.client.inject manifest field additionally pins the module-graph
    // dependencies (api-remotes + the plugin-manager page that owns
    // `plugins.row.config`).
    // `remote` (the Typert Remote client service) backs $mount/$on and the
    // mounted `remote.localLlm` namespace. The namespace itself must NOT be
    // listed here: the deep-proxy path throws "without inject" when
    // undeclared, while declaring `remote.localLlm` parks the whole module on
    // a service only our own $mount provides (deadlock — the official
    // namespaces work because api-remotes mounts them a layer below). The
    // card resolves the namespace service directly instead.
    exports.inject = ['slots', 'locale', 'remote']

    exports.apply = function apply(ctx) {
      const slots = ctx.slots
      if (slots === undefined) return
      // Load diagnostic: if this line is missing from the browser console, the
      // client half never ran (module graph stale or apply failed) and no slot
      // registration exists — the Plugins page then shows no 配置 button.
      console.info('[local-llm] client half applied; registering ' + PKG + '#' + ROW_ID + ' config slot')

      // Register the card's dictionary namespace through the injected locale
      // service (the instance backing the renderer's `t` seat). register()
      // returns the disposer, which ctx.effect wires to the fiber — on
      // HMR/refresh the old dictionaries unload before the new ones register,
      // instead of throwing "already has locale".
      const locale = ctx.locale
      if (locale) {
        ctx.effect(() => locale.register(NS, { zh: MESSAGES.zh, en: MESSAGES.en }), 'local-llm: card dictionaries')
      }

      // Mount the remote namespace for the card's lifetime. $mount resolves
      // asynchronously; the disposer race is handled so a fast unmount still
      // unmounts the contribution.
      const remote = ctx.remote
      if (remote) {
        ctx.effect(() => {
          let disposed = false
          let disposer = null
          Promise.resolve(remote.$mount(CONTRIBUTION)).then((d) => {
            if (disposed) { Promise.resolve(d()).catch(() => {}); return }
            disposer = d
          }, (e) => {
            console.log('[local-llm] remote mount failed: ' + ((e && e.message) || String(e)))
          })
          return () => {
            disposed = true
            if (disposer) return disposer()
          }
        }, 'local-llm: remote mount')
      }

      // Card API: every call rides the mounted namespace; invoke returns
      // `{ ok, value } | { ok: false, error }` (never throws for host-side
      // failures), so this face rethrows the error for the panel to show.
      // The namespace service is resolved through ctx.get(`remote.<ns>`) —
      // the same primitive the gateway uses for its own namespaces — because
      // the ctx.remote deep-proxy path is gated by per-namespace inject
      // declarations that a self-mounted third-party namespace cannot satisfy.
      function namespace() {
        if (typeof ctx.get === 'function') {
          const direct = ctx.get('remote.' + NAMESPACE)
          if (direct) return direct
        }
        return ctx.remote && ctx.remote[NAMESPACE]
      }
      const api = {
        call(method, ...args) {
          const ns = namespace()
          if (!ns) return Promise.reject(new Error('Local LLM remote is not mounted yet'))
          return ns[method](...args).then((result) => {
            if (!result.ok) throw result.error
            return result.value
          })
        },
        getState: () => api.call('getState'),
        start: (slot, mode, preset) => api.call('start', slot, mode, preset),
        stop: () => api.call('stop'),
        saveConfig: (config) => api.call('saveConfig', config),
        listSlotFiles: (dir) => api.call('listSlotFiles', dir),
        addProviders: () => api.call('addProviders'),
        onDocumentUpdated: (listener) => ctx.remote.$on('settings/document-updated', listener),
      }

      // Card mount: the Plugins page row detail's `plugins.row.config` keyed
      // slot, keyed `<package name>#<patch row id>`; `locale` gives the
      // rendered component its `t` seat. The row summary view renders the
      // one-line description (the row meta description usually covers it).
      // Instrumented while diagnosing: slots.inject defers its factory until
      // the page declares the child slot, so silence here means "never
      // declared"; register() failures surface through the catch.
      ctx.effect(() => slots.inject('plugins.row.config', () => {
        try {
          const dispose = slots.register({
            name: 'plugins.row.config',
            key: PKG + '#' + ROW_ID,
            locale: NS,
          }, (slotProps) => h(Panel, {
            view: slotProps.view,
            entryKey: slotProps.entryKey,
            t: slotProps.t,
            api,
          }))
          console.info('[local-llm] plugins.row.config registered with key "' + PKG + '#' + ROW_ID + '"')
          return dispose
        } catch (error) {
          console.error('[local-llm] plugins.row.config registration failed:', error)
          throw error
        }
      }), 'local-llm: card')

      // Crash probe: the render machinery abdicates (and may retire) an entry
      // whose component throws during render — renderSlot then renders nothing
      // and the ledger (raw entries) only loses the key if retired. Surface
      // the cause here; also expose the registry for console inspection.
      if (typeof slots.onEntryError === 'function') {
        ctx.effect(() => slots.onEntryError((...args) => {
          console.error('[local-llm] slot entry error (abdication/retire):', ...args)
        }), 'local-llm: entry-error probe')
      }
      window.__LOCAL_LLM_SLOTS__ = slots
    }

    return module.exports
  }
})
