/**
 * Local Compaction — 比例阈值压缩引擎（替代内置 dsh-compaction-basic）。
 *
 * 通过预设行 `name: 'dsh-local-llm-controller/compaction'` 加载：loader 对预设
 * 节点行只取模块的 default export（cordis-plugin-loader 规则），基类
 * CompactionEngine 在构造时注册为 ctx.compaction，/compact 命令自动兼容。
 *
 * 相对官方实现的三个行为差异（数学公式见 compaction-math.js）：
 *   1. 阈值按窗口成比例：min(ratio×W, W − 预留输出 − 自动边距)，适配 32k~150k
 *      本地小窗；官方写死 headroom 65536，在 32k 窗口上直接把阈值压成 0。
 *   2. 摘要调用输出预算按剩余空间动态推导，不再写死 65536 —— 避免摘要请求
 *      自身溢出窗口。
 *   3. 保留尾巴由"压缩后总占用 < 阈值"反推封顶，从构造上消除"下一轮立刻
 *      再压缩"的正反馈。
 *
 * 摘要降级阶梯（本地小模型的现实兜底）：
 *   路由模型本地摘要（复用 KV 前缀缓存；空摘要/失败重试一次）
 *   → 配置的云端 summarization 目标（可选）
 *   → 截断式检查点（确定性构造，不依赖任何模型，保证会话不卡死）。
 *
 * 触发与恢复机械（压缩锁、工具配对边界、稳定性复查、溢出恢复、手动 /compact）
 * 逐行改编自 @deepseek-ai/dsh-compaction-basic 0.2.0-rc.1（MIT）。
 */

import { randomUUID } from 'node:crypto'
import { isDeepStrictEqual } from 'node:util'

import z from '@deepseek-ai/schemastery'
import {
  CompactionEngine,
  CompactionId,
  ManualCompactionError,
  compactCheckpointSource,
  isCompactCheckpointSource,
  toolPairingBalancedAfter,
  toolPairingBalancedBefore,
} from '@deepseek-ai/dsh-compaction'
import {
  BlockAssembler,
  CONTEXT_WINDOW_EXCEEDED_CODE,
  LlmError,
  contentHasImage,
  createUserMessage,
  errorChain,
} from '@deepseek-ai/dsh-llm'
import { SessionSeq } from '@deepseek-ai/dsh-session'

import { clamp, marginTokens, resolveSpec, summaryCallBudget } from './compaction-math.js'

const LOG = '[local-compaction]'

/** 控制台日志用的简短错误消息（截断到 ~120 字符，不整只打印错误对象）。 */
function shortError(error) {
  const message = (error && error.message) || String(error)
  return message.length > 120 ? `${message.slice(0, 120)}…` : message
}

// ---------------------------------------------------------------------------
// 检查点文本：摘要指令 + 落盘前导
// ---------------------------------------------------------------------------

const SUMMARY_OPEN_TAG = '<compacted-summary>'
const SUMMARY_CLOSE_TAG = '</compacted-summary>'

/**
 * 摘要指令，作为回放对话之后的最后一条 user 消息发送（而非独立 system 提示）。
 * 让摘要调用成为最后一次路由请求的真前缀，从而复用 provider 的 KV 缓存。
 */
const COMPACTION_INSTRUCTION = [
  'You are now acting as a compaction engine for this AI coding assistant. Condense the conversation ABOVE into a structured checkpoint that lets another model resume the work with no loss of essential context.',
  '',
  'Output EXACTLY the Markdown structure below: keep every section, in order. Use terse bullets, not prose paragraphs. Write "(none)" for an empty section — never drop a section.',
  '',
  '## Primary Request and Intent',
  '- [the user\'s original and evolving goals; quote verbatim where the exact wording matters]',
  '',
  '## Key Technical Concepts',
  '- [technologies, frameworks, patterns, and conventions in play]',
  '',
  '## Files and Code',
  '- [exact path: why it matters, key changes or snippets]',
  '',
  '## Errors and Fixes',
  '- [error: how it was resolved, plus any related user feedback]',
  '',
  '## Pending Jobs',
  '- [explicitly requested work not yet completed]',
  '',
  '## Current Work',
  '- [precisely what was in progress at this checkpoint]',
  '',
  '## Next Step',
  '- [the single next action, directly in line with the most recent request, or "(none)"]',
  '',
  '## Critical Context',
  '- [decisions and their rationale, constraints, user preferences, open questions, data needed to continue]',
  '',
  'Rules:',
  '- Write concise English engineering prose. Preserve exact file paths, commands, error strings, identifiers, numeric values, function signatures, and syntax fragments.',
  '- Capture user feedback and explicit instructions faithfully, especially corrections.',
  '- Do NOT mention this summarization request or that the context was compacted.',
  '- Output only the checkpoint text: do not call any tool or take any other action.',
  `- If the conversation already contains a ${SUMMARY_OPEN_TAG} block, it is a PRIOR checkpoint. Do not copy it forward verbatim: preserve still-true facts, drop stale ones, and merge newer information into a single consolidated summary under the same structure.`,
].join('\n')

/** 让替换后的 user 消息成为"既定背景"的前导语。 */
const CHECKPOINT_PREAMBLE = 'This is an automatically generated checkpoint condensing an earlier span of the conversation to free up context. Treat the captured context as established background and build on it without restating it. Continue the task directly from the messages that follow, without acknowledging this checkpoint.'

// ---------------------------------------------------------------------------
// 配置解析（键收敛为本地场景所需的最小集合，无 modelPolicies）
// ---------------------------------------------------------------------------

const CONFIG_KEYS = new Set([
  'thresholdRatio',
  'retainRatio',
  'summaryReserveTokens',
  'summarizationProvider',
  'summarizationModel',
  'compactionRetries',
  'maxOverflowRetries',
  'auto',
])

/** 配置错误（携带 targetKey 供"每次目标只警告一次"去重）。 */
class TargetPressureConfigError extends Error {
  constructor(targetKey, message) {
    super(message)
    this.targetKey = targetKey
  }
}

function resolveConfig(config = {}) {
  for (const key of Object.keys(config)) {
    if (!CONFIG_KEYS.has(key)) throw new Error(`${LOG} 未知配置键 "${key}"`)
  }
  if (config.auto !== undefined && typeof config.auto !== 'boolean') throw new Error(`${LOG} auto 必须为布尔值`)
  const thresholdRatio = config.thresholdRatio ?? 0.7
  assertRatio('thresholdRatio', thresholdRatio)
  const retainRatio = config.retainRatio ?? 0.16
  assertRatio('retainRatio', retainRatio)
  if (retainRatio >= thresholdRatio) throw new Error(`${LOG} retainRatio (${retainRatio}) 必须小于 thresholdRatio (${thresholdRatio})`)
  const summaryReserveTokens = config.summaryReserveTokens ?? 8192
  assertNonNegativeInteger('summaryReserveTokens', summaryReserveTokens)
  const summarizationProvider = config.summarizationProvider ?? ''
  const summarizationModel = config.summarizationModel ?? ''
  if (summarizationProvider.length === 0 !== (summarizationModel.length === 0)) {
    throw new Error(`${LOG} summarizationProvider 与 summarizationModel 必须成对配置（同时为空或同时非空）`)
  }
  const compactionRetries = config.compactionRetries ?? 1
  const maxOverflowRetries = config.maxOverflowRetries ?? 1
  assertNonNegativeInteger('compactionRetries', compactionRetries)
  assertNonNegativeInteger('maxOverflowRetries', maxOverflowRetries)
  return deepFreeze({
    thresholdRatio,
    retainRatio,
    summaryReserveTokens,
    summarizationProvider,
    summarizationModel,
    compactionRetries,
    maxOverflowRetries,
    auto: config.auto ?? true,
  })
}

function assertRatio(name, value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > 1) {
    throw new Error(`${LOG} ${name} (${String(value)}) 必须是 (0, 1] 内的数值`)
  }
}

function assertNonNegativeInteger(name, value) {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) {
    throw new Error(`${LOG} ${name} (${String(value)}) 必须是非负整数`)
  }
}

/** 与 @deepseek-ai/dsh-util-values 的 deepFreeze 等价的本地实现（少一条 peer 链）。 */
function deepFreeze(value) {
  if (value !== null && typeof value === 'object') {
    for (const key of Object.keys(value)) deepFreeze(value[key])
    Object.freeze(value)
  }
  return value
}

// ---------------------------------------------------------------------------
// 摘要生成：LLM 调用（动态输出预算）+ 截断式兜底
// ---------------------------------------------------------------------------

/** 一次摘要调用的统一结果形状（provider/model 用于落盘的 compaction/summary 事件）。 */
async function summarizeWithLlm(ctx, target, input, agent, maxTokens, signal) {
  const assembler = new BlockAssembler()
  const messages = [
    ...input.messages,
    deepFreeze({ role: 'user', content: [{ type: 'text', text: COMPACTION_INSTRUCTION }] }),
  ]
  const options = {
    provider: target.provider,
    model: target.model,
    messages,
    toolHistory: agent.session.toolHistory(),
    ...(input.tools === undefined ? {} : { tools: [...input.tools] }),
    maxTokens,
    sessionId: agent.session.id,
    purpose: 'compaction',
    ...(signal === undefined ? {} : { signal }),
  }
  for await (const chunk of ctx.llm.stream(options)) assembler.push(chunk)
  const error = finishError(assembler.finish)
  if (error !== undefined) throw error
  const rawOutput = assembler.blocks()
  const summary = summaryText(rawOutput)
  if (!summary.some((block) => block.text.trim().length > 0)) throw new Error('summarization produced no text summary content')
  return {
    summary,
    rawOutput,
    llmStreamCall: true,
    provider: options.provider,
    model: options.model,
    maxTokens,
    ...(assembler.usage === undefined ? {} : { usage: assembler.usage }),
  }
}

/** 把终态 finish 映射为失败错误（max-tokens 视为截断失败）。 */
function finishError(finish) {
  switch (finish.kind) {
    case 'error':
    case 'aborted':
      return new LlmError(finish.failure.message, finish.failure.code, finish.failure)
    case 'max-tokens': {
      const error = new Error('summarization truncated at the token cap (incomplete checkpoint)')
      error.code = 'MAX_TOKENS'
      return error
    }
    default:
      return undefined
  }
}

/** 拒绝视觉输出，只保留文本块。 */
function summaryText(blocks) {
  if (contentHasImage(blocks)) throw new LlmError('compaction summary cannot contain image output', 'UNSUPPORTED_CONTENT')
  return blocks.filter((block) => block.type === 'text')
}

/** 用检查点前导 + 开闭标签包装摘要文本。 */
function frameSummary(summary) {
  return [
    { type: 'text', text: `${CHECKPOINT_PREAMBLE}\n\n${SUMMARY_OPEN_TAG}` },
    ...summary,
    { type: 'text', text: SUMMARY_CLOSE_TAG },
  ]
}

/** 工具 schema 的启发式 token 估算（4 字符/token）。 */
function estimateToolsTokens(tools) {
  if (!Array.isArray(tools) || tools.length === 0) return 0
  return Math.ceil(JSON.stringify(tools).length / 4)
}

/**
 * 确定性截断兜底：不依赖任何模型，按预算保留回放内容的头部（40%）与尾部
 * （60%），中间以省略标记衔接。预算取阴影区估算的 1/4（上限 4096 token），
 * 从构造上保证比被替换内容小，会话永远不会因摘要失败而卡死。
 */
function truncationFallback(meter, input, signal) {
  signal?.throwIfAborted?.()
  const shadowedEstimate = input.messages.reduce((total, message) => total + meter.estimateMessage(message), 0)
  const budgetTokens = Math.max(64, Math.min(4096, Math.floor(shadowedEstimate / 4)))
  const budgetChars = budgetTokens * 4
  const lines = []
  for (const message of input.messages) {
    const role = typeof message?.role === 'string' ? message.role : 'user'
    const content = Array.isArray(message?.content)
      ? message.content
      : typeof message?.content === 'string' ? [{ type: 'text', text: message.content }] : []
    const parts = []
    for (const block of content) {
      if (block?.type === 'text' && typeof block.text === 'string') parts.push(block.text)
      else if (block?.type === 'tool-call') parts.push(`[tool-call ${String(block.name ?? '')}] ${JSON.stringify(block.arguments ?? block.input ?? '').slice(0, 200)}`)
      else if (block?.type === 'tool-result') parts.push(`[tool-result] ${JSON.stringify(block.output ?? block.content ?? '').slice(0, 400)}`)
    }
    const joined = parts.join('\n').trim()
    if (joined.length > 0) lines.push(`--- ${role} ---\n${joined}`)
  }
  const body = lines.join('\n\n')
  let text
  if (body.length <= budgetChars) {
    text = body
  } else {
    const headChars = Math.floor(budgetChars * 0.4)
    const tailChars = budgetChars - headChars
    const omitted = body.length - headChars - tailChars
    text = `${body.slice(0, headChars)}\n\n[… 中间约 ${omitted} 字符已截断 …]\n\n${body.slice(body.length - tailChars)}`
  }
  if (text.trim().length === 0) text = '(空区域，无可摘要内容)'
  return {
    summary: [{ type: 'text', text: `## 截断式检查点（降级生成）\n\n${text}` }],
    provider: 'local-fallback',
    model: 'truncation',
    maxTokens: budgetTokens,
  }
}

// ---------------------------------------------------------------------------
// 区域机械（移植自 compaction-basic，语义不变）
// ---------------------------------------------------------------------------

/** 摘要构造期间表面被并发改写的判别错误（手动路径单独上报）。 */
class SurfaceChangedError extends Error {}

/** 表面节点 0 上的 system/message 事件（无则 undefined）。 */
function systemHead(session, headSeq) {
  const head = session.eventAt(headSeq)
  return head.type === 'system/message' ? head : undefined
}

/**
 * 选择下一个可压缩区间：从第一个非 system 表面节点开始，按 token 从尾部
 * 累积保留 retainTokens 的尾巴，并向回收缩到不切开工具调用/结果配对的边界。
 * 区间内必须至少有一个非检查点消息节点 —— 纯检查点区间（摘要的摘要）没有
 * 可合并的新内容，且几乎必然触发“摘要不小于被替换内容”不变量。
 *
 * 注意：区间两端是表面逻辑顺序下的 seq，不是单调递增的 —— 检查点消息的
 * seq 总是大于其逻辑后继的 seq（提交时才追加到事件日志）。日志需同时打印
 * 表面下标以免误读为“倒挂”。
 */
function selectCompactableRange(session, measurement, retainTokens) {
  const pricedNodes = measurement.nodes
  if (pricedNodes.length === 0) return null
  const surfaceNodes = session.surface.nodes
  if (surfaceNodes.length !== pricedNodes.length || surfaceNodes.some((seq, index) => seq !== pricedNodes[index]?.seq)) {
    throw new Error(`${LOG} token 计量表表面与当前会话表面不一致`)
  }
  const firstIdx = systemHead(session, surfaceNodes[0]) === undefined ? 0 : 1
  let accumulated = 0
  let keepFromIdx = pricedNodes.length
  for (let index = pricedNodes.length - 1; index >= 0; index -= 1) {
    accumulated += pricedNodes[index].tokens
    keepFromIdx = index
    if (accumulated >= retainTokens) break
  }
  if (keepFromIdx <= firstIdx) return null
  while (keepFromIdx > firstIdx) {
    if (toolPairingBalancedBefore(session, surfaceNodes[keepFromIdx])) break
    keepFromIdx -= 1
  }
  if (keepFromIdx <= firstIdx) return null
  for (let index = firstIdx; index < keepFromIdx; index += 1) {
    const message = session.deriveEventMessage(session.eventAt(surfaceNodes[index]))
    if (message !== null && !isCompactCheckpointSource(message.source ?? {})) {
      return { start: surfaceNodes[firstIdx], end: surfaceNodes[keepFromIdx - 1] }
    }
  }
  console.log(LOG + ` 区间 [表面${firstIdx}..${keepFromIdx - 1}] 仅含压缩检查点，无内容可合并，跳过选取`)
  return null
}

/** 异步工作开始前校验请求的表面位置区间。 */
function validateSurfaceRegion(session, start, end) {
  const nodes = session.surface.nodes
  const startIdx = nodes.indexOf(start)
  const endIdx = nodes.indexOf(end)
  if (startIdx === -1) throw new Error(`${LOG} start seq ${start} 不在当前表面`)
  if (endIdx === -1) throw new Error(`${LOG} end seq ${end} 不在当前表面`)
  if (startIdx > endIdx) throw new Error(`${LOG} start seq ${start} 位于 end seq ${end} 之后`)
  if (!toolPairingBalancedBefore(session, nodes[startIdx])) throw new Error(`${LOG} start seq ${start} 不是平衡边界（会切开工具调用/结果对）`)
  if (!toolPairingBalancedAfter(session, nodes[endIdx])) throw new Error(`${LOG} end seq ${end} 不是平衡边界（步骤未闭合）`)
  return { start, end, startIdx, endIdx, shadowedSeqs: nodes.slice(startIdx, endIdx + 1) }
}

/** 快照定价与回放输入。 */
function prepareCompaction(dependencies, session, selection) {
  const measurement = dependencies.meter.measure(session)
  const selectedNodes = measurement.nodes.slice(selection.startIdx, selection.endIdx + 1)
  if (selectedNodes.length !== selection.shadowedSeqs.length || selectedNodes.some((node, index) => node.seq !== selection.shadowedSeqs[index])) {
    throw new SurfaceChangedError(`${LOG} 摘要开始前所选表面已变化`)
  }
  return {
    ...selection,
    measurement,
    selectedNodes,
    shadowedTokenCount: selectedNodes.reduce((total, node) => total + node.heuristicTokens, 0),
    shadowedRouteTokenCount: selectedNodes.reduce((total, node) => total + node.tokens, 0),
    input: buildSummarizationInput(session, selection.shadowedSeqs),
  }
}

/** 运行摘要器并装配替换检查点（失败时经 recover 钩子重试）。 */
async function summarizeCompaction(dependencies, prepared, agent, compactionId, sourceCommandId, assertStable, signal) {
  let summaryResult
  let attempts = 0
  for (;;) {
    signal?.throwIfAborted()
    try {
      summaryResult = await dependencies.summarize(prepared.input, agent, signal)
      break
    } catch (error) {
      if (signal?.aborted === true) throw error
      assertStable(dependencies, agent.session, prepared)
      attempts += 1
      if (!dependencies.recover(error, agent, prepared.shadowedSeqs, signal)) throw error
      console.log(LOG + ` 摘要失败(第${attempts}次)，经 recover 重试: ${shortError(error)}`)
      prepared = prepareCompaction(dependencies, agent.session, validateSurfaceRegion(agent.session, prepared.start, prepared.end))
    }
  }
  const checkpointMessage = createUserMessage({
    content: frameSummary(summaryResult.summary),
    source: compactCheckpointSource(compactionId, sourceCommandId),
  })
  const framedSummaryTokenCount = dependencies.meter.estimateMessage(checkpointMessage)
  if (framedSummaryTokenCount >= prepared.shadowedRouteTokenCount) {
    throw new Error(`${LOG} 摘要不小于被替换内容（${framedSummaryTokenCount} 估算 framed token >= ${prepared.shadowedRouteTokenCount}）`)
  }
  return { ...prepared, ...summaryResult, checkpointMessage }
}

/** 要求整个表面在摘要期间保持原样（自动路径）。 */
function assertWholeSurfaceUnchanged(dependencies, session, prepared) {
  if (!isDeepStrictEqual(dependencies.meter.measure(session).nodes, prepared.measurement.nodes)) {
    throw new SurfaceChangedError(`${LOG} 摘要期间会话表面发生变化`)
  }
}

/** 只要求所选区间保持同一有效替换目标（手动路径，区间外新增节点不影响）。 */
function assertSelectedSpanStable(dependencies, session, prepared) {
  let current
  try {
    current = validateSurfaceRegion(session, prepared.start, prepared.end)
  } catch (error) {
    throw new SurfaceChangedError(`${LOG} 所选区间不再是有效替换目标`, { cause: error })
  }
  if (!isDeepStrictEqual([...current.shadowedSeqs], [...prepared.shadowedSeqs])) {
    throw new SurfaceChangedError(`${LOG} 摘要期间所选区间发生变化`)
  }
  if (!isDeepStrictEqual(dependencies.meter.measure(session).nodes.slice(current.startIdx, current.endIdx + 1), prepared.selectedNodes)) {
    throw new SurfaceChangedError(`${LOG} 摘要期间所选区间被改写`)
  }
}

/** 同步追加摘要记录与替换消息体（不 yield）。 */
function commitCompactionBody(session, startEvent, summarized) {
  const { start, end, shadowedSeqs, shadowedTokenCount, summary, provider, model, maxTokens, usage, checkpointMessage } = summarized
  const callRecord = summarized.llmStreamCall === true
    ? { rawOutput: summarized.rawOutput, llmStreamCall: true }
    : summarized.rawOutput === undefined ? {} : { rawOutput: summarized.rawOutput }
  const summaryEvent = session.append('compaction/summary', {
    compactionId: startEvent.data.compactionId,
    ...(startEvent.data.sourceCommandId === undefined ? {} : { sourceCommandId: startEvent.data.sourceCommandId }),
    summary,
    ...callRecord,
    shadowedRange: { start, end },
    shadowedSeqs: [...shadowedSeqs],
    shadowedTokenCount,
    provider,
    model,
    ...(maxTokens === undefined ? {} : { maxTokens }),
    ...(usage === undefined ? {} : { usage }),
  })
  session.append('user/message', checkpointMessage, {
    surfaceOp: { op: 'replace', startSeq: start, endSeq: end },
    sourceEventSeqs: [startEvent.seq, summaryEvent.seq, ...shadowedSeqs],
  })
  return {
    compactionId: startEvent.data.compactionId,
    ...(startEvent.data.sourceCommandId === undefined ? {} : { sourceCommandId: startEvent.data.sourceCommandId }),
    startSeq: startEvent.seq,
    summarySeq: summaryEvent.seq,
    summary,
    shadowedRange: { start, end },
    shadowedSeqs: [...shadowedSeqs],
    shadowedTokenCount,
  }
}

/** 闭合事件附加到待完成结果上。 */
function completeCompaction(pending, endEvent) {
  return { ...pending, endSeq: endEvent.seq }
}

/**
 * 重建阴影区最后一次路由请求的可缓存前缀：system 提示 + 请求头工具 schema +
 * 区间自身的消息（表面顺序）。摘要器只在其后追加指令，调用因此成为对话的
 * 真前缀，复用 provider 的 KV 缓存。
 */
function buildSummarizationInput(session, shadowedSeqs) {
  const header = session.requestHeader()
  const head = systemHead(session, session.surface.nodes[0])
  const system = head === undefined ? null : session.deriveEventMessage(head)
  const regionMessages = shadowedSeqs.map((seq) => session.deriveEventMessage(session.eventAt(seq))).filter((message) => message !== null)
  return {
    ...(header?.tools === undefined ? {} : { tools: header.tools }),
    messages: system === null ? regionMessages : [system, ...regionMessages],
  }
}

/** 独立检查开回合、未闭合压缩标记与最新种子边界状态。 */
function inspectCompactionEntryState(session) {
  let openTurn = null
  let openTurnStateKnown = false
  let unmatchedCompactionStart
  let compactionEntryStateKnown = false
  let latestEndSeedSeq
  for (let seq = session.seq - 1; seq >= 0; seq -= 1) {
    const event = session.eventAt(SessionSeq(seq))
    if (latestEndSeedSeq === undefined && event.type === 'session/end-seed') latestEndSeedSeq = event.seq
    if (!compactionEntryStateKnown) {
      if (event.type === 'compaction/start') {
        unmatchedCompactionStart = event
        compactionEntryStateKnown = true
      } else if (event.type === 'compaction/end') compactionEntryStateKnown = true
    }
    if (!openTurnStateKnown) {
      if (event.type === 'turn/start') {
        openTurn = event.data.turn
        openTurnStateKnown = true
      } else if (event.type === 'turn/end') openTurnStateKnown = true
    }
    if (openTurnStateKnown && compactionEntryStateKnown && latestEndSeedSeq !== undefined) break
  }
  return { openTurn, unmatchedCompactionStart, latestEndSeedSeq }
}

/** 拒绝存活的未闭合压缩标记（除非更晚的构造种子边界证明它属于上一轮生命周期）。 */
function assertCompactionInactive(unmatchedCompactionStart, latestEndSeedSeq, stage) {
  if (unmatchedCompactionStart === undefined || (latestEndSeedSeq !== undefined && latestEndSeedSeq > unmatchedCompactionStart.seq)) return
  throw new ManualCompactionError('busy', `${LOG} ${stage}: 压缩已在进行中（压缩锁已激活）`)
}

/** 异步策略决策后复查持久压缩锁。 */
function assertNoActiveCompaction(session, stage) {
  const entryState = inspectCompactionEntryState(session)
  assertCompactionInactive(entryState.unmatchedCompactionStart, entryState.latestEndSeedSeq, stage)
}

/** 手动路径失败分类（不削弱取消优先级）。 */
function throwManualFailure(failure) {
  if (failure.stage === 'commit') throw new ManualCompactionError('commit', `${LOG} 手动压缩未能干净提交`, { cause: failure.error })
  if (failure.error instanceof SurfaceChangedError) throw new ManualCompactionError('changed', `${LOG} 手动压缩期间历史发生变化`, { cause: failure.error })
  throw new ManualCompactionError('summary', `${LOG} 手动压缩无法产出更小的摘要`, { cause: failure.error })
}

/**
 * 对一个选定位置区间执行单次压缩事务。选择与校验只读；空闲/日志校验与
 * compaction/start 同步相邻，因此持久开启标记就是摘要 yield 前的压缩锁。
 * 每个后续失败恰好做一次 compaction/end 尝试；闭合失败会留下可检测的
 * 未匹配 start。
 */
async function compactSurfaceRegion(dependencies, session, start, end, agent, options, signal) {
  if (options.owner === null) signal?.throwIfAborted()
  const selection = validateSurfaceRegion(session, start, end)
  const entryState = inspectCompactionEntryState(session)
  assertCompactionInactive(entryState.unmatchedCompactionStart, entryState.latestEndSeedSeq, 'compaction')
  let owner
  if (options.owner === null) {
    if (entryState.openTurn !== null) throw new ManualCompactionError('busy', `${LOG} 手动压缩：会话已有未闭合回合`)
    owner = null
  } else {
    if (entryState.openTurn === null) throw new Error(`${LOG} compactRegion: 无开启回合 —— 自动压缩事件必须被回合包住`)
    owner = entryState.openTurn
  }
  const compactionId = CompactionId(randomUUID())
  const lifecycle = {
    compactionId,
    ...(options.sourceCommandId === undefined ? {} : { sourceCommandId: options.sourceCommandId }),
    turn: owner,
  }
  const startEvent = session.append('compaction/start', lifecycle)
  const assertStable = options.stability === 'whole-surface' ? assertWholeSurfaceUnchanged : assertSelectedSpanStable
  let failure
  let flushFailure
  let result
  let closed = false
  let closing = false
  let stage = 'summary'
  try {
    const summarized = await summarizeCompaction(dependencies, prepareCompaction(dependencies, session, selection), agent, compactionId, options.sourceCommandId, assertStable, signal)
    if (options.owner === null) signal?.throwIfAborted()
    assertStable(dependencies, session, summarized)
    stage = 'commit'
    const pending = commitCompactionBody(session, startEvent, summarized)
    closing = true
    const endEvent = session.append('compaction/end', lifecycle)
    closed = true
    result = completeCompaction(pending, endEvent)
  } catch (error) {
    failure = { error, stage: closing ? 'commit' : stage }
    if (!closing) {
      closing = true
      try {
        session.append('compaction/end', { ...lifecycle, error: errorChain(error) })
        closed = true
      } catch (closeError) {
        failure = { error: closeError, stage: 'commit' }
      }
    }
  }
  if (closed && options.flush !== undefined) {
    try {
      await options.flush()
    } catch (error) {
      flushFailure = error
    }
  }
  if (options.owner === null) signal?.throwIfAborted()
  if (failure !== undefined) {
    if (options.owner === null) throwManualFailure(failure)
    throw failure.error
  }
  if (flushFailure !== undefined) throw new ManualCompactionError('persistence', `${LOG} 手动压缩持久化检查点失败`, { cause: flushFailure })
  if (result === undefined) throw new Error(`${LOG} 压缩已提交但没有结果`)
  const summaryTokens = Math.ceil(result.summary.reduce((total, block) => total + (typeof block.text === 'string' ? block.text.length : 0), 0) / 4)
  console.log(LOG + ` 压缩完成: 表面[${selection.startIdx}..${selection.endIdx}] seq ${result.shadowedRange.start}..${result.shadowedRange.end} shadow=${result.shadowedTokenCount} 摘要≈${summaryTokens} tokens 压缩后 surface=${dependencies.meter.measure(session).totalTokens}`)
  return result
}

// ---------------------------------------------------------------------------
// 引擎本体
// ---------------------------------------------------------------------------

/** 解析最近一次路由请求的准确 provider/model。 */
function routedTarget(session) {
  const config = session.requestHeader()?.config
  if (config === undefined || config.provider.length === 0 || config.model.length === 0) return undefined
  return { provider: config.provider, model: config.model }
}

/** 路由请求预留的输出 token（信封自己的 maxTokens 优先，其次适配器默认值）。 */
function reservedCompletionTokens(agent, defaultMaxTokens) {
  return agent.session.requestHeader()?.config.maxTokens ?? defaultMaxTokens ?? 0
}

/** 会话目标：路由目标优先，其次 AgentOptions（用于解析可选覆盖）。 */
function conversationTarget(agent) {
  const routed = routedTarget(agent.session)
  if (routed !== undefined) return routed
  if (agent.options.provider === undefined || agent.options.provider.length === 0 || agent.options.model === undefined || agent.options.model.length === 0) return undefined
  return { provider: agent.options.provider, model: agent.options.model }
}

const thresholdRatioSchema = z.number()
const retainRatioSchema = z.number()
const summaryReserveTokensSchema = z.number().step(1).min(0)
const summarizationProviderSchema = z.string()
const summarizationModelSchema = z.string()
const compactionRetriesSchema = z.number().step(1).min(0)
const maxOverflowRetriesSchema = z.number().step(1).min(0)

/**
 * 比例阈值压缩引擎。用 ctx.tokenMeter 计价压力、保留与摘要收敛。
 * `summarize()` 是唯一自定义钩子（本实现内含降级阶梯）；回放与持久化
 * 策略保持与官方一致，所有定价决策都使用单例 token 计量表。
 */
var LocalCompactionEngine = class extends CompactionEngine {
  static inject = ['llm', 'tokenMeter', 'sessions']
  static Config = z.object({
    thresholdRatio: thresholdRatioSchema,
    retainRatio: retainRatioSchema,
    summaryReserveTokens: summaryReserveTokensSchema,
    summarizationProvider: summarizationProviderSchema,
    summarizationModel: summarizationModelSchema,
    compactionRetries: compactionRetriesSchema,
    maxOverflowRetries: maxOverflowRetriesSchema,
    auto: z.boolean(),
  })

  config
  warnedTargets = new Set()
  overflowRetries = new WeakMap()
  overflowAgents = new WeakMap()

  constructor(ctx, config = {}) {
    super(ctx)
    this.config = resolveConfig(config)
    if (this.config.auto) this._registerAutomaticCompaction()
  }

  /**
   * 注册步间压力触发与模型请求溢出恢复。compactIfNeeded 保持动态派发，
   * 子类覆盖在事件时刻生效。
   */
  _registerAutomaticCompaction() {
    const { ctx } = this
    const logResult = (result, trigger) => {
      ctx.logger.info(`${LOG} (${trigger}): 替换 ${result.shadowedSeqs.length} 个表面节点（seq ${result.shadowedRange.start}-${result.shadowedRange.end}，约 ${result.shadowedTokenCount} token）`)
    }
    ctx.on('agent/pre-step', async ({ agent, signal }, next) => {
      if (!signal.aborted) {
        try {
          const result = await this.compactIfNeeded(agent, 'pressure', signal)
          if (result !== null) logResult(result, 'step pressure')
        } catch (error) {
          if (error instanceof TargetPressureConfigError) {
            if (this.warnedTargets.has(error.targetKey)) return next()
            this.warnedTargets.add(error.targetKey)
          }
          const message = error instanceof Error ? error.message : String(error)
          ctx.logger.warn(`${LOG} 步间压缩失败: ${message}；回合继续`)
        }
      }
      return next()
    })
    ctx.on('agent/status', ({ agent, status }) => {
      if (status === 'idle') this.overflowRetries.delete(agent)
    })
    ctx.on('session/event', (session, event) => {
      if (event.type !== 'assistant/message') return
      const agent = this.overflowAgents.get(session)
      if (agent !== undefined) this.overflowRetries.delete(agent)
    })
    ctx.on('agent/request-error', async ({ agent, failure, signal }, next) => {
      if (failure.code !== CONTEXT_WINDOW_EXCEEDED_CODE || signal.aborted) return next()
      this.overflowAgents.set(agent.session, agent)
      const target = routedTarget(agent.session)
      if (target === undefined) return next()
      const retries = this.overflowRetries.get(agent) ?? 0
      if (retries >= this.config.maxOverflowRetries) return next()
      console.log(LOG + ` 溢出恢复触发: ${failure.code} ${shortError(failure)}`)
      const generation = agent.session.surface.replaceGeneration
      let result
      try {
        result = await this.compactIfNeeded(agent, 'context-overflow', signal)
      } catch (recoveryError) {
        const message = recoveryError instanceof Error ? recoveryError.message : String(recoveryError)
        if (!signal.aborted && agent.session.surface.replaceGeneration > generation) {
          ctx.logger.warn(`${LOG} 溢出压缩在持久表面推进后失败: ${message}；从替换后的表面重试`)
          this.overflowRetries.set(agent, retries + 1)
          return { kind: 'retry' }
        }
        ctx.logger.warn(`${LOG} 溢出压缩失败: ${message}；${signal.aborted ? '取消阻止重试' : '保留原始请求错误'}`)
        return next()
      }
      if (signal.aborted || agent.session.surface.replaceGeneration <= generation) return next()
      if (result !== null) logResult(result, 'context overflow recovery')
      this.overflowRetries.set(agent, retries + 1)
      return { kind: 'retry' }
    })
  }

  /**
   * 摘要降级阶梯：
   *   1. 路由模型本地摘要（回放前缀复用 KV 缓存；失败/空摘要重试一次）；
   *   2. 配置的云端 summarization 目标（可选，预算按其自身窗口推导）；
   *   3. 截断式检查点兜底（确定性，保证压缩总能落地）。
   * 本地剩余空间不足以容纳任何摘要调用时跳过对应目标，直接降级。
   */
  async summarize(input, agent, signal) {
    signal?.throwIfAborted?.()
    const meter = this.ctx.tokenMeter
    const instructionTokens = meter.estimateMessage(createUserMessage({ content: [{ type: 'text', text: COMPACTION_INSTRUCTION }] }))
    const replayTokens = input.messages.reduce((total, message) => total + meter.estimateMessage(message), instructionTokens) + estimateToolsTokens(input.tools)
    const routed = conversationTarget(agent)
    console.log(LOG + ` 摘要开始: 回放≈${replayTokens} token 路由=${routed === undefined ? '无' : `${routed.provider}/${routed.model}`}`)
    // 1) 路由模型本地摘要
    if (routed !== undefined) {
      try {
        const info = await this.ctx.llm.resolveModelInfo(routed.provider, routed.model, signal)
        const windowSize = info?.context?.contextWindow
        if (Number.isInteger(windowSize) && windowSize > 0) {
          const budget = summaryCallBudget(windowSize, replayTokens, marginTokens(windowSize))
          if (budget === null) {
            console.log(LOG + ` 本地摘要预算不足(回放≈${replayTokens} token)，降级云端`)
            this.ctx.logger.warn(`${LOG} ${routed.provider}/${routed.model}: 剩余空间不足以容纳摘要调用（回放约 ${replayTokens} token），跳过本地摘要`)
          } else {
            console.log(LOG + ` 摘要阶梯[本地] ${routed.provider}/${routed.model} 预算=${budget} token`)
            for (let attempt = 1; attempt <= 2; attempt += 1) {
              try {
                return await summarizeWithLlm(this.ctx, routed, input, agent, budget, signal)
              } catch (error) {
                if (signal?.aborted === true) throw error
                this.ctx.logger.warn(`${LOG} 本地摘要第 ${attempt} 次失败（${routed.provider}/${routed.model}）: ${error instanceof Error ? error.message : String(error)}`)
              }
            }
            console.log(LOG + ` 本地摘要 ${routed.provider}/${routed.model} 两次尝试均失败，降级下一级`)
          }
        } else {
          console.log(LOG + ` 本地模型 ${routed.provider}/${routed.model} 未声明上下文窗口，跳过本地摘要`)
        }
      } catch (error) {
        if (signal?.aborted === true) throw error
        this.ctx.logger.warn(`${LOG} 本地摘要目标解析失败: ${error instanceof Error ? error.message : String(error)}`)
      }
    }
    // 2) 云端摘要回退（成对配置时启用）
    const { summarizationProvider, summarizationModel } = this.config
    if (summarizationProvider.length > 0 && summarizationModel.length > 0) {
      try {
        const info = await this.ctx.llm.resolveModelInfo(summarizationProvider, summarizationModel, signal).catch(() => undefined)
        const windowSize = info?.context?.contextWindow
        const budget = Number.isInteger(windowSize) && windowSize > 0
          ? summaryCallBudget(windowSize, replayTokens, marginTokens(windowSize))
          : 8192
        console.log(LOG + ` 摘要阶梯[云端] ${summarizationProvider}/${summarizationModel} 预算=${budget === null ? '不足' : `${budget} token`}`)
        if (budget !== null) {
          return await summarizeWithLlm(this.ctx, { provider: summarizationProvider, model: summarizationModel }, input, agent, budget, signal)
        }
      } catch (error) {
        if (signal?.aborted === true) throw error
        this.ctx.logger.warn(`${LOG} 云端摘要失败（${summarizationProvider}/${summarizationModel}）: ${error instanceof Error ? error.message : String(error)}`)
      }
    }
    // 3) 截断式检查点兜底
    console.log(LOG + ' 摘要阶梯[截断兜底] 无可用摘要模型，降级截断式检查点')
    this.ctx.logger.warn(`${LOG} 摘要降级为截断式检查点（无可用摘要模型）`)
    return truncationFallback(meter, input, signal)
  }

  /**
   * 步间压力或 provider 确认的上下文溢出触发压缩。两个触发都用最近持久
   * 路由请求信封计价；溢出路径绕过阈值与尾巴策略以强制一次有效缩减。
   */
  async compactIfNeeded(agent, trigger, signal) {
    const target = routedTarget(agent.session)
    if (target === undefined) return null
    const meter = this.ctx.tokenMeter
    let measurement = meter.measure(agent.session)
    const prune = this.ctx.get('toolResultPruner')
    if (trigger === 'context-overflow') {
      if (prune !== undefined) {
        prune.pruneSession(agent.session)
        measurement = meter.measure(agent.session)
      }
      const range = selectCompactableRange(agent.session, measurement, 0)
      if (range === null) return null
      return this.compactRegion(range.start, range.end, agent, signal)
    }
    const info = await this.ctx.llm.resolveModelInfo(target.provider, target.model, signal)
    assertNoActiveCompaction(agent.session, 'automatic pressure compaction')
    const targetKey = `${target.provider}/${target.model}`
    if (info.context === undefined) {
      throw new TargetPressureConfigError(targetKey, `${LOG} ${targetKey} 未声明上下文容量；请在该适配器模型上配置 contextWindow`)
    }
    const reserved = reservedCompletionTokens(agent, info.defaultMaxTokens)
    const spec = resolveSpec({
      windowSize: info.context.contextWindow,
      reserved,
      thresholdRatio: this.config.thresholdRatio,
      retainRatio: this.config.retainRatio,
      summaryReserveTokens: this.config.summaryReserveTokens,
    })
    if (spec.thresholdTokens <= 0) {
      throw new TargetPressureConfigError(targetKey, `${LOG} ${targetKey}: 预留输出 ${reserved} + 边距 ${spec.margin} 吃满 ${info.context.contextWindow} 的窗口，没有压力预算；请调低该模型条目的 maxTokens`)
    }
    if (spec.thresholdTokens < spec.proportional && !this.warnedTargets.has(targetKey)) {
      this.warnedTargets.add(targetKey)
      this.ctx.logger.warn(`${LOG} ${targetKey}: 预留输出 ${reserved} + 边距 ${spec.margin} 挤压阈值，从比例值 ${spec.proportional} 下调为 ${spec.thresholdTokens}（窗口 ${info.context.contextWindow}）`)
    }
    console.log(LOG + ` 压力检查: surface=${measurement.totalTokens} 阈值=${spec.thresholdTokens} 窗口=${info.context.contextWindow} → ${measurement.totalTokens >= spec.thresholdTokens ? '触发' : '未触发'}`)
    if (measurement.totalTokens < spec.thresholdTokens) return null
    console.log(LOG + ` pre-step 压力触发: pressure=${measurement.totalTokens} 阈值=${spec.thresholdTokens}，先修剪工具结果`)
    if (prune !== undefined) {
      prune.pruneSession(agent.session)
      measurement = meter.measure(agent.session)
    }
    if (measurement.totalTokens < spec.thresholdTokens) {
      console.log(LOG + ` 修剪后未触发: surface=${measurement.totalTokens} < 阈值=${spec.thresholdTokens}`)
      return null
    }
    let result = null
    for (let attempt = 0; attempt <= this.config.compactionRetries; attempt += 1) {
      const range = selectCompactableRange(agent.session, measurement, spec.retainTokens)
      if (range === null) {
        if (result === null) return null
        // 已压缩过但 surface 仍高于阈值且无可选区间：剩余为保留尾巴/纯检查点，
        // 不再重试也不中止步骤 —— 阈值是压力策略线而非硬溢出，真实溢出由
        // context-overflow 触发器（retainTokens=0 强制压缩）兜底。
        console.log(LOG + ` 已无进一步可压缩区间（剩余为保留尾巴/检查点），surface=${measurement.totalTokens} 仍高于阈值 ${spec.thresholdTokens}；本轮回此为止，溢出由 overflow 兜底`)
        return result
      }
      const surfaceNodes = agent.session.surface.nodes
      console.log(LOG + ` 开始压缩(第${attempt + 1}次): 表面[${surfaceNodes.indexOf(range.start)}..${surfaceNodes.indexOf(range.end)}] seq ${range.start}..${range.end}`)
      result = await this.compactRegion(range.start, range.end, agent, signal)
      measurement = meter.measure(agent.session)
      if (measurement.totalTokens < spec.thresholdTokens) return result
    }
    throw new Error(`${LOG} ${this.config.compactionRetries + 1} 次压缩后仍高于阈值（${measurement.totalTokens} 估算 token >= 阈值 ${spec.thresholdTokens}）`)
  }

  /** 用有效 token 计量表对 agent 拥有的表面压缩一个闭区间。 */
  async compactRegion(start, end, agent, signal) {
    return compactSurfaceRegion(this.regionDependencies(), agent.session, start, end, agent, {
      owner: 'current-turn',
      stability: 'whole-surface',
    }, signal)
  }

  /** 空闲会话的手动压缩（/compact），独立标记对持久化后才返回。 */
  compactNow(agent, signal, sourceCommandId) {
    signal.throwIfAborted()
    console.log(LOG + ' 手动压缩 (/compact): 开始')
    try {
      return agent.runMaintenance(async (agentSignal) => {
        const operationSignal = AbortSignal.any([agentSignal, signal])
        try {
          operationSignal.throwIfAborted()
          const range = selectCompactableRange(agent.session, this.ctx.tokenMeter.measure(agent.session), 0)
          if (range === null) return null
          return await compactSurfaceRegion(this.regionDependencies(), agent.session, range.start, range.end, agent, {
            owner: null,
            stability: 'selected-span',
            ...(sourceCommandId === undefined ? {} : { sourceCommandId }),
            flush: async () => {
              await this.ctx.sessions.flush(agent.session)
            },
          }, operationSignal)
        } catch (error) {
          if (agentSignal.aborted && operationSignal.reason === agentSignal.reason) throw new ManualCompactionError('cancelled', `${LOG} 手动压缩已取消`, { cause: error })
          operationSignal.throwIfAborted()
          throw error
        }
      })
    } catch (error) {
      throw new ManualCompactionError('busy', `${LOG} 手动压缩需要空闲且无排队唤醒工作的 agent`, { cause: error })
    }
  }

  /** 绑定有效 token 计量表与动态派发的摘要钩子。 */
  regionDependencies() {
    return {
      meter: this.ctx.tokenMeter,
      summarize: (input, owner, abort) => this.summarize(input, owner, abort),
      recover: (error, agent, sourceEventSeqs, signal) => this.ctx.waterfall('compaction/summary-error', {
        session: agent.session,
        sourceEventSeqs,
        error,
        ...(signal === undefined ? {} : { signal }),
      }, () => false),
    }
  }
}

export { LocalCompactionEngine, LocalCompactionEngine as default, selectCompactableRange }
