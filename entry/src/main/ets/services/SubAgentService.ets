import { http } from '@kit.NetworkKit'
import { AIApiConfig, AIApiService, RequestMessage } from './AIApiService'
import { ReasoningLevel, ToolCall, ToolDefinition, ToolResult } from '../models/ChatModels'
import { createThrottle } from '../utils/ThrottleUtil'

export const SUB_AGENT_TOOL_ID: string = 'sub_agent'

// sub_agent 的配套收取工具。sub_agent 只负责派发并立即返回，主智能体继续自己的工具
// 循环，需要子智能体产出时再调用它取回结果。随 sub_agent 一起曝光，不单独出现在工具面板。
export const SUB_AGENT_RESULT_TOOL_ID: string = 'sub_agent_result'

// 子智能体发起的工具调用统一使用该来源标签前缀，
// UI 依赖它识别调用来源（例如主对话中不渲染子智能体的工具卡片）
export const SUB_AGENT_SOURCE_LABEL_PREFIX: string = '子智能体 · '

// 单次 sub_agent 调用允许并行派出的子智能体上限
export const SUB_AGENT_MAX_TASKS = 3

// 子智能体继承本次对话已经曝光的工具。只禁止 sub_agent 与 sub_agent_result，
// 避免递归派生和子智能体去收取同级批次；knowledge_search 是否存在完全由主请求
// 的知识库开关与曝光策略决定。
export function buildSubAgentToolSet(tools: ToolDefinition[]): ToolDefinition[] {
  const result: ToolDefinition[] = []
  for (let i = 0; i < tools.length; i++) {
    const functionName = tools[i].function.name
    if (functionName === SUB_AGENT_TOOL_ID || functionName === SUB_AGENT_RESULT_TOOL_ID) {
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
    isCancelled: () => boolean
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
  }
}

// sub_agent 工具入参
interface SubAgentTaskArgs {
  name?: string
  prompt?: string
  expected_output?: string
}

interface SubAgentToolArgs {
  tasks?: SubAgentTaskArgs[]
}

// sub_agent_result 工具入参
interface SubAgentResultToolArgs {
  batch_id?: string
  wait?: boolean
}

// 单个子智能体的执行报告（序列化后回传给主智能体）
class SubAgentTaskReport {
  name: string = ''
  status: string = ''
  result: string = ''
  rounds: number = 0
  toolCallCount: number = 0
}

// sub_agent 的返回：只确认派发，不含结果
class SubAgentDispatchResponse {
  status: string = 'dispatched'
  batchId: string = ''
  agents: string[] = []
  note: string = ''
}

// sub_agent_result（wait=true）的返回：汇总一个或多个批次的最终报告
class SubAgentCollectResponse {
  status: string = 'completed'
  batchIds: string[] = []
  results: SubAgentTaskReport[] = []
  note: string = ''
}

// sub_agent_result（wait=false）的返回：只报进度，不阻塞
class SubAgentProgressItem {
  batchId: string = ''
  name: string = ''
  status: string = ''
  rounds: number = 0
  toolCallCount: number = 0
}

class SubAgentProgressResponse {
  status: string = 'running'
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
  @Trace name: string = ''
  @Trace promptPreview: string = ''
  @Trace status: string = SUB_AGENT_STATUS_RUNNING
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

// 一次 sub_agent 派发出去的批次句柄：pending 是后台运行的汇总 Promise，
// 主智能体调用 sub_agent_result 时才 await 它
class SubAgentBatch {
  id: string
  taskNames: string[]
  liveStates: SubAgentLiveState[]
  pending: Promise<SubAgentTaskReport[]>
  note: string
  settled: boolean = false
  collected: boolean = false

  constructor(
    id: string,
    taskNames: string[],
    liveStates: SubAgentLiveState[],
    pending: Promise<SubAgentTaskReport[]>,
    note: string
  ) {
    this.id = id
    this.taskNames = taskNames
    this.liveStates = liveStates
    this.pending = pending
    this.note = note
  }
}

// 主智能体结束本轮却没有收取子智能体结果时的兜底回灌次数上限，
// 防止“派发 → 结束 → 回灌 → 再派发”无限循环
const SUB_AGENT_MAX_AUTO_COLLECT_ROUNDS: number = 3

// 子智能体服务：主智能体通过 sub_agent 工具一次派出 1-3 个子智能体并行处理子任务。
// 每个子智能体拥有独立的对话上下文和不限轮次的工具调用循环。
// sub_agent 只负责派发并立即返回 batch_id，子智能体在后台继续运行，主智能体因此
// 可以在同一轮请求里继续做自己的工作；需要产出时再调用 sub_agent_result 收取。
export class SubAgentService {
  private static instance: SubAgentService | null = null
  private runtime: SubAgentRuntimeConfig | null = null
  // 实时预览状态：始终保留最近一批子智能体的运行情况
  private previewState: SubAgentPreviewState = new SubAgentPreviewState()
  // 子智能体全局序号，用于给工具调用 id 加唯一后缀
  private agentSequence: number = 0
  // 本次请求已派发、尚未（或已经）收取的批次，按派发顺序保存
  private batches: Map<string, SubAgentBatch> = new Map()
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
    this.autoCollectRounds = 0
  }

  clearRuntime(): void {
    this.generation += 1
    this.runtime = null
    this.batches.clear()
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

    this.batchSequence += 1
    const batchId = `batch_${this.batchSequence}`
    console.info('SubAgentService', `Dispatching ${tasks.length} sub-agent(s) as ${batchId}`)

    // 上一批已全部结束时重置预览列表；批次重叠时追加，避免互相覆盖
    const mergedAgents: SubAgentLiveState[] = []
    if (this.hasRunningBatch()) {
      for (let i = 0; i < this.previewState.agents.length; i++) {
        mergedAgents.push(this.previewState.agents[i])
      }
    }
    const liveStates: SubAgentLiveState[] = []
    const taskNames: string[] = []
    for (let i = 0; i < tasks.length; i++) {
      const live = new SubAgentLiveState()
      live.name = this.resolveTaskName(tasks[i], i)
      const taskPrompt = tasks[i].prompt
      live.promptPreview = this.truncateForPreview(taskPrompt !== undefined ? taskPrompt : '', 200)
      liveStates.push(live)
      taskNames.push(live.name)
      mergedAgents.push(live)
    }
    this.previewState.agents = mergedAgents
    this.previewState.active = true
    this.previewState.hasEverRun = true

    const pendingReports: Promise<SubAgentTaskReport>[] = []
    for (let i = 0; i < tasks.length; i++) {
      pendingReports.push(this.runSingleSubAgent(runtime, tasks[i], liveStates[i]))
    }
    // 兜底成失败报告，保证 pending 永不 reject —— 它会被 sub_agent_result 延后 await，
    // 未处理的 rejection 在这段时间里没有任何接收方
    const pending: Promise<SubAgentTaskReport[]> = Promise.all(pendingReports)
      .catch((error: Object): SubAgentTaskReport[] => {
        console.error('SubAgentService', `Sub-agent batch ${batchId} failed: ${JSON.stringify(error)}`)
        const failedReports: SubAgentTaskReport[] = []
        for (let i = 0; i < taskNames.length; i++) {
          const failed = new SubAgentTaskReport()
          failed.name = taskNames[i]
          failed.status = SUB_AGENT_STATUS_FAILED
          failed.result = `子智能体执行异常: ${JSON.stringify(error)}`
          failedReports.push(failed)
        }
        return failedReports
      })

    let note = ''
    if (rawTasks.length > SUB_AGENT_MAX_TASKS) {
      note = `一次最多派出 ${SUB_AGENT_MAX_TASKS} 个子智能体，多余任务已忽略；如有需要请在后续轮次继续派出。`
    }
    const batch = new SubAgentBatch(batchId, taskNames, liveStates, pending, note)
    this.batches.set(batchId, batch)
    pending.then((): void => {
      batch.settled = true
      this.refreshPreviewActive()
    })

    const response = new SubAgentDispatchResponse()
    response.batchId = batchId
    response.agents = taskNames
    response.note = `已派出 ${tasks.length} 个子智能体，它们正在后台运行。` +
      '不要空等：请立刻继续处理你自己那部分工作（调用其它工具、整理已有信息、起草回答框架）。' +
      `需要它们的产出时调用 sub_agent_result 收取（默认等待全部完成；传 wait=false 只查看进度）。${note}`
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
          : '当前没有待收取的子智能体批次，请先调用 sub_agent 派发任务'
      ))
    }

    if (!shouldWait) {
      return JSON.stringify(this.buildProgressResponse(targets))
    }

    const response = new SubAgentCollectResponse()
    for (let i = 0; i < targets.length; i++) {
      const batch = targets[i]
      const reports = await batch.pending
      batch.settled = true
      batch.collected = true
      response.batchIds.push(batch.id)
      for (let j = 0; j < reports.length; j++) {
        response.results.push(reports[j])
      }
      if (batch.note !== '') {
        response.note = batch.note
      }
    }
    this.refreshPreviewActive()

    const runtime = this.runtime
    if (runtime !== null && runtime.isCancelled()) {
      return JSON.stringify(new SubAgentErrorResponse('子智能体执行已取消', true))
    }
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
      for (let j = 0; j < batch.liveStates.length; j++) {
        const live = batch.liveStates[j]
        const item = new SubAgentProgressItem()
        item.batchId = batch.id
        item.name = live.name
        item.status = live.status
        item.rounds = live.rounds
        item.toolCallCount = live.toolEvents.length
        response.agents.push(item)
      }
    }
    response.status = allSettled ? 'ready' : SUB_AGENT_STATUS_RUNNING
    response.note = allSettled
      ? '子智能体已全部结束，再次调用 sub_agent_result（省略 wait 或传 wait=true）即可取回完整结果。'
      : '子智能体仍在运行。请继续处理你自己那部分工作，稍后再调用 sub_agent_result 取回结果。'
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

  // 运行单个子智能体：独立上下文 + 不限轮次的工具调用循环
  private async runSingleSubAgent(
    runtime: SubAgentRuntimeConfig,
    task: SubAgentTaskArgs,
    live: SubAgentLiveState
  ): Promise<SubAgentTaskReport> {
    const report = new SubAgentTaskReport()
    report.name = live.name
    // 每个子智能体分配唯一序号，用于给工具调用 id 加后缀，
    // 避免并行子智能体各自的流生成相同 id（如 call_0）导致镜像卡片与 ask_user 应答串线
    this.agentSequence += 1
    const agentSeq = this.agentSequence
    const budgetKey = `sub-agent-${agentSeq}`
    // 子智能体现在会活过派发它的那次工具调用，必须同时盯住运行时代号：
    // 请求正常结束或出错时 clearRuntime() 递增代号，后台子智能体据此自行退出
    const myGeneration = this.generation
    const isCancelled = (): boolean => runtime.isCancelled() || this.generation !== myGeneration

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
        report.name,
        hasAskUserTool,
        hasKnowledgeSearchTool,
        hasWebSearchTool
      )
    ))
    messages.push(new RequestMessage('user', this.buildSubAgentTaskPrompt(task)))

    // 每个子智能体独享一个 AIApiService 实例，避免并发流式解析状态互相污染
    const apiService = AIApiService.createIsolated()
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
        return report
      }

      report.rounds += 1
      live.rounds = report.rounds
      console.info('SubAgentService', `[${report.name}] round ${report.rounds}`)
      const outcome = await this.performStreamRound(
        runtime,
        apiService,
        messages,
        agentTools,
        appendLiveContent,
        isCancelled
      )
      flushLiveContent()

      if (isCancelled()) {
        report.status = SUB_AGENT_STATUS_CANCELLED
        report.result = '任务被用户取消'
        live.status = SUB_AGENT_STATUS_CANCELLED
        return report
      }

      if (outcome.error !== '') {
        report.status = SUB_AGENT_STATUS_FAILED
        report.result = outcome.content !== ''
          ? `请求失败: ${outcome.error}\n\n失败前的部分输出:\n${outcome.content}`
          : `请求失败: ${outcome.error}`
        live.status = SUB_AGENT_STATUS_FAILED
        return report
      }

      if (outcome.toolCalls.length === 0) {
        report.status = SUB_AGENT_STATUS_COMPLETED
        report.result = outcome.content !== '' ? outcome.content : '(子智能体没有输出内容)'
        live.status = SUB_AGENT_STATUS_COMPLETED
        return report
      }

      // 工具调用 id 加子智能体后缀保证全局唯一；随后构建的 assistant/tool 消息
      // 使用同一批对象，改写后的 id 在续轮请求里保持一致
      for (let i = 0; i < outcome.toolCalls.length; i++) {
        outcome.toolCalls[i].id = `${outcome.toolCalls[i].id}_sa${agentSeq}`
      }

      // 执行工具调用并把结果拼回上下文，继续下一轮
      const assistantMsg = RequestMessage.createAssistantWithToolCalls(outcome.content, outcome.toolCalls)
      messages.push(assistantMsg)
      for (let i = 0; i < outcome.toolCalls.length; i++) {
        report.toolCallCount += 1
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
        const toolResult = await this.runToolCallSafely(runtime, toolCall, allowedFunctionNames, budgetKey)

        // executeToolCall 会把注册表里的显示名回填到 toolCall 上
        toolEvent.displayName = toolCall.displayName !== '' ? toolCall.displayName : toolCall.functionName
        toolEvent.status = toolResult.isError ? SUB_AGENT_TOOL_EVENT_ERROR : SUB_AGENT_TOOL_EVENT_OK
        toolEvent.resultPreview = this.truncateForPreview(toolResult.content, 400)
        runtime.onToolCallCompleted(toolCall, toolResult)
        console.info(
          'SubAgentService',
          `[${report.name}] tool ${toolCall.functionName} -> ${toolResult.isError ? 'error' : 'ok'}`
        )
        messages.push(RequestMessage.createToolResultMessage(toolResult.toolCallId, toolResult.content))
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
      ? '- 本次对话已开启知识库，你可调用 knowledge_search 检索用户文件。你拥有独立的每次用户提问最多 5 次知识库查询额度，不与主助手或其他子智能体共享；工具返回额度耗尽后立即停止检索。'
      : ''
    const webSearchRule = hasWebSearch
      ? '- 你拥有独立的默认 5 次 web_search 额度，不与主助手或其他子智能体共享。默认额度用完后，仅在确有必要且 ask_user 可用时请求用户允许追加搜索；否则基于已有结果完成报告。'
      : ''
    return `当前时间: ${runtime.timeContext}

你是主助手派出的子智能体「${agentName}」，负责独立完成一个明确的子任务。

执行规则:
- 你的最终输出会作为工具结果返回给主助手，而不是直接展示给用户，请输出简洁、结构化、信息完整的结果报告。
- 请自主完成任务；确实需要外部信息或外部系统时，使用提供的工具。
${askUserRule}
${webSearchRule}
${knowledgeSearchRule}
- 引用外部信息时保留关键来源（标题/URL），方便主助手复核。
- 任务完成后直接输出最终结果，不要输出与任务无关的寒暄。`
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
      let httpRequest: http.HttpRequest | null = null

      const settle = (): void => {
        if (settled) {
          return
        }
        settled = true
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
        runtime.maxTokens,
        undefined,
        undefined,
        runtime.reasoningLevel,
        tools.length > 0 ? tools : undefined,
        tools.length > 0 ? 'auto' : 'none'
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
