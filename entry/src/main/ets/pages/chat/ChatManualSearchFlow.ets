import {
  ChatMessage,
  MessageAttachment,
  MessageRole,
  ModelInfo,
  ModelProvider,
  ModelRole,
  ProviderType,
  ReasoningLevel,
  SearchReference
} from '../../models/ChatModels'
import { ChatViewModel } from '../../viewmodels/ChatViewModel'
import { ProviderViewModel } from '../../viewmodels/ProviderViewModel'
import {
  WebSearchService,
  SearchResult,
  SearchRuntimeConfigSnapshot,
  WebSearchExecutionOptions,
  WebSearchResult
} from '../../services/WebSearchService'
import { ChatTaskOrchestratorService } from '../../services/ChatTaskOrchestratorService'
import { DefaultModelService } from '../../services/DefaultModelService'
import { PreferenceKeys, PreferencesService } from '../../services/PreferencesService'
import { AppStateManager } from '../../viewmodels/AppStateManager'
import { getEffectiveApiKey } from '../../config/PresetProviders'
import {
  cleanSearchQuery,
  normalizeOptimizedSearchQuery,
  normalizeRelativeTimeForSearchQuery,
  shouldApplyLlmOptimizationByQuery
} from '../../utils/SearchQueryUtils'
import {
  isSelfOptimizedSearchEngineForChat,
  shouldApplyLlmQueryOptimizationForChat
} from './ChatSearchDecisionHelper'
import { syncChatMessageFromSource } from './ChatMessageActionHelper'
import {
  applyEstimatedBilling,
  ModelBillingSnapshot
} from '../../utils/ModelBillingUtils'

export interface ChatManualSearchFlowDependencies {
  chatViewModel: ChatViewModel
  chatTaskOrchestrator: ChatTaskOrchestratorService
  providerViewModel: ProviderViewModel
  webSearchService: WebSearchService
  defaultModelService: DefaultModelService
  preferencesService: PreferencesService
  appStateManager: AppStateManager
  messages: ChatMessage[]
  getSessionId: () => string
  getSessionTitle: () => string
  getCurrentTaskId: () => string
  onSetCurrentTaskId: (taskId: string) => void
  getCurrentProvider: () => ModelProvider | null
  getCurrentModelId: () => string
  getCurrentModelName: () => string
  getMessages: () => ChatMessage[]
  getReasoningLevel: () => ReasoningLevel
  isSearchCancelled: () => boolean
  onSyncMessages: () => void
  onScrollBottom: () => void
  onSetSending: (value: boolean) => void
  onSetSearchCancelled: (value: boolean) => void
  onClearComposer: () => void
  onBeforeManualSearchStart: () => void
  onSetNewEmptySession: (value: boolean) => void
  onDraftCommitted: () => void
  onMarkAutoTaskFailed: (message: string) => void
  onMarkAutoTaskCompleted: () => void
  onShowError: (message: string | Resource) => void
  onShowToast: (message: string | Resource) => void
}

export class ChatManualSearchFlow {
  private deps: ChatManualSearchFlowDependencies
  private currentSearchRequestId: string = ''

  constructor(deps: ChatManualSearchFlowDependencies) {
    this.deps = deps
  }

  cancelCurrentSearchRequest(): void {
    if (this.currentSearchRequestId === '') {
      return
    }
    this.deps.webSearchService.cancelRequest(this.currentSearchRequestId)
    this.currentSearchRequestId = ''
  }

  private createManualSearchRequestId(): string {
    return `manual_search_${this.generateId()}`
  }

  private buildSearchExecutionOptions(
    requestId: string,
    runtimeConfig: SearchRuntimeConfigSnapshot
  ): WebSearchExecutionOptions {
    return {
      requestId: requestId,
      runtimeConfig: runtimeConfig,
      cancelCheck: (): boolean => this.deps.isSearchCancelled()
    }
  }

  private finishSearchRequest(requestId: string): void {
    if (this.currentSearchRequestId === requestId) {
      this.currentSearchRequestId = ''
    }
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

  private completeTask(taskId: string): void {
    this.deps.chatTaskOrchestrator.completeTask(taskId)
    if (this.deps.getCurrentTaskId() === taskId) {
      this.deps.onSetCurrentTaskId('')
    }
    this.deps.onMarkAutoTaskCompleted()
  }

  private failTask(taskId: string, errorMessage: string): void {
    this.deps.chatTaskOrchestrator.failTask(taskId, errorMessage)
    if (this.deps.getCurrentTaskId() === taskId) {
      this.deps.onSetCurrentTaskId('')
    }
    this.deps.onMarkAutoTaskFailed(errorMessage)
  }

  async startManualSearchFallback(messageContent: string, attachmentsToSend: MessageAttachment[] = []): Promise<void> {
    this.cancelCurrentSearchRequest()
    const taskId = this.startTaskOrFail(messageContent)
    if (taskId === '') {
      return
    }
    // 手动联网搜索不会经过 ChatViewModel.sendMessage()，需要在这里开启新的去重周期。
    // 否则上一条消息返回过的 URL 会在本次搜索中被全部过滤。
    this.deps.webSearchService.resetSearchResultDedup()
    const requestId = this.createManualSearchRequestId()
    this.currentSearchRequestId = requestId

    const extractedUrl = this.deps.webSearchService.extractUrl(messageContent)
    const isPureUrl = extractedUrl !== null && extractedUrl === messageContent.trim()

    this.deps.onSetCurrentTaskId(taskId)
    this.deps.onClearComposer()
    this.deps.onSetSending(true)
    this.deps.onSetSearchCancelled(false)
    this.deps.onBeforeManualSearchStart()

    const userMessage = this.createPendingUserMessage(messageContent, attachmentsToSend)

    if (isPureUrl && extractedUrl !== null) {
      await this.performUrlFetchAsync(extractedUrl, messageContent, userMessage, attachmentsToSend, requestId, taskId)
      return
    }
    await this.performBingSearchAsync(messageContent, userMessage, attachmentsToSend, requestId, taskId)
  }

  private generateId(): string {
    return Date.now().toString() + Math.random().toString(36).substring(2, 9)
  }

  createPendingUserMessage(content: string, attachments: MessageAttachment[] = []): ChatMessage {
    const userMessage = new ChatMessage(
      this.generateId(),
      MessageRole.USER,
      content,
      ''
    )
    userMessage.isSearching = false
    for (let i = 0; i < attachments.length; i++) {
      userMessage.attachments.push(attachments[i])
    }
    this.deps.messages.push(userMessage)
    this.deps.onSyncMessages()
    this.deps.onSetNewEmptySession(false)
    this.deps.onDraftCommitted()
    this.deps.onScrollBottom()
    return userMessage
  }

  private createSearchingAIMessage(): ChatMessage {
    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      this.deps.getCurrentModelName()
    )
    aiMessage.isSearching = true
    this.deps.messages.push(aiMessage)
    this.deps.onSyncMessages()
    this.deps.onScrollBottom()
    return aiMessage
  }

  private removeSearchingAIMessage(aiMessage: ChatMessage): void {
    const idx = this.deps.messages.findIndex((m: ChatMessage) => m.id === aiMessage.id)
    if (idx >= 0) {
      this.deps.messages.splice(idx, 1)
    }
    this.deps.onSyncMessages()
  }

  async performBingSearchAsync(query: string, userMessage: ChatMessage,
    attachmentsToSend: MessageAttachment[] = [],
    requestId: string = '',
    taskId: string = ''): Promise<void> {
    const searchingAIMessage = this.createSearchingAIMessage()

    try {
      const runtimeConfig = await this.deps.webSearchService.getRuntimeConfigSnapshot()
      const preferredEngineName = await this.deps.webSearchService.getPreferredEngineName(runtimeConfig)
      searchingAIMessage.searchQuery = query
      searchingAIMessage.searchEngine = preferredEngineName

      if (this.deps.isSearchCancelled()) {
        this.removeSearchingAIMessage(searchingAIMessage)
        return
      }

      const cleanedQuery = cleanSearchQuery(query)

      if (this.deps.isSearchCancelled()) {
        this.removeSearchingAIMessage(searchingAIMessage)
        return
      }

      let optimizedQuery = cleanedQuery
      let optimizationApplied = false
      const optimizationConfigured = await this.deps.preferencesService.getBoolean(
        PreferenceKeys.SEARCH_QUERY_OPTIMIZATION_ENABLED,
        false
      )
      const shouldOptimizeByQuery = shouldApplyLlmOptimizationByQuery(query, cleanedQuery)
      const shouldApplyOptimization = shouldApplyLlmQueryOptimizationForChat(
        preferredEngineName,
        optimizationConfigured
      ) && shouldOptimizeByQuery
      if (optimizationConfigured &&
        !shouldApplyOptimization &&
      isSelfOptimizedSearchEngineForChat(preferredEngineName)) {
        console.info('ChatPage', `[联网查询] 当前引擎为${preferredEngineName}，跳过额外搜索词优化，避免重复改写`)
      }
      if (optimizationConfigured && !shouldOptimizeByQuery) {
        console.info('ChatPage', '[联网查询] 查询已足够结构化，跳过关键词优化')
      }

      if (shouldApplyOptimization) {
        await this.deps.defaultModelService.initialize()
        const searchOptModel = this.deps.defaultModelService.getModel(ModelRole.SEARCH_OPTIMIZATION)
        if (searchOptModel.isConfigured()) {
          const provider = await this.deps.providerViewModel.getProviderByIdAsync(searchOptModel.providerId)
          if (provider !== null) {
            const effectiveApiKey = getEffectiveApiKey(provider.id, provider.apiKey)
            if (effectiveApiKey !== '' || provider.type === ProviderType.OLLAMA) {
              optimizedQuery = await this.deps.chatViewModel.optimizeSearchQuery(
                cleanedQuery,
                this.deps.getMessages(),
                provider.id,
                provider.type,
                provider.apiStyle,
                effectiveApiKey,
                provider.baseUrl,
                searchOptModel.modelId,
                provider.customHeadersJson || undefined
              )
              optimizationApplied = true
            }
          }
        }
        const currentProvider = this.deps.getCurrentProvider()
        if (!optimizationApplied && currentProvider !== null) {
          const effectiveApiKey = getEffectiveApiKey(currentProvider.id, currentProvider.apiKey)
          if (effectiveApiKey !== '' || currentProvider.type === ProviderType.OLLAMA) {
            optimizedQuery = await this.deps.chatViewModel.optimizeSearchQuery(
              cleanedQuery,
              this.deps.getMessages(),
              currentProvider.id,
              currentProvider.type,
              currentProvider.apiStyle,
              effectiveApiKey,
              currentProvider.baseUrl,
              this.deps.getCurrentModelId(),
              currentProvider.customHeadersJson || undefined
            )
            optimizationApplied = true
          }
        }
      }

      optimizedQuery = normalizeOptimizedSearchQuery(cleanedQuery, optimizedQuery)
      const normalizedQuery = normalizeRelativeTimeForSearchQuery(cleanedQuery, optimizedQuery)
      if (normalizedQuery !== optimizedQuery) {
        optimizedQuery = normalizedQuery
      }
      console.info('ChatPage',
        `[联网查询] 最终搜索关键词: "${optimizedQuery}" (optimizationApplied=${optimizationApplied})`)

      if (optimizedQuery !== searchingAIMessage.searchQuery) {
        searchingAIMessage.searchQuery = optimizedQuery
      }

      if (this.deps.isSearchCancelled()) {
        this.removeSearchingAIMessage(searchingAIMessage)
        return
      }

      const searchResult = await this.deps.webSearchService.search(
        optimizedQuery,
        this.buildSearchExecutionOptions(requestId, runtimeConfig)
      )

      if (this.deps.isSearchCancelled()) {
        this.removeSearchingAIMessage(searchingAIMessage)
        return
      }

      this.removeSearchingAIMessage(searchingAIMessage)

      if (!searchResult.success) {
        this.deps.onShowToast($r('app.string.web_search_failed'))
        this.deps.onSetSending(false)
        this.failTask(taskId, searchResult.errorMessage)
        return
      }

      userMessage.searchQuery = searchResult.query
      userMessage.searchEngine = searchResult.searchEngine || preferredEngineName
      for (let i = 0; i < searchResult.references.length; i++) {
        userMessage.searchReferences.push(searchResult.references[i])
      }

      await this.sendSearchResultMessage(query, searchResult, attachmentsToSend, taskId)
    } catch (error) {
      this.removeSearchingAIMessage(searchingAIMessage)
      console.error('ChatPage', `[performBingSearchAsync] 搜索异常: ${JSON.stringify(error)}`)
      this.deps.onShowToast($r('app.string.web_search_failed'))
      this.deps.onSetSending(false)
      this.failTask(taskId, '联网搜索失败')
    } finally {
      this.finishSearchRequest(requestId)
    }
  }

  async performUrlFetchAsync(url: string, originalInput: string, userMessage: ChatMessage,
    attachmentsToSend: MessageAttachment[] = [],
    requestId: string = '',
    taskId: string = ''): Promise<void> {
    const searchingAIMessage = this.createSearchingAIMessage()

    try {
      const runtimeConfig = await this.deps.webSearchService.getRuntimeConfigSnapshot()
      if (this.deps.isSearchCancelled()) {
        this.removeSearchingAIMessage(searchingAIMessage)
        return
      }

      const webResult = await this.deps.webSearchService.fetchUrlContent(
        url,
        this.buildSearchExecutionOptions(requestId, runtimeConfig)
      )

      if (this.deps.isSearchCancelled()) {
        this.removeSearchingAIMessage(searchingAIMessage)
        return
      }

      this.removeSearchingAIMessage(searchingAIMessage)

      if (!webResult.success) {
        console.error('ChatPage', `[performUrlFetchAsync] 网页获取失败: ${webResult.errorMessage}`)
        const failureSearchResult = this.buildUrlFetchFailureSearchResult(
          originalInput.trim() !== '' ? originalInput : url,
          url,
          webResult
        )
        userMessage.searchQuery = failureSearchResult.query
        userMessage.searchEngine = failureSearchResult.searchEngine
        for (let i = 0; i < failureSearchResult.references.length; i++) {
          userMessage.searchReferences.push(failureSearchResult.references[i])
        }
        await this.sendSearchResultMessage(originalInput.trim() !== '' ? originalInput : url, failureSearchResult,
          attachmentsToSend, taskId)
        return
      }

      const searchResult = new SearchResult(
        true,
        originalInput.trim() !== '' ? originalInput : url,
        webResult.sourceName !== '' ? webResult.sourceName : 'URL抓取',
        [new SearchReference(
          `ref_${Date.now()}`,
          webResult.title,
          webResult.url,
          webResult.content.substring(0, 200) + '...'
        )],
        `标题: ${webResult.title}\n来源: ${webResult.url}\n\n${webResult.content}`,
        ''
      )

      userMessage.searchQuery = searchResult.query
      userMessage.searchEngine = searchResult.searchEngine
      for (let i = 0; i < searchResult.references.length; i++) {
        userMessage.searchReferences.push(searchResult.references[i])
      }

      await this.sendSearchResultMessage(originalInput.trim() !== '' ? originalInput : url, searchResult,
        attachmentsToSend, taskId)
    } catch (error) {
      this.removeSearchingAIMessage(searchingAIMessage)
      console.error('ChatPage', `[performUrlFetchAsync] 网页获取异常: ${JSON.stringify(error)}`)
      this.deps.onShowToast($r('app.string.url_fetch_failed'))
      this.deps.onSetSending(false)
      this.failTask(taskId, '网页抓取失败')
    } finally {
      this.finishSearchRequest(requestId)
    }
  }

  private buildUrlFetchFailureSearchResult(userQuery: string, url: string, webResult: WebSearchResult): SearchResult {
    const fullUrl = webResult.url.trim() !== '' ? webResult.url : url
    const sourceName = webResult.sourceName.trim() !== '' ? webResult.sourceName : 'URL抓取'
    const errorMessage = webResult.errorMessage.trim() !== '' ? webResult.errorMessage : '未获取到网页正文'
    return new SearchResult(
      true,
      userQuery,
      sourceName,
      [new SearchReference(
        `ref_${Date.now()}`,
        fullUrl,
        fullUrl,
        `读取失败: ${this.limitReferenceSnippet(errorMessage)}`
      )],
      this.buildUrlFetchFailureContext(fullUrl, sourceName, errorMessage),
      ''
    )
  }

  private buildUrlFetchFailureContext(url: string, sourceName: string, errorMessage: string): string {
    return `URL 读取结果:
目标链接: ${url}
读取方式: ${sourceName}
状态: 失败
错误: ${errorMessage}

要求:
- 请说明读取链路已经尝试过，以及失败原因可能是目标站点拒绝抓取、需要登录、依赖动态脚本渲染或访问受限。
- 如果需要给出下一步建议，可以建议用户在浏览器打开链接或提供网页截图/页面正文。`
  }

  private limitReferenceSnippet(text: string): string {
    const normalized = text.replace(/\s+/g, ' ').trim()
    if (normalized.length <= 180) {
      return normalized
    }
    return normalized.substring(0, 180) + '...'
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

  private async sendSearchResultMessage(userQuery: string, searchResult: SearchResult,
    attachmentsToSend: MessageAttachment[] = [],
    taskId: string = ''): Promise<void> {
    const currentProvider = this.deps.getCurrentProvider()
    if (currentProvider === null) {
      this.deps.onShowError($r('app.string.provider_required_before_chat'))
      this.deps.onSetSending(false)
      this.failTask(taskId, '未配置可用服务商')
      return
    }

    const effectiveApiKey = getEffectiveApiKey(currentProvider.id, currentProvider.apiKey)
    if (effectiveApiKey === '' && currentProvider.type !== ProviderType.OLLAMA) {
      this.deps.onShowError($r('app.string.api_key_required'))
      this.deps.onSetSending(false)
      this.failTask(taskId, '缺少 API Key')
      return
    }

    const modelId = this.deps.appStateManager.getCurrentModelId()
    const billing = this.getModelBillingSnapshot(currentProvider, modelId)
    await this.deps.chatViewModel.sendMessageWithSearchResult(
      userQuery,
      searchResult,
      currentProvider.id,
      currentProvider.type,
      currentProvider.apiStyle,
      effectiveApiKey,
      currentProvider.baseUrl,
      modelId,
      this.deps.getCurrentModelName(),
      this.deps.getMessages(),
      attachmentsToSend,
      0,
      (userMessage: ChatMessage): void => {
        const allMessages = this.deps.messages
        let found = false
        for (let i = allMessages.length - 1; i >= 0; i--) {
          if (allMessages[i].role === MessageRole.USER) {
            syncChatMessageFromSource(allMessages[i], userMessage)
            found = true
            break
          }
        }
        if (!found) {
          allMessages.push(userMessage)
          this.deps.onSyncMessages()
        }
      },
      (aiMessage: ChatMessage): void => {
        applyEstimatedBilling(aiMessage, this.deps.messages, billing, true)
        this.deps.messages.push(aiMessage)
        this.deps.onSyncMessages()
        this.deps.onScrollBottom()
      },
      (aiMessage: ChatMessage): void => {
        applyEstimatedBilling(aiMessage, this.deps.messages, billing)
        const index = this.deps.messages.findIndex((message: ChatMessage) => message.id === aiMessage.id)
        if (index < 0) {
          console.warn('ChatManualSearchFlow', `[sendSearchResultMessage] ai message not found: ${aiMessage.id}`)
          return
        }
        syncChatMessageFromSource(this.deps.messages[index], aiMessage)
        this.deps.onScrollBottom()
      },
      (): void => {
        this.deps.onSetSending(false)
        this.completeTask(taskId)
      },
      (error: string): void => {
        this.deps.onSetSending(false)
        this.failTask(taskId, error)
        this.deps.onShowError(error)
      },
      this.deps.getReasoningLevel(),
      currentProvider.apiPath || undefined,
      currentProvider.customHeadersJson || undefined
    )
  }
}
