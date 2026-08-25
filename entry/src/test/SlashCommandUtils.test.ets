import { describe, expect, it } from '@ohos/hypium'
import {
  GOAL_COMMAND_ACTION_CLEAR,
  GOAL_COMMAND_ACTION_NONE,
  GOAL_COMMAND_ACTION_PROMPT,
  GOAL_COMMAND_ACTION_SET,
  isGoalSlashCommandInput,
  resolveGoalSlashCommandAction,
  resolveGoalSlashCommandText
} from '../main/ets/utils/SlashCommandUtils'

export default function slashCommandUtilsTest() {
  describe('slashCommandUtilsTest', () => {
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
