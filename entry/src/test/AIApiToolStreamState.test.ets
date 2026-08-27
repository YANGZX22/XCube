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

    it('merges_cumulative_argument_snapshots_without_concatenating_json_objects', 0, () => {
      const stream = new ToolCallStreamState(true)
      stream.appendToolCallDelta({
        index: 0,
        functionName: 'python_sandbox',
        arguments: '{"action":"write_file","path":"main.py","content":"pri'
      })
      stream.appendToolCallDelta({
        index: 0,
        arguments: '{"action":"write_file","path":"main.py","content":"print(42)"}'
      })
      stream.appendToolCallDelta({
        index: 0,
        arguments: '{"action":"write_file","path":"main.py","content":"print(42)"}'
      })

      const calls = stream.getAccumulatedToolCalls()
      expect(calls.length).assertEqual(1)
      expect(calls[0].arguments)
        .assertEqual('{"action":"write_file","path":"main.py","content":"print(42)"}')
      const parsed = JSON.parse(calls[0].arguments) as Record<string, string>
      expect(parsed.content).assertEqual('print(42)')
    })

    it('keeps_large_incremental_tool_arguments_without_an_app_side_length_cutoff', 0, () => {
      const stream = new ToolCallStreamState(true)
      const content = 'x'.repeat(192 * 1024)
      const argumentsJson = JSON.stringify({
        action: 'write_file',
        path: 'large.txt',
        content: content
      })
      const chunkSize = 4096
      for (let start = 0; start < argumentsJson.length; start += chunkSize) {
        stream.appendToolCallDelta({
          index: 0,
          functionName: start === 0 ? 'python_sandbox' : undefined,
          arguments: argumentsJson.substring(start, Math.min(argumentsJson.length, start + chunkSize))
        })
      }

      const calls = stream.getAccumulatedToolCalls()
      expect(calls[0].arguments.length).assertEqual(argumentsJson.length)
      const parsed = JSON.parse(calls[0].arguments) as Record<string, string>
      expect(parsed.content.length).assertEqual(content.length)
    })
  })
}
