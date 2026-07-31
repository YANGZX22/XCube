import { KnowledgeEmbeddingProvider } from './KnowledgeEmbeddingService'

export const KNOWLEDGE_SEMANTIC_CHUNKER_VERSION: string = 'semantic-v3-structure-parent-child'

const DEFAULT_TARGET_CHARACTERS: number = 360
const DEFAULT_MAX_CHARACTERS: number = 480
const DEFAULT_MIN_CHARACTERS: number = 120
const DEFAULT_OVERLAP_UNIT_COUNT: number = 1
const DEFAULT_EMBEDDING_MAX_CHARACTERS: number = 512
const DEFAULT_SEMANTIC_DEVIATION_FACTOR: number = 0.75
const DEFAULT_SEMANTIC_MIN_THRESHOLD: number = 0.28
const DEFAULT_SEMANTIC_MAX_THRESHOLD: number = 0.82
const SEMANTIC_EMBEDDING_BATCH_SIZE: number = 16

const UNIT_KIND_HEADING: string = 'heading'
const UNIT_KIND_PARAGRAPH: string = 'paragraph'
const UNIT_KIND_LIST: string = 'list'
const UNIT_KIND_TABLE: string = 'table'
const UNIT_KIND_FAQ_QUESTION: string = 'faq-question'
const UNIT_KIND_FAQ_ANSWER: string = 'faq-answer'

export class KnowledgeSemanticChunkerOptions {
  targetCharacters: number
  maxCharacters: number
  minCharacters: number
  overlapUnitCount: number
  embeddingMaxCharacters: number
  semanticDeviationFactor: number
  semanticMinThreshold: number
  semanticMaxThreshold: number

  constructor(
    targetCharacters: number = DEFAULT_TARGET_CHARACTERS,
    maxCharacters: number = DEFAULT_MAX_CHARACTERS,
    minCharacters: number = DEFAULT_MIN_CHARACTERS,
    overlapUnitCount: number = DEFAULT_OVERLAP_UNIT_COUNT,
    embeddingMaxCharacters: number = DEFAULT_EMBEDDING_MAX_CHARACTERS,
    semanticDeviationFactor: number = DEFAULT_SEMANTIC_DEVIATION_FACTOR,
    semanticMinThreshold: number = DEFAULT_SEMANTIC_MIN_THRESHOLD,
    semanticMaxThreshold: number = DEFAULT_SEMANTIC_MAX_THRESHOLD
  ) {
    this.maxCharacters = Math.max(64, maxCharacters)
    this.targetCharacters = Math.max(32, Math.min(targetCharacters, this.maxCharacters))
    this.minCharacters = Math.max(16, Math.min(minCharacters, this.targetCharacters))
    this.overlapUnitCount = Math.max(0, Math.min(overlapUnitCount, 4))
    this.embeddingMaxCharacters = Math.max(64, embeddingMaxCharacters)
    this.semanticDeviationFactor = Math.max(0.1, Math.min(semanticDeviationFactor, 2.0))
    this.semanticMinThreshold = Math.max(-1.0, Math.min(semanticMinThreshold, 1.0))
    this.semanticMaxThreshold = Math.max(
      this.semanticMinThreshold,
      Math.min(semanticMaxThreshold, 1.0)
    )
  }
}

export class KnowledgeSemanticChunkRequest {
  documentId: string
  documentTitle: string
  text: string

  constructor(documentId: string, documentTitle: string, text: string) {
    this.documentId = documentId
    this.documentTitle = documentTitle
    this.text = text
  }
}

/**
 * 可直接落入关键词索引和向量 sidecar 的父子块结果。
 * rawEmbedding 保留供应商原始维度，投影由持久化层统一处理。
 */
export class KnowledgeSemanticChunk {
  id: string
  documentId: string
  documentTitle: string
  content: string
  embeddingText: string
  locator: string
  headingPath: string
  pageStart: number
  pageEnd: number
  chunkIndex: number
  continuesBefore: boolean
  continuesAfter: boolean
  parentId: string
  startOffset: number
  endOffset: number
  rawEmbedding: Float32Array | null

  constructor(
    id: string,
    documentId: string,
    documentTitle: string,
    content: string,
    embeddingText: string,
    locator: string,
    headingPath: string,
    pageStart: number,
    pageEnd: number,
    chunkIndex: number,
    continuesBefore: boolean,
    continuesAfter: boolean,
    parentId: string,
    startOffset: number,
    endOffset: number,
    rawEmbedding: Float32Array | null
  ) {
    this.id = id
    this.documentId = documentId
    this.documentTitle = documentTitle
    this.content = content
    this.embeddingText = embeddingText
    this.locator = locator
    this.headingPath = headingPath
    this.pageStart = pageStart
    this.pageEnd = pageEnd
    this.chunkIndex = chunkIndex
    this.continuesBefore = continuesBefore
    this.continuesAfter = continuesAfter
    this.parentId = parentId
    this.startOffset = startOffset
    this.endOffset = endOffset
    this.rawEmbedding = rawEmbedding
  }
}

export class KnowledgeSemanticChunkingResult {
  chunks: KnowledgeSemanticChunk[]
  semanticEmbeddingUsed: boolean
  semanticEmbeddingFailed: boolean
  semanticBreakCount: number
  structuralUnitCount: number

  constructor(
    chunks: KnowledgeSemanticChunk[] = [],
    semanticEmbeddingUsed: boolean = false,
    semanticEmbeddingFailed: boolean = false,
    semanticBreakCount: number = 0,
    structuralUnitCount: number = 0
  ) {
    this.chunks = chunks
    this.semanticEmbeddingUsed = semanticEmbeddingUsed
    this.semanticEmbeddingFailed = semanticEmbeddingFailed
    this.semanticBreakCount = semanticBreakCount
    this.structuralUnitCount = structuralUnitCount
  }
}

class KnowledgeSemanticUnit {
  content: string
  kind: string
  headingPath: string
  pageStart: number
  pageEnd: number
  parentId: string
  startOffset: number
  endOffset: number
  continuesBefore: boolean
  continuesAfter: boolean
  embeddingText: string
  rawEmbedding: Float32Array | null

  constructor(
    content: string,
    kind: string,
    headingPath: string,
    pageStart: number,
    pageEnd: number,
    parentId: string,
    startOffset: number,
    endOffset: number,
    continuesBefore: boolean = false,
    continuesAfter: boolean = false
  ) {
    this.content = content
    this.kind = kind
    this.headingPath = headingPath
    this.pageStart = pageStart
    this.pageEnd = pageEnd
    this.parentId = parentId
    this.startOffset = startOffset
    this.endOffset = endOffset
    this.continuesBefore = continuesBefore
    this.continuesAfter = continuesAfter
    this.embeddingText = ''
    this.rawEmbedding = null
  }
}

class KnowledgeSemanticUnitBuffer {
  lines: string[] = []
  kind: string = ''
  headingPath: string = ''
  page: number = 0
  parentId: string = ''
  startOffset: number = 0
  endOffset: number = 0

  isEmpty(): boolean {
    return this.lines.length === 0
  }

  reset(): void {
    this.lines = []
    this.kind = ''
    this.headingPath = ''
    this.page = 0
    this.parentId = ''
    this.startOffset = 0
    this.endOffset = 0
  }
}

class KnowledgeSemanticChunkDraft {
  units: KnowledgeSemanticUnit[] = []
  overlapUnitCount: number = 0

  contentLength(): number {
    let length = 0
    for (let index = 0; index < this.units.length; index++) {
      if (index > 0) {
        length += 2
      }
      length += this.units[index].content.length
    }
    return length
  }

  parentId(): string {
    return this.units.length > 0 ? this.units[0].parentId : ''
  }
}

class KnowledgeSemanticEmbeddingState {
  used: boolean = false
  failed: boolean = false
  semanticBreakCount: number = 0
  breakBefore: boolean[] = []
}

/**
 * 结构优先、语义增强的知识库 Chunker。
 *
 * 1. 先识别页码、Markdown 标题、段落、列表、表格与 FAQ。
 * 2. 单元超过硬上限时才安全拆分。
 * 3. 有向量供应商时，用相邻单元余弦距离的自适应阈值增加断点。
 * 4. Embedding 不可用或失败时，结果仍按相同结构规则稳定生成。
 */
export class KnowledgeSemanticChunker {
  private options: KnowledgeSemanticChunkerOptions

  constructor(options: KnowledgeSemanticChunkerOptions = new KnowledgeSemanticChunkerOptions()) {
    this.options = options
  }

  async chunk(
    request: KnowledgeSemanticChunkRequest,
    embeddingProvider: KnowledgeEmbeddingProvider | null = null
  ): Promise<KnowledgeSemanticChunkingResult> {
    const normalizedText = this.normalizeText(request.text)
    if (normalizedText === '') {
      return new KnowledgeSemanticChunkingResult()
    }

    let units = this.parseStructuralUnits(request, normalizedText)
    units = this.mergeFaqUnits(units)
    units = this.enforceSafeUnitLimit(units)
    for (let index = 0; index < units.length; index++) {
      units[index].embeddingText = this.buildEmbeddingText(
        request.documentTitle,
        units[index].headingPath,
        units[index].pageStart,
        units[index].pageEnd,
        units[index].content
      )
    }

    const embeddingState = await this.buildSemanticEmbeddingState(units, embeddingProvider)
    const baseDrafts = this.buildBaseDrafts(units, embeddingState.breakBefore)
    this.mergeShortTails(baseDrafts)
    const drafts = this.addWholeUnitOverlap(baseDrafts)
    const chunks = this.buildOutputChunks(request, drafts)

    return new KnowledgeSemanticChunkingResult(
      chunks,
      embeddingState.used,
      embeddingState.failed,
      embeddingState.semanticBreakCount,
      units.length
    )
  }

  private normalizeText(value: string): string {
    return value
      .replace(/\r\n?/g, '\n')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{4,}/g, '\n\n\n')
      .trim()
  }

  private parseStructuralUnits(
    request: KnowledgeSemanticChunkRequest,
    text: string
  ): KnowledgeSemanticUnit[] {
    const units: KnowledgeSemanticUnit[] = []
    const lines = text.split('\n')
    const headingStack: string[] = []
    const buffer = new KnowledgeSemanticUnitBuffer()
    let page = 0
    let offset = 0
    let parentSequence = 1
    let parentId = this.buildParentId(request.documentId, parentSequence)

    for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      const line = lines[lineIndex]
      const trimmed = line.trim()
      const lineStart = offset
      const lineEnd = offset + line.length
      offset = lineEnd + 1

      const parsedPage = this.parsePageMarker(trimmed)
      if (parsedPage > 0) {
        this.flushBuffer(units, buffer)
        page = parsedPage
        parentSequence += 1
        parentId = this.buildParentId(request.documentId, parentSequence)
        continue
      }

      const headingLevel = this.parseHeadingLevel(trimmed)
      if (headingLevel > 0) {
        this.flushBuffer(units, buffer)
        const heading = trimmed.substring(headingLevel).trim()
        while (headingStack.length >= headingLevel) {
          headingStack.pop()
        }
        headingStack.push(heading)
        parentSequence += 1
        parentId = this.buildParentId(request.documentId, parentSequence)
        units.push(new KnowledgeSemanticUnit(
          trimmed,
          UNIT_KIND_HEADING,
          this.joinHeadingPath(headingStack),
          page,
          page,
          parentId,
          lineStart,
          lineEnd
        ))
        continue
      }

      if (trimmed === '') {
        this.flushBuffer(units, buffer)
        continue
      }

      const kind = this.detectLineKind(trimmed, buffer.kind)
      if (!buffer.isEmpty() && kind !== buffer.kind) {
        this.flushBuffer(units, buffer)
      }
      if (buffer.isEmpty()) {
        buffer.kind = kind
        buffer.headingPath = this.joinHeadingPath(headingStack)
        buffer.page = page
        buffer.parentId = parentId
        buffer.startOffset = lineStart
      }
      buffer.lines.push(trimmed)
      buffer.endOffset = lineEnd
    }
    this.flushBuffer(units, buffer)
    return units
  }

  private flushBuffer(
    units: KnowledgeSemanticUnit[],
    buffer: KnowledgeSemanticUnitBuffer
  ): void {
    if (buffer.isEmpty()) {
      return
    }
    const content = buffer.lines.join('\n').trim()
    if (content !== '') {
      units.push(new KnowledgeSemanticUnit(
        content,
        this.detectFaqKind(content, buffer.kind),
        buffer.headingPath,
        buffer.page,
        buffer.page,
        buffer.parentId,
        buffer.startOffset,
        buffer.endOffset
      ))
    }
    buffer.reset()
  }

  private parsePageMarker(value: string): number {
    if (!value.startsWith('[第') || !value.endsWith('页]')) {
      return 0
    }
    const numberText = value.substring(2, value.length - 2).trim()
    if (numberText === '' || !/^\d+$/.test(numberText)) {
      return 0
    }
    const page = Number.parseInt(numberText, 10)
    return Number.isFinite(page) && page > 0 ? page : 0
  }

  private parseHeadingLevel(value: string): number {
    let level = 0
    while (level < value.length && level < 6 && value.charAt(level) === '#') {
      level += 1
    }
    if (level === 0 || level >= value.length) {
      return 0
    }
    return /\s/.test(value.charAt(level)) ? level : 0
  }

  private joinHeadingPath(headings: string[]): string {
    return headings.join(' > ')
  }

  private detectLineKind(value: string, previousKind: string): string {
    if (this.isTableLine(value)) {
      return UNIT_KIND_TABLE
    }
    if (this.isListLine(value) ||
      (previousKind === UNIT_KIND_LIST && /^\s+/.test(value))) {
      return UNIT_KIND_LIST
    }
    return UNIT_KIND_PARAGRAPH
  }

  private isTableLine(value: string): boolean {
    if (value.indexOf('|') < 0) {
      return false
    }
    const pipeCount = value.split('|').length - 1
    return pipeCount >= 2
  }

  private isListLine(value: string): boolean {
    if (value.startsWith('- ') || value.startsWith('* ') || value.startsWith('+ ') ||
      value.startsWith('- [') || value.startsWith('* [')) {
      return true
    }
    return /^\d+[.)、]\s+/.test(value)
  }

  private detectFaqKind(content: string, fallbackKind: string): string {
    const value = content.trim().toLowerCase()
    if (value.startsWith('q:') || value.startsWith('q：') ||
      value.startsWith('question:') || value.startsWith('question：') ||
      value.startsWith('问题:') || value.startsWith('问题：') ||
      value.startsWith('问:') || value.startsWith('问：')) {
      return UNIT_KIND_FAQ_QUESTION
    }
    if (value.startsWith('a:') || value.startsWith('a：') ||
      value.startsWith('answer:') || value.startsWith('answer：') ||
      value.startsWith('答案:') || value.startsWith('答案：') ||
      value.startsWith('答:') || value.startsWith('答：')) {
      return UNIT_KIND_FAQ_ANSWER
    }
    return fallbackKind
  }

  private mergeFaqUnits(source: KnowledgeSemanticUnit[]): KnowledgeSemanticUnit[] {
    const result: KnowledgeSemanticUnit[] = []
    let index = 0
    while (index < source.length) {
      const current = source[index]
      if (current.kind === UNIT_KIND_FAQ_QUESTION &&
        index + 1 < source.length &&
        source[index + 1].kind === UNIT_KIND_FAQ_ANSWER &&
        source[index + 1].parentId === current.parentId) {
        const answer = source[index + 1]
        const mergedContent = `${current.content}\n${answer.content}`
        if (mergedContent.length <= this.options.maxCharacters) {
          result.push(new KnowledgeSemanticUnit(
            mergedContent,
            UNIT_KIND_PARAGRAPH,
            current.headingPath,
            this.firstKnownPage(current.pageStart, answer.pageStart),
            Math.max(current.pageEnd, answer.pageEnd),
            current.parentId,
            current.startOffset,
            answer.endOffset
          ))
          index += 2
          continue
        }
      }
      result.push(current)
      index += 1
    }
    return result
  }

  private enforceSafeUnitLimit(source: KnowledgeSemanticUnit[]): KnowledgeSemanticUnit[] {
    const result: KnowledgeSemanticUnit[] = []
    for (let index = 0; index < source.length; index++) {
      const unit = source[index]
      if (unit.content.length <= this.options.maxCharacters) {
        result.push(unit)
        continue
      }
      const pieces = this.splitOversizedUnit(unit)
      for (let pieceIndex = 0; pieceIndex < pieces.length; pieceIndex++) {
        result.push(pieces[pieceIndex])
      }
    }
    return result
  }

  private splitOversizedUnit(unit: KnowledgeSemanticUnit): KnowledgeSemanticUnit[] {
    const result: KnowledgeSemanticUnit[] = []
    let cursor = 0
    while (cursor < unit.content.length) {
      let end = Math.min(cursor + this.options.maxCharacters, unit.content.length)
      if (end < unit.content.length) {
        end = this.findSafeBoundary(unit.content, cursor, end)
      }
      if (end <= cursor) {
        end = Math.min(cursor + this.options.maxCharacters, unit.content.length)
      }
      const rawPiece = unit.content.substring(cursor, end)
      const piece = rawPiece.trim()
      if (piece !== '') {
        result.push(new KnowledgeSemanticUnit(
          piece,
          unit.kind,
          unit.headingPath,
          unit.pageStart,
          unit.pageEnd,
          unit.parentId,
          unit.startOffset + cursor,
          Math.min(unit.endOffset, unit.startOffset + end),
          cursor > 0,
          end < unit.content.length
        ))
      }
      cursor = end
      while (cursor < unit.content.length && /\s/.test(unit.content.charAt(cursor))) {
        cursor += 1
      }
    }
    return result
  }

  private findSafeBoundary(text: string, start: number, proposedEnd: number): number {
    const minimumBoundary = start + Math.floor(this.options.maxCharacters * 0.55)
    const candidates: string[] = ['\n', '。', '！', '？', '. ', '! ', '? ', '；', '; ', '，', ', ']
    let best = -1
    for (let index = 0; index < candidates.length; index++) {
      const candidate = candidates[index]
      const found = text.lastIndexOf(candidate, proposedEnd - 1)
      if (found >= minimumBoundary && found > best) {
        best = found + candidate.length
      }
    }
    return best > start ? best : proposedEnd
  }

  private async buildSemanticEmbeddingState(
    units: KnowledgeSemanticUnit[],
    provider: KnowledgeEmbeddingProvider | null
  ): Promise<KnowledgeSemanticEmbeddingState> {
    const state = new KnowledgeSemanticEmbeddingState()
    state.breakBefore = new Array<boolean>(units.length)
    for (let index = 0; index < state.breakBefore.length; index++) {
      state.breakBefore[index] = false
    }
    if (provider === null || !provider.isAvailable() || units.length === 0) {
      return state
    }

    try {
      const maximumInput = Math.max(
        64,
        Math.min(provider.maxInputCharacters(), this.options.embeddingMaxCharacters)
      )
      const texts: string[] = []
      for (let index = 0; index < units.length; index++) {
        texts.push(this.limitEmbeddingText(units[index].embeddingText, maximumInput))
      }
      const vectors: Float32Array[] = []
      for (let start = 0; start < texts.length; start += SEMANTIC_EMBEDDING_BATCH_SIZE) {
        const end = Math.min(start + SEMANTIC_EMBEDDING_BATCH_SIZE, texts.length)
        const batch = texts.slice(start, end)
        const batchVectors = await provider.embedDocuments(batch)
        for (let vectorIndex = 0; vectorIndex < batchVectors.length; vectorIndex++) {
          vectors.push(batchVectors[vectorIndex])
        }
      }
      if (!this.validateVectors(vectors, units.length)) {
        state.failed = true
        return state
      }
      for (let index = 0; index < units.length; index++) {
        units[index].rawEmbedding = this.normalizedVectorCopy(vectors[index])
      }
      state.used = true
      this.applyAdaptiveSemanticBreaks(units, state)
      return state
    } catch (_error) {
      state.failed = true
      for (let index = 0; index < units.length; index++) {
        units[index].rawEmbedding = null
      }
      return state
    }
  }

  private limitEmbeddingText(value: string, maximumCharacters: number): string {
    if (value.length <= maximumCharacters) {
      return value
    }
    return value.substring(0, maximumCharacters).trim()
  }

  private validateVectors(vectors: Float32Array[], expectedCount: number): boolean {
    if (vectors.length !== expectedCount || vectors.length === 0) {
      return false
    }
    const dimension = vectors[0].length
    if (dimension <= 0) {
      return false
    }
    for (let vectorIndex = 0; vectorIndex < vectors.length; vectorIndex++) {
      const vector = vectors[vectorIndex]
      if (vector.length !== dimension) {
        return false
      }
      let hasMagnitude = false
      for (let valueIndex = 0; valueIndex < vector.length; valueIndex++) {
        if (!Number.isFinite(vector[valueIndex])) {
          return false
        }
        if (vector[valueIndex] !== 0) {
          hasMagnitude = true
        }
      }
      if (!hasMagnitude) {
        return false
      }
    }
    return true
  }

  private normalizedVectorCopy(source: Float32Array): Float32Array {
    let sumSquares = 0
    for (let index = 0; index < source.length; index++) {
      sumSquares += source[index] * source[index]
    }
    const magnitude = Math.sqrt(sumSquares)
    const result = new Float32Array(source.length)
    if (magnitude <= 0) {
      return result
    }
    for (let index = 0; index < source.length; index++) {
      result[index] = source[index] / magnitude
    }
    return result
  }

  private applyAdaptiveSemanticBreaks(
    units: KnowledgeSemanticUnit[],
    state: KnowledgeSemanticEmbeddingState
  ): void {
    const similarities: number[] = []
    const similarityByBoundary = new Array<number>(units.length)
    for (let index = 0; index < similarityByBoundary.length; index++) {
      similarityByBoundary[index] = 1.0
    }
    for (let index = 1; index < units.length; index++) {
      if (units[index - 1].parentId !== units[index].parentId) {
        continue
      }
      const previous = units[index - 1].rawEmbedding
      const current = units[index].rawEmbedding
      if (previous === null || current === null) {
        continue
      }
      const similarity = this.cosineForNormalizedVectors(previous, current)
      similarityByBoundary[index] = similarity
      similarities.push(similarity)
    }
    if (similarities.length === 0) {
      return
    }

    let threshold = 0.72
    if (similarities.length >= 3) {
      let sum = 0
      for (let index = 0; index < similarities.length; index++) {
        sum += similarities[index]
      }
      const mean = sum / similarities.length
      let varianceSum = 0
      for (let index = 0; index < similarities.length; index++) {
        const difference = similarities[index] - mean
        varianceSum += difference * difference
      }
      const deviation = Math.sqrt(varianceSum / similarities.length)
      threshold = mean - this.options.semanticDeviationFactor * deviation
    }
    threshold = Math.max(
      this.options.semanticMinThreshold,
      Math.min(threshold, this.options.semanticMaxThreshold)
    )

    for (let index = 1; index < units.length; index++) {
      if (units[index - 1].parentId === units[index].parentId &&
        similarityByBoundary[index] < threshold) {
        state.breakBefore[index] = true
        state.semanticBreakCount += 1
      }
    }
  }

  private cosineForNormalizedVectors(left: Float32Array, right: Float32Array): number {
    if (left.length !== right.length || left.length === 0) {
      return 0
    }
    let dot = 0
    for (let index = 0; index < left.length; index++) {
      dot += left[index] * right[index]
    }
    return Math.max(-1, Math.min(dot, 1))
  }

  private buildBaseDrafts(
    units: KnowledgeSemanticUnit[],
    semanticBreakBefore: boolean[]
  ): KnowledgeSemanticChunkDraft[] {
    const drafts: KnowledgeSemanticChunkDraft[] = []
    let current = new KnowledgeSemanticChunkDraft()
    for (let index = 0; index < units.length; index++) {
      const unit = units[index]
      const differentParent = current.units.length > 0 && current.parentId() !== unit.parentId
      const semanticBreak = current.units.length > 0 &&
        semanticBreakBefore[index] &&
        current.contentLength() >= this.options.minCharacters
      const reachedTarget = current.units.length > 0 &&
        current.contentLength() >= this.options.targetCharacters
      const separatorLength = current.units.length > 0 ? 2 : 0
      const exceedsMaximum = current.units.length > 0 &&
        current.contentLength() + separatorLength + unit.content.length > this.options.maxCharacters

      if (differentParent || semanticBreak || reachedTarget || exceedsMaximum) {
        drafts.push(current)
        current = new KnowledgeSemanticChunkDraft()
      }
      current.units.push(unit)
    }
    if (current.units.length > 0) {
      drafts.push(current)
    }
    return drafts
  }

  private mergeShortTails(drafts: KnowledgeSemanticChunkDraft[]): void {
    let index = 1
    while (index < drafts.length) {
      const previous = drafts[index - 1]
      const current = drafts[index]
      const combinedLength = previous.contentLength() + 2 + current.contentLength()
      if (current.parentId() === previous.parentId() &&
        current.contentLength() < this.options.minCharacters &&
        combinedLength <= this.options.maxCharacters) {
        for (let unitIndex = 0; unitIndex < current.units.length; unitIndex++) {
          previous.units.push(current.units[unitIndex])
        }
        drafts.splice(index, 1)
        continue
      }
      index += 1
    }
  }

  private addWholeUnitOverlap(
    baseDrafts: KnowledgeSemanticChunkDraft[]
  ): KnowledgeSemanticChunkDraft[] {
    const result: KnowledgeSemanticChunkDraft[] = []
    for (let index = 0; index < baseDrafts.length; index++) {
      const base = baseDrafts[index]
      const expanded = new KnowledgeSemanticChunkDraft()
      if (index > 0 &&
        this.options.overlapUnitCount > 0 &&
        baseDrafts[index - 1].parentId() === base.parentId()) {
        const previous = baseDrafts[index - 1]
        const overlap: KnowledgeSemanticUnit[] = []
        let previousIndex = previous.units.length - 1
        while (previousIndex >= 0 && overlap.length < this.options.overlapUnitCount) {
          const candidate = previous.units[previousIndex]
          let proposedLength = base.contentLength() + candidate.content.length + 2
          for (let overlapIndex = 0; overlapIndex < overlap.length; overlapIndex++) {
            proposedLength += overlap[overlapIndex].content.length + 2
          }
          if (proposedLength > this.options.maxCharacters) {
            break
          }
          overlap.unshift(candidate)
          previousIndex -= 1
        }
        for (let overlapIndex = 0; overlapIndex < overlap.length; overlapIndex++) {
          expanded.units.push(overlap[overlapIndex])
        }
        expanded.overlapUnitCount = overlap.length
      }
      for (let unitIndex = 0; unitIndex < base.units.length; unitIndex++) {
        expanded.units.push(base.units[unitIndex])
      }
      result.push(expanded)
    }
    return result
  }

  private buildOutputChunks(
    request: KnowledgeSemanticChunkRequest,
    drafts: KnowledgeSemanticChunkDraft[]
  ): KnowledgeSemanticChunk[] {
    const chunks: KnowledgeSemanticChunk[] = []
    for (let index = 0; index < drafts.length; index++) {
      const draft = drafts[index]
      if (draft.units.length === 0) {
        continue
      }
      const content = this.joinUnitContent(draft.units)
      const firstUnit = draft.units[0]
      const lastUnit = draft.units[draft.units.length - 1]
      const pageStart = this.findFirstPage(draft.units)
      const pageEnd = this.findLastPage(draft.units)
      const headingPath = this.findHeadingPath(draft.units)
      const locator = this.buildLocator(headingPath, pageStart, pageEnd, index)
      const continuesBefore = draft.overlapUnitCount > 0 || firstUnit.continuesBefore
      const continuesAfter = lastUnit.continuesAfter ||
        (index + 1 < drafts.length && drafts[index + 1].parentId() === draft.parentId())
      const embeddingText = this.buildEmbeddingText(
        request.documentTitle,
        headingPath,
        pageStart,
        pageEnd,
        content
      )
      chunks.push(new KnowledgeSemanticChunk(
        `${request.documentId}_semantic_v3_chunk_${index + 1}`,
        request.documentId,
        request.documentTitle,
        content,
        embeddingText,
        locator,
        headingPath,
        pageStart,
        pageEnd,
        index,
        continuesBefore,
        continuesAfter,
        draft.parentId(),
        firstUnit.startOffset,
        lastUnit.endOffset,
        this.buildWeightedChunkEmbedding(draft.units)
      ))
    }
    return chunks
  }

  private joinUnitContent(units: KnowledgeSemanticUnit[]): string {
    const parts: string[] = []
    for (let index = 0; index < units.length; index++) {
      parts.push(units[index].content)
    }
    return parts.join('\n\n')
  }

  private buildEmbeddingText(
    documentTitle: string,
    headingPath: string,
    pageStart: number,
    pageEnd: number,
    content: string
  ): string {
    const metadata: string[] = []
    if (documentTitle.trim() !== '') {
      metadata.push(`文件：${documentTitle.trim()}`)
    }
    if (headingPath !== '') {
      metadata.push(`章节：${headingPath}`)
    }
    if (pageStart > 0) {
      if (pageEnd > pageStart) {
        metadata.push(`页码：第 ${pageStart}-${pageEnd} 页`)
      } else {
        metadata.push(`页码：第 ${pageStart} 页`)
      }
    }
    if (metadata.length === 0) {
      return content
    }
    return `${metadata.join('\n')}\n\n${content}`
  }

  private buildWeightedChunkEmbedding(units: KnowledgeSemanticUnit[]): Float32Array | null {
    let dimension = 0
    for (let index = 0; index < units.length; index++) {
      const unitVector = units[index].rawEmbedding
      if (unitVector !== null) {
        dimension = unitVector.length
        break
      }
    }
    if (dimension <= 0) {
      return null
    }

    const accumulated = new Float32Array(dimension)
    let totalWeight = 0
    for (let unitIndex = 0; unitIndex < units.length; unitIndex++) {
      const vector = units[unitIndex].rawEmbedding
      if (vector === null || vector.length !== dimension) {
        return null
      }
      const weight = Math.max(1, units[unitIndex].content.replace(/\s/g, '').length)
      totalWeight += weight
      for (let valueIndex = 0; valueIndex < dimension; valueIndex++) {
        accumulated[valueIndex] += vector[valueIndex] * weight
      }
    }
    if (totalWeight <= 0) {
      return null
    }
    for (let index = 0; index < accumulated.length; index++) {
      accumulated[index] /= totalWeight
    }
    return this.normalizedVectorCopy(accumulated)
  }

  private findFirstPage(units: KnowledgeSemanticUnit[]): number {
    for (let index = 0; index < units.length; index++) {
      if (units[index].pageStart > 0) {
        return units[index].pageStart
      }
    }
    return 0
  }

  private findLastPage(units: KnowledgeSemanticUnit[]): number {
    let page = 0
    for (let index = 0; index < units.length; index++) {
      page = Math.max(page, units[index].pageEnd)
    }
    return page
  }

  private findHeadingPath(units: KnowledgeSemanticUnit[]): string {
    for (let index = units.length - 1; index >= 0; index--) {
      if (units[index].headingPath !== '') {
        return units[index].headingPath
      }
    }
    return ''
  }

  private buildLocator(
    headingPath: string,
    pageStart: number,
    pageEnd: number,
    chunkIndex: number
  ): string {
    const parts: string[] = []
    if (pageStart > 0) {
      if (pageEnd > pageStart) {
        parts.push(`第 ${pageStart}-${pageEnd} 页`)
      } else {
        parts.push(`第 ${pageStart} 页`)
      }
    }
    if (headingPath !== '') {
      parts.push(headingPath)
    }
    parts.push(`片段 ${chunkIndex + 1}`)
    return parts.join(' · ')
  }

  private firstKnownPage(left: number, right: number): number {
    if (left > 0) {
      return left
    }
    return right
  }

  private buildParentId(documentId: string, sequence: number): string {
    return `${documentId}_semantic_v3_parent_${sequence}`
  }
}
