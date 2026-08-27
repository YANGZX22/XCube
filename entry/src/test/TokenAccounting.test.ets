import { describe, it, expect } from '@ohos/hypium'
import {
  AttachmentType,
  BillingTimePeriod,
  ChatMessage,
  MessageAttachment,
  MessageRole,
  ModelInfo
} from '../main/ets/models/ChatModels'
import {
  buildContextUsageFromRequestTokens,
  estimateExtraPromptTokens,
  resolveContextInputBudgetTokens,
  resolveContextWindowTokens,
  resolveRequestMaxOutputTokens
} from '../main/ets/utils/ContextWindowUtils'
import {
  applyEstimatedBilling,
  calculateCacheAwareEstimatedCost,
  doBillingPeakPeriodsOverlap,
  estimateProviderManagedAttachmentTokens,
  estimateTextTokens,
  formatCacheHitPercent,
  hasOverlappingBillingPeakPeriods,
  isBillingPeakMinute,
  isDeviceLocalRestDay,
  ModelBillingSnapshot,
  resolveModelBillingPrices,
  RequestTokenUsageTracker
} from '../main/ets/utils/ModelBillingUtils'
import { ContextCompactionService } from '../main/ets/services/ContextCompactionService'

export default function tokenAccountingTest() {
  describe('tokenAccountingTest', () => {
    it('uses_the_configured_window_or_the_256k_default', 0, () => {
      expect(resolveContextWindowTokens(1024, 500000)).assertEqual(1024)
      const defaultWindow = resolveContextWindowTokens(0, 500000)
      expect(defaultWindow).assertEqual(256000)
      expect(resolveContextInputBudgetTokens(defaultWindow, 32768)).assertEqual(223232)
      expect(resolveContextWindowTokens(Number.NaN, 200000)).assertEqual(200000)
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

    it('tracks_disjoint_cache_usage_buckets_across_api_rounds', 0, () => {
      const tracker = new RequestTokenUsageTracker()
      const message = new ChatMessage('assistant-cache', MessageRole.ASSISTANT, '')

      tracker.beginRound(100)
      tracker.updateCurrentRoundUsage(100, 10, 90, 0)
      tracker.finishRound(10)
      tracker.beginRound(100)
      tracker.updateCurrentRoundUsage(100, 5, 0, 100)
      tracker.finishRound(5)
      tracker.applyToMessage(message)

      expect(message.uncachedInputTokens).assertEqual(10)
      expect(message.cacheReadTokens).assertEqual(90)
      expect(message.cacheWriteTokens).assertEqual(100)
      expect(formatCacheHitPercent(
        message.uncachedInputTokens,
        message.cacheReadTokens,
        message.cacheWriteTokens
      )).assertEqual('45')
    })

    it('formats_cache_hit_rounding_like_deepseek_harness', 0, () => {
      expect(formatCacheHitPercent(10, 90, 0)).assertEqual('90')
      expect(formatCacheHitPercent(5, 995, 0)).assertEqual('99.5')
      expect(formatCacheHitPercent(5, 9995, 0)).assertEqual('99.95')
      expect(formatCacheHitPercent(1, 19999, 0)).assertEqual('99.995')
      expect(formatCacheHitPercent(0, 10000, 0)).assertEqual('100')
    })

    it('prices_cache_hit_input_separately_and_keeps_one_output_price', 0, () => {
      const cost = calculateCacheAwareEstimatedCost(
        200,
        50,
        10,
        90,
        100,
        10,
        20,
        2
      )
      // 未命中输入=(10 未缓存 + 100 写入)，命中输入=90，输出统一按 20 计费。
      expect(Math.round(cost * 1_000_000)).assertEqual(2280)
    })

    it('bills_unclassified_estimated_input_as_cache_miss', 0, () => {
      const model = new ModelInfo('billing-cache-model', 'Billing cache model')
      model.billingEnabled = true
      model.inputPricePerMillion = 10
      model.outputPricePerMillion = 20
      model.billingCacheHitEnabled = true
      model.cacheReadPricePerMillion = 2

      const message = new ChatMessage('billing-cache-message', MessageRole.ASSISTANT, '')
      message.tokenUsageTracked = true
      message.estimatedInputTokens = 300
      message.estimatedOutputTokens = 50
      message.uncachedInputTokens = 10
      message.cacheReadTokens = 90
      message.cacheWriteTokens = 0

      applyEstimatedBilling(message, [], new ModelBillingSnapshot(model))
      // 100 个已分类输入之外的 200 个本地估算输入按未命中价计费。
      expect(Math.round(message.estimatedCost * 1_000_000)).assertEqual(3280)
    })

    it('resolves_peak_and_off_peak_prices_from_device_local_time', 0, () => {
      const model = new ModelInfo('billing-model', 'Billing model')
      model.billingTimeOfUseEnabled = true
      model.billingPeakPeriods = [new BillingTimePeriod(8 * 60, 22 * 60)]
      model.billingPeakInputPricePerMillion = 10
      model.billingPeakOutputPricePerMillion = 20
      model.billingPeakCacheReadPricePerMillion = 1
      model.billingOffPeakInputPricePerMillion = 4
      model.billingOffPeakOutputPricePerMillion = 8
      model.billingOffPeakCacheReadPricePerMillion = 0.4

      const peak = resolveModelBillingPrices(model, new Date(2026, 0, 1, 12, 30))
      const offPeak = resolveModelBillingPrices(model, new Date(2026, 0, 1, 23, 30))

      expect(peak.isPeak).assertEqual(true)
      expect(peak.inputPricePerMillion).assertEqual(10)
      expect(peak.outputPricePerMillion).assertEqual(20)
      expect(peak.cacheReadPricePerMillion).assertEqual(1)
      expect(offPeak.isPeak).assertEqual(false)
      expect(offPeak.inputPricePerMillion).assertEqual(4)
      expect(offPeak.outputPricePerMillion).assertEqual(8)
      expect(offPeak.cacheReadPricePerMillion).assertEqual(0.4)
    })

    it('supports_peak_periods_that_cross_midnight', 0, () => {
      expect(isBillingPeakMinute(23 * 60, 22 * 60, 8 * 60)).assertEqual(true)
      expect(isBillingPeakMinute(7 * 60 + 59, 22 * 60, 8 * 60)).assertEqual(true)
      expect(isBillingPeakMinute(8 * 60, 22 * 60, 8 * 60)).assertEqual(false)
      expect(isBillingPeakMinute(12 * 60, 22 * 60, 8 * 60)).assertEqual(false)
      expect(isBillingPeakMinute(12 * 60, 8 * 60, 8 * 60)).assertEqual(false)
    })

    it('uses_off_peak_prices_on_device_local_rest_days_when_enabled', 0, () => {
      const model = new ModelInfo('billing-model', 'Billing model')
      model.billingTimeOfUseEnabled = true
      model.billingPeakPeriods = [new BillingTimePeriod(8 * 60, 22 * 60)]
      model.billingPeakInputPricePerMillion = 10
      model.billingPeakOutputPricePerMillion = 20
      model.billingOffPeakInputPricePerMillion = 4
      model.billingOffPeakOutputPricePerMillion = 8

      const saturday = new Date(2026, 0, 3, 12, 30)
      const monday = new Date(2026, 0, 5, 12, 30)
      expect(isDeviceLocalRestDay(saturday)).assertEqual(true)
      expect(isDeviceLocalRestDay(monday)).assertEqual(false)
      expect(resolveModelBillingPrices(model, saturday).isPeak).assertEqual(true)

      model.billingRestDayOffPeakEnabled = true
      expect(resolveModelBillingPrices(model, saturday).isPeak).assertEqual(false)
      expect(resolveModelBillingPrices(model, saturday).inputPricePerMillion).assertEqual(4)
      expect(resolveModelBillingPrices(model, monday).isPeak).assertEqual(true)
      expect(resolveModelBillingPrices(model, monday).inputPricePerMillion).assertEqual(10)
    })

    it('detects_overlapping_peak_periods_including_cross_midnight_ranges', 0, () => {
      const morning = new BillingTimePeriod(8 * 60, 10 * 60)
      const overlapping = new BillingTimePeriod(9 * 60, 11 * 60)
      const touching = new BillingTimePeriod(10 * 60, 12 * 60)
      const overnight = new BillingTimePeriod(22 * 60, 7 * 60)
      const lateNight = new BillingTimePeriod(23 * 60, 23 * 60 + 30)
      const empty = new BillingTimePeriod(8 * 60, 8 * 60)

      expect(doBillingPeakPeriodsOverlap(morning, overlapping)).assertEqual(true)
      expect(doBillingPeakPeriodsOverlap(morning, touching)).assertEqual(false)
      expect(doBillingPeakPeriodsOverlap(overnight, lateNight)).assertEqual(true)
      expect(doBillingPeakPeriodsOverlap(morning, overnight)).assertEqual(false)
      expect(doBillingPeakPeriodsOverlap(morning, empty)).assertEqual(false)
      expect(hasOverlappingBillingPeakPeriods([morning, touching, overnight])).assertEqual(false)
      expect(hasOverlappingBillingPeakPeriods([morning, overlapping, overnight])).assertEqual(true)
    })

    it('round_trips_time_of_use_billing_configuration', 0, () => {
      const model = new ModelInfo('billing-model', 'Billing model')
      model.billingTimeOfUseEnabled = true
      model.billingCacheHitEnabled = true
      model.cacheReadPricePerMillion = 0.8
      model.billingRestDayOffPeakEnabled = true
      model.billingPeakPeriods = [
        new BillingTimePeriod(7 * 60, 9 * 60),
        new BillingTimePeriod(12 * 60, 14 * 60),
        new BillingTimePeriod(21 * 60 + 30, 7 * 60 + 15)
      ]
      model.billingPeakInputPricePerMillion = 12.5
      model.billingPeakOutputPricePerMillion = 25
      model.billingPeakCacheReadPricePerMillion = 1.25
      model.billingOffPeakInputPricePerMillion = 3.25
      model.billingOffPeakOutputPricePerMillion = 6.5
      model.billingOffPeakCacheReadPricePerMillion = 0.325

      const restored = ModelInfo.fromExtendedJson(model.toExtendedJson())
      expect(restored.billingTimeOfUseEnabled).assertEqual(true)
      expect(restored.billingCacheHitEnabled).assertEqual(true)
      expect(restored.cacheReadPricePerMillion).assertEqual(0.8)
      expect(restored.billingRestDayOffPeakEnabled).assertEqual(true)
      expect(restored.billingPeakPeriods.length).assertEqual(3)
      expect(restored.billingPeakPeriods[0].startMinutes).assertEqual(7 * 60)
      expect(restored.billingPeakPeriods[1].endMinutes).assertEqual(14 * 60)
      expect(restored.billingPeakPeriods[2].startMinutes).assertEqual(21 * 60 + 30)
      expect(restored.billingPeakPeriods[2].endMinutes).assertEqual(7 * 60 + 15)
      expect(restored.billingPeakInputPricePerMillion).assertEqual(12.5)
      expect(restored.billingPeakOutputPricePerMillion).assertEqual(25)
      expect(restored.billingPeakCacheReadPricePerMillion).assertEqual(1.25)
      expect(restored.billingOffPeakInputPricePerMillion).assertEqual(3.25)
      expect(restored.billingOffPeakOutputPricePerMillion).assertEqual(6.5)
      expect(restored.billingOffPeakCacheReadPricePerMillion).assertEqual(0.325)
    })
  })
}
