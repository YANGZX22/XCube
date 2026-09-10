import { describe, it, expect } from '@ohos/hypium'
import { ToolCallStreamState } from '../main/ets/services/AIApiService'
import { isPossibleToolArgumentsJsonPrefix, mergeToolArgumentDelta } from '../main/ets/utils/ToolArgumentStreamUtils'
import { parseAskUserQuestions } from '../main/ets/utils/AskUserQuestionUtils'

export default function aiApiToolStreamStateTest() {
  describe('aiApiToolStreamStateTest', () => {
    it('preserves_nested_object_opening_in_ask_user_deltas', 0, () => {
      const stream = new ToolCallStreamState()
      const chunks = ['{"questions":[', '{"', 'id":"q1","question":"想测试什么？","selection_type":"text"', '}]}']
      chunks.forEach((chunk: string) => {
        stream.appendToolCallDelta({ index: 0, functionName: 'ask_user', arguments: chunk })
      })
      const args = stream.getAccumulatedToolCalls()[0].arguments
      expect(args).assertEqual(chunks.join(''))
      expect(parseAskUserQuestions(args).questions[0].question).assertEqual('想测试什么？')
    })

    it('preserves_json_for_each_character_and_every_two_way_split', 0, () => {
      const samples: string[] = [
        '{"questions":[{"id":"q1","question":"第一问？","options":["A","B"]},{"id":"q2","question":"第二问？"}]}',
        '{"a":{"a":{}}}',
        '[[],[[],[]]]',
        '{"content":"{\\"text\\":\\"aa\\"} \\u4f60\\n", "n":-0.25e+2,"ok":true,"x":null}',
        '{"spaces":"  ","quotes":"\\"\\"","braces":"{{[["}'
      ]
      samples.forEach((sample: string) => {
        let merged = ''
        for (let i = 0; i < sample.length; i++) {
          merged = mergeToolArgumentDelta(merged, sample.substring(i, i + 1))
          expect(isPossibleToolArgumentsJsonPrefix(sample.substring(0, i + 1))).assertEqual(true)
        }
        expect(merged).assertEqual(sample)
        for (let split = 1; split < sample.length; split++) {
          expect(mergeToolArgumentDelta(sample.substring(0, split), sample.substring(split))).assertEqual(sample)
        }
      })
    })

    it('does_not_treat_repeated_nested_prefix_as_snapshot', 0, () => {
      expect(mergeToolArgumentDelta('{"a":', '{"a":')).assertEqual('{"a":{"a":')
      expect(mergeToolArgumentDelta('{"questions":[', '{"')).assertEqual('{"questions":[{"')
      expect(mergeToolArgumentDelta('{"text":"{', '{')).assertEqual('{"text":"{{')
    })

    it('rejects_impossible_json_prefixes_but_allows_incomplete_values', 0, () => {
      const invalid = ['{{', '{"x":truX', '{"x":01', '{"x":"\\q', '{"x":1,}', '[1,]', '{}{}', '{"x":1e+}']
      invalid.forEach((sample: string) => { expect(isPossibleToolArgumentsJsonPrefix(sample)).assertEqual(false) })
      const incomplete = ['{', '{"', '{"x":', '{"x":-', '{"x":1.', '{"x":1e+', '{"x":"\\u12', '{"x":fals']
      incomplete.forEach((sample: string) => { expect(isPossibleToolArgumentsJsonPrefix(sample)).assertEqual(true) })
    })

    it('uses_explicit_final_snapshot_to_replace_argument_stream', 0, () => {
      const stream = new ToolCallStreamState()
      stream.appendToolCallDelta({ index: 0, functionName: 'ask_user', arguments: '{"questions":[' })
      const complete = '{"questions":[{"question":"确认继续？"}]}'
      stream.appendToolCallDelta({ index: 0, arguments: complete, argumentsAreSnapshot: true })
      expect(stream.getAccumulatedToolCalls()[0].arguments).assertEqual(complete)
    })

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
