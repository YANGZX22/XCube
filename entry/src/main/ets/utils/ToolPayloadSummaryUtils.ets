import { pickLocalizedText } from './LocalizedTextUtils'

export class ToolPreviewEntry {
  label: string = ''
  value: string = ''

  constructor(label: string = '', value: string = '') {
    this.label = label
    this.value = value
  }
}

export class ToolPayloadPreview {
  summary: string = ''
  entries: ToolPreviewEntry[] = []
  rawPreview: string = '{}'
  rawTruncated: boolean = false

  constructor(
    summary: string = '',
    entries: ToolPreviewEntry[] = [],
    rawPreview: string = '{}',
    rawTruncated: boolean = false
  ) {
    this.summary = summary
    this.entries = entries
    this.rawPreview = rawPreview
    this.rawTruncated = rawTruncated
  }
}

const DEFAULT_ARGUMENT_PREVIEW = '{}'
const RESULT_ENTRY_SKIP_KEYS: string[] = ['content', 'results', 'forecast', 'data', 'items']

function truncateText(text: string, maxLength: number): string {
  if (text.length <= maxLength) {
    return text
  }
  return `${text.substring(0, maxLength).trimEnd()}...`
}

function stringifyValueForSummary(value: Object): string {
  if (value === null) {
    return 'null'
  }
  if (typeof value === 'string') {
    return truncateText(value, 60)
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return `${value}`
  }
  if (Array.isArray(value as Array<Object>)) {
    const arrayValue = value as Array<Object>
    if (arrayValue.length === 0) {
      return '[]'
    }
    const items: string[] = []
    const maxItems = Math.min(arrayValue.length, 3)
    for (let i = 0; i < maxItems; i++) {
      items.push(stringifyValueForSummary(arrayValue[i]))
    }
    const suffix = arrayValue.length > maxItems ? ', ...' : ''
    return `[${items.join(', ')}${suffix}]`
  }
  try {
    const serialized = JSON.stringify(value)
    if (serialized === undefined) {
      return `${value}`
    }
    return truncateText(serialized, 60)
  } catch (error) {
    return `${value}`
  }
}

function buildEntriesFromRecord(record: Record<string, Object>, limit: number, skipKeys: string[] = []): ToolPreviewEntry[] {
  const entries: ToolPreviewEntry[] = []
  const keys = Object.keys(record)
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i]
    if (skipKeys.includes(key)) {
      continue
    }
    const value = record[key]
    if (value === undefined) {
      continue
    }
    entries.push(new ToolPreviewEntry(key, stringifyValueForSummary(value)))
    if (entries.length >= limit) {
      break
    }
  }
  return entries
}

function buildSummaryFromEntries(entries: ToolPreviewEntry[], maxLength: number): string {
  const parts: string[] = []
  for (let i = 0; i < entries.length; i++) {
    parts.push(`${entries[i].label}: ${entries[i].value}`)
  }
  return truncateText(parts.join(' · '), maxLength)
}

function tryParseJson(raw: string): Object | null {
  const trimmed = raw.trim()
  if (trimmed === '') {
    return null
  }
  try {
    return JSON.parse(trimmed) as Object
  } catch (error) {
    return null
  }
}

function buildRawPreview(raw: string, parsed: Object | null, emptyFallback: string, maxLength: number): ToolPayloadPreview {
  let preview = raw.trim()
  if (preview === '') {
    preview = emptyFallback
  } else if (parsed !== null) {
    try {
      preview = JSON.stringify(parsed, null, 2)
    } catch (error) {
      preview = raw.trim()
    }
  }
  const truncated = preview.length > maxLength
  return new ToolPayloadPreview('', [], truncated ? `${preview.substring(0, maxLength).trimEnd()}\n...` : preview, truncated)
}

function extractContentText(record: Record<string, Object>): string {
  const content = record['content']
  if (content === undefined || !Array.isArray(content as Array<Object>)) {
    return ''
  }
  const blocks = content as Array<Record<string, Object>>
  const texts: string[] = []
  for (let i = 0; i < blocks.length; i++) {
    if (`${blocks[i]['type']}` === 'text' && blocks[i]['text'] !== undefined) {
      texts.push(`${blocks[i]['text']}`)
    }
  }
  return texts.join('\n').trim()
}

export function buildToolArgumentsPreview(argumentsJson: string, entryLimit: number = 4, rawMaxLength: number = 800): ToolPayloadPreview {
  const trimmed = argumentsJson.trim()
  const parsed = tryParseJson(trimmed)
  const rawPreview = buildRawPreview(argumentsJson, parsed, DEFAULT_ARGUMENT_PREVIEW, rawMaxLength)
  let summary = pickLocalizedText('无参数', 'No arguments')
  let entries: ToolPreviewEntry[] = []

  if (parsed !== null && !Array.isArray(parsed as Array<Object>) && typeof parsed === 'object') {
    const record = parsed as Record<string, Object>
    entries = buildEntriesFromRecord(record, entryLimit)
    if (entries.length > 0) {
      summary = buildSummaryFromEntries(entries, 120)
    } else if (Object.keys(record).length > 0) {
      summary = pickLocalizedText('包含结构化参数', 'Structured arguments')
    }
  } else if (parsed !== null) {
    summary = truncateText(stringifyValueForSummary(parsed), 120)
  } else if (trimmed !== '') {
    summary = truncateText(trimmed, 120)
  }

  return new ToolPayloadPreview(summary, entries, rawPreview.rawPreview, rawPreview.rawTruncated)
}

export function buildToolResultPreview(content: string, entryLimit: number = 4, rawMaxLength: number = 1000): ToolPayloadPreview {
  const trimmed = content.trim()
  const parsed = tryParseJson(trimmed)
  const rawPreview = buildRawPreview(content, parsed, pickLocalizedText('无结果内容', 'No result content'), rawMaxLength)
  const completedText = pickLocalizedText('已完成', 'Completed')
  let summary = completedText
  let entries: ToolPreviewEntry[] = []

  if (parsed !== null && !Array.isArray(parsed as Array<Object>) && typeof parsed === 'object') {
    const record = parsed as Record<string, Object>
    if (record['error'] !== undefined) {
      summary = truncateText(`${record['error']}`, 140)
    } else if (record['summary'] !== undefined && `${record['summary']}`.trim() !== '') {
      summary = truncateText(`${record['summary']}`.trim(), 140)
    } else if (record['message'] !== undefined && `${record['message']}`.trim() !== '') {
      summary = truncateText(`${record['message']}`.trim(), 140)
    } else if (record['results'] !== undefined && Array.isArray(record['results'] as Array<Object>)) {
      const resultCount = (record['results'] as Array<Object>).length
      summary = pickLocalizedText(`返回 ${resultCount} 条结果`, `${resultCount} results returned`)
    } else if (record['forecast'] !== undefined && Array.isArray(record['forecast'] as Array<Object>)) {
      const forecastDays = (record['forecast'] as Array<Object>).length
      summary = pickLocalizedText(`${forecastDays} 天预报`, `${forecastDays}-day forecast`)
    } else {
      const contentText = extractContentText(record)
      if (contentText !== '') {
        summary = truncateText(contentText, 140)
      }
    }

    entries = buildEntriesFromRecord(record, entryLimit, RESULT_ENTRY_SKIP_KEYS)
    if (summary === completedText && entries.length > 0) {
      summary = buildSummaryFromEntries(entries, 140)
    }
  } else if (parsed !== null) {
    summary = truncateText(stringifyValueForSummary(parsed), 140)
  } else if (trimmed !== '') {
    summary = truncateText(trimmed, 140)
  }

  return new ToolPayloadPreview(summary, entries, rawPreview.rawPreview, rawPreview.rawTruncated)
}
