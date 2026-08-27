import { describe, expect, it } from '@ohos/hypium'
import {
  buildDeepSeekWebSearchEndpoint,
  isDeepSeekProvider,
  parseDeepSeekWebSearchResponse
} from '../main/ets/utils/DeepSeekWebSearchUtils'

export default function deepSeekWebSearchUtilsTest() {
  describe('deepSeekWebSearchUtilsTest', () => {
    it('parses_structured_results_and_citation_snippets', 0, () => {
      const response = JSON.stringify({
        content: [
          {
            type: 'text',
            text: 'ignored prose',
            citations: [
              { url: 'https://example.com/a', cited_text: 'Citation snippet A' }
            ]
          },
          {
            type: 'web_search_tool_result',
            content: [
              {
                type: 'web_search_result',
                url: 'https://example.com/a',
                title: 'Result A',
                page_age: '2026-08-27'
              },
              {
                type: 'web_search_result',
                url: 'https://example.com/a',
                title: 'Duplicate A'
              },
              {
                type: 'web_search_result',
                url: 'https://example.com/b',
                title: 'Result B'
              }
            ]
          }
        ]
      })

      const result = parseDeepSeekWebSearchResponse(response, 10)
      expect(result.hasResultBlock).assertTrue()
      expect(result.sources.length).assertEqual(2)
      expect(result.sources[0].title).assertEqual('Result A')
      expect(result.sources[0].snippet).assertContain('Citation snippet A')
      expect(result.sources[0].snippet).assertContain('2026-08-27')
      expect(result.sources[1].url).assertEqual('https://example.com/b')
    })

    it('requires_a_structured_web_search_result_block', 0, () => {
      const result = parseDeepSeekWebSearchResponse('{"content":[{"type":"text","text":"answer"}]}', 5)
      expect(result.hasResultBlock).assertFalse()
      expect(result.sources.length).assertEqual(0)
    })

    it('normalizes_anthropic_compatible_endpoints', 0, () => {
      expect(buildDeepSeekWebSearchEndpoint('https://api.deepseek.com/anthropic'))
        .assertEqual('https://api.deepseek.com/anthropic/v1/messages')
      expect(buildDeepSeekWebSearchEndpoint('https://proxy.example.com/anthropic/v1/'))
        .assertEqual('https://proxy.example.com/anthropic/v1/messages')
      expect(buildDeepSeekWebSearchEndpoint('https://proxy.example.com/v1/messages'))
        .assertEqual('https://proxy.example.com/v1/messages')
    })

    it('recognizes_deepseek_provider_without_accepting_lookalike_hosts', 0, () => {
      expect(isDeepSeekProvider('custom', 'deepseek', 'https://proxy.example.com/v1')).assertTrue()
      expect(isDeepSeekProvider('custom', 'openai', 'https://api.deepseek.com/anthropic/v1')).assertTrue()
      expect(isDeepSeekProvider('custom', 'openai', 'https://api.deepseek.com.example.com/v1')).assertFalse()
    })
  })
}
