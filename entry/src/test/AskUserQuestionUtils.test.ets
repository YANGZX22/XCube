import { describe, it, expect } from '@ohos/hypium'
import { askUserQuestionRenderKey, parseAskUserQuestions } from '../main/ets/utils/AskUserQuestionUtils'

export default function askUserQuestionUtilsTest() {
  describe('AskUserQuestionUtils', () => {
    it('keeps_question_text_options_and_selection_types', 0, () => {
      const result = parseAskUserQuestions('{"questions":[{"id":"q1","question":"请选择主题","selection_type":"single","options":["浅色","深色"]},{"id":"q2","question":"选择工具","selection_type":"multi","options":["地图","搜索"]},{"id":"q3","question":"还有什么要求","selection_type":"text"}]}')
      expect(result.status).assertEqual('ready')
      expect(result.questions.length).assertEqual(3)
      expect(result.questions[0].question).assertEqual('请选择主题')
      expect(result.questions[0].options.join('|')).assertEqual('浅色|深色')
      expect(result.questions[1].selectionType).assertEqual('multi')
      expect(result.questions[2].selectionType).assertEqual('text')
    })

    it('supports_legacy_single_question_and_encoded_json', 0, () => {
      const args = '{"question":"确认继续吗？","options":["继续","取消"]}'
      expect(parseAskUserQuestions(args).questions[0].id).assertEqual('q_1')
      expect(parseAskUserQuestions(args).questions[0].selectionType).assertEqual('single')
      expect(parseAskUserQuestions(JSON.stringify(args)).questions[0].question).assertEqual('确认继续吗？')
    })

    it('reports_missing_or_invalid_arguments_instead_of_silent_empty', 0, () => {
      expect(parseAskUserQuestions('').status).assertEqual('empty')
      expect(parseAskUserQuestions('{"questions":[').status).assertEqual('invalid_json')
      expect(parseAskUserQuestions('{}').status).assertEqual('invalid_schema')
      expect(parseAskUserQuestions('null').status).assertEqual('invalid_schema')
      expect(parseAskUserQuestions('[]').status).assertEqual('invalid_schema')
      expect(parseAskUserQuestions('{"questions":[]}').status).assertEqual('no_questions')
      expect(parseAskUserQuestions('{"questions":[null,42,{"question":""}]}').status).assertEqual('no_questions')
    })

    it('keeps_valid_items_and_makes_ids_and_options_unique', 0, () => {
      const result = parseAskUserQuestions('{"questions":[null,{"id":"same","question":"第一问","options":["A","A","",42,"B"]},{"id":"same","question":"第二问"}]}')
      expect(result.questions.length).assertEqual(2)
      expect(result.questions[0].options.join('|')).assertEqual('A|B')
      expect(result.questions[0].id).assertEqual('same')
      expect(result.questions[1].id).assertEqual('same_2')
    })

    it('changes_render_key_when_same_id_receives_new_content', 0, () => {
      const first = parseAskUserQuestions('{"questions":[{"id":"q1","question":"第一版？","options":["A"]}]}').questions[0]
      const next = parseAskUserQuestions('{"questions":[{"id":"q1","question":"第二版？","options":["A","B"]}]}').questions[0]
      expect(first.id).assertEqual(next.id)
      expect(askUserQuestionRenderKey(first) !== askUserQuestionRenderKey(next)).assertEqual(true)
      expect(askUserQuestionRenderKey(next)).assertEqual(askUserQuestionRenderKey(next))
    })
  })
}
