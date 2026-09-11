import { describe, it, expect } from '@ohos/hypium'
import { util } from '@kit.ArkTS'
import { canUseNativeFileInput, decodeWorkspaceContent, decodeWorkspaceText, encodeWorkspaceBytes, getWorkspaceMimeType } from '../main/ets/utils/WorkspaceFileCodec'

export default function workspaceFileCodecTest() {
  describe('WorkspaceFileCodec', () => {
    it('gates_native_inputs_by_independent_vision_and_document_capabilities', 0, () => {
      expect(canUseNativeFileInput('image/png', true, false)).assertTrue()
      expect(canUseNativeFileInput('image/png', false, true)).assertFalse()
      expect(canUseNativeFileInput('application/pdf', false, true)).assertTrue()
      expect(canUseNativeFileInput('application/pdf', true, false)).assertFalse()
      expect(canUseNativeFileInput(getWorkspaceMimeType('report.docx'), false, true)).assertTrue()
      expect(canUseNativeFileInput('application/zip', true, true)).assertFalse()
      expect(canUseNativeFileInput('application/octet-stream', true, true)).assertFalse()
      expect(canUseNativeFileInput('image/svg+xml', true, true)).assertFalse()
    })
    it('round_trips_every_byte_including_nul_and_invalid_utf8', 0, () => {
      const bytes = new Uint8Array(256)
      for (let i = 0; i < bytes.length; i++) { bytes[i] = i }
      const restored = decodeWorkspaceContent(encodeWorkspaceBytes(bytes), 'base64')
      expect(restored.length).assertEqual(bytes.length)
      for (let i = 0; i < bytes.length; i++) { expect(restored[i]).assertEqual(bytes[i]) }
      expect(decodeWorkspaceText(bytes, 'data.bin') === undefined).assertTrue()
    })
    it('accepts_old_text_snapshots_and_legitimate_replacement_characters', 0, () => {
      const content = '中文\nhello\n\uFFFD'
      expect(decodeWorkspaceText(decodeWorkspaceContent(content), '说明.txt')).assertEqual(content)
      expect(decodeWorkspaceContent('', 'base64').length).assertEqual(0)
    })
    it('does_not_treat_ascii_pdf_or_office_files_as_editable_text', 0, () => {
      const bytes = new util.TextEncoder().encodeInto('%PDF-1.7\n1 0 obj')
      expect(decodeWorkspaceText(bytes, 'report.PDF') === undefined).assertTrue()
      expect(decodeWorkspaceText(bytes, 'book.xlsx') === undefined).assertTrue()
      expect(getWorkspaceMimeType('资料/报告.PDF')).assertEqual('application/pdf')
      expect(getWorkspaceMimeType('图片/photo.PNG')).assertEqual('image/png')
      expect(getWorkspaceMimeType('raw.unknown')).assertEqual('application/octet-stream')
    })
    it('preserves_utf8_bom_and_rejects_non_utf8_instead_of_corrupting_it', 0, () => {
      const bom = new Uint8Array([239, 187, 191, 65])
      expect(decodeWorkspaceText(bom, 'a.txt')).assertEqual('\uFEFFA')
      expect(decodeWorkspaceText(new Uint8Array([0xD6, 0xD0]), 'gbk.txt') === undefined).assertTrue()
    })
    it('rejects_malformed_bridge_data', 0, () => {
      const malformed: string[] = ['a', '====', 'a===', 'AA=A', 'AA A', 'AA\n=', '!!!!']
      for (let i = 0; i < malformed.length; i++) {
        let rejected = false
        try { decodeWorkspaceContent(malformed[i], 'base64') } catch (_error) { rejected = true }
        expect(rejected).assertTrue()
      }
      let rejectedEncoding = false
      try { decodeWorkspaceContent('test', 'binary') } catch (_error) { rejectedEncoding = true }
      expect(rejectedEncoding).assertTrue()
    })
    it('round_trips_a_multichunk_file_larger_than_the_old_limit', 0, () => {
      const bytes = new Uint8Array(1024 * 1024 + 19)
      bytes[0] = 137
      bytes[256 * 1024] = 255
      bytes[1024 * 1024] = 128
      bytes[bytes.length - 1] = 42
      const restored = decodeWorkspaceContent(encodeWorkspaceBytes(bytes), 'base64')
      expect(restored.length).assertEqual(bytes.length)
      expect(restored[256 * 1024]).assertEqual(255)
      expect(restored[1024 * 1024]).assertEqual(128)
      expect(restored[bytes.length - 1]).assertEqual(42)
    })
  })
}
