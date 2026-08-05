import { getEffectiveApiKey } from '../config/PresetProviders'
import { getDatabaseService, ProviderConfig } from './DatabaseService'
import { getHttpService, HttpResponse, HttpService } from './HttpService'
import { getPreferencesService, PreferenceKeys } from './PreferencesService'
import { normalizeCustomHeaderName, parseCustomHeadersMap } from '../utils/CustomHeaderUtils'
import {
  buildKnowledgeApiEndpoint,
  buildKnowledgeApiEndpointFingerprint,
  buildSafeModelKeyToken
} from './KnowledgeEmbeddingService'

export const KNOWLEDGE_RERANK_ENDPOINT_SUFFIX: string = '/rerank'
// 每个候选片段送去重排序前截断的字符数。重排序模型只需要判断相关性，
// 不需要完整正文；截断同时压低 token 成本与请求体积。
export const KNOWLEDGE_RERANK_MAX_DOCUMENT_CHARACTERS: number = 1024
export const KNOWLEDGE_RERANK_MAX_QUERY_CHARACTERS: number = 1000
// 单次重排序允许提交的候选上限，避免召回异常放大时把请求撑爆
export const KNOWLEDGE_RERANK_MAX_DOCUMENTS: number = 32

const API_RERANK_REQUEST_TIMEOUT_MS: number = 30000
const API_RERANK_MODEL_KEY_PREFIX: string = 'api:rerank:openai-compatible'
const API_RERANK_MAX_RESPONSE_CHARACTERS: number = 4 * 1024 * 1024

interface StoredKnowledgeRerankSelection {
  providerId?: string
  providerName?: string
  modelId?: string
  modelName?: string
  endpointFingerprint?: string
}

interface StoredProviderModel {
  id: string
  isEnabled?: boolean
}

interface OpenAIRerankResultItem {
  index?: number
  relevance_score?: number
  score?: number
}

interface OpenAIRerankError {
  message?: string
}

interface OpenAIRerankResponse {
  results?: OpenAIRerankResultItem[]
  data?: OpenAIRerankResultItem[]
  error?: OpenAIRerankError
}

class OpenAIRerankRequest {
  model: string
  query: string
  documents: string[]
  top_n: number

  constructor(model: string, query: string, documents: string[], topN: number) {
    this.model = model
    this.query = query
    this.documents = documents
    this.top_n = topN
  }
}

/** 重排序模型给某个候选片段打出的相关性分数。index 指向提交时的候选下标。 */
export class KnowledgeRerankScore {
  index: number
  score: number

  constructor(index: number, score: number) {
    this.index = index
    this.score = score
  }
}

/**
 * 重排序模型选择。与向量模型不同，重排序没有本地实现：
 * providerId/modelId/endpointFingerprint 任一为空即视为“不启用重排序”。
 */
export class KnowledgeRerankSelection {
  providerId: string
  providerName: string
  modelId: string
  modelName: string
  endpointFingerprint: string

  constructor(
    providerId: string = '',
    providerName: string = '',
    modelId: string = '',
    modelName: string = '',
    endpointFingerprint: string = ''
  ) {
    this.providerId = providerId
    this.providerName = providerName
    this.modelId = modelId
    this.modelName = modelName
    this.endpointFingerprint = endpointFingerprint
  }

  static createDisabled(): KnowledgeRerankSelection {
    return new KnowledgeRerankSelection()
  }

  copy(): KnowledgeRerankSelection {
    return new KnowledgeRerankSelection(
      this.providerId,
      this.providerName,
      this.modelId,
      this.modelName,
      this.endpointFingerprint
    )
  }

  isEnabled(): boolean {
    return this.providerId.trim() !== '' &&
      this.modelId.trim() !== '' &&
      this.endpointFingerprint.trim() !== ''
  }

  identityKey(): string {
    if (!this.isEnabled()) {
      return 'disabled'
    }
    return `${this.providerId}:${this.modelId}:${this.endpointFingerprint}`
  }

  displayName(): string {
    if (!this.isEnabled()) {
      return '不使用重排序'
    }
    const modelLabel = this.modelName.trim() !== '' ? this.modelName : this.modelId
    if (this.providerName.trim() === '') {
      return modelLabel
    }
    return `${this.providerName} · ${modelLabel}`
  }
}

export function buildKnowledgeRerankEndpoint(baseUrl: string, apiPath: string = ''): string {
  return buildKnowledgeApiEndpoint(baseUrl, apiPath, KNOWLEDGE_RERANK_ENDPOINT_SUFFIX)
}

export function buildKnowledgeRerankEndpointFingerprint(
  baseUrl: string,
  apiPath: string = '',
  customHeadersJson: string = ''
): string {
  return buildKnowledgeApiEndpointFingerprint(
    baseUrl,
    apiPath,
    customHeadersJson,
    KNOWLEDGE_RERANK_ENDPOINT_SUFFIX
  )
}

/** 端点可能带 query string（部分网关把凭据放在 URL 上），日志里一律截掉。 */
function sanitizeEndpointForLog(endpoint: string): string {
  const queryIndex = endpoint.indexOf('?')
  return queryIndex >= 0 ? endpoint.substring(0, queryIndex) : endpoint
}

function buildApiRerankModelKey(selection: KnowledgeRerankSelection): string {
  return `${API_RERANK_MODEL_KEY_PREFIX}:` +
    `${buildSafeModelKeyToken(selection.providerId)}:` +
    `${buildSafeModelKeyToken(selection.modelId)}:` +
    selection.endpointFingerprint
}

/**
 * 知识库重排序能力的可注入边界。实现不得记录 query 原文、候选片段正文或 API Key。
 */
export interface KnowledgeRerankProvider {
  isAvailable(): boolean
  modelKey(): string
  maxDocumentCharacters(): number
  rerank(query: string, documents: string[]): Promise<KnowledgeRerankScore[]>
  release(): Promise<void>
}

/**
 * 通过现有 OpenAI 风格服务商的 `/rerank` 接口做重排序
 * （Jina / Cohere / SiliconFlow / BGE-Reranker 等均兼容该形态）。
 *
 * 只保存服务商和模型引用；每次调用都从服务商数据库读取最新地址、凭据和自定义请求头。
 * 不记录 query、候选正文、分数或 API Key。
 */
export class OpenAICompatibleKnowledgeRerankProvider implements KnowledgeRerankProvider {
  private selection: KnowledgeRerankSelection
  private httpService: HttpService = getHttpService()

  constructor(selection: KnowledgeRerankSelection) {
    this.selection = selection.copy()
  }

  isAvailable(): boolean {
    return this.selection.isEnabled()
  }

  modelKey(): string {
    return buildApiRerankModelKey(this.selection)
  }

  maxDocumentCharacters(): number {
    return KNOWLEDGE_RERANK_MAX_DOCUMENT_CHARACTERS
  }

  async validateConfiguration(): Promise<void> {
    await this.resolveProviderConfig()
  }

  async rerank(query: string, documents: string[]): Promise<KnowledgeRerankScore[]> {
    const normalizedQuery = query.trim()
    if (normalizedQuery === '') {
      throw new Error('重排序 query 不能为空')
    }
    if (!Array.isArray(documents) || documents.length === 0) {
      throw new Error('重排序候选不能为空')
    }
    if (documents.length > KNOWLEDGE_RERANK_MAX_DOCUMENTS) {
      throw new Error(`单次最多重排序 ${KNOWLEDGE_RERANK_MAX_DOCUMENTS} 个候选`)
    }

    const provider = await this.resolveProviderConfig()
    const endpoint = buildKnowledgeRerankEndpoint(provider.baseUrl, provider.apiPath)
    const request = new OpenAIRerankRequest(
      this.selection.modelId,
      normalizedQuery.substring(0, KNOWLEDGE_RERANK_MAX_QUERY_CHARACTERS),
      documents,
      documents.length
    )
    // 诊断日志只记录端点、状态码、候选数和耗时；
    // 不记录 API Key、query 原文、候选正文或返回分数（ai_instruction.md §14.4）
    const startTime = Date.now()
    const response = await this.httpService.postWithTimeout(
      endpoint,
      JSON.stringify(request),
      this.buildHeaders(provider),
      API_RERANK_REQUEST_TIMEOUT_MS
    )
    console.info(
      'KnowledgeRerankService',
      `Rerank request: endpoint=${sanitizeEndpointForLog(endpoint)}, model=${this.selection.modelId}, ` +
        `documents=${documents.length}, status=${response.statusCode}, cost=${Date.now() - startTime}ms`
    )
    if (!response.success) {
      throw new Error(this.buildRequestError(response))
    }
    if (response.data.length > API_RERANK_MAX_RESPONSE_CHARACTERS) {
      throw new Error('重排序 API 返回的数据过大')
    }

    let payload: OpenAIRerankResponse
    try {
      payload = JSON.parse(response.data) as OpenAIRerankResponse
    } catch (_error) {
      throw new Error('重排序 API 返回了无法解析的响应')
    }
    return this.parseScores(payload, documents.length)
  }

  async release(): Promise<void> {
  }

  // 兼容 results（Jina/Cohere/SiliconFlow）与 data（部分兼容实现）两种字段名，
  // 分数字段兼容 relevance_score 与 score
  private parseScores(payload: OpenAIRerankResponse, documentCount: number): KnowledgeRerankScore[] {
    let items: OpenAIRerankResultItem[] | undefined = payload.results
    if (!Array.isArray(items)) {
      items = payload.data
    }
    if (!Array.isArray(items) || items.length === 0) {
      throw new Error('重排序 API 未返回结果')
    }

    const scores: KnowledgeRerankScore[] = []
    const seen = new Array<boolean>(documentCount)
    for (let index = 0; index < seen.length; index++) {
      seen[index] = false
    }
    for (let index = 0; index < items.length; index++) {
      const item = items[index]
      const rawIndex = item.index
      if (rawIndex === undefined || !Number.isInteger(rawIndex) ||
        rawIndex < 0 || rawIndex >= documentCount || seen[rawIndex]) {
        throw new Error('重排序 API 返回了无效的结果序号')
      }
      const rawScore = item.relevance_score !== undefined ? item.relevance_score : item.score
      if (rawScore === undefined || typeof rawScore !== 'number' || !Number.isFinite(rawScore)) {
        throw new Error('重排序 API 返回了无效的相关性分数')
      }
      seen[rawIndex] = true
      scores.push(new KnowledgeRerankScore(rawIndex, rawScore))
    }
    return scores
  }

  private async resolveProviderConfig(): Promise<ProviderConfig> {
    const providers = await getDatabaseService().getAllProviders()
    for (let index = 0; index < providers.length; index++) {
      const provider = providers[index]
      if (provider.id !== this.selection.providerId) {
        continue
      }
      if (!provider.isEnabled) {
        throw new Error('所选重排序服务商已停用')
      }
      if (provider.apiStyle !== 'openai') {
        throw new Error('所选服务商不是 OpenAI 兼容接口')
      }
      if (provider.type === 'azure') {
        throw new Error('当前版本尚不支持 Azure 重排序接口')
      }
      if (provider.baseUrl.trim() === '') {
        throw new Error('所选重排序服务商未配置 API 地址')
      }
      const currentFingerprint = buildKnowledgeRerankEndpointFingerprint(
        provider.baseUrl,
        provider.apiPath,
        provider.customHeadersJson
      )
      if (currentFingerprint !== this.selection.endpointFingerprint) {
        throw new Error('重排序服务商地址或路由配置已变更，请在知识库中重新选择模型')
      }
      if (!this.isSelectedModelStillConfigured(provider)) {
        throw new Error('所选重排序模型已停用或移除')
      }
      const effectiveApiKey = getEffectiveApiKey(provider.id, provider.apiKey)
      if (provider.requiresApiKey && effectiveApiKey.trim() === '') {
        throw new Error('所选重排序服务商未配置 API Key')
      }
      return provider
    }
    throw new Error('未找到所选重排序服务商')
  }

  private isSelectedModelStillConfigured(provider: ProviderConfig): boolean {
    if (provider.modelsJson.trim() === '') {
      return true
    }
    try {
      const models = JSON.parse(provider.modelsJson) as StoredProviderModel[]
      for (let index = 0; index < models.length; index++) {
        if (models[index].id === this.selection.modelId) {
          return models[index].isEnabled !== false
        }
      }
      return false
    } catch (_error) {
      return true
    }
  }

  private buildHeaders(provider: ProviderConfig): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    }
    const effectiveApiKey = getEffectiveApiKey(provider.id, provider.apiKey).trim()
    if (effectiveApiKey !== '') {
      headers['Authorization'] = `Bearer ${effectiveApiKey}`
    }

    const customHeaders = parseCustomHeadersMap(provider.customHeadersJson)
    const headerNames = Object.keys(customHeaders)
    for (let index = 0; index < headerNames.length; index++) {
      const headerName = headerNames[index]
      const normalizedName = normalizeCustomHeaderName(headerName)
      if (normalizedName === 'authorization' ||
        normalizedName === 'api-key' ||
        normalizedName === 'content-type') {
        continue
      }
      headers[headerName] = customHeaders[headerName]
    }
    return headers
  }

  private buildRequestError(response: HttpResponse): string {
    let apiMessage = ''
    if (response.data.trim() !== '') {
      try {
        const payload = JSON.parse(response.data) as OpenAIRerankResponse
        if (payload.error !== undefined && payload.error.message !== undefined) {
          apiMessage = payload.error.message.trim().substring(0, 240)
        }
      } catch (_error) {
      }
    }
    if (apiMessage !== '') {
      return `重排序 API 请求失败（HTTP ${response.statusCode}）：${apiMessage}`
    }
    if (response.statusCode > 0) {
      return `重排序 API 请求失败（HTTP ${response.statusCode}）`
    }
    return response.errorMessage.trim() !== ''
      ? `重排序 API 请求失败：${response.errorMessage}`
      : '重排序 API 请求失败'
  }
}

/**
 * 面向知识库检索调用方的重排序服务。
 *
 * 与向量模型不同，切换重排序模型不需要重建任何索引：它只影响召回之后的排序，
 * 所以 applySelection 立即生效。
 */
export class KnowledgeRerankService implements KnowledgeRerankProvider {
  private static instance: KnowledgeRerankService | null = null
  private provider: KnowledgeRerankProvider | null = null
  private selection: KnowledgeRerankSelection = KnowledgeRerankSelection.createDisabled()
  private initialized: boolean = false
  private initPromise: Promise<void> | null = null
  private customProviderInjected: boolean = false

  constructor(provider?: KnowledgeRerankProvider) {
    if (provider !== undefined) {
      this.provider = provider
      this.customProviderInjected = true
    }
  }

  static getInstance(): KnowledgeRerankService {
    if (KnowledgeRerankService.instance === null) {
      KnowledgeRerankService.instance = new KnowledgeRerankService()
    }
    return KnowledgeRerankService.instance
  }

  async initialize(): Promise<void> {
    if (this.initialized || this.customProviderInjected) {
      this.initialized = true
      return
    }
    if (this.initPromise !== null) {
      await this.initPromise
      return
    }
    this.initPromise = this.loadPersistedSelection()
    try {
      await this.initPromise
      this.initialized = true
    } finally {
      this.initPromise = null
    }
  }

  getSelection(): KnowledgeRerankSelection {
    return this.selection.copy()
  }

  async validateSelection(selection: KnowledgeRerankSelection): Promise<void> {
    if (!selection.isEnabled()) {
      return
    }
    const candidate = new OpenAICompatibleKnowledgeRerankProvider(selection)
    await candidate.validateConfiguration()
  }

  async applySelection(selection: KnowledgeRerankSelection): Promise<boolean> {
    await this.initialize()
    if (this.customProviderInjected) {
      throw new Error('测试注入的重排序服务不支持运行期切换')
    }
    const nextSelection = selection.copy()
    if (nextSelection.identityKey() === this.selection.identityKey()) {
      return false
    }
    if (nextSelection.isEnabled()) {
      const candidate = new OpenAICompatibleKnowledgeRerankProvider(nextSelection)
      await candidate.validateConfiguration()
    }
    await getPreferencesService().setString(
      PreferenceKeys.KNOWLEDGE_RERANK_SELECTION_JSON,
      JSON.stringify(nextSelection)
    )
    const previousProvider = this.provider
    this.selection = nextSelection
    this.provider = this.createProvider(nextSelection)
    if (previousProvider !== null) {
      try {
        await previousProvider.release()
      } catch (_error) {
        console.warn('KnowledgeRerankService', 'Previous rerank provider release failed')
      }
    }
    return true
  }

  isAvailable(): boolean {
    return this.provider !== null && this.provider.isAvailable()
  }

  modelKey(): string {
    return this.provider === null ? 'disabled' : this.provider.modelKey()
  }

  maxDocumentCharacters(): number {
    return this.provider === null
      ? KNOWLEDGE_RERANK_MAX_DOCUMENT_CHARACTERS
      : this.provider.maxDocumentCharacters()
  }

  async rerank(query: string, documents: string[]): Promise<KnowledgeRerankScore[]> {
    const provider = this.provider
    if (provider === null) {
      throw new Error('未配置重排序模型')
    }
    return await provider.rerank(query, documents)
  }

  async release(): Promise<void> {
    if (this.provider !== null) {
      await this.provider.release()
    }
  }

  private async loadPersistedSelection(): Promise<void> {
    const raw = await getPreferencesService().getString(
      PreferenceKeys.KNOWLEDGE_RERANK_SELECTION_JSON,
      ''
    )
    const restored = this.parsePersistedSelection(raw)
    this.selection = restored
    this.provider = this.createProvider(restored)
  }

  private parsePersistedSelection(raw: string): KnowledgeRerankSelection {
    if (raw.trim() === '') {
      return KnowledgeRerankSelection.createDisabled()
    }
    try {
      const stored = JSON.parse(raw) as StoredKnowledgeRerankSelection
      const selection = new KnowledgeRerankSelection(
        stored.providerId !== undefined ? stored.providerId : '',
        stored.providerName !== undefined ? stored.providerName : '',
        stored.modelId !== undefined ? stored.modelId : '',
        stored.modelName !== undefined ? stored.modelName : '',
        stored.endpointFingerprint !== undefined ? stored.endpointFingerprint : ''
      )
      return selection.isEnabled() ? selection : KnowledgeRerankSelection.createDisabled()
    } catch (_error) {
      return KnowledgeRerankSelection.createDisabled()
    }
  }

  private createProvider(selection: KnowledgeRerankSelection): KnowledgeRerankProvider | null {
    if (!selection.isEnabled()) {
      return null
    }
    return new OpenAICompatibleKnowledgeRerankProvider(selection)
  }
}

export function getKnowledgeRerankService(): KnowledgeRerankService {
  return KnowledgeRerankService.getInstance()
}
