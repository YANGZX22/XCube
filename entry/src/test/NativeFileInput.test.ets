import { describe, expect, it } from '@ohos/hypium'
import { ToolExecutionContext } from '../main/ets/services/ToolRegistry'
import {
  canOfferNativeFileInput,
  isNativeFileInputRejected,
  markNativeFileInputRejected,
  MAX_NATIVE_FILE_INPUT_BYTES,
  matchesToolFileKind,
  pushNativeFileInput,
  resolveNativeInputMimeType
} from '../main/ets/services/NativeFileInputService'
import { normalizeAliasedToolId, resolveLegacyToolId } from '../main/ets/utils/ToolIdAliases'

function visionContext(): ToolExecutionContext {
  return new ToolExecutionContext('session-1', 'request-1', 'main', true, false)
}

function documentContext(): ToolExecutionContext {
  return new ToolExecutionContext('session-1', 'request-1', 'main', false, true)
}

export default function nativeFileInputTest() {
  describe('nativeFileInputTest', () => {
    it('falls_back_to_the_extension_when_the_picker_gives_no_mime_type', 0, () => {
      expect(resolveNativeInputMimeType('shot.PNG', '')).assertEqual('image/png')
      expect(resolveNativeInputMimeType('report.pdf', 'application/octet-stream'))
        .assertEqual('application/pdf')
      expect(resolveNativeInputMimeType('photo.jpg', 'image/JPEG')).assertEqual('image/jpeg')
    })

    it('matches_each_reader_tool_to_its_own_file_kind', 0, () => {
      expect(matchesToolFileKind('shot.png', 'image/png', 'image')).assertTrue()
      expect(matchesToolFileKind('report.pdf', 'application/pdf', 'image')).assertFalse()
      expect(matchesToolFileKind('report.pdf', '', 'pdf')).assertTrue()
      expect(matchesToolFileKind('notes.docx', '', '.docx')).assertTrue()
      expect(matchesToolFileKind('notes.docx', '', '.xlsx')).assertFalse()
    })

    it('offers_native_input_only_for_the_capability_the_model_actually_has', 0, () => {
      expect(canOfferNativeFileInput(visionContext(), 'shot.png', 'image/png', 1024)).assertTrue()
      expect(canOfferNativeFileInput(visionContext(), 'report.pdf', 'application/pdf', 1024)).assertFalse()
      expect(canOfferNativeFileInput(documentContext(), 'report.pdf', 'application/pdf', 1024)).assertTrue()
      expect(canOfferNativeFileInput(documentContext(), 'shot.png', 'image/png', 1024)).assertFalse()
      // No context means no bound request to attach the raw bytes to.
      expect(canOfferNativeFileInput(undefined, 'shot.png', 'image/png', 1024)).assertFalse()
    })

    it('rejects_files_larger_than_the_native_input_budget', 0, () => {
      expect(canOfferNativeFileInput(visionContext(), 'huge.png', 'image/png',
        MAX_NATIVE_FILE_INPUT_BYTES + 1)).assertFalse()
      expect(canOfferNativeFileInput(visionContext(), 'big.png', 'image/png',
        MAX_NATIVE_FILE_INPUT_BYTES)).assertTrue()
    })

    it('attaches_a_read_file_once_per_call_even_when_the_model_reads_it_twice', 0, () => {
      const context = visionContext()
      const attached = pushNativeFileInput(context, 'workspace:shot.png:12', 'shot.png',
        'image/png', 1024, 'QUJD', '/data/ws/shot.png')
      const attachedAgain = pushNativeFileInput(context, 'workspace:shot.png:12', 'shot.png',
        'image/png', 1024, 'QUJD', '/data/ws/shot.png')

      expect(attached).assertTrue()
      expect(attachedAgain).assertTrue()
      expect(context.inputAttachments.length).assertEqual(1)
      expect(context.inputAttachments[0].base64Data).assertEqual('QUJD')
      // The sandbox path is kept in memory only, so a rejected native input can be
      // re-read as text without asking the model to call the tool again.
      expect(context.inputAttachments[0].filePath).assertEqual('/data/ws/shot.png')
    })

    it('stops_offering_native_input_to_a_model_whose_endpoint_rejected_it', 0, () => {
      const context = new ToolExecutionContext('session-1', 'request-1', 'main', true, false,
        'provider-x', 'model-x')
      expect(canOfferNativeFileInput(context, 'shot.png', 'image/png', 1024)).assertTrue()

      markNativeFileInputRejected('provider-x', 'model-x', true)
      expect(canOfferNativeFileInput(context, 'shot.png', 'image/png', 1024)).assertFalse()
      // Scoped to that provider+model and that kind only.
      expect(isNativeFileInputRejected('provider-x', 'model-x', false)).assertFalse()
      expect(isNativeFileInputRejected('provider-y', 'model-x', true)).assertFalse()
    })

    it('maps_the_legacy_to_text_tool_ids_onto_the_renamed_toolkits', 0, () => {
      expect(resolveLegacyToolId('pdf_to_text')).assertEqual('pdf_toolkit')
      expect(resolveLegacyToolId('image_to_text')).assertEqual('image_toolkit')
      expect(resolveLegacyToolId('docx_to_text')).assertEqual('docx_toolkit')
      expect(resolveLegacyToolId('xlsx_to_text')).assertEqual('xlsx_toolkit')
      // Unrelated and already-renamed ids pass through untouched.
      expect(resolveLegacyToolId('pdf_toolkit')).assertEqual('pdf_toolkit')
      expect(resolveLegacyToolId('web_search')).assertEqual('web_search')
      expect(normalizeAliasedToolId('  PDF-To-Text ')).assertEqual('pdf_toolkit')
    })

    it('drops_an_unreadable_or_oversized_payload_instead_of_attaching_it', 0, () => {
      const context = visionContext()
      expect(pushNativeFileInput(context, 'workspace:shot.png:12', 'shot.png', 'image/png', 1024,
        '', '/data/ws/shot.png')).assertFalse()
      expect(context.inputAttachments.length).assertEqual(0)
    })
  })
}
