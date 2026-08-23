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

test('normalizePresets: keeps provided rows, prefills the missing groups', () => {
  const p = normalizePresets({ 'text:fast': [{ flag: '-ncmoe', value: '20' }] })
  assert.deepEqual(p['text:fast'], [{ flag: '-ncmoe', value: '20' }])
  assert.notEqual(p['text:long'], undefined)
  assert.equal(argValue(p['text:fast'], '-ncmoe'), '20')
})

test('argValue: returns null when the flag is absent', () => {
  assert.equal(argValue([{ flag: '-c', value: '4096' }], '-ngl'), null)
  assert.equal(argValue(null, '-c'), null)
})
