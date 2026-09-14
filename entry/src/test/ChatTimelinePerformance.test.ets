import { describe, expect, it } from '@ohos/hypium'
import {
  AssistantResponseSegment,
  AssistantResponseSegmentType,
  ChatMessage,
  MessageRole,
  ToolCall,
  ToolResult
} from '../main/ets/models/ChatModels'
import {
  buildChatMessageContentRenderSignature,
  buildChatMessageRowRenderSignature
} from '../main/ets/components/chat/ChatMessageListDataSource'
import { encodeRenderText } from '../main/ets/utils/RenderTextSignatureUtils'
import { TimelineToolIndex } from '../main/ets/utils/TimelineToolIndex'

function signature(message: ChatMessage, editing: boolean = false, preview: string = ''): string {
  return buildChatMessageContentRenderSignature(message, editing, 'model', 15, 'theme', preview)
}

export default function chatTimelinePerformanceTest() {
  describe('chatTimelinePerformanceTest', () => {
    it('large_payloads_do_not_grow_render_signatures_with_text_size', 0, () => {
      const message = new ChatMessage('large', MessageRole.ASSISTANT, 'x'.repeat(1024))
      message.reasoningContent = 'r'.repeat(1024)
      message.toolCalls = [new ToolCall('call', 'python_sandbox', 'a'.repeat(1024))]
      message.toolResults = [new ToolResult('call', 't'.repeat(1024))]
      message.responseSegments = [new AssistantResponseSegment('reasoning',
        AssistantResponseSegmentType.REASONING, 'h'.repeat(1024))]
      const before = signature(message)
      message.content = 'x'.repeat(200000)
      message.reasoningContent = 'r'.repeat(200000)
      message.toolCalls[0].arguments = 'a'.repeat(200000)
      message.toolResults[0].content = 't'.repeat(200000)
      message.responseSegments[0].content = 'h'.repeat(200000)
      const after = signature(message)
      expect(after.length < before.length + 100).assertTrue()
      expect(after.length < 2048).assertTrue()
      expect(before === after).assertFalse()
      expect(signature(message)).assertEqual(after)
    })

    it('same_length_middle_edits_and_rollbacks_invalidate_long_text', 0, () => {
      const text = 'a'.repeat(500) + 'middle' + 'z'.repeat(500)
      const message = new ChatMessage('edit', MessageRole.ASSISTANT, text)
      const before = signature(message)
      message.content = 'a'.repeat(500) + 'MIDDLE' + 'z'.repeat(500)
      const edited = signature(message)
      expect(before === edited).assertFalse()
      expect(signature(message)).assertEqual(edited)
      message.content = text
      const restored = signature(message)
      expect(edited === restored).assertFalse()
      expect(signature(message)).assertEqual(restored)
      message.content = ''
      expect(restored === signature(message)).assertFalse()
    })

    it('historical_reasoning_arguments_and_results_can_change_independently', 0, () => {
      const text = 'x'.repeat(1024)
      const changed = text.substring(0, 500) + 'y' + text.substring(501)
      const message = new ChatMessage('history', MessageRole.ASSISTANT, text)
      message.reasoningContent = text
      message.toolCalls = [new ToolCall('call', 'tool', text)]
      message.toolResults = [new ToolResult('call', text)]
      message.responseSegments = [new AssistantResponseSegment('old', AssistantResponseSegmentType.REASONING, text)]
      let before = signature(message)
      message.reasoningContent = changed
      expect(before === signature(message)).assertFalse()
      before = signature(message)
      message.toolCalls[0].arguments = changed
      expect(before === signature(message)).assertFalse()
      before = signature(message)
      message.toolResults[0].content = changed
      expect(before === signature(message)).assertFalse()
      before = signature(message)
      message.responseSegments[0].content = changed
      expect(before === signature(message)).assertFalse()
    })

    it('text_revisions_are_scoped_and_replacement_objects_refresh', 0, () => {
      const message = new ChatMessage('owner', MessageRole.ASSISTANT, '')
      const text = 'x'.repeat(1024)
      const first = encodeRenderText(message, 'content', text)
      encodeRenderText(message, 'reasoning', text + 'new')
      expect(encodeRenderText(message, 'content', text)).assertEqual(first)
      const replacement = new ChatMessage('owner', MessageRole.ASSISTANT, '')
      expect(encodeRenderText(replacement, 'content', text) === first).assertFalse()
      encodeRenderText(message, 'content', '')
      expect(encodeRenderText(message, 'content', text) === first).assertFalse()
    })

    it('row_signature_reuses_precomputed_content_and_ignores_inactive_previews', 0, () => {
      const message = new ChatMessage('row', MessageRole.ASSISTANT, 'x'.repeat(4096))
      const content = signature(message)
      const full = buildChatMessageRowRenderSignature(message, false, true, false, false, false, false,
        'model', 15, 'theme')
      const reused = buildChatMessageRowRenderSignature(message, false, true, false, false, false, false,
        'model', 15, 'theme', '', [], '', '', 0, content)
      expect(reused).assertEqual(full)
      expect(signature(message, false, 'a'.repeat(1000))).assertEqual(content)
      expect(signature(message, true, 'a'.repeat(1000)) === signature(message, true, 'b'.repeat(1000))).assertFalse()
    })

    it('scoped_tools_keep_message_order_and_do_not_repeat_requested_ids', 0, () => {
      const calls = [new ToolCall('a', 'tool'), new ToolCall('child', 'tool'),
        new ToolCall('b', 'tool'), new ToolCall('a', 'tool')]
      const index = new TimelineToolIndex(calls, [])
      const selected = index.getCalls(['b', 'missing', 'a', 'a'])
      expect(selected.length).assertEqual(3)
      expect(selected[0] === calls[0]).assertTrue()
      expect(selected[1] === calls[2]).assertTrue()
      expect(selected[2] === calls[3]).assertTrue()
      expect(index.getCalls().length).assertEqual(4)
      expect(index.getCalls(['missing']).length).assertEqual(0)
    })

    it('tool_results_follow_ids_after_interleaving_and_collection_replacement', 0, () => {
      const calls = [new ToolCall('a', 'tool'), new ToolCall('b', 'tool')]
      const first = new ToolResult('a', 'first')
      const index = new TimelineToolIndex(calls, [new ToolResult('b', 'second'), first,
        new ToolResult('a', 'duplicate')])
      expect(index.getResult('a') === first).assertTrue()
      expect(index.getResult('b')?.content).assertEqual('second')
      expect(index.getResult('missing') === null).assertTrue()
      const replaced = new TimelineToolIndex([new ToolCall('c', 'tool'), calls[1]],
        [new ToolResult('c', 'replacement'), new ToolResult('b', 'second')])
      expect(replaced.getCalls(['a']).length).assertEqual(0)
      expect(replaced.getCalls(['c']).length).assertEqual(1)
      expect(replaced.getResult('c')?.content).assertEqual('replacement')
    })
  })
}
