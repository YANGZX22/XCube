import { AssistantResponseSegmentType, ChatMessage } from '../models/ChatModels'

export class ReplyStepCounts {
  reasoning: number = 0
  answers: number = 0
  tools: number = 0

  get total(): number {
    return this.reasoning + this.answers + this.tools
  }
}

export function countReplySteps(message: ChatMessage): ReplyStepCounts {
  const counts = new ReplyStepCounts()
  const toolIds = new Set<string>()
  for (const segment of message.responseSegments) {
    if (segment.type === AssistantResponseSegmentType.TOOL_CALLS) {
      for (const id of segment.toolCallIds) {
        if (id !== '') toolIds.add(id)
      }
    } else if (segment.type === AssistantResponseSegmentType.REASONING && /\S/.test(segment.content)) {
      counts.reasoning++
    } else if (segment.type === AssistantResponseSegmentType.CONTENT && /\S/.test(segment.content)) {
      counts.answers++
    }
  }
  // 旧消息和单轮检索可能只有聚合正文。已有对应时间线段时不能再计一次。
  if (counts.reasoning === 0 && /\S/.test(message.reasoningContent)) counts.reasoning = 1
  if (counts.answers === 0 && /\S/.test(message.content)) counts.answers = 1
  for (const call of message.toolCalls) {
    if (call.id === '') {
      counts.tools++
    } else {
      toolIds.add(call.id)
    }
  }
  counts.tools += toolIds.size
  return counts
}

export function replyTokensPerSecond(message: ChatMessage, now: number = Date.now()): number | undefined {
  const modelMs = message.elapsedModelGenerationMs(now)
  const modelOutputTokens = Math.max(0, message.estimatedOutputTokens - message.auxiliaryOutputTokens)
  return modelMs > 0 ? modelOutputTokens * 1000 / modelMs : undefined
}

export enum ReplySpeedTier {
  UNKNOWN = 'unknown',
  SNAIL = 'snail',
  TURTLE = 'turtle',
  RABBIT = 'rabbit'
}

export function getReplySpeedTier(rate: number | undefined): ReplySpeedTier {
  if (rate === undefined) return ReplySpeedTier.UNKNOWN
  if (rate < 10) return ReplySpeedTier.SNAIL
  return rate <= 30 ? ReplySpeedTier.TURTLE : ReplySpeedTier.RABBIT
}

export function formatReplySpeed(rate: number): string {
  const rounded = rate.toFixed(1)
  if (rate < 10 && rounded === '10.0') return '<10'
  if (rate > 30 && rounded === '30.0') return '>30'
  return rounded
}
