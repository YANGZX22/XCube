import { ToolDefinition } from '../models/ChatModels'
import { hasFiniteRetrievalCallLimit } from '../config/RetrievalCallLimit'

export class ToolRoundOptions {
  webSearchCount: number = 0
  knowledgeSearchCount: number = 0
  webSearchLimit: number = 0
  knowledgeSearchLimit: number = 0
  compactCompleted: boolean = false
  stopForNoProgress: boolean = false
}

export class ToolRoundSelection {
  tools: ToolDefinition[]
  toolChoice: string

  constructor(tools: ToolDefinition[]) {
    this.tools = tools
    this.toolChoice = tools.length > 0 ? 'auto' : 'none'
  }
}

// 工具可用性与是否需要调用分开：首轮保留所有可用工具，由模型按请求决定。
export function selectToolRound(tools: ToolDefinition[], options: ToolRoundOptions): ToolRoundSelection {
  const available: ToolDefinition[] = []
  if (!options.stopForNoProgress) {
    for (let i = 0; i < tools.length; i++) {
      const name = tools[i].function.name
      if (name === 'web_search' && hasFiniteRetrievalCallLimit(options.webSearchLimit) &&
        options.webSearchCount >= options.webSearchLimit) {
        continue
      }
      if (name === 'knowledge_search' && hasFiniteRetrievalCallLimit(options.knowledgeSearchLimit) &&
        options.knowledgeSearchCount >= options.knowledgeSearchLimit) {
        continue
      }
      if (name === 'compact' && options.compactCompleted) {
        continue
      }
      available.push(tools[i])
    }
  }
  return new ToolRoundSelection(available)
}
