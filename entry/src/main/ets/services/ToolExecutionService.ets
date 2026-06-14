import { ToolCall, ToolResult } from '../models/ChatModels'
import { ASK_USER_TOOL_ID } from '../config/BuiltinTools'
import { getToolRegistry, RegisteredTool, ToolRegistry } from './ToolRegistry'

// 取消检查回调类型
type CancelCheckCallback = () => boolean
type ToolApprovalCallback = (toolCall: ToolCall, tool: RegisteredTool) => Promise<boolean>

interface WebSearchPaginationArgs {
  query?: string
  q?: string
  keywords?: string
  url?: string
  page?: number
}

class PendingAskUserRuntime {
  resolve: (answerJson: string | null) => void

  constructor(resolve: (answerJson: string | null) => void) {
    this.resolve = resolve
  }
}

// 工具执行服务 - 负责执行工具调用
export class ToolExecutionService {
  private static instance: ToolExecutionService | null = null
  private registry: ToolRegistry
  // 当前取消检查回调
  private cancelCheckCallback: CancelCheckCallback | null = null
  private approvalCallback: ToolApprovalCallback | null = null
  private pendingAskUserAnswers: Map<string, PendingAskUserRuntime> = new Map()
  private webSearchQueryCounts: Map<string, number> = new Map()

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

  resolvePendingAskUserAnswer(toolCallId: string, answerJson: string | null): boolean {
    const runtime = this.pendingAskUserAnswers.get(toolCallId)
    if (runtime === undefined) {
      return false
    }
    this.pendingAskUserAnswers.delete(toolCallId)
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

  private async requestApprovalIfNeeded(toolCall: ToolCall, tool: RegisteredTool): Promise<boolean> {
    if (tool.config.permissionLevel !== 'write') {
      return true
    }
    if (this.approvalCallback === null) {
      return false
    }
    try {
      return await this.approvalCallback(toolCall, tool)
    } catch (error) {
      console.error('ToolExecutionService', `Approval callback failed: ${JSON.stringify(error)}`)
      return false
    }
  }

  private async handleAskUser(toolCall: ToolCall): Promise<ToolResult> {
    toolCall.toolId = ASK_USER_TOOL_ID
    toolCall.displayName = '向用户提问'
    toolCall.sourceLabel = '内置工具'
    toolCall.permissionLevel = 'read'

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAskUserAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAskUserAnswers.delete(toolCall.id)
        }
        this.pendingAskUserAnswers.set(toolCall.id, new PendingAskUserRuntime(resolve))
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
  async executeToolCall(toolCall: ToolCall): Promise<ToolResult> {
    console.info('ToolExecutionService', `Executing tool call: ${toolCall.functionName} (${toolCall.id})`)

    // 检查是否已取消
    if (this.isCancelled()) {
      console.info('ToolExecutionService', `Tool execution cancelled: ${toolCall.functionName}`)
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    const normalizedFunctionName = this.normalizeFunctionName(toolCall.functionName)
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
    toolCall.sourceLabel = registeredTool.config.sourceLabel
    toolCall.permissionLevel = registeredTool.config.permissionLevel
    if (this.isWebSearchToolId(toolId)) {
      this.applyWebSearchPagination(toolCall)
    }

    const approved = await this.requestApprovalIfNeeded(toolCall, registeredTool)
    if (!approved) {
      return new ToolResult(
        toolCall.id,
        JSON.stringify({
          error: '用户拒绝了工具调用',
          rejected: true,
          message: '用户未授权执行该工具调用。请不要继续调用同一工具，直接向用户说明已取消或询问是否需要修改后重试。'
        }),
        true,
        registeredTool.config.name,
        registeredTool.config.sourceLabel
      )
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
        isError = parsed.isError === true || parsed.error !== undefined
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
  async executeToolCalls(toolCalls: ToolCall[]): Promise<ToolResult[]> {
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
      results.push(await this.executeToolCall(toolCalls[i]))
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
