import { describe, it, expect } from '@ohos/hypium'
import {
  KnowledgeEmbeddingProvider,
  KnowledgeEmbeddingService
} from '../main/ets/services/KnowledgeEmbeddingService'

class CountingKnowledgeEmbeddingProvider implements KnowledgeEmbeddingProvider {
  documentEmbedCount: number = 0
  queryEmbedCount: number = 0
  releaseCount: number = 0
  lastDocumentTexts: string[] = []
  lastQueryText: string = ''

  isAvailable(): boolean {
    return true
  }

  modelKey(): string {
    return 'fake:knowledge-embedding'
  }

  maxInputCharacters(): number {
    return 384
  }

  async embedDocuments(texts: string[]): Promise<Float32Array[]> {
    this.documentEmbedCount += 1
    this.lastDocumentTexts = texts.slice()

    const vectors: Float32Array[] = []
    for (let index = 0; index < texts.length; index++) {
      const vector = new Float32Array(2)
      vector[0] = index + 1
      vector[1] = texts[index].length
      vectors.push(vector)
    }
    return vectors
  }

  async embedQuery(text: string): Promise<Float32Array> {
    this.queryEmbedCount += 1
    this.lastQueryText = text

    const vector = new Float32Array(2)
    vector[0] = 7
    vector[1] = text.length
    return vector
  }

  async release(): Promise<void> {
    this.releaseCount += 1
  }
}

export default function knowledgeEmbeddingBoundaryTest() {
  describe('knowledgeEmbeddingBoundaryTest', () => {
    it('does_not_embed_when_constructed_or_reading_capability_metadata', 0, () => {
      const provider = new CountingKnowledgeEmbeddingProvider()
      const service = new KnowledgeEmbeddingService(provider)

      expect(provider.documentEmbedCount).assertEqual(0)
      expect(provider.queryEmbedCount).assertEqual(0)
      expect(service.isAvailable()).assertEqual(true)
      expect(service.modelKey()).assertEqual('fake:knowledge-embedding')
      expect(service.maxInputCharacters()).assertEqual(384)
      expect(provider.documentEmbedCount).assertEqual(0)
      expect(provider.queryEmbedCount).assertEqual(0)
    })

    it('delegates_document_embedding_and_preserves_float32_vectors', 0, async () => {
      const provider = new CountingKnowledgeEmbeddingProvider()
      const service = new KnowledgeEmbeddingService(provider)

      const vectors = await service.embedDocuments(['alpha', '中文'])

      expect(provider.documentEmbedCount).assertEqual(1)
      expect(provider.queryEmbedCount).assertEqual(0)
      expect(provider.lastDocumentTexts.join('|')).assertEqual('alpha|中文')
      expect(vectors.length).assertEqual(2)
      expect(vectors[0] instanceof Float32Array).assertEqual(true)
      expect(vectors[1] instanceof Float32Array).assertEqual(true)
      expect(vectors[0].length).assertEqual(2)
      expect(vectors[0][0]).assertEqual(1)
      expect(vectors[0][1]).assertEqual(5)
      expect(vectors[1][0]).assertEqual(2)
      expect(vectors[1][1]).assertEqual(2)
    })

    it('invokes_query_embedding_only_after_explicit_embed_query', 0, async () => {
      const provider = new CountingKnowledgeEmbeddingProvider()
      const service = new KnowledgeEmbeddingService(provider)

      service.isAvailable()
      service.modelKey()

      expect(provider.queryEmbedCount).assertEqual(0)

      const vector = await service.embedQuery('显式查询')

      expect(provider.documentEmbedCount).assertEqual(0)
      expect(provider.queryEmbedCount).assertEqual(1)
      expect(provider.lastQueryText).assertEqual('显式查询')
      expect(vector instanceof Float32Array).assertEqual(true)
      expect(vector.length).assertEqual(2)
      expect(vector[0]).assertEqual(7)
      expect(vector[1]).assertEqual(4)
    })
  })
}
