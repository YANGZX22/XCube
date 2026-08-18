import { describe, expect, it } from '@ohos/hypium'
import {
  AssistantResponseSegment,
  AssistantResponseSegmentJson,
  AssistantResponseSegmentType,
  ChatMessage,
  MessageRole
} from '../main/ets/models/ChatModels'

export default function responseTimelineTest() {
  describe('responseTimelineTest', () => {
    it('round_trips_response_history_without_losing_order', 0, () => {
      const message = new ChatMessage('assistant-timeline', MessageRole.ASSISTANT, '最终输出')
      message.responseSegments.push(new AssistantResponseSegment(
        'reasoning-1', AssistantResponseSegmentType.REASONING, '第一轮思考'
      ))
      message.responseSegments.push(new AssistantResponseSegment(
        'tools-1', AssistantResponseSegmentType.TOOL_CALLS, '', ['call-1', 'call-2']
      ))
      message.responseSegments.push(new AssistantResponseSegment(
        'content-1', AssistantResponseSegmentType.CONTENT, '最终输出'
      ))

      const serialized: AssistantResponseSegmentJson[] = []
      for (let i = 0; i < message.responseSegments.length; i++) {
        serialized.push(message.responseSegments[i].toJson())
      }
      const restored: AssistantResponseSegment[] = []
      for (let i = 0; i < serialized.length; i++) {
        restored.push(AssistantResponseSegment.fromJson(serialized[i]))
      }

      expect(restored.length).assertEqual(3)
      expect(restored[0].type).assertEqual(AssistantResponseSegmentType.REASONING)
      expect(restored[1].type).assertEqual(AssistantResponseSegmentType.TOOL_CALLS)
      expect(restored[1].toolCallIds.join(',')).assertEqual('call-1,call-2')
      expect(restored[2].content).assertEqual('最终输出')
    })
  })
}
