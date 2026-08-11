export const DEFAULT_JSON_RESPONSE_MAX_LENGTH: number = 8000

export class JsonResponseContent {
  isJson: boolean = false
  content: string = ''
  truncated: boolean = false

  constructor(isJson: boolean, content: string = '', truncated: boolean = false) {
    this.isJson = isJson
    this.content = content
    this.truncated = truncated
  }
}

function removeUtf8Bom(text: string): string {
  if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) {
    return text.substring(1)
  }
  return text
}

/**
 * Detects a JSON HTTP response and formats it for tool output.
 * Invalid JSON is deliberately left to the HTML/text parsing path.
 */
export function parseJsonResponseContent(
  raw: string,
  maxLength: number = DEFAULT_JSON_RESPONSE_MAX_LENGTH
): JsonResponseContent {
  const normalized = removeUtf8Bom(raw.trim())
  if (normalized === '') {
    return new JsonResponseContent(false)
  }

  let formatted = ''
  try {
    const parsed = JSON.parse(normalized) as Object
    formatted = JSON.stringify(parsed, null, 2)
  } catch (_error) {
    return new JsonResponseContent(false)
  }

  if (formatted.length <= maxLength) {
    return new JsonResponseContent(true, formatted)
  }

  const suffix = '\n...（JSON 响应过长，已截断）'
  const availableLength = Math.max(0, maxLength - suffix.length)
  return new JsonResponseContent(
    true,
    `${formatted.substring(0, availableLength).trimEnd()}${suffix}`,
    true
  )
}
