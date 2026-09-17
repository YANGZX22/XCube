import { describe, it, expect } from '@ohos/hypium'
import { PromptLanguage, resolvePromptLanguage } from '../main/ets/utils/PromptLanguageUtils'
import {
  appendResponseLanguageSystemPrompt,
  buildCurrentTimeContext,
  getDefaultSystemPromptTemplate,
  getResponseLanguageSystemPrompt,
  normalizeSystemPromptTemplate,
  renderSystemPromptTemplate
} from '../main/ets/utils/SystemPromptTemplateUtils'
import { buildToolUsagePrompt, getTaskExecutionPrompt, ToolPromptOptions } from '../main/ets/config/AgentPrompts'
import { ContextCompactionService } from '../main/ets/services/ContextCompactionService'
import { ToolProgressGuard, getToolProgressStop, isToolProgressStop } from '../main/ets/utils/ToolProgressGuard'
import { buildConversationGoalSystemPrompt } from '../main/ets/utils/ConversationGoalUtils'

export default function promptLanguageTest() {
  describe('PromptLanguage', () => {
    it('uses_explicit_app_language_before_system_language', 0, () => {
      expect(resolvePromptLanguage('en-US', 'zh-CN')).assertEqual(PromptLanguage.EN_US)
      expect(resolvePromptLanguage('zh_CN', 'en-US')).assertEqual(PromptLanguage.ZH_CN)
    })

    it('follows_system_language_and_uses_english_for_other_locales', 0, () => {
      expect(resolvePromptLanguage('system', 'zh-Hant-TW')).assertEqual(PromptLanguage.ZH_CN)
      expect(resolvePromptLanguage('system', 'en-GB')).assertEqual(PromptLanguage.EN_US)
      expect(resolvePromptLanguage('default', 'ja-JP')).assertEqual(PromptLanguage.EN_US)
    })

    it('switches_saved_builtin_templates_but_preserves_custom_instructions', 0, () => {
      const zh = getDefaultSystemPromptTemplate(PromptLanguage.ZH_CN)
      const en = getDefaultSystemPromptTemplate(PromptLanguage.EN_US)
      expect(normalizeSystemPromptTemplate(zh, PromptLanguage.EN_US)).assertEqual(en)
      expect(normalizeSystemPromptTemplate(en, PromptLanguage.ZH_CN)).assertEqual(zh)
      const custom = 'Always answer in Japanese. 用户自定义身份。'
      expect(normalizeSystemPromptTemplate(custom, PromptLanguage.ZH_CN)).assertEqual(custom)
      expect(normalizeSystemPromptTemplate(custom, PromptLanguage.EN_US)).assertEqual(custom)
    })

    it('renders_dates_and_default_identity_in_the_selected_language', 0, () => {
      const date = new Date(2026, 8, 15, 10, 5)
      const en = renderSystemPromptTemplate('', date, PromptLanguage.EN_US)
      expect(en.includes('You are XCube')).assertTrue()
      expect(en.includes('2026-09-15 Tuesday 10:05 UTC')).assertTrue()
      expect(/[\u3400-\u9fff]/.test(en)).assertFalse()
      expect(buildCurrentTimeContext(date, PromptLanguage.ZH_CN).includes('2026年09月15日')).assertTrue()
    })

    it('selects_matching_execution_and_tool_rules_without_changing_limits', 0, () => {
      const options = new ToolPromptOptions()
      options.currentTime = '2026-09-15'
      options.webSearch = true
      options.knowledgeSearch = true
      options.askUser = true
      options.subAgent = true
      options.webSearchCallLimit = 2
      options.knowledgeSearchCallLimit = 3
      options.language = PromptLanguage.EN_US
      const en = buildToolUsagePrompt(options)
      expect(en.includes('web_search at most 2')).assertTrue()
      expect(en.includes('knowledge_search at most 3')).assertTrue()
      expect(/[\u3400-\u9fff]/.test(en)).assertFalse()
      options.language = PromptLanguage.ZH_CN
      const zh = buildToolUsagePrompt(options)
      expect(zh.includes('web_search 2 次')).assertTrue()
      expect(zh.includes('knowledge_search 3 次')).assertTrue()
      expect(getTaskExecutionPrompt(options.language).includes('任务执行原则')).assertTrue()
      options.webSearch = false
      expect(buildToolUsagePrompt(options).includes('联网检索')).assertFalse()
    })

    it('keeps_user_output_preferences_above_prompt_and_source_language', 0, () => {
      const custom = 'Please reply in Japanese.'
      const en = appendResponseLanguageSystemPrompt(custom, PromptLanguage.EN_US)
      const zh = appendResponseLanguageSystemPrompt(custom, PromptLanguage.ZH_CN)
      expect(en.startsWith(custom)).assertTrue()
      expect(zh.startsWith(custom)).assertTrue()
      expect(en.endsWith(getResponseLanguageSystemPrompt(PromptLanguage.EN_US))).assertTrue()
      expect(zh.endsWith(getResponseLanguageSystemPrompt(PromptLanguage.ZH_CN))).assertTrue()
      expect(en.includes('earlier preference that still applies')).assertTrue()
      expect(en.includes('Quoted text, pasted documents, code, URLs')).assertTrue()
      expect(zh.includes('简短续问、仅附件')).assertTrue()
    })

    it('preserves_source_and_goal_text_inside_localized_wrappers', 0, () => {
      const source = '中文原文：不得修改“sample.txt”。'
      const summary = ContextCompactionService.buildSummaryRequestPrompt(source, PromptLanguage.EN_US)
      expect(summary.endsWith(source)).assertTrue()
      expect(summary.includes('not a new user instruction')).assertTrue()
      const goal = buildConversationGoalSystemPrompt(source, PromptLanguage.EN_US)
      expect(goal.includes(JSON.stringify(source))).assertTrue()
      expect(goal.includes('current persistent goal')).assertTrue()
      expect(ContextCompactionService.buildAutomaticContinuationPrompt(true, PromptLanguage.EN_US)
        .includes('Keep the response language')).assertTrue()
      expect(ContextCompactionService.buildManualSummarySystemPrompt(PromptLanguage.EN_US)
        .includes('response-language')).assertTrue()
    })

    it('keeps_each_tool_actor_notice_in_its_selected_language', 0, () => {
      const guard = new ToolProgressGuard()
      guard.beginTurn('request', 'main', PromptLanguage.EN_US)
      guard.beginTurn('request', 'child', PromptLanguage.ZH_CN)
      for (let i = 0; i < 5; i++) {
        guard.observe('request', 'main', 'probe', '{}', '{}')
        guard.observe('request', 'child', 'probe', '{}', '{}')
      }
      expect(guard.getStopMessage('request', 'main')).assertEqual(getToolProgressStop(PromptLanguage.EN_US))
      expect(guard.getStopMessage('request', 'child')).assertEqual(getToolProgressStop(PromptLanguage.ZH_CN))
      expect(isToolProgressStop(guard.getStopMessage('request', 'main'))).assertTrue()
      expect(isToolProgressStop(guard.getStopMessage('request', 'child'))).assertTrue()
    })
  })
}
