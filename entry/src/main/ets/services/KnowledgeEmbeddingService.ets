import { intelligence } from '@kit.ArkData'
import { deviceInfo } from '@kit.BasicServicesKit'
import { getEffectiveApiKey } from '../config/PresetProviders'
import { getDatabaseService, ProviderConfig } from './DatabaseService'
import { getHttpService, HttpResponse, HttpService } from './HttpService'
import { getPreferencesService, PreferenceKeys } from './PreferencesService'
import { normalizeCustomHeaderName, parseCustomHeadersMap } from '../utils/CustomHeaderUtils'

export const KNOWLEDGE_EMBEDDING_MAX_INPUT_CHARACTERS: number = 512
export const ARKDATA_BASIC_TEXT_EMBEDDING_MODEL_KEY: string = 'arkdata:text-embedding:basic-model:cpu'

const CAPABILITY_NOT_SUPPORTED_CODE: number = 801
const ARKDATA_INNER_ERROR_CODE: number = 31300000
const API_EMBEDDING_REQUEST_TIMEOUT_MS: number = 60000
const API_EMBEDDING_MODEL_KEY_PREFIX: string = 'api:openai-compatible'
const API_EMBEDDING_MAX_BATCH_SIZE: number = 64
// 常见文本 Embedding 维度远低于此值。限制异常/恶意响应，避免在主线程
// 为单个向量执行数万次转换和后处理。
const API_EMBEDDING_MAX_VECTOR_DIMENSION: number = 8192
const API_EMBEDDING_MAX_RESPONSE_CHARACTERS: number = 32 * 1024 * 1024
const API_EMBEDDING_UI_YIELD_MS: number = 16
const API_EMBEDDING_VECTOR_YIELD_INTERVAL: number = 4

export enum KnowledgeEmbeddingBackend {
  LOCAL = 'local',
  API = 'api'
}

interface StoredKnowledgeEmbeddingSelection {
  backend?: string
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

interface OpenAIEmbeddingData {
  index: number
  embedding: number[]
}

interface OpenAIEmbeddingError {
  message?: string
}

interface OpenAIEmbeddingResponse {
  data?: OpenAIEmbeddingData[]
  error?: OpenAIEmbeddingError
}

class OpenAIEmbeddingRequest {
  model: string
  input: string[]

  constructor(model: string, input: string[]) {
    this.model = model
    this.input = input
  }
}

export class KnowledgeEmbeddingSelection {
  backend: string
  providerId: string
  providerName: string
  modelId: string
  modelName: string
  endpointFingerprint: string

  constructor(
    backend: string = KnowledgeEmbeddingBackend.LOCAL,
    providerId: string = '',
    providerName: string = '',
    modelId: string = '',
    modelName: string = '',
    endpointFingerprint: string = ''
  ) {
    this.backend = backend === KnowledgeEmbeddingBackend.API
      ? KnowledgeEmbeddingBackend.API
      : KnowledgeEmbeddingBackend.LOCAL
    this.providerId = providerId
    this.providerName = providerName
    this.modelId = modelId
    this.modelName = modelName
    this.endpointFingerprint = endpointFingerprint
  }

  static createLocal(): KnowledgeEmbeddingSelection {
    return new KnowledgeEmbeddingSelection()
  }

  copy(): KnowledgeEmbeddingSelection {
    return new KnowledgeEmbeddingSelection(
      this.backend,
      this.providerId,
      this.providerName,
      this.modelId,
      this.modelName,
      this.endpointFingerprint
    )
  }

  isApi(): boolean {
    return this.backend === KnowledgeEmbeddingBackend.API
  }

  isValid(): boolean {
    if (!this.isApi()) {
      return true
    }
    return this.providerId.trim() !== '' &&
      this.modelId.trim() !== '' &&
      this.endpointFingerprint.trim() !== ''
  }

  identityKey(): string {
    if (!this.isApi()) {
      return KnowledgeEmbeddingBackend.LOCAL
    }
    return `${KnowledgeEmbeddingBackend.API}:${this.providerId}:${this.modelId}:${this.endpointFingerprint}`
  }

  displayName(): string {
    if (!this.isApi()) {
      return '本地 ArkData'
    }
    const modelLabel = this.modelName.trim() !== '' ? this.modelName : this.modelId
    if (this.providerName.trim() === '') {
      return modelLabel
    }
    return `${this.providerName} · ${modelLabel}`
  }
}

function trimTrailingSlashes(value: string): string {
  let trimmed = value
  while (trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1)
  }
  return trimmed
}

function buildStableStringFingerprint(value: string): string {
  let primaryHash = 2166136261
  let secondaryHash = 0
  for (let index = 0; index < value.length; index++) {
    const characterCode = value.charCodeAt(index)
    primaryHash = Math.imul(primaryHash ^ characterCode, 16777619) >>> 0
    secondaryHash = (Math.imul(secondaryHash, 131) + characterCode) >>> 0
  }
  return `${value.length.toString(16)}-` +
    `${primaryHash.toString(16).padStart(8, '0')}-` +
    secondaryHash.toString(16).padStart(8, '0')
}

function buildSafeModelKeyToken(value: string): string {
  const safePrefix = value.replace(/[^A-Za-z0-9._-]+/g, '_').substring(0, 96)
  return `${safePrefix}_${buildStableStringFingerprint(value)}`
}

function combineProviderBaseUrlAndPath(baseUrl: string, apiPath: string): string {
  let normalizedBaseUrl = trimTrailingSlashes(baseUrl.trim())
  let normalizedPath = apiPath.trim()
  if (normalizedPath === '') {
    return normalizedBaseUrl
  }
  if (!normalizedPath.startsWith('/')) {
    normalizedPath = `/${normalizedPath}`
  }

  if (/\/v\d+\w*$/.test(normalizedBaseUrl) || normalizedBaseUrl.endsWith('/beta')) {
    const basePathSuffix = normalizedBaseUrl.substring(normalizedBaseUrl.lastIndexOf('/'))
    if (normalizedPath.startsWith(basePathSuffix)) {
      const nextSlashIndex = normalizedPath.indexOf('/', 1)
      normalizedPath = nextSlashIndex >= 0 ? normalizedPath.substring(nextSlashIndex) : ''
    }
  }
  return normalizedBaseUrl + normalizedPath
}

export function buildKnowledgeEmbeddingEndpoint(baseUrl: string, apiPath: string = ''): string {
  let normalizedBaseUrl = baseUrl.trim()
  let normalizedApiPath = apiPath.trim()
  const baseFragmentIndex = normalizedBaseUrl.indexOf('#')
  if (baseFragmentIndex >= 0) {
    normalizedBaseUrl = normalizedBaseUrl.substring(0, baseFragmentIndex)
  }
  const pathFragmentIndex = normalizedApiPath.indexOf('#')
  if (pathFragmentIndex >= 0) {
    normalizedApiPath = normalizedApiPath.substring(0, pathFragmentIndex)
  }

  let baseQuery = ''
  const baseQueryIndex = normalizedBaseUrl.indexOf('?')
  if (baseQueryIndex >= 0) {
    baseQuery = normalizedBaseUrl.substring(baseQueryIndex + 1)
    normalizedBaseUrl = normalizedBaseUrl.substring(0, baseQueryIndex)
  }
  let pathQuery = ''
  const pathQueryIndex = normalizedApiPath.indexOf('?')
  if (pathQueryIndex >= 0) {
    pathQuery = normalizedApiPath.substring(pathQueryIndex + 1)
    normalizedApiPath = normalizedApiPath.substring(0, pathQueryIndex)
  }
  let query = ''
  if (baseQuery !== '' && pathQuery !== '') {
    query = `?${baseQuery}&${pathQuery}`
  } else if (baseQuery !== '') {
    query = `?${baseQuery}`
  } else if (pathQuery !== '') {
    query = `?${pathQuery}`
  }

  let normalized = combineProviderBaseUrlAndPath(normalizedBaseUrl, normalizedApiPath)
  normalized = trimTrailingSlashes(normalized)

  const lowerEndpoint = normalized.toLowerCase()
  const replaceableSuffixes: string[] = [
    '/chat/completions',
    '/completions',
    '/responses',
    '/models'
  ]
  let replacedKnownSuffix = false
  for (let index = 0; index < replaceableSuffixes.length; index++) {
    const suffix = replaceableSuffixes[index]
    if (lowerEndpoint.endsWith(suffix)) {
      normalized = normalized.substring(0, normalized.length - suffix.length)
      replacedKnownSuffix = true
      break
    }
  }

  if (replacedKnownSuffix) {
    normalized += '/embeddings'
  } else if (!lowerEndpoint.endsWith('/embeddings')) {
    if (apiPath.trim() !== '') {
      normalized += '/embeddings'
    } else if (/\/v\d+\w*$/.test(normalized) || normalized.includes('/compatible-mode/v1')) {
      normalized += '/embeddings'
    } else {
      normalized += '/v1/embeddings'
    }
  }
  return normalized + query
}

export function buildKnowledgeEmbeddingEndpointFingerprint(
  baseUrl: string,
  apiPath: string = '',
  customHeadersJson: string = ''
): string {
  const endpointIdentity = buildKnowledgeEmbeddingEndpoint(baseUrl, apiPath)
  return buildStableStringFingerprint(`${endpointIdentity}\n${customHeadersJson.trim()}`)
}

function buildApiEmbeddingModelKey(selection: KnowledgeEmbeddingSelection): string {
  return `${API_EMBEDDING_MODEL_KEY_PREFIX}:` +
    `${buildSafeModelKeyToken(selection.providerId)}:` +
    `${buildSafeModelKeyToken(selection.modelId)}:` +
    selection.endpointFingerprint
}

interface EmbeddingBusinessError {
  code?: number
  message?: string
}

/**
 * 知识库向量生成能力的可注入边界。实现不得记录输入原文或生成的向量。
 */
export interface KnowledgeEmbeddingProvider {
  isAvailable(): boolean
  modelKey(): string
  maxInputCharacters(): number
  embedDocuments(texts: string[]): Promise<Float32Array[]>
  embedQuery(text: string): Promise<Float32Array>
  release(): Promise<void>
}

/**
 * 使用 ArkData BASIC_MODEL 的本地文本向量实现。
 *
 * 模型按首次调用惰性加载。ArkData 当前只在 2in1 开放应用数据向量化；明确的
 * 801/31300000 会在本次运行中熔断，避免同一批文档重复触发不可用模型。
 */
export class LocalArkDataTextEmbeddingProvider implements KnowledgeEmbeddingProvider {
  private model: intelligence.TextEmbedding | null = null
  private loadingPromise: Promise<intelligence.TextEmbedding> | null = null
  private unavailable: boolean = false
  private vectorDimension: number = 0
  private lifecycleGeneration: number = 0
  private cachePath: string = ''
  private deviceSupported: boolean =
    deviceInfo.deviceType === deviceInfo.DeviceTypes.TYPE_2IN1
  private unavailableMessage: string = ''

  constructor(cachePath: string = '') {
    this.cachePath = cachePath.trim()
  }

  setCachePath(cachePath: string): void {
    const normalizedPath = cachePath.trim()
    if (normalizedPath === '' || normalizedPath === this.cachePath) {
      return
    }
    this.cachePath = normalizedPath
  }

  isAvailable(): boolean {
    return this.deviceSupported && !this.unavailable
  }

  availabilityMessage(): string {
    if (!this.deviceSupported) {
      return 'ArkData 本地文本向量目前仅支持 2in1 设备；手机和平板请使用 API Embedding'
    }
    if (this.unavailableMessage.trim() !== '') {
      return this.unavailableMessage
    }
    if (this.unavailable) {
      return 'ArkData 本地文本向量在本次运行期间不可用'
    }
    return ''
  }

  modelKey(): string {
    return ARKDATA_BASIC_TEXT_EMBEDDING_MODEL_KEY
  }

  maxInputCharacters(): number {
    return KNOWLEDGE_EMBEDDING_MAX_INPUT_CHARACTERS
  }

  async embedDocuments(texts: string[]): Promise<Float32Array[]> {
    this.validateBatch(texts)
    const batchTexts = texts.slice()
    const model = await this.ensureModel()

    let rawVectors: number[][]
    try {
      rawVectors = await model.getEmbedding(batchTexts)
    } catch (error) {
      throw this.toInvocationError(error as EmbeddingBusinessError)
    }

    if (!Array.isArray(rawVectors) || rawVectors.length !== batchTexts.length) {
      throw new Error('文本向量模型返回的批量结果数量无效')
    }

    const vectors: Float32Array[] = []
    for (let index = 0; index < rawVectors.length; index++) {
      vectors.push(this.toFloat32Vector(rawVectors[index]))
    }
    this.validateAndRememberDimensions(vectors)
    return vectors
  }

  async embedQuery(text: string): Promise<Float32Array> {
    this.validateText(text)
    const model = await this.ensureModel()

    let rawVector: number[]
    try {
      rawVector = await model.getEmbedding(text)
    } catch (error) {
      throw this.toInvocationError(error as EmbeddingBusinessError)
    }

    const vector = this.toFloat32Vector(rawVector)
    this.validateAndRememberDimensions([vector])
    return vector
  }

  async release(): Promise<void> {
    this.lifecycleGeneration++
    const loadedModel = this.model
    const pendingModel = this.loadingPromise
    this.model = null
    this.loadingPromise = null
    this.vectorDimension = 0

    let modelToRelease: intelligence.TextEmbedding | null = loadedModel
    if (modelToRelease === null && pendingModel !== null) {
      try {
        modelToRelease = await pendingModel
      } catch (error) {
        if (this.markUnavailableIfNeeded(error as EmbeddingBusinessError)) {
          throw new Error('文本向量能力在当前设备上不可用')
        }
        return
      }
    }

    if (modelToRelease === null) {
      return
    }

    try {
      await modelToRelease.releaseModel()
    } catch (error) {
      if (this.markUnavailableIfNeeded(error as EmbeddingBusinessError)) {
        throw new Error('文本向量能力在当前设备上不可用')
      }
      throw new Error('文本向量模型释放失败')
    }
  }

  private validateBatch(texts: string[]): void {
    if (!Array.isArray(texts) || texts.length === 0) {
      throw new Error('待生成向量的文本列表不能为空')
    }
    for (let index = 0; index < texts.length; index++) {
      this.validateText(texts[index])
    }
  }

  private validateText(text: string): void {
    if (typeof text !== 'string' || text.trim() === '') {
      throw new Error('待生成向量的文本不能为空')
    }
    if (text.length > KNOWLEDGE_EMBEDDING_MAX_INPUT_CHARACTERS) {
      throw new Error(`单条文本不能超过 ${KNOWLEDGE_EMBEDDING_MAX_INPUT_CHARACTERS} 个字符`)
    }
  }

  private async ensureModel(): Promise<intelligence.TextEmbedding> {
    if (!this.isAvailable()) {
      const message = this.availabilityMessage()
      throw new Error(message === '' ? '文本向量能力在当前设备上不可用' : message)
    }
    if (this.model !== null) {
      return this.model
    }

    const generation = this.lifecycleGeneration
    if (this.loadingPromise === null) {
      this.loadingPromise = this.createAndLoadModel()
    }
    const pendingModel = this.loadingPromise

    try {
      const loadedModel = await pendingModel
      if (generation !== this.lifecycleGeneration) {
        throw new Error('文本向量模型已释放，请重试')
      }
      this.model = loadedModel
      return loadedModel
    } catch (error) {
      const businessError = error as EmbeddingBusinessError
      if (this.markUnavailableIfNeeded(businessError) || this.unavailable) {
        const unavailableMessage = this.availabilityMessage()
        throw new Error(
          `${unavailableMessage === '' ? '文本向量能力在当前设备上不可用' :
            unavailableMessage}：${this.businessErrorDetail(businessError)}`
        )
      }
      if (generation !== this.lifecycleGeneration) {
        throw new Error('文本向量模型已释放，请重试')
      }
      throw new Error(`文本向量模型加载失败：${this.businessErrorDetail(businessError)}`)
    } finally {
      if (this.loadingPromise === pendingModel) {
        this.loadingPromise = null
      }
    }
  }

  private async createAndLoadModel(): Promise<intelligence.TextEmbedding> {
    let config: intelligence.ModelConfig
    if (this.cachePath === '') {
      config = {
        version: intelligence.ModelVersion.BASIC_MODEL,
        isNpuAvailable: false
      }
    } else {
      config = {
        version: intelligence.ModelVersion.BASIC_MODEL,
        isNpuAvailable: false,
        cachePath: this.cachePath
      }
    }
    let model: intelligence.TextEmbedding | null = null
    try {
      model = await intelligence.getTextEmbeddingModel(config)
      await model.loadModel()
      return model
    } catch (error) {
      if (model !== null) {
        try {
          await model.releaseModel()
        } catch (releaseError) {
        }
      }
      throw this.toInvocationError(error as EmbeddingBusinessError)
    }
  }

  private toInvocationError(error: EmbeddingBusinessError): Error {
    const detail = this.businessErrorDetail(error)
    if (this.markUnavailableIfNeeded(error)) {
      const unavailableMessage = this.availabilityMessage()
      return new Error(
        `${unavailableMessage === '' ? '文本向量能力在当前设备上不可用' :
          unavailableMessage}：${detail}`
      )
    }
    return new Error(`文本向量模型调用失败：${detail}`)
  }

  private businessErrorDetail(error: EmbeddingBusinessError): string {
    const parts: string[] = []
    if (typeof error.code === 'number') {
      parts.push(`code=${error.code}`)
    }
    if (typeof error.message === 'string' && error.message.trim() !== '') {
      parts.push(error.message.trim().substring(0, 256))
    }
    return parts.length > 0 ? parts.join('，') : '未返回具体错误'
  }

  private markUnavailableIfNeeded(error: EmbeddingBusinessError): boolean {
    const code = error.code
    if (code !== CAPABILITY_NOT_SUPPORTED_CODE && code !== ARKDATA_INNER_ERROR_CODE) {
      return false
    }
    this.unavailable = true
    this.unavailableMessage = code === CAPABILITY_NOT_SUPPORTED_CODE
      ? 'ArkData 本地文本向量在当前设备上不受支持'
      : 'ArkData 本地文本向量模型初始化发生内部错误，本次运行已降级为关键词检索'
    this.loadingPromise = null
    this.vectorDimension = 0
    return true
  }

  private toFloat32Vector(values: number[]): Float32Array {
    if (!Array.isArray(values) || values.length === 0) {
      throw new Error('文本向量模型返回了空向量')
    }
    const vector = new Float32Array(values.length)
    for (let index = 0; index < values.length; index++) {
      const value = values[index]
      if (typeof value !== 'number' || !Number.isFinite(value)) {
        throw new Error('文本向量模型返回了无效数值')
      }
      vector[index] = value
      if (!Number.isFinite(vector[index])) {
        throw new Error('文本向量模型返回了超出 Float32 范围的数值')
      }
    }
    return vector
  }

  private validateAndRememberDimensions(vectors: Float32Array[]): void {
    if (vectors.length === 0) {
      throw new Error('文本向量模型未返回结果')
    }
    const dimension = vectors[0].length
    if (dimension === 0) {
      throw new Error('文本向量模型返回了空向量')
    }
    for (let index = 1; index < vectors.length; index++) {
      if (vectors[index].length !== dimension) {
        throw new Error('文本向量模型返回的向量维度不一致')
      }
    }
    if (this.vectorDimension !== 0 && this.vectorDimension !== dimension) {
      throw new Error('文本向量模型返回的向量维度发生变化')
    }
    this.vectorDimension = dimension
  }
}

/**
 * 使用现有 OpenAI API 风格服务商的 `/embeddings` 接口生成向量。
 *
 * 只保存服务商和模型引用；每次调用都从服务商数据库读取最新地址、凭据和自定义请求头。
 * 不记录输入文本、响应向量或 API Key。
 */
export class OpenAICompatibleKnowledgeEmbeddingProvider implements KnowledgeEmbeddingProvider {
  private selection: KnowledgeEmbeddingSelection
  private vectorDimension: number = 0
  private httpService: HttpService = getHttpService()

  constructor(selection: KnowledgeEmbeddingSelection) {
    this.selection = selection.copy()
  }

  isAvailable(): boolean {
    return this.selection.isApi() && this.selection.isValid()
  }

  modelKey(): string {
    return buildApiEmbeddingModelKey(this.selection)
  }

  maxInputCharacters(): number {
    return KNOWLEDGE_EMBEDDING_MAX_INPUT_CHARACTERS
  }

  async embedDocuments(texts: string[]): Promise<Float32Array[]> {
    this.validateBatch(texts)
    return await this.requestEmbeddings(texts.slice())
  }

  async embedQuery(text: string): Promise<Float32Array> {
    this.validateText(text)
    const vectors = await this.requestEmbeddings([text])
    if (vectors.length !== 1) {
      throw new Error('向量 API 返回的查询结果数量无效')
    }
    return vectors[0]
  }

  async release(): Promise<void> {
    this.vectorDimension = 0
  }

  async validateConfiguration(): Promise<void> {
    await this.resolveProviderConfig()
  }

  private validateBatch(texts: string[]): void {
    if (!Array.isArray(texts) || texts.length === 0) {
      throw new Error('待生成向量的文本列表不能为空')
    }
    if (texts.length > API_EMBEDDING_MAX_BATCH_SIZE) {
      throw new Error(`单次最多生成 ${API_EMBEDDING_MAX_BATCH_SIZE} 条文本向量`)
    }
    for (let index = 0; index < texts.length; index++) {
      this.validateText(texts[index])
    }
  }

  private validateText(text: string): void {
    if (typeof text !== 'string' || text.trim() === '') {
      throw new Error('待生成向量的文本不能为空')
    }
    if (text.length > KNOWLEDGE_EMBEDDING_MAX_INPUT_CHARACTERS) {
      throw new Error(`单条文本不能超过 ${KNOWLEDGE_EMBEDDING_MAX_INPUT_CHARACTERS} 个字符`)
    }
  }

  private async resolveProviderConfig(): Promise<ProviderConfig> {
    const providers = await getDatabaseService().getAllProviders()
    for (let index = 0; index < providers.length; index++) {
      const provider = providers[index]
      if (provider.id !== this.selection.providerId) {
        continue
      }
      if (!provider.isEnabled) {
        throw new Error('所选向量服务商已停用')
      }
      if (provider.apiStyle !== 'openai') {
        throw new Error('所选服务商不是 OpenAI 兼容接口')
      }
      if (provider.type === 'azure') {
        throw new Error('当前版本尚不支持 Azure Embeddings 接口')
      }
      if (provider.baseUrl.trim() === '') {
        throw new Error('所选向量服务商未配置 API 地址')
      }
      const currentFingerprint = buildKnowledgeEmbeddingEndpointFingerprint(
        provider.baseUrl,
        provider.apiPath,
        provider.customHeadersJson
      )
      if (currentFingerprint !== this.selection.endpointFingerprint) {
        throw new Error('向量服务商地址或路由配置已变更，请在知识库中重新选择模型')
      }
      if (!this.isSelectedModelStillConfigured(provider)) {
        throw new Error('所选向量模型已停用或移除')
      }
      const effectiveApiKey = getEffectiveApiKey(provider.id, provider.apiKey)
      if (provider.requiresApiKey && effectiveApiKey.trim() === '') {
        throw new Error('所选向量服务商未配置 API Key')
      }
      return provider
    }
    throw new Error('未找到所选向量服务商')
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

  private async requestEmbeddings(texts: string[]): Promise<Float32Array[]> {
    const provider = await this.resolveProviderConfig()
    const endpoint = buildKnowledgeEmbeddingEndpoint(provider.baseUrl, provider.apiPath)
    const request = new OpenAIEmbeddingRequest(this.selection.modelId, texts)
    const response = await this.httpService.postWithTimeout(
      endpoint,
      JSON.stringify(request),
      this.buildHeaders(provider),
      API_EMBEDDING_REQUEST_TIMEOUT_MS
    )
    if (!response.success) {
      throw new Error(this.buildRequestError(response))
    }
    if (response.data.length > API_EMBEDDING_MAX_RESPONSE_CHARACTERS) {
      throw new Error('向量 API 返回的数据过大')
    }

    let payload: OpenAIEmbeddingResponse
    try {
      payload = JSON.parse(response.data) as OpenAIEmbeddingResponse
    } catch (_error) {
      throw new Error('向量 API 返回了无法解析的响应')
    }
    if (!Array.isArray(payload.data) || payload.data.length !== texts.length) {
      throw new Error('向量 API 返回的结果数量无效')
    }

    const vectors = new Array<Float32Array>(texts.length)
    const assigned = new Array<boolean>(texts.length)
    for (let index = 0; index < assigned.length; index++) {
      assigned[index] = false
    }
    for (let index = 0; index < payload.data.length; index++) {
      const item = payload.data[index]
      if (!Number.isFinite(item.index) ||
        !Number.isInteger(item.index) ||
        item.index < 0 ||
        item.index >= texts.length ||
        assigned[item.index]) {
        throw new Error('向量 API 返回了无效的结果序号')
      }
      vectors[item.index] = this.toFloat32Vector(item.embedding)
      assigned[item.index] = true
      if (index + 1 < payload.data.length &&
        (index + 1) % API_EMBEDDING_VECTOR_YIELD_INTERVAL === 0) {
        await this.yieldToUiFrame()
      }
    }
    for (let index = 0; index < assigned.length; index++) {
      if (!assigned[index]) {
        throw new Error('向量 API 返回的结果不完整')
      }
    }
    this.validateAndRememberDimensions(vectors)
    return vectors
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
        const payload = JSON.parse(response.data) as OpenAIEmbeddingResponse
        if (payload.error !== undefined && payload.error.message !== undefined) {
          apiMessage = payload.error.message.trim().substring(0, 240)
        }
      } catch (_error) {
      }
    }
    if (apiMessage !== '') {
      return `向量 API 请求失败（HTTP ${response.statusCode}）：${apiMessage}`
    }
    if (response.statusCode > 0) {
      return `向量 API 请求失败（HTTP ${response.statusCode}）`
    }
    return response.errorMessage.trim() !== ''
      ? `向量 API 请求失败：${response.errorMessage}`
      : '向量 API 请求失败'
  }

  private toFloat32Vector(values: number[]): Float32Array {
    if (!Array.isArray(values) || values.length === 0) {
      throw new Error('向量 API 返回了空向量')
    }
    if (values.length > API_EMBEDDING_MAX_VECTOR_DIMENSION) {
      throw new Error('向量 API 返回的向量维度过大')
    }
    const vector = new Float32Array(values.length)
    for (let index = 0; index < values.length; index++) {
      const value = values[index]
      if (typeof value !== 'number' || !Number.isFinite(value)) {
        throw new Error('向量 API 返回了无效数值')
      }
      vector[index] = value
      if (!Number.isFinite(vector[index])) {
        throw new Error('向量 API 返回了超出 Float32 范围的数值')
      }
    }
    return vector
  }

  private validateAndRememberDimensions(vectors: Float32Array[]): void {
    if (vectors.length === 0 || vectors[0].length === 0) {
      throw new Error('向量 API 未返回有效结果')
    }
    const dimension = vectors[0].length
    for (let index = 1; index < vectors.length; index++) {
      if (vectors[index].length !== dimension) {
        throw new Error('向量 API 返回的向量维度不一致')
      }
    }
    if (this.vectorDimension !== 0 && this.vectorDimension !== dimension) {
      throw new Error('向量 API 返回的向量维度发生变化')
    }
    this.vectorDimension = dimension
  }

  private async yieldToUiFrame(): Promise<void> {
    await new Promise<void>((resolve): void => {
      setTimeout(resolve, API_EMBEDDING_UI_YIELD_MS)
    })
  }
}

/**
 * 面向知识库索引与查询调用方的服务。构造函数支持注入测试或替代 Provider。
 */
export class KnowledgeEmbeddingService implements KnowledgeEmbeddingProvider {
  private static instance: KnowledgeEmbeddingService | null = null
  private provider: KnowledgeEmbeddingProvider
  private selection: KnowledgeEmbeddingSelection = KnowledgeEmbeddingSelection.createLocal()
  private initialized: boolean = false
  private initPromise: Promise<void> | null = null
  private customProviderInjected: boolean = false
  private localCachePath: string = ''

  constructor(provider?: KnowledgeEmbeddingProvider) {
    if (provider !== undefined) {
      this.provider = provider
      this.customProviderInjected = true
    } else {
      this.provider = new LocalArkDataTextEmbeddingProvider()
    }
  }

  static getInstance(): KnowledgeEmbeddingService {
    if (KnowledgeEmbeddingService.instance === null) {
      KnowledgeEmbeddingService.instance = new KnowledgeEmbeddingService()
    }
    return KnowledgeEmbeddingService.instance
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

  getSelection(): KnowledgeEmbeddingSelection {
    return this.selection.copy()
  }

  configureLocalCachePath(cachePath: string): void {
    const normalizedPath = cachePath.trim()
    if (normalizedPath === '') {
      return
    }
    this.localCachePath = normalizedPath
    if (this.provider instanceof LocalArkDataTextEmbeddingProvider) {
      this.provider.setCachePath(normalizedPath)
    }
  }

  isApiSelected(): boolean {
    return this.selection.isApi()
  }

  async validateSelection(selection: KnowledgeEmbeddingSelection): Promise<void> {
    if (!selection.isValid()) {
      throw new Error('向量模型选择无效')
    }
    if (!selection.isApi()) {
      const candidate = new LocalArkDataTextEmbeddingProvider(this.localCachePath)
      if (!candidate.isAvailable()) {
        throw new Error(candidate.availabilityMessage())
      }
      return
    }
    const candidate = new OpenAICompatibleKnowledgeEmbeddingProvider(selection)
    await candidate.validateConfiguration()
  }

  async applySelection(selection: KnowledgeEmbeddingSelection): Promise<boolean> {
    await this.initialize()
    if (this.customProviderInjected) {
      throw new Error('测试注入的向量服务不支持运行期切换')
    }
    if (!selection.isValid()) {
      throw new Error('向量模型选择无效')
    }
    const nextSelection = selection.copy()
    if (nextSelection.identityKey() === this.selection.identityKey()) {
      return false
    }
    const nextProvider = this.createProvider(nextSelection)
    await getPreferencesService().setString(
      PreferenceKeys.KNOWLEDGE_EMBEDDING_SELECTION_JSON,
      JSON.stringify(nextSelection)
    )
    const previousProvider = this.provider
    this.selection = nextSelection
    this.provider = nextProvider
    try {
      await previousProvider.release()
    } catch (_error) {
      console.warn('KnowledgeEmbeddingService', 'Previous embedding provider release failed')
    }
    return true
  }

  isAvailable(): boolean {
    return this.provider.isAvailable()
  }

  availabilityMessage(): string {
    if (this.provider.isAvailable()) {
      return ''
    }
    if (this.provider instanceof LocalArkDataTextEmbeddingProvider) {
      return this.provider.availabilityMessage()
    }
    return '所选向量模型在本次运行期间不可用'
  }

  modelKey(): string {
    return this.provider.modelKey()
  }

  maxInputCharacters(): number {
    return this.provider.maxInputCharacters()
  }

  async embedDocuments(texts: string[]): Promise<Float32Array[]> {
    return await this.provider.embedDocuments(texts)
  }

  async embedQuery(text: string): Promise<Float32Array> {
    return await this.provider.embedQuery(text)
  }

  async release(): Promise<void> {
    await this.provider.release()
  }

  private async loadPersistedSelection(): Promise<void> {
    const raw = await getPreferencesService().getString(
      PreferenceKeys.KNOWLEDGE_EMBEDDING_SELECTION_JSON,
      ''
    )
    const restored = this.parsePersistedSelection(raw)
    this.selection = restored
    this.provider = this.createProvider(restored)
  }

  private parsePersistedSelection(raw: string): KnowledgeEmbeddingSelection {
    if (raw.trim() === '') {
      return KnowledgeEmbeddingSelection.createLocal()
    }
    try {
      const stored = JSON.parse(raw) as StoredKnowledgeEmbeddingSelection
      const selection = new KnowledgeEmbeddingSelection(
        stored.backend !== undefined ? stored.backend : KnowledgeEmbeddingBackend.LOCAL,
        stored.providerId !== undefined ? stored.providerId : '',
        stored.providerName !== undefined ? stored.providerName : '',
        stored.modelId !== undefined ? stored.modelId : '',
        stored.modelName !== undefined ? stored.modelName : '',
        stored.endpointFingerprint !== undefined ? stored.endpointFingerprint : ''
      )
      return selection.isValid() ? selection : KnowledgeEmbeddingSelection.createLocal()
    } catch (_error) {
      return KnowledgeEmbeddingSelection.createLocal()
    }
  }

  private createProvider(selection: KnowledgeEmbeddingSelection): KnowledgeEmbeddingProvider {
    if (selection.isApi()) {
      return new OpenAICompatibleKnowledgeEmbeddingProvider(selection)
    }
    return new LocalArkDataTextEmbeddingProvider(this.localCachePath)
  }
}

export function getKnowledgeEmbeddingService(): KnowledgeEmbeddingService {
  return KnowledgeEmbeddingService.getInstance()
}
