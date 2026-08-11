import { describe, expect, it } from '@ohos/hypium'
import { parseJsonResponseContent } from '../main/ets/utils/JsonResponseUtils'

export default function jsonResponseUtilsTest() {
  describe('jsonResponseUtilsTest', () => {
    it('formats_json_objects_and_arrays', 0, () => {
      const objectResult = parseJsonResponseContent('{"ok":true,"count":2}')
      expect(objectResult.isJson).assertTrue()
      expect(objectResult.content).assertContain('"ok": true')
      expect(objectResult.content).assertContain('"count": 2')

      const arrayResult = parseJsonResponseContent('[1,{"name":"XCube"}]')
      expect(arrayResult.isJson).assertTrue()
      expect(arrayResult.content).assertContain('"name": "XCube"')
    })

    it('supports_bom_and_json_primitives', 0, () => {
      const bomResult = parseJsonResponseContent('\uFEFF{"message":"ok"}')
      expect(bomResult.isJson).assertTrue()
      expect(bomResult.content).assertContain('"message": "ok"')

      const primitiveResult = parseJsonResponseContent('true')
      expect(primitiveResult.isJson).assertTrue()
      expect(primitiveResult.content).assertEqual('true')
    })

    it('leaves_html_for_the_html_parser', 0, () => {
      const result = parseJsonResponseContent('<html><body>hello</body></html>')
      expect(result.isJson).assertFalse()
      expect(result.content).assertEqual('')
    })

    it('marks_oversized_json_as_truncated', 0, () => {
      const result = parseJsonResponseContent('{"content":"abcdefghijklmnopqrstuvwxyz"}', 30)
      expect(result.isJson).assertTrue()
      expect(result.truncated).assertTrue()
      expect(result.content).assertContain('已截断')
    })
  })
}
