/**
 * GaussPD 向量列在当前 Phone/Tablet 实现中接受 1–1024 维。
 * embedding 后端可能返回 1536、2048 或 3072 维，因此入库与查询必须经过同一
 * 个确定性映射。这里使用带符号特征哈希；它不需要保存投影矩阵，且文档/查询两端
 * 对同一原始向量始终得到相同的 1024 维表示。
 */
export const KNOWLEDGE_VECTOR_MAX_DIMENSION: number = 1024
export const KNOWLEDGE_VECTOR_PROJECTION_VERSION: string = 'signed-feature-hash-v1-1024'

export function projectKnowledgeVector(source: Float32Array): Float32Array {
  if (!(source instanceof Float32Array) || source.length === 0) {
    throw new Error('向量不能为空')
  }

  if (source.length <= KNOWLEDGE_VECTOR_MAX_DIMENSION) {
    const copied = new Float32Array(source.length)
    let squaredNorm = 0
    for (let index = 0; index < source.length; index++) {
      const value = source[index]
      if (!Number.isFinite(value)) {
        throw new Error('向量包含无效数值')
      }
      copied[index] = value
      squaredNorm += value * value
    }
    if (!Number.isFinite(squaredNorm) || squaredNorm <= 0) {
      throw new Error('向量不能为全零向量')
    }
    return copied
  }

  const projected = new Float32Array(KNOWLEDGE_VECTOR_MAX_DIMENSION)
  for (let index = 0; index < source.length; index++) {
    const value = source[index]
    if (!Number.isFinite(value)) {
      throw new Error('向量包含无效数值')
    }
    const mixed = Math.imul(index + 1, -1640531527) >>> 0
    const bucket = mixed % KNOWLEDGE_VECTOR_MAX_DIMENSION
    const sign = (mixed & 0x80000000) === 0 ? 1 : -1
    projected[bucket] += sign * value
    if (!Number.isFinite(projected[bucket])) {
      throw new Error('降维后的向量包含无效数值')
    }
  }

  let squaredNorm = 0
  for (let index = 0; index < projected.length; index++) {
    squaredNorm += projected[index] * projected[index]
  }
  if (!Number.isFinite(squaredNorm) || squaredNorm <= 0) {
    throw new Error('降维后得到全零向量')
  }
  return projected
}
