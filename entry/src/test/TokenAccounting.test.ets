import { describe, it, expect } from '@ohos/hypium'
import { AttachmentType, ChatMessage, MessageAttachment, MessageRole } from '../main/ets/models/ChatModels'
import {
  buildContextUsageFromRequestTokens,
  estimateExtraPromptTokens,
  resolveContextInputBudgetTokens,
  resolveContextWindowTokens,
  resolveRequestMaxOutputTokens
} from '../main/ets/utils/ContextWindowUtils'
import {
  estimateProviderManagedAttachmentTokens,
  estimateTextTokens,
  RequestTokenUsageTracker
} from '../main/ets/utils/ModelBillingUtils'
import { ContextCompactionService } from '../main/ets/services/ContextCompactionService'

export default function tokenAccountingTest() {
  describe('tokenAccountingTest', () => {
    it('does_not_inflate_a_configured_small_context_window', 0, () => {
      expect(resolveContextWindowTokens(1024, 500000)).assertEqual(1024)
      expect(resolveContextWindowTokens(0, 500000)).assertEqual(0)
    })

    it('reserves_output_tokens_from_the_effective_input_budget', 0, () => {
      expect(resolveContextInputBudgetTokens(128000, 32768)).assertEqual(95232)
      const usage = buildContextUsageFromRequestTokens(76186, 128000, 32768, 80)
      expect(usage.limitTokens).assertEqual(95232)
      expect(usage.modelWindowTokens).assertEqual(128000)
      expect(usage.outputReserveTokens).assertEqual(32768)
      expect(usage.overThreshold).assertEqual(true)
    })

    it('tightens_max_output_against_the_actual_request_input', 0, () => {
      expect(resolveRequestMaxOutputTokens(32768, 128000, 120000)).assertEqual(8000)
      expect(resolveRequestMaxOutputTokens(4096, 0, 999999)).assertEqual(4096)
    })

    it('counts_the_complete_compaction_summary_wrapper', 0, () => {
      const summary = '用户正在修复上下文统计，已经确认必须包含系统提示、工具和当前输入。'
      const wrapped = ContextCompactionService.buildSummaryRequestPrompt(summary)
      expect(estimateExtraPromptTokens([wrapped]) > estimateExtraPromptTokens([summary])).assertEqual(true)
    })

    it('counts_whitespace_that_is_sent_to_the_tokenizer', 0, () => {
      expect(estimateTextTokens('a               b') > estimateTextTokens('ab')).assertEqual(true)
    })

    it('does_not_convert_binary_file_size_into_context_tokens', 0, () => {
      const small = new MessageAttachment(
        'small',
        AttachmentType.FILE,
        'report.pdf',
        '/tmp/report.pdf',
        'application/pdf',
        1024
      )
      const large = new MessageAttachment(
        'large',
        AttachmentType.FILE,
        'report.pdf',
        '/tmp/report.pdf',
        'application/pdf',
        100 * 1024 * 1024
      )
      expect(estimateProviderManagedAttachmentTokens(small))
        .assertEqual(estimateProviderManagedAttachmentTokens(large))
    })

    it('uses_actual_request_tokens_for_manual_compaction_accounting', 0, () => {
      const message = new ChatMessage('user', MessageRole.USER, '需要压缩的历史内容')
      const summary = '用户正在修复附件上下文统计；附件由工具读取，摘要必须保留工具返回的实际文本和当前任务进度。'
      const result = ContextCompactionService.getInstance().buildManualCompaction(
        'session-token-accounting',
        [message],
        summary,
        4000,
        0,
        900
      )
      expect(result.applied).assertEqual(true)
      expect(result.beforeTokens).assertEqual(900)
    })

    it('accumulates_actual_and_fallback_usage_across_api_rounds', 0, () => {
      const tracker = new RequestTokenUsageTracker()
      const message = new ChatMessage('assistant', MessageRole.ASSISTANT, '')

      tracker.beginRound(100)
      tracker.updateCurrentRoundUsage(90, 10)
      tracker.finishRound(99)
      tracker.beginRound(200)
      tracker.finishRound(20)
      tracker.applyToMessage(message)

      expect(message.estimatedInputTokens).assertEqual(290)
      expect(message.estimatedOutputTokens).assertEqual(30)
      expect(message.tokenUsageTracked).assertEqual(true)
      expect(message.tokenUsageExact).assertEqual(false)
    })
  })
}
