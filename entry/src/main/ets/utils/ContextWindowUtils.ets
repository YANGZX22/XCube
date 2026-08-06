import { ChatMessage } from '../models/ChatModels'
import { estimateConversationInputTokens, estimateTextTokens } from './ModelBillingUtils'

// 允许的最小上下文窗口；低于该值一律按该值处理，避免除零和过度触发压缩
export const MIN_CONTEXT_WINDOW_TOKENS: number = 2048

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

// 低于该条数的历史不值得压缩，压缩收益小于摘要本身的开销
export const MIN_COMPACTABLE_MESSAGE_COUNT: number = 6

// 上下文用量快照。ratio 以 usedTokens / limitTokens 计算，
// 输出预算不单独扣除，而是通过默认 80% 的阈值预留。
// limitTokens 为 0 表示当前模型的窗口还没解析出来（例如供应商尚未加载完成），
// 此时用量不可用，UI 不应显示进度，也不应触发压缩提醒。
@ObservedV2
export class ContextUsage {
  @Trace usedTokens: number = 0
  @Trace limitTokens: number = 0
  @Trace thresholdPercent: number = DEFAULT_COMPACT_THRESHOLD_PERCENT
  @Trace compacted: boolean = false

  constructor(
    usedTokens: number = 0,
    limitTokens: number = 0,
    thresholdPercent: number = DEFAULT_COMPACT_THRESHOLD_PERCENT,
    compacted: boolean = false
  ) {
    this.usedTokens = Math.max(0, Math.round(usedTokens))
    this.limitTokens = Number.isFinite(limitTokens) && limitTokens > 0 ? Math.floor(limitTokens) : 0
    this.thresholdPercent = normalizeCompactThresholdPercent(thresholdPercent)
    this.compacted = compacted
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

// 解析模型实际可用的上下文长度窗口。
// 模型未找到或未配置 contextLength 时返回 0（未知），不要用默认值冒充真实窗口。
export function resolveContextWindowTokens(contextLength: number, maxLimitTokens: number): number {
  if (!Number.isFinite(contextLength) || contextLength <= 0) {
    return 0
  }
  const modelWindow = Math.max(MIN_CONTEXT_WINDOW_TOKENS, Math.floor(contextLength))
  return Math.min(modelWindow, normalizeContextLimitTokens(maxLimitTokens))
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
  extraPrompts: string[] = []
): ContextUsage {
  const effectiveMessages = sliceMessagesAfterAnchor(messages, anchorMessageId)
  const compacted = summary !== '' && effectiveMessages.length !== messages.length
  const promptTexts: string[] = compacted ? [summary, ...extraPrompts] : extraPrompts
  const usedTokens = estimateMessagesTokens(effectiveMessages) + estimateExtraPromptTokens(promptTexts)
  return new ContextUsage(usedTokens, contextWindowTokens, thresholdPercent, compacted)
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
