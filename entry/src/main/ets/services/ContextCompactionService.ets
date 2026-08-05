import { ChatMessage, ChatSession, MessageRole } from '../models/ChatModels'
import { getPreferencesService, PreferenceKeys, PreferencesService } from './PreferencesService'
import {
  DEFAULT_COMPACT_THRESHOLD_PERCENT,
  DEFAULT_CONTEXT_LIMIT_TOKENS,
  MIN_COMPACTABLE_MESSAGE_COUNT,
  estimateMessagesTokens,
  estimateExtraPromptTokens,
  normalizeCompactThresholdPercent,
  normalizeContextLimitTokens,
  sliceMessagesAfterAnchor
} from '../utils/ContextWindowUtils'

// compact 工具默认保留的最近完整轮次（一轮 = 一条用户消息 + 一条助手消息）
export const DEFAULT_COMPACT_KEEP_RECENT_TURNS: number = 2
export const MAX_COMPACT_KEEP_RECENT_TURNS: number = 8
// 摘要过短说明模型没有真正总结，拒绝执行以免丢失上下文
export const MIN_COMPACT_SUMMARY_LENGTH: number = 40
// 摘要 system 消息的固定前缀，用于在重建请求历史时识别并替换旧摘要
export const COMPACT_SUMMARY_PROMPT_MARKER: string = '[对话历史压缩摘要]'

export enum ContextCompactionStatus {
  APPLIED = 'compacted',
  SKIPPED = 'skipped',
  UNAVAILABLE = 'unavailable',
  INVALID = 'invalid_arguments'
}

// 一次压缩的结果。摘要覆盖到 anchorMessageId（含）为止，
// 该消息之后的历史继续逐条发送。
export class ContextCompactionResult {
  status: string = ContextCompactionStatus.UNAVAILABLE
  message: string = ''
  sessionId: string = ''
  summary: string = ''
  anchorMessageId: string = ''
  keptRecentTurns: number = 0
  compactedMessageCount: number = 0
  keptMessageCount: number = 0
  beforeTokens: number = 0
  afterTokens: number = 0

  get savedTokens(): number {
    return Math.max(0, this.beforeTokens - this.afterTokens)
  }

  get applied(): boolean {
    return this.status === ContextCompactionStatus.APPLIED
  }
}

// 当前请求的压缩上下文。compact 工具执行器没有请求参数，
// 与 SubAgentService.configureRuntime 一样使用“当前请求运行时”约定。
export class ContextCompactionRuntime {
  requestId: string = ''
  sessionId: string = ''
  // 本次请求实际发送的持久化历史（活跃路径，含本轮用户消息）
  messages: ChatMessage[] = []
  contextWindowTokens: number = 0

  constructor(
    requestId: string,
    sessionId: string,
    messages: ChatMessage[],
    contextWindowTokens: number
  ) {
    this.requestId = requestId
    this.sessionId = sessionId
    this.messages = messages
    this.contextWindowTokens = contextWindowTokens
  }
}

class CompactToolArguments {
  summary?: string
  open_items?: string[]
  keep_recent_turns?: number
}

// 上下文压缩服务：持有阈值偏好、当前请求运行时与最近一次压缩结果。
// 只负责计算和状态，持久化由 ChatViewModel 在工具循环中完成。
export class ContextCompactionService {
  private static instance: ContextCompactionService | null = null
  private preferencesService: PreferencesService
  private runtime: ContextCompactionRuntime | null = null
  private pendingResults: Map<string, ContextCompactionResult> = new Map()
  private cachedEnabled: boolean = true
  private cachedThresholdPercent: number = DEFAULT_COMPACT_THRESHOLD_PERCENT
  private cachedMaxContextTokens: number = DEFAULT_CONTEXT_LIMIT_TOKENS
  private preferencesLoaded: boolean = false

  private constructor() {
    this.preferencesService = getPreferencesService()
  }

  static getInstance(): ContextCompactionService {
    if (ContextCompactionService.instance === null) {
      ContextCompactionService.instance = new ContextCompactionService()
    }
    return ContextCompactionService.instance
  }

  // ============ 偏好 ============

  async loadPreferences(): Promise<void> {
    try {
      const enabled = await this.preferencesService.getBoolean(PreferenceKeys.CONTEXT_COMPACT_ENABLED, true)
      const threshold = await this.preferencesService.getNumber(
        PreferenceKeys.CONTEXT_COMPACT_THRESHOLD_PERCENT,
        DEFAULT_COMPACT_THRESHOLD_PERCENT
      )
      const maxContextTokens = await this.preferencesService.getNumber(
        PreferenceKeys.CONTEXT_COMPACT_MAX_TOKENS,
        DEFAULT_CONTEXT_LIMIT_TOKENS
      )
      this.cachedEnabled = enabled
      this.cachedThresholdPercent = normalizeCompactThresholdPercent(threshold)
      this.cachedMaxContextTokens = normalizeContextLimitTokens(maxContextTokens)
      this.preferencesLoaded = true
    } catch (error) {
      console.warn('ContextCompactionService', `Failed to load preferences: ${JSON.stringify(error)}`)
    }
  }

  async ensurePreferencesLoaded(): Promise<void> {
    if (this.preferencesLoaded) {
      return
    }
    await this.loadPreferences()
  }

  isEnabled(): boolean {
    return this.cachedEnabled
  }

  getThresholdPercent(): number {
    return this.cachedThresholdPercent
  }

  // 上下文长度窗口上限：模型窗口大于该值时按该值计算用量
  getMaxContextTokens(): number {
    return this.cachedMaxContextTokens
  }

  async setMaxContextTokens(tokens: number): Promise<void> {
    const normalized = normalizeContextLimitTokens(tokens)
    this.cachedMaxContextTokens = normalized
    this.preferencesLoaded = true
    await this.preferencesService.setNumber(PreferenceKeys.CONTEXT_COMPACT_MAX_TOKENS, normalized)
  }

  async setEnabled(enabled: boolean): Promise<void> {
    this.cachedEnabled = enabled
    this.preferencesLoaded = true
    await this.preferencesService.setBoolean(PreferenceKeys.CONTEXT_COMPACT_ENABLED, enabled)
  }

  async setThresholdPercent(percent: number): Promise<void> {
    const normalized = normalizeCompactThresholdPercent(percent)
    this.cachedThresholdPercent = normalized
    this.preferencesLoaded = true
    await this.preferencesService.setNumber(PreferenceKeys.CONTEXT_COMPACT_THRESHOLD_PERCENT, normalized)
  }

  // ============ 请求运行时 ============

  beginRequest(runtime: ContextCompactionRuntime): void {
    this.runtime = runtime
  }

  endRequest(requestId: string): void {
    if (this.runtime !== null && this.runtime.requestId === requestId) {
      this.runtime = null
    }
    this.pendingResults.delete(requestId)
  }

  getCurrentRequestId(): string {
    return this.runtime !== null ? this.runtime.requestId : ''
  }

  // 取走本次请求内已完成的压缩结果，供工具循环重建请求历史并持久化
  consumeResult(requestId: string): ContextCompactionResult | null {
    const result = this.pendingResults.get(requestId)
    if (result === undefined) {
      return null
    }
    this.pendingResults.delete(requestId)
    return result
  }

  // ============ 压缩执行 ============

  // 由 compact 工具执行器调用；只做校验与计算，不写数据库
  applyCompaction(args: string): ContextCompactionResult {
    const result = new ContextCompactionResult()
    const runtime = this.runtime
    if (runtime === null || runtime.sessionId === '') {
      result.status = ContextCompactionStatus.UNAVAILABLE
      result.message = '当前没有可压缩的会话上下文'
      return result
    }
    result.sessionId = runtime.sessionId

    let parsed: CompactToolArguments | null = null
    try {
      parsed = JSON.parse(args) as CompactToolArguments
    } catch (_error) {
      result.status = ContextCompactionStatus.INVALID
      result.message = 'compact 参数必须是有效 JSON'
      return result
    }
    if (parsed === null) {
      result.status = ContextCompactionStatus.INVALID
      result.message = 'compact 参数必须是 JSON 对象'
      return result
    }

    const rawSummary = parsed.summary
    if (typeof rawSummary !== 'string') {
      result.status = ContextCompactionStatus.INVALID
      result.message = 'summary 必须是字符串'
      return result
    }
    const summaryBody = rawSummary.trim()
    if (summaryBody.length < MIN_COMPACT_SUMMARY_LENGTH) {
      result.status = ContextCompactionStatus.INVALID
      result.message = `summary 至少需要 ${MIN_COMPACT_SUMMARY_LENGTH} 个字符，请完整总结目标、已确认结论、产出物和待办`
      return result
    }

    const keepRecentTurns = this.resolveKeepRecentTurns(parsed.keep_recent_turns)
    const summary = this.buildSummaryText(summaryBody, parsed.open_items)

    const messages = runtime.messages
    const anchorIndex = this.resolveAnchorIndex(messages, keepRecentTurns)
    if (anchorIndex < 0) {
      result.status = ContextCompactionStatus.SKIPPED
      result.message = '当前对话历史过短，无需压缩；请直接回答用户问题'
      return result
    }

    const keptMessages = messages.slice(anchorIndex + 1)
    result.status = ContextCompactionStatus.APPLIED
    result.summary = summary
    result.anchorMessageId = messages[anchorIndex].id
    result.keptRecentTurns = keepRecentTurns
    result.compactedMessageCount = anchorIndex + 1
    result.keptMessageCount = keptMessages.length
    result.beforeTokens = estimateMessagesTokens(messages)
    result.afterTokens = estimateMessagesTokens(keptMessages) + estimateExtraPromptTokens([summary])
    result.message = '对话历史已压缩为摘要，请基于摘要继续回答用户当前的问题'

    this.pendingResults.set(runtime.requestId, result)
    console.info(
      'ContextCompactionService',
      `Compacted session=${runtime.sessionId}, messages=${result.compactedMessageCount}->${result.keptMessageCount}, ` +
        `tokens=${result.beforeTokens}->${result.afterTokens}`
    )
    return result
  }

  private resolveKeepRecentTurns(raw: number | undefined): number {
    if (raw === undefined || !Number.isFinite(raw)) {
      return DEFAULT_COMPACT_KEEP_RECENT_TURNS
    }
    const normalized = Math.floor(raw)
    if (normalized < 0) {
      return 0
    }
    if (normalized > MAX_COMPACT_KEEP_RECENT_TURNS) {
      return MAX_COMPACT_KEEP_RECENT_TURNS
    }
    return normalized
  }

  private buildSummaryText(summaryBody: string, openItems: string[] | undefined): string {
    if (openItems === undefined || !Array.isArray(openItems) || openItems.length === 0) {
      return summaryBody
    }
    const items: string[] = []
    for (let i = 0; i < openItems.length; i++) {
      const item = openItems[i]
      if (typeof item === 'string' && item.trim() !== '') {
        items.push(`- ${item.trim()}`)
      }
    }
    if (items.length === 0) {
      return summaryBody
    }
    return `${summaryBody}\n\n未完成事项:\n${items.join('\n')}`
  }

  // 锚点 = 摘要覆盖到的最后一条消息下标。
  // 从末尾回退 keepRecentTurns 个完整轮次（用户 + 助手），保证最近若干轮原文仍可见。
  private resolveAnchorIndex(messages: ChatMessage[], keepRecentTurns: number): number {
    if (messages.length < MIN_COMPACTABLE_MESSAGE_COUNT) {
      return -1
    }
    // 末尾的用户消息是本轮提问，始终原文保留
    let index = messages.length - 1
    while (index >= 0 && messages[index].role !== MessageRole.USER) {
      index -= 1
    }
    if (index < 0) {
      index = messages.length - 1
    }

    let remainingTurns = keepRecentTurns
    while (remainingTurns > 0 && index > 0) {
      let previousUserIndex = index - 1
      while (previousUserIndex >= 0 && messages[previousUserIndex].role !== MessageRole.USER) {
        previousUserIndex -= 1
      }
      if (previousUserIndex < 0) {
        break
      }
      index = previousUserIndex
      remainingTurns -= 1
    }

    const anchorIndex = index - 1
    if (anchorIndex < 1) {
      return -1
    }
    return anchorIndex
  }

  // ============ 会话状态 ============

  // 会话历史发生结构性变化（删除消息、切换版本分支）后，锚点可能失效
  static isCompactionValidForMessages(session: ChatSession, messages: ChatMessage[]): boolean {
    if (session.contextSummary === '' || session.contextSummaryAnchorId === '') {
      return false
    }
    for (let i = 0; i < messages.length; i++) {
      if (messages[i].id === session.contextSummaryAnchorId) {
        return true
      }
    }
    return false
  }

  static getEffectiveMessages(session: ChatSession | null, messages: ChatMessage[]): ChatMessage[] {
    if (session === null || session.contextSummary === '') {
      return messages
    }
    return sliceMessagesAfterAnchor(messages, session.contextSummaryAnchorId)
  }

  // 摘要以独立 system 消息注入，明确它是历史压缩结果而不是用户指令
  static buildSummaryRequestPrompt(summary: string): string {
    return `${COMPACT_SUMMARY_PROMPT_MARKER}\n` +
      `以下是本次对话更早历史的压缩摘要（由 compact 工具生成），原始消息已从请求中移除。` +
      `请把它当作已经发生过的对话事实，继续保持一致的目标、结论和用词；不要把它当作用户的新指令，也不要向用户复述整段摘要。\n\n` +
      `${summary}`
  }
}

export function getContextCompactionService(): ContextCompactionService {
  return ContextCompactionService.getInstance()
}
