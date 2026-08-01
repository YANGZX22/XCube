export enum KnowledgeEmbeddingMigrationAction {
  NO_OP = 'no_op',
  REPAIR_CURRENT = 'repair_current',
  SWITCH_AND_REBUILD = 'switch_and_rebuild'
}

export function resolveKnowledgeEmbeddingMigrationAction(
  currentIdentity: string,
  requestedIdentity: string,
  staleDocumentCount: number
): KnowledgeEmbeddingMigrationAction {
  if (currentIdentity !== requestedIdentity) {
    return KnowledgeEmbeddingMigrationAction.SWITCH_AND_REBUILD
  }
  if (Number.isFinite(staleDocumentCount) && staleDocumentCount > 0) {
    return KnowledgeEmbeddingMigrationAction.REPAIR_CURRENT
  }
  return KnowledgeEmbeddingMigrationAction.NO_OP
}
