import { describe, it, expect } from '@ohos/hypium'
import { AttachmentType, MessageAttachment } from '../main/ets/models/ChatModels'
import { isAttachmentFilePathManaged } from '../main/ets/services/AttachmentStorageService'
import { DocumentAttachmentRegistryService } from '../main/ets/services/DocumentAttachmentRegistryService'

function createImageAttachment(id: string): MessageAttachment {
  return new MessageAttachment(
    id,
    AttachmentType.IMAGE,
    `${id}.png`,
    `/data/storage/el2/base/files/attachments/images/${id}.png`,
    'image/png',
    128
  )
}

export default function attachmentCleanupTest() {
  describe('attachmentCleanupTest', () => {
    it('clears_only_the_requested_session_registry', 0, () => {
      const registry = new DocumentAttachmentRegistryService()
      registry.registerAttachments('session-a', [createImageAttachment('image-a')])
      registry.registerAttachments('session-b', [createImageAttachment('image-b')])

      registry.clearSession('session-a')

      expect(registry.listAttachments('session-a').length).assertEqual(0)
      expect(registry.getAttachment('session-a', 'image-a') === null).assertTrue()
      expect(registry.listAttachments('session-b').length).assertEqual(1)
      expect(registry.listAllFilePaths().length).assertEqual(1)
      expect(registry.listAllFilePaths()[0].endsWith('/image-b.png')).assertTrue()
    })

    it('accepts_only_paths_below_the_managed_attachment_directory', 0, () => {
      const attachmentsDir = '/data/storage/el2/base/files/attachments'

      expect(isAttachmentFilePathManaged(
        '/data/storage/el2/base/files/attachments/images/generated.png',
        attachmentsDir
      )).assertTrue()
      expect(isAttachmentFilePathManaged(
        '/data/storage/el2/base/files/source.png',
        attachmentsDir
      )).assertFalse()
      expect(isAttachmentFilePathManaged(
        '/data/storage/el2/base/files/attachments/images/../../source.png',
        attachmentsDir
      )).assertFalse()
    })
  })
}
