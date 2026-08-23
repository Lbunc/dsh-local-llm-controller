/**
 * Local LLM Controller — browser half.
 *
 * Bundle format: window.__ModuleLoader__.load({ id, factory(require) }) —
 * the shell provides the CJS shim and pre-registered modules (react, ...).
 * State/actions ride the `local-llm` settings namespace via ctx.settingsScope:
 * subscribe() replaces polling, set() writes choices and action commands.
 *
 * Card layout (vNEXT-4 partition): a launch zone (slot A/B → text/vision →
 * fast/long-context, then Start/Stop) and a config zone (llamaDir/port/key,
 * per-slot folder + model-file bubbles + alias/provider-key, and the launch
 * parameter rows for the currently selected group — 8 groups per design:
 * 2 slots × text/vision × fast/long, each a list of { flag, value } rows).
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
        'args.group': '正在编辑：{slot} · {mode} · {preset}',
        'args.flag': '参数',
        'args.value': '值',
        'btn.addArg': '添加参数行',
        'btn.delArg': '删',
        'cfg.autoDetect': '模型文件夹内自动识别 GGUF 与 mmproj；alias/providerKey 由模型文件名派生，可改',
        'cfg.llamaDir': 'llama.cpp 目录',
        'cfg.llamaDir.ph': '如 F:/llama.cpp',
        'cfg.port': '端口',
        'cfg.port.ph': '默认 55555',
        'cfg.apiKey': '密钥',
        'cfg.apiKey.ph': '留空 = 无鉴权',
        'cfg.dir': '模型文件夹',
        'cfg.dir.ph': '含 GGUF 的目录',
        'cfg.file': '模型文件',
        'cfg.alias': '模型名 (alias)',
        'cfg.providerKey': 'Provider 键',
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
        'args.group': 'Editing: {slot} · {mode} · {preset}',
        'args.flag': 'Flag',
        'args.value': 'Value',
        'btn.addArg': 'Add arg row',
        'btn.delArg': 'Del',
        'cfg.autoDetect': 'GGUF & mmproj auto-detected in the model folder; alias/providerKey derived from the model file name, editable',
        'cfg.llamaDir': 'llama.cpp directory',
        'cfg.llamaDir.ph': 'e.g. F:/llama.cpp',
        'cfg.port': 'Port',
        'cfg.port.ph': 'default 55555',
        'cfg.apiKey': 'API key',
        'cfg.apiKey.ph': 'blank = no auth',
        'cfg.dir': 'Model folder',
        'cfg.dir.ph': 'folder containing GGUF',
        'cfg.file': 'Model file',
        'cfg.alias': 'Model alias',
        'cfg.providerKey': 'Provider key',
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
.dsh-llm-arg-row { display: flex; align-items: center; gap: 6px; }
.dsh-llm-arg-flag { flex: 0 0 120px; min-width: 0; border: 1px solid var(--dsw-alias-border-l2); border-radius: 8px; background: var(--dsw-alias-bg-layer-1); color: inherit; font: inherit; font-size: 12px; line-height: 1.5; padding: 3px 8px; box-sizing: border-box; }
.dsh-llm-arg-value { flex: 1 1 auto; min-width: 0; border: 1px solid var(--dsw-alias-border-l2); border-radius: 8px; background: var(--dsw-alias-bg-layer-1); color: inherit; font: inherit; font-size: 12px; line-height: 1.5; padding: 3px 8px; box-sizing: border-box; }
.dsh-llm-arg-value:focus, .dsh-llm-arg-flag:focus { outline: none; border-color: #3b82f6; }
.dsh-llm-arg-del { border: 1px solid var(--dsw-alias-border-l2); border-radius: 8px; background: transparent; color: var(--dsw-alias-label-tertiary); padding: 3px 8px; cursor: pointer; font-size: 12px; }
.dsh-llm-arg-del:hover { color: #ef4444; border-color: #ef4444; }
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
        : { status: 'stopped', slot: 'a', mode: 'text', preset: 'fast', pid: null, lastError: null, logTail: null, config: null }
      const running = st.status === 'starting' || st.status === 'ready' || st.status === 'stopping'
      const statusText = t('status.' + st.status)
      const scope = props.scope

      // initialize the config form from the effective config the host publishes
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
          const s = (src && typeof src === 'object') ? src : {}
          return {
            dir: s.dir || '',
            file: s.file || '',
            files: Array.isArray(s.files) ? s.files : [],
            alias: s.alias || '',
            providerKey: s.providerKey || '',
            presets: normalizePresets(s.presets),
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
            const pubAlias = p.alias || ''
            const pubKey = p.providerKey || ''
            if (cur.files.join('|') !== pubFiles.join('|')) { cur.files = pubFiles; changed = true }
            if (cur.file !== pubFile) { cur.file = pubFile; changed = true }
            if (cur.alias !== pubAlias) { cur.alias = pubAlias; changed = true }
            if (cur.providerKey !== pubKey) { cur.providerKey = pubKey; changed = true }
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

      // Same rule as the host's deriveModelNames: picking a model file re-derives
      // the alias/providerKey into the draft, so a save carries the NEW names
      // instead of the previous file's derived values. Manual edits afterwards
      // are preserved until the next file picking.
      const deriveNames = (file) => {
        const alias = (file || '').replace(/\.gguf$/i, '') || ''
        const slug = alias.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '')
        return { alias, providerKey: 'dsh-local-' + (slug || 'model') }
      }
      const pickFile = (slotKey, f) => setCfgDraft((d) => {
        if (!d) return d
        const derived = deriveNames(f)
        const slots = Object.assign({}, d.slots)
        const s = Object.assign({}, slots[slotKey], derived, { file: f })
        slots[slotKey] = s
        return Object.assign({}, d, { slots })
      })

      const choose = (field, value) => { scope.set(field, value).catch(() => {}) }
      const doStart = () => { scope.set('action', 'start').catch(() => {}) }
      const doStop = () => { scope.set('action', 'stop').catch(() => {}) }
      const doAddProviders = () => {
        scope.set('action', 'add-providers').then(() => {
          setProvidersSaved(true)
          setTimeout(() => setProvidersSaved(false), 3000)
        }).catch(() => {})
      }

      const setCfg = (field, v) => setCfgDraft((d) => (d ? Object.assign({}, d, { [field]: v }) : d))
      const setSlotField = (slotKey, field, v) => setCfgDraft((d) => {
        if (!d) return d
        const slots = Object.assign({}, d.slots)
        const s = Object.assign({}, slots[slotKey])
        s[field] = v
        slots[slotKey] = s
        return Object.assign({}, d, { slots })
      })
      const setPresetRow = (slotKey, group, index, field, value) => setCfgDraft((d) => {
        if (!d) return d
        const slots = Object.assign({}, d.slots)
        const s = Object.assign({}, slots[slotKey])
        const presets = Object.assign({}, s.presets)
        const rows = presets[group].slice()
        rows[index] = Object.assign({}, rows[index], { [field]: value })
        presets[group] = rows
        s.presets = presets
        slots[slotKey] = s
        return Object.assign({}, d, { slots })
      })
      const addPresetRow = (slotKey, group) => setCfgDraft((d) => {
        if (!d) return d
        const slots = Object.assign({}, d.slots)
        const s = Object.assign({}, slots[slotKey])
        const presets = Object.assign({}, s.presets)
        presets[group] = presets[group].concat([{ flag: '', value: '' }])
        s.presets = presets
        slots[slotKey] = s
        return Object.assign({}, d, { slots })
      })
      const removePresetRow = (slotKey, group, index) => setCfgDraft((d) => {
        if (!d) return d
        const slots = Object.assign({}, d.slots)
        const s = Object.assign({}, slots[slotKey])
        const presets = Object.assign({}, s.presets)
        presets[group] = presets[group].filter((_, i) => i !== index)
        s.presets = presets
        slots[slotKey] = s
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
          const s = cfgDraft.slots[key]
          cfg.slots[key] = {
            dir: (s.dir || '').trim(),
            file: s.file || '',
            alias: (s.alias || '').trim(),
            providerKey: (s.providerKey || '').trim(),
            presets: s.presets,
          }
        }
        const n = Number(cfgDraft.port)
        if (cfgDraft.port.trim() !== '' && Number.isInteger(n)) cfg.port = n
        scope.set('config', cfg).then(() => {
          setCfgSaved(true)
          // The draft is NOT reset here: the effect above absorbs the host's
          // next publish (fresh enumeration + derived alias/providerKey) into
          // the existing draft, so no mid-edit flicker and no lost selection.
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

      // One bubble per model GGUF published by the host for a slot's model folder.
      // mmproj (vision projector) files are filtered out — they are not a
      // selectable model; the host wires them automatically in vision mode.
      const modelFilesRow = (slotKey) => {
        const files = (cfgDraft && cfgDraft.slots && cfgDraft.slots[slotKey] ? cfgDraft.slots[slotKey].files : [])
          .filter((f) => !/mmproj/i.test(f))
        if (!files || !files.length) return null
        const cur = cfgDraft.slots[slotKey]
        return h('div', { className: 'dsh-llm-bubble-row dsh-llm-wrap' },
          h('span', { className: 'dsh-llm-label' }, t('cfg.file')),
          files.map((f) => h('button', {
            key: f,
            className: 'dsh-llm-bubble dsh-llm-file-bubble' + (cur.file === f ? ' on' : ''),
            title: f,
            onClick: () => pickFile(slotKey, f),
          }, f))
        )
      }

      const slotCfg = (slotKey) => {
        if (!cfgDraft || !cfgDraft.slots) return null
        const s = cfgDraft.slots[slotKey]
        const slotLabel = t(slotKey === 'a' ? 'slot.a' : 'slot.b')
        return h('div', { className: 'dsh-llm-bubble-group' },
          h('div', { className: 'dsh-llm-bubble-row' },
            h('span', { className: 'dsh-llm-label' }, slotLabel),
            h('span', { className: 'dsh-llm-desc' }, t('cfg.autoDetect'))
          ),
          h('label', { className: 'dsh-llm-cfg-row' },
            h('span', { className: 'dsh-llm-label' }, t('cfg.dir')),
            h('input', {
              className: 'dsh-llm-input',
              value: s.dir,
              placeholder: t('cfg.dir.ph'),
              spellCheck: false,
              onChange: (e) => setSlotField(slotKey, 'dir', e.target.value),
            })
          ),
          modelFilesRow(slotKey),
          h('div', { className: 'dsh-llm-cfg-row' },
            h('span', { className: 'dsh-llm-label' }, t('cfg.alias')),
            h('input', {
              className: 'dsh-llm-input',
              value: s.alias,
              spellCheck: false,
              onChange: (e) => setSlotField(slotKey, 'alias', e.target.value),
            })
          ),
          h('div', { className: 'dsh-llm-cfg-row' },
            h('span', { className: 'dsh-llm-label' }, t('cfg.providerKey')),
            h('input', {
              className: 'dsh-llm-input',
              value: s.providerKey,
              spellCheck: false,
              onChange: (e) => setSlotField(slotKey, 'providerKey', e.target.value),
            })
          )
        )
      }

      // launch-parameter rows for the currently selected group (slot+mode+preset)
      const argRows = () => {
        if (!cfgDraft || !cfgDraft.slots) return null
        const s = cfgDraft.slots[st.slot]
        if (!s || !s.presets) return null
        const group = st.mode + ':' + st.preset
        const rows = s.presets[group] || []
        const groupLabel = t(st.slot === 'a' ? 'slot.a' : 'slot.b') + ' · ' +
          t(st.mode === 'vision' ? 'mode.vision' : 'mode.text') + ' · ' +
          t(st.preset === 'long' ? 'preset.long' : 'preset.fast')
        return h('div', { className: 'dsh-llm-bubble-group' },
          h('div', { className: 'dsh-llm-bubble-row' },
            h('span', { className: 'dsh-llm-label' }, t('label.args')),
            h('span', { className: 'dsh-llm-desc' }, groupLabel)
          ),
          rows.map((row, i) => h('div', { className: 'dsh-llm-arg-row', key: i },
            h('input', {
              className: 'dsh-llm-arg-flag',
              value: row.flag,
              placeholder: t('args.flag'),
              spellCheck: false,
              onChange: (e) => setPresetRow(st.slot, group, i, 'flag', e.target.value),
            }),
            h('input', {
              className: 'dsh-llm-arg-value',
              value: row.value,
              placeholder: t('args.value'),
              spellCheck: false,
              onChange: (e) => setPresetRow(st.slot, group, i, 'value', e.target.value),
            }),
            h('button', { className: 'dsh-llm-arg-del', title: t('btn.delArg'), onClick: () => removePresetRow(st.slot, group, i) }, t('btn.delArg'))
          )),
          h('div', { className: 'dsh-llm-bubble-row' },
            h('button', { className: 'dsh-llm-btn', onClick: () => addPresetRow(st.slot, group) }, '+' + t('btn.addArg'))
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
                statusText + (st.status === 'ready' ? (' · PID ' + st.pid) : '')
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
              h('button', { className: 'dsh-llm-bubble' + (st.slot === 'a' ? ' on' : ''), disabled: running, onClick: () => choose('slot', 'a') }, t('slot.a')),
              h('button', { className: 'dsh-llm-bubble' + (st.slot === 'b' ? ' on' : ''), disabled: running, onClick: () => choose('slot', 'b') }, t('slot.b'))
            ),
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, t('label.mode')),
              h('button', { className: 'dsh-llm-bubble' + (st.mode === 'text' ? ' on' : ''), disabled: running, onClick: () => choose('mode', 'text') }, t('mode.text')),
              h('button', { className: 'dsh-llm-bubble' + (st.mode === 'vision' ? ' on' : ''), disabled: running, onClick: () => choose('mode', 'vision') }, t('mode.vision'))
            ),
            h('div', { className: 'dsh-llm-bubble-row' },
              h('span', { className: 'dsh-llm-label' }, t('label.preset')),
              h('button', { className: 'dsh-llm-bubble' + (st.preset === 'fast' ? ' on' : ''), disabled: running, onClick: () => choose('preset', 'fast') }, t('preset.fast')),
              h('button', { className: 'dsh-llm-bubble' + (st.preset === 'long' ? ' on' : ''), disabled: running, onClick: () => choose('preset', 'long') }, t('preset.long'))
            ),
            h('div', { className: 'dsh-llm-bubble-row' },
              h('button', { className: 'dsh-llm-btn primary', disabled: running || st.status === 'error', onClick: doStart }, t('btn.start')),
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
          slotCfg('a'),
          slotCfg('b'),
          argRows(),
          h('div', { className: 'dsh-llm-bubble-row' },
            h('button', { className: 'dsh-llm-btn', disabled: !cfgDraft, onClick: saveConfig }, t('btn.save')),
            cfgSaved ? h('span', { className: 'dsh-llm-notice' }, t('btn.saved')) : null
          ),
          h('div', { className: 'dsh-llm-bubble-row' },
            h('button', { className: 'dsh-llm-btn', onClick: doAddProviders }, t('btn.addProviders')),
            providersSaved ? h('span', { className: 'dsh-llm-notice' }, t('btn.addProvidersSaved')) : null
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
