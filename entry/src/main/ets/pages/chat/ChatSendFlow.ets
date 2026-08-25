import {
  ApiStyle,
  ChatMessage,
  MessageAttachment,
  ModelInfo,
  ModelProvider,
  ReasoningLevel,
  ToolCall,
  ToolResult
} from '../../models/ChatModels'
import { ChatViewModel, ToolCallCallbacks } from '../../viewmodels/ChatViewModel'
import { ChatTaskOrchestratorService } from '../../services/ChatTaskOrchestratorService'
import { ToolRegistry } from '../../services/ToolRegistry'
import { appendUniqueToolId } from './ChatToolIdHelper'
import { syncChatMessageFromSource } from './ChatMessageActionHelper'
import { validateProviderConfig } from '../../utils/ProviderValidationUtils'
import { ASK_USER_TOOL_ID, CANVAS_DOCUMENT_TOOL_ID, PLAN_MODE_TOOL_ID } from '../../config/BuiltinTools'
import {
  applyEstimatedBilling,
  ModelBillingSnapshot
} from '../../utils/ModelBillingUtils'
import { toErrorDetail } from '../../models/AppError'

export class ChatSendPrepareResult {
  shouldSend: boolean = false
  messageContent: string = ''
  effectiveApiKey: string = ''
  currentProvider: ModelProvider | null = null
}

enum ChatExecutionPlanKind {
  PLAIN_DIRECT = 'plain_direct',
  TOOLS = 'tools',
  MANUAL_SEARCH = 'manual_search',
  UNSUPPORTED_TOOLS = 'unsupported_tools'
}

class ChatExecutionPlan {
  kind: ChatExecutionPlanKind
  enabledToolIds: string[]

  constructor(kind: ChatExecutionPlanKind, enabledToolIds: string[] = []) {
    this.kind = kind
    this.enabledToolIds = enabledToolIds
  }
}

export interface ChatSendFlowDependencies {
  chatViewModel: ChatViewModel
  messages: ChatMessage[]
  chatTaskOrchestrator: ChatTaskOrchestratorService
  toolRegistry: ToolRegistry
  getSessionId: () => string
  getSessionTitle: () => string
  getCurrentTaskId: () => string
  getCurrentModelId: () => string
  getCurrentModelName: () => string
  getMessages: () => ChatMessage[]
  getReasoningLevel: () => ReasoningLevel
  executeManualSearch: (messageContent: string, attachmentsToSend: MessageAttachment[]) => Promise<void>
  onClearComposer: () => void
  onBeforeSend: () => void
  onSetSending: (value: boolean) => void
  onSetCurrentTaskId: (taskId: string) => void
  onSyncMessages: () => void
  onScrollBottom: () => void
  onSetNewEmptySession: (value: boolean) => void
  onSessionResolved: () => void
  onDraftCommitted: () => void
  onMarkAutoTaskCompleted: () => void
  onMarkAutoTaskFailed: (message: string) => void
  onShowError: (message: string | Resource) => void
  onShowToast: (message: string | Resource) => void
  onCanvasDocumentUpdated?: () => void
  onPlanUpdated?: () => void
}

export class ChatSendFlow {
  private deps: ChatSendFlowDependencies

  constructor(deps: ChatSendFlowDependencies) {
    this.deps = deps
  }

  prepareSendRequest(
    inputText: string,
    pendingAttachmentCount: number,
    isSending: boolean,
    currentProvider: ModelProvider | null,
    currentModelId: string,
    canStartNewTask: boolean
  ): ChatSendPrepareResult {
    const result = new ChatSendPrepareResult()
    const messageContent = inputText.trim()
    if (messageContent === '' && pendingAttachmentCount === 0) {
      return result
    }
    if (isSending) {
      return result
    }

    const providerValidation = validateProviderConfig(currentProvider)
    if (!providerValidation.isValid || currentProvider === null) {
      if (currentProvider === null) {
        this.deps.onShowError($r('app.string.provider_required_before_chat'))
        this.deps.onMarkAutoTaskFailed('未配置可用服务商')
      } else if (currentProvider.requiresApiKey && providerValidation.effectiveApiKey === '') {
        this.deps.onShowError($r('app.string.api_key_required'))
        this.deps.onMarkAutoTaskFailed('缺少 API Key')
      } else {
        this.deps.onShowError(providerValidation.errorMessage)
        this.deps.onMarkAutoTaskFailed(providerValidation.errorMessage)
      }
      return result
    }

    if (!this.isCurrentModelAvailable(currentProvider, currentModelId)) {
      this.deps.onShowError('当前模型不可用，请重新选择模型')
      this.deps.onMarkAutoTaskFailed('当前模型不可用')
      return result
    }

    if (!canStartNewTask) {
      this.deps.onShowToast($r('app.string.task_parallel_limit_reached'))
      this.deps.onMarkAutoTaskFailed('并行任务已达上限')
      return result
    }

    result.shouldSend = true
    result.messageContent = messageContent
    result.effectiveApiKey = providerValidation.effectiveApiKey
    result.currentProvider = currentProvider
    return result
  }

  private isCurrentModelAvailable(currentProvider: ModelProvider, currentModelId: string): boolean {
    if (currentModelId === '') {
      return false
    }
    for (let i = 0; i < currentProvider.models.length; i++) {
      const model = currentProvider.models[i]
      if (model.id === currentModelId && model.isEnabled) {
        return true
      }
    }
    return false
  }

  async executeSend(
    messageContent: string,
    currentProvider: ModelProvider,
    effectiveApiKey: string,
    attachmentsToSend: MessageAttachment[],
    webSearchConversationEnabled: boolean,
    selectedToolIds: string[],
    forcedToolIds: string[],
    currentModelId: string,
    modelSupportsDocuments: boolean = true,
    modelSupportsVision: boolean = true,
    requestContent: string = '',
    userDocumentToolHint: string = ''
  ): Promise<void> {
    const plan = this.buildExecutionPlan(
      messageContent,
      currentProvider,
      webSearchConversationEnabled,
      selectedToolIds,
      forcedToolIds,
      currentModelId
    )
    console.info(
      'ChatSendFlow',
      `[executeSend] plan=${plan.kind}, search=${webSearchConversationEnabled}, selected=${selectedToolIds.join(',')}, forced=${forcedToolIds.join(',')}, tools=${plan.enabledToolIds.join(',')}`
    )

    if (plan.kind === ChatExecutionPlanKind.MANUAL_SEARCH) {
      await this.deps.executeManualSearch(messageContent, attachmentsToSend)
      return
    }

    if (plan.kind === ChatExecutionPlanKind.TOOLS) {
      await this.sendMessageWithTools(
        messageContent,
        currentProvider,
        effectiveApiKey,
        attachmentsToSend,
        plan.enabledToolIds,
        modelSupportsDocuments,
        modelSupportsVision,
        requestContent,
        userDocumentToolHint
      )
      return
    }

    if (plan.kind === ChatExecutionPlanKind.UNSUPPORTED_TOOLS) {
      const message = '当前模型或接口不支持所选工具，请切换到支持 tools 的模型后重试'
      this.deps.onShowError(message)
      this.deps.onMarkAutoTaskFailed(message)
      return
    }

    await this.sendPlainMessage(
      messageContent,
      currentProvider,
      effectiveApiKey,
      attachmentsToSend,
      modelSupportsDocuments,
      modelSupportsVision,
      requestContent,
      userDocumentToolHint
    )
  }

  isCurrentModelSupportsTools(currentProvider: ModelProvider | null, currentModelId: string): boolean {
    if (currentProvider === null) {
      return false
    }
    if (currentProvider.apiStyle !== ApiStyle.OPENAI) {
      console.info('ChatSendFlow', `[Function Calling] 当前 API 风格不支持 tools: ${currentProvider.apiStyle}`)
      return false
    }
    for (let i = 0; i < currentProvider.models.length; i++) {
      const model = currentProvider.models[i]
      if (model.id === currentModelId) {
        console.info('ChatSendFlow',
          `[Function Calling] 当前模型 supportsTools=${model.capabilities.supportsTools}, modelId=${model.id}`)
        return model.capabilities.supportsTools
      }
    }
    console.info('ChatSendFlow',
      `[Function Calling] 未在 provider.models 中找到当前模型: currentModelId=${currentModelId}, provider=${currentProvider.id}`)
    return false
  }

  buildEnabledToolIds(selectedToolIds: string[] = [], forcedToolIds: string[] = []): string[] {
    const ids: string[] = []
    const allToolIds = [...selectedToolIds, ...forcedToolIds]
    for (let i = 0; i < allToolIds.length; i++) {
      const toolId = allToolIds[i]
      if (this.deps.toolRegistry.isToolRegistered(toolId)) {
        appendUniqueToolId(ids, toolId)
      }
    }
    return ids
  }

  private shouldEnableWebSearch(
    webSearchConversationEnabled: boolean,
    forcedToolIds: string[]
  ): boolean {
    if (webSearchConversationEnabled) {
      return true
    }
    return forcedToolIds.includes('web_search')
  }

  private filterNonSearchToolIds(toolIds: string[]): string[] {
    const ids: string[] = []
    for (let i = 0; i < toolIds.length; i++) {
      if (toolIds[i] !== 'web_search') {
        ids.push(toolIds[i])
      }
    }
    return ids
  }

  private isCanvasDocumentToolCall(toolCall: ToolCall): boolean {
    if (toolCall.toolId.trim() === CANVAS_DOCUMENT_TOOL_ID) {
      return true
    }
    return toolCall.functionName.trim().toLowerCase().replace(/[\s\-]+/g, '_') === CANVAS_DOCUMENT_TOOL_ID
  }

  private isPlanModeToolCall(toolCall: ToolCall): boolean {
    if (toolCall.toolId.trim() === PLAN_MODE_TOOL_ID) {
      return true
    }
    return toolCall.functionName.trim().toLowerCase().replace(/[\s\-]+/g, '_') === PLAN_MODE_TOOL_ID
  }

  private buildExecutionPlan(
    messageContent: string,
    currentProvider: ModelProvider,
    webSearchConversationEnabled: boolean,
    selectedToolIds: string[],
    forcedToolIds: string[],
    currentModelId: string
  ): ChatExecutionPlan {
    const enabledToolIds = this.buildEnabledToolIds(selectedToolIds, this.filterNonSearchToolIds(forcedToolIds))
    const searchEnabled = this.shouldEnableWebSearch(webSearchConversationEnabled, forcedToolIds) ||
      enabledToolIds.includes('web_search')
    if (searchEnabled && this.deps.toolRegistry.isToolRegistered('web_search')) {
      appendUniqueToolId(enabledToolIds, 'web_search')
    }
    if (enabledToolIds.length === 0) {
      return new ChatExecutionPlan(ChatExecutionPlanKind.PLAIN_DIRECT)
    }

    if (searchEnabled && this.allToolsAreWebSearch(enabledToolIds) && this.isPureUrlInput(messageContent)) {
      return new ChatExecutionPlan(ChatExecutionPlanKind.MANUAL_SEARCH, enabledToolIds)
    }

    if (this.isCurrentModelSupportsTools(currentProvider, currentModelId)) {
      if (searchEnabled && this.deps.toolRegistry.isToolRegistered(ASK_USER_TOOL_ID)) {
        appendUniqueToolId(enabledToolIds, ASK_USER_TOOL_ID)
      }
      return new ChatExecutionPlan(ChatExecutionPlanKind.TOOLS, enabledToolIds)
    }

    if (searchEnabled && this.allToolsAreWebSearch(enabledToolIds)) {
      return new ChatExecutionPlan(ChatExecutionPlanKind.MANUAL_SEARCH, enabledToolIds)
    }

    return new ChatExecutionPlan(ChatExecutionPlanKind.UNSUPPORTED_TOOLS, enabledToolIds)
  }

  private isPureUrlInput(messageContent: string): boolean {
    const trimmed = messageContent.trim()
    if (trimmed === '' || /\s/.test(trimmed)) {
      return false
    }
    const httpPattern = /^https?:\/\/[^\s]+$/i
    if (httpPattern.test(trimmed)) {
      return true
    }
    const domainPattern = /^[\w\-]+\.[\w\-]+(:\d+)?(\/[\w\-._~:/?#[\]@!$&'()*+,;=]*)?$/i
    return domainPattern.test(trimmed)
  }

  private allToolsAreWebSearch(toolIds: string[]): boolean {
    if (toolIds.length === 0) {
      return false
    }
    for (let i = 0; i < toolIds.length; i++) {
      if (toolIds[i] !== 'web_search') {
        return false
      }
    }
    return true
  }

  private startTaskOrFail(messageContent: string): string {
    const taskId = this.deps.chatTaskOrchestrator.startTask(
      this.deps.getSessionId(),
      this.deps.getSessionTitle(),
      messageContent,
      this.deps.chatViewModel
    )
    if (taskId === '') {
      this.deps.onShowToast($r('app.string.task_parallel_limit_reached'))
      this.deps.onMarkAutoTaskFailed('并行任务已达上限')
      return ''
    }
    return taskId
  }

  private prepareSendState(taskId: string): void {
    this.deps.onSetCurrentTaskId(taskId)
    this.deps.onSetSending(true)
    this.deps.onBeforeSend()
  }

  private handleUserMessageAdded(userMessage: ChatMessage): void {
    this.deps.onSessionResolved()
    this.deps.onClearComposer()
    this.deps.messages.push(userMessage)
    this.deps.onSyncMessages()
    this.deps.onSetNewEmptySession(false)
    this.deps.onDraftCommitted()
    this.deps.onScrollBottom()
  }

  private handleAIMessageAdded(aiMessage: ChatMessage, billing: ModelBillingSnapshot): void {
    this.deps.onSessionResolved()
    applyEstimatedBilling(aiMessage, this.deps.messages, billing, true)
    this.deps.messages.push(aiMessage)
    this.deps.onSyncMessages()
    this.deps.onScrollBottom()
  }

  private handleAIMessageUpdated(aiMessage: ChatMessage, billing: ModelBillingSnapshot): void {
    applyEstimatedBilling(aiMessage, this.deps.messages, billing)
    const index = this.deps.messages.findIndex((message: ChatMessage) => message.id === aiMessage.id)
    if (index < 0) {
      console.warn('ChatSendFlow', `[handleAIMessageUpdated] message not found: ${aiMessage.id}`)
      return
    }
    syncChatMessageFromSource(this.deps.messages[index], aiMessage)
    this.deps.onScrollBottom()
  }

  private getModelBillingSnapshot(provider: ModelProvider, modelId: string): ModelBillingSnapshot {
    let model: ModelInfo | null = null
    for (let i = 0; i < provider.models.length; i++) {
      if (provider.models[i].id === modelId) {
        model = provider.models[i]
        break
      }
    }
    return new ModelBillingSnapshot(model)
  }

  private handleTaskCompleted(taskId: string): void {
    this.deps.chatTaskOrchestrator.completeTask(taskId)
    if (this.deps.getCurrentTaskId() === taskId) {
      this.deps.onSetCurrentTaskId('')
    }
    this.deps.onSetSending(false)
    this.deps.onMarkAutoTaskCompleted()
  }

  private handleTaskFailed(taskId: string, error: string, showError: boolean): void {
    this.deps.chatTaskOrchestrator.failTask(taskId, error)
    if (this.deps.getCurrentTaskId() === taskId) {
      this.deps.onSetCurrentTaskId('')
    }
    this.deps.onSetSending(false)
    this.deps.onMarkAutoTaskFailed(error)
    if (showError) {
      this.deps.onShowError(error)
    }
  }

  async sendPlainMessage(
    messageContent: string,
    currentProvider: ModelProvider,
    effectiveApiKey: string,
    attachmentsToSend: MessageAttachment[] = [],
    modelSupportsDocuments: boolean = true,
    modelSupportsVision: boolean = true,
    requestContent: string = '',
    userDocumentToolHint: string = ''
  ): Promise<void> {
    const taskId = this.startTaskOrFail(messageContent)
    if (taskId === '') {
      return
    }

    this.prepareSendState(taskId)
    const modelId = this.deps.getCurrentModelId()
    const billing = this.getModelBillingSnapshot(currentProvider, modelId)

    try {
      await this.deps.chatViewModel.sendMessage(
        messageContent,
        currentProvider.id,
        currentProvider.type,
        currentProvider.apiStyle,
        effectiveApiKey,
        currentProvider.baseUrl,
        modelId,
        this.deps.getCurrentModelName(),
        this.deps.getMessages(),
        (userMessage: ChatMessage): void => {
          this.handleUserMessageAdded(userMessage)
        },
        (aiMessage: ChatMessage): void => {
          this.handleAIMessageAdded(aiMessage, billing)
        },
        (aiMessage: ChatMessage): void => {
          this.handleAIMessageUpdated(aiMessage, billing)
        },
        (): void => {
          this.handleTaskCompleted(taskId)
        },
        (error: string): void => {
          this.handleTaskFailed(taskId, error, true)
        },
        attachmentsToSend,
        0,
        this.deps.getReasoningLevel(),
        modelSupportsDocuments,
        modelSupportsVision,
        requestContent,
        userDocumentToolHint,
        currentProvider.apiPath || undefined,
        currentProvider.customHeadersJson || undefined
      )
    } catch (error) {
      const message = `发送失败: ${toErrorDetail(error as Object)}`
      console.error('ChatSendFlow', `[sendPlainMessage] ${message}`)
      this.handleTaskFailed(taskId, message, true)
    }
  }

  async sendMessageWithTools(
    messageContent: string,
    currentProvider: ModelProvider,
    effectiveApiKey: string,
    attachmentsToSend: MessageAttachment[] = [],
    enabledToolIds: string[] = [],
    modelSupportsDocuments: boolean = true,
    modelSupportsVision: boolean = true,
    requestContent: string = '',
    userDocumentToolHint: string = ''
  ): Promise<void> {
    const taskId = this.startTaskOrFail(messageContent)
    if (taskId === '') {
      return
    }

    this.prepareSendState(taskId)
    const modelId = this.deps.getCurrentModelId()
    const billing = this.getModelBillingSnapshot(currentProvider, modelId)
    const tools = this.deps.toolRegistry.getEnabledToolDefinitions(enabledToolIds)

    console.info('ChatSendFlow', `[Function Calling] 启用工具: ${enabledToolIds.join(', ')}`)
    let shouldRefreshCanvasDocument = false
    let shouldRefreshPlan = false

    const toolCallbacks: ToolCallCallbacks = {
      onToolCallStarted: (toolCalls: ToolCall[]): void => {
        console.info('ChatSendFlow', `[Function Calling] 工具调用开始: ${toolCalls.length} 个`)
        for (let i = 0; i < toolCalls.length; i++) {
          console.info('ChatSendFlow', `  - ${toolCalls[i].functionName}: ${toolCalls[i].arguments}`)
          if (this.isCanvasDocumentToolCall(toolCalls[i])) {
            shouldRefreshCanvasDocument = true
          }
          if (this.isPlanModeToolCall(toolCalls[i])) {
            shouldRefreshPlan = true
          }
        }
      },
      onToolCallCompleted: (results: ToolResult[]): void => {
        console.info('ChatSendFlow', `[Function Calling] 工具调用完成: ${results.length} 个结果`)
        if (shouldRefreshCanvasDocument && this.deps.onCanvasDocumentUpdated !== undefined) {
          shouldRefreshCanvasDocument = false
          this.deps.onCanvasDocumentUpdated()
        }
        if (shouldRefreshPlan && this.deps.onPlanUpdated !== undefined) {
          shouldRefreshPlan = false
          this.deps.onPlanUpdated()
        }
      },
      onSearching: (query: string): void => {
        console.info('ChatSendFlow', `[Function Calling] 正在搜索: ${query}`)
      }
    }

    try {
      await this.deps.chatViewModel.sendMessageWithTools(
        messageContent,
        currentProvider.id,
        currentProvider.type,
        currentProvider.apiStyle,
        effectiveApiKey,
        currentProvider.baseUrl,
        modelId,
        this.deps.getCurrentModelName(),
        this.deps.getMessages(),
        (userMessage: ChatMessage): void => {
          this.handleUserMessageAdded(userMessage)
        },
        (aiMessage: ChatMessage): void => {
          this.handleAIMessageAdded(aiMessage, billing)
        },
        (aiMessage: ChatMessage): void => {
          this.handleAIMessageUpdated(aiMessage, billing)
        },
        (): void => {
          this.handleTaskCompleted(taskId)
        },
        (error: string): void => {
          this.handleTaskFailed(taskId, error, true)
        },
        attachmentsToSend,
        0,
        this.deps.getReasoningLevel(),
        tools,
        toolCallbacks,
        modelSupportsDocuments,
        modelSupportsVision,
        requestContent,
        userDocumentToolHint,
        currentProvider.apiPath || undefined,
        currentProvider.customHeadersJson || undefined
      )
    } catch (error) {
      const message = `发送失败: ${toErrorDetail(error as Object)}`
      console.error('ChatSendFlow', `[sendMessageWithTools] ${message}`)
      this.handleTaskFailed(taskId, message, true)
    }
  }
}
