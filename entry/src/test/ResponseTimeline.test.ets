import { describe, expect, it } from '@ohos/hypium'
import {
  countReplySteps, formatReplySpeed, getReplySpeedTier, ReplySpeedTier, replyTokensPerSecond
} from '../main/ets/utils/ReplyStatistics'
import { getMessageCacheHitPercent, RequestTokenUsageTracker } from '../main/ets/utils/ModelBillingUtils'
import { shouldShowMessageHeader } from '../main/ets/utils/MessageListUtils'
import {
  AssistantResponseSegment,
  AssistantResponseSegmentJson,
  AssistantResponseSegmentType,
  ChatMessage,
  MessageRole,
  ToolCall
} from '../main/ets/models/ChatModels'

export default function responseTimelineTest() {
  describe('responseTimelineTest', () => {
    it('freezes_elapsed_time_at_completion_or_stop', 0, () => {
      const message = new ChatMessage('timed', MessageRole.ASSISTANT, '')
      expect(message.elapsedGenerationMs()).assertEqual(-1)
      message.startGeneration(1000)
      expect(message.elapsedGenerationMs(1350)).assertEqual(350)
      message.finishGeneration(66500)
      message.finishGeneration(100000)
      expect(message.elapsedGenerationMs(120000)).assertEqual(65500)
      expect(replyTokensPerSecond(message)).assertEqual(undefined)
      expect(shouldShowMessageHeader(message)).assertTrue()
      expect(shouldShowMessageHeader(new ChatMessage('user', MessageRole.USER, ''))).assertFalse()
    })

    it('averages_primary_model_rounds_across_tool_waits_and_auxiliary_output', 0, () => {
      const message = new ChatMessage('timed-tools', MessageRole.ASSISTANT, '')
      const tracker = new RequestTokenUsageTracker(message)
      message.startGeneration(1000)
      tracker.beginRound(100, 2000)
      tracker.addEstimatedOutput(40)
      expect(replyTokensPerSecond(message, 2000)).assertEqual(undefined)
      expect(replyTokensPerSecond(message, 4000)).assertEqual(20)
      tracker.updateCurrentRoundUsage(100, 60)
      tracker.finishRound(40, 5000)
      tracker.applyToMessage()
      expect(replyTokensPerSecond(message, 25000)).assertEqual(20)
      tracker.addCompletedUsage(80, 300, true)
      tracker.applyToMessage()
      expect(message.estimatedOutputTokens).assertEqual(360)
      expect(replyTokensPerSecond(message, 65000)).assertEqual(20)
      tracker.beginRound(500, 65000)
      tracker.updateCurrentRoundUsage(500, 140)
      tracker.finishRound(140, 72000)
      tracker.applyToMessage()
      message.finishGeneration(73000)
      expect(message.generationDurationMs).assertEqual(72000)
      expect(message.modelDurationMs).assertEqual(10000)
      expect(message.estimatedOutputTokens).assertEqual(500)
      expect(replyTokensPerSecond(message, 90000)).assertEqual(20)
      expect(getReplySpeedTier(replyTokensPerSecond(message))).assertEqual(ReplySpeedTier.TURTLE)
    })

    it('freezes_model_time_on_stop_and_preserves_unknown_historical_timing', 0, () => {
      const message = new ChatMessage('interrupted', MessageRole.ASSISTANT, '')
      message.estimatedOutputTokens = 50
      message.generationDurationMs = 30000
      expect(replyTokensPerSecond(message)).assertEqual(undefined)

      const tracker = new RequestTokenUsageTracker(message)
      message.startGeneration(1000)
      tracker.beginRound(20, 5000)
      tracker.addEstimatedOutput(5)
      message.finishGeneration(5250)
      tracker.finishRound(5, 7000)
      tracker.applyToMessage()
      expect(message.generationDurationMs).assertEqual(4250)
      expect(message.elapsedModelGenerationMs(100000)).assertEqual(250)
      expect(replyTokensPerSecond(message, 100000)).assertEqual(20)
    })

    it('counts_response_segments_and_distinct_calls_including_parallel_tools', 0, () => {
      const message = new ChatMessage('steps', MessageRole.ASSISTANT, 'Final answer')
      message.reasoningContent = 'Latest thought'
      message.responseSegments = [
        new AssistantResponseSegment('r1', AssistantResponseSegmentType.REASONING, 'First thought'),
        new AssistantResponseSegment('t', AssistantResponseSegmentType.TOOL_CALLS, '', ['a', 'b']),
        new AssistantResponseSegment('g', AssistantResponseSegmentType.USER_GUIDANCE, 'A correction'),
        new AssistantResponseSegment('compact', AssistantResponseSegmentType.CONTEXT_COMPACTION, 'completed'),
        new AssistantResponseSegment('empty', AssistantResponseSegmentType.CONTENT, '  '),
        new AssistantResponseSegment('r2', AssistantResponseSegmentType.REASONING, 'Latest thought'),
        new AssistantResponseSegment('c', AssistantResponseSegmentType.CONTENT, 'Final answer')
      ]
      message.toolCalls = [new ToolCall('a', 'search'), new ToolCall('child', 'read_file')]
      const steps = countReplySteps(message)
      expect(steps.reasoning).assertEqual(2)
      expect(steps.answers).assertEqual(1)
      expect(steps.tools).assertEqual(3)
      expect(steps.total).assertEqual(6)
      message.responseSegments = []
      expect(countReplySteps(message).total).assertEqual(4)
    })

    it('matches_speed_icons_to_the_displayed_rate_at_both_cutoffs', 0, () => {
      expect(getReplySpeedTier(undefined)).assertEqual(ReplySpeedTier.UNKNOWN)
      expect(getReplySpeedTier(0)).assertEqual(ReplySpeedTier.SNAIL)
      expect(getReplySpeedTier(9.99)).assertEqual(ReplySpeedTier.SNAIL)
      expect(formatReplySpeed(9.99)).assertEqual('<10')
      expect(getReplySpeedTier(10)).assertEqual(ReplySpeedTier.TURTLE)
      expect(formatReplySpeed(10)).assertEqual('10.0')
      expect(getReplySpeedTier(30)).assertEqual(ReplySpeedTier.TURTLE)
      expect(formatReplySpeed(30)).assertEqual('30.0')
      expect(getReplySpeedTier(30.01)).assertEqual(ReplySpeedTier.RABBIT)
      expect(formatReplySpeed(30.01)).assertEqual('>30')
      expect(formatReplySpeed(42.72)).assertEqual('42.7')
    })

    it('replaces_live_estimates_with_usage_and_keeps_completed_rounds', 0, () => {
      const message = new ChatMessage('usage', MessageRole.ASSISTANT, '')
      const tracker = new RequestTokenUsageTracker(message)
      tracker.beginRound(20)
      tracker.addEstimatedOutput(5)
      tracker.applyToMessage()
      expect(message.estimatedOutputTokens).assertEqual(5)
      expect(message.tokenUsageExact).assertFalse()
      tracker.updateCurrentRoundUsage(18, 4)
      tracker.applyToMessage()
      tracker.addEstimatedOutput(3)
      expect(message.estimatedOutputTokens).assertEqual(4)
      expect(message.tokenUsageExact).assertTrue()
      tracker.finishRound(8)
      tracker.beginRound(30)
      tracker.addEstimatedOutput(2)
      tracker.applyToMessage()
      expect(message.estimatedInputTokens).assertEqual(48)
      expect(message.estimatedOutputTokens).assertEqual(6)
      expect(message.tokenUsageExact).assertFalse()
    })

    it('keeps_cache_hit_counts_and_rates_on_the_same_reported_input_across_rounds', 0, () => {
      const message = new ChatMessage('cache', MessageRole.ASSISTANT, '')
      const tracker = new RequestTokenUsageTracker(message)
      tracker.beginRound(200)
      tracker.applyToMessage()
      expect(getMessageCacheHitPercent(message)).assertEqual(null)
      tracker.updateCurrentRoundUsage(100, 4, 0, 20)
      tracker.finishRound(4)
      tracker.applyToMessage()
      expect(message.cacheReadTokens).assertEqual(0)
      expect(getMessageCacheHitPercent(message)).assertEqual('0')

      tracker.addCompletedUsage(300, 10, true, 240, 20)
      tracker.beginRound(900)
      tracker.applyToMessage()
      expect(message.estimatedInputTokens).assertEqual(1300)
      expect(message.cacheReadTokens).assertEqual(240)
      expect(getMessageCacheHitPercent(message)).assertEqual('60')
    })

    it('follows_the_current_reasoning_segment_across_tool_rounds', 0, () => {
      const message = new ChatMessage('rounds', MessageRole.ASSISTANT, '')
      message.isGenerating = true
      expect(message.isStreamingReasoning()).assertFalse()
      message.responseSegments.push(new AssistantResponseSegment('r1', AssistantResponseSegmentType.REASONING, '先检索'))
      expect(message.isStreamingReasoning()).assertTrue()
      message.responseSegments.push(new AssistantResponseSegment('t', AssistantResponseSegmentType.TOOL_CALLS, '', ['call']))
      expect(message.isStreamingReasoning()).assertFalse()
      message.responseSegments.push(new AssistantResponseSegment('r2', AssistantResponseSegmentType.REASONING, '整理结果'))
      expect(message.isStreamingReasoning()).assertTrue()
      message.isGenerating = false
      expect(message.isStreamingReasoning()).assertFalse()
      message.isGenerating = true
      message.responseSegments.push(new AssistantResponseSegment('c', AssistantResponseSegmentType.CONTENT, '正文'))
      expect(message.isStreamingReasoning()).assertFalse()
    })

    it('recognizes_live_reasoning_in_messages_without_segments', 0, () => {
      const message = new ChatMessage('legacy', MessageRole.ASSISTANT, '')
      message.isGenerating = true
      message.reasoningContent = '思考'
      expect(message.isStreamingReasoning()).assertTrue()
      message.isSearching = true
      expect(message.isStreamingReasoning()).assertFalse()
      message.isSearching = false
      message.content = '正文'
      expect(message.isStreamingReasoning()).assertFalse()
      message.content = ''
      message.toolCalls.push(new ToolCall('call', 'web_search'))
      expect(message.isStreamingReasoning()).assertFalse()
    })

    it('round_trips_response_history_without_losing_order', 0, () => {
      const message = new ChatMessage('assistant-timeline', MessageRole.ASSISTANT, '最终输出')
      message.responseSegments.push(new AssistantResponseSegment(
        'reasoning-1', AssistantResponseSegmentType.REASONING, '第一轮思考'
      ))
      message.responseSegments.push(new AssistantResponseSegment(
        'tools-1', AssistantResponseSegmentType.TOOL_CALLS, '', ['call-1', 'call-2']
      ))
      message.responseSegments.push(new AssistantResponseSegment(
        'compaction-1', AssistantResponseSegmentType.CONTEXT_COMPACTION, 'completed'
      ))
      message.responseSegments.push(new AssistantResponseSegment(
        'guidance-1', AssistantResponseSegmentType.USER_GUIDANCE, '先给结论'
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

      expect(restored.length).assertEqual(5)
      expect(restored[0].type).assertEqual(AssistantResponseSegmentType.REASONING)
      expect(restored[1].type).assertEqual(AssistantResponseSegmentType.TOOL_CALLS)
      expect(restored[1].toolCallIds.join(',')).assertEqual('call-1,call-2')
      expect(restored[2].type).assertEqual(AssistantResponseSegmentType.CONTEXT_COMPACTION)
      expect(restored[2].content).assertEqual('completed')
      expect(restored[3].type).assertEqual(AssistantResponseSegmentType.USER_GUIDANCE)
      expect(restored[3].content).assertEqual('先给结论')
      expect(restored[4].content).assertEqual('最终输出')
    })
  })
}
