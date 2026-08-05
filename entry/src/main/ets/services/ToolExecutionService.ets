import { ToolCall, ToolResult } from '../models/ChatModels'
import { ASK_USER_TOOL_ID } from '../config/BuiltinTools'
import { getToolRegistry, RegisteredTool, ToolRegistry } from './ToolRegistry'

// 取消检查回调类型
type CancelCheckCallback = () => boolean
type ToolApprovalCallback = (toolCall: ToolCall, tool: RegisteredTool) => Promise<ToolApprovalResult>

export enum ToolApprovalStatus {
  APPROVED = 'approved',
  REJECTED = 'rejected',
  CANCELLED = 'cancelled',
  UNAVAILABLE = 'unavailable'
}

export class ToolApprovalResult {
  status: string = ToolApprovalStatus.CANCELLED
  message: string = ''

  constructor(status: string = ToolApprovalStatus.CANCELLED, message: string = '') {
    this.status = status
    this.message = message
  }

  static approve(): ToolApprovalResult {
    return new ToolApprovalResult(ToolApprovalStatus.APPROVED)
  }

  static reject(message: string = ''): ToolApprovalResult {
    return new ToolApprovalResult(ToolApprovalStatus.REJECTED, message)
  }

  static cancel(message: string = ''): ToolApprovalResult {
    return new ToolApprovalResult(ToolApprovalStatus.CANCELLED, message)
  }

  static unavailable(message: string = ''): ToolApprovalResult {
    return new ToolApprovalResult(ToolApprovalStatus.UNAVAILABLE, message)
  }
}

interface WebSearchPaginationArgs {
  query?: string
  q?: string
  keywords?: string
  url?: string
  page?: number
}

class PendingAskUserRuntime {
  resolve: (answerJson: string | null) => void
  toolCall: ToolCall

  constructor(resolve: (answerJson: string | null) => void, toolCall: ToolCall) {
    this.resolve = resolve
    this.toolCall = toolCall
  }
}

export type PendingAskUserChangedCallback = () => void

// 工具执行服务 - 负责执行工具调用
export class ToolExecutionService {
  private static instance: ToolExecutionService | null = null
  private registry: ToolRegistry
  // 当前取消检查回调
  private cancelCheckCallback: CancelCheckCallback | null = null
  private approvalCallback: ToolApprovalCallback | null = null
  private pendingAskUserAnswers: Map<string, PendingAskUserRuntime> = new Map()
  private pendingAskUserChangedCallback: PendingAskUserChangedCallback | null = null
  private webSearchQueryCounts: Map<string, number> = new Map()
  // 全局工具互斥链：sub_agent 改为异步派发后，主智能体与后台子智能体会同时执行工具，
  // 必须共用同一把锁来维持应用内“同一时刻只执行一个工具”的约定
  // （避免审批弹窗并发弹出、Pyodide WebView 并发执行等问题）
  private exclusiveChain: Promise<void> = Promise.resolve()

  private constructor() {
    this.registry = getToolRegistry()
  }

  static getInstance(): ToolExecutionService {
    if (ToolExecutionService.instance === null) {
      ToolExecutionService.instance = new ToolExecutionService()
    }
    return ToolExecutionService.instance
  }

  // 设置取消检查回调
  setCancelCheckCallback(callback: CancelCheckCallback | null): void {
    this.cancelCheckCallback = callback
  }

  // 清除取消检查回调
  clearCancelCheckCallback(): void {
    this.cancelCheckCallback = null
  }

  setApprovalCallback(callback: ToolApprovalCallback | null): void {
    this.approvalCallback = callback
  }

  setPendingAskUserChangedCallback(callback: PendingAskUserChangedCallback | null): void {
    this.pendingAskUserChangedCallback = callback
  }

  getPendingAskUserToolCalls(): ToolCall[] {
    const calls: ToolCall[] = []
    this.pendingAskUserAnswers.forEach((runtime: PendingAskUserRuntime) => {
      calls.push(runtime.toolCall)
    })
    return calls
  }

  promotePendingAskUserAnswer(toolCallId: string): boolean {
    const runtime = this.pendingAskUserAnswers.get(toolCallId)
    if (runtime === undefined) {
      return false
    }
    this.pendingAskUserAnswers.delete(toolCallId)
    this.pendingAskUserAnswers.set(toolCallId, runtime)
    this.notifyPendingAskUserChanged()
    return true
  }

  private notifyPendingAskUserChanged(): void {
    if (this.pendingAskUserChangedCallback !== null) {
      this.pendingAskUserChangedCallback()
    }
  }

  resolvePendingAskUserAnswer(toolCallId: string, answerJson: string | null): boolean {
    const runtime = this.pendingAskUserAnswers.get(toolCallId)
    if (runtime === undefined) {
      return false
    }
    this.pendingAskUserAnswers.delete(toolCallId)
    this.notifyPendingAskUserChanged()
    runtime.resolve(answerJson)
    return true
  }

  cancelAllPendingAskUserAnswers(): void {
    const ids: string[] = []
    this.pendingAskUserAnswers.forEach((_runtime: PendingAskUserRuntime, key: string) => {
      ids.push(key)
    })
    for (let i = 0; i < ids.length; i++) {
      this.resolvePendingAskUserAnswer(ids[i], null)
    }
  }

  resetWebSearchQueryState(): void {
    this.webSearchQueryCounts.clear()
  }

  // 在全局工具互斥锁内执行 task（简单的 promise 链）。
  // 会长时间挂起的调用（ask_user、sub_agent_result）不要走这里，否则会把锁一直占住。
  async runExclusively<T>(task: () => Promise<T>): Promise<T> {
    const previous = this.exclusiveChain
    let release: () => void = () => {}
    this.exclusiveChain = new Promise<void>((resolveLock) => {
      release = resolveLock
    })
    await previous
    try {
      return await task()
    } finally {
      release()
    }
  }

  // 检查是否已取消
  private isCancelled(): boolean {
    if (this.cancelCheckCallback !== null) {
      return this.cancelCheckCallback()
    }
    return false
  }

  private normalizeFunctionName(functionName: string): string {
    const rawName = functionName as string | null | undefined
    if (rawName === undefined || rawName === null) {
      return ''
    }
    return rawName.trim()
  }

  private resolveToolId(functionName: string): string | undefined {
    if (functionName !== '') {
      const direct = this.registry.getToolIdByFunctionName(functionName)
      if (direct !== undefined) {
        return direct
      }
    }

    const normalized = functionName.toLowerCase().replace(/[\s\-]+/g, '_')
    if ((normalized === 'exa_search' || normalized === 'websearch' || normalized === 'search_web'
      || normalized === 'internet_search' || normalized === 'web_search_exa')
      && this.registry.isToolRegistered('web_search')) {
      return 'web_search'
    }
    return undefined
  }

  private isAskUserFunctionName(functionName: string): boolean {
    const normalized = functionName.toLowerCase().replace(/[\s\-]+/g, '_')
    return normalized === ASK_USER_TOOL_ID || normalized === 'user_input' || normalized === 'ask'
  }

  private isFunctionAllowedForRound(functionName: string, allowedFunctionNames: string[]): boolean {
    let canonicalName = functionName
    if (this.isAskUserFunctionName(functionName)) {
      canonicalName = ASK_USER_TOOL_ID
    } else {
      const toolId = this.resolveToolId(functionName)
      if (toolId !== undefined) {
        const registeredTool = this.registry.getTool(toolId)
        if (registeredTool !== undefined) {
          canonicalName = registeredTool.definition.function.name
        }
      }
    }
    return allowedFunctionNames.includes(canonicalName)
  }

  private buildUnadvertisedToolResult(toolCall: ToolCall, functionName: string): ToolResult {
    const displayName = functionName !== '' ? functionName : 'unknown'
    console.warn('ToolExecutionService', `Rejected tool not advertised in this round: ${displayName}`)
    return new ToolResult(
      toolCall.id,
      JSON.stringify({
        error: '工具未在本轮提供',
        code: 'TOOL_NOT_ADVERTISED',
        functionName: displayName
      }),
      true,
      displayName,
      toolCall.sourceLabel
    )
  }

  private isWebSearchToolId(toolId: string): boolean {
    return toolId === 'web_search'
  }

  private normalizeSearchQueryKey(query: string): string {
    return query.toLowerCase().replace(/\s+/g, ' ').trim()
  }

  private resolveSearchPaginationQuery(args: WebSearchPaginationArgs): string {
    const candidates: string[] = []
    if (args.url !== undefined) {
      candidates.push(args.url)
    }
    if (args.query !== undefined) {
      candidates.push(args.query)
    }
    if (args.q !== undefined) {
      candidates.push(args.q)
    }
    if (args.keywords !== undefined) {
      candidates.push(args.keywords)
    }
    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i].trim()
      if (candidate !== '') {
        return candidate
      }
    }
    return ''
  }

  private applyWebSearchPagination(toolCall: ToolCall): void {
    let parsed: WebSearchPaginationArgs = {}
    try {
      parsed = JSON.parse(toolCall.arguments) as WebSearchPaginationArgs
    } catch (_error) {
      return
    }

    const rawQuery = this.resolveSearchPaginationQuery(parsed)
    if (rawQuery === '') {
      return
    }

    const existingPage = parsed.page
    if (typeof existingPage === 'number' && existingPage > 0) {
      return
    }

    const key = this.normalizeSearchQueryKey(rawQuery)
    const previousCount = this.webSearchQueryCounts.get(key)
    const nextPage = previousCount === undefined ? 1 : previousCount + 1
    this.webSearchQueryCounts.set(key, nextPage)
    parsed.page = nextPage
    toolCall.arguments = JSON.stringify(parsed)
    if (nextPage > 1) {
      console.info('ToolExecutionService', `Repeated web_search query detected, using page ${nextPage}: ${rawQuery}`)
    }
  }

  private buildCancelledResult(toolCall: ToolCall, displayName: string, sourceLabel: string): ToolResult {
    return new ToolResult(
      toolCall.id,
      JSON.stringify({ error: '工具执行已取消', cancelled: true }),
      true,
      displayName,
      sourceLabel
    )
  }

  private async requestApprovalIfNeeded(toolCall: ToolCall, tool: RegisteredTool): Promise<ToolApprovalResult> {
    if (tool.config.permissionLevel !== 'write') {
      return ToolApprovalResult.approve()
    }
    if (this.approvalCallback === null) {
      return ToolApprovalResult.unavailable('工具审批界面不可用')
    }
    try {
      return await this.approvalCallback(toolCall, tool)
    } catch (error) {
      console.error('ToolExecutionService', `Approval callback failed: ${JSON.stringify(error)}`)
      return ToolApprovalResult.unavailable(`工具审批失败: ${JSON.stringify(error)}`)
    }
  }

  private buildApprovalDeniedResult(toolCall: ToolCall, tool: RegisteredTool, approval: ToolApprovalResult): ToolResult {
    if (approval.status === ToolApprovalStatus.REJECTED) {
      return new ToolResult(
        toolCall.id,
        JSON.stringify({
          error: '用户拒绝了工具调用',
          rejected: true,
          message: approval.message !== ''
            ? approval.message
            : '用户未授权执行该工具调用。请不要继续调用同一工具，直接向用户说明已取消或询问是否需要修改后重试。'
        }),
        true,
        tool.config.name,
        tool.config.sourceLabel
      )
    }

    if (approval.status === ToolApprovalStatus.UNAVAILABLE) {
      return new ToolResult(
        toolCall.id,
        JSON.stringify({
          error: '工具审批不可用',
          approvalUnavailable: true,
          message: approval.message !== '' ? approval.message : '未能展示或连接工具审批界面，请稍后重试。'
        }),
        true,
        tool.config.name,
        tool.config.sourceLabel
      )
    }

    return new ToolResult(
      toolCall.id,
      JSON.stringify({
        error: '工具审批已取消',
        cancelled: true,
        message: approval.message !== '' ? approval.message : '工具审批面板已关闭，本次工具调用未执行。'
      }),
      true,
      tool.config.name,
      tool.config.sourceLabel
    )
  }

  private async handleAskUser(toolCall: ToolCall): Promise<ToolResult> {
    toolCall.toolId = ASK_USER_TOOL_ID
    toolCall.displayName = '向用户提问'
    // 子智能体会预先打上“子智能体 · xxx”来源标签，保留它以便 UI 区分调用来源
    if (toolCall.sourceLabel === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = 'read'

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAskUserAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAskUserAnswers.delete(toolCall.id)
        }
        this.pendingAskUserAnswers.set(toolCall.id, new PendingAskUserRuntime(resolve, toolCall))
        this.notifyPendingAskUserChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `ask_user failed: ${JSON.stringify(error)}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `ask_user 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    if (this.isCancelled()) {
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: '用户未回答该问题', cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    return new ToolResult(
      toolCall.id,
      answerJson,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // 执行单个工具调用
  async executeToolCall(toolCall: ToolCall, allowedFunctionNames: string[]): Promise<ToolResult> {
    console.info('ToolExecutionService', `Executing tool call: ${toolCall.functionName} (${toolCall.id})`)

    // 检查是否已取消
    if (this.isCancelled()) {
      console.info('ToolExecutionService', `Tool execution cancelled: ${toolCall.functionName}`)
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    const normalizedFunctionName = this.normalizeFunctionName(toolCall.functionName)
    if (!this.isFunctionAllowedForRound(normalizedFunctionName, allowedFunctionNames)) {
      return this.buildUnadvertisedToolResult(toolCall, normalizedFunctionName)
    }
    if (this.isAskUserFunctionName(normalizedFunctionName)) {
      return await this.handleAskUser(toolCall)
    }

    // 通过函数名获取工具 ID
    const toolId = this.resolveToolId(normalizedFunctionName)
    if (toolId === undefined) {
      const displayName = normalizedFunctionName !== '' ? normalizedFunctionName : 'null'
      console.error('ToolExecutionService', `Tool not found: ${displayName}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `未知工具: ${displayName}` }),
        true,
        displayName,
        toolCall.sourceLabel
      )
    }

    const registeredTool = this.registry.getTool(toolId)
    if (registeredTool === undefined) {
      console.error('ToolExecutionService', `Registered tool not found: ${toolId}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `工具未注册: ${toolId}` }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.toolId = registeredTool.id
    toolCall.displayName = registeredTool.config.name
    toolCall.sourceType = registeredTool.config.sourceType
    // 流式解析出的工具调用 sourceLabel 恒为空；子智能体镜像的调用会预先打上
    // “子智能体 · xxx”标签，保留它以便 UI 区分调用来源
    if (toolCall.sourceLabel === '') {
      toolCall.sourceLabel = registeredTool.config.sourceLabel
    }
    toolCall.permissionLevel = registeredTool.config.permissionLevel
    if (this.isWebSearchToolId(toolId)) {
      this.applyWebSearchPagination(toolCall)
    }

    const approval = await this.requestApprovalIfNeeded(toolCall, registeredTool)
    if (approval.status !== ToolApprovalStatus.APPROVED) {
      return this.buildApprovalDeniedResult(toolCall, registeredTool, approval)
    }

    // 获取工具执行器
    const executor = this.registry.getToolExecutor(toolId)
    if (executor === undefined) {
      console.error('ToolExecutionService', `Executor not found for tool: ${toolId}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `工具执行器未找到: ${toolId}` }),
        true,
        registeredTool.config.name,
        registeredTool.config.sourceLabel
      )
    }

    try {
      // 执行工具
      const startTime = Date.now()
      const result = await executor.execute(toolCall.arguments)

      // 执行完成后再次检查是否取消（避免返回已取消的结果）
      if (this.isCancelled()) {
        console.info('ToolExecutionService', `Tool execution cancelled after completion: ${toolCall.functionName}`)
        return this.buildCancelledResult(toolCall, registeredTool.config.name, registeredTool.config.sourceLabel)
      }

      const duration = Date.now() - startTime
      console.info('ToolExecutionService', `Tool ${toolCall.functionName} completed in ${duration}ms`)

      let isError = false
      try {
        const parsed = JSON.parse(result) as Record<string, Object>
        // 仅当 error 字段为非空字符串才视为错误；空字符串（如 Pyodide 成功结果带 error:''）不算
        const errorField = parsed.error
        const hasError = errorField !== undefined && errorField !== null && errorField !== ''
        isError = parsed.isError === true || hasError
      } catch (_error) {}

      return new ToolResult(
        toolCall.id,
        result,
        isError,
        registeredTool.config.name,
        registeredTool.config.sourceLabel
      )
    } catch (error) {
      console.error('ToolExecutionService', `Tool execution error: ${JSON.stringify(error)}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `工具执行失败: ${JSON.stringify(error)}` }),
        true,
        registeredTool.config.name,
        registeredTool.config.sourceLabel
      )
    }
  }

  // 批量执行工具调用（串行，避免多个确认框并发弹出）
  async executeToolCalls(toolCalls: ToolCall[], allowedFunctionNames: string[]): Promise<ToolResult[]> {
    console.info('ToolExecutionService', `Executing ${toolCalls.length} tool calls`)

    // 检查是否已取消
    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'Tool execution cancelled before batch execution')
      return toolCalls.map(tc => new ToolResult(
        tc.id,
        JSON.stringify({ error: '工具执行已取消', cancelled: true }),
        true,
        tc.displayName,
        tc.sourceLabel
      ))
    }

    const results: ToolResult[] = []
    for (let i = 0; i < toolCalls.length; i++) {
      results.push(await this.executeToolCall(toolCalls[i], allowedFunctionNames))
    }
    return results
  }

  // 检查工具是否可用
  isToolAvailable(functionName: string): boolean {
    const normalizedFunctionName = this.normalizeFunctionName(functionName)
    if (this.isAskUserFunctionName(normalizedFunctionName)) {
      return true
    }
    const toolId = this.resolveToolId(normalizedFunctionName)
    return toolId !== undefined
  }
}

// 导出单例实例获取方法
export function getToolExecutionService(): ToolExecutionService {
  return ToolExecutionService.getInstance()
}
