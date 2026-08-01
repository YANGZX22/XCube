import { describe, it, expect } from '@ohos/hypium'
import {
  KnowledgeRetrievalFallbackReason,
  KnowledgeRetrievalMode,
  resolveKnowledgeRetrievalPlan
} from '../main/ets/services/KnowledgeRetrievalService'
import {
  KnowledgeEmbeddingMigrationAction,
  resolveKnowledgeEmbeddingMigrationAction
} from '../main/ets/services/KnowledgeVectorRecoveryPolicy'

export default function knowledgeVectorRecoveryPolicyTest() {
  describe('knowledgeVectorRecoveryPolicyTest', () => {
    it('repairs_stale_documents_when_the_same_model_is_selected', 0, () => {
      expect(resolveKnowledgeEmbeddingMigrationAction('model-1', 'model-1', 3))
        .assertEqual(KnowledgeEmbeddingMigrationAction.REPAIR_CURRENT)
      expect(resolveKnowledgeEmbeddingMigrationAction('model-1', 'model-1', 0))
        .assertEqual(KnowledgeEmbeddingMigrationAction.NO_OP)
      expect(resolveKnowledgeEmbeddingMigrationAction('model-1', 'model-2', 0))
        .assertEqual(KnowledgeEmbeddingMigrationAction.SWITCH_AND_REBUILD)
    })

    it('does_not_embed_a_query_without_vector_ready_documents', 0, () => {
      const plan = resolveKnowledgeRetrievalPlan({
        invertedConfigured: true,
        vectorConfigured: true,
        vectorScopeAvailable: true,
        embeddingAvailable: true,
        vectorReadyDocumentCount: 0,
        embeddingModelStable: true
      })

      expect(plan.mode).assertEqual(KnowledgeRetrievalMode.KEYWORD)
      expect(plan.reason).assertEqual(
        KnowledgeRetrievalFallbackReason.NO_VECTOR_READY_DOCUMENTS
      )
      expect(plan.shouldEmbedQuery).assertEqual(false)
    })

    it('uses_hybrid_retrieval_only_when_every_preflight_gate_is_ready', 0, () => {
      const plan = resolveKnowledgeRetrievalPlan({
        invertedConfigured: true,
        vectorConfigured: true,
        vectorScopeAvailable: true,
        embeddingAvailable: true,
        vectorReadyDocumentCount: 7,
        embeddingModelStable: true
      })

      expect(plan.mode).assertEqual(KnowledgeRetrievalMode.HYBRID)
      expect(plan.reason).assertEqual(KnowledgeRetrievalFallbackReason.NONE)
      expect(plan.shouldEmbedQuery).assertEqual(true)
    })

    it('reports_each_pre_embedding_fallback_reason', 0, () => {
      const vectorMissing = resolveKnowledgeRetrievalPlan({
        invertedConfigured: true,
        vectorConfigured: false,
        vectorScopeAvailable: true,
        embeddingAvailable: true,
        vectorReadyDocumentCount: -1,
        embeddingModelStable: true
      })
      const embeddingMissing = resolveKnowledgeRetrievalPlan({
        invertedConfigured: true,
        vectorConfigured: true,
        vectorScopeAvailable: true,
        embeddingAvailable: false,
        vectorReadyDocumentCount: -1,
        embeddingModelStable: true
      })
      const modelChanged = resolveKnowledgeRetrievalPlan({
        invertedConfigured: true,
        vectorConfigured: true,
        vectorScopeAvailable: true,
        embeddingAvailable: true,
        vectorReadyDocumentCount: 1,
        embeddingModelStable: false
      })

      expect(vectorMissing.reason).assertEqual(
        KnowledgeRetrievalFallbackReason.VECTOR_NOT_CONFIGURED
      )
      expect(embeddingMissing.reason).assertEqual(
        KnowledgeRetrievalFallbackReason.EMBEDDING_UNAVAILABLE
      )
      expect(modelChanged.reason).assertEqual(
        KnowledgeRetrievalFallbackReason.EMBEDDING_MODEL_CHANGED
      )
    })
  })
}
