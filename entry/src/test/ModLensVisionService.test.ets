import { describe, expect, it } from '@ohos/hypium'
import { getBuiltinToolIds, MODLENS_READ_IMAGE_TOOL_ID } from '../main/ets/config/BuiltinTools'
import {
  isModLensGatewaySuccessJson,
  normalizeModLensGatewayUrl,
  sniffModLensImageMime
} from '../main/ets/services/ModLensVisionService'

export default function modLensVisionServiceTest() {
  describe('modLensVisionServiceTest', () => {
    it('normalizes_only_http_gateway_urls', 0, () => {
      expect(normalizeModLensGatewayUrl(' http://127.0.0.1:8787/ '))
        .assertEqual('http://127.0.0.1:8787')
      expect(normalizeModLensGatewayUrl('https://vision.example.com/modlens/'))
        .assertEqual('https://vision.example.com/modlens')
      expect(normalizeModLensGatewayUrl('file:///tmp/modlens')).assertEqual('')
      expect(normalizeModLensGatewayUrl('http://')).assertEqual('')
    })

    it('sniffs_image_signatures_instead_of_trusting_mime_labels', 0, () => {
      expect(sniffModLensImageMime(new Uint8Array([0xFF, 0xD8, 0xFF, 0x00])))
        .assertEqual('image/jpeg')
      expect(sniffModLensImageMime(new Uint8Array([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
      ]))).assertEqual('image/png')
      expect(sniffModLensImageMime(new Uint8Array([0x68, 0x65, 0x6C, 0x6C, 0x6F])))
        .assertEqual('')
    })

    it('accepts_only_structured_modlens_evidence', 0, () => {
      const valid: string = '{"ok":true,"output":{"provider":"gemini-api","result":' +
        '{"summary":"A chart","ocr":{},"layout":{},"semantics":{},"visual":{},"uncertainty":[]}}}'
      expect(isModLensGatewaySuccessJson(valid)).assertTrue()
      expect(isModLensGatewaySuccessJson('{"ok":true,"output":{"provider":"gemini-api"}}'))
        .assertFalse()
    })

    it('exposes_modlens_as_a_builtin_tool', 0, () => {
      expect(getBuiltinToolIds().includes(MODLENS_READ_IMAGE_TOOL_ID)).assertTrue()
    })
  })
}
