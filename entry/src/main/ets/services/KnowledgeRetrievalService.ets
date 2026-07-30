import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { util } from '@kit.ArkTS'
import { retrieval } from '@kit.DataAugmentationKit'
import {
  getKnowledgeEmbeddingService,
  KnowledgeEmbeddingProvider
} from './KnowledgeEmbeddingService'
import { projectKnowledgeVector } from './KnowledgeVectorProjection'

const DEFAULT_TOP_K: number = 5
const MIN_TOP_K: number = 1
const MAX_TOP_K: number = 10
const MAX_QUERY_BYTES: number = 1000
const MAX_DOCUMENT_IDS: number = 100
const MAX_DOCUMENT_ID_CHARACTERS: number = 512
const MAX_TOTAL_RESULT_CHARACTERS: number = 12000
const MAX_TITLE_CHARACTERS: number = 512
const MAX_LOCATOR_CHARACTERS: number = 1024
const INVERTED_INDEX_RECALL_NAME: string = 'knowledge_inverted_index'
const INVERTED_INDEX_BM25_WEIGHT: number = 1.0
const INVERTED_INDEX_TITLE_WEIGHT: number = 2.0
const INVERTED_INDEX_CONTENT_WEIGHT: number = 1.0
const VECTOR_RECALL_NAME: string = 'knowledge_vector_index'
const HYBRID_MIN_DEEP_SIZE: number = 20
const HYBRID_DEEP_SIZE_MULTIPLIER: number = 4

export const KNOWLEDGE_FTS_TABLE_NAME: string = 'knowledge_chunks_fts'
export const KNOWLEDGE_CHUNK_ID_COLUMN: string = 'chunk_id'
export const KNOWLEDGE_DOCUMENT_ID_COLUMN: string = 'document_id'
export const KNOWLEDGE_TITLE_COLUMN: string = 'title'
export const KNOWLEDGE_LOCATOR_COLUMN: string = 'locator'
export const KNOWLEDGE_CONTENT_COLUMN: string = 'content'

export function isValidKnowledgeDocumentId(value: string): boolean {
  if (typeof value !== 'string') {
    return false
  }
  const normalized = value.trim()
  if (normalized === '' || normalized.length > MAX_DOCUMENT_ID_CHARACTERS ||
    normalized.indexOf(',') >= 0) {
    return false
  }
  for (let index = 0; index < normalized.length; index++) {
    const code = normalized.charCodeAt(index)
    if (code <= 0x1F || code === 0x7F) {
      return false
    }
  }
  return true
}

export enum KnowledgeSearchStatus {
  OK = 'ok',
  NO_HITS = 'no_hits',
  UNAVAILABLE = 'unavailable',
  ERROR = 'error'
}

export class KnowledgeSearchRequest {
  query: string = ''
  topK: number = DEFAULT_TOP_K
  documentIds: string[] = []

  constructor(query: string = '', topK: number = DEFAULT_TOP_K, documentIds: string[] = []) {
    this.query = query
    this.topK = topK
    this.documentIds = documentIds.slice()
  }
}

export class KnowledgeSearchHit {
  documentId: string = ''
  chunkId: string = ''
  title: string = ''
  locator: string = ''
  score: number = 0
  content: string = ''

  constructor(
    documentId: string = '',
    chunkId: string = '',
    title: string = '',
    locator: string = '',
    score: number = 0,
    content: string = ''
  ) {
    this.documentId = documentId
    this.chunkId = chunkId
    this.title = title
    this.locator = locator
    this.score = score
    this.content = content
  }
}

export class KnowledgeSearchResponse {
  status: KnowledgeSearchStatus = KnowledgeSearchStatus.NO_HITS
  code: string = ''
  message: string = ''
  query: string = ''
  topK: number = DEFAULT_TOP_K
  hits: KnowledgeSearchHit[] = []
  truncated: boolean = false
  queryTruncated: boolean = false

  constructor(
    status: KnowledgeSearchStatus,
    query: string,
    topK: number,
    code: string = '',
    message: string = ''
  ) {
    this.status = status
    this.query = query
    this.topK = topK
    this.code = code
    this.message = message
  }
}

export interface KnowledgeRetrievalAdapter {
  isAvailable(): boolean
  search(request: KnowledgeSearchRequest): Promise<KnowledgeSearchResponse>
}

export interface KnowledgeReadyDocumentProvider {
  listReadyDocumentIds(): Promise<string[]>
}

export interface KnowledgeVectorReadyDocumentProvider {
  listVectorReadyDocumentIds(documentIds: string[]): Promise<string[]>
}

export interface KnowledgeVectorHealthObserver {
  onVectorDimensionMismatch(expectedDimension: number, actualDimension: number): void
}

export interface DataAugmentationInvertedIndexConfiguration {
  context: common.BaseContext
  storeConfig: relationalStore.StoreConfig
  ftsTableName: string
  fromClause?: string
  primaryKeyColumns: string[]
  documentIdColumn: string
  chunkIdColumn: string
  titleColumn: string
  locatorColumn: string
  contentColumn: string
}

export interface DataAugmentationVectorIndexConfiguration {
  context: common.BaseContext
  storeConfig: relationalStore.StoreConfig
  tableName: string
  primaryKeyColumns: string[]
  documentIdColumn: string
  chunkIdColumn: string
  titleColumn: string
  locatorColumn: string
  contentColumn: string
  embeddingColumn: string
  dimension: number
}

interface RetrievalBusinessError {
  code?: number
  message?: string
}

class EffectiveRetrievalColumns {
  primaryKeyColumns: string[] = []
  documentIdColumn: string = ''
  chunkIdColumn: string = ''
  titleColumn: string = ''
  locatorColumn: string = ''
  contentColumn: string = ''
  responseColumns: string[] = []
}

class EffectiveInvertedIndexConfiguration extends EffectiveRetrievalColumns {
  context: common.BaseContext
  storeConfig: relationalStore.StoreConfig
  ftsTableName: string
  fromClause: string

  constructor(configuration: DataAugmentationInvertedIndexConfiguration) {
    super()
    this.context = configuration.context
    this.storeConfig = configuration.storeConfig
    this.ftsTableName = configuration.ftsTableName.trim()
    const normalizedFromClause = configuration.fromClause === undefined ? '' : configuration.fromClause.trim()
    this.fromClause = normalizedFromClause === '' ? this.ftsTableName : normalizedFromClause
    this.primaryKeyColumns = normalizeColumnNames(configuration.primaryKeyColumns)
    this.documentIdColumn = configuration.documentIdColumn.trim()
    this.chunkIdColumn = configuration.chunkIdColumn.trim()
    this.titleColumn = configuration.titleColumn.trim()
    this.locatorColumn = configuration.locatorColumn.trim()
    this.contentColumn = configuration.contentColumn.trim()
    this.responseColumns = buildResponseColumns(this)
  }
}

class EffectiveVectorIndexConfiguration extends EffectiveRetrievalColumns {
  context: common.BaseContext
  storeConfig: relationalStore.StoreConfig
  tableName: string
  embeddingColumn: string
  dimension: number

  constructor(configuration: DataAugmentationVectorIndexConfiguration) {
    super()
    this.context = configuration.context
    this.storeConfig = configuration.storeConfig
    this.tableName = configuration.tableName.trim()
    this.primaryKeyColumns = normalizeColumnNames(configuration.primaryKeyColumns)
    this.documentIdColumn = configuration.documentIdColumn.trim()
    this.chunkIdColumn = configuration.chunkIdColumn.trim()
    this.titleColumn = configuration.titleColumn.trim()
    this.locatorColumn = configuration.locatorColumn.trim()
    this.contentColumn = configuration.contentColumn.trim()
    this.embeddingColumn = configuration.embeddingColumn.trim()
    this.dimension = configuration.dimension
    this.responseColumns = buildResponseColumns(this)
  }
}

function appendUniqueColumn(columns: string[], column: string): void {
  if (column !== '' && columns.indexOf(column) < 0) {
    columns.push(column)
  }
}

function normalizeColumnNames(columns: string[]): string[] {
  const normalized: string[] = []
  for (let index = 0; index < columns.length; index++) {
    appendUniqueColumn(normalized, columns[index].trim())
  }
  return normalized
}

function buildResponseColumns(configuration: EffectiveRetrievalColumns): string[] {
  const columns: string[] = []
  appendUniqueColumn(columns, configuration.documentIdColumn)
  appendUniqueColumn(columns, configuration.chunkIdColumn)
  appendUniqueColumn(columns, configuration.titleColumn)
  appendUniqueColumn(columns, configuration.locatorColumn)
  appendUniqueColumn(columns, configuration.contentColumn)
  return columns
}

function buildUnavailableResponse(
  query: string,
  topK: number,
  code: string,
  message: string
): KnowledgeSearchResponse {
  return new KnowledgeSearchResponse(KnowledgeSearchStatus.UNAVAILABLE, query, topK, code, message)
}

function buildErrorResponse(query: string, topK: number, code: string, message: string): KnowledgeSearchResponse {
  return new KnowledgeSearchResponse(KnowledgeSearchStatus.ERROR, query, topK, code, message)
}

function buildNoHitsResponse(query: string, topK: number): KnowledgeSearchResponse {
  return new KnowledgeSearchResponse(
    KnowledgeSearchStatus.NO_HITS,
    query,
    topK,
    'no_hits',
    '没有检索到相关知识库内容'
  )
}

function stringFromColumn(
  columns: Record<string, relationalStore.ValueType>,
  columnName: string
): string {
  if (columnName === '') {
    return ''
  }
  const value = columns[columnName]
  if (value === null) {
    return ''
  }
  if (typeof value === 'string') {
    return value
  }
  if (typeof value === 'number' || typeof value === 'boolean' || typeof value === 'bigint') {
    return value.toString()
  }
  return ''
}

function mapRetrievalItem(
  item: retrieval.ItemInfo,
  configuration: EffectiveRetrievalColumns
): KnowledgeSearchHit | null {
  const content = stringFromColumn(item.columns, configuration.contentColumn).trim()
  if (content === '') {
    return null
  }

  let documentId = stringFromColumn(item.columns, configuration.documentIdColumn).trim()
  let chunkId = stringFromColumn(item.columns, configuration.chunkIdColumn).trim()
  if (documentId === '') {
    documentId = item.primaryKey
  }
  if (chunkId === '') {
    chunkId = item.primaryKey
  }

  const title = stringFromColumn(item.columns, configuration.titleColumn).trim()
  const locator = stringFromColumn(item.columns, configuration.locatorColumn).trim()
  const score = Number.isFinite(item.score) && item.score >= 0 ? item.score : 0
  return new KnowledgeSearchHit(documentId, chunkId, title, locator, score, content)
}

/**
 * Data Augmentation Kit 的纯倒排索引检索适配器。
 *
 * 本适配器只调用 retrieval.getRetriever/retrieveRdb，不调用 rag 或
 * knowledgeProcessor，也不会拼装、修改或注入任何模型提示词。
 */
export class DataAugmentationInvertedIndexAdapter implements KnowledgeRetrievalAdapter {
  private configuration: EffectiveInvertedIndexConfiguration | null = null
  private retriever: retrieval.Retriever | null = null
  private dataSnapshotGeneration: number = 0
  private configurationError: string = '知识库检索尚未配置'

  configure(configuration: DataAugmentationInvertedIndexConfiguration): void {
    const effective = new EffectiveInvertedIndexConfiguration(configuration)
    const validationError = this.validateConfiguration(effective)
    this.invalidateDataSnapshot()
    if (validationError !== '') {
      this.configuration = null
      this.configurationError = validationError
      return
    }
    this.configuration = effective
    this.configurationError = ''
  }

  clearConfiguration(): void {
    this.configuration = null
    this.invalidateDataSnapshot()
    this.configurationError = '知识库检索尚未配置'
  }

  invalidateDataSnapshot(): void {
    // A cached retriever may keep the database view from the time it was created.
    this.dataSnapshotGeneration += 1
    this.retriever = null
  }

  isConfigured(): boolean {
    return this.configuration !== null
  }

  isAvailable(): boolean {
    return this.isConfigured()
  }

  async search(request: KnowledgeSearchRequest): Promise<KnowledgeSearchResponse> {
    const configuration = this.configuration
    if (configuration === null) {
      return buildUnavailableResponse(
        request.query,
        request.topK,
        'retrieval_not_configured',
        this.configurationError
      )
    }

    try {
      const retriever = await this.getOrCreateRetriever(configuration)
      const recallCondition = this.buildRecallCondition(configuration, request)
      const recallConditions: retrieval.RecallCondition[] = [recallCondition]
      const condition: retrieval.RetrievalCondition = {
        recallConditions: recallConditions,
        resultCount: request.topK
      }
      const records = await retriever.retrieveRdb(request.query, condition)
      const hits: KnowledgeSearchHit[] = []
      for (let index = 0; index < records.records.length; index++) {
        const hit = mapRetrievalItem(records.records[index], configuration)
        if (hit === null || !this.matchesDocumentFilter(hit.documentId, request.documentIds)) {
          continue
        }
        hits.push(hit)
        if (hits.length >= request.topK) {
          break
        }
      }

      if (hits.length === 0) {
        return buildNoHitsResponse(request.query, request.topK)
      }
      const response = new KnowledgeSearchResponse(KnowledgeSearchStatus.OK, request.query, request.topK)
      response.hits = hits
      return response
    } catch (error) {
      const businessError = error as RetrievalBusinessError
      console.error(
        'KnowledgeRetrievalService',
        `Data Augmentation Kit inverted retrieval failed: code=${businessError.code}`
      )
      if (businessError.code === 801) {
        return buildUnavailableResponse(
          request.query,
          request.topK,
          'retrieval_capability_unavailable',
          '当前设备不支持知识库检索能力'
        )
      }
      return buildErrorResponse(
        request.query,
        request.topK,
        'retrieval_failed',
        '知识库检索失败'
      )
    }
  }

  private validateConfiguration(configuration: EffectiveInvertedIndexConfiguration): string {
    if (configuration.ftsTableName === '') {
      return '倒排索引表名未配置'
    }
    if (configuration.fromClause === '') {
      return '倒排索引查询来源未配置'
    }
    if (configuration.primaryKeyColumns.length === 0) {
      return '倒排索引主键列未配置'
    }
    if (configuration.documentIdColumn === '') {
      return '文档 ID 列未配置'
    }
    if (configuration.chunkIdColumn === '') {
      return '分块 ID 列未配置'
    }
    if (configuration.contentColumn === '') {
      return '内容列未配置'
    }
    return ''
  }

  private async getOrCreateRetriever(
    configuration: EffectiveInvertedIndexConfiguration
  ): Promise<retrieval.Retriever> {
    if (this.retriever !== null) {
      return this.retriever
    }
    const snapshotGeneration = this.dataSnapshotGeneration
    const channelConfig: retrieval.ChannelConfig = {
      channelType: retrieval.ChannelType.INVERTED_INDEX_DATABASE,
      context: configuration.context,
      dbConfig: configuration.storeConfig
    }
    const channelConfigs: retrieval.ChannelConfig[] = [channelConfig]
    const retrievalConfig: retrieval.RetrievalConfig = {
      channelConfigs: channelConfigs
    }
    const retriever = await retrieval.getRetriever(retrievalConfig)
    if (snapshotGeneration === this.dataSnapshotGeneration) {
      this.retriever = retriever
    }
    return retriever
  }

  private buildRecallCondition(
    configuration: EffectiveInvertedIndexConfiguration,
    request: KnowledgeSearchRequest
  ): retrieval.InvertedIndexRecallCondition {
    const columnWeight: Record<string, number> = {}
    if (configuration.titleColumn !== '' &&
      configuration.titleColumn !== configuration.contentColumn) {
      columnWeight[configuration.titleColumn] = INVERTED_INDEX_TITLE_WEIGHT
    }
    columnWeight[configuration.contentColumn] = INVERTED_INDEX_CONTENT_WEIGHT
    const bm25Strategy: retrieval.Bm25Strategy = {
      bm25Weight: INVERTED_INDEX_BM25_WEIGHT,
      columnWeight: columnWeight
    }
    const condition: retrieval.InvertedIndexRecallCondition = {
      ftsTableName: configuration.ftsTableName,
      fromClause: configuration.fromClause,
      primaryKey: configuration.primaryKeyColumns.slice(),
      responseColumns: configuration.responseColumns.slice(),
      invertedIndexStrategies: [bm25Strategy],
      recallName: INVERTED_INDEX_RECALL_NAME,
      deepSize: request.topK
    }
    if (request.documentIds.length > 0) {
      const documentFilter: retrieval.FilterInfo = {
        columns: [configuration.documentIdColumn],
        operator: retrieval.Operator.OP_IN,
        filterValue: request.documentIds.join(',')
      }
      condition.filters = [documentFilter]
    }
    return condition
  }

  private matchesDocumentFilter(documentId: string, documentIds: string[]): boolean {
    if (documentIds.length === 0) {
      return true
    }
    return documentIds.indexOf(documentId) >= 0
  }
}

/**
 * Data Augmentation Kit 的本地混合检索适配器。
 *
 * 文档向量在导入/重建时生成；查询向量只会在 search() 中生成。生产调用中
 * search() 仅由 knowledge_search 的真实工具 executor 到达，不参与工具曝光，
 * 也不会把命中内容拼入任何模型提示词。任一向量能力失败均透明回退 BM25。
 */
export class DataAugmentationHybridAdapter implements KnowledgeRetrievalAdapter {
  private invertedAdapter: DataAugmentationInvertedIndexAdapter =
    new DataAugmentationInvertedIndexAdapter()
  private invertedConfiguration: EffectiveInvertedIndexConfiguration | null = null
  private vectorConfiguration: EffectiveVectorIndexConfiguration | null = null
  private embeddingProvider: KnowledgeEmbeddingProvider
  private vectorReadyDocumentProvider: KnowledgeVectorReadyDocumentProvider | null = null
  private vectorHealthObserver: KnowledgeVectorHealthObserver | null = null
  private retriever: retrieval.Retriever | null = null
  private dataSnapshotGeneration: number = 0

  constructor(embeddingProvider: KnowledgeEmbeddingProvider = getKnowledgeEmbeddingService()) {
    this.embeddingProvider = embeddingProvider
  }

  configure(configuration: DataAugmentationInvertedIndexConfiguration): void {
    this.invertedAdapter.configure(configuration)
    const effective = new EffectiveInvertedIndexConfiguration(configuration)
    if (this.validateInvertedConfiguration(effective) === '') {
      this.invertedConfiguration = effective
    } else {
      this.invertedConfiguration = null
    }
    this.invalidateHybridDataSnapshot()
  }

  configureVector(configuration: DataAugmentationVectorIndexConfiguration | null): void {
    this.invalidateHybridDataSnapshot()
    if (configuration === null) {
      this.vectorConfiguration = null
      return
    }
    const effective = new EffectiveVectorIndexConfiguration(configuration)
    if (this.validateVectorConfiguration(effective) !== '') {
      this.vectorConfiguration = null
      return
    }
    this.vectorConfiguration = effective
  }

  setVectorReadyDocumentProvider(provider: KnowledgeVectorReadyDocumentProvider | null): void {
    this.vectorReadyDocumentProvider = provider
  }

  setVectorHealthObserver(observer: KnowledgeVectorHealthObserver | null): void {
    this.vectorHealthObserver = observer
  }

  clearConfiguration(): void {
    this.invertedConfiguration = null
    this.vectorConfiguration = null
    this.invalidateHybridDataSnapshot()
    this.invertedAdapter.clearConfiguration()
  }

  invalidateDataSnapshot(): void {
    // Refresh both paths so later FTS/vector mutations are visible to the next query.
    this.invalidateHybridDataSnapshot()
    this.invertedAdapter.invalidateDataSnapshot()
  }

  private invalidateHybridDataSnapshot(): void {
    this.dataSnapshotGeneration += 1
    this.retriever = null
  }

  isVectorConfigured(): boolean {
    return this.vectorConfiguration !== null
  }

  isAvailable(): boolean {
    return this.invertedAdapter.isAvailable()
  }

  async search(request: KnowledgeSearchRequest): Promise<KnowledgeSearchResponse> {
    const invertedConfiguration = this.invertedConfiguration
    const vectorConfiguration = this.vectorConfiguration
    const vectorReadyDocumentProvider = this.vectorReadyDocumentProvider
    if (invertedConfiguration === null || vectorConfiguration === null ||
      vectorReadyDocumentProvider === null || !this.embeddingProvider.isAvailable()) {
      return await this.invertedAdapter.search(request)
    }

    try {
      const embeddingModelKey = this.embeddingProvider.modelKey()
      const vectorDocumentIds = await vectorReadyDocumentProvider
        .listVectorReadyDocumentIds(request.documentIds)
      if (vectorDocumentIds.length === 0 ||
        embeddingModelKey !== this.embeddingProvider.modelKey()) {
        return await this.invertedAdapter.search(request)
      }
      const queryForEmbedding = this.clampEmbeddingInput(
        request.query,
        this.embeddingProvider.maxInputCharacters()
      )
      const rawQueryVector = await this.embeddingProvider.embedQuery(queryForEmbedding)
      const queryVector = projectKnowledgeVector(rawQueryVector)
      if (embeddingModelKey !== this.embeddingProvider.modelKey()) {
        return await this.invertedAdapter.search(request)
      }
      if (queryVector.length !== vectorConfiguration.dimension) {
        this.vectorConfiguration = null
        this.invalidateHybridDataSnapshot()
        if (this.vectorHealthObserver !== null) {
          this.vectorHealthObserver.onVectorDimensionMismatch(
            vectorConfiguration.dimension,
            queryVector.length
          )
        }
        console.warn(
          'KnowledgeRetrievalService',
          `Vector dimension mismatch: expected=${vectorConfiguration.dimension}, actual=${queryVector.length}`
        )
        return await this.invertedAdapter.search(request)
      }

      const retriever = await this.getOrCreateRetriever(
        invertedConfiguration,
        vectorConfiguration
      )
      const deepSize = Math.max(
        HYBRID_MIN_DEEP_SIZE,
        request.topK * HYBRID_DEEP_SIZE_MULTIPLIER
      )
      const recallConditions: retrieval.RecallCondition[] = [
        this.buildInvertedRecallCondition(invertedConfiguration, request, deepSize),
        this.buildVectorRecallCondition(
          vectorConfiguration,
          new KnowledgeSearchRequest(request.query, request.topK, vectorDocumentIds),
          queryVector,
          deepSize
        )
      ]
      const rerankMethod: retrieval.RerankMethod = {
        rerankType: retrieval.RerankType.RRF
      }
      const condition: retrieval.RetrievalCondition = {
        recallConditions: recallConditions,
        rerankMethod: rerankMethod,
        resultCount: request.topK
      }
      if (embeddingModelKey !== this.embeddingProvider.modelKey()) {
        return await this.invertedAdapter.search(request)
      }
      const records = await retriever.retrieveRdb(request.query, condition)
      if (embeddingModelKey !== this.embeddingProvider.modelKey()) {
        return await this.invertedAdapter.search(request)
      }
      const response = this.mapRecords(records, vectorConfiguration, request)
      if (response.status === KnowledgeSearchStatus.NO_HITS) {
        return await this.invertedAdapter.search(request)
      }
      return response
    } catch (error) {
      const businessError = error as RetrievalBusinessError
      console.warn(
        'KnowledgeRetrievalService',
        `Hybrid vector retrieval unavailable, falling back to BM25: code=${businessError.code}`
      )
      return await this.invertedAdapter.search(request)
    }
  }

  private validateInvertedConfiguration(
    configuration: EffectiveInvertedIndexConfiguration
  ): string {
    if (configuration.ftsTableName === '' || configuration.fromClause === '') {
      return '倒排索引表未配置'
    }
    if (configuration.primaryKeyColumns.length === 0 ||
      configuration.documentIdColumn === '' ||
      configuration.chunkIdColumn === '' ||
      configuration.contentColumn === '') {
      return '倒排索引字段未配置'
    }
    return ''
  }

  private validateVectorConfiguration(configuration: EffectiveVectorIndexConfiguration): string {
    if (configuration.tableName === '') {
      return '向量表未配置'
    }
    if (configuration.primaryKeyColumns.length === 0 ||
      configuration.documentIdColumn === '' ||
      configuration.chunkIdColumn === '' ||
      configuration.contentColumn === '' ||
      configuration.embeddingColumn === '') {
      return '向量索引字段未配置'
    }
    if (!Number.isFinite(configuration.dimension) ||
      !Number.isInteger(configuration.dimension) ||
      configuration.dimension <= 0) {
      return '向量维度无效'
    }
    return ''
  }

  private async getOrCreateRetriever(
    invertedConfiguration: EffectiveInvertedIndexConfiguration,
    vectorConfiguration: EffectiveVectorIndexConfiguration
  ): Promise<retrieval.Retriever> {
    if (this.retriever !== null) {
      return this.retriever
    }
    const snapshotGeneration = this.dataSnapshotGeneration
    const channelConfigs: retrieval.ChannelConfig[] = [
      {
        channelType: retrieval.ChannelType.INVERTED_INDEX_DATABASE,
        context: invertedConfiguration.context,
        dbConfig: invertedConfiguration.storeConfig
      },
      {
        channelType: retrieval.ChannelType.VECTOR_DATABASE,
        context: vectorConfiguration.context,
        dbConfig: vectorConfiguration.storeConfig
      }
    ]
    const retriever = await retrieval.getRetriever({ channelConfigs: channelConfigs })
    if (snapshotGeneration === this.dataSnapshotGeneration) {
      this.retriever = retriever
    }
    return retriever
  }

  private buildInvertedRecallCondition(
    configuration: EffectiveInvertedIndexConfiguration,
    request: KnowledgeSearchRequest,
    deepSize: number
  ): retrieval.InvertedIndexRecallCondition {
    const columnWeight: Record<string, number> = {}
    if (configuration.titleColumn !== '' &&
      configuration.titleColumn !== configuration.contentColumn) {
      columnWeight[configuration.titleColumn] = INVERTED_INDEX_TITLE_WEIGHT
    }
    columnWeight[configuration.contentColumn] = INVERTED_INDEX_CONTENT_WEIGHT
    const bm25Strategy: retrieval.Bm25Strategy = {
      bm25Weight: INVERTED_INDEX_BM25_WEIGHT,
      columnWeight: columnWeight
    }
    const condition: retrieval.InvertedIndexRecallCondition = {
      ftsTableName: configuration.ftsTableName,
      fromClause: configuration.fromClause,
      primaryKey: configuration.primaryKeyColumns.slice(),
      responseColumns: configuration.responseColumns.slice(),
      invertedIndexStrategies: [bm25Strategy],
      recallName: INVERTED_INDEX_RECALL_NAME,
      deepSize: deepSize
    }
    const filters = this.buildDocumentFilters(configuration.documentIdColumn, request.documentIds)
    if (filters.length > 0) {
      condition.filters = filters
    }
    return condition
  }

  private buildVectorRecallCondition(
    configuration: EffectiveVectorIndexConfiguration,
    request: KnowledgeSearchRequest,
    queryVector: Float32Array,
    deepSize: number
  ): retrieval.VectorRecallCondition {
    const vectorQuery: retrieval.VectorQuery = {
      column: configuration.embeddingColumn,
      value: queryVector
    }
    const condition: retrieval.VectorRecallCondition = {
      vectorQuery: vectorQuery,
      fromClause: configuration.tableName,
      primaryKey: configuration.primaryKeyColumns.slice(),
      responseColumns: configuration.responseColumns.slice(),
      recallName: VECTOR_RECALL_NAME,
      deepSize: deepSize
    }
    const filters = this.buildDocumentFilters(configuration.documentIdColumn, request.documentIds)
    if (filters.length > 0) {
      condition.filters = filters
    }
    return condition
  }

  private buildDocumentFilters(column: string, documentIds: string[]): retrieval.FilterInfo[] {
    if (documentIds.length === 0) {
      return []
    }
    const filter: retrieval.FilterInfo = {
      columns: [column],
      operator: retrieval.Operator.OP_IN,
      filterValue: documentIds.join(',')
    }
    return [filter]
  }

  private mapRecords(
    records: retrieval.RdbRecords,
    configuration: EffectiveRetrievalColumns,
    request: KnowledgeSearchRequest
  ): KnowledgeSearchResponse {
    const hits: KnowledgeSearchHit[] = []
    for (let index = 0; index < records.records.length; index++) {
      const hit = mapRetrievalItem(records.records[index], configuration)
      if (hit === null ||
        (request.documentIds.length > 0 && request.documentIds.indexOf(hit.documentId) < 0)) {
        continue
      }
      hits.push(hit)
      if (hits.length >= request.topK) {
        break
      }
    }
    if (hits.length === 0) {
      return buildNoHitsResponse(request.query, request.topK)
    }
    const response = new KnowledgeSearchResponse(
      KnowledgeSearchStatus.OK,
      request.query,
      request.topK
    )
    response.hits = hits
    return response
  }

  private clampEmbeddingInput(value: string, maxCharacters: number): string {
    if (!Number.isFinite(maxCharacters) || maxCharacters < 1 || value.length <= maxCharacters) {
      return value
    }
    let length = Math.floor(maxCharacters)
    if (length > 0 && length < value.length) {
      const code = value.charCodeAt(length - 1)
      if (code >= 0xD800 && code <= 0xDBFF) {
        length--
      }
    }
    return value.substring(0, length)
  }
}

/**
 * 知识库纯检索服务。模型提示词与工具编排不属于本服务的职责。
 */
export class KnowledgeRetrievalService {
  private static instance: KnowledgeRetrievalService | null = null
  private adapter: KnowledgeRetrievalAdapter | null = null
  private readyDocumentProvider: KnowledgeReadyDocumentProvider | null = null

  private constructor() {
  }

  static getInstance(): KnowledgeRetrievalService {
    if (KnowledgeRetrievalService.instance === null) {
      KnowledgeRetrievalService.instance = new KnowledgeRetrievalService()
    }
    return KnowledgeRetrievalService.instance
  }

  setAdapter(adapter: KnowledgeRetrievalAdapter | null): void {
    this.adapter = adapter
  }

  setReadyDocumentProvider(provider: KnowledgeReadyDocumentProvider | null): void {
    this.readyDocumentProvider = provider
  }

  hasAdapter(): boolean {
    return this.adapter !== null
  }

  isAvailable(): boolean {
    return this.adapter !== null && this.adapter.isAvailable() &&
      this.readyDocumentProvider !== null
  }

  async search(request: KnowledgeSearchRequest): Promise<KnowledgeSearchResponse> {
    if (typeof request.query !== 'string') {
      return buildErrorResponse('', this.clampTopK(request.topK), 'invalid_query', '检索词必须是字符串')
    }
    const trimmedQuery = request.query.trim()
    if (trimmedQuery === '') {
      return buildErrorResponse('', this.clampTopK(request.topK), 'invalid_query', '检索词不能为空')
    }

    const topK = this.clampTopK(request.topK)
    const query = this.clampUtf8(trimmedQuery, MAX_QUERY_BYTES)
    const queryTruncated = query !== trimmedQuery
    if (query === '') {
      return buildErrorResponse('', topK, 'invalid_query', '检索词不能为空')
    }

    if (!Array.isArray(request.documentIds)) {
      return buildErrorResponse(query, topK, 'invalid_document_ids', 'documentIds 必须是字符串数组')
    }
    const documentFilterRequested = request.documentIds.length > 0
    const documentIds = this.normalizeDocumentIds(request.documentIds)
    if (documentFilterRequested && documentIds.length === 0) {
      return buildErrorResponse(
        query,
        topK,
        'invalid_document_ids',
        'documentIds 未包含有效文档 ID'
      )
    }

    const readyDocumentProvider = this.readyDocumentProvider
    if (readyDocumentProvider === null) {
      return buildUnavailableResponse(
        query,
        topK,
        'ready_document_policy_unavailable',
        '知识库文档状态校验不可用'
      )
    }
    let effectiveDocumentIds: string[]
    try {
      effectiveDocumentIds = await this.resolveReadyDocumentScope(
        readyDocumentProvider,
        documentIds
      )
    } catch (error) {
      console.error('KnowledgeRetrievalService', 'Failed to resolve ready knowledge documents')
      return buildErrorResponse(
        query,
        topK,
        'ready_document_policy_failed',
        '知识库文档状态校验失败'
      )
    }
    if (effectiveDocumentIds.length === 0) {
      const noHits = buildNoHitsResponse(query, topK)
      noHits.queryTruncated = queryTruncated
      return noHits
    }

    // 全库查询不向 DAK 下推“全部 READY 文档 ID”的 OP_IN。READY 集合可能很长，
    // 且 FTS 的 UNINDEXED 列过滤在不同设备实现上会把正常召回压成 no_hits。
    // 未显式限定文件时先做全库召回，随后仍以 effectiveDocumentIds 做 fail-closed 过滤。
    const adapterDocumentIds = documentFilterRequested ? effectiveDocumentIds : []
    const normalizedRequest = new KnowledgeSearchRequest(query, topK, adapterDocumentIds)
    const adapter = this.adapter
    if (adapter === null) {
      const unavailable = buildUnavailableResponse(
        query,
        topK,
        'retrieval_adapter_unavailable',
        '知识库检索适配器不可用'
      )
      unavailable.queryTruncated = queryTruncated
      return unavailable
    }

    try {
      const response = await adapter.search(normalizedRequest)
      const stillReadyDocumentIds = await this.resolveReadyDocumentScope(
        readyDocumentProvider,
        effectiveDocumentIds
      )
      if (stillReadyDocumentIds.length === 0) {
        const noHits = buildNoHitsResponse(query, topK)
        noHits.queryTruncated = queryTruncated
        return noHits
      }
      const finalRequest = new KnowledgeSearchRequest(query, topK, stillReadyDocumentIds)
      return this.normalizeResponse(response, finalRequest, queryTruncated)
    } catch (error) {
      console.error('KnowledgeRetrievalService', 'Knowledge retrieval adapter failed')
      const failed = buildErrorResponse(query, topK, 'retrieval_adapter_failed', '知识库检索失败')
      failed.queryTruncated = queryTruncated
      return failed
    }
  }

  private clampTopK(value: number): number {
    if (!Number.isFinite(value)) {
      return DEFAULT_TOP_K
    }
    const integerValue = Math.floor(value)
    if (integerValue < MIN_TOP_K) {
      return MIN_TOP_K
    }
    if (integerValue > MAX_TOP_K) {
      return MAX_TOP_K
    }
    return integerValue
  }

  private utf8Length(value: string): number {
    return new util.TextEncoder().encodeInto(value).byteLength
  }

  private clampUtf8(value: string, maxBytes: number): string {
    if (this.utf8Length(value) <= maxBytes) {
      return value
    }
    let low = 0
    let high = value.length
    while (low < high) {
      const middle = Math.ceil((low + high) / 2)
      const candidate = this.safeSubstring(value, middle)
      if (this.utf8Length(candidate) <= maxBytes) {
        low = middle
      } else {
        high = middle - 1
      }
    }
    return this.safeSubstring(value, low).trim()
  }

  private safeSubstring(value: string, requestedLength: number): string {
    let length = Math.min(Math.max(requestedLength, 0), value.length)
    if (length > 0 && length < value.length) {
      const lastCodeUnit = value.charCodeAt(length - 1)
      if (lastCodeUnit >= 0xD800 && lastCodeUnit <= 0xDBFF) {
        length--
      }
    }
    return value.substring(0, length)
  }

  private normalizeDocumentIds(documentIds: string[]): string[] {
    const normalized: string[] = []
    for (let index = 0; index < documentIds.length && normalized.length < MAX_DOCUMENT_IDS; index++) {
      const rawDocumentId = documentIds[index]
      if (typeof rawDocumentId !== 'string') {
        continue
      }
      const documentId = rawDocumentId.trim()
      if (!isValidKnowledgeDocumentId(documentId)) {
        continue
      }
      if (normalized.indexOf(documentId) < 0) {
        normalized.push(documentId)
      }
    }
    return normalized
  }

  private async resolveReadyDocumentScope(
    provider: KnowledgeReadyDocumentProvider,
    requestedDocumentIds: string[]
  ): Promise<string[]> {
    const rawReadyDocumentIds = await provider.listReadyDocumentIds()
    if (!Array.isArray(rawReadyDocumentIds)) {
      throw new Error('Ready document provider returned a non-array value')
    }
    const readyDocumentIds = this.normalizeReadyDocumentIds(rawReadyDocumentIds)
    if (requestedDocumentIds.length === 0) {
      return readyDocumentIds
    }
    const intersection: string[] = []
    for (let index = 0; index < requestedDocumentIds.length; index++) {
      const documentId = requestedDocumentIds[index]
      if (readyDocumentIds.indexOf(documentId) >= 0 && intersection.indexOf(documentId) < 0) {
        intersection.push(documentId)
      }
    }
    return intersection
  }

  private normalizeReadyDocumentIds(documentIds: string[]): string[] {
    const normalized: string[] = []
    for (let index = 0; index < documentIds.length; index++) {
      const rawDocumentId = documentIds[index]
      if (typeof rawDocumentId !== 'string') {
        continue
      }
      const documentId = rawDocumentId.trim()
      if (isValidKnowledgeDocumentId(documentId) && normalized.indexOf(documentId) < 0) {
        normalized.push(documentId)
      }
    }
    return normalized
  }

  private normalizeResponse(
    response: KnowledgeSearchResponse,
    request: KnowledgeSearchRequest,
    queryTruncated: boolean
  ): KnowledgeSearchResponse {
    if (response.status === KnowledgeSearchStatus.UNAVAILABLE) {
      const unavailable = buildUnavailableResponse(
        request.query,
        request.topK,
        response.code === '' ? 'retrieval_unavailable' : response.code,
        response.message === '' ? '知识库检索不可用' : response.message
      )
      unavailable.queryTruncated = queryTruncated
      return unavailable
    }
    if (response.status === KnowledgeSearchStatus.ERROR) {
      const failed = buildErrorResponse(
        request.query,
        request.topK,
        response.code === '' ? 'retrieval_failed' : response.code,
        response.message === '' ? '知识库检索失败' : response.message
      )
      failed.queryTruncated = queryTruncated
      return failed
    }

    const budgeted = this.applyResultBudget(response.hits, request)
    budgeted.queryTruncated = queryTruncated
    return budgeted
  }

  private applyResultBudget(
    sourceHits: KnowledgeSearchHit[],
    request: KnowledgeSearchRequest
  ): KnowledgeSearchResponse {
    const response = new KnowledgeSearchResponse(KnowledgeSearchStatus.OK, request.query, request.topK)
    let usedCharacters = 0

    for (let index = 0; index < sourceHits.length && response.hits.length < request.topK; index++) {
      const source = sourceHits[index]
      const documentId = this.safeSubstring(source.documentId.trim(), MAX_DOCUMENT_ID_CHARACTERS)
      if (!this.matchesDocumentFilter(documentId, request.documentIds)) {
        continue
      }

      const chunkId = this.safeSubstring(source.chunkId.trim(), MAX_DOCUMENT_ID_CHARACTERS)
      const title = this.safeSubstring(source.title.trim(), MAX_TITLE_CHARACTERS)
      const locator = this.safeSubstring(source.locator.trim(), MAX_LOCATOR_CHARACTERS)
      const content = source.content.trim()
      if (content === '') {
        continue
      }

      const metadataCharacters = documentId.length + chunkId.length + title.length + locator.length
      const remainingCharacters = MAX_TOTAL_RESULT_CHARACTERS - usedCharacters - metadataCharacters
      if (remainingCharacters <= 0) {
        response.truncated = true
        break
      }

      const budgetedContent = this.safeSubstring(content, remainingCharacters)
      if (budgetedContent === '') {
        response.truncated = true
        break
      }
      if (budgetedContent.length < content.length) {
        response.truncated = true
      }

      const score = Number.isFinite(source.score) && source.score >= 0 ? source.score : 0
      response.hits.push(new KnowledgeSearchHit(
        documentId,
        chunkId,
        title,
        locator,
        score,
        budgetedContent
      ))
      usedCharacters += metadataCharacters + budgetedContent.length
      if (response.truncated) {
        break
      }
    }

    if (response.hits.length === 0) {
      const noHits = buildNoHitsResponse(request.query, request.topK)
      noHits.truncated = response.truncated
      return noHits
    }
    if (response.hits.length < sourceHits.length) {
      response.truncated = true
    }
    return response
  }

  private matchesDocumentFilter(documentId: string, documentIds: string[]): boolean {
    if (documentIds.length === 0) {
      return true
    }
    return documentIds.indexOf(documentId) >= 0
  }
}

export function getKnowledgeRetrievalService(): KnowledgeRetrievalService {
  return KnowledgeRetrievalService.getInstance()
}
