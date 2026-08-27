import { describe, it, expect } from '@ohos/hypium'
import {
  parseSubAgentToolArguments,
  repairTruncatedSubAgentToolArguments
} from '../main/ets/services/SubAgentArgumentParser'

export default function subAgentArgumentParserTest() {
  describe('subAgentArgumentParserTest', () => {
    it('parses_flat_task_fields_without_any_array_parameter', 0, () => {
      const parsed = parseSubAgentToolArguments(
        '{"main_thread_work":"主线程整理对照表","task_1_name":"date",' +
          '"task_1_prompt":"核实亚冬会开幕日期","task_1_expected_output":"附来源",' +
          '"task_2_prompt":"查找组委会官方页面"}'
      )
      expect(parsed.main_thread_work).assertEqual('主线程整理对照表')
      expect(parsed.tasks?.length).assertEqual(2)
      expect(parsed.tasks?.[0].name).assertEqual('date')
      expect(parsed.tasks?.[0].prompt).assertEqual('核实亚冬会开幕日期')
      expect(parsed.tasks?.[0].expected_output).assertEqual('附来源')
      expect(parsed.tasks?.[1].prompt).assertEqual('查找组委会官方页面')
    })

    it('parses_standard_and_double_encoded_dispatch_arguments', 0, () => {
      const standard = '{"main_thread_work":"核实另一来源","tasks":[{"name":"date",' +
        '"prompt":"核实亚冬会开幕日期","expected_output":"附来源"}]}'
      const parsed = parseSubAgentToolArguments(standard)
      expect(parsed.main_thread_work).assertEqual('核实另一来源')
      expect(parsed.tasks?.length).assertEqual(1)
      expect(parsed.tasks?.[0].prompt).assertEqual('核实亚冬会开幕日期')

      const doubleEncoded = parseSubAgentToolArguments(JSON.stringify(standard))
      expect(doubleEncoded.main_thread_work).assertEqual('核实另一来源')
      expect(doubleEncoded.tasks?.[0].expected_output).assertEqual('附来源')
    })

    it('parses_fenced_and_string_encoded_task_arrays', 0, () => {
      const fenced = '```json\n{"main_thread_work":"主线程整理提纲",' +
        '"tasks":"[{\\"prompt\\":\\"独立联网核实日期\\"}]"}\n```'
      const parsed = parseSubAgentToolArguments(fenced)
      expect(parsed.main_thread_work).assertEqual('主线程整理提纲')
      expect(parsed.tasks?.length).assertEqual(1)
      expect(parsed.tasks?.[0].prompt).assertEqual('独立联网核实日期')
    })

    it('accepts_common_field_aliases_without_losing_the_prompt', 0, () => {
      const parsed = parseSubAgentToolArguments(
        '{"mainThreadWork":"整理对照表","sub_tasks":{"name":"source",' +
          '"instruction":"搜索并返回权威来源","expectedOutput":"标题和 URL"}}'
      )
      expect(parsed.main_thread_work).assertEqual('整理对照表')
      expect(parsed.tasks?.length).assertEqual(1)
      expect(parsed.tasks?.[0].prompt).assertEqual('搜索并返回权威来源')
      expect(parsed.tasks?.[0].expected_output).assertEqual('标题和 URL')
    })

    it('recovers_trailing_container_closures_and_repeated_stream_snapshots', 0, () => {
      const truncated = '{"main_thread_work":"整理结论","tasks":[{"prompt":"核实来源"}]'
      expect(repairTruncatedSubAgentToolArguments(truncated)).assertEqual(`${truncated}}`)
      expect(parseSubAgentToolArguments(truncated).tasks?.[0].prompt).assertEqual('核实来源')

      const snapshots = '{"main_thread_work":"旧任务","tasks":[]}' +
        '{"main_thread_work":"新任务","tasks":[{"prompt":"执行新任务"}]}'
      const parsed = parseSubAgentToolArguments(snapshots)
      expect(parsed.main_thread_work).assertEqual('新任务')
      expect(parsed.tasks?.[0].prompt).assertEqual('执行新任务')
    })

    it('rejects_a_prompt_string_that_was_cut_off', 0, () => {
      let rejected = false
      try {
        parseSubAgentToolArguments(
          '{"main_thread_work":"整理结论","tasks":[{"prompt":"只收到半段'
        )
      } catch (_error) {
        rejected = true
      }
      expect(rejected).assertTrue()
    })
  })
}
