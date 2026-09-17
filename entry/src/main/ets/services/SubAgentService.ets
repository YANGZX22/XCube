import { PromptLanguage, pickPromptText } from '../utils/PromptLanguageUtils'
import { getToolProgressStop, isToolProgressStop } from '../utils/ToolProgressGuard'
import { getCollectedSubAgentGuidance, getTaskExecutionPrompt } from '../config/AgentPrompts'
import { appendResponseLanguageSystemPrompt, getResponseLanguageContinuationReminder } from '../utils/SystemPromptTemplateUtils'
import { http } from '@kit.NetworkKit'
import { AIApiConfig, AIApiService, RequestMessage, UsageInfo } from './AIApiService'
import { ReasoningLevel, ToolCall, ToolDefinition, ToolResult } from '../models/ChatModels'
import { createThrottle } from '../utils/ThrottleUtil'
import { estimateTextTokens } from '../utils/ModelBillingUtils'
import {
  hasFiniteRetrievalCallLimit,
  UNLIMITED_RETRIEVAL_CALL_LIMIT
} from '../config/RetrievalCallLimit'
import {
  buildContextUsageFromRequestTokens,
  resolveRequestMaxOutputTokens
} from '../utils/ContextWindowUtils'
import {
  COMPACT_SUMMARY_PROMPT_MARKER,
  ContextCompactionService,
  MIN_COMPACT_SUMMARY_LENGTH,
  getContextCompactionService
} from './ContextCompactionService'
import {
  parseSubAgentToolArguments,
  SubAgentDispatchArguments,
  SubAgentTaskArguments
} from './SubAgentArgumentParser'
import { ToolExecutionContext } from './ToolRegistry'
import { ReasoningRequestStrategy } from './ProviderCompatibilityRegistry'

export const SUB_AGENT_TOOL_ID: string = 'sub_agent'

// sub_agent 的配套收取工具。sub_agent 只负责派发并立即返回，主智能体继续自己的工具
// 循环，需要子智能体产出时再调用它取回结果。随 sub_agent 一起曝光，不单独出现在工具面板。
export const SUB_AGENT_RESULT_TOOL_ID: string = 'sub_agent_result'

// 主智能体向已派出的子智能体续发消息。每次续发都会复用该子智能体的完整上下文，
// 并返回一个新的 batchId，仍由 sub_agent_result 异步收取本轮回复。
export const SUB_AGENT_MESSAGE_TOOL_ID: string = 'sub_agent_message'

// 子智能体发起的工具调用统一使用该来源标签前缀，
// UI 依赖它识别调用来源（例如主对话中不渲染子智能体的工具卡片）
export const SUB_AGENT_SOURCE_LABEL_PREFIX: string = '子智能体 · '

// 单次 sub_agent 调用允许并行派出的子智能体上限
export const SUB_AGENT_MAX_TASKS = 3

// 子智能体继承本次对话已经曝光的工具。只禁止 sub_agent 及其两个配套工具，
// 避免递归派生和子智能体去收取同级批次；knowledge_search 是否存在完全由主请求
// 的知识库开关与曝光策略决定。
export function buildSubAgentToolSet(tools: ToolDefinition[]): ToolDefinition[] {
  const result: ToolDefinition[] = []
  for (let i = 0; i < tools.length; i++) {
    const functionName = tools[i].function.name
    if (functionName === SUB_AGENT_TOOL_ID || functionName === SUB_AGENT_RESULT_TOOL_ID ||
      functionName === SUB_AGENT_MESSAGE_TOOL_ID) {
      continue
    }
    result.push(tools[i])
  }
  return result
}

// 子智能体执行工具时的回调（由 ChatViewModel 注入 ToolExecutionService.executeToolCall，
// 避免 SubAgentService -> ToolExecutionService -> BuiltinTools 的循环依赖）
export type SubAgentToolRunner = (
  toolCall: ToolCall,
  allowedFunctionNames: string[],
  budgetKey: string,
  executionContext: ToolExecutionContext
) => Promise<ToolResult>

// 子智能体工具调用镜像回调：把子智能体的工具调用/结果同步进主对话的 AI 消息，
// 让 ask_user 弹窗/结果栏、图表、Canvas、日程等交互式工具对用户可见
export type SubAgentToolCallStarted = (toolCall: ToolCall) => void
export type SubAgentToolCallCompleted = (toolCall: ToolCall, toolResult: ToolResult) => void
export type SubAgentUsageCallback = (
  inputTokens: number,
  outputTokens: number,
  exact: boolean,
  cacheReadTokens: number,
  cacheWriteTokens: number
) => void

// 子智能体运行时配置，由 ChatViewModel 在每次带工具的请求开始前注入
export class SubAgentRuntimeConfig {
  apiConfig: AIApiConfig
  modelId: string
  temperature: number
  maxTokens: number
  reasoningLevel: ReasoningLevel
  tools: ToolDefinition[]
  timeContext: string
  toolExecutionContext: ToolExecutionContext
  toolRunner: SubAgentToolRunner
  onToolTurnStarted: (actorId: string) => void
  shouldStopTools: (actorId: string) => boolean
  onToolCallStarted: SubAgentToolCallStarted
  onToolCallCompleted: SubAgentToolCallCompleted
  isCancelled: () => boolean
  onUsage: SubAgentUsageCallback
  contextWindowTokens: number
  webSearchCallLimit: number
  knowledgeSearchCallLimit: number
  promptLanguage: PromptLanguage

  constructor(
    apiConfig: AIApiConfig,
    modelId: string,
    temperature: number,
    maxTokens: number,
    reasoningLevel: ReasoningLevel,
    tools: ToolDefinition[],
    timeContext: string,
    toolExecutionContext: ToolExecutionContext,
    toolRunner: SubAgentToolRunner,
    onToolTurnStarted: (actorId: string) => void,
    shouldStopTools: (actorId: string) => boolean,
    onToolCallStarted: SubAgentToolCallStarted,
    onToolCallCompleted: SubAgentToolCallCompleted,
    isCancelled: () => boolean,
    onUsage: SubAgentUsageCallback,
    contextWindowTokens: number = 0,
    webSearchCallLimit: number = UNLIMITED_RETRIEVAL_CALL_LIMIT,
    knowledgeSearchCallLimit: number = UNLIMITED_RETRIEVAL_CALL_LIMIT,
    promptLanguage: PromptLanguage = PromptLanguage.ZH_CN
  ) {
    this.apiConfig = apiConfig
    this.modelId = modelId
    this.temperature = temperature
    this.maxTokens = maxTokens
    this.reasoningLevel = reasoningLevel
    this.tools = tools
    this.timeContext = timeContext
    this.toolExecutionContext = toolExecutionContext
    this.toolRunner = toolRunner
    this.onToolTurnStarted = onToolTurnStarted
    this.shouldStopTools = shouldStopTools
    this.onToolCallStarted = onToolCallStarted
    this.onToolCallCompleted = onToolCallCompleted
    this.isCancelled = isCancelled
    this.onUsage = onUsage
    this.contextWindowTokens = contextWindowTokens
    this.webSearchCallLimit = webSearchCallLimit
    this.knowledgeSearchCallLimit = knowledgeSearchCallLimit
    this.promptLanguage = promptLanguage
  }
}

interface SubAgentMessageItemArgs {
  agent_id?: string
  agentId?: string
  message?: string
  expected_output?: string
}

interface SubAgentMessageToolArgs {
  main_thread_work?: string
  messages?: SubAgentMessageItemArgs[]
}

// sub_agent_result 工具入参
interface SubAgentResultToolArgs {
  batch_id?: string
  wait?: boolean
}

// 单个子智能体的执行报告（序列化后回传给主智能体）
class SubAgentTaskReport {
  agentId: string = ''
  name: string = ''
  status: string = ''
  result: string = ''
  conversationTurn: number = 0
  rounds: number = 0
  toolCallCount: number = 0
}

class SubAgentSessionDescriptor {
  agentId: string = ''
  name: string = ''
}

// sub_agent 的返回：只确认派发，不含结果
class SubAgentDispatchResponse {
  status: string = 'dispatched'
  nextAction: string = 'continue_main_thread_work'
  mainThreadWork: string = ''
  batchId: string = ''
  agents: string[] = []
  sessions: SubAgentSessionDescriptor[] = []
  note: string = ''
}

// sub_agent_result（wait=true）的返回：汇总一个或多个批次的当前轮回复
class SubAgentCollectResponse {
  status: string = 'completed'
  nextAction: string = 'integrate_results_or_resolve_material_gap'
  batchIds: string[] = []
  results: SubAgentTaskReport[] = []
  note: string = ''
}

// sub_agent_result（wait=false）的返回：只报进度，不阻塞
class SubAgentProgressItem {
  batchId: string = ''
  agentId: string = ''
  name: string = ''
  status: string = ''
  conversationTurn: number = 0
  rounds: number = 0
  toolCallCount: number = 0
}

class SubAgentProgressResponse {
  status: string = 'running'
  nextAction: string = 'continue_main_thread_work_without_polling'
  batchIds: string[] = []
  agents: SubAgentProgressItem[] = []
  note: string = ''
}

class SubAgentErrorResponse {
  error: string = ''
  cancelled: boolean = false

  constructor(error: string, cancelled: boolean = false) {
    this.error = error
    this.cancelled = cancelled
  }
}

// 单轮流式请求的产出
class SubAgentRoundOutcome {
  content: string = ''
  reasoningContent: string = ''
  toolCalls: ToolCall[] = []
  error: string = ''
}

export const SUB_AGENT_STATUS_RUNNING = 'running'
export const SUB_AGENT_STATUS_COMPLETED = 'completed'
export const SUB_AGENT_STATUS_IDLE = 'idle'
export const SUB_AGENT_STATUS_FAILED = 'failed'
export const SUB_AGENT_STATUS_CANCELLED = 'cancelled'

export const SUB_AGENT_TOOL_EVENT_RUNNING = 'running'
export const SUB_AGENT_TOOL_EVENT_OK = 'ok'
export const SUB_AGENT_TOOL_EVENT_ERROR = 'error'

// ============ 实时预览状态（供 bindSheet 预览面板观察）============

// 子智能体的单次工具调用事件
@ObservedV2
export class SubAgentToolEventState {
  @Trace functionName: string = ''
  @Trace displayName: string = ''
  @Trace argsPreview: string = ''
  @Trace status: string = SUB_AGENT_TOOL_EVENT_RUNNING
  @Trace resultPreview: string = ''
}

// 单个子智能体的实时运行状态
@ObservedV2
export class SubAgentLiveState {
  @Trace agentId: string = ''
  @Trace name: string = ''
  @Trace promptPreview: string = ''
  @Trace status: string = SUB_AGENT_STATUS_RUNNING
  @Trace conversationTurns: number = 0
  @Trace rounds: number = 0
  @Trace liveContent: string = ''
  @Trace toolEvents: SubAgentToolEventState[] = []
}

// 最近一批子智能体的整体状态（保留到下一批开始，供事后查看）
@ObservedV2
export class SubAgentPreviewState {
  @Trace agents: SubAgentLiveState[] = []
  @Trace active: boolean = false
  @Trace hasEverRun: boolean = false
}

// 单个子智能体的持久会话。messages 会跨主从对话轮次保留；一次模型回复完成后会话
// 只进入空闲态，不会销毁，主智能体可继续通过 sub_agent_message 发送下一条消息。
class SubAgentSession {
  id: string
  name: string
  liveState: SubAgentLiveState
  messages: RequestMessage[]
  apiService: AIApiService
  tools: ToolDefinition[]
  allowedFunctionNames: string[]
  budgetKey: string
  generation: number
  conversationTurns: number = 0
  totalRounds: number = 0
  totalToolCallCount: number = 0
  busy: boolean = false
  awaitingCollection: boolean = false
  // 每个子智能体各自算自己的上下文，压缩计数与失败记忆也各自独立
  compactCount: number = 0
  // 上一次压缩失败时的消息条数：没有新进展前不再反复发摘要请求
  compactionFailedAtMessageCount: number = -1

  constructor(
    id: string,
    name: string,
    liveState: SubAgentLiveState,
    messages: RequestMessage[],
    apiService: AIApiService,
    tools: ToolDefinition[],
    allowedFunctionNames: string[],
    budgetKey: string,
    generation: number
  ) {
    this.id = id
    this.name = name
    this.liveState = liveState
    this.messages = messages
    this.apiService = apiService
    this.tools = tools
    this.allowedFunctionNames = allowedFunctionNames
    this.budgetKey = budgetKey
    this.generation = generation
  }
}

// 一次派发或续发形成一个可收取批次。批次是“一轮回复”的句柄；会话本身在批次
// 收取后继续存在，因此同一个 agentId 可以参与任意多轮主从对话。
class SubAgentBatch {
  id: string
  sessions: SubAgentSession[]
  pending: Promise<SubAgentTaskReport[]>
  note: string
  settled: boolean = false
  collected: boolean = false

  constructor(
    id: string,
    sessions: SubAgentSession[],
    pending: Promise<SubAgentTaskReport[]>,
    note: string
  ) {
    this.id = id
    this.sessions = sessions
    this.pending = pending
    this.note = note
  }
}

// 主智能体结束本轮却没有收取子智能体结果时的兜底回灌次数上限，
// 防止“派发 → 结束 → 回灌 → 再派发”无限循环
const SUB_AGENT_MAX_AUTO_COLLECT_ROUNDS: number = 3

// 子智能体服务：主智能体通过 sub_agent 工具一次派出 1-3 个子智能体并行处理子任务。
// 每个子智能体拥有独立且可复用的对话上下文和不限轮次的工具调用循环。
// sub_agent 只负责派发并立即返回 batch_id，子智能体在后台继续运行，主智能体因此
// 可以在同一轮请求里继续做自己的工作；需要产出时再调用 sub_agent_result 收取，
// 收取后通过 sub_agent_message 可继续任意多轮主从对话。
export class SubAgentService {
  private static instance: SubAgentService | null = null
  private runtime: SubAgentRuntimeConfig | null = null
  // 实时预览状态：始终保留最近一批子智能体的运行情况
  private previewState: SubAgentPreviewState = new SubAgentPreviewState()
  // 子智能体全局序号，用于给工具调用 id 加唯一后缀
  private agentSequence: number = 0
  // 本次请求已派发、尚未（或已经）收取的批次，按派发顺序保存
  private batches: Map<string, SubAgentBatch> = new Map()
  // 本次主对话请求内仍可继续交谈的子智能体会话
  private sessions: Map<string, SubAgentSession> = new Map()
  private batchSequence: number = 0
  private autoCollectRounds: number = 0
  // 运行时代号：每次配置/清理运行时递增，后台仍在跑的子智能体据此自行退出，
  // 避免请求结束（正常完成或出错）后还有子智能体继续消耗额度
  private generation: number = 0

  private constructor() {}

  static getInstance(): SubAgentService {
    if (SubAgentService.instance === null) {
      SubAgentService.instance = new SubAgentService()
    }
    return SubAgentService.instance
  }

  configureRuntime(runtime: SubAgentRuntimeConfig): void {
    this.generation += 1
    this.runtime = runtime
    this.batches.clear()
    this.sessions.clear()
    this.autoCollectRounds = 0
  }

  clearRuntime(): void {
    this.generation += 1
    this.runtime = null
    this.batches.clear()
    this.sessions.clear()
    this.autoCollectRounds = 0
    this.previewState.active = false
  }

  getPreviewState(): SubAgentPreviewState {
    return this.previewState
  }

  // sub_agent 工具执行入口：派发后立即返回，不等待子智能体完成
  async executeSubAgentToolCall(argsJson: string): Promise<string> {
    const runtime = this.runtime
    if (runtime === null) {
      return JSON.stringify(new SubAgentErrorResponse('子智能体运行时未初始化，请重新发送消息后再试'))
    }

    let parsedArgs: SubAgentDispatchArguments = {}
    try {
      parsedArgs = parseSubAgentToolArguments(argsJson)
    } catch (_error) {
      return JSON.stringify(new SubAgentErrorResponse('sub_agent 参数不是合法 JSON'))
    }

    const rawTasks = parsedArgs.tasks
    if (rawTasks === undefined || rawTasks.length === 0) {
      return JSON.stringify(new SubAgentErrorResponse(
        'sub_agent 需要 1-3 个任务；请至少提供非空 task_1_prompt'
      ))
    }

    const tasks: SubAgentTaskArguments[] = []
    for (let i = 0; i < rawTasks.length && tasks.length < SUB_AGENT_MAX_TASKS; i++) {
      const prompt = rawTasks[i].prompt
      if (prompt !== undefined && prompt.trim() !== '') {
        tasks.push(rawTasks[i])
      }
    }
    if (tasks.length === 0) {
      return JSON.stringify(new SubAgentErrorResponse('sub_agent 的每个任务都必须包含非空 prompt'))
    }
    const mainThreadWork = parsedArgs.main_thread_work !== undefined ? parsedArgs.main_thread_work.trim() : ''
    if (mainThreadWork === '') {
      return JSON.stringify(new SubAgentErrorResponse(
        'sub_agent 必须提供非空 main_thread_work，明确派发后主线程要先完成的具体交付物'
      ))
    }

    // 当前请求第一次派发时清除上一次请求留下的预览；同一请求后续新派发则追加。
    const mergedAgents: SubAgentLiveState[] = []
    if (this.sessions.size > 0) {
      for (let i = 0; i < this.previewState.agents.length; i++) {
        mergedAgents.push(this.previewState.agents[i])
      }
    }
    const dispatchedSessions: SubAgentSession[] = []
    const taskNames: string[] = []
    for (let i = 0; i < tasks.length; i++) {
      const live = new SubAgentLiveState()
      live.name = this.resolveTaskName(tasks[i], i)
      const taskPrompt = tasks[i].prompt
      live.promptPreview = this.truncateForPreview(taskPrompt !== undefined ? taskPrompt : '', 200)
      const session = this.createSubAgentSession(runtime, live)
      live.agentId = session.id
      this.sessions.set(session.id, session)
      dispatchedSessions.push(session)
      taskNames.push(live.name)
      mergedAgents.push(live)
    }
    this.previewState.agents = mergedAgents
    this.previewState.active = true
    this.previewState.hasEverRun = true

    const pendingReports: Promise<SubAgentTaskReport>[] = []
    for (let i = 0; i < tasks.length; i++) {
      pendingReports.push(this.runSubAgentTurn(
        runtime,
        dispatchedSessions[i],
        this.buildSubAgentTaskPrompt(tasks[i])
      ))
    }

    let note = ''
    if (rawTasks.length > SUB_AGENT_MAX_TASKS) {
      note = pickPromptText(runtime.promptLanguage,
        `一次最多派出 ${SUB_AGENT_MAX_TASKS} 个子智能体，多余任务已忽略；如有需要请在后续轮次继续派出。`,
        `At most ${SUB_AGENT_MAX_TASKS} sub-agents can be dispatched at once. Excess tasks were omitted; dispatch them later if needed.`)
    }
    const batch = this.registerBatch(dispatchedSessions, pendingReports, note)
    console.info('SubAgentService', `Dispatching ${tasks.length} sub-agent(s) as ${batch.id}`)

    const response = new SubAgentDispatchResponse()
    response.batchId = batch.id
    response.mainThreadWork = mainThreadWork
    response.agents = taskNames
    response.sessions = this.buildSessionDescriptors(dispatchedSessions)
    response.note = pickPromptText(runtime.promptLanguage, `已派出 ${tasks.length} 个子智能体，它们正在后台运行。` +
      '下一步不是收取结果：禁止紧接着调用 sub_agent_result（wait=true/false 均不应）。' +
      `请立即完成你承诺的主线程交付物：“${mainThreadWork}”。` +
      '只有该交付物已完成且主线程已无可独立推进的工作时才允许收取。' +
      `收取后会话不会关闭，可用 sessions 中的 agentId 调用 sub_agent_message 继续引导。${note}`,
      `${tasks.length} sub-agents are running in the background. First complete the independent main-thread work: ` +
        `${JSON.stringify(mainThreadWork)}. Do not collect immediately after dispatch. ` +
        'Collect when this work is done and further progress depends on their replies. Sessions remain available ' +
        `for targeted follow-ups through sub_agent_message using the agentIds in sessions. ${note}`)
    return JSON.stringify(response)
  }

  // 向一个或多个已空闲的子智能体续发消息。续发会复用完整的 system/user/assistant/tool
  // 上下文，并像初次派发一样立即返回新 batchId；对话轮数没有硬编码上限。
  async sendSubAgentMessages(argsJson: string): Promise<string> {
    const runtime = this.runtime
    if (runtime === null) {
      return JSON.stringify(new SubAgentErrorResponse('子智能体运行时未初始化，请重新发送消息后再试'))
    }

    let parsedArgs: SubAgentMessageToolArgs = {}
    try {
      parsedArgs = JSON.parse(argsJson) as SubAgentMessageToolArgs
    } catch (_error) {
      return JSON.stringify(new SubAgentErrorResponse('sub_agent_message 参数不是合法 JSON'))
    }
    const rawMessages = parsedArgs.messages
    if (rawMessages === undefined || rawMessages.length === 0) {
      return JSON.stringify(new SubAgentErrorResponse(
        'sub_agent_message 需要至少一条 messages，每条消息必须包含 agent_id 和非空 message'
      ))
    }
    const mainThreadWork = parsedArgs.main_thread_work !== undefined ? parsedArgs.main_thread_work.trim() : ''
    const targetSessions: SubAgentSession[] = []
    const followUpPrompts: string[] = []
    for (let i = 0; i < rawMessages.length; i++) {
      const item = rawMessages[i]
      const rawAgentId = item.agent_id !== undefined ? item.agent_id : item.agentId
      const rawMessage = item.message
      const agentId = rawAgentId !== undefined ? rawAgentId.trim() : ''
      const message = rawMessage !== undefined ? rawMessage.trim() : ''
      if (agentId === '' || message === '') {
        return JSON.stringify(new SubAgentErrorResponse(
          `sub_agent_message 的第 ${i + 1} 条消息缺少 agent_id 或非空 message`
        ))
      }
      const session = this.sessions.get(agentId)
      if (session === undefined || session.generation !== this.generation) {
        return JSON.stringify(new SubAgentErrorResponse(`未找到 agent_id=${agentId} 的可用子智能体会话`))
      }
      if (targetSessions.includes(session)) {
        return JSON.stringify(new SubAgentErrorResponse(
          `同一次 sub_agent_message 不能向 agent_id=${agentId} 连续发送多条消息，请合并为一条`
        ))
      }
      if (session.busy) {
        return JSON.stringify(new SubAgentErrorResponse(
          `agent_id=${agentId} 仍在生成回复，请先调用 sub_agent_result 收取当前批次`
        ))
      }
      if (session.awaitingCollection) {
        return JSON.stringify(new SubAgentErrorResponse(
          `agent_id=${agentId} 的上一轮回复尚未收取，请先调用 sub_agent_result，再根据回复继续引导`
        ))
      }
      targetSessions.push(session)
      followUpPrompts.push(this.buildFollowUpPrompt(item))
    }

    const pendingReports: Promise<SubAgentTaskReport>[] = []
    for (let i = 0; i < targetSessions.length; i++) {
      pendingReports.push(this.runSubAgentTurn(runtime, targetSessions[i], followUpPrompts[i]))
    }
    const batch = this.registerBatch(targetSessions, pendingReports, '')
    this.previewState.active = true
    this.previewState.hasEverRun = true

    const response = new SubAgentDispatchResponse()
    response.batchId = batch.id
    response.mainThreadWork = mainThreadWork
    for (let i = 0; i < targetSessions.length; i++) {
      response.agents.push(targetSessions[i].name)
    }
    response.sessions = this.buildSessionDescriptors(targetSessions)
    response.note = pickPromptText(runtime.promptLanguage, `已向 ${targetSessions.length} 个子智能体续发消息，原上下文已保留。` +
      (mainThreadWork !== '' ? `等待期间可继续：“${mainThreadWork}”。` : '') +
      '需要回复时用 sub_agent_result(wait=true) 收取；没有可独立推进的工作时直接等待，不要制造新任务或反复轮询。',
      `Sent follow-ups to ${targetSessions.length} sub-agents with their context preserved. ` +
        (mainThreadWork !== '' ? `Independent work while waiting: ${JSON.stringify(mainThreadWork)}. ` : '') +
        'Collect needed replies with sub_agent_result(wait=true). If no independent work remains, wait directly; do not invent tasks or poll repeatedly.')
    return JSON.stringify(response)
  }

  // sub_agent_result 工具执行入口：收取（或查看）已派发批次的结果
  async collectSubAgentResults(argsJson: string): Promise<string> {
    let parsedArgs: SubAgentResultToolArgs = {}
    if (argsJson !== undefined && argsJson !== null && argsJson.trim() !== '') {
      try {
        parsedArgs = JSON.parse(argsJson) as SubAgentResultToolArgs
      } catch (_error) {
        // 无参调用等价于“收取全部未收取批次”，不因为空参数或脏 JSON 直接失败
        parsedArgs = {}
      }
    }
    const requestedBatchId = parsedArgs.batch_id !== undefined ? parsedArgs.batch_id.trim() : ''
    const shouldWait = parsedArgs.wait !== false

    const targets = this.resolveTargetBatches(requestedBatchId)
    if (targets.length === 0) {
      return JSON.stringify(new SubAgentErrorResponse(
        requestedBatchId !== ''
          ? `未找到 batch_id=${requestedBatchId} 的子智能体批次`
          : '当前没有待收取的子智能体批次；如尚未派发请调用 sub_agent，' +
            '如要继续已有会话请调用 sub_agent_message'
      ))
    }

    if (!shouldWait) {
      return JSON.stringify(this.buildProgressResponse(targets))
    }

    const response = new SubAgentCollectResponse()
    for (let i = 0; i < targets.length; i++) {
      const batch = targets[i]
      const reports = await batch.pending
      const wasCollected = batch.collected
      batch.settled = true
      batch.collected = true
      response.batchIds.push(batch.id)
      for (let j = 0; j < reports.length; j++) {
        response.results.push(reports[j])
      }
      if (batch.note !== '') {
        response.note = batch.note
      }
      if (!wasCollected) {
        for (let j = 0; j < batch.sessions.length; j++) {
          const session = batch.sessions[j]
          session.awaitingCollection = false
          if (!session.busy && session.generation === this.generation &&
            session.liveState.status !== SUB_AGENT_STATUS_CANCELLED) {
            session.liveState.status = SUB_AGENT_STATUS_IDLE
          }
        }
      }
    }
    this.refreshPreviewActive()

    const runtime = this.runtime
    if (runtime !== null && runtime.isCancelled()) {
      return JSON.stringify(new SubAgentErrorResponse('子智能体执行已取消', true))
    }
    response.note = (response.note !== '' ? response.note + ' ' : '') + getCollectedSubAgentGuidance(runtime !== null ? runtime.promptLanguage : PromptLanguage.ZH_CN)
    return JSON.stringify(response)
  }

  // 主智能体结束本轮时是否还有没被收取的子智能体产出
  hasUncollectedBatches(): boolean {
    let found = false
    this.batches.forEach((batch: SubAgentBatch): void => {
      if (!batch.collected) {
        found = true
      }
    })
    return found
  }

  canAutoCollect(): boolean {
    return this.autoCollectRounds < SUB_AGENT_MAX_AUTO_COLLECT_ROUNDS && this.hasUncollectedBatches()
  }

  // 兜底收取：主智能体没主动调用 sub_agent_result 就结束了本轮，
  // 由调用方把结果回灌成一轮上下文后让模型重新作答
  async autoCollectPendingResults(): Promise<string> {
    this.autoCollectRounds += 1
    return await this.collectSubAgentResults('{}')
  }

  private resolveTargetBatches(batchId: string): SubAgentBatch[] {
    const targets: SubAgentBatch[] = []
    if (batchId !== '') {
      const batch = this.batches.get(batchId)
      if (batch !== undefined) {
        targets.push(batch)
      }
      return targets
    }
    this.batches.forEach((batch: SubAgentBatch): void => {
      if (!batch.collected) {
        targets.push(batch)
      }
    })
    return targets
  }

  private buildProgressResponse(targets: SubAgentBatch[]): SubAgentProgressResponse {
    const response = new SubAgentProgressResponse()
    let allSettled = true
    for (let i = 0; i < targets.length; i++) {
      const batch = targets[i]
      response.batchIds.push(batch.id)
      if (!batch.settled) {
        allSettled = false
      }
      for (let j = 0; j < batch.sessions.length; j++) {
        const session = batch.sessions[j]
        const live = session.liveState
        const item = new SubAgentProgressItem()
        item.batchId = batch.id
        item.agentId = session.id
        item.name = live.name
        item.status = live.status
        item.conversationTurn = session.conversationTurns
        item.rounds = live.rounds
        item.toolCallCount = session.totalToolCallCount
        response.agents.push(item)
      }
    }
    response.status = allSettled ? 'ready' : SUB_AGENT_STATUS_RUNNING
    response.nextAction = allSettled
      ? 'collect_only_after_main_thread_work_is_complete'
      : 'continue_main_thread_work_without_polling'
    response.note = allSettled
      ? '子智能体本轮回复已就绪。如果主线程交付物也已完成，可调用 sub_agent_result(wait=true) 取回；' +
        '否则先继续主线程工作。'
      : '子智能体仍在运行。不要连续查看进度；请继续完成主线程交付物，' +
        '直到确实需要回复才能推进时再收取。'
    return response
  }

  private hasRunningBatch(): boolean {
    let running = false
    this.batches.forEach((batch: SubAgentBatch): void => {
      if (!batch.settled) {
        running = true
      }
    })
    return running
  }

  private refreshPreviewActive(): void {
    this.previewState.active = this.hasRunningBatch()
  }

  private resolveTaskName(task: SubAgentTaskArguments, index: number): string {
    return task.name !== undefined && task.name.trim() !== '' ? task.name.trim() : `sub-agent-${index + 1}`
  }

  private truncateForPreview(text: string, maxLength: number): string {
    const normalized = text.trim()
    if (normalized.length <= maxLength) {
      return normalized
    }
    return normalized.substring(0, maxLength) + '…'
  }

  private buildFollowUpPrompt(item: SubAgentMessageItemArgs): string {
    const message = item.message !== undefined ? item.message.trim() : ''
    const expectedOutput = item.expected_output !== undefined ? item.expected_output.trim() : ''
    if (expectedOutput === '') {
      return message
    }
    return `${message}\n\n${pickPromptText(this.runtime?.promptLanguage ?? PromptLanguage.ZH_CN, '本轮期望输出格式', 'Expected output for this turn')}:\n${expectedOutput}`
  }

  private buildSessionDescriptors(sessions: SubAgentSession[]): SubAgentSessionDescriptor[] {
    const descriptors: SubAgentSessionDescriptor[] = []
    for (let i = 0; i < sessions.length; i++) {
      const descriptor = new SubAgentSessionDescriptor()
      descriptor.agentId = sessions[i].id
      descriptor.name = sessions[i].name
      descriptors.push(descriptor)
    }
    return descriptors
  }

  private createSubAgentSession(runtime: SubAgentRuntimeConfig, live: SubAgentLiveState): SubAgentSession {
    this.agentSequence += 1
    const agentId = `agent_${this.agentSequence}`
    const budgetKey = `sub-agent-${this.agentSequence}`
    const agentTools = buildSubAgentToolSet(runtime.tools)
    const allowedFunctionNames: string[] = []
    let hasAskUserTool = false
    let hasKnowledgeSearchTool = false
    let hasWebSearchTool = false
    for (let i = 0; i < agentTools.length; i++) {
      allowedFunctionNames.push(agentTools[i].function.name)
      if (this.isAskUserFunction(agentTools[i].function.name)) {
        hasAskUserTool = true
      }
      if (agentTools[i].function.name === 'knowledge_search') {
        hasKnowledgeSearchTool = true
      }
      if (agentTools[i].function.name === 'web_search') {
        hasWebSearchTool = true
      }
    }

    const messages: RequestMessage[] = []
    messages.push(new RequestMessage(
      'system',
      this.buildSubAgentSystemPrompt(
        runtime,
        live.name,
        hasAskUserTool,
        hasKnowledgeSearchTool,
        hasWebSearchTool
      )
    ))
    return new SubAgentSession(
      agentId,
      live.name,
      live,
      messages,
      AIApiService.createIsolated(),
      agentTools,
      allowedFunctionNames,
      budgetKey,
      this.generation
    )
  }

  private registerBatch(
    sessions: SubAgentSession[],
    pendingReports: Promise<SubAgentTaskReport>[],
    note: string
  ): SubAgentBatch {
    this.batchSequence += 1
    const batchId = `batch_${this.batchSequence}`
    // 每个会话单独兜底，避免一个异常让同批次仍在工作的其它会话被误标为空闲。
    const safePendingReports: Promise<SubAgentTaskReport>[] = []
    for (let i = 0; i < pendingReports.length; i++) {
      const session = sessions[i]
      safePendingReports.push(pendingReports[i].catch((error: Object): SubAgentTaskReport => {
        console.error(
          'SubAgentService',
          `Sub-agent ${session.id} in ${batchId} failed: ${JSON.stringify(error)}`
        )
        session.busy = false
        session.awaitingCollection = true
        session.liveState.status = SUB_AGENT_STATUS_FAILED
        const failed = new SubAgentTaskReport()
        failed.agentId = session.id
        failed.name = session.name
        failed.status = SUB_AGENT_STATUS_FAILED
        failed.result = `子智能体执行异常: ${JSON.stringify(error)}`
        failed.conversationTurn = session.conversationTurns
        return failed
      }))
    }
    // 所有单项 Promise 都已兜底，批次 pending 可安全延后到 sub_agent_result 再 await。
    const pending: Promise<SubAgentTaskReport[]> = Promise.all(safePendingReports)
    const batch = new SubAgentBatch(batchId, sessions, pending, note)
    this.batches.set(batchId, batch)
    pending.then((): void => {
      batch.settled = true
      this.refreshPreviewActive()
    })
    return batch
  }

  // 运行子智能体的一轮对话：会话上下文持久保留；轮内工具调用循环同样不设次数上限。
  private async runSubAgentTurn(
    runtime: SubAgentRuntimeConfig,
    session: SubAgentSession,
    userMessage: string
  ): Promise<SubAgentTaskReport> {
    const report = new SubAgentTaskReport()
    report.agentId = session.id
    report.name = session.name
    session.busy = true
    session.awaitingCollection = true
    session.conversationTurns += 1
    report.conversationTurn = session.conversationTurns
    const live = session.liveState
    live.status = SUB_AGENT_STATUS_RUNNING
    live.conversationTurns = session.conversationTurns
    if (session.conversationTurns > 1) {
      live.liveContent += `\n\n—— 主助手第 ${session.conversationTurns} 轮指令 ——\n` +
        `${this.truncateForPreview(userMessage, 500)}\n\n`
    }

    // 会话必须同时盯住运行时代号：
    // 请求正常结束或出错时 clearRuntime() 递增代号，后台子智能体据此自行退出
    const isCancelled = (): boolean => runtime.isCancelled() || this.generation !== session.generation
    // 上轮的停止通知不能约束新的续发指令；工具结果和推理历史仍保留。
    for (let i = session.messages.length - 1; i >= 0; i--) {
      if (session.messages[i].role === 'system' && isToolProgressStop(session.messages[i].content)) {
        session.messages.splice(i, 1)
      }
    }
    session.messages.push(new RequestMessage('user', userMessage))
    runtime.onToolTurnStarted(session.id)
    // 流式内容按 150ms 节流写入预览状态，避免高频 UI 刷新
    const liveContentThrottle = createThrottle(150)
    const appendLiveContent = (chunk: string): void => {
      liveContentThrottle.throttle(chunk, (batched: string) => {
        live.liveContent += batched
      })
    }
    const flushLiveContent = (): void => {
      liveContentThrottle.flush((batched: string) => {
        live.liveContent += batched
      })
    }

    while (true) {
      if (isCancelled()) {
        report.status = SUB_AGENT_STATUS_CANCELLED
        report.result = '任务被用户取消'
        live.status = SUB_AGENT_STATUS_CANCELLED
        session.busy = false
        return report
      }

      // 发请求前先自检上下文。子智能体独立计算自己的窗口用量，越过阈值就地压缩，
      // 不依赖主对话的压缩闸门，也不占用主对话那一次压缩机会。
      await this.compactSessionIfNeeded(runtime, session, isCancelled)
      if (isCancelled()) {
        report.status = SUB_AGENT_STATUS_CANCELLED
        report.result = '任务被用户取消'
        live.status = SUB_AGENT_STATUS_CANCELLED
        session.busy = false
        return report
      }

      report.rounds += 1
      session.totalRounds += 1
      live.rounds = session.totalRounds
      console.info(
        'SubAgentService',
        `[${report.name}] conversation ${report.conversationTurn}, model round ${report.rounds}`
      )
      const stopTools = runtime.shouldStopTools(session.id)
      if (stopTools) {
        session.messages.push(new RequestMessage('system', getToolProgressStop(runtime.promptLanguage)))
      }
      this.refreshResponseLanguageReminder(session.messages, runtime.promptLanguage)
      const outcome = await this.performStreamRound(
        runtime,
        session.apiService,
        session.messages,
        stopTools ? [] : session.tools,
        appendLiveContent,
        isCancelled
      )
      flushLiveContent()

      if (isCancelled()) {
        report.status = SUB_AGENT_STATUS_CANCELLED
        report.result = '任务被用户取消'
        live.status = SUB_AGENT_STATUS_CANCELLED
        session.busy = false
        return report
      }

      if (outcome.error !== '') {
        report.status = SUB_AGENT_STATUS_FAILED
        report.result = outcome.content !== ''
          ? `请求失败: ${outcome.error}\n\n失败前的部分输出:\n${outcome.content}`
          : `请求失败: ${outcome.error}`
        live.status = SUB_AGENT_STATUS_FAILED
        session.busy = false
        return report
      }

      if (outcome.toolCalls.length === 0 || stopTools) {
        report.status = SUB_AGENT_STATUS_COMPLETED
        report.result = outcome.content !== '' ? outcome.content :
          (stopTools ? getToolProgressStop(runtime.promptLanguage) : pickPromptText(runtime.promptLanguage, '(子智能体没有输出内容)', '(No content returned by sub-agent)'))
        const assistantMessage = new RequestMessage('assistant', outcome.content)
        assistantMessage.reasoningContent = outcome.reasoningContent
        session.messages.push(assistantMessage)
        live.status = SUB_AGENT_STATUS_COMPLETED
        session.busy = false
        return report
      }

      // 工具调用 id 加子智能体后缀保证全局唯一；随后构建的 assistant/tool 消息
      // 使用同一批对象，改写后的 id 在续轮请求里保持一致
      for (let i = 0; i < outcome.toolCalls.length; i++) {
        outcome.toolCalls[i].id = `${outcome.toolCalls[i].id}_sa_${session.id}` +
          `_t${session.conversationTurns}_r${session.totalRounds}`
      }

      // 执行工具调用并把结果拼回上下文，继续下一轮
      const assistantMsg = RequestMessage.createAssistantWithToolCalls(outcome.content, outcome.toolCalls)
      assistantMsg.reasoningContent = outcome.reasoningContent
      session.messages.push(assistantMsg)
      const nativeToolInputs: RequestMessage[] = []
      for (let i = 0; i < outcome.toolCalls.length; i++) {
        report.toolCallCount += 1
        session.totalToolCallCount += 1
        const toolCall = outcome.toolCalls[i]
        const toolEvent = new SubAgentToolEventState()
        toolEvent.functionName = toolCall.functionName
        toolEvent.displayName = toolCall.functionName
        toolEvent.argsPreview = this.truncateForPreview(toolCall.arguments, 300)
        live.toolEvents.push(toolEvent)

        // 预先打上来源标签并镜像到主对话消息：ask_user 弹窗/结果栏、图表、
        // Canvas、日程审批等交互式工具由此对用户可见（ToolCall 为 @ObservedV2，
        // 执行过程中回填的显示名等字段会实时反映到卡片上）
        toolCall.sourceLabel = `${SUB_AGENT_SOURCE_LABEL_PREFIX}${report.name}`
        runtime.onToolCallStarted(toolCall)

        // 工具互斥（“同一时刻只执行一个工具”）由 toolRunner 统一负责：主智能体与
        // 子智能体现在会同时执行工具，两边必须共用同一把锁，不能各锁各的
        const toolResult = await this.runToolCallSafely(
          runtime,
          toolCall,
          session.allowedFunctionNames,
          session.budgetKey,
          runtime.toolExecutionContext.withActor(session.id)
        )

        // executeToolCall 会把注册表里的显示名回填到 toolCall 上
        toolEvent.displayName = toolCall.displayName !== '' ? toolCall.displayName : toolCall.functionName
        toolEvent.status = toolResult.isError ? SUB_AGENT_TOOL_EVENT_ERROR : SUB_AGENT_TOOL_EVENT_OK
        toolEvent.resultPreview = this.truncateForPreview(toolResult.content, 400)
        runtime.onToolCallCompleted(toolCall, toolResult)
        console.info(
          'SubAgentService',
          `[${report.name}] tool ${toolCall.functionName} -> ${toolResult.isError ? 'error' : 'ok'}`
        )
        session.messages.push(RequestMessage.createToolResultMessage(toolResult.toolCallId, toolResult.content))
        const inputs = RequestMessage.consumeToolInputMessages([toolResult])
        for (let j = 0; j < inputs.length; j++) {
          nativeToolInputs.push(inputs[j])
        }
      }
      for (let i = 0; i < nativeToolInputs.length; i++) {
        session.messages.push(nativeToolInputs[i])
      }
      // 工具轮次之间用空行分隔流式正文，预览里更易读
      if (live.liveContent !== '' && !live.liveContent.endsWith('\n\n')) {
        live.liveContent += '\n\n'
      }
    }
  }

  private isAskUserFunction(functionName: string): boolean {
    const normalized = functionName.toLowerCase().replace(/[\s\-]+/g, '_')
    return normalized === 'ask_user' || normalized === 'user_input' || normalized === 'ask'
  }

  private refreshResponseLanguageReminder(messages: RequestMessage[], language: PromptLanguage): void {
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role === 'system' && (messages[i].content === getResponseLanguageContinuationReminder(PromptLanguage.ZH_CN) ||
        messages[i].content === getResponseLanguageContinuationReminder(PromptLanguage.EN_US))) {
        messages.splice(i, 1)
      }
    }
    messages.push(new RequestMessage('system', getResponseLanguageContinuationReminder(language)))
  }

  private buildSubAgentSystemPrompt(
    runtime: SubAgentRuntimeConfig,
    agentName: string,
    hasAskUser: boolean,
    hasKnowledgeSearch: boolean,
    hasWebSearch: boolean
  ): string {
    if (runtime.promptLanguage === PromptLanguage.ZH_CN) {
      return this.buildChineseSubAgentSystemPrompt(runtime, agentName, hasAskUser, hasKnowledgeSearch, hasWebSearch)
    }
    const askUserRule = hasAskUser
      ? '- Use ask_user only for material ambiguity you cannot reasonably resolve. These questions are visible to the user; use the requested output language. Otherwise proceed with reasonable assumptions and state them when relevant.'
      : '- You cannot ask the user questions. Proceed with reasonable assumptions where possible and state material uncertainty.'
    const knowledgeSearchRule = hasKnowledgeSearch
      ? (hasFiniteRetrievalCallLimit(runtime.knowledgeSearchCallLimit)
        ? `- Retrieve user files with knowledge_search as needed, at most ${runtime.knowledgeSearchCallLimit} calls per turn. Your budget is independent of other agents. Stop at the limit or when evidence is sufficient.`
        : '- Use knowledge_search as needed with an independent budget and no fixed call limit. Stop when evidence is sufficient or further queries offer no new information.')
      : ''
    const webSearchRule = hasWebSearch
      ? (hasFiniteRetrievalCallLimit(runtime.webSearchCallLimit)
        ? `- Use web_search at most ${runtime.webSearchCallLimit} times per turn, independently of other agents. At the limit, report from available evidence.`
        : '- Use web_search as needed with an independent budget and no fixed call limit. Stop when evidence is sufficient or further queries offer no new information.')
      : ''
    return appendResponseLanguageSystemPrompt(`Current time: ${runtime.timeContext}

You are the sub-agent ${JSON.stringify(agentName)}, assigned an independent task by the main assistant.

Execution rules:
- Your reply is returned to the main assistant as a tool result. Follow-ups reuse this conversation; continue from its context.
- Complete all currently actionable work and return a concise, complete report. Do not defer available work merely because a follow-up is possible.
${getTaskExecutionPrompt(runtime.promptLanguage)}
${askUserRule}
${webSearchRule}
${knowledgeSearchRule}
- Preserve source titles and URLs for external claims.
- Deliver the result with necessary evidence, or explain the remaining work or blocker. Stop when the task is complete, without routine self-check sections or suggestions to keep questioning.
- Honor the output language specified in the assignment or expected output; operational instructions and tool results do not override it.`, runtime.promptLanguage)
  }

  private buildChineseSubAgentSystemPrompt(
    runtime: SubAgentRuntimeConfig,
    agentName: string,
    hasAskUser: boolean,
    hasKnowledgeSearch: boolean,
    hasWebSearch: boolean
  ): string {
    const askUserRule = hasAskUser
      ? '- 仅在遇到无法自行决定的关键歧义时，才调用 ask_user 向用户提问（问题会显示在主对话中）；能合理假设时优先继续完成，并在结果中说明假设。'
      : '- 你无法向用户提问。信息不足时基于合理假设继续，并在结果中说明假设与不确定性。'
    const knowledgeSearchRule = hasKnowledgeSearch
      ? (hasFiniteRetrievalCallLimit(runtime.knowledgeSearchCallLimit)
        ? `- 本次对话已开启知识库，你可调用 knowledge_search 检索用户文件。每轮最多调用 ${runtime.knowledgeSearchCallLimit} 次；你独立计数，不与主助手或其他子智能体共享。达到上限或证据充分后立即停止检索。`
        : '- 本次对话已开启知识库，你可按需调用 knowledge_search 检索用户文件，不设固定次数上限。你独立计数，不与主助手或其他子智能体共享；证据充分、结果重复或已无新信息时立即停止检索。')
      : ''
    const webSearchRule = hasWebSearch
      ? (hasFiniteRetrievalCallLimit(runtime.webSearchCallLimit)
        ? `- 每轮最多调用 web_search ${runtime.webSearchCallLimit} 次；你独立计数，不与主助手或其他子智能体共享。达到上限后基于已有结果完成报告。`
        : '- 你可按需调用 web_search，不设固定次数上限，并独立计数，不与主助手或其他子智能体共享；证据充分、结果重复或已无新信息时立即停止搜索。')
      : ''
    return appendResponseLanguageSystemPrompt(`当前时间: ${runtime.timeContext}

你是主助手派出的子智能体「${agentName}」，负责独立完成一个明确的子任务。

执行规则:
- 你与主助手之间是可持续多轮的协作会话。每次回复都会作为工具结果返回给主助手；主助手之后可能继续追问、纠正方向或要求深化，你必须结合此前完整上下文继续工作。
- 每一轮都应输出简洁、结构化、信息完整的阶段回复；不要因为可能有下一轮而省略当前已能完成的内容。
${getTaskExecutionPrompt(runtime.promptLanguage)}
${askUserRule}
${webSearchRule}
${knowledgeSearchRule}
- 引用外部信息时保留关键来源（标题/URL），方便主助手复核。
- 本轮任务完成后直接输出结果，不要输出与任务无关的寒暄。
- 交付当前子任务的结果与必要依据；未完成时明确剩余工作或阻塞。任务完成后结束，不附加例行自检或建议主助手继续追问。`, runtime.promptLanguage)
  }

  private buildSubAgentTaskPrompt(task: SubAgentTaskArguments): string {
    const prompt = task.prompt !== undefined ? task.prompt.trim() : ''
    const expectedOutput = task.expected_output !== undefined ? task.expected_output.trim() : ''
    if (expectedOutput === '') {
      return prompt
    }
    return `${prompt}\n\n${pickPromptText(this.runtime?.promptLanguage ?? PromptLanguage.ZH_CN, '期望输出格式', 'Expected output')}:\n${expectedOutput}`
  }

  // ============ 子智能体上下文压缩 ============
  //
  // 子智能体的上下文与主对话完全独立：它有自己的 messages、自己的窗口预算，
  // 因此也必须自己判断阈值、自己压缩。此前这里没有任何压缩，历史涨到窗口上限后
  // resolveRequestMaxOutputTokens 把可用输出压到 1，或者供应商直接报超长，
  // 表现就是子智能体“到了阈值不压缩，然后整个停住”。

  // 摘要之外仍以原文保留的最近消息条数。子智能体一轮里可能有很多次工具往返，
  // 按条数保留比按“轮次”更贴合它的消息形状。
  private static readonly COMPACT_KEEP_RECENT_MESSAGES: number = 8

  // 送去做摘要的转写文本上限，避免摘要请求自己又撑爆窗口
  private static readonly COMPACT_TRANSCRIPT_MAX_CHARS: number = 80000
  private static readonly COMPACT_TRANSCRIPT_HEAD_CHARS: number = 20000
  private static readonly COMPACT_MESSAGE_PREVIEW_CHARS: number = 1500

  // 被切掉的部分太小就不值得压：摘要本身也要占一份上下文，
  // 换不来净收益的压缩只会白扔原文。先粗筛，拿到摘要后再按实际大小复核。
  private static readonly COMPACT_MIN_DROPPED_TOKENS: number = 1000

  // 前导 system 消息（子智能体的系统提示，以及上一次压缩插入的摘要）必须保留在最前。
  // 返回值是会话正文的起始下标。
  private resolveConversationStartIndex(messages: RequestMessage[]): number {
    let index = 0
    while (index < messages.length && messages[index].role === 'system') {
      index += 1
    }
    return index
  }

  private findExistingSummaryIndex(messages: RequestMessage[]): number {
    for (let i = 0; i < messages.length; i++) {
      if (messages[i].role !== 'system') {
        break
      }
      if (messages[i].content.indexOf(COMPACT_SUMMARY_PROMPT_MARKER) >= 0) {
        return i
      }
    }
    return -1
  }

  // 安全的切割点：只能切在 user 或 assistant 之前。切在 tool 之前会把 tool result
  // 与它的 assistant(tool_calls) 拆散，供应商会直接报协议错误。
  private snapToSafeBoundary(messages: RequestMessage[], startIndex: number, desired: number): number {
    // 优先向前退到这组调用的 assistant(tool_calls)：整组保留，留下的历史只多不少
    let backward = desired
    while (backward > startIndex && messages[backward].role === 'tool') {
      backward -= 1
    }
    if (backward > startIndex) {
      return backward
    }
    // 保留窗口之外整个就是一组超大的工具往返时，只能整组丢掉，否则永远压不动
    let forward = desired
    while (forward < messages.length && messages[forward].role === 'tool') {
      forward += 1
    }
    return forward
  }

  // 子智能体经常是“消息条数不多、但每条极重”——一次检索就能塞满窗口。固定保留 N 条
  // 会让这类会话永远切不出可压缩的部分，表现正是“到了阈值也不压缩”。这里逐步缩小
  // 保留窗口，直到能切出东西；但至少留一条原文，否则请求里会只剩 system 消息。
  private resolveSafeSplitIndex(messages: RequestMessage[], startIndex: number): number {
    for (let keep = SubAgentService.COMPACT_KEEP_RECENT_MESSAGES; keep >= 1; keep--) {
      const desired = messages.length - keep
      if (desired <= startIndex) {
        continue
      }
      const split = this.snapToSafeBoundary(messages, startIndex, desired)
      if (split > startIndex && split < messages.length) {
        return split
      }
    }
    return startIndex
  }

  private buildCompactionTranscript(messages: RequestMessage[]): string {
    const lines: string[] = []
    for (let i = 0; i < messages.length; i++) {
      const message = messages[i]
      const body = this.truncateForPreview(message.content, SubAgentService.COMPACT_MESSAGE_PREVIEW_CHARS)
      if (message.role === 'assistant' && message.toolCalls.length > 0) {
        const calls: string[] = []
        for (let j = 0; j < message.toolCalls.length; j++) {
          calls.push(`${message.toolCalls[j].functionName}(${this.truncateForPreview(
            message.toolCalls[j].arguments, 300)})`)
        }
        lines.push(`[子智能体] ${body}\n[调用工具] ${calls.join('; ')}`)
        continue
      }
      if (message.role === 'tool') {
        lines.push(`[工具结果] ${body}`)
        continue
      }
      if (message.role === 'user') {
        lines.push(`[主助手指令] ${body}`)
        continue
      }
      lines.push(`[子智能体] ${body}`)
    }
    const transcript = lines.join('\n\n')
    if (transcript.length <= SubAgentService.COMPACT_TRANSCRIPT_MAX_CHARS) {
      return transcript
    }
    // 掐掉中间而不是尾部：任务目标在开头，最新进展在结尾，两端都不能丢
    const head = transcript.substring(0, SubAgentService.COMPACT_TRANSCRIPT_HEAD_CHARS)
    const tailLength = SubAgentService.COMPACT_TRANSCRIPT_MAX_CHARS -
      SubAgentService.COMPACT_TRANSCRIPT_HEAD_CHARS
    const tail = transcript.substring(transcript.length - tailLength)
    return `${head}\n\n……（中间记录过长已省略）……\n\n${tail}`
  }

  // 摘要只要一段纯文本，不需要推理，也不该为它多付一份思考 token
  private buildCompactionApiConfig(source: AIApiConfig): AIApiConfig {
    const config: AIApiConfig = {
      providerId: source.providerId,
      providerType: source.providerType,
      apiStyle: source.apiStyle,
      apiKey: source.apiKey,
      baseUrl: source.baseUrl,
      apiPath: source.apiPath,
      openaiTransport: source.openaiTransport,
      customHeadersJson: source.customHeadersJson,
      topP: source.topP,
      presencePenalty: source.presencePenalty,
      frequencyPenalty: source.frequencyPenalty
    }
    config.modelReasoningStrategyOverride = ReasoningRequestStrategy.NONE
    config.modelSupportsReasoning = false
    return config
  }

  private async requestSubAgentSummary(
    runtime: SubAgentRuntimeConfig,
    session: SubAgentSession,
    droppedMessages: RequestMessage[]
  ): Promise<string> {
    const apiConfig = this.buildCompactionApiConfig(runtime.apiConfig)
    const requestMessages: RequestMessage[] = [
      new RequestMessage('system', ContextCompactionService.buildSubAgentSummarySystemPrompt(session.name, runtime.promptLanguage)),
      new RequestMessage('user',
        `以下是需要压缩的工作记录：\n\n${this.buildCompactionTranscript(droppedMessages)}\n\n` +
          ContextCompactionService.buildSubAgentSummaryUserPrompt(runtime.promptLanguage))
    ]
    // 流式解析状态是实例级的，摘要请求必须走独立实例，不能污染会话自己的解析器
    const isolated = AIApiService.createIsolated()
    const estimatedInput = isolated.estimateRequestInputTokens(
      apiConfig,
      requestMessages,
      runtime.modelId,
      ReasoningLevel.OFF
    )
    const maxOutputTokens = resolveRequestMaxOutputTokens(
      runtime.maxTokens,
      runtime.contextWindowTokens,
      estimatedInput
    )
    try {
      const result = await isolated.sendChatRequest(
        apiConfig,
        requestMessages,
        runtime.modelId,
        0.3,
        maxOutputTokens
      )
      if (!result.success) {
        console.error('SubAgentService',
          `[${session.name}] compaction summary failed: ${result.errorMessage}`)
        return ''
      }
      // 压缩摘要同样是一次真实的模型调用，必须计入本轮账单。
      // 走和子智能体正常轮次一样的 onUsage 回调，汇总到主消息的用量统计里。
      const usage = result.usage
      runtime.onUsage(
        usage !== null ? usage.prompt_tokens : estimatedInput,
        usage !== null ? usage.completion_tokens : estimateTextTokens(result.content),
        usage !== null,
        usage !== null ? (usage.cache_read_tokens ?? 0) : 0,
        usage !== null ? (usage.cache_write_tokens ?? 0) : 0
      )
      return result.content.trim()
    } catch (error) {
      console.error('SubAgentService',
        `[${session.name}] compaction summary error: ${JSON.stringify(error)}`)
      return ''
    }
  }

  // 每一轮请求前自检：超过阈值就地压缩自己的 messages，压不动时如实返回 false，
  // 让调用方继续把这一轮发出去，而不是静默停住。
  private async compactSessionIfNeeded(
    runtime: SubAgentRuntimeConfig,
    session: SubAgentSession,
    isCancelled: () => boolean
  ): Promise<boolean> {
    const compactionService = getContextCompactionService()
    await compactionService.ensurePreferencesLoaded()
    if (!compactionService.isEnabled() || runtime.contextWindowTokens <= 0) {
      return false
    }
    // 上次压缩失败后，没有新消息进来就不再重复发摘要请求
    if (session.compactionFailedAtMessageCount === session.messages.length) {
      return false
    }

    const estimatedInput = session.apiService.estimateRequestInputTokens(
      runtime.apiConfig,
      session.messages,
      runtime.modelId,
      runtime.reasoningLevel,
      session.tools.length > 0 ? session.tools : undefined,
      true
    )
    const usage = buildContextUsageFromRequestTokens(
      estimatedInput,
      runtime.contextWindowTokens,
      runtime.maxTokens,
      compactionService.getThresholdPercent()
    )
    if (!usage.overThreshold) {
      return false
    }

    const startIndex = this.resolveConversationStartIndex(session.messages)
    const splitIndex = this.resolveSafeSplitIndex(session.messages, startIndex)
    if (splitIndex <= startIndex) {
      console.warn('SubAgentService',
        `[${session.name}] over context threshold but nothing older is safe to compact`)
      session.compactionFailedAtMessageCount = session.messages.length
      return false
    }

    const originalMessageCount = session.messages.length
    const droppedMessages = session.messages.slice(startIndex, splitIndex)
    const droppedTokens = session.apiService.estimateRequestInputTokens(
      runtime.apiConfig,
      droppedMessages,
      runtime.modelId,
      ReasoningLevel.OFF
    )
    if (droppedTokens < SubAgentService.COMPACT_MIN_DROPPED_TOKENS) {
      console.warn('SubAgentService',
        `[${session.name}] over context threshold but only ${droppedTokens} tokens are compactable; ` +
          'the recent tool results alone fill the window')
      session.compactionFailedAtMessageCount = session.messages.length
      return false
    }
    console.info('SubAgentService',
      `[${session.name}] context ${usage.percent}% >= ${usage.thresholdPercent}%, ` +
        `compacting ${droppedMessages.length} messages`)
    session.liveState.liveContent += `\n\n—— 上下文达到 ${usage.percent}%，正在压缩较早的工作记录 ——\n\n`

    const summary = await this.requestSubAgentSummary(runtime, session, droppedMessages)
    if (isCancelled()) {
      return false
    }
    if (summary.length < MIN_COMPACT_SUMMARY_LENGTH) {
      console.warn('SubAgentService', `[${session.name}] compaction produced no usable summary`)
      session.compactionFailedAtMessageCount = session.messages.length
      return false
    }

    const summaryMessage = new RequestMessage('system',
      ContextCompactionService.buildSummaryRequestPrompt(summary, runtime.promptLanguage))
    // 摘要反而比被它替换掉的原文还大时，压缩是净亏损：原文丢了，窗口没省下来
    const summaryTokens = estimateTextTokens(summaryMessage.content)
    if (summaryTokens >= droppedTokens) {
      console.warn('SubAgentService',
        `[${session.name}] compaction abandoned: summary ${summaryTokens} tokens ` +
          `is not smaller than the ${droppedTokens} tokens it would replace`)
      session.compactionFailedAtMessageCount = session.messages.length
      return false
    }
    const rebuilt: RequestMessage[] = []
    const existingSummaryIndex = this.findExistingSummaryIndex(session.messages)
    for (let i = 0; i < startIndex; i++) {
      // 旧摘要被本次摘要取代：新摘要是在包含旧摘要的历史上生成的，留着只会重复占地方
      if (i === existingSummaryIndex) {
        continue
      }
      rebuilt.push(session.messages[i])
    }
    rebuilt.push(summaryMessage)
    for (let i = splitIndex; i < session.messages.length; i++) {
      rebuilt.push(session.messages[i])
    }
    session.messages.splice(0, session.messages.length)
    for (let i = 0; i < rebuilt.length; i++) {
      session.messages.push(rebuilt[i])
    }
    session.compactCount += 1
    session.compactionFailedAtMessageCount = -1
    console.info('SubAgentService',
      `[${session.name}] compaction #${session.compactCount} done: ` +
        `messages ${originalMessageCount}->${rebuilt.length}`)
    return true
  }

  // 单轮流式请求：聚合内容与工具调用，Promise 化回调接口
  private performStreamRound(
    runtime: SubAgentRuntimeConfig,
    apiService: AIApiService,
    messages: RequestMessage[],
    tools: ToolDefinition[],
    onContentChunk: (chunk: string) => void,
    isCancelled: () => boolean
  ): Promise<SubAgentRoundOutcome> {
    return new Promise<SubAgentRoundOutcome>((resolve) => {
      const outcome = new SubAgentRoundOutcome()
      let settled = false
      let cancelHandled = false
      let contentBuffer = ''
      let actualInputTokens = -1
      let actualOutputTokens = -1
      let actualCacheReadTokens = 0
      let actualCacheWriteTokens = 0
      let httpRequest: http.HttpRequest | null = null
      const estimatedInputTokens = apiService.estimateRequestInputTokens(
        runtime.apiConfig,
        messages,
        runtime.modelId,
        runtime.reasoningLevel,
        tools.length > 0 ? tools : undefined,
        true
      )
      const safeMaxOutputTokens = resolveRequestMaxOutputTokens(
        runtime.maxTokens,
        runtime.contextWindowTokens,
        estimatedInputTokens
      )

      const settle = (): void => {
        if (settled) {
          return
        }
        settled = true
        let estimatedOutputTokens = estimateTextTokens(outcome.content) + estimateTextTokens(outcome.reasoningContent)
        for (let i = 0; i < outcome.toolCalls.length; i++) {
          estimatedOutputTokens += estimateTextTokens(outcome.toolCalls[i].functionName)
          estimatedOutputTokens += estimateTextTokens(outcome.toolCalls[i].arguments)
        }
        runtime.onUsage(
          actualInputTokens >= 0 ? actualInputTokens : estimatedInputTokens,
          actualOutputTokens >= 0 ? actualOutputTokens : estimatedOutputTokens,
          actualInputTokens >= 0 && actualOutputTokens >= 0,
          actualCacheReadTokens,
          actualCacheWriteTokens
        )
        resolve(outcome)
      }

      httpRequest = apiService.streamChatRequestWithTools(
        runtime.apiConfig,
        messages,
        runtime.modelId,
        (contentChunk: string) => {
          contentBuffer += contentChunk
          onContentChunk(contentChunk)
          if (!cancelHandled && isCancelled() && httpRequest !== null) {
            cancelHandled = true
            try {
              httpRequest.destroy()
            } catch (error) {
              console.warn('SubAgentService', `Failed to destroy cancelled stream: ${JSON.stringify(error)}`)
            }
          }
        },
        (toolCalls: ToolCall[]) => {
          outcome.content = contentBuffer
          outcome.toolCalls = toolCalls
          settle()
        },
        (error: string) => {
          outcome.content = contentBuffer
          outcome.error = error !== '' ? error : '请求失败'
          settle()
        },
        runtime.temperature,
        safeMaxOutputTokens,
        (reasoningChunk: string): void => {
          outcome.reasoningContent += reasoningChunk
        },
        undefined,
        runtime.reasoningLevel,
        tools.length > 0 ? tools : undefined,
        tools.length > 0 ? 'auto' : 'none',
        undefined,
        (usage: UsageInfo): void => {
          actualInputTokens = Math.max(actualInputTokens, usage.prompt_tokens)
          actualOutputTokens = Math.max(actualOutputTokens, usage.completion_tokens)
          actualCacheReadTokens = Math.max(actualCacheReadTokens, usage.cache_read_tokens ?? 0)
          actualCacheWriteTokens = Math.max(actualCacheWriteTokens, usage.cache_write_tokens ?? 0)
        }
      )
    })
  }

  // toolRunner 抛出时不能让整个子智能体崩掉，转成一条错误工具结果继续下一轮
  private async runToolCallSafely(
    runtime: SubAgentRuntimeConfig,
    toolCall: ToolCall,
    allowedFunctionNames: string[],
    budgetKey: string,
    executionContext: ToolExecutionContext
  ): Promise<ToolResult> {
    try {
      return await runtime.toolRunner(toolCall, allowedFunctionNames, budgetKey, executionContext)
    } catch (error) {
      console.error('SubAgentService', `Sub-agent tool execution failed: ${JSON.stringify(error)}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify(new SubAgentErrorResponse(`工具执行失败: ${JSON.stringify(error)}`)),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }
  }
}

export function getSubAgentService(): SubAgentService {
  return SubAgentService.getInstance()
}
