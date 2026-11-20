import { describe, expect, it } from '@ohos/hypium'
import { buildAnnotatedRequest, formatAnnotatedMessage, MAX_REPLY_ANNOTATIONS, parseReplyAnnotations, ReplyAnnotation } from '../main/ets/models/ReplyAnnotation'
import { PromptLanguage } from '../main/ets/utils/PromptLanguageUtils'

export default function replyAnnotationTest() {
  describe('Reply annotations', () => {
    it('keeps multiline selections and their comments paired in order', 0, () => {
      const notes: ReplyAnnotation[] = [
        { quote: '示例 🌱\r\n\r\n  print(1)', comment: '为什么要缩进？' },
        { quote: '示例 🌱', comment: '换一个例子。' }
      ]
      expect(formatAnnotatedMessage('请解释', notes.length, PromptLanguage.ZH_CN)).assertEqual(
        '2 条注释\n请解释')
      const request = buildAnnotatedRequest('请解释', notes, PromptLanguage.ZH_CN)
      expect(request.startsWith('请解释\n\n用户特别强调了')).assertEqual(true)
      expect(request.endsWith(JSON.stringify(notes))).assertEqual(true)
      expect(JSON.stringify(parseReplyAnnotations(JSON.stringify(notes)))).assertEqual(JSON.stringify(notes))
    })
    it('can send only annotations and leaves an ordinary message intact', 0, () => {
      const notes: ReplyAnnotation[] = [{ quote: '/goal', comment: 'What does this do?' }]
      expect(formatAnnotatedMessage('', notes.length, PromptLanguage.EN_US)).assertEqual('1 annotation')
      const request = buildAnnotatedRequest('', notes, PromptLanguage.EN_US)
      expect(request.startsWith('The user highlighted')).assertEqual(true)
      expect(request.endsWith(JSON.stringify(notes))).assertEqual(true)
      const typedQuote = '> my own quote\n'
      expect(formatAnnotatedMessage(typedQuote, 0, PromptLanguage.EN_US)).assertEqual(typedQuote)
      expect(buildAnnotatedRequest(typedQuote, [], PromptLanguage.EN_US)).assertEqual(typedQuote)
    })
    it('retains a selection with an optional comment', 0, () => {
      const notes = parseReplyAnnotations('[{"quote":"选文","comment":""}]')
      expect(notes.length).assertEqual(1)
      expect(formatAnnotatedMessage('请展开', notes.length, PromptLanguage.ZH_CN)).assertEqual('1 条注释\n请展开')
      expect(formatAnnotatedMessage('', notes.length, PromptLanguage.ZH_CN)).assertEqual('1 条注释')
      expect(formatAnnotatedMessage('', notes.length, PromptLanguage.EN_US)).assertEqual('1 annotation')
      expect(buildAnnotatedRequest('', notes, PromptLanguage.ZH_CN).endsWith(JSON.stringify(notes))).assertEqual(true)
    })
    it('restores at most five selections from a stored draft', 0, () => {
      const notes: ReplyAnnotation[] = [{ quote: ' ', comment: 'blank excerpt' }]
      for (let i = 0; i < 7; i++) notes.push({ quote: 'same excerpt', comment: i.toString() })
      const restored = parseReplyAnnotations(JSON.stringify(notes))
      expect(restored.length).assertEqual(MAX_REPLY_ANNOTATIONS)
      expect(restored[0].comment).assertEqual('0')
      expect(restored[4].comment).assertEqual('4')
    })
    it('reads legacy and invalid draft records safely', 0, () => {
      for (const raw of ['', '{', '{}', 'null', '[null,42,{"quote":1,"comment":"x"}]']) {
        expect(parseReplyAnnotations(raw).length).assertEqual(0)
      }
    })
  })
}
