import {
  getHttpService,
  HttpService,
  HttpRequestController,
  HttpRequestRuntimeOptions
} from './HttpService'
import { util } from '@kit.ArkTS'
import { SearchReference, SearchServiceConfig, SearchEngine } from '../models/ChatModels'
import { getPreferencesService, PreferenceKeys } from './PreferencesService'
import { cleanSearchQuery as cleanSearchQueryShared } from '../utils/SearchQueryUtils'
import { JsonResponseContent, parseJsonResponseContent } from '../utils/JsonResponseUtils'
import { getDatabaseService, ProviderConfig } from './DatabaseService'
import { getEffectiveApiKey } from '../config/PresetProviders'
import {
  buildDeepSeekWebSearchEndpoint,
  DEEPSEEK_WEB_SEARCH_DEFAULT_BASE_URL,
  DEEPSEEK_WEB_SEARCH_DEFAULT_MODEL,
  DEEPSEEK_WEB_SEARCH_MAX_TOKENS,
  DEEPSEEK_WEB_SEARCH_MAX_USES,
  DEEPSEEK_WEB_SEARCH_TIMEOUT_MS,
  extractDeepSeekWebSearchError,
  isDeepSeekProvider,
  parseDeepSeekWebSearchResponse
} from '../utils/DeepSeekWebSearchUtils'

// 搜索结果类（用于返回给业务层）
export class SearchResult {
  success: boolean
  query: string
  searchEngine: string
  references: SearchReference[]
  contentForAI: string
  errorMessage: string
  startIndex: number
  // 翻页/去重后已无更多新结果时为 true（success 仍为 true，但 references 为空），用于提示模型换词或停止
  exhausted: boolean

  constructor(
    success: boolean,
    query: string,
    searchEngine: string,
    references: SearchReference[],
    contentForAI: string,
    errorMessage: string,
    startIndex: number = 1,
    exhausted: boolean = false
  ) {
    this.success = success
    this.query = query
    this.searchEngine = searchEngine
    this.references = references
    this.contentForAI = contentForAI
    this.errorMessage = errorMessage
    this.startIndex = startIndex
    this.exhausted = exhausted
  }
}

// 单个搜索结果项
export class SearchResultItem {
  title: string = ''
  url: string = ''
  snippet: string = ''

  constructor(title: string, url: string, snippet: string) {
    this.title = title
    this.url = url
    this.snippet = snippet
  }
}

// 网页搜索结果类
export class WebSearchResult {
  success: boolean = false
  url: string = ''
  title: string = ''
  content: string = ''
  errorMessage: string = ''
  searchResults: SearchResultItem[] = []
  sourceName: string = ''

  constructor(success: boolean, url: string, title: string, content: string, errorMessage: string,
    searchResults?: SearchResultItem[], sourceName: string = '') {
    this.success = success
    this.url = url
    this.title = title
    this.content = content
    this.errorMessage = errorMessage
    this.sourceName = sourceName
    if (searchResults !== undefined) {
      this.searchResults = searchResults
    }
  }
}

// 运行时配置快照：单次搜索链路内复用，避免重复读取偏好设置
export class SearchRuntimeConfigSnapshot {
  enabled: boolean = true
  searchEngine: SearchEngine = SearchEngine.BING
  maxResults: number = 10
  timeout: number = 5000
  autoTestConnection: boolean = true
  braveApiKey: string = ''
  tavilyApiKey: string = ''
  tavilyBaseUrl: string = 'https://api.tavily.com'
  exaApiKey: string = ''
  exaBaseUrl: string = 'https://api.exa.ai'
  bochaApiKey: string = ''
  bochaBaseUrl: string = 'https://api.bochaai.com'
  deepseekUseCurrentProvider: boolean = true
  deepseekApiKey: string = ''
  deepseekBaseUrl: string = DEEPSEEK_WEB_SEARCH_DEFAULT_BASE_URL
}

// 搜索执行选项（可选）
export interface WebSearchExecutionOptions {
  requestId?: string
  runtimeConfig?: SearchRuntimeConfigSnapshot
  cancelCheck?: () => boolean
  page?: number
}

// HTML 解析结果类
class HtmlParseResult {
  title: string = ''
  content: string = ''

  constructor(title: string, content: string) {
    this.title = title
    this.content = content
  }
}

// Bing 搜索结果类（内部使用）
class BingSearchResponse {
  success: boolean = false
  query: string = ''
  results: SearchResultItem[] = []
  errorMessage: string = ''

  constructor(success: boolean, query: string, results: SearchResultItem[], errorMessage: string) {
    this.success = success
    this.query = query
    this.results = results
    this.errorMessage = errorMessage
  }
}

// Bing 结果相关性判定结果
class BingRelevanceVerdict {
  relevant: boolean
  filtered: SearchResultItem[]

  constructor(relevant: boolean, filtered: SearchResultItem[]) {
    this.relevant = relevant
    this.filtered = filtered
  }
}

class ExaSearchTextConfig {
  maxCharacters: number = 2500
}

class ExaSearchContentsConfig {
  text: ExaSearchTextConfig = new ExaSearchTextConfig()
}

class ExaSearchRequest {
  query: string = ''
  type: string = 'auto'
  numResults: number = 10
  contents: ExaSearchContentsConfig = new ExaSearchContentsConfig()

  constructor(query: string, numResults: number) {
    this.query = query
    this.numResults = numResults
  }
}

class BochaSearchRequest {
  query: string = ''
  summary: boolean = true
  count: number = 10
  freshness: string = 'noLimit'

  constructor(query: string, count: number) {
    this.query = query
    this.count = count
  }
}

class DeepSeekSearchTextContent {
  type: string = 'text'
  text: string = ''

  constructor(text: string) {
    this.text = text
  }
}

class DeepSeekSearchMessage {
  role: string = 'user'
  content: DeepSeekSearchTextContent[] = []

  constructor(text: string) {
    this.content = [new DeepSeekSearchTextContent(text)]
  }
}

class DeepSeekSearchTool {
  type: string = 'web_search_20250305'
  name: string = 'web_search'
  max_uses: number = DEEPSEEK_WEB_SEARCH_MAX_USES
}

class DeepSeekSearchRequest {
  model: string = DEEPSEEK_WEB_SEARCH_DEFAULT_MODEL
  max_tokens: number = DEEPSEEK_WEB_SEARCH_MAX_TOKENS
  messages: DeepSeekSearchMessage[] = []
  tools: DeepSeekSearchTool[] = [new DeepSeekSearchTool()]

  constructor(query: string) {
    this.messages = [new DeepSeekSearchMessage(`Perform a web search for the query: ${query}`)]
  }
}

class TavilyExtractRequest {
  urls: string[] = []
  extract_depth: string = 'basic'
  format: string = 'markdown'
  include_images: boolean = false
  timeout: number = 10

  constructor(url: string, extractDepth: string, timeoutSeconds: number) {
    this.urls = [url]
    this.extract_depth = extractDepth
    this.timeout = timeoutSeconds
  }
}

class RequestControllerEntry {
  controller: HttpRequestController
  refCount: number = 1

  constructor(controller: HttpRequestController) {
    this.controller = controller
  }
}

export class WebSearchService {
  private static instance: WebSearchService | null = null
  private httpService: HttpService

  // 保留旧字段，兼容现有调用方
  private config: SearchServiceConfig = new SearchServiceConfig()
  private braveApiKey: string = ''
  private tavilyApiKey: string = ''
  private exaApiKey: string = ''
  private exaBaseUrl: string = 'https://api.exa.ai'
  private bochaApiKey: string = ''
  private bochaBaseUrl: string = 'https://api.bochaai.com'
  private deepseekApiKey: string = ''
  private deepseekBaseUrl: string = DEEPSEEK_WEB_SEARCH_DEFAULT_BASE_URL

  private requestControllerMap: Map<string, RequestControllerEntry> = new Map()
  // 记录本次用户请求已返回过的 URL，用于跨查询、跨页去重（新用户消息时清空）
  private returnedUrlsInCurrentRequest: Set<string> = new Set()
  private returnedDomainsInCurrentRequest: Set<string> = new Set()

  // 中文字典/百科类域名：Bing 拆词噪声（多字词被拆成首字）通常落在这些站点
  private readonly cjkDictionaryDomains: string[] = [
    'baike.baidu.com', 'hanyuguoxue.com', 'hancibao.com', 'zdic.net',
    'zd.hwxnet.com', 'hwxnet.com', 'qianp.com', 'guoxuedashi.net',
    'zidian', 'cidian'
  ]

  private constructor() {
    this.httpService = getHttpService()
  }

  static getInstance(): WebSearchService {
    if (WebSearchService.instance === null) {
      WebSearchService.instance = new WebSearchService()
    }
    return WebSearchService.instance
  }

  private normalizeBaseUrl(raw: string, fallback: string): string {
    const trimmed = raw.trim()
    if (trimmed === '') {
      return fallback
    }
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1)
    }
    return trimmed
  }

  private parseSearchEngine(raw: string): SearchEngine {
    if (raw === SearchEngine.BRAVE) {
      return SearchEngine.BRAVE
    }
    if (raw === SearchEngine.TAVILY) {
      return SearchEngine.TAVILY
    }
    if (raw === SearchEngine.EXA) {
      return SearchEngine.EXA
    }
    if (raw === SearchEngine.BOCHA) {
      return SearchEngine.BOCHA
    }
    if (raw === SearchEngine.DEEPSEEK) {
      return SearchEngine.DEEPSEEK
    }
    if (raw === SearchEngine.CUSTOM) {
      return SearchEngine.CUSTOM
    }
    return SearchEngine.BING
  }

  private normalizeTimeout(raw: number): number {
    if (raw <= 0) {
      return 5000
    }
    if (raw > 60000) {
      return 60000
    }
    return raw
  }

  private normalizeResultCount(raw: number): number {
    if (raw <= 0) {
      return 10
    }
    if (raw > 20) {
      return 20
    }
    return raw
  }

  private normalizeSearchPage(raw: number | undefined): number {
    if (raw === undefined || raw <= 1) {
      return 1
    }
    if (raw > 10) {
      return 10
    }
    return Math.floor(raw)
  }

  private getSearchStartIndex(resultCount: number, page: number): number {
    const normalizedPage = this.normalizeSearchPage(page)
    return (normalizedPage - 1) * this.normalizeResultCount(resultCount) + 1
  }

  private applyRuntimeConfig(snapshot: SearchRuntimeConfigSnapshot): void {
    this.config.enabled = snapshot.enabled
    this.config.searchEngine = snapshot.searchEngine
    this.config.maxResults = snapshot.maxResults
    this.config.timeout = snapshot.timeout
    this.config.autoTestConnection = snapshot.autoTestConnection
    this.braveApiKey = snapshot.braveApiKey
    this.tavilyApiKey = snapshot.tavilyApiKey
    this.exaApiKey = snapshot.exaApiKey
    this.exaBaseUrl = snapshot.exaBaseUrl
    this.bochaApiKey = snapshot.bochaApiKey
    this.bochaBaseUrl = snapshot.bochaBaseUrl
    this.deepseekApiKey = snapshot.deepseekApiKey
    this.deepseekBaseUrl = snapshot.deepseekBaseUrl
  }

  // 加载搜索服务配置（旧接口，保留）
  async loadConfig(): Promise<void> {
    const runtime = await this.getRuntimeConfigSnapshot()
    this.applyRuntimeConfig(runtime)
  }

  // 获取单次搜索链路可复用的配置快照
  async getRuntimeConfigSnapshot(): Promise<SearchRuntimeConfigSnapshot> {
    const prefsService = getPreferencesService()
    const snapshot = new SearchRuntimeConfigSnapshot()

    const enabled = await prefsService.getBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, false)
    const engine = await prefsService.getString(PreferenceKeys.SEARCH_ENGINE, 'bing')
    const maxResults = await prefsService.getNumber(PreferenceKeys.SEARCH_MAX_RESULTS, 10)
    const timeout = await prefsService.getNumber(PreferenceKeys.SEARCH_TIMEOUT, 5000)
    const autoTest = await prefsService.getBoolean(PreferenceKeys.SEARCH_AUTO_TEST, true)
    const braveApiKey = await prefsService.getString(PreferenceKeys.SEARCH_BRAVE_API_KEY, '')
    const tavilyApiKey = await prefsService.getString(PreferenceKeys.SEARCH_TAVILY_API_KEY, '')
    const tavilyBaseUrl =
      await prefsService.getString(PreferenceKeys.SEARCH_TAVILY_BASE_URL, 'https://api.tavily.com')
    const exaApiKey = await prefsService.getString(PreferenceKeys.SEARCH_EXA_API_KEY, '')
    const exaBaseUrl = await prefsService.getString(PreferenceKeys.SEARCH_EXA_BASE_URL, 'https://api.exa.ai')
    const bochaApiKey = await prefsService.getString(PreferenceKeys.SEARCH_BOCHA_API_KEY, '')
    const bochaBaseUrl = await prefsService.getString(PreferenceKeys.SEARCH_BOCHA_BASE_URL, 'https://api.bochaai.com')
    const deepseekUseCurrentProvider = await prefsService.getBoolean(
      PreferenceKeys.SEARCH_DEEPSEEK_USE_CURRENT_PROVIDER,
      true
    )
    const deepseekApiKey = await prefsService.getString(PreferenceKeys.SEARCH_DEEPSEEK_API_KEY, '')
    const deepseekBaseUrl = await prefsService.getString(
      PreferenceKeys.SEARCH_DEEPSEEK_BASE_URL,
      DEEPSEEK_WEB_SEARCH_DEFAULT_BASE_URL
    )

    snapshot.enabled = enabled
    snapshot.searchEngine = this.parseSearchEngine(engine)
    snapshot.maxResults = this.normalizeResultCount(maxResults)
    snapshot.timeout = this.normalizeTimeout(timeout)
    snapshot.autoTestConnection = autoTest
    snapshot.braveApiKey = braveApiKey.trim()
    snapshot.tavilyApiKey = tavilyApiKey.trim()
    snapshot.tavilyBaseUrl = this.normalizeBaseUrl(tavilyBaseUrl, 'https://api.tavily.com')
    snapshot.exaApiKey = exaApiKey.trim()
    snapshot.exaBaseUrl = this.normalizeBaseUrl(exaBaseUrl, 'https://api.exa.ai')
    snapshot.bochaApiKey = bochaApiKey.trim()
    snapshot.bochaBaseUrl = this.normalizeBaseUrl(bochaBaseUrl, 'https://api.bochaai.com')
    snapshot.deepseekUseCurrentProvider = deepseekUseCurrentProvider
    snapshot.deepseekApiKey = deepseekUseCurrentProvider
      ? (snapshot.searchEngine === SearchEngine.DEEPSEEK ? await this.resolveCurrentDeepSeekProviderApiKey() : '')
      : deepseekApiKey.trim()
    snapshot.deepseekBaseUrl = deepseekUseCurrentProvider
      ? DEEPSEEK_WEB_SEARCH_DEFAULT_BASE_URL
      : this.normalizeBaseUrl(deepseekBaseUrl, DEEPSEEK_WEB_SEARCH_DEFAULT_BASE_URL)

    // 同步到旧字段，兼容依赖 this.config 的现有逻辑
    this.applyRuntimeConfig(snapshot)
    return snapshot
  }

  private resolvePreferredEngineName(runtime: SearchRuntimeConfigSnapshot): string {
    if (runtime.searchEngine === SearchEngine.BRAVE) {
      return 'Brave Search'
    }
    if (runtime.searchEngine === SearchEngine.TAVILY) {
      return 'Tavily'
    }
    if (runtime.searchEngine === SearchEngine.EXA && runtime.exaApiKey !== '') {
      return 'Exa'
    }
    if (runtime.searchEngine === SearchEngine.BOCHA && runtime.bochaApiKey !== '') {
      return '博查(Bocha)'
    }
    if (runtime.searchEngine === SearchEngine.DEEPSEEK) {
      return 'DeepSeek Web Search'
    }
    return 'Bing(local)'
  }

  private async resolveCurrentDeepSeekProviderApiKey(): Promise<string> {
    const providerId = await getPreferencesService().getCurrentProviderId()
    if (providerId === '') {
      return ''
    }
    const providers = await getDatabaseService().getAllProviders()
    for (let i = 0; i < providers.length; i++) {
      const provider: ProviderConfig = providers[i]
      if (provider.id === providerId && isDeepSeekProvider(provider.id, provider.type, provider.baseUrl)) {
        return getEffectiveApiKey(provider.id, provider.apiKey).trim()
      }
    }
    return ''
  }

  async getPreferredEngineName(runtimeConfig?: SearchRuntimeConfigSnapshot): Promise<string> {
    const runtime = runtimeConfig !== undefined ? runtimeConfig : await this.getRuntimeConfigSnapshot()
    return this.resolvePreferredEngineName(runtime)
  }

  private acquireRequestController(requestId: string): HttpRequestController | null {
    if (requestId === '') {
      return null
    }

    const existing = this.requestControllerMap.get(requestId)
    if (existing !== undefined) {
      existing.refCount += 1
      return existing.controller
    }

    const controller = new HttpRequestController()
    this.requestControllerMap.set(requestId, new RequestControllerEntry(controller))
    return controller
  }

  private releaseRequestController(requestId: string): void {
    if (requestId === '') {
      return
    }

    const existing = this.requestControllerMap.get(requestId)
    if (existing === undefined) {
      return
    }

    existing.refCount -= 1
    if (existing.refCount <= 0) {
      this.requestControllerMap.delete(requestId)
    }
  }

  cancelRequest(requestId: string): void {
    if (requestId === '') {
      return
    }
    const existing = this.requestControllerMap.get(requestId)
    if (existing === undefined) {
      return
    }
    existing.controller.cancelAll()
    this.requestControllerMap.delete(requestId)
  }

  cancelAllRequests(): void {
    this.requestControllerMap.forEach((entry: RequestControllerEntry) => {
      entry.controller.cancelAll()
    })
    this.requestControllerMap.clear()
  }

  // 重置搜索结果去重状态（每次新用户消息时调用，与 ToolExecutionService 的 page 计数生命周期对齐）
  resetSearchResultDedup(): void {
    this.returnedUrlsInCurrentRequest.clear()
    this.returnedDomainsInCurrentRequest.clear()
  }

  private normalizeResultUrlForDedup(url: string): string {
    let normalized = url.trim()
    if (normalized === '') {
      return ''
    }

    const hashIndex = normalized.indexOf('#')
    if (hashIndex >= 0) {
      normalized = normalized.substring(0, hashIndex)
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1)
    }
    if (normalized.startsWith('https://')) {
      normalized = normalized.substring(8)
    } else if (normalized.startsWith('http://')) {
      normalized = normalized.substring(7)
    }
    return normalized.toLowerCase()
  }

  private extractDomainForDedup(url: string): string {
    let normalized = url.trim()
    if (normalized === '') {
      return ''
    }
    if (normalized.startsWith('https://')) {
      normalized = normalized.substring(8)
    } else if (normalized.startsWith('http://')) {
      normalized = normalized.substring(7)
    }
    const slashIndex = normalized.indexOf('/')
    if (slashIndex >= 0) {
      normalized = normalized.substring(0, slashIndex)
    }
    const questionIndex = normalized.indexOf('?')
    if (questionIndex >= 0) {
      normalized = normalized.substring(0, questionIndex)
    }
    const colonIndex = normalized.indexOf(':')
    if (colonIndex >= 0) {
      normalized = normalized.substring(0, colonIndex)
    }
    if (normalized.startsWith('www.')) {
      normalized = normalized.substring(4)
    }
    return normalized.toLowerCase()
  }

  private buildSeenDomainExclusion(maxCount: number = 4): string {
    const parts: string[] = []
    this.returnedDomainsInCurrentRequest.forEach((domain: string) => {
      if (parts.length >= maxCount) {
        return
      }
      if (domain !== '' && !domain.includes('bing.com')) {
        parts.push(`-site:${domain}`)
      }
    })
    return parts.join(' ')
  }

  // 本轮请求全局去重：过滤掉已通过任意查询返回过的 URL，并把新 URL 记入集合
  private dedupeSearchResult(result: SearchResult): SearchResult {
    if (!result.success || result.references.length === 0) {
      return result
    }

    const freshReferences: SearchReference[] = []
    for (let i = 0; i < result.references.length; i++) {
      const ref = result.references[i]
      const urlKey = this.normalizeResultUrlForDedup(ref.url)
      if (urlKey !== '' && this.returnedUrlsInCurrentRequest.has(urlKey)) {
        continue
      }
      if (urlKey !== '') {
        this.returnedUrlsInCurrentRequest.add(urlKey)
        const domain = this.extractDomainForDedup(ref.url)
        if (domain !== '') {
          this.returnedDomainsInCurrentRequest.add(domain)
        }
      }
      freshReferences.push(ref)
    }

    // 全部都是旧结果 → 标记枯竭，返回空结果让上层提示模型换词/停止
    if (freshReferences.length === 0) {
      return new SearchResult(true, result.query, result.searchEngine, [], '', '', result.startIndex, true)
    }

    // 有部分新结果：用去重后的 references 重建供 AI 的内容，避免把旧结果再喂给模型
    const dedupedItems: SearchResultItem[] = []
    for (let i = 0; i < freshReferences.length; i++) {
      const ref = freshReferences[i]
      dedupedItems.push(new SearchResultItem(ref.title, ref.url, ref.snippet))
    }
    const contentForAI = this.limitPromptContent(this.buildContentForAI(dedupedItems), 6000)
    return new SearchResult(
      true,
      result.query,
      result.searchEngine,
      freshReferences,
      contentForAI,
      '',
      result.startIndex,
      false
    )
  }

  private isCancelled(controller: HttpRequestController | null, cancelCheck?: () => boolean): boolean {
    if (controller !== null && controller.isCancelled()) {
      return true
    }
    if (cancelCheck !== undefined && cancelCheck()) {
      if (controller !== null) {
        controller.cancelAll()
      }
      return true
    }
    return false
  }

  private buildHttpOptions(timeout: number, controller: HttpRequestController | null): HttpRequestRuntimeOptions {
    const options: HttpRequestRuntimeOptions = { timeout: this.normalizeTimeout(timeout) }
    if (controller !== null) {
      options.controller = controller
    }
    return options
  }

  private buildCancelledSearchResult(query: string, engineName: string): SearchResult {
    return new SearchResult(
      false,
      query,
      engineName,
      [],
      '',
      '请求已取消'
    )
  }

  private buildCancelledWebResult(url: string): WebSearchResult {
    return new WebSearchResult(false, url, '', '', '请求已取消')
  }

  private async searchWithRuntime(
    query: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean,
    page: number = 1
  ): Promise<SearchResult> {
    if (runtime.searchEngine === SearchEngine.EXA) {
      const exaResult = await this.exaSearchEnhanced(query, runtime, controller, cancelCheck, page)
      if (exaResult.success) {
        return exaResult
      }
      if (this.isCancelled(controller, cancelCheck)) {
        return this.buildCancelledSearchResult(query, 'Exa')
      }
      console.warn('WebSearchService', `[Exa] Failed, fallback to Bing: ${exaResult.errorMessage}`)
      const bingFallback = await this.bingSearchEnhanced(query, runtime, controller, cancelCheck, page)
      return bingFallback.success ? bingFallback : exaResult
    }
    if (runtime.searchEngine === SearchEngine.BRAVE) {
      return await this.braveSearchEnhanced(query, runtime, controller, cancelCheck, page)
    }
    if (runtime.searchEngine === SearchEngine.TAVILY) {
      return await this.tavilySearchEnhanced(query, runtime, controller, cancelCheck, page)
    }
    if (runtime.searchEngine === SearchEngine.BOCHA) {
      // 博查失败不回退 Bing，直接返回错误，让用户明确是 Key/配额/网络问题
      return await this.bochaSearchEnhanced(query, runtime, controller, cancelCheck, page)
    }
    if (runtime.searchEngine === SearchEngine.DEEPSEEK) {
      return await this.deepSeekSearchEnhanced(query, runtime, controller, cancelCheck, page)
    }
    return await this.bingSearchEnhanced(query, runtime, controller, cancelCheck, page)
  }

  private buildFreshResultRetryQueries(originalQuery: string, effectiveQuery: string, page: number): string[] {
    const candidates: string[] = []
    this.pushUniqueCandidate(candidates, effectiveQuery)
    const seenDomainExclusion = this.buildSeenDomainExclusion()

    for (let i = 1; i <= 6; i++) {
      this.pushUniqueCandidate(candidates, this.buildDiversifiedSearchQuery(originalQuery, page + i))
      this.pushUniqueCandidate(candidates, this.buildDiversifiedSearchQuery(effectiveQuery, page + i))
      if (seenDomainExclusion !== '') {
        this.pushUniqueCandidate(candidates, `${this.buildDiversifiedSearchQuery(originalQuery, page + i)} ${seenDomainExclusion}`)
        this.pushUniqueCandidate(candidates, `${this.buildDiversifiedSearchQuery(effectiveQuery, page + i)} ${seenDomainExclusion}`)
      }
    }

    const filtered: string[] = []
    for (let i = 0; i < candidates.length; i++) {
      if (candidates[i] !== effectiveQuery) {
        filtered.push(candidates[i])
      }
    }
    return filtered
  }

  // 统一搜索接口
  async search(query: string, options?: WebSearchExecutionOptions): Promise<SearchResult> {
    const runtime = options?.runtimeConfig !== undefined ? options.runtimeConfig : await this.getRuntimeConfigSnapshot()
    const requestId = options?.requestId !== undefined ? options.requestId : ''
    const cancelCheck = options?.cancelCheck
    const page = this.normalizeSearchPage(options?.page)
    const controller = this.acquireRequestController(requestId)

    try {
      if (this.isCancelled(controller, cancelCheck)) {
        return this.buildCancelledSearchResult(query, this.resolvePreferredEngineName(runtime))
      }

      if (!runtime.enabled) {
        return new SearchResult(false, query, this.resolvePreferredEngineName(runtime), [], '', '搜索服务未启用')
      }

      const cleanedQuery = cleanSearchQueryShared(query)
      if (cleanedQuery !== query) {
        console.info('WebSearchService', `Search query cleaned: "${query}" -> "${cleanedQuery}"`)
      }

      // 天气类查询：强制使用更可解析/更权威站点，避免结果被“查/查重/天眼查”等噪声污染
      let finalQuery = cleanedQuery
      const weatherIntentForRewrite = this.isWeatherIntent(cleanedQuery)
      if (weatherIntentForRewrite) {
        finalQuery = this.buildWeatherSiteQuery(cleanedQuery)
        if (finalQuery !== cleanedQuery) {
          console.info('WebSearchService', `Weather query rewritten: "${cleanedQuery}" -> "${finalQuery}"`)
        }
      }
      if (page > 1 && runtime.searchEngine === SearchEngine.BING && !weatherIntentForRewrite) {
        const diversifiedQuery = this.buildRepeatedBingSearchQuery(finalQuery, page)
        if (diversifiedQuery !== finalQuery) {
          console.info('WebSearchService', `Repeated Bing query diversified(page=${page}): "${finalQuery}" -> "${diversifiedQuery}"`)
          finalQuery = diversifiedQuery
        }
      }

      if (this.isCancelled(controller, cancelCheck)) {
        return this.buildCancelledSearchResult(finalQuery, this.resolvePreferredEngineName(runtime))
      }

      const result = await this.searchWithRuntime(finalQuery, runtime, controller, cancelCheck, page)
      const dedupedResult = this.dedupeSearchResult(result)
      if (!dedupedResult.success || weatherIntentForRewrite) {
        return dedupedResult
      }
      if (!dedupedResult.exhausted && dedupedResult.references.length > 0) {
        return dedupedResult
      }

      // DeepSeek 的一次请求已允许服务器侧多次检索；空结果不再自动追加昂贵的模型轮次。
      if (runtime.searchEngine === SearchEngine.DEEPSEEK) {
        return dedupedResult
      }

      // 如果当前关键词无结果，或只返回了本轮已见过的 URL，主动换搜索角度补搜，避免把空结果交给模型。
      const retryQueries = this.buildFreshResultRetryQueries(cleanedQuery, finalQuery, page)
      const maxRetryCount = Math.min(retryQueries.length, 5)
      for (let i = 0; i < maxRetryCount; i++) {
        if (this.isCancelled(controller, cancelCheck)) {
          return this.buildCancelledSearchResult(finalQuery, this.resolvePreferredEngineName(runtime))
        }
        const retryQuery = retryQueries[i]
        console.info('WebSearchService', `Search result duplicated, retrying with query: "${retryQuery}"`)
        const retryResult = await this.searchWithRuntime(retryQuery, runtime, controller, cancelCheck, 1)
        const retryDeduped = this.dedupeSearchResult(retryResult)
        if (retryDeduped.success && !retryDeduped.exhausted && retryDeduped.references.length > 0) {
          return retryDeduped
        }
      }

      return dedupedResult
    } finally {
      this.releaseRequestController(requestId)
    }
  }

  private async bingSearchEnhanced(
    query: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean,
    page: number = 1
  ): Promise<SearchResult> {
    const response = await this.bingSearchInternal(query, runtime.maxResults, runtime, controller, cancelCheck, page)

    if (!response.success) {
      return new SearchResult(
        false,
        query,
        'Bing(local)',
        [],
        '',
        response.errorMessage
      )
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledSearchResult(query, 'Bing(local)')
    }

    const weatherIntent = this.isWeatherIntent(query)

    // 天气类查询：如果强制站点仍然无结果，回退到备用站点再搜一次
    let effectiveResponse = response
    if (effectiveResponse.results.length === 0 && weatherIntent) {
      const fallbackQuery = this.buildWeatherFallbackQuery(query)
      if (fallbackQuery !== '' && fallbackQuery !== query) {
        const fallbackResp = await this.bingSearchInternal(fallbackQuery, runtime.maxResults, runtime, controller, cancelCheck, page)
        if (fallbackResp.success && fallbackResp.results.length > 0) {
          effectiveResponse = fallbackResp
        }
      }
    }

    // 相关性校验：Bing 会把生僻中文多字词拆成首字返回字典/百科噪声（如"忆张师"→"忆"），
    // 识别这种拆词噪声并诚实返回，避免用无关结果误导模型。
    if (!weatherIntent) {
      const relevance = this.assessBingResultRelevance(query, effectiveResponse.results)
      if (!relevance.relevant) {
        const tip = `未找到「${query}」的相关网页结果，该词可能是生僻或冷门实体；请勿编造，可补充上下文（如人物所属领域/作品/机构）后重试，或在设置中改用博查(Bocha)/Tavily 等中文检索引擎。`
        return new SearchResult(
          true,
          effectiveResponse.query,
          'Bing(local)',
          [],
          tip,
          '',
          this.getSearchStartIndex(runtime.maxResults, page),
          true
        )
      }
      if (relevance.filtered.length !== effectiveResponse.results.length) {
        console.info('WebSearchService', `Bing relevance filter kept ${relevance.filtered.length}/${effectiveResponse.results.length} result(s) for "${query}"`)
        effectiveResponse = new BingSearchResponse(true, effectiveResponse.query, relevance.filtered, '')
      }
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledSearchResult(query, 'Bing(local)')
    }

    // 天气/实时数据类问题：抓取网页正文摘要供模型提取数值
    let enriched = ''
    if (weatherIntent && effectiveResponse.results.length > 0) {
      enriched = await this.enrichTopPagesForAI(effectiveResponse.results, 2, runtime, controller, cancelCheck)
      if (enriched === '') {
        const fallbackQuery = this.buildWeatherFallbackQuery(effectiveResponse.query)
        if (fallbackQuery !== '' && fallbackQuery !== effectiveResponse.query) {
          const fallbackResp = await this.bingSearchInternal(fallbackQuery, runtime.maxResults, runtime, controller, cancelCheck, page)
          if (fallbackResp.success && fallbackResp.results.length > 0) {
            effectiveResponse = fallbackResp
            enriched = await this.enrichTopPagesForAI(effectiveResponse.results, 2, runtime, controller, cancelCheck)
          }
        }
      }
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledSearchResult(query, 'Bing(local)')
    }

    const references: SearchReference[] = []
    for (let i = 0; i < effectiveResponse.results.length; i++) {
      const item = effectiveResponse.results[i]
      references.push(new SearchReference(
        `ref_${Date.now()}_${i}`,
        item.title,
        item.url,
        item.snippet
      ))
    }

    let contentForAI = this.buildContentForAI(effectiveResponse.results)

    if (weatherIntent && enriched !== '') {
      contentForAI += '\n' + enriched
    }

    contentForAI = this.limitPromptContent(contentForAI, 6000)

    return new SearchResult(
      true,
      effectiveResponse.query,
      'Bing(local)',
      references,
      contentForAI,
      '',
      this.getSearchStartIndex(runtime.maxResults, page)
    )
  }

  private async exaSearchEnhanced(
    query: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean,
    page: number = 1
  ): Promise<SearchResult> {
    if (runtime.exaApiKey === '') {
      return new SearchResult(
        false,
        query,
        'Exa',
        [],
        '',
        'Exa API Key 未配置'
      )
    }

    // Exa 无原生分页：翻页时改写查询词制造差异（天气类已在 search() 做过 site 改写，这里跳过避免污染）
    const effectiveQuery = page > 1 && !this.isWeatherIntent(query)
      ? this.buildDiversifiedSearchQuery(query, page)
      : query

    const response = await this.exaSearch(effectiveQuery, runtime.maxResults, runtime, controller, cancelCheck)
    if (!response.success) {
      return new SearchResult(
        false,
        effectiveQuery,
        'Exa',
        [],
        '',
        response.errorMessage
      )
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledSearchResult(effectiveQuery, 'Exa')
    }

    const references: SearchReference[] = []
    for (let i = 0; i < response.results.length; i++) {
      const item = response.results[i]
      references.push(new SearchReference(
        `ref_${Date.now()}_${i}`,
        item.title,
        item.url,
        item.snippet
      ))
    }

    const contentForAI = this.limitPromptContent(this.buildContentForAI(response.results), 6000)
    return new SearchResult(
      true,
      effectiveQuery,
      'Exa',
      references,
      contentForAI,
      '',
      this.getSearchStartIndex(runtime.maxResults, page)
    )
  }

  private async deepSeekSearchEnhanced(
    query: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean,
    page: number = 1
  ): Promise<SearchResult> {
    if (runtime.deepseekApiKey === '') {
      const message = runtime.deepseekUseCurrentProvider
        ? '当前聊天未选择已配置 API Key 的 DeepSeek 服务商；请切换到 DeepSeek 服务商，或在搜索设置中改为手动配置'
        : 'DeepSeek Web Search API Key 未配置'
      return new SearchResult(false, query, 'DeepSeek Web Search', [], '', message)
    }

    const effectiveQuery = page > 1 && !this.isWeatherIntent(query)
      ? this.buildDiversifiedSearchQuery(query, page)
      : query
    const response = await this.deepSeekSearch(effectiveQuery, runtime, controller, cancelCheck)
    if (!response.success) {
      return new SearchResult(false, effectiveQuery, 'DeepSeek Web Search', [], '', response.errorMessage)
    }
    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledSearchResult(effectiveQuery, 'DeepSeek Web Search')
    }

    const references: SearchReference[] = []
    for (let i = 0; i < response.results.length; i++) {
      const item = response.results[i]
      references.push(new SearchReference(`ref_${Date.now()}_${i}`, item.title, item.url, item.snippet))
    }
    return new SearchResult(
      true,
      effectiveQuery,
      'DeepSeek Web Search',
      references,
      this.limitPromptContent(this.buildContentForAI(response.results), 6000),
      '',
      this.getSearchStartIndex(runtime.maxResults, page),
      references.length === 0
    )
  }

  private async bochaSearchEnhanced(
    query: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean,
    page: number = 1
  ): Promise<SearchResult> {
    if (runtime.bochaApiKey === '') {
      return new SearchResult(
        false,
        query,
        '博查(Bocha)',
        [],
        '',
        '博查 API Key 未配置'
      )
    }

    // 博查无原生分页：翻页时改写查询词制造差异（天气类已在 search() 做过 site 改写，这里跳过避免污染）
    const effectiveQuery = page > 1 && !this.isWeatherIntent(query)
      ? this.buildDiversifiedSearchQuery(query, page)
      : query

    const response = await this.bochaSearch(effectiveQuery, runtime.maxResults, runtime, controller, cancelCheck)
    if (!response.success) {
      return new SearchResult(
        false,
        effectiveQuery,
        '博查(Bocha)',
        [],
        '',
        response.errorMessage
      )
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledSearchResult(effectiveQuery, '博查(Bocha)')
    }

    const references: SearchReference[] = []
    for (let i = 0; i < response.results.length; i++) {
      const item = response.results[i]
      references.push(new SearchReference(
        `ref_${Date.now()}_${i}`,
        item.title,
        item.url,
        item.snippet
      ))
    }

    return new SearchResult(
      true,
      effectiveQuery,
      '博查(Bocha)',
      references,
      this.limitPromptContent(this.buildContentForAI(response.results), 6000),
      '',
      this.getSearchStartIndex(runtime.maxResults, page)
    )
  }

  private async braveSearchEnhanced(
    query: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean,
    page: number = 1
  ): Promise<SearchResult> {
    if (runtime.braveApiKey === '') {
      return new SearchResult(
        false,
        query,
        'Brave Search',
        [],
        '',
        'Brave API Key 未配置'
      )
    }

    const response = await this.braveSearch(query, runtime.maxResults, runtime, controller, cancelCheck, page)
    if (!response.success) {
      return new SearchResult(
        false,
        query,
        'Brave Search',
        [],
        '',
        response.errorMessage
      )
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledSearchResult(query, 'Brave Search')
    }

    const references: SearchReference[] = []
    for (let i = 0; i < response.results.length; i++) {
      const item = response.results[i]
      references.push(new SearchReference(
        `ref_${Date.now()}_${i}`,
        item.title,
        item.url,
        item.snippet
      ))
    }

    return new SearchResult(
      true,
      query,
      'Brave Search',
      references,
      this.limitPromptContent(this.buildContentForAI(response.results), 6000),
      '',
      this.getSearchStartIndex(runtime.maxResults, page)
    )
  }

  private async tavilySearchEnhanced(
    query: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean,
    page: number = 1
  ): Promise<SearchResult> {
    if (runtime.tavilyApiKey === '') {
      return new SearchResult(
        false,
        query,
        'Tavily',
        [],
        '',
        'Tavily API Key 未配置'
      )
    }

    // Tavily 无原生分页：翻页时改写查询词制造差异（天气类已在 search() 做过 site 改写，这里跳过避免污染）
    const effectiveQuery = page > 1 && !this.isWeatherIntent(query)
      ? this.buildDiversifiedSearchQuery(query, page)
      : query

    const response = await this.tavilySearch(effectiveQuery, runtime.maxResults, runtime, controller, cancelCheck)
    if (!response.success) {
      return new SearchResult(
        false,
        effectiveQuery,
        'Tavily',
        [],
        '',
        response.errorMessage
      )
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledSearchResult(effectiveQuery, 'Tavily')
    }

    const references: SearchReference[] = []
    for (let i = 0; i < response.results.length; i++) {
      const item = response.results[i]
      references.push(new SearchReference(
        `ref_${Date.now()}_${i}`,
        item.title,
        item.url,
        item.snippet
      ))
    }

    return new SearchResult(
      true,
      effectiveQuery,
      'Tavily',
      references,
      this.limitPromptContent(this.buildContentForAI(response.results), 6000),
      '',
      this.getSearchStartIndex(runtime.maxResults, page)
    )
  }

  private async braveSearch(
    query: string,
    resultCount: number,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean,
    page: number = 1
  ): Promise<BingSearchResponse> {
    try {
      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      // Brave 的 offset 是页号（0-based，最大 9），配合 count 翻页
      const braveOffset = Math.min(this.normalizeSearchPage(page) - 1, 9)
      const searchUrl =
        `https://api.search.brave.com/res/v1/web/search?q=${encodeURIComponent(query)}&count=${this.normalizeResultCount(resultCount)}&offset=${braveOffset}`
      const response = await this.httpService.get(
        searchUrl,
        {
          'Accept': 'application/json',
          'X-Subscription-Token': runtime.braveApiKey
        },
        this.buildHttpOptions(runtime.timeout, controller)
      )

      if (!response.success) {
        return new BingSearchResponse(false, query, [], response.errorMessage)
      }

      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      const errorMessage = this.extractBraveErrorMessage(response.data)
      if (errorMessage !== '') {
        return new BingSearchResponse(false, query, [], errorMessage)
      }

      return new BingSearchResponse(
        true,
        query,
        this.parseBraveSearchResults(response.data, this.normalizeResultCount(resultCount)),
        ''
      )
    } catch (error) {
      return new BingSearchResponse(false, query, [], `Brave 搜索失败: ${JSON.stringify(error)}`)
    }
  }

  private async tavilySearch(
    query: string,
    resultCount: number,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<BingSearchResponse> {
    try {
      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      const response = await this.httpService.postWithTimeout(
        this.buildTavilyEndpointUrl(runtime.tavilyBaseUrl, 'search'),
        JSON.stringify({
          query: query,
          topic: 'general',
          search_depth: 'basic',
          max_results: this.normalizeResultCount(resultCount),
          include_answer: false,
          include_images: false,
          include_raw_content: false
        }),
        this.buildTavilyHeaders(runtime),
        runtime.timeout,
        this.buildHttpOptions(runtime.timeout, controller)
      )

      if (!response.success) {
        return new BingSearchResponse(false, query, [], response.errorMessage)
      }

      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      const errorMessage = this.extractTavilyErrorMessage(response.data)
      if (errorMessage !== '') {
        return new BingSearchResponse(false, query, [], errorMessage)
      }

      return new BingSearchResponse(
        true,
        query,
        this.parseTavilySearchResults(response.data, this.normalizeResultCount(resultCount)),
        ''
      )
    } catch (error) {
      return new BingSearchResponse(false, query, [], `Tavily 搜索失败: ${JSON.stringify(error)}`)
    }
  }

  private async deepSeekSearch(
    query: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<BingSearchResponse> {
    try {
      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      const timeout = Math.max(this.normalizeTimeout(runtime.timeout), DEEPSEEK_WEB_SEARCH_TIMEOUT_MS)
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'x-api-key': runtime.deepseekApiKey,
        'Authorization': `Bearer ${runtime.deepseekApiKey}`,
        'anthropic-version': '2023-06-01'
      }
      const response = await this.httpService.postWithTimeout(
        buildDeepSeekWebSearchEndpoint(runtime.deepseekBaseUrl),
        JSON.stringify(new DeepSeekSearchRequest(query)),
        headers,
        timeout,
        this.buildHttpOptions(timeout, controller)
      )

      if (!response.success) {
        const detail = extractDeepSeekWebSearchError(response.data)
        const message = detail !== '' ? detail : response.errorMessage
        return new BingSearchResponse(false, query, [], `DeepSeek Web Search 请求失败: ${message}`)
      }
      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      const errorMessage = extractDeepSeekWebSearchError(response.data)
      if (errorMessage !== '') {
        return new BingSearchResponse(false, query, [], errorMessage)
      }
      const parsed = parseDeepSeekWebSearchResponse(response.data, this.normalizeResultCount(runtime.maxResults))
      if (!parsed.hasResultBlock) {
        return new BingSearchResponse(
          false,
          query,
          [],
          'DeepSeek 未返回结构化 web_search_tool_result，请确认接口支持 Anthropic Web Search'
        )
      }

      const results: SearchResultItem[] = []
      for (let i = 0; i < parsed.sources.length; i++) {
        const source = parsed.sources[i]
        results.push(new SearchResultItem(source.title, source.url, source.snippet))
      }
      return new BingSearchResponse(true, query, results, '')
    } catch (error) {
      return new BingSearchResponse(false, query, [], `DeepSeek Web Search 失败: ${JSON.stringify(error)}`)
    }
  }

  private buildTavilyHeaders(runtime: SearchRuntimeConfigSnapshot): Record<string, string> {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': `Bearer ${runtime.tavilyApiKey}`
    }
  }

  private stripKnownTavilyEndpoint(url: string): string {
    const endpoints: string[] = ['/search', '/extract', '/map', '/crawl', '/research', '/usage']
    for (let i = 0; i < endpoints.length; i++) {
      if (url.endsWith(endpoints[i])) {
        return url.substring(0, url.length - endpoints[i].length)
      }
    }
    return url
  }

  private buildTavilyEndpointUrl(baseUrl: string, endpoint: string): string {
    const normalized = this.normalizeBaseUrl(baseUrl, 'https://api.tavily.com')
    const base = this.stripKnownTavilyEndpoint(normalized)
    return `${base}/${endpoint}`
  }

  private getTavilyExtractApiTimeoutSeconds(depth: string): number {
    return depth === 'advanced' ? 30 : 10
  }

  private getTavilyExtractHttpTimeoutMs(runtimeTimeout: number, depth: string): number {
    const apiTimeoutMs = this.getTavilyExtractApiTimeoutSeconds(depth) * 1000
    return Math.max(this.normalizeTimeout(runtimeTimeout), apiTimeoutMs + 5000)
  }

  private async tavilyExtractUrlContent(
    url: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<WebSearchResult> {
    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledWebResult(url)
    }

    if (!this.isValidUrl(url)) {
      return new WebSearchResult(false, url, '', '', 'URL 格式无效')
    }

    const fullUrl = this.normalizeContentUrl(url)
    const basicResult = await this.tavilyExtractUrlContentByDepth(fullUrl, runtime, controller, cancelCheck, 'basic')
    if (basicResult.success || this.isCancelled(controller, cancelCheck) ||
      !this.shouldRetryTavilyExtractWithAdvanced(basicResult.errorMessage)) {
      return basicResult
    }

    console.warn('WebSearchService', `[Tavily Extract] Basic failed, retry advanced: ${basicResult.errorMessage}`)
    const advancedResult = await this.tavilyExtractUrlContentByDepth(
      fullUrl,
      runtime,
      controller,
      cancelCheck,
      'advanced'
    )
    if (advancedResult.success || this.isCancelled(controller, cancelCheck)) {
      return advancedResult
    }

    return new WebSearchResult(
      false,
      fullUrl,
      '',
      '',
      `Tavily Extract basic 失败: ${basicResult.errorMessage}; advanced 失败: ${advancedResult.errorMessage}`,
      undefined,
      'Tavily Extract'
    )
  }

  private async tavilyExtractUrlContentByDepth(
    fullUrl: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck: (() => boolean) | undefined,
    depth: string
  ): Promise<WebSearchResult> {
    try {
      const timeout = this.getTavilyExtractHttpTimeoutMs(runtime.timeout, depth)
      const request = new TavilyExtractRequest(
        fullUrl,
        depth,
        this.getTavilyExtractApiTimeoutSeconds(depth)
      )
      console.info(
        'WebSearchService',
        `[Tavily Extract] POST ${this.buildTavilyEndpointUrl(runtime.tavilyBaseUrl, 'extract')} depth=${depth}`
      )
      const response = await this.httpService.postWithTimeout(
        this.buildTavilyEndpointUrl(runtime.tavilyBaseUrl, 'extract'),
        JSON.stringify(request),
        this.buildTavilyHeaders(runtime),
        timeout,
        this.buildHttpOptions(timeout, controller)
      )

      if (!response.success) {
        return new WebSearchResult(false, fullUrl, '', '', response.errorMessage, undefined, 'Tavily Extract')
      }

      if (this.isCancelled(controller, cancelCheck)) {
        return this.buildCancelledWebResult(fullUrl)
      }

      const errorMessage = this.extractTavilyErrorMessage(response.data)
      if (errorMessage !== '') {
        return new WebSearchResult(false, fullUrl, '', '', errorMessage, undefined, 'Tavily Extract')
      }

      return this.parseTavilyExtractResult(response.data, fullUrl)
    } catch (error) {
      return new WebSearchResult(
        false,
        fullUrl,
        '',
        '',
        `Tavily Extract 失败: ${JSON.stringify(error)}`,
        undefined,
        'Tavily Extract'
      )
    }
  }

  private shouldRetryTavilyExtractWithAdvanced(errorMessage: string): boolean {
    if (errorMessage === '') {
      return true
    }
    const lower = errorMessage.toLowerCase()
    if (lower.includes('401') || lower.includes('403') || lower.includes('api key') ||
      lower.includes('unauthorized') || lower.includes('forbidden') || lower.includes('quota') ||
      lower.includes('credit') || lower.includes('rate limit') || lower.includes('请求已取消')) {
      return false
    }
    return true
  }

  private async exaSearch(
    query: string,
    resultCount: number,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<BingSearchResponse> {
    try {
      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'x-api-key': runtime.exaApiKey
      }

      const request = new ExaSearchRequest(query, this.normalizeResultCount(resultCount))
      const body = JSON.stringify(request)
      const response = await this.httpService.postWithTimeout(
        `${runtime.exaBaseUrl}/search`,
        body,
        headers,
        runtime.timeout,
        this.buildHttpOptions(runtime.timeout, controller)
      )

      if (!response.success) {
        return new BingSearchResponse(false, query, [], response.errorMessage)
      }

      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      const errorMessage = this.extractExaErrorMessage(response.data)
      if (errorMessage !== '') {
        return new BingSearchResponse(false, query, [], errorMessage)
      }

      const results = this.parseExaSearchResults(response.data, this.normalizeResultCount(resultCount))
      return new BingSearchResponse(true, query, results, '')
    } catch (error) {
      return new BingSearchResponse(false, query, [], `Exa 搜索失败: ${JSON.stringify(error)}`)
    }
  }

  private async bochaSearch(
    query: string,
    resultCount: number,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<BingSearchResponse> {
    try {
      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': `Bearer ${runtime.bochaApiKey}`
      }

      const request = new BochaSearchRequest(query, this.normalizeResultCount(resultCount))
      const body = JSON.stringify(request)
      const response = await this.httpService.postWithTimeout(
        `${runtime.bochaBaseUrl}/v1/web-search`,
        body,
        headers,
        runtime.timeout,
        this.buildHttpOptions(runtime.timeout, controller)
      )

      if (!response.success) {
        return new BingSearchResponse(false, query, [], response.errorMessage)
      }

      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      const errorMessage = this.extractBochaErrorMessage(response.data)
      if (errorMessage !== '') {
        return new BingSearchResponse(false, query, [], errorMessage)
      }

      const results = this.parseBochaSearchResults(response.data, this.normalizeResultCount(resultCount))
      return new BingSearchResponse(true, query, results, '')
    } catch (error) {
      return new BingSearchResponse(false, query, [], `博查搜索失败: ${JSON.stringify(error)}`)
    }
  }

  // 博查响应错误：顶层 code 非 200，或 msg/message 含错误信息
  private extractBochaErrorMessage(json: string): string {
    if (json === '') {
      return ''
    }
    try {
      const parsed = JSON.parse(json) as Record<string, Object>
      const code = parsed['code']
      if (typeof code === 'number' && code !== 200) {
        const msg = this.readStringFromObject(parsed, 'msg')
        const message = this.readStringFromObject(parsed, 'message')
        const detail = msg !== '' ? msg : message
        return detail !== '' ? `博查返回错误(code=${code}): ${detail}` : `博查返回错误(code=${code})`
      }
      const error = parsed['error']
      if (error !== undefined && error !== null) {
        if (typeof error === 'string') {
          return error
        }
        if (typeof error === 'object') {
          const errorObj = error as Record<string, Object>
          const message = this.readStringFromObject(errorObj, 'message')
          if (message !== '') {
            return message
          }
          return JSON.stringify(errorObj)
        }
      }
      return ''
    } catch (_error) {
      return ''
    }
  }

  // 解析博查响应：data.webPages.value[]，title=name，snippet 优先 summary 否则 snippet
  private parseBochaSearchResults(json: string, maxCount: number): SearchResultItem[] {
    const results: SearchResultItem[] = []
    if (json === '') {
      return results
    }

    try {
      const parsed = JSON.parse(json) as Record<string, Object>
      const dataValue = parsed['data']
      if (dataValue === undefined || dataValue === null || typeof dataValue !== 'object' || Array.isArray(dataValue)) {
        return results
      }
      const dataObj = dataValue as Record<string, Object>
      const webPages = dataObj['webPages']
      if (webPages === undefined || webPages === null || typeof webPages !== 'object' || Array.isArray(webPages)) {
        return results
      }
      const webPagesObj = webPages as Record<string, Object>
      const valueArray = webPagesObj['value']
      if (valueArray === undefined || valueArray === null || !Array.isArray(valueArray)) {
        return results
      }

      const list = valueArray as Object[]
      for (let i = 0; i < list.length && results.length < maxCount; i++) {
        const item = list[i]
        if (item === null || item === undefined || typeof item !== 'object' || Array.isArray(item)) {
          continue
        }
        const itemObj = item as Record<string, Object>
        const title = this.readStringFromObject(itemObj, 'name').trim()
        const url = this.readStringFromObject(itemObj, 'url').trim()
        const summary = this.readStringFromObject(itemObj, 'summary').trim()
        // 博查 summary 是为 LLM 设计的长摘要，比传统 snippet 信息量大，放宽截断长度以保留其价值
        const rawSnippet = summary !== '' ? summary : this.readStringFromObject(itemObj, 'snippet')
        const snippet = this.normalizeBochaSnippet(rawSnippet)
        if (title === '' || url === '') {
          continue
        }
        results.push(new SearchResultItem(title, url, snippet))
      }
    } catch (error) {
      console.error('WebSearchService', `Parse Bocha results failed: ${JSON.stringify(error)}`)
    }

    return results
  }

  private extractBraveErrorMessage(json: string): string {
    if (json === '') {
      return ''
    }
    try {
      const parsed = JSON.parse(json) as Record<string, Object>
      const error = parsed['error']
      if (error === undefined || error === null) {
        return ''
      }
      if (typeof error === 'string') {
        return error
      }
      if (typeof error === 'object') {
        const errorObj = error as Record<string, Object>
        const message = this.readStringFromObject(errorObj, 'message')
        if (message !== '') {
          return message
        }
        return JSON.stringify(errorObj)
      }
      return JSON.stringify(error)
    } catch (_error) {
      return ''
    }
  }

  private extractTavilyErrorMessage(json: string): string {
    if (json === '') {
      return ''
    }
    try {
      const parsed = JSON.parse(json) as Record<string, Object>
      const detail = parsed['detail']
      if (detail !== undefined && detail !== null) {
        if (typeof detail === 'string') {
          return detail
        }
        return JSON.stringify(detail)
      }
      const message = this.readStringFromObject(parsed, 'message')
      if (message !== '') {
        return message
      }
      const error = parsed['error']
      if (error === undefined || error === null) {
        return ''
      }
      if (typeof error === 'string') {
        return error
      }
      if (typeof error === 'object') {
        const errorObj = error as Record<string, Object>
        const message = this.readStringFromObject(errorObj, 'message')
        if (message !== '') {
          return message
        }
        return JSON.stringify(errorObj)
      }
      return JSON.stringify(error)
    } catch (_error) {
      return ''
    }
  }

  private parseBraveSearchResults(json: string, maxCount: number): SearchResultItem[] {
    const results: SearchResultItem[] = []
    if (json === '') {
      return results
    }

    try {
      const parsed = JSON.parse(json) as Record<string, Object>
      const web = parsed['web']
      if (web === undefined || web === null || typeof web !== 'object' || Array.isArray(web)) {
        return results
      }
      const webObj = web as Record<string, Object>
      const resultsValue = webObj['results']
      if (resultsValue === undefined || resultsValue === null || !Array.isArray(resultsValue)) {
        return results
      }

      const list = resultsValue as Object[]
      for (let i = 0; i < list.length && results.length < maxCount; i++) {
        const item = list[i]
        if (item === null || item === undefined || typeof item !== 'object' || Array.isArray(item)) {
          continue
        }
        const itemObj = item as Record<string, Object>
        const title = this.readStringFromObject(itemObj, 'title').trim()
        const url = this.readStringFromObject(itemObj, 'url').trim()
        const snippet = this.normalizeSnippet(this.readStringFromObject(itemObj, 'description'))
        if (title === '' || url === '') {
          continue
        }
        results.push(new SearchResultItem(title, url, snippet))
      }
    } catch (error) {
      console.error('WebSearchService', `Parse Brave results failed: ${JSON.stringify(error)}`)
    }

    return results
  }

  private parseTavilySearchResults(json: string, maxCount: number): SearchResultItem[] {
    const results: SearchResultItem[] = []
    if (json === '') {
      return results
    }

    try {
      const parsed = JSON.parse(json) as Record<string, Object>
      const resultsValue = parsed['results']
      if (resultsValue === undefined || resultsValue === null || !Array.isArray(resultsValue)) {
        return results
      }

      const list = resultsValue as Object[]
      for (let i = 0; i < list.length && results.length < maxCount; i++) {
        const item = list[i]
        if (item === null || item === undefined || typeof item !== 'object' || Array.isArray(item)) {
          continue
        }
        const itemObj = item as Record<string, Object>
        const title = this.readStringFromObject(itemObj, 'title').trim()
        const url = this.readStringFromObject(itemObj, 'url').trim()
        const snippet = this.normalizeSnippet(this.readStringFromObject(itemObj, 'content'))
        if (title === '' || url === '') {
          continue
        }
        results.push(new SearchResultItem(title, url, snippet))
      }
    } catch (error) {
      console.error('WebSearchService', `Parse Tavily results failed: ${JSON.stringify(error)}`)
    }

    return results
  }

  private parseTavilyExtractResult(json: string, fallbackUrl: string): WebSearchResult {
    if (json === '') {
      return new WebSearchResult(false, fallbackUrl, '', '', 'Tavily Extract 未返回内容')
    }

    try {
      const parsed = JSON.parse(json) as Record<string, Object>
      const resultsValue = parsed['results']
      if (resultsValue !== undefined && resultsValue !== null && Array.isArray(resultsValue)) {
        const list = resultsValue as Object[]
        for (let i = 0; i < list.length; i++) {
          const item = list[i]
          if (item === null || item === undefined || typeof item !== 'object' || Array.isArray(item)) {
            continue
          }
          const itemObj = item as Record<string, Object>
          const content = this.extractTavilyExtractContent(itemObj)
          if (content === '') {
            continue
          }
          const resultUrl = this.readStringFromObject(itemObj, 'url')
          const resolvedUrl = resultUrl !== '' ? resultUrl : fallbackUrl
          let title = this.readStringFromObject(itemObj, 'title').trim()
          if (title === '') {
            title = this.extractTitleFromTextContent(content, resolvedUrl)
          }
          const jsonContent = parseJsonResponseContent(content)
          if (jsonContent.isJson) {
            return new WebSearchResult(
              true,
              resolvedUrl,
              jsonContent.truncated ? 'JSON 数据（已截断）' : 'JSON 数据',
              jsonContent.content,
              '',
              undefined,
              'Tavily Extract(JSON)'
            )
          }
          return new WebSearchResult(
            true,
            resolvedUrl,
            title,
            this.limitExtractedContent(content),
            '',
            undefined,
            'Tavily Extract'
          )
        }
      }

      const failedMessage = this.extractTavilyFailedResultMessage(parsed)
      if (failedMessage !== '') {
        return new WebSearchResult(false, fallbackUrl, '', '', failedMessage)
      }
    } catch (error) {
      console.error('WebSearchService', `Parse Tavily extract failed: ${JSON.stringify(error)}`)
      return new WebSearchResult(false, fallbackUrl, '', '', `Tavily Extract 解析失败: ${JSON.stringify(error)}`)
    }

    return new WebSearchResult(false, fallbackUrl, '', '', 'Tavily Extract 未返回正文')
  }

  private extractTavilyExtractContent(itemObj: Record<string, Object>): string {
    const rawContent = this.readStringFromObject(itemObj, 'raw_content').trim()
    if (rawContent !== '') {
      return rawContent
    }

    const content = this.readStringFromObject(itemObj, 'content').trim()
    if (content !== '') {
      return content
    }

    return this.readStringFromObject(itemObj, 'text').trim()
  }

  private extractTavilyFailedResultMessage(parsed: Record<string, Object>): string {
    const failedResults = parsed['failed_results']
    if (failedResults === undefined || failedResults === null || !Array.isArray(failedResults)) {
      return ''
    }

    const list = failedResults as Object[]
    for (let i = 0; i < list.length; i++) {
      const item = list[i]
      if (item === null || item === undefined || typeof item !== 'object' || Array.isArray(item)) {
        continue
      }
      const itemObj = item as Record<string, Object>
      const error = this.readStringFromObject(itemObj, 'error')
      if (error !== '') {
        return error
      }
    }
    return ''
  }

  private extractTitleFromTextContent(content: string, fallbackUrl: string): string {
    const headingMatch = /^#{1,6}\s+(.+)$/m.exec(content)
    if (headingMatch !== null && headingMatch[1] !== undefined) {
      const title = headingMatch[1].trim()
      if (title !== '') {
        return title
      }
    }
    return fallbackUrl
  }

  private limitExtractedContent(content: string): string {
    const maxContentLength = 8000
    if (content.length <= maxContentLength) {
      return content
    }
    return content.substring(0, maxContentLength) + '...'
  }

  private extractExaErrorMessage(json: string): string {
    if (json === '') {
      return ''
    }
    try {
      const parsed = JSON.parse(json) as Record<string, Object>
      const error = parsed['error']
      if (error === undefined || error === null) {
        return ''
      }
      if (typeof error === 'string') {
        return error
      }
      if (typeof error === 'object') {
        const errorObj = error as Record<string, Object>
        const message = this.readStringFromObject(errorObj, 'message')
        if (message !== '') {
          return message
        }
        return JSON.stringify(errorObj)
      }
      return JSON.stringify(error)
    } catch (_error) {
      return ''
    }
  }

  private parseExaSearchResults(json: string, maxCount: number): SearchResultItem[] {
    const results: SearchResultItem[] = []
    if (json === '') {
      return results
    }

    try {
      const parsed = JSON.parse(json) as Record<string, Object>
      const resultsValue = parsed['results']
      if (resultsValue === undefined || resultsValue === null || !Array.isArray(resultsValue)) {
        return results
      }

      const list = resultsValue as Object[]
      for (let i = 0; i < list.length && results.length < maxCount; i++) {
        const item = list[i]
        if (item === null || item === undefined || typeof item !== 'object' || Array.isArray(item)) {
          continue
        }
        const itemObj = item as Record<string, Object>
        const title = this.readStringFromObject(itemObj, 'title')
        const url = this.readStringFromObject(itemObj, 'url')
        const snippet = this.extractExaSnippet(itemObj)

        if (title === '' || url === '') {
          continue
        }
        results.push(new SearchResultItem(title, url, snippet))
      }
    } catch (error) {
      console.error('WebSearchService', `Parse Exa results failed: ${JSON.stringify(error)}`)
    }

    return results
  }

  private extractExaSnippet(itemObj: Record<string, Object>): string {
    const summary = this.readStringFromObject(itemObj, 'summary')
    if (summary !== '') {
      return this.normalizeSnippet(summary)
    }

    const text = this.readStringFromObject(itemObj, 'text')
    if (text !== '') {
      return this.normalizeSnippet(text)
    }

    const highlights = itemObj['highlights']
    if (highlights !== undefined && highlights !== null && Array.isArray(highlights)) {
      const list = highlights as Object[]
      for (let i = 0; i < list.length; i++) {
        if (typeof list[i] === 'string') {
          return this.normalizeSnippet(list[i] as string)
        }
      }
    }

    return ''
  }

  private normalizeSnippet(raw: string): string {
    const trimmed = raw.replace(/\s+/g, ' ').trim()
    if (trimmed.length <= 220) {
      return trimmed
    }
    return trimmed.substring(0, 220) + '...'
  }

  // 博查 summary 长摘要专用：放宽到 500 字，保留更多上下文给模型；buildContentForAI 仍有总长限制
  private normalizeBochaSnippet(raw: string): string {
    const trimmed = raw.replace(/\s+/g, ' ').trim()
    if (trimmed.length <= 500) {
      return trimmed
    }
    return trimmed.substring(0, 500) + '...'
  }

  private readStringFromObject(obj: Record<string, Object>, key: string): string {
    const value = obj[key]
    if (value === undefined || value === null) {
      return ''
    }
    if (typeof value === 'string') {
      return value
    }
    return ''
  }

  private buildWeatherSiteQuery(query: string): string {
    if (query.includes('site:')) {
      return query
    }
    const city = this.extractCityFromWeatherQuery(query)
    const base = city !== '' ? `${city} 天气预报` : '天气预报'
    return `${base} site:weather.com.cn`
  }

  private buildWeatherFallbackQuery(query: string): string {
    if (query.includes('site:')) {
      const withoutSite = query.replace(/site:[^\s]+/g, '').trim()
      const city = this.extractCityFromWeatherQuery(withoutSite)
      const base = city !== '' ? `${city} 天气预报` : '天气预报'
      return `${base} site:nmc.cn`
    }
    const city = this.extractCityFromWeatherQuery(query)
    const base = city !== '' ? `${city} 天气预报` : '天气预报'
    return `${base} site:nmc.cn`
  }

  private extractCityFromWeatherQuery(query: string): string {
    let q = query.trim().replace(/\s+/g, ' ')
    q = q.replace(/site:[^\s]+/g, '').trim()
    q = q.replace(/(今天|今日|现在|当前|明天|后天)/g, '').trim()

    const match = /^(.*?)(?:的)?(?:天气预报|天气|气温|温度)/.exec(q)
    if (match && match[1] !== undefined) {
      const city = match[1].trim()
      if (city !== '') {
        return city
      }
    }

    const parts = q.split(' ')
    return parts.length > 0 ? parts[0].trim() : ''
  }

  private isWeatherIntent(text: string): boolean {
    const t = text.replace(/\s+/g, '')
    if (t.includes('weather.com.cn') || t.includes('nmc.cn')) {
      return true
    }
    const keywords: string[] = [
      '天气', '天气预报', '气温', '温度', '降雨', '降水', '湿度', '风速', '风力', '空气质量', 'AQI', 'PM2.5'
    ]
    for (let i = 0; i < keywords.length; i++) {
      if (t.includes(keywords[i])) {
        return true
      }
    }
    return false
  }

  // ========== Bing 结果相关性校验 ==========
  // 提取查询中最长的连续中文核心串（去掉口语词、标点、运算符）
  private extractCoreCjkQuery(query: string): string {
    let cleaned = query.trim()
    if (cleaned.includes('site:') || cleaned.includes('-site:') || cleaned.includes(' OR ')) {
      return ''
    }
    cleaned = cleaned
      .replace(/[“”"']/g, '')
      .replace(/[？?。!！，,、：:；;]/g, ' ')
      .trim()
    const matches = cleaned.match(/[一-鿿]+/g)
    if (matches === null || matches.length === 0) {
      return ''
    }
    let longest = ''
    for (let i = 0; i < matches.length; i++) {
      if (matches[i].length > longest.length) {
        longest = matches[i]
      }
    }
    return longest
  }

  private isCjkDictionaryUrl(url: string): boolean {
    const lower = url.toLowerCase()
    for (let i = 0; i < this.cjkDictionaryDomains.length; i++) {
      if (lower.includes(this.cjkDictionaryDomains[i])) {
        return true
      }
    }
    return false
  }

  // 结果是否与 core 相关：命中 core 全串，或命中 core 的 ≥2 字连续子串
  private resultMatchesCore(item: SearchResultItem, core: string): boolean {
    const haystack = `${item.title} ${item.snippet}`.replace(/\s+/g, '')
    if (haystack.includes(core)) {
      return true
    }
    for (let len = core.length - 1; len >= 2; len--) {
      for (let start = 0; start + len <= core.length; start++) {
        if (haystack.includes(core.substring(start, start + len))) {
          return true
        }
      }
    }
    return false
  }

  // 评估 Bing 结果相关性：返回是否相关 + 过滤掉拆词噪声后的列表。
  // 针对 Bing 把生僻多字词拆成首字、返回字典/百科噪声的固有行为。
  private assessBingResultRelevance(query: string, results: SearchResultItem[]): BingRelevanceVerdict {
    if (results.length === 0) {
      return new BingRelevanceVerdict(false, [])
    }
    const core = this.extractCoreCjkQuery(query)
    // 核心串 <2 字（单字或非中文主导查询）不校验，原样返回
    if (core.length < 2) {
      return new BingRelevanceVerdict(true, results)
    }

    const relevant: SearchResultItem[] = []
    let dictionaryNoiseCount = 0
    for (let i = 0; i < results.length; i++) {
      const item = results[i]
      if (this.resultMatchesCore(item, core)) {
        relevant.push(item)
      } else if (this.isCjkDictionaryUrl(item.url)) {
        dictionaryNoiseCount += 1
      }
    }

    // 无任何相关结果且存在字典噪声 → 判定为拆词噪声，不相关
    if (relevant.length === 0 && dictionaryNoiseCount > 0) {
      return new BingRelevanceVerdict(false, [])
    }
    // 无相关结果也无明显字典噪声：保守保留原结果，避免误杀（可能 core 提取不准）
    if (relevant.length === 0) {
      return new BingRelevanceVerdict(true, results)
    }
    return new BingRelevanceVerdict(true, relevant)
  }

  private pushUniqueCandidate(candidates: string[], value: string): void {
    const normalized = value.replace(/\s+/g, ' ').trim()
    if (normalized === '' || candidates.includes(normalized)) {
      return
    }
    candidates.push(normalized)
  }

  private appendUniqueSearchResults(
    target: SearchResultItem[],
    incoming: SearchResultItem[],
    maxCount: number
  ): void {
    const normalizedMaxCount = this.normalizeResultCount(maxCount)
    for (let i = 0; i < incoming.length; i++) {
      if (target.length >= normalizedMaxCount) {
        return
      }
      const url = incoming[i].url.trim()
      if (url === '') {
        continue
      }
      let exists = false
      for (let j = 0; j < target.length; j++) {
        if (target[j].url.trim() === url) {
          exists = true
          break
        }
      }
      if (!exists) {
        target.push(incoming[i])
      }
    }
  }

  private buildRepeatedBingSearchQuery(query: string, page: number): string {
    return this.buildDiversifiedSearchQuery(query, page)
  }

  // 引擎无关的查询词变体：对无原生分页能力的引擎（Bing/Tavily/Exa），
  // 在重复搜索同一 query 时改写关键词以拿到不同结果。page<=1 不改写。
  private buildDiversifiedSearchQuery(query: string, page: number): string {
    if (page <= 1) {
      return query
    }

    // 用同义/角度扩展词制造差异。注意：Bing RSS/HTML 无视引号与 -排除/OR 语法，
    // 故这里只用普通追加词；对支持运算符的引擎（Tavily/Exa/博查）同样有效。
    const genericSuffixes: string[] = [
      '资料',
      '介绍',
      '原文',
      '详情',
      '报道',
      '官方'
    ]
    const suffix = genericSuffixes[(page - 2) % genericSuffixes.length]
    if (query.includes(suffix)) {
      return query
    }
    return `${query} ${suffix}`.trim()
  }


  private async enrichTopPagesForAI(
    results: SearchResultItem[],
    maxFetch: number,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<string> {
    const candidates: SearchResultItem[] = []
    for (let i = 0; i < results.length; i++) {
      if (candidates.length >= maxFetch) {
        break
      }
      const item = results[i]
      if (item.url === '' || this.isBingInternalUrl(item.url)) {
        continue
      }
      candidates.push(item)
    }

    if (candidates.length === 0) {
      return ''
    }

    const tasks: Promise<string>[] = []
    for (let i = 0; i < candidates.length; i++) {
      tasks.push(this.fetchSinglePageSummary(candidates[i].url, runtime, controller, cancelCheck))
    }

    const summaries = await Promise.all(tasks)
    const validSummaries: string[] = []
    for (let i = 0; i < summaries.length; i++) {
      if (summaries[i] !== '') {
        validSummaries.push(summaries[i])
      }
    }

    return validSummaries.join('\n').trim()
  }

  private async fetchSinglePageSummary(
    url: string,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<string> {
    if (this.isCancelled(controller, cancelCheck)) {
      return ''
    }

    try {
      const webResult = await this.fetchUrlContentInternal(url, runtime.timeout, controller, cancelCheck)
      if (!webResult.success) {
        return ''
      }
      if (webResult.content.trim() === '' || webResult.content.includes('无法提取正文内容')) {
        return ''
      }

      let text = webResult.content
      const maxLen = 1200
      if (text.length > maxLen) {
        text = text.substring(0, maxLen) + '...'
      }

      return `抓取到的网页正文摘要（用于提取具体数据）:\n标题: ${webResult.title}\n来源: ${webResult.url}\n${text}`
    } catch (_error) {
      return ''
    }
  }

  private limitPromptContent(content: string, maxChars: number): string {
    if (content.length <= maxChars) {
      return content
    }
    return content.substring(0, maxChars) + '\n\n[搜索上下文已截断]'
  }

  // 构建给 AI 的内容（限制总长度，避免上下文过大）
  private buildContentForAI(results: SearchResultItem[]): string {
    let content = '以下是搜索结果:\n\n'
    const maxChars = 3800

    for (let i = 0; i < results.length; i++) {
      const item = results[i]
      const block = `${i + 1}. ${item.title}\n   ${item.snippet}\n   来源: ${item.url}\n\n`
      if ((content + block).length > maxChars) {
        content += '[更多结果已省略]\n'
        break
      }
      content += block
    }
    return content
  }

  // ========== Bing 搜索功能 ==========
  // 执行 Bing 搜索（公开接口，兼容旧调用）
  async bingSearch(
    query: string,
    resultCount: number = 5,
    runtimeConfig?: SearchRuntimeConfigSnapshot,
    options?: WebSearchExecutionOptions
  ): Promise<BingSearchResponse> {
    const runtime = runtimeConfig !== undefined ? runtimeConfig : await this.getRuntimeConfigSnapshot()
    const requestId = options?.requestId !== undefined ? options.requestId : ''
    const controller = this.acquireRequestController(requestId)

    try {
      return await this.bingSearchInternal(
        query,
        resultCount,
        runtime,
        controller,
        options?.cancelCheck,
        this.normalizeSearchPage(options?.page)
      )
    } finally {
      this.releaseRequestController(requestId)
    }
  }

  private async bingSearchInternal(
    query: string,
    resultCount: number,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean,
    page: number = 1
  ): Promise<BingSearchResponse> {
    try {
      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      const encodedQuery = encodeURIComponent(query)
      const normalizedCount = this.normalizeResultCount(resultCount)
      const startIndex = this.getSearchStartIndex(normalizedCount, page)
      const mergedResponse = new BingSearchResponse(true, query, [], '')
      const errors: string[] = []

      const primaryRssUrl = this.buildBingRssSearchUrl('www.bing.com', encodedQuery, normalizedCount, startIndex)
      const primaryRssResponse =
        await this.bingRssSearchByUrl(primaryRssUrl, query, normalizedCount, runtime, controller, cancelCheck)
      this.mergeBingResponse(mergedResponse, primaryRssResponse, normalizedCount, errors)

      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      if (mergedResponse.results.length < normalizedCount) {
        const fallbackRssUrl = this.buildBingRssSearchUrl('cn.bing.com', encodedQuery, normalizedCount, startIndex)
        const fallbackRssResponse =
          await this.bingRssSearchByUrl(fallbackRssUrl, query, normalizedCount, runtime, controller, cancelCheck)
        this.mergeBingResponse(mergedResponse, fallbackRssResponse, normalizedCount, errors)
      }

      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      if (mergedResponse.results.length < normalizedCount) {
        const primaryUrl = this.buildBingHtmlSearchUrl('www.bing.com', encodedQuery, normalizedCount, startIndex)
        const primaryResponse = await this.bingSearchByUrl(primaryUrl, query, normalizedCount, runtime, controller, cancelCheck)
        this.mergeBingResponse(mergedResponse, primaryResponse, normalizedCount, errors)
      }

      if (this.isCancelled(controller, cancelCheck)) {
        return new BingSearchResponse(false, query, [], '请求已取消')
      }

      if (mergedResponse.results.length < normalizedCount) {
        const fallbackUrl = this.buildBingHtmlSearchUrl('cn.bing.com', encodedQuery, normalizedCount, startIndex)
        const fallbackResponse =
          await this.bingSearchByUrl(fallbackUrl, query, normalizedCount, runtime, controller, cancelCheck)
        this.mergeBingResponse(mergedResponse, fallbackResponse, normalizedCount, errors)
      }

      if (mergedResponse.results.length > 0) {
        return mergedResponse
      }

      if (errors.length > 0) {
        return new BingSearchResponse(false, query, [], this.joinUniqueMessages(errors))
      }

      return mergedResponse
    } catch (error) {
      return new BingSearchResponse(false, query, [], `Bing 搜索失败: ${JSON.stringify(error)}`)
    }
  }

  private mergeBingResponse(
    target: BingSearchResponse,
    incoming: BingSearchResponse,
    maxCount: number,
    errors: string[]
  ): void {
    if (!incoming.success) {
      if (incoming.errorMessage !== '') {
        errors.push(incoming.errorMessage)
      }
      return
    }
    if (incoming.results.length === 0) {
      return
    }
    this.appendUniqueSearchResults(target.results, incoming.results, maxCount)
  }

  private joinUniqueMessages(messages: string[]): string {
    const unique: string[] = []
    for (let i = 0; i < messages.length; i++) {
      const message = messages[i].trim()
      if (message === '' || unique.includes(message)) {
        continue
      }
      unique.push(message)
    }
    return unique.join('; ')
  }

  private buildBingRssSearchUrl(host: string, encodedQuery: string, resultCount: number, startIndex: number): string {
    return `https://${host}/search?format=rss&q=${encodedQuery}&setlang=zh-Hans&cc=CN&mkt=zh-CN&count=${resultCount}&first=${startIndex}`
  }

  private buildBingHtmlSearchUrl(host: string, encodedQuery: string, resultCount: number, startIndex: number): string {
    return `https://${host}/search?q=${encodedQuery}&setlang=zh-Hans&cc=CN&mkt=zh-CN&count=${resultCount}&first=${startIndex}`
  }

  private async bingRssSearchByUrl(
    searchUrl: string,
    query: string,
    resultCount: number,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<BingSearchResponse> {
    if (this.isCancelled(controller, cancelCheck)) {
      return new BingSearchResponse(false, query, [], '请求已取消')
    }

    const response = await this.httpService.get(
      searchUrl,
      {
        'Accept': 'application/rss+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.5'
      },
      this.buildHttpOptions(runtime.timeout, controller)
    )

    if (!response.success) {
      return new BingSearchResponse(false, query, [], response.errorMessage)
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return new BingSearchResponse(false, query, [], '请求已取消')
    }

    const challengeMessage = this.extractBingChallengeMessage(response.data)
    if (challengeMessage !== '') {
      return new BingSearchResponse(false, query, [], challengeMessage)
    }

    const results = this.parseBingRssSearchResults(response.data, this.normalizeResultCount(resultCount))
    return new BingSearchResponse(true, query, results, '')
  }

  private async bingSearchByUrl(
    searchUrl: string,
    query: string,
    resultCount: number,
    runtime: SearchRuntimeConfigSnapshot,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<BingSearchResponse> {
    if (this.isCancelled(controller, cancelCheck)) {
      return new BingSearchResponse(false, query, [], '请求已取消')
    }

    const response = await this.httpService.get(
      searchUrl,
      {},
      this.buildHttpOptions(runtime.timeout, controller)
    )

    if (!response.success) {
      return new BingSearchResponse(false, query, [], response.errorMessage)
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return new BingSearchResponse(false, query, [], '请求已取消')
    }

    const challengeMessage = this.extractBingChallengeMessage(response.data)
    if (challengeMessage !== '') {
      return new BingSearchResponse(false, query, [], challengeMessage)
    }

    const results = this.parseBingSearchResults(response.data, this.normalizeResultCount(resultCount))
    return new BingSearchResponse(true, query, results, '')
  }

  private parseBingRssSearchResults(xml: string, maxCount: number): SearchResultItem[] {
    const results: SearchResultItem[] = []
    const seenUrls: Map<string, boolean> = new Map()
    const itemRegex = /<item\b[^>]*>([\s\S]*?)<\/item>/gi
    let match = itemRegex.exec(xml)

    while (match !== null && results.length < maxCount) {
      const block = match[1]
      const title = this.stripHtmlTags(this.extractXmlTagContent(block, 'title')).trim()
      const url = this.resolveBingResultUrl(this.extractXmlTagContent(block, 'link')).trim()
      const snippet = this.normalizeSnippet(this.stripHtmlTags(this.extractXmlTagContent(block, 'description')).trim())

      if (title !== '' && url !== '' && !this.isBingInternalUrl(url) && !seenUrls.has(url)) {
        seenUrls.set(url, true)
        results.push(new SearchResultItem(title, url, snippet))
      }

      match = itemRegex.exec(xml)
    }

    return results
  }

  private extractXmlTagContent(xml: string, tagName: string): string {
    const regex = new RegExp(`<${tagName}\\b[^>]*>([\\s\\S]*?)<\\/${tagName}>`, 'i')
    const match = regex.exec(xml)
    if (!match || match[1] === undefined) {
      return ''
    }
    const cdataMatch = /^<!\[CDATA\[([\s\S]*?)\]\]>$/.exec(match[1].trim())
    const raw = cdataMatch && cdataMatch[1] !== undefined ? cdataMatch[1] : match[1]
    return this.decodeHtmlEntities(raw.trim())
  }

  // 解析 Bing 搜索结果页 HTML（多策略，增强鲁棒性）
  private parseBingSearchResults(html: string, maxCount: number): SearchResultItem[] {
    const results: SearchResultItem[] = []
    const seenUrls: Map<string, boolean> = new Map()

    this.collectResultsFromBAlgoBlocks(html, maxCount, results, seenUrls)
    if (results.length < maxCount) {
      this.collectResultsFromHeadingLinks(html, maxCount, results, seenUrls)
    }

    return results
  }

  private collectResultsFromBAlgoBlocks(
    html: string,
    maxCount: number,
    output: SearchResultItem[],
    seenUrls: Map<string, boolean>
  ): void {
    const algoRegex = /<li[^>]*class=["'][^"']*b_algo[^"']*["'][^>]*>([\s\S]*?)<\/li>/gi
    let match = algoRegex.exec(html)

    while (match !== null && output.length < maxCount) {
      const block = match[1]
      const parsed = this.parseResultFromBlock(block)
      if (parsed !== null) {
        const normalizedUrl = parsed.url.trim()
        if (!seenUrls.has(normalizedUrl)) {
          seenUrls.set(normalizedUrl, true)
          output.push(parsed)
        }
      }
      match = algoRegex.exec(html)
    }
  }

  private collectResultsFromHeadingLinks(
    html: string,
    maxCount: number,
    output: SearchResultItem[],
    seenUrls: Map<string, boolean>
  ): void {
    const headingRegex = /<h2[^>]*>[\s\S]*?<a[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>[\s\S]*?<\/h2>/gi
    let match = headingRegex.exec(html)

    while (match !== null && output.length < maxCount) {
      const url = this.resolveBingResultUrl(match[1])
      const title = this.stripHtmlTags(match[2]).trim()

      if (title !== '' && !this.isBingInternalUrl(url)) {
        const normalizedUrl = url.trim()
        if (!seenUrls.has(normalizedUrl)) {
          seenUrls.set(normalizedUrl, true)
          const snippet = this.extractSnippetNearMatch(html, match.index)
          output.push(new SearchResultItem(title, normalizedUrl, snippet))
        }
      }

      match = headingRegex.exec(html)
    }
  }

  private parseResultFromBlock(block: string): SearchResultItem | null {
    const titleMatch = /<h2[^>]*>([\s\S]*?)<\/h2>/i.exec(block)
    if (!titleMatch) {
      return null
    }

    const titleBlock = titleMatch[1]
    const linkMatch = /<a[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/i.exec(titleBlock)
    if (!linkMatch) {
      return null
    }

    const url = this.resolveBingResultUrl(linkMatch[1])
    const title = this.stripHtmlTags(linkMatch[2]).trim()
    if (title === '' || this.isBingInternalUrl(url)) {
      return null
    }

    let snippetMatch = /<div[^>]*class=["'][^"']*b_caption[^"']*["'][^>]*>[\s\S]*?<p[^>]*>([\s\S]*?)<\/p>/i.exec(block)
    if (!snippetMatch) {
      snippetMatch = /<p[^>]*>([\s\S]*?)<\/p>/i.exec(block)
    }

    const snippet = snippetMatch ? this.normalizeSnippet(this.stripHtmlTags(snippetMatch[1]).trim()) : ''
    return new SearchResultItem(title, url.trim(), snippet)
  }

  private extractSnippetNearMatch(html: string, startIndex: number): string {
    const safeStart = startIndex >= 0 ? startIndex : 0
    const safeEnd = Math.min(html.length, safeStart + 1000)
    const segment = html.substring(safeStart, safeEnd)
    const snippetMatch = /<p[^>]*>([\s\S]*?)<\/p>/i.exec(segment)
    if (!snippetMatch) {
      return ''
    }
    return this.normalizeSnippet(this.stripHtmlTags(snippetMatch[1]).trim())
  }

  private isBingInternalUrl(url: string): boolean {
    const lower = url.toLowerCase()
    if (lower.startsWith('/search') || lower.startsWith('/?') || lower.startsWith('/ck/')
      || lower.startsWith('/aclick')) {
      return true
    }
    const host = this.extractHostFromUrl(lower)
    return host === 'bing.com' || host === 'www.bing.com' || host === 'cn.bing.com'
      || host === 'www4.bing.com'
  }

  private extractHostFromUrl(url: string): string {
    let value = url.trim()
    if (value.startsWith('https://')) {
      value = value.substring(8)
    } else if (value.startsWith('http://')) {
      value = value.substring(7)
    } else {
      return ''
    }
    const slashIndex = value.indexOf('/')
    if (slashIndex >= 0) {
      value = value.substring(0, slashIndex)
    }
    const questionIndex = value.indexOf('?')
    if (questionIndex >= 0) {
      value = value.substring(0, questionIndex)
    }
    const colonIndex = value.indexOf(':')
    if (colonIndex >= 0) {
      value = value.substring(0, colonIndex)
    }
    return value
  }

  private resolveBingResultUrl(rawUrl: string): string {
    const decodedUrl = this.decodeHtmlEntities(rawUrl).trim()
    if (decodedUrl === '') {
      return ''
    }
    if (!this.isBingInternalUrl(decodedUrl)) {
      return decodedUrl
    }

    const extractedUrl = this.extractUrlQueryParam(decodedUrl, 'url')
    if (extractedUrl !== '') {
      return extractedUrl
    }

    const extractedRedirect = this.extractUrlQueryParam(decodedUrl, 'r')
    if (extractedRedirect !== '') {
      return extractedRedirect
    }

    const extractedBingUrl = this.extractUrlQueryParam(decodedUrl, 'u')
    if (extractedBingUrl !== '') {
      const decodedBingUrl = this.decodeBingEncodedUrl(extractedBingUrl)
      if (decodedBingUrl !== '') {
        return decodedBingUrl
      }
      if (!this.isBingInternalUrl(extractedBingUrl)) {
        return extractedBingUrl
      }
    }

    return decodedUrl
  }

  private decodeBingEncodedUrl(rawValue: string): string {
    let value = rawValue.trim()
    if (value === '') {
      return ''
    }
    if (value.startsWith('a1') && value.length > 2) {
      value = value.substring(2)
    }
    value = value.replace(/-/g, '+').replace(/_/g, '/')
    while (value.length % 4 !== 0) {
      value += '='
    }
    try {
      const helper = new util.Base64Helper()
      const decodedBytes = helper.decodeSync(value)
      const decoder = util.TextDecoder.create('utf-8')
      const decoded = decoder.decodeToString(decodedBytes).trim()
      if (decoded.startsWith('http://') || decoded.startsWith('https://')) {
        return decoded
      }
    } catch (_error) {}
    return ''
  }

  private extractUrlQueryParam(url: string, key: string): string {
    const queryStart = url.indexOf('?')
    if (queryStart < 0 || queryStart >= url.length - 1) {
      return ''
    }

    const fragmentStart = url.indexOf('#', queryStart + 1)
    const query = fragmentStart >= 0 ? url.substring(queryStart + 1, fragmentStart) : url.substring(queryStart + 1)
    const parts = query.split('&')
    for (let i = 0; i < parts.length; i++) {
      const separatorIndex = parts[i].indexOf('=')
      if (separatorIndex <= 0) {
        continue
      }
      const rawKey = parts[i].substring(0, separatorIndex)
      if (rawKey !== key) {
        continue
      }
      const rawValue = parts[i].substring(separatorIndex + 1).replace(/\+/g, ' ')
      try {
        return decodeURIComponent(rawValue)
      } catch (_error) {
        return rawValue
      }
    }
    return ''
  }

  private extractBingChallengeMessage(html: string): string {
    const lower = html.toLowerCase()
    const hasChallenge = lower.includes('turnstile') || lower.includes('captcha') ||
      html.includes('最后一步') || html.includes('请解决以下难题')
    if (!hasChallenge) {
      return ''
    }
    return 'Bing Local 被 Bing 验证页拦截，无法解析搜索结果。已优先尝试 RSS 入口；若仍失败，请稍后重试或切换 Brave/Tavily/Exa。'
  }

  private decodeHtmlEntities(text: string): string {
    return text
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/&#39;/g, "'")
      .replace(/&#(\d+);/g, (_match: string, code: string): string => {
        const value = Number(code)
        if (Number.isNaN(value)) {
          return ''
        }
        return String.fromCharCode(value)
      })
      .replace(/&#x([0-9a-fA-F]+);/g, (_match: string, code: string): string => {
        const value = parseInt(code, 16)
        if (Number.isNaN(value)) {
          return ''
        }
        return String.fromCharCode(value)
      })
  }

  // 移除 HTML 标签
  private stripHtmlTags(text: string): string {
    return this.decodeHtmlEntities(text.replace(/<[^>]+>/g, ''))
      .replace(/\s+/g, ' ')
      .trim()
  }

  // ========== URL 抓取功能 ==========
  // 抓取网页内容
  async fetchUrlContent(url: string, options?: WebSearchExecutionOptions): Promise<WebSearchResult> {
    const runtime = options?.runtimeConfig !== undefined ? options.runtimeConfig : await this.getRuntimeConfigSnapshot()
    const requestId = options?.requestId !== undefined ? options.requestId : ''
    const controller = this.acquireRequestController(requestId)

    try {
      // 只有 Tavily 当前接入了 provider-side Extract；其它搜索引擎保持本地网页抓取兼容路径。
      if (runtime.searchEngine === SearchEngine.TAVILY) {
        if (runtime.tavilyApiKey === '') {
          return new WebSearchResult(
            false,
            this.normalizeContentUrl(url),
            '',
            '',
            'Tavily API Key 未配置，无法调用 Extract',
            undefined,
            'Tavily Extract'
          )
        }
        const tavilyResult = await this.tavilyExtractUrlContent(url, runtime, controller, options?.cancelCheck)
        if (tavilyResult.success) {
          this.normalizeJsonWebResult(tavilyResult)
          return tavilyResult
        }
        if (this.isCancelled(controller, options?.cancelCheck)) {
          return tavilyResult
        }
        console.warn('WebSearchService', `[Tavily Extract] Failed, fallback to local fetch: ${tavilyResult.errorMessage}`)
        const localResult = await this.fetchUrlContentInternal(url, runtime.timeout, controller, options?.cancelCheck)
        if (localResult.success) {
          localResult.sourceName = 'Tavily Extract失败后 URL抓取'
          return localResult
        }
        return new WebSearchResult(
          false,
          this.normalizeContentUrl(url),
          '',
          '',
          `Tavily Extract 失败: ${tavilyResult.errorMessage}; 本地 URL 抓取失败: ${localResult.errorMessage}`,
          undefined,
          'Tavily Extract'
        )
      }
      return await this.fetchUrlContentInternal(url, runtime.timeout, controller, options?.cancelCheck)
    } finally {
      this.releaseRequestController(requestId)
    }
  }

  private async fetchUrlContentInternal(
    url: string,
    timeout: number,
    controller: HttpRequestController | null,
    cancelCheck?: () => boolean
  ): Promise<WebSearchResult> {
    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledWebResult(url)
    }

    if (!this.isValidUrl(url)) {
      return new WebSearchResult(false, url, '', '', 'URL 格式无效')
    }

    const fullUrl = this.normalizeContentUrl(url)

    const response = await this.httpService.get(
      fullUrl,
      {
        'Accept': 'application/json,text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      },
      this.buildHttpOptions(timeout, controller)
    )

    if (!response.success) {
      if (this.isCancelled(controller, cancelCheck)) {
        return this.buildCancelledWebResult(fullUrl)
      }
      return new WebSearchResult(false, fullUrl, '', '', response.errorMessage)
    }

    if (this.isCancelled(controller, cancelCheck)) {
      return this.buildCancelledWebResult(fullUrl)
    }

    const jsonContent = parseJsonResponseContent(response.data)
    if (jsonContent.isJson) {
      const title = jsonContent.truncated ? 'JSON 数据（已截断）' : 'JSON 数据'
      return new WebSearchResult(true, fullUrl, title, jsonContent.content, '', undefined, 'URL抓取(JSON)')
    }

    const parsed = this.parseHtmlContent(response.data)
    if (parsed.content.trim() === '') {
      return new WebSearchResult(false, fullUrl, parsed.title, '', '本地 URL 抓取未提取到网页正文', undefined, 'URL抓取')
    }
    return new WebSearchResult(true, fullUrl, parsed.title, parsed.content, '', undefined, 'URL抓取')
  }

  private normalizeJsonWebResult(result: WebSearchResult): void {
    const jsonContent: JsonResponseContent = parseJsonResponseContent(result.content)
    if (!jsonContent.isJson) {
      return
    }
    result.title = jsonContent.truncated ? 'JSON 数据（已截断）' : 'JSON 数据'
    result.content = jsonContent.content
    result.sourceName = 'Tavily Extract(JSON)'
  }

  private normalizeContentUrl(url: string): string {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'https://' + url
    }
    return url
  }

  // 解析 HTML 提取正文
  private parseHtmlContent(html: string): HtmlParseResult {
    const titleMatch = html.match(/<title[^>]*>([^<]+)<\/title>/i)
    const title = titleMatch ? titleMatch[1].trim() : '未知标题'

    const cleanHtml = html
      .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
      .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
      .replace(/<nav[^>]*>[\s\S]*?<\/nav>/gi, '')
      .replace(/<footer[^>]*>[\s\S]*?<\/footer>/gi, '')
      .replace(/<header[^>]*>[\s\S]*?<\/header>/gi, '')
      .replace(/<br\s*\/?>/gi, '\n')

    const contentMatches = cleanHtml.match(/<(p|h[1-6]|li|td|th|span)[^>]*>([\s\S]*?)<\/\1>/gi)

    let content = ''
    if (contentMatches) {
      content = contentMatches
        .map((match: string): string => match
          .replace(/<[^>]+>/g, '')
          .replace(/&nbsp;/g, ' ')
          .replace(/&amp;/g, '&')
          .replace(/&lt;/g, '<')
          .replace(/&gt;/g, '>')
          .replace(/&quot;/g, '"')
          .replace(/&#39;/g, "'")
          .replace(/\n+/g, '\n')
          .trim())
        .filter((text: string): boolean => {
          if (text.length > 10) {
            return true
          }
          if (/(℃|°|AQI|PM2\.5|\d+\s*-\s*\d+)/i.test(text)) {
            return true
          }
          return false
        })
        .join('\n')
    }

    const maxContentLength = 8000
    if (content.length > maxContentLength) {
      content = content.substring(0, maxContentLength) + '...'
    }

    return new HtmlParseResult(title, content)
  }

  // 验证 URL 格式
  isValidUrl(text: string): boolean {
    const urlPattern = /^https?:\/\/[\w\-.]+(:\d+)?(\/[\w\-._~:/?#[\]@!$&'()*+,;=]*)?$|^[\w\-.]+(:\d+)?(\/[\w\-._~:/?#[\]@!$&'()*+,;=]*)?$/
    return urlPattern.test(text.trim())
  }

  // 从文本中提取 URL
  extractUrl(text: string): string | null {
    const trimmed = text.trim()

    const httpPattern = /^https?:\/\/[^\s]+/
    const httpMatch = trimmed.match(httpPattern)
    if (httpMatch) {
      return httpMatch[0]
    }

    const domainPattern = /^[\w\-]+\.[\w\-]+(:\d+)?(\/[\w\-._~:/?#[\]@!$&'()*+,;=]*)?/
    const domainMatch = trimmed.match(domainPattern)
    if (domainMatch) {
      return domainMatch[0]
    }

    return null
  }
}

export function getWebSearchService(): WebSearchService {
  return WebSearchService.getInstance()
}
