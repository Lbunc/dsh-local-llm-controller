import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  PRESET_GROUPS,
  deriveModelNames,
  defaultPresetArgs,
  normalizeArgRow,
  normalizePresets,
  argValue,
  maxTokensFor,
} from '../lib/index.js'
import { marginTokens, resolveSpec, summaryCallBudget } from '../lib/compaction-math.js'
import { selectCompactableRange } from '../lib/compaction.js'
import { compactCheckpointSource } from '@deepseek-ai/dsh-compaction'

test('deriveModelNames: slugifies a GGUF filename into alias + provider key', () => {
  const d = deriveModelNames('Qwen3.6-35B-A3B-Q8_K.gguf')
  assert.equal(d.alias, 'Qwen3.6-35B-A3B-Q8_K')
  assert.equal(d.providerKey, 'dsh-local-qwen3-6-35b-a3b-q8-k')
})

test('deriveModelNames: empty or junk input still yields a usable provider key', () => {
  assert.equal(deriveModelNames('').providerKey, 'dsh-local-model')
  assert.equal(deriveModelNames('...GGUF').providerKey, 'dsh-local-model')
})

test('defaultPresetArgs: covers the base set and carries -c per group', () => {
  const fast = defaultPresetArgs('text:fast')
  const long = defaultPresetArgs('text:long')
  assert.ok(fast.length > 5)
  assert.equal(argValue(fast, '-c'), '32768')
  assert.equal(argValue(long, '-c'), '131072')
  assert.equal(argValue(fast, '--metrics'), null) // pure flag: no value
  // neutralized penalties are part of the required sampling set
  assert.equal(argValue(fast, '--repeat-penalty'), '1')
  assert.equal(argValue(fast, '--presence-penalty'), '0')
  assert.equal(argValue(long, '--repeat-penalty'), '1')
  assert.equal(argValue(long, '--presence-penalty'), '0')
})

test('normalizeArgRow: drops invalid rows, coerces values', () => {
  assert.equal(normalizeArgRow(null), null)
  assert.equal(normalizeArgRow({}), null)
  assert.equal(normalizeArgRow({ flag: ' ' }), null)
  assert.deepEqual(normalizeArgRow({ flag: '-ngl', value: 99 }), { flag: '-ngl', value: '99' })
  assert.deepEqual(normalizeArgRow({ flag: '--metrics' }), { flag: '--metrics', value: '' })
})

test('normalizePresets: fills all eight groups', () => {
  const p = normalizePresets(null)
  assert.deepEqual(Object.keys(p).sort(), [...PRESET_GROUPS].sort())
  for (const g of PRESET_GROUPS) assert.ok(Array.isArray(p[g]) && p[g].length > 0)
})

test('normalizePresets: keeps provided rows verbatim, prefills the missing groups', () => {
  // a stored group is user state: rows are kept EXACTLY as saved — deletions
  // and value edits persist across reloads, restarts, and plugin upgrades
  const p = normalizePresets({ 'text:fast': [{ flag: '-ncmoe', value: '20' }] })
  assert.deepEqual(p['text:fast'], [{ flag: '-ncmoe', value: '20' }])
  assert.notEqual(p['text:long'], undefined)
  assert.equal(argValue(p['text:fast'], '-ncmoe'), '20')
  assert.equal(argValue(p['text:fast'], '--repeat-penalty'), null)
})

test('normalizePresets: a group the user emptied stays empty', () => {
  const p = normalizePresets({ 'text:fast': [], 'text:long': [{ flag: '-ngl', value: '99' }] })
  assert.deepEqual(p['text:fast'], [])
  assert.deepEqual(p['text:long'], [{ flag: '-ngl', value: '99' }])
  // absent groups still get the template
  assert.ok(p['vision:fast'].length > 0)
  assert.ok(p['vision:long'].length > 0)
})

test('normalizePresets: template updates never backfill stored groups', () => {
  // a stored group that lacks template rows keeps lacking them after an
  // upgrade — new defaults reach NEW groups only, never tuned ones
  const p = normalizePresets({ 'text:fast': [{ flag: '-ngl', value: '99' }] })
  assert.equal(argValue(p['text:fast'], '--repeat-penalty'), null)
  assert.equal(argValue(p['text:fast'], '--presence-penalty'), null)
  assert.equal(argValue(p['text:fast'], '-ngl'), '99')
})

test('argValue: returns null when the flag is absent', () => {
  assert.equal(argValue([{ flag: '-c', value: '4096' }], '-ngl'), null)
  assert.equal(argValue(null, '-c'), null)
})

test('maxTokensFor: quarter of -c per preset group (fast 8192, long 32768)', () => {
  assert.equal(maxTokensFor(defaultPresetArgs('text:fast')), 8192)
  assert.equal(maxTokensFor(defaultPresetArgs('text:long')), 32768)
  assert.equal(maxTokensFor([{ flag: '-c', value: '40961' }]), 10240) // floor
})

test('maxTokensFor: null on absent or non-positive -c — caller keeps stored value', () => {
  assert.equal(maxTokensFor([]), null)
  assert.equal(maxTokensFor([{ flag: '-ngl', value: '99' }]), null)
  assert.equal(maxTokensFor([{ flag: '-c', value: '' }]), null)
  assert.equal(maxTokensFor([{ flag: '-c', value: 'abc' }]), null)
  assert.equal(maxTokensFor([{ flag: '-c', value: '0' }]), null)
})

// --- compaction-math: 比例阈值压缩引擎的预算推导 ---

test('compaction-math: marginTokens 随窗口 5% 缩放并限制在 [1024, 8192]', () => {
  assert.equal(marginTokens(32768), 1638)
  assert.equal(marginTokens(131072), 6553)
  assert.equal(marginTokens(8192), 1024) // 下限
  assert.equal(marginTokens(1e9), 8192) // 上限
})

test('compaction-math: c/4 预留下 32k/131k 阈值恰为 70%', () => {
  const fast = resolveSpec({ windowSize: 32768, reserved: 8192 })
  assert.equal(fast.thresholdTokens, 22937)
  assert.equal(fast.thresholdTokens, Math.floor(32768 * 0.7))
  const long = resolveSpec({ windowSize: 131072, reserved: 32768 })
  assert.equal(long.thresholdTokens, 91750)
  assert.equal(long.thresholdTokens, Math.floor(131072 * 0.7))
})

test('compaction-math: 预留输出过大时阈值自动下调而不是归零', () => {
  // c/2 预留（旧模型条目）：min(0.7W, 0.5W − margin) 仍可触发
  const squeezed = resolveSpec({ windowSize: 131072, reserved: 65536 })
  assert.equal(squeezed.thresholdTokens, 131072 - 65536 - 6553)
  assert.ok(squeezed.thresholdTokens > 0)
  assert.ok(squeezed.thresholdTokens < squeezed.proportional)
  // 极端：reserved + margin 吃满窗口 → 无法触发（上层转为一次性配置警告）
  const dead = resolveSpec({ windowSize: 32768, reserved: 31130 })
  assert.equal(dead.thresholdTokens, 0)
})

test('compaction-math: 尾巴封顶保证压缩后总占用低于阈值（根治二次触发）', () => {
  for (const [w, reserved] of [[32768, 8192], [65536, 16384], [131072, 32768], [150000, 37500]]) {
    const spec = resolveSpec({ windowSize: w, reserved })
    // 压缩后总占用上界 = 尾巴 + 摘要预留 ≤ 阈值 − 边距
    assert.ok(spec.retainTokens + spec.summaryUpper <= spec.thresholdTokens, `W=${w}`)
    // 尾巴同时受比例约束（0.16×消息预算）
    assert.ok(spec.retainTokens <= Math.floor((w - reserved) * 0.16), `W=${w}`)
    assert.ok(spec.retainTokens > 0, `W=${w}`)
  }
})

test('compaction-math: summaryCallBudget 按剩余空间推导，不足 1024 返回 null', () => {
  assert.equal(summaryCallBudget(32768, 20000, 1638), 11130)
  assert.equal(summaryCallBudget(131072, 90000, 6553), 34519)
  assert.equal(summaryCallBudget(32768, 30106, 1638), 1024) // 边界：恰为下限
  assert.equal(summaryCallBudget(32768, 30107, 1638), null) // 1023 < 1024
})

// --- 区间选取：纯检查点守卫与非单调 seq 回归（静夜思会话 [130,130] / [148,144]） ---

/** 最小会话桩：仅提供区间选取与工具配对缓存所需的 API（无工具调用 → 全部边界平衡）。 */
function fakeSession(events, nodes) {
  const seqs = nodes ?? events.map((_, seq) => seq)
  return {
    surface: { nodes: seqs, replaceGeneration: 0 },
    eventAt: (seq) => (events[seq] === undefined ? undefined : { ...events[seq], seq }),
    deriveEventMessage: (event) => (event === undefined || event.type !== 'user/message' ? null : event.data),
  }
}

const priced = (seqs, tokens) => ({
  nodes: seqs.map((seq, index) => ({ seq, tokens: tokens[index] })),
  totalTokens: tokens.reduce((a, b) => a + b, 0),
})
const systemEv = (tokens) => ({ type: 'system/message', data: {}, tokens })
const userEv = (tokens) => ({ type: 'user/message', data: { role: 'user', content: [{ type: 'text', text: 'hello' }] }, tokens })
const checkpointEv = (tokens) => ({
  type: 'user/message',
  data: { role: 'user', content: [{ type: 'text', text: '## 检查点' }], source: compactCheckpointSource('test-id') },
  tokens,
})

test('selectCompactableRange: 纯检查点区间返回 null（[130,130] 回归）', () => {
  // 表面 = [system, 检查点C1, 大消息]：尾巴预算恰被大消息吃满时，唯一候选区间
  // 是刚生成的检查点本身 —— 旧实现会选取它（摘要的摘要），几乎必然触发
  // “摘要不小于被替换内容”并浪费一次 LLM 调用；修复后直接返回 null
  const session = fakeSession([systemEv(10), checkpointEv(200), userEv(5000)])
  assert.equal(selectCompactableRange(session, priced([0, 1, 2], [10, 200, 5000]), 4000), null)
})

test('selectCompactableRange: 检查点+真实消息的区间正常选取（[130,135] 形态）', () => {
  const session = fakeSession([systemEv(10), checkpointEv(200), userEv(1000), userEv(1000)])
  const range = selectCompactableRange(session, priced([0, 1, 2, 3], [10, 200, 1000, 1000]), 900)
  assert.deepEqual(range, { start: 1, end: 2 })
})

test('selectCompactableRange: 检查点 seq 高于逻辑后继（[148,144] 形态）按表面顺序选取', () => {
  // 检查点提交时才追加到事件日志，seq(148) 大于逻辑后继(136/137)；表面逻辑
  // 顺序仍是 [system, C2, 136, 137] —— 区间合法，两端 seq 非单调不是倒挂
  const events = []
  events[0] = systemEv(10)
  events[148] = checkpointEv(200)
  events[136] = userEv(500)
  events[137] = userEv(500)
  const seqs = [0, 148, 136, 137]
  const session = fakeSession(events, seqs)
  const range = selectCompactableRange(session, priced(seqs, [10, 200, 500, 500]), 500)
  assert.deepEqual(range, { start: 148, end: 136 })
})

test('selectCompactableRange: 表面仅剩检查点时返回 null（/compact 空转形态）', () => {
  const session = fakeSession([checkpointEv(100), checkpointEv(200)])
  assert.equal(selectCompactableRange(session, priced([0, 1], [100, 200]), 0), null)
})

test('selectCompactableRange: 单条真实消息的区间仍合法（守卫不误伤）', () => {
  // 尾巴预算 1000 恰由末条消息满足 → keepFromIdx=2，区间 = 表面[1..1] 单条真实消息
  const session = fakeSession([systemEv(10), userEv(1000), userEv(1000)])
  const range = selectCompactableRange(session, priced([0, 1, 2], [10, 1000, 1000]), 1000)
  assert.deepEqual(range, { start: 1, end: 1 })
})
