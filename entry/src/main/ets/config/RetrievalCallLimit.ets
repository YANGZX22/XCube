export const UNLIMITED_RETRIEVAL_CALL_LIMIT: number = 0
export const MAX_RETRIEVAL_CALL_LIMIT: number = 10

export function normalizeRetrievalCallLimit(value: number): number {
  if (!Number.isFinite(value) || !Number.isInteger(value)) {
    return UNLIMITED_RETRIEVAL_CALL_LIMIT
  }
  if (value < 1 || value > MAX_RETRIEVAL_CALL_LIMIT) {
    return UNLIMITED_RETRIEVAL_CALL_LIMIT
  }
  return value
}

export function hasFiniteRetrievalCallLimit(value: number): boolean {
  return normalizeRetrievalCallLimit(value) > UNLIMITED_RETRIEVAL_CALL_LIMIT
}
