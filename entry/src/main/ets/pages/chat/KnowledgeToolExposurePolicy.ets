import { ApiStyle } from '../../models/ChatModels'

export const KNOWLEDGE_SEARCH_TOOL_ID: string = 'knowledge_search'

/**
 * knowledge_search 的自动曝光输入。
 *
 * 本策略只投影本轮可交给模型的工具 ID，不读取消息、不拼接提示词，
 * 也不执行知识库检索。
 */
export interface KnowledgeToolExposureInput {
  currentApiStyle: ApiStyle
  modelSupportsTools: boolean
  knowledgeReady: boolean
  userEnabled: boolean
  baseToolIds: string[]
}

export function shouldExposeKnowledgeSearchTool(input: KnowledgeToolExposureInput): boolean {
  return input.currentApiStyle === ApiStyle.OPENAI &&
    input.modelSupportsTools &&
    input.knowledgeReady &&
    input.userEnabled
}

/**
 * 返回本轮可曝光的工具 ID。
 *
 * knowledge_search 只有在全部门槛满足时才会出现。即使调用方的基础列表
 * 残留了旧值，本策略也会先移除它，再按当前状态决定是否追加。
 */
export function resolveKnowledgeToolExposure(input: KnowledgeToolExposureInput): string[] {
  const resolvedToolIds: string[] = []

  for (let index = 0; index < input.baseToolIds.length; index++) {
    const toolId = input.baseToolIds[index]
    if (toolId !== KNOWLEDGE_SEARCH_TOOL_ID && !resolvedToolIds.includes(toolId)) {
      resolvedToolIds.push(toolId)
    }
  }

  if (shouldExposeKnowledgeSearchTool(input)) {
    resolvedToolIds.push(KNOWLEDGE_SEARCH_TOOL_ID)
  }

  return resolvedToolIds
}
