import { describe, it, expect } from '@ohos/hypium'
import { AttachmentType, MessageAttachment } from '../main/ets/models/ChatModels'
import {
  DocumentAttachmentRegistryService,
  isOfficeOpenXmlDocumentAttachment
} from '../main/ets/services/DocumentAttachmentRegistryService'
import {
  DOCX_TO_TEXT_TOOL_ID,
  getBuiltinToolIds,
  XLSX_TO_TEXT_TOOL_ID
} from '../main/ets/config/BuiltinTools'

export default function officeDocumentToolTest() {
  describe('officeDocumentToolTest', () => {
    it('exposes_docx_and_xlsx_as_builtin_tools', 0, () => {
      const toolIds = getBuiltinToolIds()

      expect(toolIds.includes(DOCX_TO_TEXT_TOOL_ID)).assertTrue()
      expect(toolIds.includes(XLSX_TO_TEXT_TOOL_ID)).assertTrue()
    })

    it('registers_only_supported_office_attachments_for_the_session', 0, () => {
      const registry = new DocumentAttachmentRegistryService()
      const sessionId = 'office-tool-test-session'
      const attachments: MessageAttachment[] = [
        new MessageAttachment(
          'docx_attachment',
          AttachmentType.FILE,
          '制度.docx',
          '/data/storage/el2/base/files/attachments/files/docx_attachment.docx',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          120
        ),
        new MessageAttachment(
          'xlsx_attachment',
          AttachmentType.FILE,
          '预算.xlsx',
          '/data/storage/el2/base/files/attachments/files/xlsx_attachment.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          240
        ),
        new MessageAttachment(
          'txt_attachment',
          AttachmentType.FILE,
          '备注.txt',
          '/data/storage/el2/base/files/attachments/files/txt_attachment.txt',
          'text/plain',
          30
        )
      ]

      registry.registerAttachments(sessionId, attachments)

      expect(registry.listAttachments(sessionId).length).assertEqual(2)
      expect(registry.getAttachment(sessionId, 'docx_attachment') !== null).assertTrue()
      expect(registry.getAttachment(sessionId, 'xlsx_attachment') !== null).assertTrue()
      expect(registry.getAttachment(sessionId, 'txt_attachment') === null).assertTrue()
      expect(isOfficeOpenXmlDocumentAttachment(attachments[0])).assertTrue()
      expect(isOfficeOpenXmlDocumentAttachment(attachments[1])).assertTrue()
      expect(isOfficeOpenXmlDocumentAttachment(attachments[2])).assertFalse()
    })
  })
}
