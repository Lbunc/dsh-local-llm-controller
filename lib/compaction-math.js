/**
 * Local Compaction — 纯数学推导层（零依赖，单测可直接导入）。
 *
 * 相对 dsh-compaction-basic 的两处根治（公式详见各函数注释）：
 *   1. 阈值按窗口成比例，且预留输出与安全边距参与推导 —— 修复原版写死
 *      headroom 65536 导致小窗（32k）阈值归零、压缩被整体禁用的问题；
 *   2. 保留尾巴由"压缩后总占用 < 阈值"反推封顶 —— 从构造上消除
 *      "摘要 + 尾巴在下一轮又触发压缩"的正反馈循环。
 */

/** 区间截断。 */
export function clamp(v, lo, hi) {
  return Math.min(Math.max(v, lo), hi)
}

/** 压缩安全边距：随窗口 5% 缩放，限制在 [1024, 8192]。 */
export function marginTokens(windowSize) {
  return clamp(Math.floor(windowSize * 0.05), 1024, 8192)
}

/**
 * 派生一次压缩的完整预算规格。
 *
 *   margin          = clamp(floor(0.05×W), 1024, 8192)
 *   threshold       = floor(min(ratio×W, W − reserved − margin))
 *   summaryUpper    = min(max(1024, summaryReserve), max(1024, floor(0.25×W)))
 *   retain（尾巴）  = min(floor((W − reserved)×retainRatio), threshold − summaryUpper − margin)
 *
 * threshold 取比例值与压力预算的较小者：reserved 过大（如 0.5W）时阈值自动
 * 下调而不是把压缩彻底禁用；retain 的 tailCap 封顶保证
 * "压缩后总占用 ≈ retain + 摘要 ≤ threshold − margin"，
 * 下一轮不会再触发（根治正反馈）。
 *
 * @param windowSize         适配器报告的上下文窗口 W（正整数）
 * @param reserved           单次请求预留的输出 maxTokens（非负；0 表示未知）
 * @param thresholdRatio     触发比例（默认 0.7）
 * @param retainRatio        原文尾巴比例（默认 0.16，按消息预算计）
 * @param summaryReserveTokens 检查点消息的预留上限（默认 8192）
 * @returns thresholdTokens ≤ 0 表示 reserved+margin 吃满窗口，无法触发。
 */
export function resolveSpec({ windowSize, reserved = 0, thresholdRatio = 0.7, retainRatio = 0.16, summaryReserveTokens = 8192 }) {
  const margin = marginTokens(windowSize)
  const proportional = Math.floor(windowSize * thresholdRatio)
  const pressureBudget = windowSize - reserved - margin
  const thresholdTokens = Math.min(proportional, pressureBudget)
  if (thresholdTokens <= 0) {
    return { margin, proportional, thresholdTokens: 0, summaryUpper: 0, tailCap: 0, retainTokens: 0 }
  }
  // 摘要预留自身不许吃掉小窗：下限 1024，上限随 0.25W 缩放
  const summaryUpper = Math.min(Math.max(1024, summaryReserveTokens), Math.max(1024, Math.floor(windowSize * 0.25)))
  const tailCap = Math.max(0, thresholdTokens - summaryUpper - margin)
  const proportionalRetain = Math.floor((windowSize - reserved) * retainRatio)
  const retainTokens = Math.min(proportionalRetain, tailCap)
  return { margin, proportional, thresholdTokens, summaryUpper, tailCap, retainTokens }
}

/**
 * 摘要调用的输出预算：W − 回放输入估算 − margin。不足 1024 返回 null，
 * 调用方跳过注定溢出的摘要请求，直接走降级阶梯（云端 → 截断兜底）。
 * 修复原版写死 65536 输出上限在 32k 窗口上必然越界的问题。
 */
export function summaryCallBudget(windowSize, replayTokens, margin) {
  const budget = Math.floor(windowSize - replayTokens - margin)
  return budget >= 1024 ? budget : null
}
