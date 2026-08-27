import { describe, it, expect } from '@ohos/hypium'
import { AttachmentType, MessageAttachment } from '../main/ets/models/ChatModels'
import {
  isAttachmentCacheFileOldEnough,
  isAttachmentFilePathManaged
} from '../main/ets/services/AttachmentStorageService'
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

function createSandboxFileAttachment(id: string, extension: string): MessageAttachment {
  return new MessageAttachment(
    id,
    AttachmentType.FILE,
    `report.${extension}`,
    `/data/storage/el2/base/files/attachments/files/${id}.${extension}`,
    extension === 'pdf' ? 'application/pdf' : 'text/csv',
    256
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

    it('unregisters_only_the_deleted_message_attachment', 0, () => {
      const registry = new DocumentAttachmentRegistryService()
      registry.registerAttachments('session-a', [
        createImageAttachment('image-a'),
        createImageAttachment('image-b')
      ])
      registry.registerAttachments('session-b', [createImageAttachment('image-c')])

      registry.unregisterAttachment('session-a', 'image-a')

      expect(registry.getAttachment('session-a', 'image-a') === null).assertTrue()
      expect(registry.getAttachment('session-a', 'image-b') !== null).assertTrue()
      expect(registry.getAttachment('session-b', 'image-c') !== null).assertTrue()
      expect(registry.listAllFilePaths().length).assertEqual(2)
    })

    it('protects_registered_python_sandbox_files_from_cache_cleanup', 0, () => {
      const registry = new DocumentAttachmentRegistryService()
      registry.registerAttachments('session-a', [
        createSandboxFileAttachment('python_file_pdf', 'pdf'),
        createSandboxFileAttachment('python_file_csv', 'csv')
      ])

      expect(registry.listAllFilePaths().length).assertEqual(2)
      expect(registry.listAllFilePaths()[0].indexOf('/attachments/files/') >= 0).assertTrue()
      expect(registry.getAttachment('session-a', 'python_file_pdf') !== null).assertTrue()
      expect(registry.getAttachment('session-a', 'python_file_csv') !== null).assertTrue()
    })

    it('keeps_recent_cache_files_until_references_can_be_persisted', 0, () => {
      const cleanupStartedAt = 1_000_000
      const fiveMinutes = 5 * 60 * 1000

      expect(isAttachmentCacheFileOldEnough(
        cleanupStartedAt - fiveMinutes - 1,
        cleanupStartedAt,
        fiveMinutes
      )).assertTrue()
      expect(isAttachmentCacheFileOldEnough(
        cleanupStartedAt - fiveMinutes + 1,
        cleanupStartedAt,
        fiveMinutes
      )).assertFalse()
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
