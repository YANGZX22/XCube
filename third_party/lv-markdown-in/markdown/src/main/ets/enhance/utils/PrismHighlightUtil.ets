import { codeStringToColorString, PrismBlock, PrismNode, PrismRes } from '@cangjie-tpc/prism_hybrid'
import { CodeHighlight } from '../model/CodeHighlight'
import { HighlightCode, HighlightNode } from '../model/highlightNode'

interface HighlightCacheValue {
  key: string
  value: HighlightNode[]
}

const highlightCache: Map<string, HighlightCacheValue> = new Map()
const highlightCacheOrder: string[] = []
const MAX_CACHE_SIZE = 64

function normalizeLanguage(language?: string): string {
  const lang = (language || 'text').trim().toLowerCase()
  if (lang == 'js') {
    return 'javascript'
  }
  if (lang == 'ts' || lang == 'ets') {
    return 'typescript'
  }
  if (lang == 'py') {
    return 'python'
  }
  if (lang == 'c++') {
    return 'cpp'
  }
  if (lang == 'htm') {
    return 'html'
  }
  return lang || 'text'
}

function buildCacheKey(code: string, language: string, colors: CodeHighlight, isDarkTheme: boolean): string {
  return `${language}\n${isDarkTheme ? 'dark' : 'light'}\n${JSON.stringify(colors)}\n${code}`
}

function saveCache(key: string, value: HighlightNode[]) {
  if (!highlightCache.has(key)) {
    highlightCacheOrder.push(key)
  }
  highlightCache.set(key, {
    key: key,
    value: value
  })
  while (highlightCacheOrder.length > MAX_CACHE_SIZE) {
    const oldKey = highlightCacheOrder.shift()
    if (oldKey) {
      highlightCache.delete(oldKey)
    }
  }
}

function numberColorToString(color: number | undefined, fallback: string): string {
  if (color == undefined) {
    return fallback
  }
  const unsigned = color >>> 0
  let hex = unsigned.toString(16)
  while (hex.length < 8) {
    hex = `0${hex}`
  }
  return `#${hex}`
}

function convertPrismResult(result: PrismRes, fallbackColor: string): HighlightNode[] {
  // CodeRender 用固定 height(22) 的 Row 渲染每个 HighlightNode,契约是「一 row = 一视觉行」。
  // 但 prism_hybrid 只在 token 文本恰好等于 "\n" 时切分 block(见 index.cj),
  // 多行 token(Python docstring、块注释、"\n\n" 空行、"\n   " 换行+缩进的空白)的内嵌换行
  // 不是 block 边界,会整段塞进一个 block。若直接映射成一个 row,固定行高会溢出、与下方行重叠。
  // 因此这里按 \n 把每个 token 拆进正确的视觉行:block 边界算一个换行,token 内嵌 \n 也各算一个换行。
  const blocks = Array.from(result.getListColor())
  const rows: HighlightNode[] = []
  let current: HighlightCode[] = []
  blocks.forEach((block: PrismBlock, blockIdx: number) => {
    // 相邻 block 之间隐含一个被消费掉的 "\n" token → 开新行。
    if (blockIdx > 0) {
      const row: HighlightNode = { type: 'row', code: current }
      rows.push(row)
      current = []
    }
    const nodes = Array.from(block.getList())
    nodes.forEach((node: PrismNode) => {
      const color: string = numberColorToString(node.getColor(), fallbackColor)
      const type: string = node.getType()
      const segments: string[] = node.getText().split('\n')
      segments.forEach((seg: string, segIdx: number) => {
        if (segIdx > 0) {
          const row: HighlightNode = { type: 'row', code: current }
          rows.push(row)
          current = []
        }
        if (seg.length > 0) {
          const cell: HighlightCode = { color: color, text: seg, type: type }
          current.push(cell)
        }
      })
    })
  })
  const lastRow: HighlightNode = { type: 'row', code: current }
  rows.push(lastRow)
  return rows
}

function buildPlainTextRows(code: string, normalColor: string): HighlightNode[] {
  return code.split('\n').map((line: string): HighlightNode => {
    const cell: HighlightCode = { color: normalColor, text: line, type: 'normal' }
    const row: HighlightNode = { type: 'row', code: [cell] }
    return row
  })
}

export namespace PrismHighlightUtil {
  export async function highlight(code: string, colors: CodeHighlight, language?: string,
    isDarkTheme: boolean = false): Promise<HighlightNode[]> {
    const normalizedLanguage = normalizeLanguage(language)
    const safeCode = code || ''
    const key = buildCacheKey(safeCode, normalizedLanguage, colors, isDarkTheme)
    const cached = highlightCache.get(key)
    if (cached) {
      return cached.value
    }

    try {
      const prismRes: PrismRes = await codeStringToColorString(safeCode, normalizedLanguage, isDarkTheme)
      const result = convertPrismResult(prismRes, colors.normal as string)
      saveCache(key, result)
      return result
    } catch (_err) {
      const result = buildPlainTextRows(safeCode, colors.normal as string)
      saveCache(key, result)
      return result
    }
  }

  // 只读查询缓存(命中可能是已算出的 Prism 结果或失败兜底纯文本结果),不触发任何计算。
  // 供 CodeRender 同步占位阶段复用,避免长代码每个流式 chunk 都触发重复高亮。
  export function getCached(code: string, colors: CodeHighlight, language?: string,
    isDarkTheme: boolean = false): HighlightNode[] | undefined {
    const normalizedLanguage = normalizeLanguage(language)
    const key = buildCacheKey(code || '', normalizedLanguage, colors, isDarkTheme)
    return highlightCache.get(key)?.value
  }
}
