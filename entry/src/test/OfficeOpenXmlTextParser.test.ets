import { describe, it, expect } from '@ohos/hypium'
import {
  OfficeOpenXmlTextParser,
  OfficeWorksheetSource
} from '../main/ets/services/OfficeOpenXmlTextParser'

export default function officeOpenXmlTextParserTest() {
  describe('officeOpenXmlTextParserTest', () => {
    it('extracts_docx_headings_lists_entities_and_tables', 0, () => {
      const parser = new OfficeOpenXmlTextParser()
      const styles = '<?xml version="1.0"?>' +
        '<w:styles xmlns:w="word"><w:style w:type="paragraph" w:styleId="Heading1">' +
        '<w:name w:val="heading 1"/></w:style></w:styles>'
      const document = '<?xml version="1.0"?>' +
        '<w:document xmlns:w="word"><w:body>' +
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>' +
        '<w:r><w:t>员工&amp;制度</w:t></w:r></w:p>' +
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="1"/></w:numPr></w:pPr>' +
        '<w:r><w:t>提前申请</w:t></w:r></w:p>' +
        '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>姓名</w:t></w:r></w:p></w:tc>' +
        '<w:tc><w:p><w:r><w:t>部门</w:t></w:r></w:p></w:tc></w:tr>' +
        '<w:tr><w:tc><w:p><w:r><w:t>小王</w:t></w:r></w:p></w:tc>' +
        '<w:tc><w:p><w:r><w:t>研发</w:t></w:r></w:p></w:tc></w:tr></w:tbl>' +
        '</w:body></w:document>'

      const result = parser.parseDocx(document, styles, 10000)

      expect(result.truncated).assertEqual(false)
      expect(result.text).assertContain('# 员工&制度')
      expect(result.text).assertContain('  - 提前申请')
      expect(result.text).assertContain('| 姓名 | 部门 |')
      expect(result.text).assertContain('| 小王 | 研发 |')
    })

    it('extracts_xlsx_shared_inline_formula_date_and_coordinates', 0, () => {
      const parser = new OfficeOpenXmlTextParser()
      const workbook = '<workbook xmlns:r="rels"><workbookPr date1904="0"/><sheets>' +
        '<sheet name="预算表" sheetId="1" r:id="rId1"/></sheets></workbook>'
      const relationships = '<Relationships><Relationship Id="rId1" ' +
        'Target="worksheets/sheet1.xml"/></Relationships>'
      const sharedStrings = '<sst><si><r><t>名</t></r><r><t>称</t></r></si>' +
        '<si><t>日期</t></si></sst>'
      const styles = '<styleSheet><cellXfs count="2"><xf numFmtId="0"/>' +
        '<xf numFmtId="14"/></cellXfs></styleSheet>'
      const worksheet = '<worksheet><sheetData>' +
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>' +
        '<row r="2"><c r="A2" t="inlineStr"><is><t>项目甲</t></is></c>' +
        '<c r="B2" s="1"><v>45292</v></c>' +
        '<c r="C2"><f>1+2</f><v>3</v></c></row>' +
        '</sheetData><mergeCells><mergeCell ref="A3:C3"/></mergeCells></worksheet>'

      const result = parser.parseXlsx(
        workbook,
        relationships,
        sharedStrings,
        styles,
        [new OfficeWorksheetSource('xl/worksheets/sheet1.xml', worksheet)],
        10000
      )

      expect(result.truncated).assertEqual(false)
      expect(result.cellCount).assertEqual(5)
      expect(result.text).assertContain('## 工作表：预算表')
      expect(result.text).assertContain('合并单元格：A3:C3')
      expect(result.text).assertContain('| 行 | A | B | C |')
      expect(result.text).assertContain('| 1 | 名称 | 日期 |')
      expect(result.text).assertContain('项目甲')
      expect(result.text).assertContain('2024-01-01')
      expect(result.text).assertContain('3（公式：=1+2）')
    })

    it('renders_very_sparse_xlsx_rows_with_cell_references', 0, () => {
      const parser = new OfficeOpenXmlTextParser()
      const workbook = '<workbook xmlns:r="rels"><sheets>' +
        '<sheet name="稀疏数据" r:id="rId1"/></sheets></workbook>'
      const relationships = '<Relationships><Relationship Id="rId1" ' +
        'Target="worksheets/sheet1.xml"/></Relationships>'
      const worksheet = '<worksheet><sheetData><row r="9">' +
        '<c r="A9" t="inlineStr"><is><t>起点</t></is></c>' +
        '<c r="XFD9" t="inlineStr"><is><t>终点</t></is></c>' +
        '</row></sheetData></worksheet>'

      const result = parser.parseXlsx(
        workbook,
        relationships,
        '',
        '',
        [new OfficeWorksheetSource('xl/worksheets/sheet1.xml', worksheet)],
        10000
      )

      expect(result.text).assertContain('[A9] 起点')
      expect(result.text).assertContain('[XFD9] 终点')
    })
  })
}
