import { ChatMessage } from '../models/ChatModels'
import { estimateConversationInputTokens, estimateTextTokens } from './ModelBillingUtils'

// 仅保留兼容导出。模型窗口不再被强行抬高到该值，配置多少就按多少计算。
export const MIN_CONTEXT_WINDOW_TOKENS: number = 2048

// 模型的上下文长度未填写时使用的默认窗口。
export const DEFAULT_MODEL_CONTEXT_WINDOW_TOKENS: number = 256000

// 用户可设置的上下文长度窗口上限：超大窗口模型（例如 1M）按该上限计算用量，
// 避免把全部窗口都当成可用预算
export const MIN_CONTEXT_LIMIT_TOKENS: number = 100000
export const MAX_CONTEXT_LIMIT_TOKENS: number = 1000000
export const DEFAULT_CONTEXT_LIMIT_TOKENS: number = 500000
export const CONTEXT_LIMIT_TOKENS_STEP: number = 50000

// 触发压缩提醒的默认阈值与可配置范围（百分比）
export const DEFAULT_COMPACT_THRESHOLD_PERCENT: number = 80
export const MIN_COMPACT_THRESHOLD_PERCENT: number = 50
export const MAX_COMPACT_THRESHOLD_PERCENT: number = 95
export const COMPACT_THRESHOLD_PERCENT_STEP: number = 5

// 低于该条数的历史不值得压缩，压缩收益小于摘要本身的开销。
// 只在模型窗口未知时作为唯一判据；窗口已知时以 MIN_COMPACT_USAGE_PERCENT 为准。
export const MIN_COMPACTABLE_MESSAGE_COUNT: number = 6

// 压缩下限（“绝不压缩”阈值）：用量低于窗口的该比例时压缩收益小于摘要开销。
// 反过来，只要用量超过该比例，即使历史只有一两条消息也允许压缩——
// 单条消息也可能很重（例如子智能体一次带回巨量工具结果）。
export const MIN_COMPACT_USAGE_PERCENT: number = 15

export function isContextHeavyEnoughToCompact(usedTokens: number, contextWindowTokens: number): boolean {
  if (!Number.isFinite(contextWindowTokens) || contextWindowTokens <= 0) {
    return false
  }
  if (!Number.isFinite(usedTokens) || usedTokens <= 0) {
    return false
  }
  return usedTokens * 100 >= contextWindowTokens * MIN_COMPACT_USAGE_PERCENT
}

// 上下文用量快照。ratio 以 usedTokens / limitTokens 计算；limitTokens 是扣除
// 最大输出预算后的安全输入预算，modelWindowTokens 才是模型/用户上限决定的总窗口。
// limitTokens 为 0 表示当前模型的窗口还没解析出来（例如供应商尚未加载完成），
// 此时用量不可用，UI 不应显示进度，也不应触发压缩提醒。
@ObservedV2
export class ContextUsage {
  @Trace usedTokens: number = 0
  @Trace limitTokens: number = 0
  @Trace thresholdPercent: number = DEFAULT_COMPACT_THRESHOLD_PERCENT
  @Trace compacted: boolean = false
  @Trace modelWindowTokens: number = 0
  @Trace outputReserveTokens: number = 0

  constructor(
    usedTokens: number = 0,
    limitTokens: number = 0,
    thresholdPercent: number = DEFAULT_COMPACT_THRESHOLD_PERCENT,
    compacted: boolean = false,
    modelWindowTokens: number = 0,
    outputReserveTokens: number = 0
  ) {
    this.usedTokens = Math.max(0, Math.round(usedTokens))
    this.limitTokens = Number.isFinite(limitTokens) && limitTokens > 0 ? Math.floor(limitTokens) : 0
    this.thresholdPercent = normalizeCompactThresholdPercent(thresholdPercent)
    this.compacted = compacted
    this.modelWindowTokens = Number.isFinite(modelWindowTokens) && modelWindowTokens > 0 ?
      Math.floor(modelWindowTokens) : this.limitTokens
    this.outputReserveTokens = Number.isFinite(outputReserveTokens) && outputReserveTokens > 0 ?
      Math.floor(outputReserveTokens) : 0
  }

  // 当前模型的上下文窗口是否已知
  get resolved(): boolean {
    return this.limitTokens > 0
  }

  // 0 ~ 1，可超过 1（历史已超出窗口）
  get ratio(): number {
    return this.resolved ? this.usedTokens / this.limitTokens : 0
  }

  // 展示用整数百分比，不做上限截断，超窗时应如实显示
  get percent(): number {
    return Math.round(this.ratio * 100)
  }

  get remainingTokens(): number {
    return Math.max(0, this.limitTokens - this.usedTokens)
  }

  get overThreshold(): boolean {
    return this.resolved && this.percent >= this.thresholdPercent
  }
}

// 解析模型实际可用的上下文长度窗口。未填写 contextLength 时按 256K 处理，
// 然后再受用户设置的上下文长度上限约束。模型未找到的情况由调用方保持为 0。
export function resolveContextWindowTokens(contextLength: number, maxLimitTokens: number): number {
  const modelWindow = Number.isFinite(contextLength) && contextLength > 0 ?
    Math.floor(contextLength) : DEFAULT_MODEL_CONTEXT_WINDOW_TOKENS
  return Math.min(modelWindow, normalizeContextLimitTokens(maxLimitTokens))
}

// 从总窗口扣除输出上限，得到本次请求允许占用的最大输入预算。
export function resolveContextInputBudgetTokens(contextWindowTokens: number, maxOutputTokens: number): number {
  if (!Number.isFinite(contextWindowTokens) || contextWindowTokens <= 0) {
    return 0
  }
  const windowTokens = Math.floor(contextWindowTokens)
  const requestedReserve = Number.isFinite(maxOutputTokens) ? Math.max(0, Math.floor(maxOutputTokens)) : 0
  const reserve = Math.min(requestedReserve, Math.max(0, windowTokens - 1))
  return Math.max(1, windowTokens - reserve)
}

// 请求真正发送时再根据实际输入收紧输出上限，避免 input + max_output 超过窗口。
export function resolveRequestMaxOutputTokens(
  configuredMaxOutputTokens: number,
  contextWindowTokens: number,
  inputTokens: number
): number {
  const configured = Number.isFinite(configuredMaxOutputTokens) ?
    Math.max(1, Math.floor(configuredMaxOutputTokens)) : 1
  if (!Number.isFinite(contextWindowTokens) || contextWindowTokens <= 0) {
    return configured
  }
  const available = Math.max(1, Math.floor(contextWindowTokens) - Math.max(0, Math.ceil(inputTokens)))
  return Math.min(configured, available)
}

export function normalizeContextLimitTokens(tokens: number): number {
  if (!Number.isFinite(tokens)) {
    return DEFAULT_CONTEXT_LIMIT_TOKENS
  }
  const rounded = Math.round(tokens / CONTEXT_LIMIT_TOKENS_STEP) * CONTEXT_LIMIT_TOKENS_STEP
  if (rounded < MIN_CONTEXT_LIMIT_TOKENS) {
    return MIN_CONTEXT_LIMIT_TOKENS
  }
  if (rounded > MAX_CONTEXT_LIMIT_TOKENS) {
    return MAX_CONTEXT_LIMIT_TOKENS
  }
  return rounded
}

export function normalizeCompactThresholdPercent(percent: number): number {
  if (!Number.isFinite(percent)) {
    return DEFAULT_COMPACT_THRESHOLD_PERCENT
  }
  const rounded = Math.round(percent)
  if (rounded < MIN_COMPACT_THRESHOLD_PERCENT) {
    return MIN_COMPACT_THRESHOLD_PERCENT
  }
  if (rounded > MAX_COMPACT_THRESHOLD_PERCENT) {
    return MAX_COMPACT_THRESHOLD_PERCENT
  }
  return rounded
}

// 估算一段历史消息占用的输入 token，与计费预估共用同一个估算器
export function estimateMessagesTokens(messages: ChatMessage[]): number {
  return estimateConversationInputTokens(messages)
}

// 估算 system prompt 与摘要等附加文本的 token
export function estimateExtraPromptTokens(texts: string[]): number {
  let tokens = 0
  for (let i = 0; i < texts.length; i++) {
    const text = texts[i]
    if (text === '') {
      continue
    }
    tokens += estimateTextTokens(text) + 4
  }
  return tokens
}

// 按压缩锚点裁剪历史：返回锚点之后仍需逐条发送的消息。
// 锚点不在消息列表中（例如已被删除或切换到其他分支）时按未压缩处理。
export function sliceMessagesAfterAnchor(messages: ChatMessage[], anchorMessageId: string): ChatMessage[] {
  if (anchorMessageId === '') {
    return messages
  }
  for (let i = 0; i < messages.length; i++) {
    if (messages[i].id === anchorMessageId) {
      return messages.slice(i + 1)
    }
  }
  return messages
}

// 计算某次请求实际会发送的上下文用量
export function computeContextUsage(
  messages: ChatMessage[],
  contextWindowTokens: number,
  thresholdPercent: number,
  summary: string = '',
  anchorMessageId: string = '',
  extraPrompts: string[] = [],
  maxOutputTokens: number = 0
): ContextUsage {
  const effectiveMessages = sliceMessagesAfterAnchor(messages, anchorMessageId)
  const compacted = summary !== '' && effectiveMessages.length !== messages.length
  const promptTexts: string[] = compacted ? [summary, ...extraPrompts] : extraPrompts
  const usedTokens = estimateMessagesTokens(effectiveMessages) + estimateExtraPromptTokens(promptTexts)
  const inputBudget = resolveContextInputBudgetTokens(contextWindowTokens, maxOutputTokens)
  const reserve = contextWindowTokens > 0 ? Math.max(0, contextWindowTokens - inputBudget) : 0
  return new ContextUsage(
    usedTokens,
    inputBudget,
    thresholdPercent,
    compacted,
    contextWindowTokens,
    reserve
  )
}

// 已按最终 RequestMessage 估算出输入时，直接生成上下文快照，避免再次从 ChatMessage 猜测。
export function buildContextUsageFromRequestTokens(
  usedTokens: number,
  contextWindowTokens: number,
  maxOutputTokens: number,
  thresholdPercent: number,
  compacted: boolean = false
): ContextUsage {
  const inputBudget = resolveContextInputBudgetTokens(contextWindowTokens, maxOutputTokens)
  const reserve = contextWindowTokens > 0 ? Math.max(0, contextWindowTokens - inputBudget) : 0
  return new ContextUsage(
    usedTokens,
    inputBudget,
    thresholdPercent,
    compacted,
    contextWindowTokens,
    reserve
  )
}

export function formatTokenCount(tokens: number): string {
  const safeTokens = Math.max(0, Math.round(tokens))
  if (safeTokens < 1000) {
    return `${safeTokens}`
  }
  if (safeTokens < 1000000) {
    const value = safeTokens / 1000
    return `${value >= 100 ? Math.round(value).toString() : value.toFixed(1)}K`
  }
  return `${(safeTokens / 1000000).toFixed(1)}M`
}
