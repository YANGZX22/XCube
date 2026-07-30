import { Context } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { KNOWLEDGE_VECTOR_MAX_DIMENSION } from './KnowledgeVectorProjection'

export const KNOWLEDGE_VECTOR_DATABASE_NAME: string = 'chatcube_knowledge_vectors.db'
export const KNOWLEDGE_VECTOR_TABLE_NAME: string = 'knowledge_chunk_vectors'
export const KNOWLEDGE_VECTOR_METADATA_TABLE_NAME: string = 'knowledge_vector_metadata'
export const KNOWLEDGE_VECTOR_CHUNK_ID_COLUMN: string = 'chunk_id'
export const KNOWLEDGE_VECTOR_DOCUMENT_ID_COLUMN: string = 'document_id'
export const KNOWLEDGE_VECTOR_GENERATION_COLUMN: string = 'generation'
export const KNOWLEDGE_VECTOR_TITLE_COLUMN: string = 'title'
export const KNOWLEDGE_VECTOR_LOCATOR_COLUMN: string = 'locator'
export const KNOWLEDGE_VECTOR_CONTENT_COLUMN: string = 'content'
export const KNOWLEDGE_VECTOR_EMBEDDING_COLUMN: string = 'embedding'

const KNOWLEDGE_VECTOR_EMBEDDING_INDEX: string =
  'knowledge_chunk_vectors_embedding_cosine_idx'
const KNOWLEDGE_VECTOR_SCHEMA_VERSION: number = 5
const METADATA_ROW_ID: number = 1
const MIN_VECTOR_DIMENSION: number = 1
const MAX_MODEL_KEY_CHARACTERS: number = 512
const MAX_DOCUMENT_ID_CHARACTERS: number = 512
const MAX_GENERATION_CHARACTERS: number = 512
const MAX_CHUNK_ID_CHARACTERS: number = 1024
const MAX_TITLE_CHARACTERS: number = 4096
const MAX_LOCATOR_CHARACTERS: number = 4096
const MAX_CONTENT_CHARACTERS: number = 64 * 1024

export enum KnowledgeVectorStoreStatus {
  CLOSED = 'closed',
  READY = 'ready',
  UNSUPPORTED = 'unsupported',
  REBUILD_REQUIRED = 'rebuild_required',
  INVALID_CONFIGURATION = 'invalid_configuration',
  ERROR = 'error'
}

export class KnowledgeVectorStoreMetadata {
  schemaVersion: number = 0
  modelKey: string = ''
  dimension: number = 0
  updatedAt: number = 0

  constructor(
    schemaVersion: number = 0,
    modelKey: string = '',
    dimension: number = 0,
    updatedAt: number = 0
  ) {
    this.schemaVersion = schemaVersion
    this.modelKey = modelKey
    this.dimension = dimension
    this.updatedAt = updatedAt
  }

  copy(): KnowledgeVectorStoreMetadata {
    return new KnowledgeVectorStoreMetadata(
      this.schemaVersion,
      this.modelKey,
      this.dimension,
      this.updatedAt
    )
  }
}

export class KnowledgeVectorStoreOpenResult {
  status: KnowledgeVectorStoreStatus = KnowledgeVectorStoreStatus.CLOSED
  message: string = ''
  metadata: KnowledgeVectorStoreMetadata | null = null

  constructor(
    status: KnowledgeVectorStoreStatus,
    message: string = '',
    metadata: KnowledgeVectorStoreMetadata | null = null
  ) {
    this.status = status
    this.message = message
    this.metadata = metadata === null ? null : metadata.copy()
  }

  isReady(): boolean {
    return this.status === KnowledgeVectorStoreStatus.READY
  }

  requiresRebuild(): boolean {
    return this.status === KnowledgeVectorStoreStatus.REBUILD_REQUIRED
  }
}

/**
 * 待写入 sidecar 的向量记录。文本列与 FTS 使用相同名称，使 DAK 的倒排与向量
 * channel 可以共享 filters、responseColumns 及 chunk_id 主键。
 */
export class KnowledgeVectorRecord {
  chunkId: string = ''
  documentId: string = ''
  generation: string = ''
  title: string = ''
  locator: string = ''
  content: string = ''
  embedding: Float32Array = new Float32Array(0)

  constructor(
    chunkId: string = '',
    documentId: string = '',
    generation: string = '',
    title: string = '',
    locator: string = '',
    content: string = '',
    embedding: Float32Array = new Float32Array(0)
  ) {
    this.chunkId = chunkId
    this.documentId = documentId
    this.generation = generation
    this.title = title
    this.locator = locator
    this.content = content
    this.embedding = embedding
  }
}

/**
 * 知识库的 ArkData 向量 sidecar。
 *
 * 本类只会打开固定名称的 vector store，不会打开、修改或删除普通知识库数据库。
 * 表结构首次由经过严格整数范围校验的 embedding 维度建立；模型或维度发生变化时，
 * 调用方会收到 REBUILD_REQUIRED，旧 sidecar 不会被自动破坏。
 */
export class KnowledgeVectorStore {
  private static instance: KnowledgeVectorStore | null = null
  private store: relationalStore.RdbStore | null = null
  private metadata: KnowledgeVectorStoreMetadata | null = null
  private status: KnowledgeVectorStoreStatus = KnowledgeVectorStoreStatus.CLOSED
  private statusMessage: string = ''
  private mutationTail: Promise<void> = Promise.resolve()

  static getInstance(): KnowledgeVectorStore {
    if (KnowledgeVectorStore.instance === null) {
      KnowledgeVectorStore.instance = new KnowledgeVectorStore()
    }
    return KnowledgeVectorStore.instance
  }

  isVectorSupported(): boolean {
    return relationalStore.isVectorSupported()
  }

  isReady(): boolean {
    return this.status === KnowledgeVectorStoreStatus.READY &&
      this.store !== null &&
      this.metadata !== null
  }

  getStatus(): KnowledgeVectorStoreStatus {
    return this.status
  }

  getStatusMessage(): string {
    return this.statusMessage
  }

  getMetadata(): KnowledgeVectorStoreMetadata | null {
    return this.metadata === null ? null : this.metadata.copy()
  }

  /**
   * 可直接用于 Data Augmentation Kit VECTOR_DATABASE channel 的 dbConfig。
   * 调用方仍应先确认 isReady() 为 true。
   */
  getStoreConfig(): relationalStore.StoreConfig {
    const config: relationalStore.StoreConfig = {
      name: KNOWLEDGE_VECTOR_DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S3,
      vector: true
    }
    return config
  }

  getVectorTableName(): string {
    return KNOWLEDGE_VECTOR_TABLE_NAME
  }

  getEmbeddingColumnName(): string {
    return KNOWLEDGE_VECTOR_EMBEDDING_COLUMN
  }

  async initialize(
    context: Context,
    modelKey: string,
    dimension: number
  ): Promise<KnowledgeVectorStoreOpenResult> {
    const normalizedModelKey = this.normalizeModelKey(modelKey)
    const normalizedDimension = this.normalizeDimension(dimension)
    if (normalizedModelKey === null || normalizedDimension === null) {
      return new KnowledgeVectorStoreOpenResult(
        KnowledgeVectorStoreStatus.INVALID_CONFIGURATION,
        '向量模型标识或维度无效'
      )
    }

    const releaseLock = await this.acquireMutationLock()
    try {
      return await this.initializeLocked(context, normalizedModelKey, normalizedDimension)
    } finally {
      releaseLock()
    }
  }

  /**
   * 显式重建固定名称的纯派生 sidecar。此方法不会接收数据库名称，因此不可能
   * 删除 chatcube_knowledge.db 或其他普通 RDB。
   */
  async rebuild(
    context: Context,
    modelKey: string,
    dimension: number
  ): Promise<KnowledgeVectorStoreOpenResult> {
    const normalizedModelKey = this.normalizeModelKey(modelKey)
    const normalizedDimension = this.normalizeDimension(dimension)
    if (normalizedModelKey === null || normalizedDimension === null) {
      return new KnowledgeVectorStoreOpenResult(
        KnowledgeVectorStoreStatus.INVALID_CONFIGURATION,
        '向量模型标识或维度无效'
      )
    }

    const releaseLock = await this.acquireMutationLock()
    try {
      if (!relationalStore.isVectorSupported()) {
        await this.closeCurrentStore()
        return this.setOpenState(
          KnowledgeVectorStoreStatus.UNSUPPORTED,
          '当前设备不支持 ArkData 向量数据库'
        )
      }
      await this.closeCurrentStore()
      try {
        await relationalStore.deleteRdbStore(context, this.getStoreConfig())
      } catch (error) {
        return this.setOpenState(
          KnowledgeVectorStoreStatus.ERROR,
          `向量 sidecar 重建前清理失败：${this.safeErrorMessage(error)}`
        )
      }
      return await this.initializeLocked(context, normalizedModelKey, normalizedDimension)
    } finally {
      releaseLock()
    }
  }

  /**
   * 删除固定名称的纯派生 sidecar，用于没有可用维度元数据时完成隐私清理。
   */
  async purge(context: Context): Promise<boolean> {
    const releaseLock = await this.acquireMutationLock()
    try {
      await this.closeCurrentStore()
      try {
        await relationalStore.deleteRdbStore(context, this.getStoreConfig())
        this.status = KnowledgeVectorStoreStatus.CLOSED
        this.statusMessage = ''
        return true
      } catch (_error) {
        this.status = KnowledgeVectorStoreStatus.ERROR
        this.statusMessage = '向量 sidecar 清理失败'
        return false
      }
    } finally {
      releaseLock()
    }
  }

  /**
   * 在一个 ArkData 事务中删除指定文档的全部旧 generation，再写入唯一新 generation。
   * 空 records 表示原子清空该文档。
   */
  async replaceDocumentGeneration(
    documentId: string,
    generation: string,
    records: KnowledgeVectorRecord[]
  ): Promise<number> {
    const releaseLock = await this.acquireMutationLock()
    try {
      const store = this.requireReadyStore()
      const metadata = this.requireMetadata()
      const normalizedDocumentId = this.requireScopedValue(
        documentId,
        MAX_DOCUMENT_ID_CHARACTERS,
        '文档 ID'
      )
      const normalizedGeneration = this.requireScopedValue(
        generation,
        MAX_GENERATION_CHARACTERS,
        '向量 generation'
      )
      this.validateRecords(
        records,
        metadata.dimension,
        normalizedDocumentId,
        normalizedGeneration
      )

      const transactionId = await store.beginTrans()
      try {
        await store.execute(
          `DELETE FROM ${KNOWLEDGE_VECTOR_TABLE_NAME}
           WHERE ${KNOWLEDGE_VECTOR_DOCUMENT_ID_COLUMN} = ?`,
          transactionId,
          [normalizedDocumentId]
        )
        for (let index = 0; index < records.length; index++) {
          const record = records[index]
          await store.execute(
            `INSERT INTO ${KNOWLEDGE_VECTOR_TABLE_NAME}
              (${KNOWLEDGE_VECTOR_CHUNK_ID_COLUMN},
               ${KNOWLEDGE_VECTOR_DOCUMENT_ID_COLUMN},
               ${KNOWLEDGE_VECTOR_GENERATION_COLUMN},
               ${KNOWLEDGE_VECTOR_TITLE_COLUMN},
               ${KNOWLEDGE_VECTOR_LOCATOR_COLUMN},
               ${KNOWLEDGE_VECTOR_CONTENT_COLUMN},
               ${KNOWLEDGE_VECTOR_EMBEDDING_COLUMN})
             VALUES (?, ?, ?, ?, ?, ?, ?)`,
            transactionId,
            [
              record.chunkId.trim(),
              normalizedDocumentId,
              normalizedGeneration,
              record.title.trim(),
              record.locator.trim(),
              record.content.trim(),
              record.embedding
            ]
          )
        }
        await store.commit(transactionId)
        return records.length
      } catch (error) {
        await this.rollbackQuietly(store, transactionId)
        throw new Error(`知识库向量原子替换失败：${this.safeErrorMessage(error)}`)
      }
    } finally {
      releaseLock()
    }
  }

  async deleteDocumentGeneration(documentId: string, generation: string): Promise<number> {
    const normalizedDocumentId = this.requireScopedValue(
      documentId,
      MAX_DOCUMENT_ID_CHARACTERS,
      '文档 ID'
    )
    const normalizedGeneration = this.requireScopedValue(
      generation,
      MAX_GENERATION_CHARACTERS,
      '向量 generation'
    )
    return await this.deleteWhere(
      `DELETE FROM ${KNOWLEDGE_VECTOR_TABLE_NAME}
       WHERE ${KNOWLEDGE_VECTOR_DOCUMENT_ID_COLUMN} = ?
         AND ${KNOWLEDGE_VECTOR_GENERATION_COLUMN} = ?`,
      [normalizedDocumentId, normalizedGeneration]
    )
  }

  /**
   * 删除一个文档在 sidecar 中的全部 generation。
   */
  async deleteDocument(documentId: string): Promise<number> {
    const normalizedDocumentId = this.requireScopedValue(
      documentId,
      MAX_DOCUMENT_ID_CHARACTERS,
      '文档 ID'
    )
    return await this.deleteWhere(
      `DELETE FROM ${KNOWLEDGE_VECTOR_TABLE_NAME}
       WHERE ${KNOWLEDGE_VECTOR_DOCUMENT_ID_COLUMN} = ?`,
      [normalizedDocumentId]
    )
  }

  async close(): Promise<void> {
    const releaseLock = await this.acquireMutationLock()
    try {
      const store = this.store
      this.store = null
      this.metadata = null
      this.status = KnowledgeVectorStoreStatus.CLOSED
      this.statusMessage = ''
      if (store !== null) {
        await store.close()
      }
    } finally {
      releaseLock()
    }
  }

  private async initializeLocked(
    context: Context,
    modelKey: string,
    dimension: number
  ): Promise<KnowledgeVectorStoreOpenResult> {
    if (!relationalStore.isVectorSupported()) {
      await this.closeCurrentStore()
      return this.setOpenState(
        KnowledgeVectorStoreStatus.UNSUPPORTED,
        '当前设备不支持 ArkData 向量数据库'
      )
    }

    if (this.isReady()) {
      const currentMetadata = this.requireMetadata()
      if (this.metadataMatches(currentMetadata, modelKey, dimension)) {
        return this.setOpenState(
          KnowledgeVectorStoreStatus.READY,
          '',
          currentMetadata
        )
      }
      await this.closeCurrentStore()
      return this.setOpenState(
        KnowledgeVectorStoreStatus.REBUILD_REQUIRED,
        '现有向量 sidecar 的模型或维度不匹配，需要重建',
        currentMetadata
      )
    }

    await this.closeCurrentStore()
    let openedStore: relationalStore.RdbStore | null = null
    try {
      openedStore = await relationalStore.getRdbStore(context, this.getStoreConfig())
      await openedStore.execute(this.buildCreateMetadataTableSql(), 0)
      const storedMetadata = await this.readMetadata(openedStore)

      if (storedMetadata === null) {
        const vectorTableExists = await this.tableExists(
          openedStore,
          KNOWLEDGE_VECTOR_TABLE_NAME
        )
        if (vectorTableExists) {
          await openedStore.close()
          return this.setOpenState(
            KnowledgeVectorStoreStatus.REBUILD_REQUIRED,
            '现有向量 sidecar 缺少 schema 元数据，需要重建'
          )
        }
        const indexWarning = await this.createInitialSchema(openedStore, modelKey, dimension)
        const createdMetadata = new KnowledgeVectorStoreMetadata(
          KNOWLEDGE_VECTOR_SCHEMA_VERSION,
          modelKey,
          dimension,
          Date.now()
        )
        this.store = openedStore
        this.metadata = createdMetadata
        return this.setOpenState(
          KnowledgeVectorStoreStatus.READY,
          indexWarning,
          createdMetadata
        )
      }

      if (!this.metadataMatches(storedMetadata, modelKey, dimension)) {
        await openedStore.close()
        return this.setOpenState(
          KnowledgeVectorStoreStatus.REBUILD_REQUIRED,
          '现有向量 sidecar 的 schema、模型或维度不匹配，需要重建',
          storedMetadata
        )
      }

      const vectorTableExists = await this.tableExists(
        openedStore,
        KNOWLEDGE_VECTOR_TABLE_NAME
      )
      if (!vectorTableExists) {
        await openedStore.close()
        return this.setOpenState(
          KnowledgeVectorStoreStatus.REBUILD_REQUIRED,
          '现有向量 sidecar 表结构不完整，需要重建',
          storedMetadata
        )
      }

      const indexWarning = await this.ensureIndexes(openedStore)
      this.store = openedStore
      this.metadata = storedMetadata
      return this.setOpenState(
        KnowledgeVectorStoreStatus.READY,
        indexWarning,
        storedMetadata
      )
    } catch (error) {
      if (openedStore !== null) {
        try {
          await openedStore.close()
        } catch (_closeError) {
        }
      }
      this.store = null
      this.metadata = null
      return this.setOpenState(
        KnowledgeVectorStoreStatus.ERROR,
        `向量 sidecar 初始化失败：${this.safeErrorMessage(error)}`
      )
    }
  }

  private async createInitialSchema(
    store: relationalStore.RdbStore,
    modelKey: string,
    dimension: number
  ): Promise<string> {
    let stage: string = '创建向量数据表'
    try {
      // GaussPD 的官方向量建表示例使用 txId=0。部分真机虽然支持向量事务，
      // 但会拒绝在显式事务中执行 CREATE TABLE。
      await store.execute(this.buildCreateVectorTableSql(dimension), 0)
      stage = '写入向量 schema 元数据'
      await store.execute(
        `INSERT INTO ${KNOWLEDGE_VECTOR_METADATA_TABLE_NAME}
          (metadata_id, schema_version, model_key, dimension, updated_at)
         VALUES (?, ?, ?, ?, ?)`,
        0,
        [
          METADATA_ROW_ID,
          KNOWLEDGE_VECTOR_SCHEMA_VERSION,
          modelKey,
          dimension,
          Date.now()
        ]
      )
    } catch (error) {
      try {
        await store.execute(`DROP TABLE IF EXISTS ${KNOWLEDGE_VECTOR_TABLE_NAME}`, 0)
      } catch (_cleanupError) {
      }
      throw new Error(`${stage}失败：${this.safeErrorMessage(error)}`)
    }
    return await this.ensureEmbeddingIndexBestEffort(store)
  }

  private async ensureIndexes(store: relationalStore.RdbStore): Promise<string> {
    return await this.ensureEmbeddingIndexBestEffort(store)
  }

  private async ensureEmbeddingIndexBestEffort(store: relationalStore.RdbStore): Promise<string> {
    try {
      await store.execute(this.buildCreateEmbeddingIndexSql(), 0)
      return ''
    } catch (error) {
      const message = `GSDISKANN 索引未建立，将使用无索引向量检索：${this.safeErrorMessage(error)}`
      console.warn('KnowledgeVectorStore', message)
      return message
    }
  }

  private buildCreateMetadataTableSql(): string {
    return `CREATE TABLE IF NOT EXISTS ${KNOWLEDGE_VECTOR_METADATA_TABLE_NAME} (
      metadata_id INTEGER PRIMARY KEY,
      schema_version INTEGER NOT NULL,
      model_key TEXT NOT NULL,
      dimension INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )`
  }

  private buildCreateVectorTableSql(dimension: number): string {
    // dimension 已由 normalizeDimension 限定为纯正整数，不能注入 SQL。
    return `CREATE TABLE ${KNOWLEDGE_VECTOR_TABLE_NAME} (
      ${KNOWLEDGE_VECTOR_CHUNK_ID_COLUMN} TEXT PRIMARY KEY,
      ${KNOWLEDGE_VECTOR_DOCUMENT_ID_COLUMN} TEXT NOT NULL,
      ${KNOWLEDGE_VECTOR_GENERATION_COLUMN} TEXT NOT NULL,
      ${KNOWLEDGE_VECTOR_TITLE_COLUMN} TEXT NOT NULL,
      ${KNOWLEDGE_VECTOR_LOCATOR_COLUMN} TEXT NOT NULL,
      ${KNOWLEDGE_VECTOR_CONTENT_COLUMN} TEXT NOT NULL,
      ${KNOWLEDGE_VECTOR_EMBEDDING_COLUMN} FLOATVECTOR(${dimension})
    )`
  }

  private buildCreateEmbeddingIndexSql(): string {
    return `CREATE INDEX IF NOT EXISTS ${KNOWLEDGE_VECTOR_EMBEDDING_INDEX}
      ON ${KNOWLEDGE_VECTOR_TABLE_NAME}
      USING GSDISKANN(${KNOWLEDGE_VECTOR_EMBEDDING_COLUMN} COSINE)`
  }

  private async readMetadata(
    store: relationalStore.RdbStore
  ): Promise<KnowledgeVectorStoreMetadata | null> {
    const resultSet = await store.querySql(
      `SELECT schema_version, model_key, dimension, updated_at
       FROM ${KNOWLEDGE_VECTOR_METADATA_TABLE_NAME}
       WHERE metadata_id = ?
       LIMIT 1`,
      [METADATA_ROW_ID]
    )
    try {
      if (!resultSet.goToNextRow()) {
        return null
      }
      return new KnowledgeVectorStoreMetadata(
        resultSet.getLong(resultSet.getColumnIndex('schema_version')),
        resultSet.getString(resultSet.getColumnIndex('model_key')),
        resultSet.getLong(resultSet.getColumnIndex('dimension')),
        resultSet.getLong(resultSet.getColumnIndex('updated_at'))
      )
    } finally {
      resultSet.close()
    }
  }

  private async tableExists(store: relationalStore.RdbStore, tableName: string): Promise<boolean> {
    let resultSet: relationalStore.ResultSet | null = null
    try {
      resultSet = await store.querySql(`SELECT COUNT(*) AS row_count FROM ${tableName}`)
      return resultSet.goToNextRow()
    } catch (_error) {
      return false
    } finally {
      if (resultSet !== null) {
        resultSet.close()
      }
    }
  }

  private async deleteWhere(
    sql: string,
    bindArgs: relationalStore.ValueType[]
  ): Promise<number> {
    const releaseLock = await this.acquireMutationLock()
    try {
      const store = this.requireReadyStore()
      const transactionId = await store.beginTrans()
      try {
        const result = await store.execute(sql, transactionId, bindArgs)
        await store.commit(transactionId)
        return typeof result === 'number' && Number.isFinite(result)
          ? Math.max(0, Math.floor(result))
          : 0
      } catch (error) {
        await this.rollbackQuietly(store, transactionId)
        throw new Error(`知识库向量删除失败：${this.safeErrorMessage(error)}`)
      }
    } finally {
      releaseLock()
    }
  }

  private validateRecords(
    records: KnowledgeVectorRecord[],
    expectedDimension: number,
    expectedDocumentId: string,
    expectedGeneration: string
  ): void {
    if (!Array.isArray(records)) {
      throw new Error('知识库向量记录必须是数组')
    }
    const chunkIds: Set<string> = new Set()
    for (let index = 0; index < records.length; index++) {
      const record = records[index]
      if (record === null || record === undefined) {
        throw new Error('知识库向量记录不能为空')
      }
      const chunkId = this.requireScopedValue(
        record.chunkId,
        MAX_CHUNK_ID_CHARACTERS,
        '知识片段 ID'
      )
      const documentId = this.requireScopedValue(
        record.documentId,
        MAX_DOCUMENT_ID_CHARACTERS,
        '知识片段文档 ID'
      )
      const generation = this.requireScopedValue(
        record.generation,
        MAX_GENERATION_CHARACTERS,
        '知识片段 generation'
      )
      if (chunkIds.has(chunkId)) {
        throw new Error('同一批知识库向量包含重复片段 ID')
      }
      chunkIds.add(chunkId)
      if (documentId !== expectedDocumentId) {
        throw new Error('知识片段文档 ID 与原子替换范围不一致')
      }
      if (generation !== expectedGeneration) {
        throw new Error('知识片段 generation 与原子替换范围不一致')
      }
      this.requireTextValue(record.title, MAX_TITLE_CHARACTERS, '知识片段标题')
      this.requireTextValue(record.locator, MAX_LOCATOR_CHARACTERS, '知识片段定位')
      this.requireTextValue(record.content, MAX_CONTENT_CHARACTERS, '知识片段正文')

      const embedding = record.embedding
      if (!(embedding instanceof Float32Array) || embedding.length !== expectedDimension) {
        throw new Error(`知识片段向量维度必须为 ${expectedDimension}`)
      }
      for (let valueIndex = 0; valueIndex < embedding.length; valueIndex++) {
        if (!Number.isFinite(embedding[valueIndex])) {
          throw new Error('知识片段向量包含无效数值')
        }
      }
    }
  }

  private requireTextValue(value: string, maxCharacters: number, label: string): string {
    if (typeof value !== 'string') {
      throw new Error(`${label} 必须是字符串`)
    }
    const normalized = value.trim()
    if (normalized === '' || normalized.length > maxCharacters ||
      normalized.indexOf('\u0000') >= 0) {
      throw new Error(`${label} 无效`)
    }
    return normalized
  }

  private normalizeModelKey(modelKey: string): string | null {
    if (typeof modelKey !== 'string') {
      return null
    }
    const normalized = modelKey.trim()
    if (!this.isSafeScopedValue(normalized, MAX_MODEL_KEY_CHARACTERS)) {
      return null
    }
    return normalized
  }

  private normalizeDimension(dimension: number): number | null {
    if (typeof dimension !== 'number' ||
      !Number.isFinite(dimension) ||
      !Number.isInteger(dimension) ||
      dimension < MIN_VECTOR_DIMENSION ||
      dimension > KNOWLEDGE_VECTOR_MAX_DIMENSION) {
      return null
    }
    return dimension
  }

  private requireScopedValue(value: string, maxCharacters: number, label: string): string {
    if (typeof value !== 'string') {
      throw new Error(`${label} 必须是字符串`)
    }
    const normalized = value.trim()
    if (!this.isSafeScopedValue(normalized, maxCharacters)) {
      throw new Error(`${label} 无效`)
    }
    return normalized
  }

  private isSafeScopedValue(value: string, maxCharacters: number): boolean {
    if (value === '' || value.length > maxCharacters) {
      return false
    }
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index)
      if (code <= 0x1F || code === 0x7F) {
        return false
      }
    }
    return true
  }

  private metadataMatches(
    metadata: KnowledgeVectorStoreMetadata,
    modelKey: string,
    dimension: number
  ): boolean {
    return metadata.schemaVersion === KNOWLEDGE_VECTOR_SCHEMA_VERSION &&
      metadata.modelKey === modelKey &&
      metadata.dimension === dimension
  }

  private requireReadyStore(): relationalStore.RdbStore {
    if (!this.isReady() || this.store === null) {
      throw new Error('知识库向量 sidecar 尚未就绪')
    }
    return this.store
  }

  private requireMetadata(): KnowledgeVectorStoreMetadata {
    if (this.metadata === null) {
      throw new Error('知识库向量 schema 元数据不可用')
    }
    return this.metadata
  }

  private async rollbackQuietly(store: relationalStore.RdbStore, transactionId: number): Promise<void> {
    try {
      await store.rollback(transactionId)
    } catch (_rollbackError) {
    }
  }

  private async closeCurrentStore(): Promise<void> {
    const currentStore = this.store
    this.store = null
    this.metadata = null
    if (currentStore !== null) {
      try {
        await currentStore.close()
      } catch (_closeError) {
      }
    }
  }

  private setOpenState(
    status: KnowledgeVectorStoreStatus,
    message: string,
    metadata: KnowledgeVectorStoreMetadata | null = null
  ): KnowledgeVectorStoreOpenResult {
    this.status = status
    this.statusMessage = message
    this.metadata = metadata === null ? null : metadata.copy()
    return new KnowledgeVectorStoreOpenResult(status, message, metadata)
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

  private safeErrorMessage(error: Object): string {
    if (error instanceof Error && error.message.trim() !== '') {
      return error.message
    }
    const serialized = JSON.stringify(error)
    return serialized === '' || serialized === '{}' ? '未知错误' : serialized
  }
}

export function getKnowledgeVectorStore(): KnowledgeVectorStore {
  return KnowledgeVectorStore.getInstance()
}
