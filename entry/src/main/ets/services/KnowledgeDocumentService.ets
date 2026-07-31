import { Context } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { AttachmentType, MessageAttachment } from '../models/ChatModels'
import {
  DataAugmentationHybridAdapter,
  DataAugmentationInvertedIndexConfiguration,
  DataAugmentationVectorIndexConfiguration,
  getKnowledgeRetrievalService,
  KnowledgeHitContextProvider,
  KnowledgeReadyDocumentProvider,
  KnowledgeSearchHit,
  KnowledgeVectorHealthObserver,
  KnowledgeVectorReadyDocumentProvider
} from './KnowledgeRetrievalService'
import {
  getKnowledgeEmbeddingService,
  KnowledgeEmbeddingSelection
} from './KnowledgeEmbeddingService'
import {
  getKnowledgeVectorStore,
  KnowledgeVectorRecord,
  KnowledgeVectorStoreStatus
} from './KnowledgeVectorStore'
import {
  KnowledgeVectorBootstrapCompletion,
  KnowledgeVectorBootstrapGate,
  KnowledgeVectorBootstrapResult
} from './KnowledgeVectorBootstrapGate'
import {
  KNOWLEDGE_SEMANTIC_CHUNKER_VERSION,
  KnowledgeSemanticChunk,
  KnowledgeSemanticChunker,
  KnowledgeSemanticChunkRequest
} from './KnowledgeSemanticChunker'
import { projectKnowledgeVector } from './KnowledgeVectorProjection'
import { RegisteredDocumentAttachment } from './DocumentAttachmentRegistryService'
import { getPdfTextExtractionService } from './PdfTextExtractionService'
import { getImageTextRecognitionService } from './ImageTextRecognitionService'

export const KNOWLEDGE_DATABASE_NAME: string = 'chatcube_knowledge.db'
export const KNOWLEDGE_DOCUMENTS_TABLE: string = 'knowledge_documents'
export const KNOWLEDGE_CHUNKS_FTS_TABLE: string = 'knowledge_chunks_fts'
export const KNOWLEDGE_CHUNK_METADATA_TABLE: string = 'knowledge_chunk_metadata'
export const KNOWLEDGE_VECTOR_INDEX_STATE_TABLE: string = 'knowledge_vector_index_state'
export const KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE: string = 'knowledge_vector_delete_queue'

const KNOWLEDGE_FILES_DIRECTORY: string = 'knowledge/files'
const MAX_FILE_BYTES: number = 20 * 1024 * 1024
const MAX_DOCUMENT_TEXT_CHARACTERS: number = 2 * 1024 * 1024
const MIN_PDF_TEXT_CHARACTERS_BEFORE_OCR: number = 120
export const KNOWLEDGE_CHUNK_MAX_CHARACTERS: number = 480
const KNOWLEDGE_CHUNKER_VERSION: string = KNOWLEDGE_SEMANTIC_CHUNKER_VERSION
const EMBEDDING_BATCH_SIZE: number = 16
const FILE_IO_CHUNK_BYTES: number = 256 * 1024
const KNOWLEDGE_UI_YIELD_MS: number = 16
const KNOWLEDGE_CHUNK_YIELD_INTERVAL: number = 4

export enum KnowledgeDocumentStatus {
  INDEXING = 'indexing',
  READY = 'ready',
  FAILED = 'failed',
  DELETING = 'deleting'
}

enum KnowledgeVectorIndexStatus {
  INDEXING = 'indexing',
  READY = 'ready',
  FAILED = 'failed',
  UNSUPPORTED = 'unsupported',
  DELETE_PENDING = 'delete_pending'
}

class KnowledgeVectorIndexState {
  documentId: string = ''
  generation: string = ''
  status: string = KnowledgeVectorIndexStatus.FAILED
  chunkerVersion: string = ''
  modelKey: string = ''
  dimension: number = 0
  vectorCount: number = 0
  lastError: string = ''
  updatedAt: number = 0
}

export class KnowledgeDocument {
  id: string = ''
  title: string = ''
  originalName: string = ''
  filePath: string = ''
  mimeType: string = ''
  size: number = 0
  contentHash: string = ''
  status: string = KnowledgeDocumentStatus.INDEXING
  chunkCount: number = 0
  errorMessage: string = ''
  createdAt: number = 0
  updatedAt: number = 0

  constructor(
    id: string = '',
    title: string = '',
    originalName: string = '',
    filePath: string = '',
    mimeType: string = '',
    size: number = 0
  ) {
    this.id = id
    this.title = title
    this.originalName = originalName
    this.filePath = filePath
    this.mimeType = mimeType
    this.size = size
  }
}

export class KnowledgeImportResult {
  ok: boolean = false
  duplicate: boolean = false
  message: string = ''
  document: KnowledgeDocument | null = null
  vectorReady: boolean = false
  vectorMessage: string = ''

  constructor(
    ok: boolean = false,
    message: string = '',
    document: KnowledgeDocument | null = null,
    duplicate: boolean = false,
    vectorReady: boolean = false,
    vectorMessage: string = ''
  ) {
    this.ok = ok
    this.message = message
    this.document = document
    this.duplicate = duplicate
    this.vectorReady = vectorReady
    this.vectorMessage = vectorMessage
  }
}

export class KnowledgeTextPreview {
  text: string = ''
  truncated: boolean = false

  constructor(text: string = '', truncated: boolean = false) {
    this.text = text
    this.truncated = truncated
  }
}

export class KnowledgeEmbeddingMigrationResult {
  changed: boolean = false
  totalDocuments: number = 0
  keywordReadyDocuments: number = 0
  vectorReadyDocuments: number = 0
  failedDocuments: number = 0
  lastVectorMessage: string = ''
  cancelled: boolean = false
}

class KnowledgeVectorBuildResult {
  ready: boolean = false
  message: string = ''

  constructor(ready: boolean = false, message: string = '') {
    this.ready = ready
    this.message = message
  }
}

class KnowledgeDocumentMigrationResult {
  keywordReady: boolean = false
  vectorReady: boolean = false
  message: string = ''

  constructor(keywordReady: boolean = false, vectorReady: boolean = false, message: string = '') {
    this.keywordReady = keywordReady
    this.vectorReady = vectorReady
    this.message = message
  }
}

class KnowledgeVectorStartupPlan {
  modelKey: string = ''
  documentIds: string[] = []
  vectorReady: boolean = false
  message: string = ''
}

class KnowledgeChunk {
  id: string = ''
  documentId: string = ''
  title: string = ''
  locator: string = ''
  content: string = ''
  embeddingText: string = ''
  chunkIndex: number = 0
  parentId: string = ''
  headingPath: string = ''
  pageStart: number = 0
  pageEnd: number = 0
  continuesBefore: boolean = false
  continuesAfter: boolean = false
  rawEmbedding: Float32Array | null = null

  constructor(
    id: string,
    documentId: string,
    title: string,
    locator: string,
    content: string,
    embeddingText: string,
    chunkIndex: number,
    parentId: string,
    headingPath: string,
    pageStart: number,
    pageEnd: number,
    continuesBefore: boolean,
    continuesAfter: boolean,
    rawEmbedding: Float32Array | null
  ) {
    this.id = id
    this.documentId = documentId
    this.title = title
    this.locator = locator
    this.content = content
    this.embeddingText = embeddingText
    this.chunkIndex = chunkIndex
    this.parentId = parentId
    this.headingPath = headingPath
    this.pageStart = pageStart
    this.pageEnd = pageEnd
    this.continuesBefore = continuesBefore
    this.continuesAfter = continuesAfter
    this.rawEmbedding = rawEmbedding
  }
}

class KnowledgeChunkContextMetadata {
  documentId: string = ''
  chunkIndex: number = 0
  parentId: string = ''
  continuesBefore: boolean = false
  continuesAfter: boolean = false
}

class KnowledgeStoredChunkContext {
  chunkId: string = ''
  locator: string = ''
  content: string = ''
}

export class KnowledgeDocumentService implements
  KnowledgeReadyDocumentProvider,
  KnowledgeVectorReadyDocumentProvider,
  KnowledgeVectorHealthObserver,
  KnowledgeHitContextProvider {
  private static instance: KnowledgeDocumentService | null = null
  private context: Context | null = null
  private store: relationalStore.RdbStore | null = null
  private storeConfig: relationalStore.StoreConfig | null = null
  private initPromise: Promise<void> | null = null
  private initialized: boolean = false
  private readyDocumentCount: number = 0
  private mutationTail: Promise<void> = Promise.resolve()
  private vectorRecoveryScheduled: boolean = false
  private embeddingMigrationGeneration: number = 0
  private vectorBootstrapGate: KnowledgeVectorBootstrapGate = new KnowledgeVectorBootstrapGate()
  private semanticChunker: KnowledgeSemanticChunker = new KnowledgeSemanticChunker()
  private retrievalAdapter: DataAugmentationHybridAdapter =
    new DataAugmentationHybridAdapter()

  private constructor() {
  }

  private async acquireMutationLock(): Promise<() => void> {
    const previous = this.mutationTail
    let releaseLock: () => void = (): void => {
    }
    this.mutationTail = new Promise<void>((resolve): void => {
      releaseLock = (): void => {
        resolve()
      }
    })
    await previous
    return releaseLock
  }

  static getInstance(): KnowledgeDocumentService {
    if (KnowledgeDocumentService.instance === null) {
      KnowledgeDocumentService.instance = new KnowledgeDocumentService()
    }
    return KnowledgeDocumentService.instance
  }

  async initialize(context: Context): Promise<void> {
    if (this.initialized) {
      return
    }
    if (this.initPromise !== null) {
      await this.initPromise
      return
    }
    this.initPromise = this.doInitialize(context)
    try {
      await this.initPromise
    } finally {
      this.initPromise = null
    }
  }

  private async doInitialize(context: Context): Promise<void> {
    const embeddingService = getKnowledgeEmbeddingService()
    await embeddingService.initialize()
    embeddingService.configureLocalCachePath(context.cacheDir)
    this.context = context
    this.ensureKnowledgeFilesDirectory(context)
    const config = this.buildStoreConfig()
    const store = await relationalStore.getRdbStore(context, config)
    await this.createTables(store, config)
    await this.recoverInterruptedDocuments(store)
    this.storeConfig = config
    this.store = store
    this.readyDocumentCount = await this.countReadyDocuments(store)
    this.configureRetrievalAdapter(context, config)
    this.initialized = true
    console.info(
      'KnowledgeDocumentService',
      `Initialized: readyDocuments=${this.readyDocumentCount}`
    )
    const quickVectorStartup = this.prepareVectorStartup()
    this.vectorBootstrapGate.track(
      quickVectorStartup.then(
        (plan: KnowledgeVectorStartupPlan): KnowledgeVectorBootstrapCompletion => {
          return plan.vectorReady
            ? KnowledgeVectorBootstrapCompletion.readyResult(plan.message)
            : KnowledgeVectorBootstrapCompletion.failedResult(plan.message)
        }
      )
    )
    quickVectorStartup.then(
      (plan: KnowledgeVectorStartupPlan): void => {
        if (plan.documentIds.length > 0) {
          console.info(
            'KnowledgeDocumentService',
            `Deferred startup vector migrations: documents=${plan.documentIds.length}`
          )
        }
      },
      (_error: Object): void => {
        console.warn('KnowledgeDocumentService', 'Knowledge vector startup recovery stopped')
      }
    )
  }

  private async recoverInterruptedDocuments(store: relationalStore.RdbStore): Promise<void> {
    const deletingFilePaths: string[] = []
    const deletingResultSet = await store.querySql(
      `SELECT file_path FROM ${KNOWLEDGE_DOCUMENTS_TABLE} WHERE status = ?`,
      [KnowledgeDocumentStatus.DELETING]
    )
    try {
      while (deletingResultSet.goToNextRow()) {
        const filePath = deletingResultSet.getString(deletingResultSet.getColumnIndex('file_path')).trim()
        if (filePath !== '') {
          deletingFilePaths.push(filePath)
        }
      }
    } finally {
      deletingResultSet.close()
    }

    store.beginTransaction()
    try {
      await store.executeSql(
        `DELETE FROM ${KNOWLEDGE_CHUNKS_FTS_TABLE}
         WHERE document_id IN (
           SELECT id FROM ${KNOWLEDGE_DOCUMENTS_TABLE} WHERE status <> ?
         )`,
        [KnowledgeDocumentStatus.READY]
      )
      await store.executeSql(
        `DELETE FROM ${KNOWLEDGE_CHUNK_METADATA_TABLE}
         WHERE document_id IN (
           SELECT id FROM ${KNOWLEDGE_DOCUMENTS_TABLE} WHERE status <> ?
         )`,
        [KnowledgeDocumentStatus.READY]
      )
      await store.executeSql(
        `INSERT OR REPLACE INTO ${KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE}
          (document_id, model_key, dimension, created_at)
         SELECT d.id, COALESCE(v.model_key, ?), COALESCE(v.dimension, 0), ?
         FROM ${KNOWLEDGE_DOCUMENTS_TABLE} d
         LEFT JOIN ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE} v ON v.document_id = d.id
         WHERE d.status = ?`,
        [
          getKnowledgeEmbeddingService().modelKey(),
          Date.now(),
          KnowledgeDocumentStatus.DELETING
        ]
      )
      await store.executeSql(
        `UPDATE ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE}
         SET status = ?, last_error = ?, updated_at = ?
         WHERE document_id IN (
           SELECT id FROM ${KNOWLEDGE_DOCUMENTS_TABLE} WHERE status = ?
         )`,
        [
          KnowledgeVectorIndexStatus.DELETE_PENDING,
          '等待清理本地向量派生数据',
          Date.now(),
          KnowledgeDocumentStatus.DELETING
        ]
      )
      await store.executeSql(
        `DELETE FROM ${KNOWLEDGE_DOCUMENTS_TABLE} WHERE status = ?`,
        [KnowledgeDocumentStatus.DELETING]
      )
      await store.executeSql(
        `UPDATE ${KNOWLEDGE_DOCUMENTS_TABLE}
         SET status = ?, chunk_count = 0, error_message = ?, updated_at = ?
         WHERE status = ?`,
        [
          KnowledgeDocumentStatus.FAILED,
          '上次索引过程被中断，请重建索引',
          Date.now(),
          KnowledgeDocumentStatus.INDEXING
        ]
      )
      store.commit()
    } catch (error) {
      store.rollBack()
      throw new Error(this.safeErrorMessage(error))
    }

    for (let i = 0; i < deletingFilePaths.length; i++) {
      try {
        if (fileIo.accessSync(deletingFilePaths[i])) {
          fileIo.unlinkSync(deletingFilePaths[i])
        }
      } catch (error) {
        console.warn(
          'KnowledgeDocumentService',
          `Interrupted delete file cleanup failed: ${this.safeErrorMessage(error)}`
        )
      }
    }
  }

  private buildStoreConfig(): relationalStore.StoreConfig {
    const config: relationalStore.StoreConfig = {
      name: KNOWLEDGE_DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S3
    }
    if (relationalStore.isTokenizerSupported(relationalStore.Tokenizer.CUSTOM_TOKENIZER)) {
      config.tokenizer = relationalStore.Tokenizer.CUSTOM_TOKENIZER
    }
    return config
  }

  private async createTables(
    store: relationalStore.RdbStore,
    config: relationalStore.StoreConfig
  ): Promise<void> {
    await store.executeSql(`
      CREATE TABLE IF NOT EXISTS ${KNOWLEDGE_DOCUMENTS_TABLE} (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        original_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size INTEGER NOT NULL,
        content_hash TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL,
        chunk_count INTEGER NOT NULL DEFAULT 0,
        error_message TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    `)
    await store.executeSql(`
      CREATE TABLE IF NOT EXISTS ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE} (
        document_id TEXT PRIMARY KEY,
        generation TEXT NOT NULL,
        status TEXT NOT NULL,
        chunker_version TEXT NOT NULL,
        model_key TEXT NOT NULL,
        dimension INTEGER NOT NULL DEFAULT 0,
        vector_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT NOT NULL DEFAULT '',
        updated_at INTEGER NOT NULL
      )
    `)
    await store.executeSql(`
      CREATE TABLE IF NOT EXISTS ${KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE} (
        document_id TEXT PRIMARY KEY,
        model_key TEXT NOT NULL,
        dimension INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    `)
    await store.executeSql(`
      CREATE TABLE IF NOT EXISTS ${KNOWLEDGE_CHUNK_METADATA_TABLE} (
        chunk_id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        parent_id TEXT NOT NULL,
        heading_path TEXT NOT NULL DEFAULT '',
        page_start INTEGER NOT NULL DEFAULT 0,
        page_end INTEGER NOT NULL DEFAULT 0,
        continues_before INTEGER NOT NULL DEFAULT 0,
        continues_after INTEGER NOT NULL DEFAULT 0
      )
    `)
    await store.executeSql(`
      CREATE INDEX IF NOT EXISTS knowledge_chunk_metadata_document_index
      ON ${KNOWLEDGE_CHUNK_METADATA_TABLE}(document_id, chunk_index)
    `)

    const tokenizer = config.tokenizer
    let createFtsSql = `
      CREATE VIRTUAL TABLE IF NOT EXISTS ${KNOWLEDGE_CHUNKS_FTS_TABLE}
      USING fts5(
        chunk_id UNINDEXED,
        document_id UNINDEXED,
        title,
        locator UNINDEXED,
        content
      )
    `
    if (tokenizer === relationalStore.Tokenizer.CUSTOM_TOKENIZER) {
      createFtsSql = `
        CREATE VIRTUAL TABLE IF NOT EXISTS ${KNOWLEDGE_CHUNKS_FTS_TABLE}
        USING fts5(
          chunk_id UNINDEXED,
          document_id UNINDEXED,
          title,
          locator UNINDEXED,
          content,
          tokenize='customtokenizer cut_mode short_words'
        )
      `
    }
    await store.executeSql(createFtsSql)
  }

  private configureRetrievalAdapter(context: Context, storeConfig: relationalStore.StoreConfig): void {
    const configuration: DataAugmentationInvertedIndexConfiguration = {
      context: context,
      storeConfig: storeConfig,
      ftsTableName: KNOWLEDGE_CHUNKS_FTS_TABLE,
      primaryKeyColumns: ['chunk_id'],
      documentIdColumn: 'document_id',
      chunkIdColumn: 'chunk_id',
      titleColumn: 'title',
      locatorColumn: 'locator',
      contentColumn: 'content'
    }
    this.retrievalAdapter.configure(configuration)
    this.retrievalAdapter.setVectorReadyDocumentProvider(this)
    this.retrievalAdapter.setVectorHealthObserver(this)
    const retrievalService = getKnowledgeRetrievalService()
    retrievalService.setReadyDocumentProvider(this)
    retrievalService.setHitContextProvider(this)
    retrievalService.setAdapter(this.retrievalAdapter)
  }

  private configureVectorRetrieval(context: Context, dimension: number): void {
    const vectorStore = getKnowledgeVectorStore()
    if (!vectorStore.isReady()) {
      this.retrievalAdapter.configureVector(null)
      return
    }
    const configuration: DataAugmentationVectorIndexConfiguration = {
      context: context,
      storeConfig: vectorStore.getStoreConfig(),
      tableName: vectorStore.getVectorTableName(),
      primaryKeyColumns: ['chunk_id'],
      documentIdColumn: 'document_id',
      chunkIdColumn: 'chunk_id',
      titleColumn: 'title',
      locatorColumn: 'locator',
      contentColumn: 'content',
      embeddingColumn: vectorStore.getEmbeddingColumnName(),
      dimension: dimension
    }
    this.retrievalAdapter.configureVector(configuration)
  }

  onVectorDimensionMismatch(expectedDimension: number, actualDimension: number): void {
    if (this.vectorRecoveryScheduled ||
      !Number.isFinite(actualDimension) ||
      !Number.isInteger(actualDimension) ||
      actualDimension <= 0 ||
      expectedDimension === actualDimension) {
      return
    }
    this.vectorRecoveryScheduled = true
    this.runVectorDimensionRecovery(actualDimension).catch((_error: Object): void => {
      console.warn('KnowledgeDocumentService', 'Knowledge vector dimension recovery stopped')
    })
  }

  private async runVectorDimensionRecovery(actualDimension: number): Promise<void> {
    try {
      const recovered = await this.attemptVectorDimensionRecovery(actualDimension)
      if (!recovered) {
        await new Promise<void>((resolve) => setTimeout(resolve, 1000))
        await this.attemptVectorDimensionRecovery(actualDimension)
      }
    } finally {
      this.vectorRecoveryScheduled = false
    }
  }

  private async attemptVectorDimensionRecovery(actualDimension: number): Promise<boolean> {
    try {
      return await this.recoverVectorDimensionMismatch(actualDimension)
    } catch (_error) {
      console.warn('KnowledgeDocumentService', 'Knowledge vector recovery attempt failed')
      return false
    }
  }

  private async recoverVectorDimensionMismatch(actualDimension: number): Promise<boolean> {
    const releaseLock = await this.acquireMutationLock()
    let documentIds: string[] = []
    let recoveryModelKey = ''
    try {
      const store = this.store
      const context = this.context
      if (store === null || context === null) {
        return true
      }

      const vectorStore = getKnowledgeVectorStore()
      const modelKey = getKnowledgeEmbeddingService().modelKey()
      recoveryModelKey = modelKey
      this.retrievalAdapter.configureVector(null)
      const metadata = vectorStore.getMetadata()
      if (!vectorStore.isReady() ||
        metadata === null ||
        metadata.modelKey !== modelKey ||
        metadata.dimension !== actualDimension) {
        await store.executeSql(
          `UPDATE ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE}
           SET status = ?, last_error = ?, updated_at = ?
           WHERE status = ?`,
          [
            KnowledgeVectorIndexStatus.FAILED,
            '向量维度已变化，等待按新维度重新生成',
            Date.now(),
            KnowledgeVectorIndexStatus.READY
          ]
        )
        const openResult = await vectorStore.rebuild(
          context,
          modelKey,
          actualDimension
        )
        if (!openResult.isReady()) {
          return false
        }
      }
      await this.flushPendingVectorDeletions(store)
      this.configureVectorRetrieval(context, actualDimension)
      documentIds = await this.listDocumentsNeedingVectorMigration(
        store,
        modelKey,
        true
      )
    } finally {
      releaseLock()
    }

    for (let index = 0; index < documentIds.length; index++) {
      if (getKnowledgeEmbeddingService().modelKey() !== recoveryModelKey) {
        return true
      }
      await this.migrateReadyDocument(documentIds[index], recoveryModelKey)
    }
    return true
  }

  private async prepareVectorStartup(): Promise<KnowledgeVectorStartupPlan> {
    const releaseLock = await this.acquireMutationLock()
    const plan = new KnowledgeVectorStartupPlan()
    try {
      const store = this.store
      const context = this.context
      if (store === null || context === null) {
        plan.message = '知识库上下文不可用，首次查询使用关键词检索'
        return plan
      }

      const vectorStore = getKnowledgeVectorStore()
      plan.modelKey = getKnowledgeEmbeddingService().modelKey()
      const existingState = await this.findVectorStoreSeed(
        store,
        plan.modelKey
      )
      if (existingState !== null && existingState.dimension > 0) {
        let openResult = await vectorStore.initialize(
          context,
          plan.modelKey,
          existingState.dimension
        )
        if (openResult.status === KnowledgeVectorStoreStatus.REBUILD_REQUIRED) {
          this.retrievalAdapter.configureVector(null)
          await store.executeSql(
            `UPDATE ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE}
             SET status = ?, last_error = ?, updated_at = ?
             WHERE status = ?`,
            [
              KnowledgeVectorIndexStatus.FAILED,
              '本地向量 sidecar 需要重建',
              Date.now(),
              KnowledgeVectorIndexStatus.READY
            ]
          )
          openResult = await vectorStore.rebuild(
            context,
            plan.modelKey,
            existingState.dimension
          )
        }
        if (openResult.isReady()) {
          await this.flushPendingVectorDeletions(store)
          this.configureVectorRetrieval(context, existingState.dimension)
          plan.vectorReady = true
          plan.message = '向量 sidecar 已恢复，混合检索可用'
        } else {
          plan.message = openResult.message.trim() === ''
            ? '向量 sidecar 暂不可用，首次查询使用关键词检索'
            : openResult.message
        }
      } else if (await this.hasPendingVectorDeletions(store)) {
        this.retrievalAdapter.configureVector(null)
        if (await vectorStore.purge(context)) {
          await this.clearCompletedVectorDeletionMetadata(store)
        }
      }

      plan.documentIds = await this.listDocumentsNeedingVectorMigration(
        store,
        plan.modelKey,
        vectorStore.isVectorSupported()
      )
      if (plan.message === '') {
        plan.message = vectorStore.isVectorSupported()
          ? '尚无可直接恢复的语义向量，首次查询使用关键词检索'
          : '当前设备不支持向量 sidecar，使用关键词检索'
      }
      return plan
    } finally {
      releaseLock()
    }
  }

  private async findVectorStoreSeed(
    store: relationalStore.RdbStore,
    modelKey: string
  ): Promise<KnowledgeVectorIndexState | null> {
    const readyState = await this.findReadyVectorState(store, modelKey)
    if (readyState !== null) {
      return readyState
    }
    return await this.findPendingDeletionVectorState(store, modelKey)
  }

  private async findReadyVectorState(
    store: relationalStore.RdbStore,
    modelKey: string
  ): Promise<KnowledgeVectorIndexState | null> {
    const resultSet = await store.querySql(
      `SELECT v.document_id, v.generation, v.status, v.chunker_version, v.model_key,
        v.dimension, v.vector_count, v.last_error, v.updated_at
       FROM ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE} v
       INNER JOIN ${KNOWLEDGE_DOCUMENTS_TABLE} d ON d.id = v.document_id
       WHERE d.status = ? AND v.status = ? AND v.chunker_version = ?
         AND v.model_key = ? AND v.dimension > 0
       ORDER BY v.updated_at DESC
       LIMIT 1`,
      [
        KnowledgeDocumentStatus.READY,
        KnowledgeVectorIndexStatus.READY,
        KNOWLEDGE_CHUNKER_VERSION,
        modelKey
      ]
    )
    try {
      if (!resultSet.goToNextRow()) {
        return null
      }
      return this.readVectorIndexState(resultSet)
    } finally {
      resultSet.close()
    }
  }

  private async findPendingDeletionVectorState(
    store: relationalStore.RdbStore,
    modelKey: string
  ): Promise<KnowledgeVectorIndexState | null> {
    const resultSet = await store.querySql(
      `SELECT q.document_id AS document_id, '' AS generation, ? AS status,
        '' AS chunker_version, q.model_key AS model_key, q.dimension AS dimension,
        0 AS vector_count, '' AS last_error, q.created_at AS updated_at
       FROM ${KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE} q
       WHERE q.model_key = ? AND q.dimension > 0
       ORDER BY q.created_at ASC
       LIMIT 1`,
      [
        KnowledgeVectorIndexStatus.DELETE_PENDING,
        modelKey
      ]
    )
    try {
      if (!resultSet.goToNextRow()) {
        return null
      }
      return this.readVectorIndexState(resultSet)
    } finally {
      resultSet.close()
    }
  }

  private async listDocumentsNeedingVectorMigration(
    store: relationalStore.RdbStore,
    modelKey: string,
    vectorSupported: boolean
  ): Promise<string[]> {
    const metadata = getKnowledgeVectorStore().getMetadata()
    const resultSet = await store.querySql(
      `SELECT d.id, d.content_hash, d.chunk_count,
        (SELECT COUNT(*) FROM ${KNOWLEDGE_CHUNKS_FTS_TABLE} f
          WHERE f.document_id = d.id) AS stored_chunk_count,
        (SELECT COUNT(*) FROM ${KNOWLEDGE_CHUNK_METADATA_TABLE} m
          WHERE m.document_id = d.id) AS stored_metadata_count,
        CASE WHEN v.document_id IS NULL THEN 0 ELSE 1 END AS has_vector_state,
        COALESCE(v.generation, '') AS generation,
        COALESCE(v.status, '') AS vector_status,
        COALESCE(v.chunker_version, '') AS chunker_version,
        COALESCE(v.model_key, '') AS model_key,
        COALESCE(v.dimension, 0) AS dimension,
        COALESCE(v.vector_count, 0) AS vector_count
       FROM ${KNOWLEDGE_DOCUMENTS_TABLE} d
       LEFT JOIN ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE} v ON v.document_id = d.id
       WHERE d.status = ?
       ORDER BY d.created_at ASC`,
      [KnowledgeDocumentStatus.READY]
    )
    const documentIds: string[] = []
    try {
      while (resultSet.goToNextRow()) {
        const documentId = resultSet.getString(resultSet.getColumnIndex('id')).trim()
        const hasVectorState =
          resultSet.getLong(resultSet.getColumnIndex('has_vector_state')) > 0
        if (documentId === '' || !hasVectorState) {
          if (documentId !== '') {
            documentIds.push(documentId)
          }
          continue
        }

        const contentHash = resultSet.getString(resultSet.getColumnIndex('content_hash'))
        const generation = resultSet.getString(resultSet.getColumnIndex('generation'))
        const status = resultSet.getString(resultSet.getColumnIndex('vector_status'))
        const chunkerVersion = resultSet.getString(resultSet.getColumnIndex('chunker_version'))
        const stateModelKey = resultSet.getString(resultSet.getColumnIndex('model_key'))
        const dimension = resultSet.getLong(resultSet.getColumnIndex('dimension'))
        const vectorCount = resultSet.getLong(resultSet.getColumnIndex('vector_count'))
        const chunkCount = resultSet.getLong(resultSet.getColumnIndex('chunk_count'))
        const storedChunkCount = resultSet.getLong(resultSet.getColumnIndex('stored_chunk_count'))
        const storedMetadataCount =
          resultSet.getLong(resultSet.getColumnIndex('stored_metadata_count'))
        const ftsIndexIsComplete =
          chunkCount > 0 &&
          storedChunkCount === chunkCount &&
          storedMetadataCount === chunkCount
        const identityMatches =
          generation === this.buildIndexGenerationFromHash(contentHash) &&
          chunkerVersion === KNOWLEDGE_CHUNKER_VERSION &&
          stateModelKey === modelKey
        const unsupportedIsCurrent =
          status === KnowledgeVectorIndexStatus.UNSUPPORTED &&
          !vectorSupported &&
          identityMatches &&
          ftsIndexIsComplete
        const readyStateIsComplete =
          status === KnowledgeVectorIndexStatus.READY &&
          identityMatches &&
          ftsIndexIsComplete &&
          metadata !== null &&
          metadata.modelKey === modelKey &&
          dimension > 0 &&
          dimension === metadata.dimension &&
          vectorCount > 0 &&
          vectorCount === chunkCount
        if (!unsupportedIsCurrent && !readyStateIsComplete) {
          documentIds.push(documentId)
        }
      }
    } finally {
      resultSet.close()
    }
    return documentIds
  }

  private async migrateReadyDocument(
    documentId: string,
    expectedModelKey: string = ''
  ): Promise<KnowledgeDocumentMigrationResult> {
    const releaseLock = await this.acquireMutationLock()
    let document: KnowledgeDocument | null = null
    let generation = ''
    let activeModelKey = ''
    try {
      const store = this.store
      if (store === null) {
        return new KnowledgeDocumentMigrationResult(false, false, '知识库尚未初始化')
      }
      activeModelKey = getKnowledgeEmbeddingService().modelKey()
      if (expectedModelKey !== '' && activeModelKey !== expectedModelKey) {
        return new KnowledgeDocumentMigrationResult(false, false, '向量模型已发生变化')
      }
      document = await this.findDocumentById(store, documentId)
      if (document === null || document.status !== KnowledgeDocumentStatus.READY) {
        return new KnowledgeDocumentMigrationResult(false, false, '知识文件当前不可用')
      }
      const extension = this.getSupportedExtension(document.originalName)
      if (extension === '' || !fileIo.accessSync(document.filePath)) {
        return new KnowledgeDocumentMigrationResult(false, false, '原文件不存在或格式不受支持')
      }

      generation = this.buildIndexGeneration(document)
      await this.upsertVectorIndexState(
        store,
        document.id,
        generation,
        KnowledgeVectorIndexStatus.INDEXING,
        activeModelKey,
        0,
        0,
        ''
      )
      const text = await this.extractDocumentText(document, extension)
      const chunks = await this.buildChunks(document, text, generation)
      if (chunks.length === 0) {
        throw new Error('文件中没有可建立索引的文字')
      }
      await this.replaceDocumentChunks(store, document.id, chunks)
      await this.verifyStoredDocumentChunks(store, document.id, chunks.length)
      document.chunkCount = chunks.length
      document.updatedAt = Date.now()
      await this.updateDocumentStatus(store, document)
      this.invalidateRetrievalSnapshot()
      const vectorResult = await this.indexDocumentVectorsBestEffort(
        store,
        document,
        generation,
        chunks
      )
      this.invalidateRetrievalSnapshot()
      return new KnowledgeDocumentMigrationResult(true, vectorResult.ready, vectorResult.message)
    } catch (error) {
      const errorMessage = this.safeVectorErrorMessage(error)
      const store = this.store
      if (store !== null && document !== null && generation !== '') {
        await this.upsertVectorIndexStateQuietly(
          store,
          document.id,
          generation,
          KnowledgeVectorIndexStatus.FAILED,
          activeModelKey,
          0,
          0,
          errorMessage
        )
      }
      this.invalidateRetrievalSnapshot()
      return new KnowledgeDocumentMigrationResult(false, false, errorMessage)
    } finally {
      releaseLock()
    }
  }

  async listVectorReadyDocumentIds(documentIds: string[]): Promise<string[]> {
    const store = this.store
    const vectorStore = getKnowledgeVectorStore()
    const metadata = vectorStore.getMetadata()
    if (store === null || !vectorStore.isReady() || metadata === null) {
      return []
    }
    const modelKey = getKnowledgeEmbeddingService().modelKey()
    if (metadata.modelKey !== modelKey) {
      return []
    }
    const resultSet = await store.querySql(
      `SELECT d.id, d.content_hash, v.generation
       FROM ${KNOWLEDGE_DOCUMENTS_TABLE} d
       INNER JOIN ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE} v ON v.document_id = d.id
       WHERE d.status = ? AND v.status = ? AND v.chunker_version = ?
         AND v.model_key = ? AND v.dimension = ?
         AND v.vector_count > 0 AND v.vector_count = d.chunk_count`,
      [
        KnowledgeDocumentStatus.READY,
        KnowledgeVectorIndexStatus.READY,
        KNOWLEDGE_CHUNKER_VERSION,
        modelKey,
        metadata.dimension
      ]
    )
    const readyDocumentIds: string[] = []
    try {
      while (resultSet.goToNextRow()) {
        const documentId = resultSet.getString(resultSet.getColumnIndex('id')).trim()
        const contentHash = resultSet.getString(resultSet.getColumnIndex('content_hash'))
        const generation = resultSet.getString(resultSet.getColumnIndex('generation'))
        if ((documentIds.length === 0 || documentIds.indexOf(documentId) >= 0) &&
          generation === this.buildIndexGenerationFromHash(contentHash)) {
          readyDocumentIds.push(documentId)
        }
      }
    } finally {
      resultSet.close()
    }
    return readyDocumentIds
  }

  private async hasPendingVectorDeletions(store: relationalStore.RdbStore): Promise<boolean> {
    const resultSet = await store.querySql(
      `SELECT COUNT(*) AS pending_count
       FROM ${KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE}
       WHERE NOT EXISTS (
         SELECT 1 FROM ${KNOWLEDGE_DOCUMENTS_TABLE} d
         WHERE d.id = ${KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE}.document_id
       )`
    )
    try {
      return resultSet.goToNextRow() &&
        resultSet.getLong(resultSet.getColumnIndex('pending_count')) > 0
    } finally {
      resultSet.close()
    }
  }

  private async flushPendingVectorDeletions(store: relationalStore.RdbStore): Promise<void> {
    const vectorStore = getKnowledgeVectorStore()
    if (!vectorStore.isReady()) {
      return
    }
    const resultSet = await store.querySql(
      `SELECT q.document_id
       FROM ${KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE} q
       WHERE NOT EXISTS (
         SELECT 1 FROM ${KNOWLEDGE_DOCUMENTS_TABLE} d WHERE d.id = q.document_id
       )
       ORDER BY q.created_at ASC`
    )
    const documentIds: string[] = []
    try {
      while (resultSet.goToNextRow()) {
        const documentId = resultSet.getString(resultSet.getColumnIndex('document_id')).trim()
        if (documentId !== '') {
          documentIds.push(documentId)
        }
      }
    } finally {
      resultSet.close()
    }
    for (let index = 0; index < documentIds.length; index++) {
      try {
        await vectorStore.deleteDocument(documentIds[index])
        await this.completeVectorDeletionMetadata(store, documentIds[index])
      } catch (_error) {
        console.warn('KnowledgeDocumentService', 'Pending knowledge vector cleanup will retry')
      }
    }
  }

  private async clearCompletedVectorDeletionMetadata(
    store: relationalStore.RdbStore
  ): Promise<void> {
    store.beginTransaction()
    try {
      await store.executeSql(
        `DELETE FROM ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE}
         WHERE document_id IN (
           SELECT q.document_id FROM ${KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE} q
           WHERE NOT EXISTS (
             SELECT 1 FROM ${KNOWLEDGE_DOCUMENTS_TABLE} d WHERE d.id = q.document_id
           )
         )`
      )
      await store.executeSql(
        `DELETE FROM ${KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE}
         WHERE NOT EXISTS (
           SELECT 1 FROM ${KNOWLEDGE_DOCUMENTS_TABLE} d
           WHERE d.id = ${KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE}.document_id
         )`
      )
      store.commit()
    } catch (error) {
      store.rollBack()
      throw new Error(this.safeErrorMessage(error))
    }
  }

  private async completeVectorDeletionMetadata(
    store: relationalStore.RdbStore,
    documentId: string
  ): Promise<void> {
    store.beginTransaction()
    try {
      await store.executeSql(
        `DELETE FROM ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE}
         WHERE document_id = ? AND NOT EXISTS (
           SELECT 1 FROM ${KNOWLEDGE_DOCUMENTS_TABLE} d WHERE d.id = ?
         )`,
        [documentId, documentId]
      )
      await store.executeSql(
        `DELETE FROM ${KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE} WHERE document_id = ?`,
        [documentId]
      )
      store.commit()
    } catch (error) {
      store.rollBack()
      throw new Error(this.safeErrorMessage(error))
    }
  }

  private readVectorIndexState(
    resultSet: relationalStore.ResultSet
  ): KnowledgeVectorIndexState {
    const state = new KnowledgeVectorIndexState()
    state.documentId = resultSet.getString(resultSet.getColumnIndex('document_id'))
    state.generation = resultSet.getString(resultSet.getColumnIndex('generation'))
    state.status = resultSet.getString(resultSet.getColumnIndex('status'))
    state.chunkerVersion = resultSet.getString(resultSet.getColumnIndex('chunker_version'))
    state.modelKey = resultSet.getString(resultSet.getColumnIndex('model_key'))
    state.dimension = resultSet.getLong(resultSet.getColumnIndex('dimension'))
    state.vectorCount = resultSet.getLong(resultSet.getColumnIndex('vector_count'))
    state.lastError = resultSet.getString(resultSet.getColumnIndex('last_error'))
    state.updatedAt = resultSet.getLong(resultSet.getColumnIndex('updated_at'))
    return state
  }

  private buildIndexGeneration(document: KnowledgeDocument): string {
    return this.buildIndexGenerationFromHash(document.contentHash)
  }

  private buildIndexGenerationFromHash(contentHash: string): string {
    const modelToken = getKnowledgeEmbeddingService().modelKey()
      .replace(/[^A-Za-z0-9]+/g, '_')
      .substring(0, 32)
    const hashToken = contentHash.substring(0, 16)
    return `${KNOWLEDGE_CHUNKER_VERSION}_${modelToken}_${hashToken}`
  }

  private async indexDocumentVectorsBestEffort(
    store: relationalStore.RdbStore,
    document: KnowledgeDocument,
    generation: string,
    chunks: KnowledgeChunk[]
  ): Promise<KnowledgeVectorBuildResult> {
    const embeddingService = getKnowledgeEmbeddingService()
    const vectorStore = getKnowledgeVectorStore()
    try {
      await this.upsertVectorIndexState(
        store,
        document.id,
        generation,
        KnowledgeVectorIndexStatus.INDEXING,
        embeddingService.modelKey(),
        0,
        0,
        ''
      )
      if (!vectorStore.isVectorSupported()) {
        const unsupportedMessage = '当前设备不支持本地语义向量库'
        await this.upsertVectorIndexState(
          store,
          document.id,
          generation,
          KnowledgeVectorIndexStatus.UNSUPPORTED,
          embeddingService.modelKey(),
          0,
          0,
          unsupportedMessage
        )
        return new KnowledgeVectorBuildResult(false, unsupportedMessage)
      }
      if (!embeddingService.isAvailable()) {
        const unavailableMessage = embeddingService.availabilityMessage()
        throw new Error(unavailableMessage === ''
          ? '本次运行期间所选向量模型不可用'
          : unavailableMessage)
      }

      const vectors: Float32Array[] = []
      const reusableRawVectors = await this.collectReusableRawChunkVectors(chunks)
      if (reusableRawVectors !== null) {
        for (let index = 0; index < reusableRawVectors.length; index++) {
          vectors.push(projectKnowledgeVector(reusableRawVectors[index]))
          if (this.shouldYieldChunkWork(index, reusableRawVectors.length)) {
            await this.yieldToUiFrame()
          }
        }
      } else {
        const maximumInputCharacters = Math.max(64, embeddingService.maxInputCharacters())
        for (let start = 0; start < chunks.length; start += EMBEDDING_BATCH_SIZE) {
          const end = Math.min(chunks.length, start + EMBEDDING_BATCH_SIZE)
          const texts: string[] = []
          for (let index = start; index < end; index++) {
            texts.push(this.limitEmbeddingText(
              chunks[index].embeddingText,
              maximumInputCharacters
            ))
          }
          const batchVectors = await embeddingService.embedDocuments(texts)
          for (let index = 0; index < batchVectors.length; index++) {
            vectors.push(projectKnowledgeVector(batchVectors[index]))
          }
          if (end < chunks.length) {
            await this.yieldToUiFrame()
          }
        }
      }
      if (vectors.length !== chunks.length || vectors.length === 0) {
        throw new Error('向量模型返回的结果数量无效')
      }
      const dimension = vectors[0].length
      const context = this.context
      if (context === null) {
        throw new Error('知识库上下文不可用')
      }

      let openResult = await vectorStore.initialize(
        context,
        embeddingService.modelKey(),
        dimension
      )
      if (openResult.status === KnowledgeVectorStoreStatus.REBUILD_REQUIRED) {
        this.retrievalAdapter.configureVector(null)
        await store.executeSql(
          `UPDATE ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE}
           SET status = ?, last_error = ?, updated_at = ?
           WHERE status = ?`,
          [
            KnowledgeVectorIndexStatus.FAILED,
            '向量 sidecar 已重建，等待重新生成',
            Date.now(),
            KnowledgeVectorIndexStatus.READY
          ]
        )
        openResult = await vectorStore.rebuild(
          context,
          embeddingService.modelKey(),
          dimension
        )
      }
      if (!openResult.isReady()) {
        const openMessage = openResult.message.trim() === ''
          ? '本地向量 sidecar 不可用'
          : openResult.message
        throw new Error(openMessage)
      }
      await this.flushPendingVectorDeletions(store)

      const records: KnowledgeVectorRecord[] = []
      for (let index = 0; index < chunks.length; index++) {
        const chunk = chunks[index]
        records.push(new KnowledgeVectorRecord(
          chunk.id,
          chunk.documentId,
          generation,
          chunk.title,
          chunk.locator,
          chunk.content,
          vectors[index]
        ))
        if (this.shouldYieldChunkWork(index, chunks.length)) {
          await this.yieldToUiFrame()
        }
      }
      const vectorCount = await vectorStore.replaceDocumentGeneration(
        document.id,
        generation,
        records
      )
      if (vectorCount !== chunks.length) {
        throw new Error('本地向量写入数量不完整')
      }
      await this.upsertVectorIndexState(
        store,
        document.id,
        generation,
        KnowledgeVectorIndexStatus.READY,
        embeddingService.modelKey(),
        dimension,
        vectorCount,
        ''
      )
      this.configureVectorRetrieval(context, dimension)
      return new KnowledgeVectorBuildResult(true, '语义向量索引已就绪')
    } catch (error) {
      await this.deleteVectorDocumentQuietly(document.id)
      const unavailable = vectorStore.getStatus() === KnowledgeVectorStoreStatus.UNSUPPORTED
      const failureMessage = unavailable
        ? '当前设备不支持本地语义向量库'
        : this.safeVectorErrorMessage(error)
      await this.upsertVectorIndexStateQuietly(
        store,
        document.id,
        generation,
        unavailable ? KnowledgeVectorIndexStatus.UNSUPPORTED : KnowledgeVectorIndexStatus.FAILED,
        embeddingService.modelKey(),
        0,
        0,
        failureMessage
      )
      console.warn(
        'KnowledgeDocumentService',
        `Vector indexing unavailable; BM25 remains active: ` +
        `status=${vectorStore.getStatus()}, error=${failureMessage}`
      )
      return new KnowledgeVectorBuildResult(false, failureMessage)
    }
  }

  private async collectReusableRawChunkVectors(
    chunks: KnowledgeChunk[]
  ): Promise<Float32Array[] | null> {
    if (chunks.length === 0) {
      return null
    }
    const first = chunks[0].rawEmbedding
    if (first === null || first.length === 0) {
      return null
    }
    const dimension = first.length
    const vectors: Float32Array[] = []
    for (let chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
      const vector = chunks[chunkIndex].rawEmbedding
      if (vector === null || vector.length !== dimension) {
        return null
      }
      let hasMagnitude = false
      for (let valueIndex = 0; valueIndex < vector.length; valueIndex++) {
        if (!Number.isFinite(vector[valueIndex])) {
          return null
        }
        if (vector[valueIndex] !== 0) {
          hasMagnitude = true
        }
      }
      if (!hasMagnitude) {
        return null
      }
      vectors.push(vector)
      if (this.shouldYieldChunkWork(chunkIndex, chunks.length)) {
        await this.yieldToUiFrame()
      }
    }
    return vectors
  }

  private limitEmbeddingText(value: string, maximumCharacters: number): string {
    if (value.length <= maximumCharacters) {
      return value
    }
    return value.substring(0, maximumCharacters).trim()
  }

  private async upsertVectorIndexState(
    store: relationalStore.RdbStore,
    documentId: string,
    generation: string,
    status: string,
    modelKey: string,
    dimension: number,
    vectorCount: number,
    lastError: string
  ): Promise<void> {
    await store.executeSql(
      `INSERT OR REPLACE INTO ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE}
        (document_id, generation, status, chunker_version, model_key, dimension,
         vector_count, last_error, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        documentId,
        generation,
        status,
        KNOWLEDGE_CHUNKER_VERSION,
        modelKey,
        dimension,
        vectorCount,
        lastError.substring(0, 512),
        Date.now()
      ]
    )
  }

  private async upsertVectorIndexStateQuietly(
    store: relationalStore.RdbStore,
    documentId: string,
    generation: string,
    status: string,
    modelKey: string,
    dimension: number,
    vectorCount: number,
    lastError: string
  ): Promise<void> {
    try {
      await this.upsertVectorIndexState(
        store,
        documentId,
        generation,
        status,
        modelKey,
        dimension,
        vectorCount,
        lastError
      )
    } catch (_error) {
      console.warn('KnowledgeDocumentService', 'Knowledge vector state update failed')
    }
  }

  private async deleteVectorDocumentQuietly(documentId: string): Promise<void> {
    const vectorStore = getKnowledgeVectorStore()
    if (!vectorStore.isReady()) {
      return
    }
    try {
      await vectorStore.deleteDocument(documentId)
    } catch (_error) {
      console.warn('KnowledgeDocumentService', 'Knowledge vector cleanup failed')
    }
  }

  private async enqueueVectorDeletion(
    store: relationalStore.RdbStore,
    documentId: string
  ): Promise<void> {
    let modelKey = getKnowledgeEmbeddingService().modelKey()
    let dimension = 0
    const resultSet = await store.querySql(
      `SELECT model_key, dimension
       FROM ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE}
       WHERE document_id = ?
       LIMIT 1`,
      [documentId]
    )
    try {
      if (resultSet.goToNextRow()) {
        modelKey = resultSet.getString(resultSet.getColumnIndex('model_key'))
        dimension = resultSet.getLong(resultSet.getColumnIndex('dimension'))
      }
    } finally {
      resultSet.close()
    }
    await store.executeSql(
      `INSERT OR REPLACE INTO ${KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE}
        (document_id, model_key, dimension, created_at)
       VALUES (?, ?, ?, ?)`,
      [documentId, modelKey, dimension, Date.now()]
    )
    await store.executeSql(
      `UPDATE ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE}
       SET status = ?, last_error = ?, updated_at = ?
       WHERE document_id = ?`,
      [
        KnowledgeVectorIndexStatus.DELETE_PENDING,
        '等待清理本地向量派生数据',
        Date.now(),
        documentId
      ]
    )
  }

  private async tryDeleteVectorDocument(documentId: string): Promise<boolean> {
    const vectorStore = getKnowledgeVectorStore()
    if (!vectorStore.isReady()) {
      return false
    }
    try {
      await vectorStore.deleteDocument(documentId)
      return true
    } catch (_error) {
      console.warn('KnowledgeDocumentService', 'Knowledge vector deletion queued for retry')
      return false
    }
  }

  private async cancelVectorDeletion(
    store: relationalStore.RdbStore,
    documentId: string
  ): Promise<void> {
    await store.executeSql(
      `DELETE FROM ${KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE} WHERE document_id = ?`,
      [documentId]
    )
    await store.executeSql(
      `UPDATE ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE}
       SET status = ?, last_error = ?, updated_at = ?
       WHERE document_id = ? AND status = ?`,
      [
        KnowledgeVectorIndexStatus.FAILED,
        '文档删除未完成，等待重新生成向量',
        Date.now(),
        documentId,
        KnowledgeVectorIndexStatus.DELETE_PENDING
      ]
    )
  }

  private safeVectorErrorMessage(error: Object): string {
    if (error instanceof Error && error.message.trim() !== '') {
      return error.message.substring(0, 512)
    }
    return '语义向量索引失败，将继续使用关键词检索'
  }

  private shouldYieldChunkWork(index: number, total: number): boolean {
    return index + 1 < total && (index + 1) % KNOWLEDGE_CHUNK_YIELD_INTERVAL === 0
  }

  private async yieldToUiFrame(): Promise<void> {
    await new Promise<void>((resolve): void => {
      setTimeout(resolve, KNOWLEDGE_UI_YIELD_MS)
    })
  }

  isReady(): boolean {
    return this.initialized && this.store !== null
  }

  async switchEmbeddingSelection(
    selection: KnowledgeEmbeddingSelection
  ): Promise<KnowledgeEmbeddingMigrationResult> {
    const result = new KnowledgeEmbeddingMigrationResult()
    const embeddingService = getKnowledgeEmbeddingService()
    await embeddingService.initialize()
    if (embeddingService.getSelection().identityKey() === selection.identityKey()) {
      return result
    }

    await embeddingService.validateSelection(selection)
    const releaseLock = await this.acquireMutationLock()
    let documentIds: string[] = []
    let migrationGeneration = 0
    let migrationModelKey = ''
    try {
      const store = this.store
      const context = this.context
      if (store === null || context === null) {
        throw new Error('知识库尚未初始化')
      }

      this.retrievalAdapter.configureVector(null)
      try {
        result.changed = await embeddingService.applySelection(selection)
      } catch (error) {
        const metadata = getKnowledgeVectorStore().getMetadata()
        if (metadata !== null && metadata.modelKey === embeddingService.modelKey()) {
          this.configureVectorRetrieval(context, metadata.dimension)
        }
        throw new Error(this.safeVectorErrorMessage(error))
      }
      if (!result.changed) {
        const metadata = getKnowledgeVectorStore().getMetadata()
        if (metadata !== null && metadata.modelKey === embeddingService.modelKey()) {
          this.configureVectorRetrieval(context, metadata.dimension)
        }
        return result
      }

      this.embeddingMigrationGeneration += 1
      migrationGeneration = this.embeddingMigrationGeneration
      migrationModelKey = embeddingService.modelKey()
      await store.executeSql(
        `UPDATE ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE}
         SET status = ?, last_error = ?, updated_at = ?
         WHERE status <> ?`,
        [
          KnowledgeVectorIndexStatus.FAILED,
          '向量模型已切换，等待重新生成',
          Date.now(),
          KnowledgeVectorIndexStatus.DELETE_PENDING
        ]
      )
      documentIds = await this.listReadyDocumentIds()
      result.totalDocuments = documentIds.length
    } finally {
      releaseLock()
    }

    for (let index = 0; index < documentIds.length; index++) {
      if (migrationGeneration !== this.embeddingMigrationGeneration) {
        result.cancelled = true
        break
      }
      const migrated = await this.migrateReadyDocument(documentIds[index], migrationModelKey)
      if (migrationGeneration !== this.embeddingMigrationGeneration ||
        embeddingService.modelKey() !== migrationModelKey) {
        result.cancelled = true
        break
      }
      if (migrated.keywordReady) {
        result.keywordReadyDocuments += 1
      } else {
        result.failedDocuments += 1
      }
      if (migrated.vectorReady) {
        result.vectorReadyDocuments += 1
      } else if (migrated.message.trim() !== '') {
        result.lastVectorMessage = migrated.message
      }
    }
    return result
  }

  hasReadyDocuments(): boolean {
    return this.readyDocumentCount > 0
  }

  isRetrievalReady(): boolean {
    return this.isReady() && this.hasReadyDocuments() &&
      getKnowledgeRetrievalService().isAvailable()
  }

  /**
   * 只允许真实 knowledge_search executor 调用。工具曝光、提示词构建和页面状态
   * 查询不得等待该 gate，避免在模型调用工具前触发任何检索链路。
   */
  async awaitVectorBootstrapForKnowledgeSearch(): Promise<KnowledgeVectorBootstrapResult> {
    return await this.vectorBootstrapGate.waitForFirstKnowledgeSearch()
  }

  shouldExposeKnowledgeTool(): boolean {
    // 输入区的“利用知识库”开关决定本轮是否向模型曝光工具。
    // 服务层只校验索引是否真实可检索，避免旧版全局偏好阻断新入口。
    return this.isRetrievalReady()
  }

  async listDocuments(): Promise<KnowledgeDocument[]> {
    const store = this.store
    if (store === null) {
      return []
    }
    const resultSet = await store.querySql(
      `SELECT id, title, original_name, file_path, mime_type, size, content_hash, status,
        chunk_count, error_message, created_at, updated_at
       FROM ${KNOWLEDGE_DOCUMENTS_TABLE}
       ORDER BY created_at DESC`
    )
    const documents: KnowledgeDocument[] = []
    try {
      while (resultSet.goToNextRow()) {
        documents.push(this.readDocument(resultSet))
      }
    } finally {
      resultSet.close()
    }
    return documents
  }

  async listReadyDocumentIds(): Promise<string[]> {
    const store = this.store
    if (store === null) {
      return []
    }
    const resultSet = await store.querySql(
      `SELECT id FROM ${KNOWLEDGE_DOCUMENTS_TABLE} WHERE status = ?`,
      [KnowledgeDocumentStatus.READY]
    )
    const documentIds: string[] = []
    try {
      while (resultSet.goToNextRow()) {
        const documentId = resultSet.getString(resultSet.getColumnIndex('id')).trim()
        if (documentId !== '') {
          documentIds.push(documentId)
        }
      }
    } finally {
      resultSet.close()
    }
    return documentIds
  }

  /**
   * 在纯检索命中之后按父块关系补齐最多一个前后相邻块。
   * 该方法只由 KnowledgeRetrievalService 在真实工具检索完成后调用；
   * 不生成 query、不再次召回，也不向提示词直接注入内容。
   */
  async expandHitContexts(hits: KnowledgeSearchHit[]): Promise<KnowledgeSearchHit[]> {
    const store = this.store
    if (store === null || hits.length === 0) {
      return hits
    }
    const preciseChunkIds: string[] = []
    for (let index = 0; index < hits.length; index++) {
      if (preciseChunkIds.indexOf(hits[index].chunkId) < 0) {
        preciseChunkIds.push(hits[index].chunkId)
      }
    }
    const expanded: KnowledgeSearchHit[] = []
    for (let index = 0; index < hits.length; index++) {
      expanded.push(await this.expandSingleHitContext(
        store,
        hits[index],
        preciseChunkIds
      ))
    }
    return expanded
  }

  private async expandSingleHitContext(
    store: relationalStore.RdbStore,
    hit: KnowledgeSearchHit,
    preciseChunkIds: string[]
  ): Promise<KnowledgeSearchHit> {
    const metadata = await this.findChunkContextMetadata(store, hit.chunkId)
    if (metadata === null || metadata.parentId === '') {
      return hit
    }

    let previous: KnowledgeStoredChunkContext | null = null
    let next: KnowledgeStoredChunkContext | null = null
    if (metadata.continuesBefore && metadata.chunkIndex > 0) {
      previous = await this.findStoredChunkContext(
        store,
        metadata.documentId,
        metadata.parentId,
        metadata.chunkIndex - 1
      )
    }
    if (metadata.continuesAfter) {
      next = await this.findStoredChunkContext(
        store,
        metadata.documentId,
        metadata.parentId,
        metadata.chunkIndex + 1
      )
    }
    if (previous !== null && preciseChunkIds.indexOf(previous.chunkId) >= 0) {
      previous = null
    }
    if (next !== null && preciseChunkIds.indexOf(next.chunkId) >= 0) {
      next = null
    }
    if (previous === null && next === null) {
      return hit
    }

    const contentBlocks: string[] = []
    const locatorParts: string[] = []
    if (previous !== null) {
      this.appendUniqueContentBlocks(contentBlocks, previous.content)
      this.appendUniqueString(locatorParts, previous.locator)
    }
    this.appendUniqueContentBlocks(contentBlocks, hit.content)
    this.appendUniqueString(locatorParts, hit.locator)
    if (next !== null) {
      this.appendUniqueContentBlocks(contentBlocks, next.content)
      this.appendUniqueString(locatorParts, next.locator)
    }
    return new KnowledgeSearchHit(
      hit.documentId,
      hit.chunkId,
      hit.title,
      locatorParts.join(' → '),
      hit.score,
      contentBlocks.join('\n\n')
    )
  }

  private async findChunkContextMetadata(
    store: relationalStore.RdbStore,
    chunkId: string
  ): Promise<KnowledgeChunkContextMetadata | null> {
    const resultSet = await store.querySql(
      `SELECT document_id, chunk_index, parent_id, continues_before, continues_after
       FROM ${KNOWLEDGE_CHUNK_METADATA_TABLE}
       WHERE chunk_id = ?
       LIMIT 1`,
      [chunkId]
    )
    try {
      if (!resultSet.goToNextRow()) {
        return null
      }
      const metadata = new KnowledgeChunkContextMetadata()
      metadata.documentId =
        resultSet.getString(resultSet.getColumnIndex('document_id'))
      metadata.chunkIndex =
        resultSet.getLong(resultSet.getColumnIndex('chunk_index'))
      metadata.parentId =
        resultSet.getString(resultSet.getColumnIndex('parent_id'))
      metadata.continuesBefore =
        resultSet.getLong(resultSet.getColumnIndex('continues_before')) > 0
      metadata.continuesAfter =
        resultSet.getLong(resultSet.getColumnIndex('continues_after')) > 0
      return metadata
    } finally {
      resultSet.close()
    }
  }

  private async findStoredChunkContext(
    store: relationalStore.RdbStore,
    documentId: string,
    parentId: string,
    chunkIndex: number
  ): Promise<KnowledgeStoredChunkContext | null> {
    const resultSet = await store.querySql(
      `SELECT f.chunk_id, f.locator, f.content
       FROM ${KNOWLEDGE_CHUNK_METADATA_TABLE} m
       INNER JOIN ${KNOWLEDGE_CHUNKS_FTS_TABLE} f ON f.chunk_id = m.chunk_id
       WHERE m.document_id = ? AND m.parent_id = ? AND m.chunk_index = ?
       LIMIT 1`,
      [documentId, parentId, chunkIndex]
    )
    try {
      if (!resultSet.goToNextRow()) {
        return null
      }
      const context = new KnowledgeStoredChunkContext()
      context.chunkId = resultSet.getString(resultSet.getColumnIndex('chunk_id')).trim()
      context.locator = resultSet.getString(resultSet.getColumnIndex('locator')).trim()
      context.content = resultSet.getString(resultSet.getColumnIndex('content')).trim()
      return context.content === '' ? null : context
    } finally {
      resultSet.close()
    }
  }

  private appendUniqueContentBlocks(target: string[], value: string): void {
    const blocks = value.split('\n\n')
    for (let index = 0; index < blocks.length; index++) {
      const block = blocks[index].trim()
      if (block !== '' && target.indexOf(block) < 0) {
        target.push(block)
      }
    }
  }

  private appendUniqueString(target: string[], value: string): void {
    const normalized = value.trim()
    if (normalized !== '' && target.indexOf(normalized) < 0) {
      target.push(normalized)
    }
  }

  async loadTextPreview(documentId: string): Promise<KnowledgeTextPreview> {
    const store = this.store
    if (store === null) {
      throw new Error('知识库尚未初始化')
    }
    const document = await this.findDocumentById(store, documentId)
    if (document === null) {
      throw new Error('未找到知识库文件')
    }
    const extension = this.getSupportedExtension(document.originalName)
    if (extension !== '.txt' && extension !== '.md' && extension !== '.markdown') {
      throw new Error('该文件不支持文本预览')
    }
    if (!fileIo.accessSync(document.filePath)) {
      throw new Error('原文件不存在')
    }
    const bytes = this.readFilePathBytes(document.filePath)
    const decoder = util.TextDecoder.create('utf-8')
    const text = this.normalizeText(decoder.decodeToString(bytes, { stream: false }))
    const truncated = text.length > MAX_DOCUMENT_TEXT_CHARACTERS
    return new KnowledgeTextPreview(
      truncated ? text.substring(0, MAX_DOCUMENT_TEXT_CHARACTERS) : text,
      truncated
    )
  }

  async importDocument(uri: string, originalName: string): Promise<KnowledgeImportResult> {
    const releaseLock = await this.acquireMutationLock()
    try {
      return await this.importDocumentLocked(uri, originalName)
    } finally {
      releaseLock()
    }
  }

  private async importDocumentLocked(uri: string, originalName: string): Promise<KnowledgeImportResult> {
    const store = this.store
    const context = this.context
    if (store === null || context === null) {
      return new KnowledgeImportResult(false, '知识库尚未初始化')
    }

    const normalizedName = this.normalizeFileName(originalName)
    const extension = this.getSupportedExtension(normalizedName)
    if (extension === '') {
      return new KnowledgeImportResult(false, '当前知识库支持 PDF、TXT、Markdown 和常见图片文件')
    }

    let sourceFile: fileIo.File | null = null
    let targetPath = ''
    let documentInserted = false
    try {
      sourceFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(sourceFile.fd)
      if (stat.size <= 0) {
        return new KnowledgeImportResult(false, '文件为空')
      }
      if (stat.size > MAX_FILE_BYTES) {
        return new KnowledgeImportResult(false, '文件超过 20 MB 限制')
      }

      const bytes = this.readFileBytes(sourceFile.fd, stat.size)
      const contentHash = await this.sha256Hex(bytes)
      const duplicate = await this.findDocumentByHash(store, contentHash)
      if (duplicate !== null) {
        const storedChunkCount = await this.countStoredDocumentChunks(store, duplicate.id)
        const storedMetadataCount =
          await this.countStoredDocumentChunkMetadata(store, duplicate.id)
        if (duplicate.status === KnowledgeDocumentStatus.READY &&
          duplicate.chunkCount > 0 &&
          storedChunkCount === duplicate.chunkCount &&
          storedMetadataCount === duplicate.chunkCount) {
          return new KnowledgeImportResult(true, '该文件已在知识库中', duplicate, true)
        }
        const rebuilt = await this.rebuildDocumentLocked(duplicate.id)
        rebuilt.duplicate = true
        if (rebuilt.ok) {
          rebuilt.message = '已恢复该文件的知识索引'
        }
        return rebuilt
      }

      const documentId = this.generateId('kb_doc')
      targetPath = `${context.filesDir}/${KNOWLEDGE_FILES_DIRECTORY}/${documentId}${extension}`
      this.writeFileBytes(targetPath, bytes)
      const now = Date.now()
      const document = new KnowledgeDocument(
        documentId,
        this.titleFromFileName(normalizedName),
        normalizedName,
        targetPath,
        this.mimeTypeForExtension(extension),
        stat.size
      )
      document.contentHash = contentHash
      document.status = KnowledgeDocumentStatus.INDEXING
      document.createdAt = now
      document.updatedAt = now
      await this.insertDocument(store, document)
      documentInserted = true

      try {
        const text = await this.extractDocumentText(document, extension)
        const generation = this.buildIndexGeneration(document)
        const chunks = await this.buildChunks(document, text, generation)
        if (chunks.length === 0) {
          throw new Error('文件中没有可建立索引的文字')
        }
        await this.replaceDocumentChunks(store, document.id, chunks)
        await this.verifyStoredDocumentChunks(store, document.id, chunks.length)
        document.status = KnowledgeDocumentStatus.READY
        document.chunkCount = chunks.length
        document.errorMessage = ''
        document.updatedAt = Date.now()
        await this.updateDocumentStatus(store, document)
        this.readyDocumentCount += 1
        this.invalidateRetrievalSnapshot()
        const vectorResult = await this.indexDocumentVectorsBestEffort(
          store,
          document,
          generation,
          chunks
        )
        const indexMode = vectorResult.ready
          ? '语义向量与关键词混合索引已就绪'
          : `关键词索引已就绪；语义向量未完成：${vectorResult.message}`
        return new KnowledgeImportResult(
          true,
          `已建立 ${chunks.length} 个知识片段，${indexMode}`,
          document,
          false,
          vectorResult.ready,
          vectorResult.message
        )
      } catch (error) {
        await this.deleteVectorDocumentQuietly(document.id)
        document.status = KnowledgeDocumentStatus.FAILED
        document.errorMessage = this.safeErrorMessage(error)
        document.updatedAt = Date.now()
        await this.deleteDocumentChunks(store, document.id)
        await this.updateDocumentStatus(store, document)
        this.invalidateRetrievalSnapshot()
        return new KnowledgeImportResult(false, document.errorMessage, document)
      }
    } catch (error) {
      console.error('KnowledgeDocumentService', `Import failed: ${JSON.stringify(error)}`)
      if (!documentInserted && targetPath !== '') {
        try {
          if (fileIo.accessSync(targetPath)) {
            fileIo.unlinkSync(targetPath)
          }
        } catch (cleanupError) {
          console.warn(
            'KnowledgeDocumentService',
            `Failed to remove incomplete knowledge file: ${this.safeErrorMessage(cleanupError)}`
          )
        }
      }
      return new KnowledgeImportResult(false, this.safeErrorMessage(error))
    } finally {
      if (sourceFile !== null) {
        fileIo.closeSync(sourceFile)
      }
    }
  }

  async rebuildDocument(documentId: string): Promise<KnowledgeImportResult> {
    const releaseLock = await this.acquireMutationLock()
    try {
      return await this.rebuildDocumentLocked(documentId)
    } finally {
      releaseLock()
    }
  }

  private async rebuildDocumentLocked(documentId: string): Promise<KnowledgeImportResult> {
    const store = this.store
    if (store === null) {
      return new KnowledgeImportResult(false, '知识库尚未初始化')
    }
    const document = await this.findDocumentById(store, documentId)
    if (document === null) {
      return new KnowledgeImportResult(false, '未找到知识库文件')
    }
    const extension = this.getSupportedExtension(document.originalName)
    if (extension === '' || !fileIo.accessSync(document.filePath)) {
      return new KnowledgeImportResult(false, '原文件不存在或格式不受支持', document)
    }

    const wasReady = document.status === KnowledgeDocumentStatus.READY
    const previousChunkCount = document.chunkCount
    const generation = this.buildIndexGeneration(document)
    if (!wasReady) {
      document.status = KnowledgeDocumentStatus.INDEXING
    }
    document.errorMessage = ''
    document.updatedAt = Date.now()
    await this.updateDocumentStatus(store, document)
    try {
      await this.upsertVectorIndexState(
        store,
        document.id,
        generation,
        KnowledgeVectorIndexStatus.INDEXING,
        getKnowledgeEmbeddingService().modelKey(),
        0,
        0,
        ''
      )
      const text = await this.extractDocumentText(document, extension)
      const chunks = await this.buildChunks(document, text, generation)
      if (chunks.length === 0) {
        throw new Error('文件中没有可建立索引的文字')
      }
      await this.replaceDocumentChunks(store, document.id, chunks)
      await this.verifyStoredDocumentChunks(store, document.id, chunks.length)
      document.status = KnowledgeDocumentStatus.READY
      document.chunkCount = chunks.length
      document.errorMessage = ''
      document.updatedAt = Date.now()
      await this.updateDocumentStatus(store, document)
      if (!wasReady) {
        this.readyDocumentCount += 1
      }
      this.invalidateRetrievalSnapshot()
      const vectorResult = await this.indexDocumentVectorsBestEffort(
        store,
        document,
        generation,
        chunks
      )
      const indexMode = vectorResult.ready
        ? '语义向量与关键词混合索引已就绪'
        : `关键词索引已就绪；语义向量未完成：${vectorResult.message}`
      return new KnowledgeImportResult(
        true,
        `已重建 ${chunks.length} 个知识片段，${indexMode}`,
        document,
        false,
        vectorResult.ready,
        vectorResult.message
      )
    } catch (error) {
      if (!wasReady) {
        await this.deleteDocumentChunks(store, document.id)
      }
      await this.upsertVectorIndexStateQuietly(
        store,
        document.id,
        generation,
        KnowledgeVectorIndexStatus.FAILED,
        getKnowledgeEmbeddingService().modelKey(),
        0,
        0,
        this.safeVectorErrorMessage(error)
      )
      document.status = wasReady ? KnowledgeDocumentStatus.READY : KnowledgeDocumentStatus.FAILED
      document.chunkCount = wasReady ? previousChunkCount : 0
      document.errorMessage = wasReady
        ? `重建失败，继续使用原索引：${this.safeErrorMessage(error)}`
        : this.safeErrorMessage(error)
      document.updatedAt = Date.now()
      await this.updateDocumentStatus(store, document)
      this.invalidateRetrievalSnapshot()
      return new KnowledgeImportResult(false, document.errorMessage, document)
    }
  }

  async deleteDocument(documentId: string): Promise<boolean> {
    const releaseLock = await this.acquireMutationLock()
    try {
      return await this.deleteDocumentLocked(documentId)
    } finally {
      releaseLock()
    }
  }

  private async deleteDocumentLocked(documentId: string): Promise<boolean> {
    const store = this.store
    if (store === null) {
      return false
    }
    const document = await this.findDocumentById(store, documentId)
    if (document === null) {
      return false
    }
    const wasReady = document.status === KnowledgeDocumentStatus.READY
    try {
      document.status = KnowledgeDocumentStatus.DELETING
      document.updatedAt = Date.now()
      await this.updateDocumentStatus(store, document)
      await this.enqueueVectorDeletion(store, document.id)
      const vectorDeleted = await this.tryDeleteVectorDocument(document.id)
      store.beginTransaction()
      try {
        await this.deleteDocumentChunks(store, document.id)
        if (vectorDeleted) {
          await store.executeSql(
            `DELETE FROM ${KNOWLEDGE_VECTOR_INDEX_STATE_TABLE} WHERE document_id = ?`,
            [document.id]
          )
          await store.executeSql(
            `DELETE FROM ${KNOWLEDGE_VECTOR_DELETE_QUEUE_TABLE} WHERE document_id = ?`,
            [document.id]
          )
        }
        await store.executeSql(
          `DELETE FROM ${KNOWLEDGE_DOCUMENTS_TABLE} WHERE id = ?`,
          [document.id]
        )
        store.commit()
        this.invalidateRetrievalSnapshot()
      } catch (error) {
        store.rollBack()
        throw new Error(this.safeErrorMessage(error))
      }
      if (wasReady) {
        this.readyDocumentCount = Math.max(0, this.readyDocumentCount - 1)
      }
      try {
        if (fileIo.accessSync(document.filePath)) {
          fileIo.unlinkSync(document.filePath)
        }
      } catch (error) {
        console.warn(
          'KnowledgeDocumentService',
          `Document metadata deleted but file cleanup failed: ${this.safeErrorMessage(error)}`
        )
      }
      return true
    } catch (error) {
      console.error('KnowledgeDocumentService', `Delete failed: ${JSON.stringify(error)}`)
      document.status = wasReady ? KnowledgeDocumentStatus.READY : KnowledgeDocumentStatus.FAILED
      document.errorMessage = '删除失败，请重试'
      document.updatedAt = Date.now()
      await this.updateDocumentStatus(store, document)
      await this.cancelVectorDeletion(store, document.id)
      return false
    }
  }

  private async extractDocumentText(document: KnowledgeDocument, extension: string): Promise<string> {
    if (extension === '.txt' || extension === '.md' || extension === '.markdown') {
      const bytes = this.readFilePathBytes(document.filePath)
      const decoder = util.TextDecoder.create('utf-8')
      return this.normalizeText(decoder.decodeToString(bytes, { stream: false }))
        .substring(0, MAX_DOCUMENT_TEXT_CHARACTERS)
    }

    if (extension === '.pdf') {
      const attachment = new MessageAttachment(
        document.id,
        AttachmentType.FILE,
        document.originalName,
        document.filePath,
        document.mimeType,
        document.size
      )
      const registered = new RegisteredDocumentAttachment('knowledge', attachment)
      const textResult = await getPdfTextExtractionService().extractAttachment(
        registered,
        MAX_DOCUMENT_TEXT_CHARACTERS,
        false
      )
      let result = textResult
      if (!textResult.ok ||
        this.countMeaningfulCharacters(textResult.text) < MIN_PDF_TEXT_CHARACTERS_BEFORE_OCR) {
        const ocrResult = await getPdfTextExtractionService().extractAttachment(
          registered,
          MAX_DOCUMENT_TEXT_CHARACTERS,
          true
        )
        if (ocrResult.ok &&
          this.countMeaningfulCharacters(ocrResult.text) > this.countMeaningfulCharacters(textResult.text)) {
          result = ocrResult
        }
      }
      if (!result.ok || result.text.trim() === '') {
        throw new Error(result.message === '' ? '未能从 PDF 提取文字' : result.message)
      }
      return this.normalizeText(result.text)
    }
    if (this.isImageExtension(extension)) {
      const attachment = new MessageAttachment(
        document.id,
        AttachmentType.IMAGE,
        document.originalName,
        document.filePath,
        document.mimeType,
        document.size
      )
      const registered = new RegisteredDocumentAttachment('knowledge', attachment)
      const result = await getImageTextRecognitionService().recognizeAttachment(
        registered,
        MAX_DOCUMENT_TEXT_CHARACTERS
      )
      if (!result.ok || result.text.trim() === '') {
        throw new Error(result.message === '' ? '未能从图片识别文字' : result.message)
      }
      return this.normalizeText(result.text)
    }
    throw new Error('文件格式不受支持')
  }

  private countMeaningfulCharacters(value: string): number {
    return value.replace(/\s/g, '').length
  }

  private async buildChunks(
    document: KnowledgeDocument,
    text: string,
    generation: string
  ): Promise<KnowledgeChunk[]> {
    const normalized = this.normalizeText(text)
    if (normalized === '') {
      return []
    }
    const result = await this.semanticChunker.chunk(
      new KnowledgeSemanticChunkRequest(document.id, document.title, normalized),
      getKnowledgeEmbeddingService()
    )
    const chunks: KnowledgeChunk[] = []
    for (let index = 0; index < result.chunks.length; index++) {
      const semanticChunk: KnowledgeSemanticChunk = result.chunks[index]
      const title = semanticChunk.headingPath === ''
        ? document.title
        : `${document.title} · ${semanticChunk.headingPath}`
      chunks.push(new KnowledgeChunk(
        `${document.id}_${generation}_chunk_${index + 1}`,
        document.id,
        title,
        semanticChunk.locator,
        semanticChunk.content,
        semanticChunk.embeddingText,
        index,
        semanticChunk.parentId,
        semanticChunk.headingPath,
        semanticChunk.pageStart,
        semanticChunk.pageEnd,
        semanticChunk.continuesBefore,
        semanticChunk.continuesAfter,
        semanticChunk.rawEmbedding
      ))
      if (this.shouldYieldChunkWork(index, result.chunks.length)) {
        await this.yieldToUiFrame()
      }
    }
    console.info(
      'KnowledgeDocumentService',
      `Chunked document: chunks=${chunks.length}, units=${result.structuralUnitCount}, ` +
      `semantic=${result.semanticEmbeddingUsed}, semanticBreaks=${result.semanticBreakCount}, ` +
      `embeddingFallback=${result.semanticEmbeddingFailed}`
    )
    return chunks
  }

  private async replaceDocumentChunks(
    store: relationalStore.RdbStore,
    documentId: string,
    chunks: KnowledgeChunk[]
  ): Promise<void> {
    store.beginTransaction()
    try {
      await this.deleteDocumentChunks(store, documentId)
      for (let i = 0; i < chunks.length; i++) {
        const chunk = chunks[i]
        await store.executeSql(
          `INSERT INTO ${KNOWLEDGE_CHUNKS_FTS_TABLE}
            (chunk_id, document_id, title, locator, content)
           VALUES (?, ?, ?, ?, ?)`,
          [chunk.id, chunk.documentId, chunk.title, chunk.locator, chunk.content]
        )
        await store.executeSql(
          `INSERT INTO ${KNOWLEDGE_CHUNK_METADATA_TABLE}
            (chunk_id, document_id, chunk_index, parent_id, heading_path,
             page_start, page_end, continues_before, continues_after)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            chunk.id,
            chunk.documentId,
            chunk.chunkIndex,
            chunk.parentId,
            chunk.headingPath,
            chunk.pageStart,
            chunk.pageEnd,
            chunk.continuesBefore ? 1 : 0,
            chunk.continuesAfter ? 1 : 0
          ]
        )
        if (this.shouldYieldChunkWork(i, chunks.length)) {
          await this.yieldToUiFrame()
        }
      }
      store.commit()
    } catch (error) {
      store.rollBack()
      throw new Error(this.safeErrorMessage(error))
    }
  }

  private async countStoredDocumentChunks(
    store: relationalStore.RdbStore,
    documentId: string
  ): Promise<number> {
    const resultSet = await store.querySql(
      `SELECT COUNT(*) AS stored_chunk_count
       FROM ${KNOWLEDGE_CHUNKS_FTS_TABLE}
       WHERE document_id = ?`,
      [documentId]
    )
    try {
      if (!resultSet.goToNextRow()) {
        return 0
      }
      return resultSet.getLong(resultSet.getColumnIndex('stored_chunk_count'))
    } finally {
      resultSet.close()
    }
  }

  private async countStoredDocumentChunkMetadata(
    store: relationalStore.RdbStore,
    documentId: string
  ): Promise<number> {
    const resultSet = await store.querySql(
      `SELECT COUNT(*) AS stored_metadata_count
       FROM ${KNOWLEDGE_CHUNK_METADATA_TABLE}
       WHERE document_id = ?`,
      [documentId]
    )
    try {
      if (!resultSet.goToNextRow()) {
        return 0
      }
      return resultSet.getLong(resultSet.getColumnIndex('stored_metadata_count'))
    } finally {
      resultSet.close()
    }
  }

  private async verifyStoredDocumentChunks(
    store: relationalStore.RdbStore,
    documentId: string,
    expectedCount: number
  ): Promise<void> {
    const storedCount = await this.countStoredDocumentChunks(store, documentId)
    const storedMetadataCount =
      await this.countStoredDocumentChunkMetadata(store, documentId)
    if (expectedCount <= 0 ||
      storedCount !== expectedCount ||
      storedMetadataCount !== expectedCount) {
      throw new Error(
        `知识片段写入不完整：期望 ${expectedCount} 条，` +
        `正文 ${storedCount} 条，元数据 ${storedMetadataCount} 条`
      )
    }
  }

  private async deleteDocumentChunks(store: relationalStore.RdbStore, documentId: string): Promise<void> {
    await store.executeSql(
      `DELETE FROM ${KNOWLEDGE_CHUNK_METADATA_TABLE} WHERE document_id = ?`,
      [documentId]
    )
    await store.executeSql(
      `DELETE FROM ${KNOWLEDGE_CHUNKS_FTS_TABLE} WHERE document_id = ?`,
      [documentId]
    )
  }

  private invalidateRetrievalSnapshot(): void {
    this.retrievalAdapter.invalidateDataSnapshot()
  }

  private async insertDocument(store: relationalStore.RdbStore, document: KnowledgeDocument): Promise<void> {
    await store.executeSql(
      `INSERT INTO ${KNOWLEDGE_DOCUMENTS_TABLE}
        (id, title, original_name, file_path, mime_type, size, content_hash, status,
         chunk_count, error_message, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        document.id,
        document.title,
        document.originalName,
        document.filePath,
        document.mimeType,
        document.size,
        document.contentHash,
        document.status,
        document.chunkCount,
        document.errorMessage,
        document.createdAt,
        document.updatedAt
      ]
    )
  }

  private async updateDocumentStatus(
    store: relationalStore.RdbStore,
    document: KnowledgeDocument
  ): Promise<void> {
    await store.executeSql(
      `UPDATE ${KNOWLEDGE_DOCUMENTS_TABLE}
       SET status = ?, chunk_count = ?, error_message = ?, updated_at = ?
       WHERE id = ?`,
      [
        document.status,
        document.chunkCount,
        document.errorMessage,
        document.updatedAt,
        document.id
      ]
    )
  }

  private async countReadyDocuments(store: relationalStore.RdbStore): Promise<number> {
    const resultSet = await store.querySql(
      `SELECT COUNT(*) AS ready_count FROM ${KNOWLEDGE_DOCUMENTS_TABLE} WHERE status = ?`,
      [KnowledgeDocumentStatus.READY]
    )
    try {
      if (resultSet.goToNextRow()) {
        return resultSet.getLong(resultSet.getColumnIndex('ready_count'))
      }
      return 0
    } finally {
      resultSet.close()
    }
  }

  private async findDocumentByHash(
    store: relationalStore.RdbStore,
    contentHash: string
  ): Promise<KnowledgeDocument | null> {
    return await this.findSingleDocument(
      store,
      `SELECT id, title, original_name, file_path, mime_type, size, content_hash, status,
        chunk_count, error_message, created_at, updated_at
       FROM ${KNOWLEDGE_DOCUMENTS_TABLE} WHERE content_hash = ? LIMIT 1`,
      [contentHash]
    )
  }

  private async findDocumentById(
    store: relationalStore.RdbStore,
    documentId: string
  ): Promise<KnowledgeDocument | null> {
    return await this.findSingleDocument(
      store,
      `SELECT id, title, original_name, file_path, mime_type, size, content_hash, status,
        chunk_count, error_message, created_at, updated_at
       FROM ${KNOWLEDGE_DOCUMENTS_TABLE} WHERE id = ? LIMIT 1`,
      [documentId]
    )
  }

  private async findSingleDocument(
    store: relationalStore.RdbStore,
    sql: string,
    bindArgs: relationalStore.ValueType[]
  ): Promise<KnowledgeDocument | null> {
    const resultSet = await store.querySql(sql, bindArgs)
    try {
      if (!resultSet.goToNextRow()) {
        return null
      }
      return this.readDocument(resultSet)
    } finally {
      resultSet.close()
    }
  }

  private readDocument(resultSet: relationalStore.ResultSet): KnowledgeDocument {
    const document = new KnowledgeDocument(
      resultSet.getString(resultSet.getColumnIndex('id')),
      resultSet.getString(resultSet.getColumnIndex('title')),
      resultSet.getString(resultSet.getColumnIndex('original_name')),
      resultSet.getString(resultSet.getColumnIndex('file_path')),
      resultSet.getString(resultSet.getColumnIndex('mime_type')),
      resultSet.getLong(resultSet.getColumnIndex('size'))
    )
    document.contentHash = resultSet.getString(resultSet.getColumnIndex('content_hash'))
    document.status = resultSet.getString(resultSet.getColumnIndex('status'))
    document.chunkCount = resultSet.getLong(resultSet.getColumnIndex('chunk_count'))
    document.errorMessage = resultSet.getString(resultSet.getColumnIndex('error_message'))
    document.createdAt = resultSet.getLong(resultSet.getColumnIndex('created_at'))
    document.updatedAt = resultSet.getLong(resultSet.getColumnIndex('updated_at'))
    return document
  }

  private ensureKnowledgeFilesDirectory(context: Context): void {
    const knowledgeDirectory = `${context.filesDir}/knowledge`
    const filesDirectory = `${context.filesDir}/${KNOWLEDGE_FILES_DIRECTORY}`
    try {
      fileIo.mkdirSync(knowledgeDirectory)
    } catch (_error) {
    }
    try {
      fileIo.mkdirSync(filesDirectory)
    } catch (_error) {
    }
  }

  private readFilePathBytes(path: string): Uint8Array {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
    try {
      const stat = fileIo.statSync(file.fd)
      return this.readFileBytes(file.fd, stat.size)
    } finally {
      fileIo.closeSync(file)
    }
  }

  private readFileBytes(fileDescriptor: number, size: number): Uint8Array {
    const bytes = new Uint8Array(size)
    let offset = 0
    while (offset < size) {
      const chunkLength = Math.min(FILE_IO_CHUNK_BYTES, size - offset)
      const chunkBuffer = new ArrayBuffer(chunkLength)
      const readBytes = fileIo.readSync(fileDescriptor, chunkBuffer)
      if (readBytes <= 0) {
        throw new Error(`读取文件不完整：期望 ${size} 字节，实际 ${offset} 字节`)
      }
      bytes.set(new Uint8Array(chunkBuffer, 0, readBytes), offset)
      offset += readBytes
    }
    return bytes
  }

  private writeFileBytes(path: string, bytes: Uint8Array): void {
    const file = fileIo.openSync(
      path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC
    )
    try {
      let offset = 0
      while (offset < bytes.byteLength) {
        const end = Math.min(bytes.byteLength, offset + FILE_IO_CHUNK_BYTES)
        const chunkBuffer = bytes.buffer.slice(
          bytes.byteOffset + offset,
          bytes.byteOffset + end
        )
        const writtenBytes = fileIo.writeSync(file.fd, chunkBuffer)
        if (writtenBytes <= 0) {
          throw new Error(`写入文件不完整：期望 ${bytes.byteLength} 字节，实际 ${offset} 字节`)
        }
        offset += writtenBytes
      }
    } finally {
      fileIo.closeSync(file)
    }
  }

  private async sha256Hex(bytes: Uint8Array): Promise<string> {
    try {
      const md = cryptoFramework.createMd('SHA256')
      await md.update({ data: bytes })
      const digest = await md.digest()
      let hex = ''
      for (let i = 0; i < digest.data.length; i++) {
        hex += digest.data[i].toString(16).padStart(2, '0')
      }
      return hex
    } catch (_error) {
      // 部分设备可能缺少 CryptoArchitectureKit 摘要能力。知识库导入不能因此整体失败；
      // 使用两个独立 32 位滚动哈希和文件长度作为稳定的本地去重标识。
      let primaryHash = 2166136261
      let secondaryHash = 0
      for (let index = 0; index < bytes.length; index++) {
        primaryHash = Math.imul(primaryHash ^ bytes[index], 16777619) >>> 0
        secondaryHash = (Math.imul(secondaryHash, 131) + bytes[index]) >>> 0
      }
      return `fallback-${bytes.length.toString(16)}-` +
        `${primaryHash.toString(16).padStart(8, '0')}-` +
        secondaryHash.toString(16).padStart(8, '0')
    }
  }

  private normalizeText(value: string): string {
    return value
      .replace(/\r\n?/g, '\n')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim()
  }

  private normalizeFileName(value: string): string {
    const trimmed = value.trim()
    if (trimmed === '') {
      return 'knowledge-file'
    }
    return trimmed.replace(/[\\/:*?"<>|]/g, '_')
  }

  private getSupportedExtension(fileName: string): string {
    const lower = fileName.toLowerCase()
    const extensions: string[] = [
      '.markdown',
      '.jpeg',
      '.webp',
      '.pdf',
      '.txt',
      '.jpg',
      '.png',
      '.bmp',
      '.md'
    ]
    for (let i = 0; i < extensions.length; i++) {
      if (lower.endsWith(extensions[i])) {
        return extensions[i]
      }
    }
    return ''
  }

  private isImageExtension(extension: string): boolean {
    return extension === '.jpg' || extension === '.jpeg' || extension === '.png' ||
      extension === '.webp' || extension === '.bmp'
  }

  private titleFromFileName(fileName: string): string {
    const extension = this.getSupportedExtension(fileName)
    if (extension !== '' && fileName.length > extension.length) {
      return fileName.substring(0, fileName.length - extension.length)
    }
    return fileName
  }

  private mimeTypeForExtension(extension: string): string {
    if (extension === '.pdf') {
      return 'application/pdf'
    }
    if (extension === '.md' || extension === '.markdown') {
      return 'text/markdown'
    }
    if (extension === '.jpg' || extension === '.jpeg') {
      return 'image/jpeg'
    }
    if (extension === '.png') {
      return 'image/png'
    }
    if (extension === '.webp') {
      return 'image/webp'
    }
    if (extension === '.bmp') {
      return 'image/bmp'
    }
    return 'text/plain'
  }

  private generateId(prefix: string): string {
    const random = Math.floor(Math.random() * 0xFFFFFF).toString(16).padStart(6, '0')
    return `${prefix}_${Date.now()}_${random}`
  }

  private safeErrorMessage(error: Object): string {
    if (error instanceof Error && error.message.trim() !== '') {
      return error.message
    }
    const serialized = JSON.stringify(error)
    return serialized === '' || serialized === '{}' ? '知识库文件处理失败' : serialized
  }
}

export function getKnowledgeDocumentService(): KnowledgeDocumentService {
  return KnowledgeDocumentService.getInstance()
}
