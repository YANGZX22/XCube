import { describe, it, expect } from '@ohos/hypium'
import { ToolCallStreamState } from '../main/ets/services/AIApiService'

export default function aiApiToolStreamStateTest() {
  describe('aiApiToolStreamStateTest', () => {
    it('keeps_interleaved_tool_deltas_isolated_per_stream_request', 0, () => {
      const leftStream = new ToolCallStreamState(true)
      const rightStream = new ToolCallStreamState(true)

      leftStream.appendToolCallDelta({
        index: 0,
        functionName: 'knowledge_',
        arguments: '{"query":"left'
      })
      rightStream.appendToolCallDelta({
        index: 0,
        functionName: 'web_search',
        arguments: '{"query":"right'
      })
      leftStream.appendToolCallDelta({
        index: 0,
        functionName: 'search',
        arguments: ' only"}'
      })
      rightStream.appendToolCallDelta({
        index: 0,
        arguments: ' only"}'
      })

      const leftCalls = leftStream.getAccumulatedToolCalls()
      const rightCalls = rightStream.getAccumulatedToolCalls()

      expect(leftCalls.length).assertEqual(1)
      expect(leftCalls[0].id.startsWith('tool_call_')).assertEqual(true)
      expect(leftCalls[0].functionName).assertEqual('knowledge_search')
      expect(leftCalls[0].arguments).assertEqual('{"query":"left only"}')
      expect(leftCalls[0].arguments.includes('right')).assertEqual(false)

      expect(rightCalls.length).assertEqual(1)
      expect(rightCalls[0].id.startsWith('tool_call_')).assertEqual(true)
      expect(rightCalls[0].id === leftCalls[0].id).assertEqual(false)
      expect(rightCalls[0].functionName).assertEqual('web_search')
      expect(rightCalls[0].arguments).assertEqual('{"query":"right only"}')
      expect(rightCalls[0].arguments.includes('left')).assertEqual(false)
    })
  })
}
