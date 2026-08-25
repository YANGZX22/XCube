import {
  ToolConfig,
  ToolDefinition,
  ToolFunction,
  ToolParameters,
  ToolPermissionLevel,
  ToolSourceType
} from '../models/ChatModels'
import {
  ContextCompactionResult,
  ContextCompactionStatus,
  DEFAULT_COMPACT_KEEP_RECENT_TURNS,
  MAX_COMPACT_KEEP_RECENT_TURNS,
  MIN_COMPACT_SUMMARY_LENGTH,
  getContextCompactionService
} from '../services/ContextCompactionService'
import { ToolExecutor } from '../services/ToolRegistry'

export const COMPACT_TOOL_ID: string = 'compact'

// 成功结果：不回传摘要正文，避免同一段文本在工具结果里再占一份上下文
class CompactSuccessOutput {
  status: string = ContextCompactionStatus.APPLIED
  message: string = ''
  compactedMessageCount: number = 0
  keptMessageCount: number = 0
  keptRecentTurns: number = 0
  beforeTokens: number = 0
  afterTokens: number = 0
  savedTokens: number = 0

  constructor(result: ContextCompactionResult) {
    this.status = result.status
    this.message = result.message
    this.compactedMessageCount = result.compactedMessageCount
    this.keptMessageCount = result.keptMessageCount
    this.keptRecentTurns = result.keptRecentTurns
    this.beforeTokens = result.beforeTokens
    this.afterTokens = result.afterTokens
    this.savedTokens = result.savedTokens
  }
}

class CompactErrorOutput {
  status: string = ''
  error: string = ''
  message: string = ''

  constructor(status: string, message: string) {
    this.status = status
    this.error = status
    this.message = message
  }
}

export class CompactExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    const result = getContextCompactionService().applyCompaction(args)
    if (!result.applied) {
      return JSON.stringify(new CompactErrorOutput(result.status, result.message))
    }
    return JSON.stringify(new CompactSuccessOutput(result))
  }
}

export function createCompactToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "summary": {
        "type": "string",
        "description": "必填，至少 ${MIN_COMPACT_SUMMARY_LENGTH} 个字符。用第三人称完整总结此前对话，覆盖：用户的目标与关键约束、已确认的事实和结论、已产出的代码/文件/数据及其位置、已经排除的方案及原因、当前进度。使用用户的语言，保留关键标识符、文件名、数字和专有名词原文；不要写成'我们讨论了…'式的空泛概述，也不要臆造未发生的内容。"
      },
      "open_items": {
        "type": "array",
        "items": { "type": "string" },
        "description": "可选。尚未完成的事项或待确认问题，每条一句话。"
      },
      "keep_recent_turns": {
        "type": "integer",
        "minimum": 0,
        "maximum": ${MAX_COMPACT_KEEP_RECENT_TURNS},
        "description": "可选，默认 ${DEFAULT_COMPACT_KEEP_RECENT_TURNS}。摘要之外仍以原文保留的最近完整轮次数；最近上下文细节重要时可适当调大。"
      }
    },
    "required": ["summary"],
    "additionalProperties": false
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)

  const func = new ToolFunction(
    COMPACT_TOOL_ID,
    '按用户明确要求压缩当前对话的上下文：把此前的对话历史浓缩成一段结构化摘要，' +
      '应用会用该摘要替换掉更早的原始消息，只保留最近若干轮原文。' +
      '摘要必须自包含，因为被替换掉的原文之后不再可见；写漏的信息会永久丢失。' +
      '本工具只影响发送给模型的上下文，不会删除用户在界面上看到的聊天记录。' +
      '阈值触发的自动压缩由应用独立完成，不需要调用本工具。',
    parameters
  )

  return new ToolDefinition(func)
}

export function createCompactToolConfig(): ToolConfig {
  return new ToolConfig(
    COMPACT_TOOL_ID,
    '上下文压缩',
    '上下文接近上限时，由应用自动把更早的对话压缩成摘要',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    COMPACT_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}
