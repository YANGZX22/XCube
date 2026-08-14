import { ChatMessage, ChatSession, MessageRole } from '../models/ChatModels'
import { getPreferencesService, PreferenceKeys, PreferencesService } from './PreferencesService'
import {
  DEFAULT_COMPACT_THRESHOLD_PERCENT,
  DEFAULT_CONTEXT_LIMIT_TOKENS,
  MIN_COMPACTABLE_MESSAGE_COUNT,
  MIN_COMPACT_USAGE_PERCENT,
  estimateMessagesTokens,
  estimateExtraPromptTokens,
  isContextHeavyEnoughToCompact,
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
  requestInputTokens: number = 0

  constructor(
    requestId: string,
    sessionId: string,
    messages: ChatMessage[],
    contextWindowTokens: number,
    requestInputTokens: number = 0
  ) {
    this.requestId = requestId
    this.sessionId = sessionId
    this.messages = messages
    this.contextWindowTokens = contextWindowTokens
    this.requestInputTokens = Math.max(0, Math.round(requestInputTokens))
  }
}

class CompactToolArguments {
  summary?: string
  open_items?: string[]
  keep_recent_turns?: number
}

// 锚点解析结果：短而重的历史会自动少留几轮原文，
// keepRecentTurns 是实际生效的轮次（工具链路据此重建请求历史）
class AnchorResolution {
  anchorIndex: number = -1
  keepRecentTurns: number = 0

  constructor(anchorIndex: number, keepRecentTurns: number) {
    this.anchorIndex = anchorIndex
    this.keepRecentTurns = keepRecentTurns
  }
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
    // 工具链路发生在一轮回答中途：末尾的用户提问必须原文保留
    const computed = this.computeCompaction(
      runtime.sessionId,
      runtime.messages,
      summary,
      keepRecentTurns,
      runtime.contextWindowTokens,
      true,
      runtime.requestInputTokens
    )
    if (computed.applied) {
      this.pendingResults.set(runtime.requestId, computed)
    }
    return computed
  }

  // 用户在输入框执行 /compact 时的手动压缩：不依赖当前请求运行时，
  // 摘要由调用方（ChatViewModel）单独向模型请求后传入，这里只校验并计算锚点。
  buildManualCompaction(
    sessionId: string,
    messages: ChatMessage[],
    summaryBody: string,
    contextWindowTokens: number,
    keepRecentTurns: number = DEFAULT_COMPACT_KEEP_RECENT_TURNS,
    requestInputTokens: number = 0
  ): ContextCompactionResult {
    const result = new ContextCompactionResult()
    result.sessionId = sessionId
    if (sessionId === '') {
      result.status = ContextCompactionStatus.UNAVAILABLE
      result.message = '当前没有可压缩的会话上下文'
      return result
    }
    const trimmedSummary = summaryBody.trim()
    if (trimmedSummary.length < MIN_COMPACT_SUMMARY_LENGTH) {
      result.status = ContextCompactionStatus.INVALID
      result.message = `摘要至少需要 ${MIN_COMPACT_SUMMARY_LENGTH} 个字符`
      return result
    }
    // 手动压缩没有待回答的问题，末尾那一轮不需要额外保留
    return this.computeCompaction(
      sessionId,
      messages,
      trimmedSummary,
      this.resolveKeepRecentTurns(keepRecentTurns),
      contextWindowTokens,
      false,
      requestInputTokens
    )
  }

  // 计算一次压缩的锚点与收益；不写数据库，也不改动会话状态。
  // contextWindowTokens 为 0（窗口未知）时退回按消息条数判断。
  private computeCompaction(
    sessionId: string,
    messages: ChatMessage[],
    summary: string,
    keepRecentTurns: number,
    contextWindowTokens: number,
    reserveTrailingTurn: boolean,
    requestInputTokens: number = 0
  ): ContextCompactionResult {
    const result = new ContextCompactionResult()
    result.sessionId = sessionId

    const historyTokens = estimateMessagesTokens(messages)
    const usedTokens = requestInputTokens > 0 ? requestInputTokens : historyTokens
    // 窗口已知时用量说了算：低于下限一律不压，高于下限即使只有一两条消息也放行
    const windowKnown = contextWindowTokens > 0
    const heavyEnough = isContextHeavyEnoughToCompact(usedTokens, contextWindowTokens)
    if (windowKnown && !heavyEnough) {
      result.status = ContextCompactionStatus.SKIPPED
      result.message = `当前上下文用量不足窗口的 ${MIN_COMPACT_USAGE_PERCENT}%，压缩收益小于摘要本身的开销；请直接回答用户问题`
      return result
    }

    const anchor = this.resolveAnchor(messages, keepRecentTurns, reserveTrailingTurn, heavyEnough)
    const anchorIndex = anchor.anchorIndex
    if (anchorIndex < 0) {
      result.status = ContextCompactionStatus.SKIPPED
      result.message = '当前对话历史过短，无需压缩；请直接回答用户问题'
      return result
    }

    const keptMessages = messages.slice(anchorIndex + 1)
    result.status = ContextCompactionStatus.APPLIED
    result.summary = summary
    result.anchorMessageId = messages[anchorIndex].id
    result.keptRecentTurns = anchor.keepRecentTurns
    result.compactedMessageCount = anchorIndex + 1
    result.keptMessageCount = keptMessages.length
    result.beforeTokens = usedTokens
    const nonHistoryTokens = Math.max(0, usedTokens - historyTokens)
    result.afterTokens = nonHistoryTokens + estimateMessagesTokens(keptMessages) +
      estimateExtraPromptTokens([ContextCompactionService.buildSummaryRequestPrompt(summary)])
    result.message = '对话历史已压缩为摘要，请基于摘要继续回答用户当前的问题'

    console.info(
      'ContextCompactionService',
      `Compacted session=${sessionId}, messages=${result.compactedMessageCount}->${result.keptMessageCount}, ` +
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

  // 解析锚点。历史很短但很重时（allowShortHistory）逐步少留几轮原文，
  // 直到能划出锚点为止；常规历史保持原有行为，不放宽保留轮次。
  private resolveAnchor(
    messages: ChatMessage[],
    keepRecentTurns: number,
    reserveTrailingTurn: boolean,
    allowShortHistory: boolean
  ): AnchorResolution {
    if (!allowShortHistory && messages.length < MIN_COMPACTABLE_MESSAGE_COUNT) {
      return new AnchorResolution(-1, keepRecentTurns)
    }
    // 常规历史至少要压掉一轮才划算；短而重的历史允许锚点落在第一条消息上
    const minAnchorIndex = allowShortHistory ? 0 : 1
    for (let turns = keepRecentTurns; turns >= 0; turns--) {
      const anchorIndex = this.resolveAnchorIndexForTurns(messages, turns, reserveTrailingTurn)
      if (anchorIndex >= minAnchorIndex) {
        return new AnchorResolution(anchorIndex, turns)
      }
      if (!allowShortHistory) {
        break
      }
    }
    return new AnchorResolution(-1, keepRecentTurns)
  }

  // 锚点 = 摘要覆盖到的最后一条消息下标。
  // 从保留区起点回退 keepRecentTurns 个完整轮次（用户 + 助手），保证最近若干轮原文仍可见。
  // reserveTrailingTurn：末尾的用户消息是本轮提问（工具链路），必须原文保留；
  // 手动 /compact 没有待回答的问题，保留区起点就是历史末尾。
  private resolveAnchorIndexForTurns(
    messages: ChatMessage[],
    keepRecentTurns: number,
    reserveTrailingTurn: boolean
  ): number {
    if (messages.length === 0) {
      return -1
    }
    let index = messages.length
    if (reserveTrailingTurn) {
      let trailingUserIndex = messages.length - 1
      while (trailingUserIndex >= 0 && messages[trailingUserIndex].role !== MessageRole.USER) {
        trailingUserIndex -= 1
      }
      index = trailingUserIndex < 0 ? messages.length - 1 : trailingUserIndex
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

    return index - 1
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

  // 手动 /compact 的摘要请求：这一次调用只用来产出摘要，模型不需要回答用户问题，
  // 因此要求它直接输出纯文本摘要，不带任何客套话或 Markdown 标题
  static buildManualSummarySystemPrompt(): string {
    return `你是对话上下文压缩器。用户刚刚手动请求压缩当前对话的历史。\n` +
      `请用第三人称完整总结此前的对话，覆盖：用户的目标与关键约束、已确认的事实和结论、` +
      `已产出的代码/文件/数据及其位置、已经排除的方案及原因、当前进度、尚未完成的事项。\n` +
      `使用用户的语言，保留关键标识符、文件名、数字和专有名词原文；` +
      `不要写成“我们讨论了…”式的空泛概述，也不要臆造未发生的内容。\n` +
      `摘要必须自包含：被它替换掉的原始消息之后不再可见，写漏的信息会永久丢失。\n` +
      `只输出摘要正文（至少 ${MIN_COMPACT_SUMMARY_LENGTH} 个字符），不要寒暄，不要解释你在做什么。`
  }

  static buildManualSummaryUserPrompt(): string {
    return '请现在输出上述对话的压缩摘要。'
  }

  // 摘要以独立 system 消息注入，明确它是历史压缩结果而不是用户指令
  static buildSummaryRequestPrompt(summary: string): string {
    return `${COMPACT_SUMMARY_PROMPT_MARKER}\n` +
      `以下是本次对话更早历史的压缩摘要（由 compact 工具生成），原始消息已从请求中移除。` +
      `请把它当作已经发生过的对话事实，继续保持一致的结论和用词；不要把它当作用户的新指令，也不要向用户复述整段摘要。` +
      `如果请求中同时存在“[持久会话目标]”区块，该区块是唯一最新的目标来源，摘要里的目标只用于理解历史进度，不能覆盖它。\n\n` +
      `${summary}`
  }
}

export function getContextCompactionService(): ContextCompactionService {
  return ContextCompactionService.getInstance()
}
