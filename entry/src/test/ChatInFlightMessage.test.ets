import { describe, expect, it } from '@ohos/hypium'
import { AttachmentType, MessageAttachment } from '../main/ets/models/ChatModels'
import {
  buildSteeringRequestContent,
  buildSteeringTimelineText,
  ChatInFlightMessage,
  InFlightMessageDelivery
} from '../main/ets/pages/chat/ChatInFlightMessage'

export default function chatInFlightMessageTest() {
  describe('chatInFlightMessageTest', () => {
    it('keeps_queue_payload_isolated_from_the_composer_array', 0, () => {
      const attachment = new MessageAttachment('a1', AttachmentType.FILE, 'notes.txt', '/tmp/notes.txt', 'text/plain')
      const composerAttachments = [attachment]
      const pending = new ChatInFlightMessage(
        '  follow up  ',
        composerAttachments,
        InFlightMessageDelivery.QUEUE,
        'session-1'
      )
      composerAttachments.splice(0, 1)

      expect(pending.content).assertEqual('follow up')
      expect(pending.attachments.length).assertEqual(1)
      expect(pending.sessionId).assertEqual('session-1')
    })

    it('builds_explicit_non_interrupting_guidance_context', 0, () => {
      const attachment = new MessageAttachment('a1', AttachmentType.IMAGE, 'diagram.png', '', 'image/png')
      const timeline = buildSteeringTimelineText('focus on the diagram', [attachment])
      const request = buildSteeringRequestContent('focus on the diagram')

      expect(timeline.includes('diagram.png')).assertEqual(true)
      expect(request.includes('User guidance received')).assertEqual(true)
      expect(request.includes('Do not repeat completed work')).assertEqual(true)
    })
  })
}
