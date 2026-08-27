import { describe, expect, it } from '@ohos/hypium'
import { ApiStyle } from '../main/ets/models/ChatModels'
import { ToolCallStreamState } from '../main/ets/services/AIApiService'
import {
  isKnownReasoningModelId,
  ReasoningControlMode,
  resolveReasoningControlMode,
  supportsOpenAIUsageInStreaming
} from '../main/ets/services/ProviderCompatibilityRegistry'
import {
  extractSseDataPayload,
  joinOpenAIStreamReasoningDetails,
  normalizeOpenAIResponsesStreamEvent,
  normalizeOpenAIStreamText,
  normalizeSseLineEndings,
  splitOpenAIStreamContent,
  stripSseBom
} from '../main/ets/utils/OpenAIStreamCompatibilityUtils'

export default function openAIStreamCompatibilityTest() {
  describe('openAIStreamCompatibilityTest', () => {
    it('normalizes_standard_and_part_array_chat_completion_text', 0, () => {
      expect(normalizeOpenAIStreamText('Hello')).assertEqual('Hello')
      expect(normalizeOpenAIStreamText([
        { type: 'text', text: 'Hello' },
        { type: 'output_text', text: ' there' }
      ])).assertEqual('Hello there')
      expect(normalizeOpenAIStreamText({ type: 'text', text: 'single part' })).assertEqual('single part')
      const split = splitOpenAIStreamContent([
        { type: 'reasoning', text: 'think' },
        { type: 'text', text: 'answer' }
      ])
      expect(split.reasoningContent).assertEqual('think')
      expect(split.content).assertEqual('answer')
      expect(joinOpenAIStreamReasoningDetails([
        { type: 'reasoning.text', text: 'Think' },
        { type: 'reasoning.text', text: ' again' }
      ])).assertEqual('Think again')
    })

    it('normalizes_sse_line_endings_and_utf8_bom', 0, () => {
      expect(normalizeSseLineEndings('data: one\r\ndata: two\rdata: three'))
        .assertEqual('data: one\ndata: two\ndata: three')
      expect(stripSseBom('\uFEFFdata: {"ok":true}')).assertEqual('data: {"ok":true}')
      expect(extractSseDataPayload(
        'data: {"choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}'
      )).assertEqual('{"choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}')
      expect(extractSseDataPayload('data: [DONE]')).assertEqual('')
    })

    it('keeps_optional_stream_usage_off_for_unknown_compatible_gateways', 0, () => {
      expect(supportsOpenAIUsageInStreaming({
        providerId: 'custom_1',
        baseUrl: 'https://gateway.example.com/v1',
        apiStyle: ApiStyle.OPENAI
      })).assertFalse()
      expect(supportsOpenAIUsageInStreaming({
        providerId: 'deepseek',
        baseUrl: 'https://api.deepseek.com/v1',
        apiStyle: ApiStyle.OPENAI
      })).assertTrue()
    })

    it('recognizes_routed_openai_reasoning_model_ids', 0, () => {
      expect(isKnownReasoningModelId('openai/gpt-5.4-mini')).assertTrue()
      expect(resolveReasoningControlMode({
        providerId: 'custom_1',
        baseUrl: 'https://api.ofox.ai/v1',
        apiStyle: ApiStyle.OPENAI
      }, 'openai/gpt-5.4-mini', false)).assertEqual(ReasoningControlMode.EFFORT)
    })

    it('normalizes_responses_text_reasoning_and_tool_argument_events', 0, () => {
      const textEvent = normalizeOpenAIResponsesStreamEvent({
        type: 'response.output_text.delta',
        delta: '你'
      })
      const reasoningEvent = normalizeOpenAIResponsesStreamEvent({
        type: 'response.reasoning_summary_text.delta',
        delta: '先分析'
      })
      expect(textEvent.content).assertEqual('你')
      expect(reasoningEvent.reasoningContent).assertEqual('先分析')

      const state = new ToolCallStreamState(true)
      const added = normalizeOpenAIResponsesStreamEvent({
        type: 'response.output_item.added',
        output_index: 0,
        item: {
          type: 'function_call',
          id: 'fc_1',
          call_id: 'call_1',
          name: 'get_weather',
          arguments: ''
        }
      })
      const delta = normalizeOpenAIResponsesStreamEvent({
        type: 'response.function_call_arguments.delta',
        output_index: 0,
        call_id: 'call_1',
        delta: '{"location":"\u5317\u4eac"}'
      })
      state.appendToolCallDelta(added.toolCallDeltas[0])
      state.appendToolCallDelta(delta.toolCallDeltas[0])

      const calls = state.getAccumulatedToolCalls()
      expect(calls.length).assertEqual(1)
      expect(calls[0].id).assertEqual('call_1')
      expect(calls[0].functionName).assertEqual('get_weather')
      expect(calls[0].arguments).assertEqual('{"location":"\u5317\u4eac"}')
    })
  })
}
