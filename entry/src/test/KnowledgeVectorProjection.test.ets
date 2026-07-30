import { describe, it, expect } from '@ohos/hypium'
import {
  KNOWLEDGE_VECTOR_MAX_DIMENSION,
  projectKnowledgeVector
} from '../main/ets/services/KnowledgeVectorProjection'

export default function knowledgeVectorProjectionTest() {
  describe('knowledgeVectorProjectionTest', () => {
    it('preserves_supported_dimensions_and_values', 0, () => {
      const source = Float32Array.from([3, 4])
      const projected = projectKnowledgeVector(source)

      expect(projected instanceof Float32Array).assertEqual(true)
      expect(projected.length).assertEqual(2)
      expect(projected[0]).assertEqual(3)
      expect(projected[1]).assertEqual(4)
      expect(projected === source).assertEqual(false)
    })

    it('reduces_2048_dimensions_to_the_gausspd_limit_deterministically', 0, () => {
      const source = new Float32Array(2048)
      for (let index = 0; index < source.length; index++) {
        source[index] = (index % 31) - 15
      }

      const first = projectKnowledgeVector(source)
      const second = projectKnowledgeVector(source)

      expect(first.length).assertEqual(KNOWLEDGE_VECTOR_MAX_DIMENSION)
      expect(second.length).assertEqual(KNOWLEDGE_VECTOR_MAX_DIMENSION)
      for (let index = 0; index < first.length; index++) {
        expect(Number.isFinite(first[index])).assertEqual(true)
        expect(first[index]).assertEqual(second[index])
      }
    })
  })
}
