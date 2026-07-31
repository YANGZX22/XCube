import { describe, it, expect } from '@ohos/hypium'
import {
  KnowledgeSemanticChunker,
  KnowledgeSemanticChunkerOptions,
  KnowledgeSemanticChunkRequest
} from '../main/ets/services/KnowledgeSemanticChunker'
import { KnowledgeEmbeddingProvider } from '../main/ets/services/KnowledgeEmbeddingService'

class TopicKnowledgeSemanticEmbeddingProvider implements KnowledgeEmbeddingProvider {
  callCount: number = 0
  totalTextCount: number = 0
  lastTexts: string[] = []

  isAvailable(): boolean {
    return true
  }

  maxInputCharacters(): number {
    return 512
  }

  modelKey(): string {
    return 'test:topic'
  }

  async embedDocuments(texts: string[]): Promise<Float32Array[]> {
    this.callCount += 1
    this.totalTextCount += texts.length
    this.lastTexts = texts.slice()
    const vectors: Float32Array[] = []
    for (let index = 0; index < texts.length; index++) {
      if (texts[index].includes('量子') || texts[index].includes('光子')) {
        vectors.push(Float32Array.from([0, 4]))
      } else {
        vectors.push(Float32Array.from([3, 0]))
      }
    }
    return vectors
  }

  async embedQuery(_text: string): Promise<Float32Array> {
    return Float32Array.from([1, 0])
  }

  async release(): Promise<void> {
  }
}

class FailingKnowledgeSemanticEmbeddingProvider implements KnowledgeEmbeddingProvider {
  isAvailable(): boolean {
    return true
  }

  maxInputCharacters(): number {
    return 512
  }

  modelKey(): string {
    return 'test:failing'
  }

  async embedDocuments(_texts: string[]): Promise<Float32Array[]> {
    throw new Error('synthetic embedding failure')
  }

  async embedQuery(_text: string): Promise<Float32Array> {
    throw new Error('synthetic embedding failure')
  }

  async release(): Promise<void> {
  }
}

export default function knowledgeSemanticChunkerTest() {
  describe('knowledgeSemanticChunkerTest', () => {
    it('preserves_heading_page_faq_list_and_table_structure', 0, async () => {
      const options = new KnowledgeSemanticChunkerOptions(160, 220, 40, 1)
      const chunker = new KnowledgeSemanticChunker(options)
      const request = new KnowledgeSemanticChunkRequest(
        'doc-structure',
        '员工手册.pdf',
        '[第 3 页]\n# 休假制度\n## 年假\n\n' +
        '问题：新员工有多少天年假？\n\n答案：入职第一年有五天年假。\n\n' +
        '- 可拆分使用\n- 需提前申请\n\n' +
        '| 类型 | 天数 |\n| --- | --- |\n| 年假 | 5 |'
      )

      const result = await chunker.chunk(request)

      expect(result.structuralUnitCount >= 4).assertEqual(true)
      expect(result.chunks.length >= 1).assertEqual(true)
      expect(result.chunks[0].headingPath).assertContain('休假制度')
      expect(result.chunks[0].pageStart).assertEqual(3)
      expect(result.chunks[0].locator).assertContain('第 3 页')
      expect(result.chunks[0].embeddingText).assertContain('文件：员工手册.pdf')
      expect(result.chunks[0].embeddingText).assertContain('章节：')
      for (let index = 0; index < result.chunks.length; index++) {
        expect(result.chunks[index].content.length <= options.maxCharacters).assertEqual(true)
        expect(result.chunks[index].parentId.length > 0).assertEqual(true)
      }
      let allContent = ''
      for (let index = 0; index < result.chunks.length; index++) {
        allContent += `${result.chunks[index].content}\n`
      }
      expect(allContent).assertContain('问题：新员工有多少天年假？\n答案：入职第一年有五天年假。')
      expect(allContent).assertContain('| 类型 | 天数 |')
      expect(allContent).assertContain('- 可拆分使用\n- 需提前申请')
    })

    it('keeps_the_hard_limit_and_overlaps_whole_units', 0, async () => {
      const options = new KnowledgeSemanticChunkerOptions(55, 90, 20, 1)
      const chunker = new KnowledgeSemanticChunker(options)
      const first = '第一段说明本地知识库如何建立关键词索引，并完整保留原始内容。'
      const second = '第二段说明向量索引如何生成，同时不会把检索结果提前写入提示词。'
      const third = '第三段很短，用于验证后一片段按完整结构单元重叠。'
      const request = new KnowledgeSemanticChunkRequest(
        'doc-overlap',
        '索引说明.md',
        `${first}\n\n${second}\n\n${third}`
      )

      const result = await chunker.chunk(request)

      expect(result.chunks.length >= 2).assertEqual(true)
      for (let index = 0; index < result.chunks.length; index++) {
        expect(result.chunks[index].content.length <= options.maxCharacters).assertEqual(true)
      }
      expect(result.chunks[1].continuesBefore).assertEqual(true)
      expect(result.chunks[1].content.startsWith(second) ||
        result.chunks[1].content.startsWith(first)).assertEqual(true)
    })

    it('batches_structural_unit_embeddings_sixteen_at_a_time', 0, async () => {
      const options = new KnowledgeSemanticChunkerOptions(300, 420, 20, 0)
      const chunker = new KnowledgeSemanticChunker(options)
      const provider = new TopicKnowledgeSemanticEmbeddingProvider()
      let text = ''
      for (let index = 0; index < 17; index++) {
        if (index > 0) {
          text += '\n\n'
        }
        text += `第 ${index + 1} 个独立自然段介绍猫的生活习惯。`
      }

      const result = await chunker.chunk(
        new KnowledgeSemanticChunkRequest('doc-batch', '批处理.txt', text),
        provider
      )

      expect(result.structuralUnitCount).assertEqual(17)
      expect(provider.callCount).assertEqual(2)
      expect(provider.totalTextCount).assertEqual(17)
      expect(result.semanticEmbeddingUsed).assertEqual(true)
    })

    it('uses_adaptive_semantic_boundaries_and_reuses_raw_vectors', 0, async () => {
      const options = new KnowledgeSemanticChunkerOptions(300, 420, 20, 0)
      const chunker = new KnowledgeSemanticChunker(options)
      const provider = new TopicKnowledgeSemanticEmbeddingProvider()
      const request = new KnowledgeSemanticChunkRequest(
        'doc-semantic',
        '混合主题.txt',
        '猫喜欢安静地趴在窗边晒太阳。\n\n' +
        '幼猫通常通过叫声表达自己的需求。\n\n' +
        '量子计算使用量子比特处理信息。\n\n' +
        '光子的量子态可以用于信息传输。'
      )

      const result = await chunker.chunk(request, provider)

      expect(provider.callCount).assertEqual(1)
      expect(provider.lastTexts.length).assertEqual(result.structuralUnitCount)
      expect(result.semanticEmbeddingUsed).assertEqual(true)
      expect(result.semanticEmbeddingFailed).assertEqual(false)
      expect(result.semanticBreakCount >= 1).assertEqual(true)
      expect(result.chunks.length).assertEqual(2)
      expect(result.chunks[0].content).assertContain('猫')
      expect(result.chunks[1].content).assertContain('量子')
      expect(result.chunks[0].rawEmbedding === null).assertEqual(false)
      expect(result.chunks[1].rawEmbedding === null).assertEqual(false)
      const firstVector = result.chunks[0].rawEmbedding
      const secondVector = result.chunks[1].rawEmbedding
      if (firstVector !== null && secondVector !== null) {
        expect(firstVector.length).assertEqual(2)
        expect(secondVector.length).assertEqual(2)
        expect(Math.abs(firstVector[0] - 1) < 0.0001).assertEqual(true)
        expect(Math.abs(secondVector[1] - 1) < 0.0001).assertEqual(true)
      }
    })

    it('falls_back_to_structural_chunks_when_embedding_fails', 0, async () => {
      const chunker = new KnowledgeSemanticChunker(
        new KnowledgeSemanticChunkerOptions(120, 180, 30, 0)
      )
      const request = new KnowledgeSemanticChunkRequest(
        'doc-fallback',
        'fallback.md',
        '# 标题\n\n第一段仍然可以建立关键词索引。\n\n第二段仍然可以被检索。'
      )

      const result = await chunker.chunk(
        request,
        new FailingKnowledgeSemanticEmbeddingProvider()
      )

      expect(result.semanticEmbeddingUsed).assertEqual(false)
      expect(result.semanticEmbeddingFailed).assertEqual(true)
      expect(result.chunks.length >= 1).assertEqual(true)
      for (let index = 0; index < result.chunks.length; index++) {
        expect(result.chunks[index].rawEmbedding === null).assertEqual(true)
        expect(result.chunks[index].embeddingText.length > 0).assertEqual(true)
      }
    })
  })
}
