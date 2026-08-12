export class OfficeWorksheetSource {
  path: string = ''
  xml: string = ''

  constructor(path: string, xml: string) {
    this.path = path
    this.xml = xml
  }
}

export class OfficeOpenXmlParseResult {
  text: string = ''
  truncated: boolean = false
  cellCount: number = 0

  constructor(text: string, truncated: boolean = false, cellCount: number = 0) {
    this.text = text
    this.truncated = truncated
    this.cellCount = cellCount
  }
}

enum OfficeXmlTokenKind {
  START = 0,
  END = 1,
  TEXT = 2
}

class OfficeXmlToken {
  kind: OfficeXmlTokenKind = OfficeXmlTokenKind.TEXT
  name: string = ''
  text: string = ''
  attributes: Map<string, string> = new Map()

  constructor(
    kind: OfficeXmlTokenKind,
    name: string = '',
    text: string = '',
    attributes: Map<string, string> = new Map()
  ) {
    this.kind = kind
    this.name = name
    this.text = text
    this.attributes = attributes
  }

  attribute(name: string): string {
    const exact = this.attributes.get(name)
    if (exact !== undefined) {
      return exact
    }
    let result = ''
    this.attributes.forEach((value: string, key: string): void => {
      if (result === '' && OfficeXmlTokenizer.localName(key) === name) {
        result = value
      }
    })
    return result
  }
}

class OfficeXmlTokenizer {
  static localName(name: string): string {
    const colon = name.lastIndexOf(':')
    return colon >= 0 ? name.substring(colon + 1) : name
  }

  parse(xmlText: string, handler: (token: OfficeXmlToken) => void): void {
    let offset = 0
    while (offset < xmlText.length) {
      const tagStart = xmlText.indexOf('<', offset)
      if (tagStart < 0) {
        this.emitText(xmlText.substring(offset), handler)
        return
      }
      if (tagStart > offset) {
        this.emitText(xmlText.substring(offset, tagStart), handler)
      }
      if (xmlText.startsWith('<!--', tagStart)) {
        const commentEnd = xmlText.indexOf('-->', tagStart + 4)
        offset = commentEnd >= 0 ? commentEnd + 3 : xmlText.length
        continue
      }
      if (xmlText.startsWith('<![CDATA[', tagStart)) {
        const cdataEnd = xmlText.indexOf(']]>', tagStart + 9)
        if (cdataEnd < 0) {
          this.emitText(xmlText.substring(tagStart + 9), handler, false)
          return
        }
        this.emitText(xmlText.substring(tagStart + 9, cdataEnd), handler, false)
        offset = cdataEnd + 3
        continue
      }
      if (xmlText.startsWith('<?', tagStart)) {
        const instructionEnd = xmlText.indexOf('?>', tagStart + 2)
        offset = instructionEnd >= 0 ? instructionEnd + 2 : xmlText.length
        continue
      }
      const tagEnd = this.findTagEnd(xmlText, tagStart + 1)
      if (tagEnd < 0) {
        return
      }
      let content = xmlText.substring(tagStart + 1, tagEnd).trim()
      offset = tagEnd + 1
      if (content === '' || content.startsWith('!')) {
        continue
      }
      if (content.startsWith('/')) {
        const endName = this.readName(content, 1)
        handler(new OfficeXmlToken(OfficeXmlTokenKind.END, OfficeXmlTokenizer.localName(endName)))
        continue
      }
      let selfClosing = false
      if (content.endsWith('/')) {
        selfClosing = true
        content = content.substring(0, content.length - 1).trim()
      }
      const rawName = this.readName(content, 0)
      if (rawName === '') {
        continue
      }
      const name = OfficeXmlTokenizer.localName(rawName)
      const attributes = this.parseAttributes(content, rawName.length)
      handler(new OfficeXmlToken(OfficeXmlTokenKind.START, name, '', attributes))
      if (selfClosing) {
        handler(new OfficeXmlToken(OfficeXmlTokenKind.END, name))
      }
    }
  }

  private emitText(
    text: string,
    handler: (token: OfficeXmlToken) => void,
    decodeEntities: boolean = true
  ): void {
    if (text === '') {
      return
    }
    handler(new OfficeXmlToken(
      OfficeXmlTokenKind.TEXT,
      '',
      decodeEntities ? this.decodeXmlEntities(text) : text
    ))
  }

  private findTagEnd(xmlText: string, start: number): number {
    let quote = ''
    for (let index = start; index < xmlText.length; index++) {
      const character = xmlText.charAt(index)
      if (quote !== '') {
        if (character === quote) {
          quote = ''
        }
        continue
      }
      if (character === '"' || character === "'") {
        quote = character
      } else if (character === '>') {
        return index
      }
    }
    return -1
  }

  private readName(value: string, start: number): string {
    let end = start
    while (end < value.length) {
      const character = value.charAt(end)
      if (this.isWhitespace(character) || character === '/' || character === '>') {
        break
      }
      end += 1
    }
    return value.substring(start, end)
  }

  private parseAttributes(content: string, start: number): Map<string, string> {
    const attributes: Map<string, string> = new Map()
    let offset = start
    while (offset < content.length) {
      while (offset < content.length && this.isWhitespace(content.charAt(offset))) {
        offset += 1
      }
      if (offset >= content.length) {
        break
      }
      const nameStart = offset
      while (offset < content.length &&
        !this.isWhitespace(content.charAt(offset)) && content.charAt(offset) !== '=') {
        offset += 1
      }
      const name = content.substring(nameStart, offset)
      while (offset < content.length && this.isWhitespace(content.charAt(offset))) {
        offset += 1
      }
      if (content.charAt(offset) !== '=') {
        attributes.set(name, '')
        continue
      }
      offset += 1
      while (offset < content.length && this.isWhitespace(content.charAt(offset))) {
        offset += 1
      }
      if (offset >= content.length) {
        attributes.set(name, '')
        break
      }
      const quote = content.charAt(offset)
      let rawValue = ''
      if (quote === '"' || quote === "'") {
        const valueStart = offset + 1
        const valueEnd = content.indexOf(quote, valueStart)
        if (valueEnd < 0) {
          rawValue = content.substring(valueStart)
          offset = content.length
        } else {
          rawValue = content.substring(valueStart, valueEnd)
          offset = valueEnd + 1
        }
      } else {
        const valueStart = offset
        while (offset < content.length && !this.isWhitespace(content.charAt(offset))) {
          offset += 1
        }
        rawValue = content.substring(valueStart, offset)
      }
      attributes.set(name, this.decodeXmlEntities(rawValue))
    }
    return attributes
  }

  private isWhitespace(value: string): boolean {
    return value === ' ' || value === '\n' || value === '\r' || value === '\t'
  }

  private decodeXmlEntities(value: string): string {
    if (value.indexOf('&') < 0) {
      return value
    }
    let result = ''
    let offset = 0
    while (offset < value.length) {
      const ampersand = value.indexOf('&', offset)
      if (ampersand < 0) {
        result += value.substring(offset)
        break
      }
      result += value.substring(offset, ampersand)
      const semicolon = value.indexOf(';', ampersand + 1)
      if (semicolon < 0 || semicolon - ampersand > 12) {
        result += '&'
        offset = ampersand + 1
        continue
      }
      const entity = value.substring(ampersand + 1, semicolon)
      const decoded = this.decodeEntity(entity)
      if (decoded === '') {
        result += `&${entity};`
      } else {
        result += decoded
      }
      offset = semicolon + 1
    }
    return result
  }

  private decodeEntity(entity: string): string {
    if (entity === 'amp') {
      return '&'
    }
    if (entity === 'lt') {
      return '<'
    }
    if (entity === 'gt') {
      return '>'
    }
    if (entity === 'quot') {
      return '"'
    }
    if (entity === 'apos') {
      return "'"
    }
    if (!entity.startsWith('#')) {
      return ''
    }
    let codePoint = 0
    if (entity.startsWith('#x') || entity.startsWith('#X')) {
      codePoint = Number.parseInt(entity.substring(2), 16)
    } else {
      codePoint = Number.parseInt(entity.substring(1), 10)
    }
    if (!Number.isFinite(codePoint) || codePoint <= 0 || codePoint > 0x10FFFF) {
      return ''
    }
    if (codePoint <= 0xFFFF) {
      return String.fromCharCode(codePoint)
    }
    const adjusted = codePoint - 0x10000
    return String.fromCharCode(0xD800 + (adjusted >> 10), 0xDC00 + (adjusted & 0x3FF))
  }
}

class DocxStyleInfo {
  styleId: string = ''
  name: string = ''
  outlineLevel: number = -1
  paragraphStyle: boolean = false
}

class XlsxSheetInfo {
  name: string = ''
  relationshipId: string = ''
  path: string = ''
}

class XlsxCell {
  reference: string = ''
  row: number = 0
  column: number = 0
  value: string = ''
}

class XlsxWorksheetResult {
  rows: Map<number, XlsxCell[]> = new Map()
  mergeRanges: string[] = []
  cellCount: number = 0
  truncated: boolean = false
}

export class OfficeOpenXmlTextParser {
  private static readonly XLSX_MAX_CELLS: number = 100000
  private static readonly XLSX_MAX_TABLE_COLUMNS: number = 64
  private static readonly XLSX_ROWS_PER_TABLE: number = 50
  private tokenizer: OfficeXmlTokenizer = new OfficeXmlTokenizer()

  parseDocx(documentXml: string, stylesXml: string = '', maxCharacters: number = 2 * 1024 * 1024):
    OfficeOpenXmlParseResult {
    const headingLevels = this.parseDocxHeadingLevels(stylesXml)
    const blocks: string[] = []
    let inParagraph = false
    let captureText = false
    let inNumberingProperties = false
    let paragraphText = ''
    let paragraphStyle = ''
    let paragraphHeadingLevel = -1
    let paragraphListLevel = -1
    let tableDepth = 0
    let currentRows: string[][] = []
    let currentRow: string[] | null = null
    let currentCellParagraphs: string[] | null = null

    this.tokenizer.parse(documentXml, (token: OfficeXmlToken): void => {
      if (token.kind === OfficeXmlTokenKind.TEXT) {
        if (captureText && inParagraph) {
          paragraphText += token.text
        }
        return
      }
      if (token.kind === OfficeXmlTokenKind.START) {
        if (token.name === 'tbl') {
          if (tableDepth === 0) {
            currentRows = []
          }
          tableDepth += 1
          return
        }
        if (token.name === 'tr' && tableDepth === 1) {
          currentRow = []
          return
        }
        if (token.name === 'tc' && tableDepth === 1) {
          currentCellParagraphs = []
          return
        }
        if (token.name === 'p') {
          inParagraph = true
          captureText = false
          inNumberingProperties = false
          paragraphText = ''
          paragraphStyle = ''
          paragraphHeadingLevel = -1
          paragraphListLevel = -1
          return
        }
        if (!inParagraph) {
          return
        }
        if (token.name === 't') {
          captureText = true
        } else if (token.name === 'tab') {
          paragraphText += '    '
        } else if (token.name === 'br' || token.name === 'cr') {
          paragraphText += '\n'
        } else if (token.name === 'pStyle') {
          paragraphStyle = token.attribute('val')
        } else if (token.name === 'outlineLvl') {
          paragraphHeadingLevel = this.parseInteger(token.attribute('val'), -1) + 1
        } else if (token.name === 'numPr') {
          inNumberingProperties = true
        } else if (token.name === 'ilvl' && inNumberingProperties) {
          paragraphListLevel = Math.max(0, this.parseInteger(token.attribute('val'), 0))
        }
        return
      }

      if (token.name === 't') {
        captureText = false
        return
      }
      if (token.name === 'numPr') {
        inNumberingProperties = false
        return
      }
      if (token.name === 'p' && inParagraph) {
        const normalized = this.normalizeParagraphText(paragraphText)
        if (normalized !== '') {
          let formatted = normalized
          let headingLevel = paragraphHeadingLevel
          if (headingLevel < 1 && paragraphStyle !== '') {
            const mappedLevel = headingLevels.get(paragraphStyle)
            headingLevel = mappedLevel === undefined ? -1 : mappedLevel
          }
          if (headingLevel >= 1) {
            formatted = `${this.repeat('#', Math.min(6, headingLevel))} ${normalized}`
          } else if (paragraphListLevel >= 0) {
            formatted = `${this.repeat('  ', Math.min(8, paragraphListLevel))}- ${normalized}`
          }
          if (tableDepth > 0 && currentCellParagraphs !== null) {
            currentCellParagraphs.push(formatted)
          } else {
            blocks.push(formatted)
          }
        }
        inParagraph = false
        captureText = false
        return
      }
      if (token.name === 'tc' && tableDepth === 1 && currentRow !== null) {
        currentRow.push(currentCellParagraphs === null ? '' : currentCellParagraphs.join('<br>'))
        currentCellParagraphs = null
        return
      }
      if (token.name === 'tr' && tableDepth === 1 && currentRow !== null) {
        currentRows.push(currentRow)
        currentRow = null
        return
      }
      if (token.name === 'tbl' && tableDepth > 0) {
        tableDepth -= 1
        if (tableDepth === 0) {
          const table = this.renderDocxTable(currentRows)
          if (table !== '') {
            blocks.push(table)
          }
          currentRows = []
        }
      }
    })

    return this.limitResult(this.normalizeBlocks(blocks), maxCharacters)
  }

  parseXlsx(
    workbookXml: string,
    workbookRelationshipsXml: string,
    sharedStringsXml: string,
    stylesXml: string,
    worksheets: OfficeWorksheetSource[],
    maxCharacters: number = 2 * 1024 * 1024
  ): OfficeOpenXmlParseResult {
    const sheets = this.parseWorkbookSheets(workbookXml)
    const relationships = this.parseRelationships(workbookRelationshipsXml)
    const sharedStrings = this.parseSharedStrings(sharedStringsXml)
    const dateStyles = this.parseXlsxDateStyles(stylesXml)
    const date1904 = this.parseWorkbookDateSystem(workbookXml)
    const sourceByPath: Map<string, string> = new Map()
    for (let index = 0; index < worksheets.length; index++) {
      sourceByPath.set(this.normalizePackagePath('', worksheets[index].path), worksheets[index].xml)
    }
    for (let index = 0; index < sheets.length; index++) {
      const target = relationships.get(sheets[index].relationshipId)
      if (target !== undefined) {
        sheets[index].path = this.normalizePackagePath('xl', target)
      }
    }
    if (sheets.length === 0) {
      for (let index = 0; index < worksheets.length; index++) {
        const fallback = new XlsxSheetInfo()
        fallback.name = `Sheet ${index + 1}`
        fallback.path = this.normalizePackagePath('', worksheets[index].path)
        sheets.push(fallback)
      }
    }

    const blocks: string[] = []
    let totalCells = 0
    let truncated = false
    for (let sheetIndex = 0; sheetIndex < sheets.length; sheetIndex++) {
      const sheet = sheets[sheetIndex]
      let sheetXml = sourceByPath.get(sheet.path)
      if (sheetXml === undefined && sheetIndex < worksheets.length) {
        sheetXml = worksheets[sheetIndex].xml
      }
      if (sheetXml === undefined) {
        continue
      }
      const remainingCells = Math.max(0, OfficeOpenXmlTextParser.XLSX_MAX_CELLS - totalCells)
      if (remainingCells === 0) {
        truncated = true
        break
      }
      const worksheet = this.parseWorksheet(
        sheetXml,
        sharedStrings,
        dateStyles,
        date1904,
        remainingCells
      )
      totalCells += worksheet.cellCount
      truncated = truncated || worksheet.truncated
      blocks.push(`## 工作表：${this.sanitizeHeading(sheet.name)}`)
      if (worksheet.mergeRanges.length > 0) {
        blocks.push(`合并单元格：${worksheet.mergeRanges.join('、')}`)
      }
      const rendered = this.renderWorksheet(worksheet)
      if (rendered !== '') {
        blocks.push(rendered)
      } else {
        blocks.push('（空工作表）')
      }
    }
    if (truncated) {
      blocks.push('（工作簿内容较大，已达到本地解析上限）')
    }
    const limited = this.limitResult(this.normalizeBlocks(blocks), maxCharacters)
    limited.cellCount = totalCells
    limited.truncated = limited.truncated || truncated
    return limited
  }

  private parseDocxHeadingLevels(stylesXml: string): Map<string, number> {
    const levels: Map<string, number> = new Map()
    if (stylesXml === '') {
      return levels
    }
    let current: DocxStyleInfo | null = null
    this.tokenizer.parse(stylesXml, (token: OfficeXmlToken): void => {
      if (token.kind === OfficeXmlTokenKind.START && token.name === 'style') {
        current = new DocxStyleInfo()
        current.styleId = token.attribute('styleId')
        current.paragraphStyle = token.attribute('type') === 'paragraph'
      } else if (token.kind === OfficeXmlTokenKind.START && current !== null && token.name === 'name') {
        current.name = token.attribute('val')
      } else if (token.kind === OfficeXmlTokenKind.START && current !== null && token.name === 'outlineLvl') {
        current.outlineLevel = this.parseInteger(token.attribute('val'), -1)
      } else if (token.kind === OfficeXmlTokenKind.END && token.name === 'style' && current !== null) {
        if (current.paragraphStyle && current.styleId !== '') {
          const level = current.outlineLevel >= 0
            ? current.outlineLevel + 1
            : this.headingLevelFromStyleName(current.name === '' ? current.styleId : current.name)
          if (level >= 1) {
            levels.set(current.styleId, Math.min(6, level))
          }
        }
        current = null
      }
    })
    return levels
  }

  private headingLevelFromStyleName(value: string): number {
    const normalized = value.trim().toLowerCase().replace(/\s/g, '')
    if (normalized === 'title' || normalized === '标题') {
      return 1
    }
    let prefixLength = 0
    if (normalized.startsWith('heading')) {
      prefixLength = 'heading'.length
    } else if (normalized.startsWith('标题')) {
      prefixLength = '标题'.length
    }
    if (prefixLength === 0) {
      return -1
    }
    return this.parseInteger(normalized.substring(prefixLength), 1)
  }

  private renderDocxTable(rows: string[][]): string {
    if (rows.length === 0) {
      return ''
    }
    let width = 0
    for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      width = Math.max(width, rows[rowIndex].length)
    }
    if (width === 0) {
      return ''
    }
    const lines: string[] = []
    lines.push(this.renderMarkdownRow(rows[0], width))
    const separator: string[] = []
    for (let column = 0; column < width; column++) {
      separator.push('---')
    }
    lines.push(this.renderMarkdownRow(separator, width))
    for (let rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      lines.push(this.renderMarkdownRow(rows[rowIndex], width))
    }
    return lines.join('\n')
  }

  private renderMarkdownRow(values: string[], width: number): string {
    const cells: string[] = []
    for (let column = 0; column < width; column++) {
      cells.push(this.escapeMarkdownCell(column < values.length ? values[column] : ''))
    }
    return `| ${cells.join(' | ')} |`
  }

  private parseWorkbookSheets(workbookXml: string): XlsxSheetInfo[] {
    const sheets: XlsxSheetInfo[] = []
    this.tokenizer.parse(workbookXml, (token: OfficeXmlToken): void => {
      if (token.kind === OfficeXmlTokenKind.START && token.name === 'sheet') {
        const sheet = new XlsxSheetInfo()
        sheet.name = token.attribute('name')
        sheet.relationshipId = token.attribute('id')
        sheets.push(sheet)
      }
    })
    return sheets
  }

  private parseRelationships(xmlText: string): Map<string, string> {
    const relationships: Map<string, string> = new Map()
    this.tokenizer.parse(xmlText, (token: OfficeXmlToken): void => {
      if (token.kind === OfficeXmlTokenKind.START && token.name === 'Relationship') {
        const id = token.attribute('Id')
        const target = token.attribute('Target')
        if (id !== '' && target !== '') {
          relationships.set(id, target)
        }
      }
    })
    return relationships
  }

  private parseSharedStrings(xmlText: string): string[] {
    const strings: string[] = []
    if (xmlText === '') {
      return strings
    }
    let inSharedItem = false
    let captureText = false
    let value = ''
    this.tokenizer.parse(xmlText, (token: OfficeXmlToken): void => {
      if (token.kind === OfficeXmlTokenKind.START && token.name === 'si') {
        inSharedItem = true
        value = ''
      } else if (token.kind === OfficeXmlTokenKind.START && inSharedItem && token.name === 't') {
        captureText = true
      } else if (token.kind === OfficeXmlTokenKind.TEXT && captureText) {
        value += token.text
      } else if (token.kind === OfficeXmlTokenKind.END && token.name === 't') {
        captureText = false
      } else if (token.kind === OfficeXmlTokenKind.END && token.name === 'si') {
        strings.push(this.normalizeCellValue(value))
        inSharedItem = false
        captureText = false
      }
    })
    return strings
  }

  private parseWorkbookDateSystem(workbookXml: string): boolean {
    let date1904 = false
    this.tokenizer.parse(workbookXml, (token: OfficeXmlToken): void => {
      if (token.kind === OfficeXmlTokenKind.START && token.name === 'workbookPr') {
        const value = token.attribute('date1904').toLowerCase()
        date1904 = value === '1' || value === 'true'
      }
    })
    return date1904
  }

  private parseXlsxDateStyles(stylesXml: string): Set<number> {
    const result: Set<number> = new Set()
    if (stylesXml === '') {
      return result
    }
    const customFormats: Map<number, string> = new Map()
    let inCellFormats = false
    let styleIndex = 0
    this.tokenizer.parse(stylesXml, (token: OfficeXmlToken): void => {
      if (token.kind === OfficeXmlTokenKind.START && token.name === 'numFmt') {
        const id = this.parseInteger(token.attribute('numFmtId'), -1)
        if (id >= 0) {
          customFormats.set(id, token.attribute('formatCode'))
        }
      } else if (token.kind === OfficeXmlTokenKind.START && token.name === 'cellXfs') {
        inCellFormats = true
        styleIndex = 0
      } else if (token.kind === OfficeXmlTokenKind.START && inCellFormats && token.name === 'xf') {
        const formatId = this.parseInteger(token.attribute('numFmtId'), 0)
        const customCode = customFormats.get(formatId)
        if (this.isDateNumberFormat(formatId, customCode === undefined ? '' : customCode)) {
          result.add(styleIndex)
        }
        styleIndex += 1
      } else if (token.kind === OfficeXmlTokenKind.END && token.name === 'cellXfs') {
        inCellFormats = false
      }
    })
    return result
  }

  private isDateNumberFormat(formatId: number, formatCode: string): boolean {
    if ((formatId >= 14 && formatId <= 22) ||
      (formatId >= 27 && formatId <= 36) ||
      (formatId >= 45 && formatId <= 47) ||
      (formatId >= 50 && formatId <= 58)) {
      return true
    }
    if (formatCode === '') {
      return false
    }
    let normalized = ''
    let inQuote = false
    let inBracket = false
    for (let index = 0; index < formatCode.length; index++) {
      const character = formatCode.charAt(index).toLowerCase()
      if (character === '"') {
        inQuote = !inQuote
      } else if (!inQuote && character === '[') {
        inBracket = true
      } else if (!inQuote && character === ']') {
        inBracket = false
      } else if (!inQuote && !inBracket && character !== '\\') {
        normalized += character
      } else if (character === '\\') {
        index += 1
      }
    }
    return normalized.indexOf('yy') >= 0 || normalized.indexOf('dd') >= 0 ||
      normalized.indexOf('hh') >= 0 || normalized.indexOf('ss') >= 0 ||
      normalized.indexOf('m/') >= 0 || normalized.indexOf('/m') >= 0 ||
      normalized.indexOf('m-') >= 0 || normalized.indexOf('-m') >= 0
  }

  private parseWorksheet(
    xmlText: string,
    sharedStrings: string[],
    dateStyles: Set<number>,
    date1904: boolean,
    maxCells: number
  ): XlsxWorksheetResult {
    const result = new XlsxWorksheetResult()
    let currentRowNumber = 0
    let inferredRowNumber = 0
    let inferredColumn = 0
    let currentReference = ''
    let currentType = ''
    let currentStyle = -1
    let currentValue = ''
    let currentInlineValue = ''
    let currentFormula = ''
    let captureValue = false
    let captureInline = false
    let captureFormula = false
    let inCell = false

    this.tokenizer.parse(xmlText, (token: OfficeXmlToken): void => {
      if (result.truncated) {
        return
      }
      if (token.kind === OfficeXmlTokenKind.TEXT) {
        if (captureValue) {
          currentValue += token.text
        } else if (captureInline) {
          currentInlineValue += token.text
        } else if (captureFormula) {
          currentFormula += token.text
        }
        return
      }
      if (token.kind === OfficeXmlTokenKind.START) {
        if (token.name === 'row') {
          inferredRowNumber += 1
          currentRowNumber = this.parseInteger(token.attribute('r'), inferredRowNumber)
          inferredRowNumber = currentRowNumber
          inferredColumn = 0
        } else if (token.name === 'c') {
          inCell = true
          currentReference = token.attribute('r')
          currentType = token.attribute('t')
          currentStyle = this.parseInteger(token.attribute('s'), -1)
          currentValue = ''
          currentInlineValue = ''
          currentFormula = ''
        } else if (inCell && token.name === 'v') {
          captureValue = true
        } else if (inCell && token.name === 't') {
          captureInline = true
        } else if (inCell && token.name === 'f') {
          captureFormula = true
        } else if (token.name === 'mergeCell') {
          const range = token.attribute('ref')
          if (range !== '' && result.mergeRanges.length < 100) {
            result.mergeRanges.push(range)
          }
        }
        return
      }
      if (token.name === 'v') {
        captureValue = false
      } else if (token.name === 't') {
        captureInline = false
      } else if (token.name === 'f') {
        captureFormula = false
      } else if (token.name === 'c' && inCell) {
        if (result.cellCount >= maxCells) {
          result.truncated = true
          inCell = false
          return
        }
        const coordinate = this.parseCellCoordinate(currentReference, currentRowNumber, inferredColumn + 1)
        inferredColumn = coordinate.column
        const displayValue = this.resolveXlsxCellValue(
          currentType,
          currentValue,
          currentInlineValue,
          currentFormula,
          currentStyle,
          sharedStrings,
          dateStyles,
          date1904
        )
        if (displayValue !== '') {
          const cell = new XlsxCell()
          cell.reference = currentReference === ''
            ? `${this.columnName(coordinate.column)}${coordinate.row}`
            : currentReference
          cell.row = coordinate.row
          cell.column = coordinate.column
          cell.value = displayValue
          let row = result.rows.get(cell.row)
          if (row === undefined) {
            row = []
            result.rows.set(cell.row, row)
          }
          row.push(cell)
          result.cellCount += 1
        }
        inCell = false
      }
    })
    return result
  }

  private parseCellCoordinate(reference: string, fallbackRow: number, fallbackColumn: number): XlsxCell {
    const coordinate = new XlsxCell()
    coordinate.row = Math.max(1, fallbackRow)
    coordinate.column = Math.max(1, fallbackColumn)
    if (reference === '') {
      return coordinate
    }
    let column = 0
    let offset = 0
    while (offset < reference.length) {
      const code = reference.charCodeAt(offset)
      if (code >= 65 && code <= 90) {
        column = column * 26 + code - 64
      } else if (code >= 97 && code <= 122) {
        column = column * 26 + code - 96
      } else {
        break
      }
      offset += 1
    }
    const row = this.parseInteger(reference.substring(offset), fallbackRow)
    coordinate.column = Math.max(1, column > 0 ? column : fallbackColumn)
    coordinate.row = Math.max(1, row)
    return coordinate
  }

  private resolveXlsxCellValue(
    type: string,
    rawValue: string,
    inlineValue: string,
    formula: string,
    styleIndex: number,
    sharedStrings: string[],
    dateStyles: Set<number>,
    date1904: boolean
  ): string {
    let display = ''
    const normalizedRaw = this.normalizeCellValue(rawValue)
    if (type === 's') {
      const sharedIndex = this.parseInteger(normalizedRaw, -1)
      display = sharedIndex >= 0 && sharedIndex < sharedStrings.length
        ? sharedStrings[sharedIndex]
        : normalizedRaw
    } else if (type === 'inlineStr') {
      display = this.normalizeCellValue(inlineValue)
    } else if (type === 'b') {
      display = normalizedRaw === '1' ? 'TRUE' : 'FALSE'
    } else if (type === 'e') {
      display = normalizedRaw === '' ? '#ERROR' : normalizedRaw
    } else if (type === 'd') {
      display = normalizedRaw
    } else if (dateStyles.has(styleIndex) && normalizedRaw !== '') {
      display = this.formatExcelDate(normalizedRaw, date1904)
    } else {
      display = normalizedRaw
    }
    const normalizedFormula = this.normalizeCellValue(formula)
    if (normalizedFormula !== '') {
      if (display === '') {
        return `=${normalizedFormula}`
      }
      return `${display}（公式：=${normalizedFormula}）`
    }
    return display
  }

  private formatExcelDate(rawValue: string, date1904: boolean): string {
    const serial = Number(rawValue)
    if (!Number.isFinite(serial)) {
      return rawValue
    }
    let days = Math.floor(serial)
    const fraction = serial - days
    let epoch = Date.UTC(1899, 11, 31)
    if (date1904) {
      epoch = Date.UTC(1904, 0, 1)
    } else if (days >= 60) {
      days -= 1
    }
    const milliseconds = epoch + days * 86400000 + Math.round(fraction * 86400000)
    const date = new Date(milliseconds)
    if (!Number.isFinite(date.getTime())) {
      return rawValue
    }
    const iso = date.toISOString()
    if (fraction === 0) {
      return iso.substring(0, 10)
    }
    return iso.substring(0, 19).replace('T', ' ')
  }

  private renderWorksheet(worksheet: XlsxWorksheetResult): string {
    const rowNumbers: number[] = []
    worksheet.rows.forEach((_cells: XlsxCell[], rowNumber: number): void => {
      rowNumbers.push(rowNumber)
    })
    rowNumbers.sort((left: number, right: number): number => left - right)
    if (rowNumbers.length === 0) {
      return ''
    }
    let minColumn = Number.MAX_SAFE_INTEGER
    let maxColumn = 0
    for (let rowIndex = 0; rowIndex < rowNumbers.length; rowIndex++) {
      const cells = worksheet.rows.get(rowNumbers[rowIndex])
      if (cells === undefined) {
        continue
      }
      for (let cellIndex = 0; cellIndex < cells.length; cellIndex++) {
        minColumn = Math.min(minColumn, cells[cellIndex].column)
        maxColumn = Math.max(maxColumn, cells[cellIndex].column)
      }
    }
    const width = maxColumn - minColumn + 1
    if (width <= 0) {
      return ''
    }
    if (width > OfficeOpenXmlTextParser.XLSX_MAX_TABLE_COLUMNS) {
      return this.renderSparseWorksheet(worksheet, rowNumbers)
    }
    const sections: string[] = []
    for (let start = 0; start < rowNumbers.length; start += OfficeOpenXmlTextParser.XLSX_ROWS_PER_TABLE) {
      const end = Math.min(rowNumbers.length, start + OfficeOpenXmlTextParser.XLSX_ROWS_PER_TABLE)
      const firstRow = rowNumbers[start]
      const lastRow = rowNumbers[end - 1]
      const lines: string[] = []
      if (rowNumbers.length > OfficeOpenXmlTextParser.XLSX_ROWS_PER_TABLE) {
        lines.push(`### 行 ${firstRow}–${lastRow}`)
      }
      const header: string[] = ['行']
      const separator: string[] = ['---']
      for (let column = minColumn; column <= maxColumn; column++) {
        header.push(this.columnName(column))
        separator.push('---')
      }
      lines.push(this.renderMarkdownRow(header, header.length))
      lines.push(this.renderMarkdownRow(separator, separator.length))
      for (let rowIndex = start; rowIndex < end; rowIndex++) {
        const rowNumber = rowNumbers[rowIndex]
        const values: string[] = []
        values.push(`${rowNumber}`)
        for (let column = minColumn; column <= maxColumn; column++) {
          values.push('')
        }
        const cells = worksheet.rows.get(rowNumber)
        if (cells !== undefined) {
          for (let cellIndex = 0; cellIndex < cells.length; cellIndex++) {
            const position = cells[cellIndex].column - minColumn + 1
            if (position >= 1 && position < values.length) {
              values[position] = cells[cellIndex].value
            }
          }
        }
        lines.push(this.renderMarkdownRow(values, values.length))
      }
      sections.push(lines.join('\n'))
    }
    return sections.join('\n\n')
  }

  private renderSparseWorksheet(worksheet: XlsxWorksheetResult, rowNumbers: number[]): string {
    const lines: string[] = []
    for (let rowIndex = 0; rowIndex < rowNumbers.length; rowIndex++) {
      const cells = worksheet.rows.get(rowNumbers[rowIndex])
      if (cells === undefined) {
        continue
      }
      cells.sort((left: XlsxCell, right: XlsxCell): number => left.column - right.column)
      const values: string[] = []
      for (let cellIndex = 0; cellIndex < cells.length; cellIndex++) {
        values.push(`[${cells[cellIndex].reference}] ${cells[cellIndex].value}`)
      }
      lines.push(values.join('；'))
    }
    return lines.join('\n')
  }

  private normalizePackagePath(baseDirectory: string, target: string): string {
    let normalizedTarget = target.replace(/\\/g, '/')
    while (normalizedTarget.startsWith('/')) {
      normalizedTarget = normalizedTarget.substring(1)
    }
    const pieces: string[] = []
    if (baseDirectory !== '' && !normalizedTarget.startsWith(`${baseDirectory}/`)) {
      const basePieces = baseDirectory.split('/')
      for (let index = 0; index < basePieces.length; index++) {
        if (basePieces[index] !== '') {
          pieces.push(basePieces[index])
        }
      }
    }
    const targetPieces = normalizedTarget.split('/')
    for (let index = 0; index < targetPieces.length; index++) {
      const piece = targetPieces[index]
      if (piece === '' || piece === '.') {
        continue
      }
      if (piece === '..') {
        if (pieces.length > 0) {
          pieces.pop()
        }
      } else {
        pieces.push(piece)
      }
    }
    return pieces.join('/')
  }

  private columnName(column: number): string {
    let value = Math.max(1, column)
    let result = ''
    while (value > 0) {
      const remainder = (value - 1) % 26
      result = String.fromCharCode(65 + remainder) + result
      value = Math.floor((value - 1) / 26)
    }
    return result
  }

  private normalizeParagraphText(value: string): string {
    return value
      .replace(/\u00A0/g, ' ')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim()
  }

  private normalizeCellValue(value: string): string {
    return value
      .replace(/\r/g, '\n')
      .replace(/\u00A0/g, ' ')
      .replace(/[ \t]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim()
  }

  private normalizeBlocks(blocks: string[]): string {
    const normalized: string[] = []
    for (let index = 0; index < blocks.length; index++) {
      const block = blocks[index].trim()
      if (block !== '') {
        normalized.push(block)
      }
    }
    return normalized.join('\n\n').trim()
  }

  private limitResult(text: string, maxCharacters: number): OfficeOpenXmlParseResult {
    const normalizedLimit = Math.max(1000, maxCharacters)
    if (text.length <= normalizedLimit) {
      return new OfficeOpenXmlParseResult(text, false)
    }
    const marker = '\n\n（文档内容较大，已截断）'
    const end = Math.max(0, normalizedLimit - marker.length)
    return new OfficeOpenXmlParseResult(`${text.substring(0, end).trim()}${marker}`, true)
  }

  private escapeMarkdownCell(value: string): string {
    return value.replace(/\|/g, '\\|').replace(/\n/g, '<br>')
  }

  private sanitizeHeading(value: string): string {
    const normalized = this.normalizeCellValue(value).replace(/#/g, '')
    return normalized === '' ? '未命名' : normalized
  }

  private parseInteger(value: string, fallback: number): number {
    if (value.trim() === '') {
      return fallback
    }
    const parsed = Number.parseInt(value, 10)
    return Number.isFinite(parsed) ? parsed : fallback
  }

  private repeat(value: string, count: number): string {
    let result = ''
    for (let index = 0; index < count; index++) {
      result += value
    }
    return result
  }
}
