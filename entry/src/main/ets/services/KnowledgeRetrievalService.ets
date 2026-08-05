import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { util } from '@kit.ArkTS'
import { retrieval } from '@kit.DataAugmentationKit'
import {
  getKnowledgeEmbeddingService,
  KnowledgeEmbeddingProvider
} from './KnowledgeEmbeddingService'
import { projectKnowledgeVector } from './KnowledgeVectorProjection'
import {
  getKnowledgeVectorStore,
  KnowledgeVectorSearchRecord
} from './KnowledgeVectorStore'
import {
  getKnowledgeRerankService,
  KNOWLEDGE_RERANK_MAX_DOCUMENTS,
  KnowledgeRerankProvider,
  KnowledgeRerankScore
} from './KnowledgeRerankService'

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
const HYBRID_RRF_RANK_CONSTANT: number = 60
const HYBRID_KEYWORD_WEIGHT: number = 1.05
const HYBRID_VECTOR_WEIGHT: number = 1.0
const MAX_RETRIEVER_ATTEMPTS: number = 2
// 启用重排序时向底层适配器多要几倍候选：RRF 只看排名位置，重排序模型需要
// 一个足够宽的候选窗口才有价值，最终仍按用户/模型请求的 topK 截断。
const RERANK_CANDIDATE_MULTIPLIER: number = 4
const RERANK_MIN_CANDIDATES: number = 10

// Data Augmentation Kit 在未设置时默认 1，只会保留近乎完全相同的向量。
// 0.4 与 SDK 默认向量重排分层 [0.6, 0.45, 0.4] 的最低相关档一致。
export const KNOWLEDGE_VECTOR_SIMILARITY_THRESHOLD: number = 0.4

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

export enum KnowledgeRetrievalMode {
  KEYWORD = 'keyword',
  HYBRID = 'hybrid'
}

export enum KnowledgeRetrievalFallbackReason {
  NONE = '',
  INVERTED_NOT_CONFIGURED = 'inverted_not_configured',
  VECTOR_NOT_CONFIGURED = 'vector_not_configured',
  VECTOR_SCOPE_UNAVAILABLE = 'vector_scope_unavailable',
  EMBEDDING_UNAVAILABLE = 'embedding_unavailable',
  NO_VECTOR_READY_DOCUMENTS = 'no_vector_ready_documents',
  VECTOR_SCOPE_FAILED = 'vector_scope_failed',
  EMBEDDING_MODEL_CHANGED = 'embedding_model_changed',
  QUERY_EMBEDDING_FAILED = 'query_embedding_failed',
  QUERY_VECTOR_INVALID = 'query_vector_invalid',
  VECTOR_DIMENSION_MISMATCH = 'vector_dimension_mismatch',
  HYBRID_SNAPSHOT_CHANGED = 'hybrid_snapshot_changed',
  HYBRID_RETRIEVAL_FAILED = 'hybrid_retrieval_failed'
}

/** 重排序未生效的原因。命中仍按 RRF 融合顺序返回，检索本身不会因此失败。 */
export enum KnowledgeRerankFallbackReason {
  NONE = '',
  NOT_CONFIGURED = 'rerank_not_configured',
  NOT_ENOUGH_CANDIDATES = 'rerank_not_enough_candidates',
  REQUEST_FAILED = 'rerank_request_failed',
  INVALID_RESULT = 'rerank_invalid_result'
}

export interface KnowledgeRetrievalPlanInput {
  invertedConfigured: boolean
  vectorConfigured: boolean
  vectorScopeAvailable: boolean
  embeddingAvailable: boolean
  vectorReadyDocumentCount: number
  embeddingModelStable: boolean
}

export class KnowledgeRetrievalPlan {
  mode: string = KnowledgeRetrievalMode.KEYWORD
  reason: string = KnowledgeRetrievalFallbackReason.NONE
  shouldEmbedQuery: boolean = false

  constructor(mode: string, reason: string, shouldEmbedQuery: boolean) {
    this.mode = mode
    this.reason = reason
    this.shouldEmbedQuery = shouldEmbedQuery
  }
}

export function resolveKnowledgeRetrievalPlan(
  input: KnowledgeRetrievalPlanInput
): KnowledgeRetrievalPlan {
  if (!input.invertedConfigured) {
    return new KnowledgeRetrievalPlan(
      KnowledgeRetrievalMode.KEYWORD,
      KnowledgeRetrievalFallbackReason.INVERTED_NOT_CONFIGURED,
      false
    )
  }
  if (!input.vectorConfigured) {
    return new KnowledgeRetrievalPlan(
      KnowledgeRetrievalMode.KEYWORD,
      KnowledgeRetrievalFallbackReason.VECTOR_NOT_CONFIGURED,
      false
    )
  }
  if (!input.vectorScopeAvailable) {
    return new KnowledgeRetrievalPlan(
      KnowledgeRetrievalMode.KEYWORD,
      KnowledgeRetrievalFallbackReason.VECTOR_SCOPE_UNAVAILABLE,
      false
    )
  }
  if (!input.embeddingAvailable) {
    return new KnowledgeRetrievalPlan(
      KnowledgeRetrievalMode.KEYWORD,
      KnowledgeRetrievalFallbackReason.EMBEDDING_UNAVAILABLE,
      false
    )
  }
  if (input.vectorReadyDocumentCount === 0) {
    return new KnowledgeRetrievalPlan(
      KnowledgeRetrievalMode.KEYWORD,
      KnowledgeRetrievalFallbackReason.NO_VECTOR_READY_DOCUMENTS,
      false
    )
  }
  if (!input.embeddingModelStable) {
    return new KnowledgeRetrievalPlan(
      KnowledgeRetrievalMode.KEYWORD,
      KnowledgeRetrievalFallbackReason.EMBEDDING_MODEL_CHANGED,
      false
    )
  }
  return new KnowledgeRetrievalPlan(
    KnowledgeRetrievalMode.HYBRID,
    KnowledgeRetrievalFallbackReason.NONE,
    true
  )
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
  retrievalMode: string = KnowledgeRetrievalMode.KEYWORD
  fallbackReason: string = KnowledgeRetrievalFallbackReason.NONE
  // rerankApplied=true 时 hits[].score 是重排序模型给出的相关性分数；
  // 否则是 RRF 融合分（或关键词通道原始分），两者不可比较。
  rerankApplied: boolean = false
  rerankFallbackReason: string = KnowledgeRerankFallbackReason.NONE

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

/**
 * Expands already-retrieved, still-READY hits with adjacent or parent context.
 *
 * Implementations must remain pure retrieval helpers: this hook is reached only
 * from an actual knowledge_search execution and must not call or modify a model
 * prompt.
 */
export interface KnowledgeHitContextProvider {
  expandHitContexts(hits: KnowledgeSearchHit[]): Promise<KnowledgeSearchHit[]>
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

/** Provider 的自由文本异常可能回显私有查询，只允许记录稳定、短小的错误码。 */
function buildSafeRetrievalFallbackCode(error: Object): string {
  const businessError = error as RetrievalBusinessError
  if (businessError.code === undefined) {
    return ''
  }
  const code = `${businessError.code}`.trim()
  if (code === '' || code.length > 64 || !/^[A-Za-z0-9_.:-]+$/.test(code)) {
    return ''
  }
  return `code=${code}`
}

class KnowledgeRetrieverLease {
  retriever: retrieval.Retriever
  snapshotGeneration: number
  createdForAttempt: boolean

  constructor(
    retriever: retrieval.Retriever,
    snapshotGeneration: number,
    createdForAttempt: boolean
  ) {
    this.retriever = retriever
    this.snapshotGeneration = snapshotGeneration
    this.createdForAttempt = createdForAttempt
  }
}

/**
 * Restricts an internal DAK retry to the first attempt and to evidence that the
 * Retriever itself may be stale or cold. A normal empty result from an already
 * cached Retriever is authoritative and must not become an unconditional
 * duplicate query.
 */
export function shouldRetryKnowledgeRetrieverAttempt(
  attemptIndex: number,
  retrieverCreated: boolean,
  snapshotChanged: boolean,
  retrieveFailed: boolean,
  noHits: boolean
): boolean {
  if (attemptIndex !== 0) {
    return false
  }
  if (retrieveFailed || snapshotChanged) {
    return true
  }
  return retrieverCreated && noHits
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

class KnowledgeFusionCandidate {
  hit: KnowledgeSearchHit
  fusedScore: number = 0
  keywordRank: number = 0
  vectorRank: number = 0

  constructor(hit: KnowledgeSearchHit) {
    this.hit = hit
  }
}

function findKnowledgeFusionCandidate(
  candidates: KnowledgeFusionCandidate[],
  hit: KnowledgeSearchHit
): KnowledgeFusionCandidate | null {
  for (let index = 0; index < candidates.length; index++) {
    const candidate = candidates[index]
    if (candidate.hit.chunkId === hit.chunkId && candidate.hit.documentId === hit.documentId) {
      return candidate
    }
  }
  return null
}

function addKnowledgeFusionChannel(
  candidates: KnowledgeFusionCandidate[],
  hits: KnowledgeSearchHit[],
  weight: number,
  keywordChannel: boolean
): void {
  for (let index = 0; index < hits.length; index++) {
    const hit = hits[index]
    let candidate = findKnowledgeFusionCandidate(candidates, hit)
    if (candidate === null) {
      candidate = new KnowledgeFusionCandidate(hit)
      candidates.push(candidate)
    }
    if (keywordChannel) {
      if (candidate.keywordRank > 0) {
        continue
      }
      candidate.keywordRank = index + 1
    } else {
      if (candidate.vectorRank > 0) {
        continue
      }
      candidate.vectorRank = index + 1
    }
    candidate.fusedScore += weight / (HYBRID_RRF_RANK_CONSTANT + index + 1)
  }
}

/**
 * DAK 的默认多通道重排可能淘汰“仅向量命中”的记录。这里对两路独立召回做
 * union-RRF：任一路的候选都会保留，同时被关键词和向量命中的候选自然获得加分。
 */
export function fuseKnowledgeSearchHits(
  keywordHits: KnowledgeSearchHit[],
  vectorHits: KnowledgeSearchHit[],
  topK: number
): KnowledgeSearchHit[] {
  const candidates: KnowledgeFusionCandidate[] = []
  addKnowledgeFusionChannel(candidates, keywordHits, HYBRID_KEYWORD_WEIGHT, true)
  addKnowledgeFusionChannel(candidates, vectorHits, HYBRID_VECTOR_WEIGHT, false)
  candidates.sort((left: KnowledgeFusionCandidate, right: KnowledgeFusionCandidate): number => {
    if (left.fusedScore !== right.fusedScore) {
      return right.fusedScore - left.fusedScore
    }
    const leftChannels = (left.keywordRank > 0 ? 1 : 0) + (left.vectorRank > 0 ? 1 : 0)
    const rightChannels = (right.keywordRank > 0 ? 1 : 0) + (right.vectorRank > 0 ? 1 : 0)
    if (leftChannels !== rightChannels) {
      return rightChannels - leftChannels
    }
    if ((left.keywordRank > 0) !== (right.keywordRank > 0)) {
      return left.keywordRank > 0 ? -1 : 1
    }
    const leftBestRank = left.keywordRank === 0
      ? left.vectorRank
      : (left.vectorRank === 0 ? left.keywordRank : Math.min(left.keywordRank, left.vectorRank))
    const rightBestRank = right.keywordRank === 0
      ? right.vectorRank
      : (right.vectorRank === 0 ? right.keywordRank : Math.min(right.keywordRank, right.vectorRank))
    if (leftBestRank !== rightBestRank) {
      return leftBestRank - rightBestRank
    }
    if (left.hit.chunkId === right.hit.chunkId) {
      return 0
    }
    return left.hit.chunkId < right.hit.chunkId ? -1 : 1
  })

  const limit = Math.max(0, Math.min(Math.floor(topK), candidates.length))
  const fused: KnowledgeSearchHit[] = []
  for (let index = 0; index < limit; index++) {
    const candidate = candidates[index]
    fused.push(new KnowledgeSearchHit(
      candidate.hit.documentId,
      candidate.hit.chunkId,
      candidate.hit.title,
      candidate.hit.locator,
      candidate.fusedScore,
      candidate.hit.content
    ))
  }
  return fused
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

    const recallCondition = this.buildRecallCondition(configuration, request)
    const recallConditions: retrieval.RecallCondition[] = [recallCondition]
    const condition: retrieval.RetrievalCondition = {
      recallConditions: recallConditions,
      resultCount: request.topK
    }
    for (let attemptIndex = 0; attemptIndex < MAX_RETRIEVER_ATTEMPTS; attemptIndex++) {
      let lease: KnowledgeRetrieverLease | null = null
      try {
        lease = await this.getOrCreateRetriever(configuration)
        const records = await lease.retriever.retrieveRdb(request.query, condition)
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

        const snapshotChanged = lease.snapshotGeneration !== this.dataSnapshotGeneration
        const noHits = hits.length === 0
        if (shouldRetryKnowledgeRetrieverAttempt(
          attemptIndex,
          lease.createdForAttempt,
          snapshotChanged,
          false,
          noHits
        )) {
          this.discardRetriever(lease)
          continue
        }
        if (snapshotChanged) {
          return buildErrorResponse(
            request.query,
            request.topK,
            'retrieval_snapshot_changed',
            '知识库索引正在更新，请稍后重试'
          )
        }
        if (noHits) {
          return buildNoHitsResponse(request.query, request.topK)
        }
        const response = new KnowledgeSearchResponse(
          KnowledgeSearchStatus.OK,
          request.query,
          request.topK
        )
        response.hits = hits
        return response
      } catch (error) {
        const businessError = error as RetrievalBusinessError
        if (lease !== null) {
          this.discardRetriever(lease)
        }
        if (shouldRetryKnowledgeRetrieverAttempt(
          attemptIndex,
          lease !== null && lease.createdForAttempt,
          lease !== null && lease.snapshotGeneration !== this.dataSnapshotGeneration,
          true,
          false
        )) {
          continue
        }
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
    return buildErrorResponse(request.query, request.topK, 'retrieval_failed', '知识库检索失败')
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
  ): Promise<KnowledgeRetrieverLease> {
    if (this.retriever !== null) {
      return new KnowledgeRetrieverLease(
        this.retriever,
        this.dataSnapshotGeneration,
        false
      )
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
      if (this.retriever === null) {
        this.retriever = retriever
      } else {
        return new KnowledgeRetrieverLease(
          this.retriever,
          snapshotGeneration,
          false
        )
      }
    }
    return new KnowledgeRetrieverLease(retriever, snapshotGeneration, true)
  }

  private discardRetriever(lease: KnowledgeRetrieverLease): void {
    if (lease.snapshotGeneration === this.dataSnapshotGeneration &&
      this.retriever === lease.retriever) {
      this.retriever = null
    }
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
    const embeddingAvailable = this.embeddingProvider.isAvailable()
    const preflightPlan = resolveKnowledgeRetrievalPlan({
      invertedConfigured: invertedConfiguration !== null,
      vectorConfigured: vectorConfiguration !== null,
      vectorScopeAvailable: vectorReadyDocumentProvider !== null,
      embeddingAvailable: embeddingAvailable,
      vectorReadyDocumentCount: -1,
      embeddingModelStable: true
    })
    if (invertedConfiguration === null || vectorConfiguration === null ||
      vectorReadyDocumentProvider === null || !embeddingAvailable) {
      return await this.searchKeywordFallback(request, preflightPlan.reason)
    }

    try {
      const embeddingModelKey = this.embeddingProvider.modelKey()
      let vectorDocumentIds: string[]
      try {
        vectorDocumentIds = await vectorReadyDocumentProvider
          .listVectorReadyDocumentIds(request.documentIds)
      } catch (_error) {
        return await this.searchKeywordFallback(
          request,
          KnowledgeRetrievalFallbackReason.VECTOR_SCOPE_FAILED
        )
      }
      const scopedPlan = resolveKnowledgeRetrievalPlan({
        invertedConfigured: true,
        vectorConfigured: true,
        vectorScopeAvailable: true,
        embeddingAvailable: true,
        vectorReadyDocumentCount: vectorDocumentIds.length,
        embeddingModelStable: embeddingModelKey === this.embeddingProvider.modelKey()
      })
      if (!scopedPlan.shouldEmbedQuery) {
        return await this.searchKeywordFallback(request, scopedPlan.reason)
      }
      const queryForEmbedding = this.clampEmbeddingInput(
        request.query,
        this.embeddingProvider.maxInputCharacters()
      )
      let rawQueryVector: Float32Array
      try {
        rawQueryVector = await this.embeddingProvider.embedQuery(queryForEmbedding)
      } catch (error) {
        return await this.searchKeywordFallback(
          request,
          KnowledgeRetrievalFallbackReason.QUERY_EMBEDDING_FAILED
        )
      }
      let queryVector: Float32Array
      try {
        queryVector = projectKnowledgeVector(rawQueryVector)
      } catch (_error) {
        return await this.searchKeywordFallback(
          request,
          KnowledgeRetrievalFallbackReason.QUERY_VECTOR_INVALID
        )
      }
      if (embeddingModelKey !== this.embeddingProvider.modelKey()) {
        return await this.searchKeywordFallback(
          request,
          KnowledgeRetrievalFallbackReason.EMBEDDING_MODEL_CHANGED
        )
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
        return await this.searchKeywordFallback(
          request,
          KnowledgeRetrievalFallbackReason.VECTOR_DIMENSION_MISMATCH
        )
      }

      const deepSize = Math.max(
        HYBRID_MIN_DEEP_SIZE,
        request.topK * HYBRID_DEEP_SIZE_MULTIPLIER
      )
      if (embeddingModelKey !== this.embeddingProvider.modelKey()) {
        return await this.searchKeywordFallback(
          request,
          KnowledgeRetrievalFallbackReason.EMBEDDING_MODEL_CHANGED
        )
      }

      // BM25 仍由 DAK 负责；向量近邻直接由 ArkData sidecar 查询。DAK 的最终
      // 相关性筛选会淘汰 BM25=0 的向量候选，因此不能再让它决定向量通道结果。
      const keywordResponse = await this.invertedAdapter.search(
        new KnowledgeSearchRequest(request.query, deepSize, request.documentIds)
      )
      let vectorRecords: KnowledgeVectorSearchRecord[]
      try {
        vectorRecords = await getKnowledgeVectorStore().searchNearest(
          queryVector,
          vectorDocumentIds,
          deepSize,
          KNOWLEDGE_VECTOR_SIMILARITY_THRESHOLD
        )
      } catch (error) {
        return this.reuseKeywordResponse(
          keywordResponse,
          request,
          KnowledgeRetrievalFallbackReason.HYBRID_RETRIEVAL_FAILED,
          this.safeFallbackCode(error)
        )
      }
      if (embeddingModelKey !== this.embeddingProvider.modelKey()) {
        return this.reuseKeywordResponse(
          keywordResponse,
          request,
          KnowledgeRetrievalFallbackReason.EMBEDDING_MODEL_CHANGED
        )
      }
      return this.fuseDirectSearchChannels(
        keywordResponse,
        vectorRecords,
        request,
        deepSize
      )
    } catch (error) {
      return await this.searchKeywordFallback(
        request,
        KnowledgeRetrievalFallbackReason.HYBRID_RETRIEVAL_FAILED,
        this.safeFallbackCode(error)
      )
    }
  }

  private reuseKeywordResponse(
    source: KnowledgeSearchResponse,
    request: KnowledgeSearchRequest,
    reason: string,
    detail: string = ''
  ): KnowledgeSearchResponse {
    const safeReason = reason.trim() === ''
      ? KnowledgeRetrievalFallbackReason.HYBRID_RETRIEVAL_FAILED
      : reason
    console.warn(
      'KnowledgeRetrievalService',
      `Knowledge retrieval mode=keyword, reason=${safeReason}` +
      `${detail.trim() === '' ? '' : `, diagnostic=${detail.substring(0, 80)}`}`
    )
    const response = new KnowledgeSearchResponse(
      source.status,
      request.query,
      request.topK,
      source.code,
      source.message
    )
    response.hits = source.hits.slice(0, Math.min(request.topK, source.hits.length))
    response.truncated = source.truncated || source.hits.length > request.topK
    response.queryTruncated = source.queryTruncated
    response.retrievalMode = KnowledgeRetrievalMode.KEYWORD
    response.fallbackReason = safeReason
    return response
  }

  private async searchKeywordFallback(
    request: KnowledgeSearchRequest,
    reason: string,
    detail: string = ''
  ): Promise<KnowledgeSearchResponse> {
    const safeReason = reason.trim() === ''
      ? KnowledgeRetrievalFallbackReason.HYBRID_RETRIEVAL_FAILED
      : reason
    console.warn(
      'KnowledgeRetrievalService',
      `Knowledge retrieval mode=keyword, reason=${safeReason}` +
      `${detail.trim() === '' ? '' : `, diagnostic=${detail.substring(0, 80)}`}`
    )
    try {
      const response = await this.invertedAdapter.search(request)
      response.retrievalMode = KnowledgeRetrievalMode.KEYWORD
      response.fallbackReason = safeReason
      return response
    } catch (_error) {
      console.error(
        'KnowledgeRetrievalService',
        `Keyword fallback failed: originalReason=${safeReason}`
      )
      const failed = buildErrorResponse(
        request.query,
        request.topK,
        'keyword_fallback_failed',
        '关键词检索失败'
      )
      failed.retrievalMode = KnowledgeRetrievalMode.KEYWORD
      failed.fallbackReason = safeReason
      return failed
    }
  }

  private safeFallbackCode(error: Object): string {
    return buildSafeRetrievalFallbackCode(error)
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
  ): Promise<KnowledgeRetrieverLease> {
    if (this.retriever !== null) {
      return new KnowledgeRetrieverLease(
        this.retriever,
        this.dataSnapshotGeneration,
        false
      )
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
      if (this.retriever === null) {
        this.retriever = retriever
      } else {
        return new KnowledgeRetrieverLease(
          this.retriever,
          snapshotGeneration,
          false
        )
      }
    }
    return new KnowledgeRetrieverLease(retriever, snapshotGeneration, true)
  }

  private discardRetriever(lease: KnowledgeRetrieverLease): void {
    if (lease.snapshotGeneration === this.dataSnapshotGeneration &&
      this.retriever === lease.retriever) {
      this.retriever = null
    }
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
      value: queryVector,
      similarityThreshold: KNOWLEDGE_VECTOR_SIMILARITY_THRESHOLD
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

  private fuseDirectSearchChannels(
    keywordResponse: KnowledgeSearchResponse,
    vectorRecords: KnowledgeVectorSearchRecord[],
    request: KnowledgeSearchRequest,
    channelLimit: number
  ): KnowledgeSearchResponse {
    const keywordHits = keywordResponse.status === KnowledgeSearchStatus.OK
      ? keywordResponse.hits.slice(0, Math.min(channelLimit, keywordResponse.hits.length))
      : []
    const vectorHits = this.mapDirectVectorHits(vectorRecords, request, channelLimit)
    const hits = fuseKnowledgeSearchHits(keywordHits, vectorHits, request.topK)
    console.info(
      'KnowledgeRetrievalService',
      `Direct hybrid recall: keyword=${keywordHits.length}, vector=${vectorHits.length}, ` +
      `fused=${hits.length}, bestVectorSimilarity=${this.bestVectorSimilarity(vectorRecords)}`
    )
    if (hits.length === 0) {
      if (keywordResponse.status === KnowledgeSearchStatus.ERROR ||
        keywordResponse.status === KnowledgeSearchStatus.UNAVAILABLE) {
        const failed = buildErrorResponse(
          request.query,
          request.topK,
          'hybrid_channels_unavailable',
          '知识库检索失败'
        )
        failed.retrievalMode = KnowledgeRetrievalMode.HYBRID
        return failed
      }
      const noHits = buildNoHitsResponse(request.query, request.topK)
      noHits.retrievalMode = KnowledgeRetrievalMode.HYBRID
      return noHits
    }
    const response = new KnowledgeSearchResponse(
      KnowledgeSearchStatus.OK,
      request.query,
      request.topK
    )
    response.hits = hits
    response.retrievalMode = KnowledgeRetrievalMode.HYBRID
    return response
  }

  private mapDirectVectorHits(
    records: KnowledgeVectorSearchRecord[],
    request: KnowledgeSearchRequest,
    limit: number
  ): KnowledgeSearchHit[] {
    const hits: KnowledgeSearchHit[] = []
    for (let index = 0; index < records.length; index++) {
      const record = records[index]
      if (request.documentIds.length > 0 &&
        request.documentIds.indexOf(record.documentId) < 0) {
        continue
      }
      hits.push(new KnowledgeSearchHit(
        record.documentId,
        record.chunkId,
        record.title,
        record.locator,
        record.similarity,
        record.content
      ))
      if (hits.length >= limit) {
        break
      }
    }
    return hits
  }

  private bestVectorSimilarity(records: KnowledgeVectorSearchRecord[]): string {
    if (records.length === 0 || !Number.isFinite(records[0].similarity)) {
      return 'none'
    }
    return records[0].similarity.toFixed(4)
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
  private hitContextProvider: KnowledgeHitContextProvider | null = null

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

  setHitContextProvider(provider: KnowledgeHitContextProvider | null): void {
    this.hitContextProvider = provider
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
    // 启用重排序时向下游多要候选，重排序后再由 normalizeResponse 截回 topK。
    // 关键词回退路径同样受益，因此这里统一处理，而不是只挂在混合检索里。
    const rerankProvider = await this.resolveRerankProvider()
    const adapterTopK = rerankProvider !== null ? this.resolveRerankCandidateTopK(topK) : topK
    const normalizedRequest = new KnowledgeSearchRequest(query, adapterTopK, adapterDocumentIds)
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
        noHits.retrievalMode = response.retrievalMode
        noHits.fallbackReason = response.fallbackReason
        return noHits
      }
      const finalRequest = new KnowledgeSearchRequest(query, topK, stillReadyDocumentIds)
      // 先重排序再扩展上下文：重排序只看召回到的原始片段，
      // 上下文扩展则只需要作用在最终留下的少数命中上。
      const rerankedResponse = await this.applyRerankBestEffort(
        response,
        rerankProvider,
        query,
        topK
      )
      const responseWithContext = await this.expandHitContextsBestEffort(
        rerankedResponse,
        finalRequest
      )
      return this.normalizeResponse(responseWithContext, finalRequest, queryTruncated)
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

  /**
   * 解析本次检索可用的重排序 Provider。未配置或不可用时返回 null，
   * 调用方据此退回原有的 RRF 顺序。
   *
   * 这里主动 initialize()：knowledge_search 可能在知识库页面从未展示过的情况下执行，
   * 不能依赖 UI 去加载已持久化的重排序选择。
   */
  private async resolveRerankProvider(): Promise<KnowledgeRerankProvider | null> {
    const service = getKnowledgeRerankService()
    try {
      await service.initialize()
    } catch (error) {
      console.warn(
        'KnowledgeRetrievalService',
        `Rerank service initialization failed: ${buildSafeRetrievalFallbackCode(error)}`
      )
      return null
    }
    return service.isAvailable() ? service : null
  }

  private resolveRerankCandidateTopK(topK: number): number {
    const desired = Math.max(topK * RERANK_CANDIDATE_MULTIPLIER, RERANK_MIN_CANDIDATES)
    return Math.min(desired, KNOWLEDGE_RERANK_MAX_DOCUMENTS)
  }

  /**
   * 用重排序模型对召回结果重新排序。任何失败都不改变检索成败：
   * 出错时保留 RRF 融合顺序，只在响应里记录 rerankFallbackReason。
   *
   * 不记录 query 原文、候选正文或返回分数。
   */
  private async applyRerankBestEffort(
    response: KnowledgeSearchResponse,
    provider: KnowledgeRerankProvider | null,
    query: string,
    topK: number
  ): Promise<KnowledgeSearchResponse> {
    if (provider === null) {
      const untouched = this.copyResponseWithHits(response, response.hits)
      untouched.rerankFallbackReason = KnowledgeRerankFallbackReason.NOT_CONFIGURED
      return untouched
    }
    if (response.status !== KnowledgeSearchStatus.OK) {
      return response
    }
    // 候选数不超过要返回的条数时重排序不会改变最终集合，省掉一次网络请求
    if (response.hits.length <= 1 || response.hits.length <= topK) {
      const untouched = this.copyResponseWithHits(response, response.hits)
      untouched.rerankFallbackReason = KnowledgeRerankFallbackReason.NOT_ENOUGH_CANDIDATES
      return untouched
    }

    const maxDocumentCharacters = provider.maxDocumentCharacters()
    const documents: string[] = []
    for (let index = 0; index < response.hits.length; index++) {
      documents.push(this.buildRerankDocument(response.hits[index], maxDocumentCharacters))
    }

    let scores: KnowledgeRerankScore[]
    try {
      scores = await provider.rerank(query, documents)
    } catch (error) {
      console.warn(
        'KnowledgeRetrievalService',
        `Rerank failed, keeping fusion order: ${buildSafeRetrievalFallbackCode(error)}`
      )
      const untouched = this.copyResponseWithHits(response, response.hits)
      untouched.rerankFallbackReason = KnowledgeRerankFallbackReason.REQUEST_FAILED
      return untouched
    }
    if (!Array.isArray(scores) || scores.length === 0) {
      const untouched = this.copyResponseWithHits(response, response.hits)
      untouched.rerankFallbackReason = KnowledgeRerankFallbackReason.INVALID_RESULT
      return untouched
    }

    const ordered = this.buildRerankedHits(response.hits, scores)
    console.info(
      'KnowledgeRetrievalService',
      `Rerank applied: candidates=${response.hits.length}, scored=${scores.length}, topK=${topK}`
    )
    const reranked = this.copyResponseWithHits(response, ordered)
    reranked.rerankApplied = true
    reranked.rerankFallbackReason = KnowledgeRerankFallbackReason.NONE
    return reranked
  }

  /**
   * 重排序模型只判断相关性，不需要完整正文；标题一并带上以便区分同名片段。
   */
  private buildRerankDocument(hit: KnowledgeSearchHit, maxCharacters: number): string {
    const title = hit.title.trim()
    const content = hit.content.trim()
    const combined = title === '' ? content : `${title}\n${content}`
    if (combined.length <= maxCharacters) {
      return combined === '' ? hit.chunkId : combined
    }
    return combined.substring(0, maxCharacters)
  }

  /**
   * 按重排序分数降序重排；模型没有打分的候选保持原有 RRF 相对顺序接在后面，
   * 保证重排序只调整顺序、永远不会丢结果。
   */
  private buildRerankedHits(
    sourceHits: KnowledgeSearchHit[],
    scores: KnowledgeRerankScore[]
  ): KnowledgeSearchHit[] {
    const sorted = scores.slice()
    sorted.sort((left: KnowledgeRerankScore, right: KnowledgeRerankScore): number => {
      if (left.score !== right.score) {
        return right.score - left.score
      }
      return left.index - right.index
    })

    const ordered: KnowledgeSearchHit[] = []
    const taken = new Array<boolean>(sourceHits.length)
    for (let index = 0; index < taken.length; index++) {
      taken[index] = false
    }
    for (let index = 0; index < sorted.length; index++) {
      const entry = sorted[index]
      if (entry.index < 0 || entry.index >= sourceHits.length || taken[entry.index]) {
        continue
      }
      taken[entry.index] = true
      const source = sourceHits[entry.index]
      ordered.push(new KnowledgeSearchHit(
        source.documentId,
        source.chunkId,
        source.title,
        source.locator,
        entry.score,
        source.content
      ))
    }
    for (let index = 0; index < sourceHits.length; index++) {
      if (!taken[index]) {
        ordered.push(sourceHits[index])
      }
    }
    return ordered
  }

  private async expandHitContextsBestEffort(
    response: KnowledgeSearchResponse,
    request: KnowledgeSearchRequest
  ): Promise<KnowledgeSearchResponse> {
    if (response.status !== KnowledgeSearchStatus.OK) {
      return response
    }

    // Filter before expansion so the provider never observes a hit whose
    // document failed the second READY check. Keep an independent copy for a
    // fail-safe fallback if the provider throws or returns an invalid result.
    const preciseHits = this.copyMatchingHits(response.hits, request.documentIds)
    const contextualized = this.copyResponseWithHits(response, preciseHits)
    const provider = this.hitContextProvider
    if (provider === null || preciseHits.length === 0) {
      return contextualized
    }

    try {
      const providerInput = this.copyHits(preciseHits)
      const expandedHits = await provider.expandHitContexts(providerInput)
      if (!Array.isArray(expandedHits)) {
        console.warn(
          'KnowledgeRetrievalService',
          'Knowledge hit context provider returned a non-array result'
        )
        return contextualized
      }
      const readyExpandedHits = this.copyMatchingHits(expandedHits, request.documentIds)
      if (readyExpandedHits.length === 0 && preciseHits.length > 0) {
        console.warn(
          'KnowledgeRetrievalService',
          'Knowledge hit context provider returned no usable contexts'
        )
        return contextualized
      }
      return this.copyResponseWithHits(response, readyExpandedHits)
    } catch (error) {
      console.warn(
        'KnowledgeRetrievalService',
        'Knowledge hit context expansion failed; using precise hits'
      )
      return contextualized
    }
  }

  private copyMatchingHits(
    sourceHits: KnowledgeSearchHit[],
    documentIds: string[]
  ): KnowledgeSearchHit[] {
    const hits: KnowledgeSearchHit[] = []
    for (let index = 0; index < sourceHits.length; index++) {
      const source = sourceHits[index]
      const documentId = source.documentId.trim()
      if (!this.matchesDocumentFilter(documentId, documentIds)) {
        continue
      }
      hits.push(this.copyHit(source))
    }
    return hits
  }

  private copyHits(sourceHits: KnowledgeSearchHit[]): KnowledgeSearchHit[] {
    const hits: KnowledgeSearchHit[] = []
    for (let index = 0; index < sourceHits.length; index++) {
      hits.push(this.copyHit(sourceHits[index]))
    }
    return hits
  }

  private copyHit(source: KnowledgeSearchHit): KnowledgeSearchHit {
    return new KnowledgeSearchHit(
      source.documentId,
      source.chunkId,
      source.title,
      source.locator,
      source.score,
      source.content
    )
  }

  private copyResponseWithHits(
    source: KnowledgeSearchResponse,
    hits: KnowledgeSearchHit[]
  ): KnowledgeSearchResponse {
    const response = new KnowledgeSearchResponse(
      source.status,
      source.query,
      source.topK,
      source.code,
      source.message
    )
    response.hits = hits
    response.truncated = source.truncated
    response.queryTruncated = source.queryTruncated
    response.retrievalMode = source.retrievalMode
    response.fallbackReason = source.fallbackReason
    response.rerankApplied = source.rerankApplied
    response.rerankFallbackReason = source.rerankFallbackReason
    return response
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
      unavailable.retrievalMode = response.retrievalMode
      unavailable.fallbackReason = response.fallbackReason
      unavailable.rerankApplied = response.rerankApplied
      unavailable.rerankFallbackReason = response.rerankFallbackReason
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
      failed.retrievalMode = response.retrievalMode
      failed.fallbackReason = response.fallbackReason
      failed.rerankApplied = response.rerankApplied
      failed.rerankFallbackReason = response.rerankFallbackReason
      return failed
    }

    const budgeted = this.applyResultBudget(response.hits, request)
    budgeted.queryTruncated = queryTruncated
    budgeted.retrievalMode = response.retrievalMode
    budgeted.fallbackReason = response.fallbackReason
    budgeted.rerankApplied = response.rerankApplied
    budgeted.rerankFallbackReason = response.rerankFallbackReason
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
