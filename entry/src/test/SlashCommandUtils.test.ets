import { describe, expect, it } from '@ohos/hypium'
import { PromptLanguage } from '../main/ets/utils/PromptLanguageUtils'
import {
  buildRequiredSkillPrompt,
  buildSkillSlashCommands,
  GOAL_COMMAND_ACTION_CLEAR,
  GOAL_COMMAND_ACTION_NONE,
  GOAL_COMMAND_ACTION_PROMPT,
  GOAL_COMMAND_ACTION_SET,
  isGoalSlashCommandInput,
  matchSlashCommands,
  resolveGoalSlashCommandAction,
  resolveGoalSlashCommandText,
  resolveSlashCommandId,
  resolveSlashSkillId,
  SlashSkillInfo
} from '../main/ets/utils/SlashCommandUtils'

export default function slashCommandUtilsTest() {
  describe('slashCommandUtilsTest', () => {
    it('finds_enabled_skills_and_accepts_tasks_bare_commands_and_attachments_only_input', 0, () => {
      const catalog: SlashSkillInfo[] = [
        { id: 'help', name: 'app-help', description: 'Using XCube' },
        { id: 'report', name: '整理 报告', description: '生成报告' },
        { id: 'plan-skill', name: 'plan', description: 'Quarterly planning' }
      ]
      const commands = buildSkillSlashCommands(catalog)
      expect(matchSlashCommands('/', commands).length).assertEqual(9)
      expect(matchSlashCommands('/整', commands)[0].description).assertEqual('生成报告')
      expect(matchSlashCommands('/app', commands)[0].name).assertEqual('/skill:app-help')
      expect(resolveSlashSkillId('/skill:整理-报告\n第一段\n第二段', commands)).assertEqual('report')
      expect(resolveSlashSkillId('/APP-HELP', commands)).assertEqual('help')
      expect(resolveSlashSkillId('/skill:app-help ', commands)).assertEqual('help')
      expect(resolveSlashCommandId('/plan')).assertEqual('plan')
      expect(resolveSlashSkillId('/plan', commands) === undefined).assertTrue()
      expect(resolveSlashSkillId('/skill:plan', commands)).assertEqual('plan-skill')
      expect(resolveSlashSkillId('/skill:app-help 写说明', [])).assertEqual('')
      expect(resolveSlashSkillId('介绍 /skill:app-help', commands) === undefined).assertTrue()
      expect(resolveSlashSkillId('/app-help/guide', commands) === undefined).assertTrue()
      expect(matchSlashCommands('/skill:app-help 写说明', commands).length).assertEqual(0)
    })

    it('resolves_duplicate_skill_names_by_id_and_keeps_explicit_selection_turn_scoped', 0, () => {
      const one: SlashSkillInfo = { id: 'a/b', name: 'Daily report', description: 'First' }
      const two: SlashSkillInfo = { id: 'second', name: 'daily-report', description: 'Second' }
      const commands = buildSkillSlashCommands([one, two])
      expect(commands[0].name !== commands[1].name).assertTrue()
      expect(resolveSlashSkillId(commands[0].name, commands)).assertEqual(one.id)
      expect(resolveSlashSkillId(commands[0].name, buildSkillSlashCommands([one]))).assertEqual(one.id)
      expect(resolveSlashSkillId(commands[0].name, buildSkillSlashCommands([two]))).assertEqual('')
      expect(resolveSlashSkillId('/skill:daily-report', commands)).assertEqual('')
      expect(resolveSlashSkillId('下一条普通消息', commands) === undefined).assertTrue()
      expect(buildRequiredSkillPrompt('', PromptLanguage.EN_US)).assertEqual('')
      expect(buildRequiredSkillPrompt(one.id, PromptLanguage.ZH_CN).includes('必须调用 use_skill')).assertTrue()
      expect(buildRequiredSkillPrompt(two.id, PromptLanguage.EN_US).includes('must call use_skill')).assertTrue()
      expect(buildRequiredSkillPrompt(one.id, PromptLanguage.EN_US).includes('{"skill_id":"a/b","path":"SKILL.md"}')).assertTrue()
    })

    it('treats_a_bare_goal_command_as_cancelling_an_existing_goal', 0, () => {
      expect(resolveGoalSlashCommandAction('/goal', '写完第三章')).assertEqual(GOAL_COMMAND_ACTION_CLEAR)
      expect(resolveGoalSlashCommandAction('/goal ', '写完第三章')).assertEqual(GOAL_COMMAND_ACTION_CLEAR)
      expect(resolveGoalSlashCommandAction('  /goal\n ', '写完第三章')).assertEqual(GOAL_COMMAND_ACTION_CLEAR)
    })

    it('prompts_for_goal_text_when_there_is_nothing_to_cancel', 0, () => {
      expect(resolveGoalSlashCommandAction('/goal', '')).assertEqual(GOAL_COMMAND_ACTION_PROMPT)
      // 只有空白的目标等同于没有目标，不能报告成"取消了目标"
      expect(resolveGoalSlashCommandAction('/goal ', '   ')).assertEqual(GOAL_COMMAND_ACTION_PROMPT)
    })

    it('still_sets_the_goal_when_the_command_carries_text', 0, () => {
      expect(resolveGoalSlashCommandAction('/goal 写完第三章', '')).assertEqual(GOAL_COMMAND_ACTION_SET)
      // 已有目标时带正文是替换，不是取消
      expect(resolveGoalSlashCommandAction('/goal 改写第三章', '写完第三章')).assertEqual(GOAL_COMMAND_ACTION_SET)
      expect(resolveGoalSlashCommandAction('/goal\n多行\n目标', '')).assertEqual(GOAL_COMMAND_ACTION_SET)
    })

    it('ignores_text_that_only_looks_like_the_goal_command', 0, () => {
      expect(resolveGoalSlashCommandAction('/goalkeeper', '写完第三章')).assertEqual(GOAL_COMMAND_ACTION_NONE)
      expect(resolveGoalSlashCommandAction('goal', '写完第三章')).assertEqual(GOAL_COMMAND_ACTION_NONE)
      expect(resolveGoalSlashCommandAction('说说 /goal 怎么用', '写完第三章')).assertEqual(GOAL_COMMAND_ACTION_NONE)
    })

    it('keeps_the_existing_goal_command_parsing_intact', 0, () => {
      expect(isGoalSlashCommandInput('/goal')).assertTrue()
      expect(isGoalSlashCommandInput('/goalkeeper')).assertFalse()
      expect(resolveGoalSlashCommandText('/goal  写完第三章  ')).assertEqual('写完第三章')
      expect(resolveGoalSlashCommandText('/goal')).assertEqual('')
    })
  })
}
