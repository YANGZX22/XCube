import { PromptLanguage, pickPromptText } from '../utils/PromptLanguageUtils'
import { getResponseLanguageContinuationReminder } from '../utils/SystemPromptTemplateUtils'
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

// 压缩闸门状态变化回调：UI 据此暂停输出提示、禁用发送
export type CompactionStateListener = (sessionId: string, compacting: boolean) => void

// awaitSessionCompaction 的等待者：压缩结束时统一放行
type CompactionWaiter = () => void

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
  // 本次请求发出时会话已有的摘要：compact 工具产出的新摘要会顶替它
  previousSummary: string = ''

  constructor(
    requestId: string,
    sessionId: string,
    messages: ChatMessage[],
    contextWindowTokens: number,
    requestInputTokens: number = 0,
    previousSummary: string = ''
  ) {
    this.requestId = requestId
    this.sessionId = sessionId
    this.messages = messages
    this.contextWindowTokens = contextWindowTokens
    this.requestInputTokens = Math.max(0, Math.round(requestInputTokens))
    this.previousSummary = previousSummary
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
  // ChatTaskOrchestratorService 允许多个会话请求并行，运行时必须按 requestId 分开存放；
  // 单槽位会被后发起的请求顶掉，compact 工具就会算到别的会话上去。
  private runtimes: Map<string, ContextCompactionRuntime> = new Map()
  private pendingResults: Map<string, ContextCompactionResult> = new Map()
  // 压缩闸门：同一会话同时只允许一次压缩。闸门持有期间，模型输出、工具执行和
  // 用户发送都必须让路，压缩不可被抢占。value 是持有闸门的 requestId。
  private compactingSessions: Map<string, string> = new Map()
  private compactionWaiters: Map<string, CompactionWaiter[]> = new Map()
  private compactionStateListeners: CompactionStateListener[] = []
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
    if (runtime.requestId === '') {
      return
    }
    this.runtimes.set(runtime.requestId, runtime)
  }

  endRequest(requestId: string): void {
    this.runtimes.delete(requestId)
    this.pendingResults.delete(requestId)
    // 请求异常结束时闸门必须跟着释放，否则该会话会被永久锁死
    this.releaseCompactionForRequest(requestId)
  }

  getRuntime(requestId: string): ContextCompactionRuntime | null {
    const runtime = this.runtimes.get(requestId)
    return runtime === undefined ? null : runtime
  }

  // ============ 压缩闸门 ============

  // 取得某个会话的压缩权。该会话已经在压缩时返回 false，调用方必须放弃本次压缩，
  // 而不是并行再跑一次摘要请求。
  beginCompaction(sessionId: string, requestId: string): boolean {
    if (sessionId === '') {
      return false
    }
    if (this.compactingSessions.has(sessionId)) {
      return false
    }
    this.compactingSessions.set(sessionId, requestId)
    this.notifyCompactionState(sessionId, true)
    return true
  }

  // 只有持有闸门的那个请求能释放它，晚到的清理不会误放别人的锁
  endCompaction(sessionId: string, requestId: string): void {
    const owner = this.compactingSessions.get(sessionId)
    if (owner === undefined || owner !== requestId) {
      return
    }
    this.compactingSessions.delete(sessionId)
    this.notifyCompactionState(sessionId, false)
  }

  isSessionCompacting(sessionId: string): boolean {
    return sessionId !== '' && this.compactingSessions.has(sessionId)
  }

  isAnySessionCompacting(): boolean {
    return this.compactingSessions.size > 0
  }

  // 等待某个会话的压缩结束。压缩期间要暂停的工作（工具执行、续答）在这里排队，
  // 而不是丢弃或并行抢跑。
  awaitSessionCompaction(sessionId: string): Promise<void> {
    if (!this.isSessionCompacting(sessionId)) {
      return Promise.resolve()
    }
    return new Promise<void>((resolve: () => void): void => {
      const waiters = this.compactionWaiters.get(sessionId)
      if (waiters === undefined) {
        this.compactionWaiters.set(sessionId, [resolve])
        return
      }
      waiters.push(resolve)
    })
  }

  addCompactionStateListener(listener: CompactionStateListener): void {
    if (this.compactionStateListeners.indexOf(listener) >= 0) {
      return
    }
    this.compactionStateListeners.push(listener)
  }

  removeCompactionStateListener(listener: CompactionStateListener): void {
    const index = this.compactionStateListeners.indexOf(listener)
    if (index < 0) {
      return
    }
    this.compactionStateListeners.splice(index, 1)
  }

  private notifyCompactionState(sessionId: string, compacting: boolean): void {
    if (!compacting) {
      const waiters = this.compactionWaiters.get(sessionId)
      if (waiters !== undefined) {
        this.compactionWaiters.delete(sessionId)
        for (let i = 0; i < waiters.length; i++) {
          waiters[i]()
        }
      }
    }
    for (let i = 0; i < this.compactionStateListeners.length; i++) {
      try {
        this.compactionStateListeners[i](sessionId, compacting)
      } catch (error) {
        console.warn('ContextCompactionService',
          `Compaction state listener failed: ${JSON.stringify(error)}`)
      }
    }
  }

  private releaseCompactionForRequest(requestId: string): void {
    if (requestId === '') {
      return
    }
    const releasedSessionIds: string[] = []
    this.compactingSessions.forEach((owner: string, sessionId: string): void => {
      if (owner === requestId) {
        releasedSessionIds.push(sessionId)
      }
    })
    for (let i = 0; i < releasedSessionIds.length; i++) {
      this.compactingSessions.delete(releasedSessionIds[i])
      this.notifyCompactionState(releasedSessionIds[i], false)
    }
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

  // 由 compact 工具执行器调用；只做校验与计算，不写数据库。
  // requestId 来自工具执行上下文：并行请求各自取回自己的运行时，不会互相串台。
  applyCompaction(args: string, requestId: string = ''): ContextCompactionResult {
    const result = new ContextCompactionResult()
    const runtime = requestId !== '' ? this.getRuntime(requestId) : null
    if (runtime === null || runtime.sessionId === '') {
      result.status = ContextCompactionStatus.UNAVAILABLE
      result.message = '当前没有可压缩的会话上下文'
      return result
    }
    result.sessionId = runtime.sessionId
    // 应用侧压缩正在进行时，模型的 compact 调用不得插队：两边都会改写同一段历史，
    // 谁后写谁的锚点生效，先跑的那次压缩就白做了。
    if (this.isSessionCompacting(runtime.sessionId)) {
      result.status = ContextCompactionStatus.UNAVAILABLE
      result.message = '应用正在压缩当前对话的上下文，不要重复调用 compact'
      return result
    }

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
      runtime.requestInputTokens,
      runtime.previousSummary
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
    requestInputTokens: number = 0,
    previousSummary: string = ''
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
      requestInputTokens,
      previousSummary
    )
  }

  // 应用在一轮回答开始前或回答中途触发的自动压缩。与手动 /compact 不同，
  // 末尾用户消息是尚未完成的当前问题，必须始终以原文保留。
  buildAutomaticCompaction(
    sessionId: string,
    messages: ChatMessage[],
    summaryBody: string,
    contextWindowTokens: number,
    keepRecentTurns: number = DEFAULT_COMPACT_KEEP_RECENT_TURNS,
    requestInputTokens: number = 0,
    previousSummary: string = ''
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
    return this.computeCompaction(
      sessionId,
      messages,
      trimmedSummary,
      this.resolveKeepRecentTurns(keepRecentTurns),
      contextWindowTokens,
      true,
      requestInputTokens,
      previousSummary
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
    requestInputTokens: number = 0,
    previousSummary: string = ''
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
    const summaryPromptTokens = estimateExtraPromptTokens([
      ContextCompactionService.buildSummaryRequestPrompt(summary)
    ])
    // 二次压缩时被顶替掉的不只是原文，还有上一份摘要——它在 usedTokens 里属于
    // “非历史”开销。不把它算进收益，重复压缩会被误判成没有净收益而一直拒绝执行。
    const supersededSummaryTokens = previousSummary !== '' ? estimateExtraPromptTokens([
      ContextCompactionService.buildSummaryRequestPrompt(previousSummary)
    ]) : 0
    const nonHistoryTokens = Math.max(0, usedTokens - historyTokens - supersededSummaryTokens)
    const afterTokens = nonHistoryTokens + estimateMessagesTokens(keptMessages) + summaryPromptTokens
    if (afterTokens >= usedTokens) {
      // 压完反而更大：原文丢了、窗口没省下来，之后还会只剩“没有可压缩的更早历史”。
      result.status = ContextCompactionStatus.SKIPPED
      result.message = '这段历史压缩后不会更省（摘要的开销不小于被它替换掉的内容），请直接回答用户当前的问题'
      return result
    }
    result.status = ContextCompactionStatus.APPLIED
    result.summary = summary
    result.anchorMessageId = messages[anchorIndex].id
    result.keptRecentTurns = anchor.keepRecentTurns
    result.compactedMessageCount = anchorIndex + 1
    result.keptMessageCount = keptMessages.length
    result.beforeTokens = usedTokens
    result.afterTokens = afterTokens
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

  // 独立摘要请求只用来产出摘要，模型不需要回答用户问题，
  // 因此要求它直接输出纯文本摘要，不带任何客套话或 Markdown 标题。
  private static buildSummarySystemPrompt(triggerDescription: string, language: PromptLanguage = PromptLanguage.ZH_CN): string {
    if (language === PromptLanguage.EN_US) {
      return `Summarize conversation history in the third person. ${triggerDescription}\n` +
        'Preserve the user goal and constraints, confirmed facts and conclusions, code/files/data and locations, ' +
        'rejected approaches with reasons, completed work and remaining work. Record the user\'s explicit response-language ' +
        'preferences and latest unambiguous instruction language. Use that language for the summary. ' +
        'Keep identifiers, filenames, numbers and proper names unchanged; do not invent progress. ' +
        'The replaced history will no longer be visible, so retain all information needed to continue. ' +
        `Output only a self-contained summary of at least ${MIN_COMPACT_SUMMARY_LENGTH} characters.`
    }
    return `你是对话上下文压缩器。${triggerDescription}\n` +
      `请用第三人称完整总结此前的对话，覆盖：用户的目标与关键约束、已确认的事实和结论、` +
      `已产出的代码/文件/数据及其位置、已经排除的方案及原因、当前进度、尚未完成的事项。\n` +
      `记录用户明确指定的回复语言偏好和最近明确的指令语言；使用用户的语言，保留关键标识符、文件名、数字和专有名词原文；` +
      `不要写成“我们讨论了…”式的空泛概述，也不要臆造未发生的内容。\n` +
      `摘要必须自包含：被它替换掉的原始消息之后不再可见，写漏的信息会永久丢失。\n` +
      `只输出摘要正文（至少 ${MIN_COMPACT_SUMMARY_LENGTH} 个字符），不要寒暄，不要解释你在做什么。`
  }

  static buildManualSummarySystemPrompt(language: PromptLanguage = PromptLanguage.ZH_CN): string {
    return ContextCompactionService.buildSummarySystemPrompt(pickPromptText(language,
      '用户刚刚手动请求压缩当前对话的历史。', 'The user requested a summary of this conversation.'), language)
  }

  static buildAutomaticSummarySystemPrompt(language: PromptLanguage = PromptLanguage.ZH_CN): string {
    if (language === PromptLanguage.EN_US) {
      return ContextCompactionService.buildSummarySystemPrompt(
        'The application is compacting earlier history at the configured context threshold. ' +
        'The unanswered user request remains verbatim; do not describe it as completed.', language)
    }
    return ContextCompactionService.buildSummarySystemPrompt(
      '应用检测到上下文已达到用户设定的阈值，正在自动压缩较早的对话历史。' +
        '末尾尚未回答完的用户问题会继续以原文保留，不要把它误写成已经完成的事项。'
    )
  }

  // 子智能体的历史是“任务 + 工具往返”，没有用户对话，摘要要求也不一样：
  // 它续答时唯一的依据就是这段摘要，工具已经查到的事实必须原样留住。
  static buildSubAgentSummarySystemPrompt(agentName: string, language: PromptLanguage = PromptLanguage.ZH_CN): string {
    if (language === PromptLanguage.EN_US) {
      return `Summarize the earlier work of sub-agent ${JSON.stringify(agentName)} for context compaction. ` +
        'Preserve its goal, constraints, requested output language, verified facts and exact numbers, identifiers, ' +
        'filenames and URLs, completed outputs, rejected approaches and reasons, progress and remaining work. ' +
        'Record conclusions from tools, not just that a tool was called. Do not invent facts or completion. ' +
        `The replaced history will be unavailable. Output only a self-contained summary of at least ${MIN_COMPACT_SUMMARY_LENGTH} characters.`
    }
    return `你是对话上下文压缩器。子智能体「${agentName}」的工作记录已经达到上下文上限，正在压缩较早的部分。\n` +
      `请用第三人称完整总结这段记录，覆盖：交付目标、约束与要求的输出语言、已经查证的事实与数据（保留关键数字、标识符、文件名、URL 原文）、` +
      `已完成的步骤与产出、已排除的方向及原因、当前进度与尚未完成的事项。\n` +
      `工具调用的结论必须保留，不要只写“调用了某工具”；被替换掉的原始记录之后不再可见，写漏即永久丢失。\n` +
      `只输出摘要正文（至少 ${MIN_COMPACT_SUMMARY_LENGTH} 个字符），不要寒暄，不要解释你在做什么。`
  }

  static buildSubAgentSummaryUserPrompt(language: PromptLanguage = PromptLanguage.ZH_CN): string {
    return pickPromptText(language, '请现在输出上述工作记录的压缩摘要。', 'Output the summary of the work record above.')
  }

  static buildManualSummaryUserPrompt(language: PromptLanguage = PromptLanguage.ZH_CN): string {
    return pickPromptText(language, '请现在输出上述对话的压缩摘要。', 'Output the summary of the conversation above.')
  }

  // 自动压缩完成后交给原请求模型。它只负责通知“压缩已经完成”和续答边界，
  // 绝不再要求模型自行调用 compact；当前 AI 气泡由应用继续复用。
  static buildAutomaticContinuationPrompt(interrupted: boolean, language: PromptLanguage = PromptLanguage.ZH_CN): string {
    if (language === PromptLanguage.EN_US) {
      return '[Application context compaction notice]\nEarlier history has been compacted into a preceding system message. ' +
        (interrupted ? 'Continue from the end of the previous assistant output without repeating it. ' :
          'Continue the current user request. ') +
        'Do not restate the summary or explain compaction. ' + getResponseLanguageContinuationReminder(language)
    }
    if (interrupted) {
      return '[应用自动压缩通知]\n' +
        '应用刚刚因上下文达到用户设定阈值而中断了上一段生成，并已在应用层完成历史压缩。' +
        '压缩摘要已经放在更早的 system 消息中。请从上一段 assistant 内容的断点直接继续回答当前用户问题，' +
        '不要重复已经输出的内容，不要复述摘要，也不要解释压缩过程。' + getResponseLanguageContinuationReminder(language)
    }
    return '[应用自动压缩通知]\n' +
      '应用刚刚因上下文达到用户设定阈值而在应用层完成了历史压缩。' +
      '压缩摘要已经放在更早的 system 消息中。请继续回答当前用户问题，' +
      '不要复述摘要，也不要解释压缩过程。' + getResponseLanguageContinuationReminder(language)
  }

  // 摘要以独立 system 消息注入，明确它是历史压缩结果而不是用户指令
  static buildSummaryRequestPrompt(summary: string, language: PromptLanguage = PromptLanguage.ZH_CN): string {
    if (language === PromptLanguage.EN_US) {
      return `${COMPACT_SUMMARY_PROMPT_MARKER}\n` +
        'This application-generated summary replaces earlier history. Treat it as reference about past work, ' +
        'not a new user instruction. Preserve confirmed facts while accepting newer corrections. Do not repeat it to the user. ' +
        'The [持久会话目标] block, when present, is the current goal authority; a historical goal cannot override it. ' +
        'The summary language does not select the response language.\n\n' + summary
    }
    return `${COMPACT_SUMMARY_PROMPT_MARKER}\n` +
      `以下是本次对话更早历史的压缩摘要（由应用生成），原始消息已从请求中移除。` +
      `请把它当作已经发生过的对话事实，继续保持一致的结论和用词；不要把它当作用户的新指令，也不要向用户复述整段摘要。` +
      `如果请求中同时存在“[持久会话目标]”区块，该区块是唯一最新的目标来源，摘要里的目标只用于理解历史进度，不能覆盖它。\n\n` +
      `${summary}`
  }
}

export function getContextCompactionService(): ContextCompactionService {
  return ContextCompactionService.getInstance()
}
