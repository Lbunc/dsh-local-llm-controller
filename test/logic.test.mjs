import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  PRESET_GROUPS,
  deriveModelNames,
  defaultPresetArgs,
  normalizeArgRow,
  normalizePresets,
  argValue,
} from '../lib/index.js'

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
