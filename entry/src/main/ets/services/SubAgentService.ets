import { http } from '@kit.NetworkKit'
import { AIApiConfig, AIApiService, RequestMessage, UsageInfo } from './AIApiService'
import { ReasoningLevel, ToolCall, ToolDefinition, ToolResult } from '../models/ChatModels'
import { createThrottle } from '../utils/ThrottleUtil'
import { estimateTextTokens } from '../utils/ModelBillingUtils'
import {
  hasFiniteRetrievalCallLimit,
  UNLIMITED_RETRIEVAL_CALL_LIMIT
} from '../config/RetrievalCallLimit'
import { resolveRequestMaxOutputTokens } from '../utils/ContextWindowUtils'

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
  budgetKey: string
) => Promise<ToolResult>

// 子智能体工具调用镜像回调：把子智能体的工具调用/结果同步进主对话的 AI 消息，
// 让 ask_user 弹窗/结果栏、图表、Canvas、日程等交互式工具对用户可见
export type SubAgentToolCallStarted = (toolCall: ToolCall) => void
export type SubAgentToolCallCompleted = (toolCall: ToolCall, toolResult: ToolResult) => void
export type SubAgentUsageCallback = (inputTokens: number, outputTokens: number, exact: boolean) => void

// 子智能体运行时配置，由 ChatViewModel 在每次带工具的请求开始前注入
export class SubAgentRuntimeConfig {
  apiConfig: AIApiConfig
  modelId: string
  temperature: number
  maxTokens: number
  reasoningLevel: ReasoningLevel
  tools: ToolDefinition[]
  timeContext: string
  toolRunner: SubAgentToolRunner
  onToolCallStarted: SubAgentToolCallStarted
  onToolCallCompleted: SubAgentToolCallCompleted
  isCancelled: () => boolean
  onUsage: SubAgentUsageCallback
  contextWindowTokens: number
  webSearchCallLimit: number
  knowledgeSearchCallLimit: number

  constructor(
    apiConfig: AIApiConfig,
    modelId: string,
    temperature: number,
    maxTokens: number,
    reasoningLevel: ReasoningLevel,
    tools: ToolDefinition[],
    timeContext: string,
    toolRunner: SubAgentToolRunner,
    onToolCallStarted: SubAgentToolCallStarted,
    onToolCallCompleted: SubAgentToolCallCompleted,
    isCancelled: () => boolean,
    onUsage: SubAgentUsageCallback,
    contextWindowTokens: number = 0,
    webSearchCallLimit: number = UNLIMITED_RETRIEVAL_CALL_LIMIT,
    knowledgeSearchCallLimit: number = UNLIMITED_RETRIEVAL_CALL_LIMIT
  ) {
    this.apiConfig = apiConfig
    this.modelId = modelId
    this.temperature = temperature
    this.maxTokens = maxTokens
    this.reasoningLevel = reasoningLevel
    this.tools = tools
    this.timeContext = timeContext
    this.toolRunner = toolRunner
    this.onToolCallStarted = onToolCallStarted
    this.onToolCallCompleted = onToolCallCompleted
    this.isCancelled = isCancelled
    this.onUsage = onUsage
    this.contextWindowTokens = contextWindowTokens
    this.webSearchCallLimit = webSearchCallLimit
    this.knowledgeSearchCallLimit = knowledgeSearchCallLimit
  }
}

// sub_agent 工具入参
interface SubAgentTaskArgs {
  name?: string
  prompt?: string
  expected_output?: string
}

interface SubAgentToolArgs {
  main_thread_work?: string
  tasks?: SubAgentTaskArgs[]
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
  nextAction: string = 'quality_gate_then_follow_up_or_finalize'
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

    let parsedArgs: SubAgentToolArgs = {}
    try {
      parsedArgs = JSON.parse(argsJson) as SubAgentToolArgs
    } catch (_error) {
      return JSON.stringify(new SubAgentErrorResponse('sub_agent 参数不是合法 JSON'))
    }

    const rawTasks = parsedArgs.tasks
    if (rawTasks === undefined || rawTasks.length === 0) {
      return JSON.stringify(new SubAgentErrorResponse('sub_agent 需要 1-3 个 tasks，每个任务必须包含自包含的 prompt'))
    }

    const tasks: SubAgentTaskArgs[] = []
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
      note = `一次最多派出 ${SUB_AGENT_MAX_TASKS} 个子智能体，多余任务已忽略；如有需要请在后续轮次继续派出。`
    }
    const batch = this.registerBatch(dispatchedSessions, pendingReports, note)
    console.info('SubAgentService', `Dispatching ${tasks.length} sub-agent(s) as ${batch.id}`)

    const response = new SubAgentDispatchResponse()
    response.batchId = batch.id
    response.mainThreadWork = mainThreadWork
    response.agents = taskNames
    response.sessions = this.buildSessionDescriptors(dispatchedSessions)
    response.note = `已派出 ${tasks.length} 个子智能体，它们正在后台运行。` +
      '下一步不是收取结果：禁止紧接着调用 sub_agent_result（wait=true/false 均不应）。' +
      `请立即完成你承诺的主线程交付物：“${mainThreadWork}”。` +
      '只有该交付物已完成且主线程已无可独立推进的工作时才允许收取。' +
      `收取后会话不会关闭，可用 sessions 中的 agentId 调用 sub_agent_message 继续引导。${note}`
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
    if (mainThreadWork === '') {
      return JSON.stringify(new SubAgentErrorResponse(
        'sub_agent_message 必须提供非空 main_thread_work，明确续发后主线程要先完成的具体交付物'
      ))
    }

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
    response.note = `已向 ${targetSessions.length} 个子智能体续发消息，它们正在沿用原有上下文生成新回复。` +
      `不要立即阻塞收取或查看进度；先完成你承诺的主线程交付物：“${mainThreadWork}”。` +
      '之后用 sub_agent_result 收取本轮 batch，并再次执行质量门；主从对话轮数不设上限。'
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
    response.note = (response.note !== '' ? response.note + ' ' : '') +
      '立即执行质量门：逐项检查目标覆盖、事实/证据、约束、内部一致性与格式。' +
      '若有可修正的实质缺口，应在撰写最终回答前将结果中的 agentId 作为 agent_id 调用 ' +
      'sub_agent_message，明确指出缺口和本轮验收目标；通过质量门后再综合作答。'
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

  private resolveTaskName(task: SubAgentTaskArgs, index: number): string {
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
    return `${message}\n\n本轮期望输出格式:\n${expectedOutput}`
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
    session.messages.push(new RequestMessage('user', userMessage))
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

      report.rounds += 1
      session.totalRounds += 1
      live.rounds = session.totalRounds
      console.info(
        'SubAgentService',
        `[${report.name}] conversation ${report.conversationTurn}, model round ${report.rounds}`
      )
      const outcome = await this.performStreamRound(
        runtime,
        session.apiService,
        session.messages,
        session.tools,
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

      if (outcome.toolCalls.length === 0) {
        report.status = SUB_AGENT_STATUS_COMPLETED
        report.result = outcome.content !== '' ? outcome.content : '(子智能体没有输出内容)'
        session.messages.push(new RequestMessage('assistant', outcome.content))
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
      session.messages.push(assistantMsg)
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
          session.budgetKey
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

  private buildSubAgentSystemPrompt(
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
    return `当前时间: ${runtime.timeContext}

你是主助手派出的子智能体「${agentName}」，负责独立完成一个明确的子任务。

执行规则:
- 你与主助手之间是可持续多轮的协作会话。每次回复都会作为工具结果返回给主助手；主助手之后可能继续追问、纠正方向或要求深化，你必须结合此前完整上下文继续工作。
- 每一轮都应输出简洁、结构化、信息完整的阶段回复；不要因为可能有下一轮而省略当前已能完成的内容。
- 请自主完成任务；确实需要外部信息或外部系统时，使用提供的工具。
${askUserRule}
${webSearchRule}
${knowledgeSearchRule}
- 引用外部信息时保留关键来源（标题/URL），方便主助手复核。
- 本轮任务完成后直接输出结果，不要输出与任务无关的寒暄。
- 每轮回复末尾附上简短“交付自检”：标明完成度（complete/partial/blocked）、仍缺少的证据或风险（没有则写“无”），以及主助手下一轮最值得追问的一个点（无需追问则写“无”）。不要虚报完成度。`
  }

  private buildSubAgentTaskPrompt(task: SubAgentTaskArgs): string {
    const prompt = task.prompt !== undefined ? task.prompt.trim() : ''
    const expectedOutput = task.expected_output !== undefined ? task.expected_output.trim() : ''
    if (expectedOutput === '') {
      return prompt
    }
    return `${prompt}\n\n期望输出格式:\n${expectedOutput}`
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
        let estimatedOutputTokens = estimateTextTokens(outcome.content)
        for (let i = 0; i < outcome.toolCalls.length; i++) {
          estimatedOutputTokens += estimateTextTokens(outcome.toolCalls[i].functionName)
          estimatedOutputTokens += estimateTextTokens(outcome.toolCalls[i].arguments)
        }
        runtime.onUsage(
          actualInputTokens >= 0 ? actualInputTokens : estimatedInputTokens,
          actualOutputTokens >= 0 ? actualOutputTokens : estimatedOutputTokens,
          actualInputTokens >= 0 && actualOutputTokens >= 0
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
        undefined,
        undefined,
        runtime.reasoningLevel,
        tools.length > 0 ? tools : undefined,
        tools.length > 0 ? 'auto' : 'none',
        undefined,
        (usage: UsageInfo): void => {
          actualInputTokens = Math.max(actualInputTokens, usage.prompt_tokens)
          actualOutputTokens = Math.max(actualOutputTokens, usage.completion_tokens)
        }
      )
    })
  }

  // toolRunner 抛出时不能让整个子智能体崩掉，转成一条错误工具结果继续下一轮
  private async runToolCallSafely(
    runtime: SubAgentRuntimeConfig,
    toolCall: ToolCall,
    allowedFunctionNames: string[],
    budgetKey: string
  ): Promise<ToolResult> {
    try {
      return await runtime.toolRunner(toolCall, allowedFunctionNames, budgetKey)
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
