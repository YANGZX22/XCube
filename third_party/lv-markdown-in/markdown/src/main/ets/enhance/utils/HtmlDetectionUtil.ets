interface MarkdownFence {
  marker: string
  length: number
}

function getFenceStart(line: string): MarkdownFence | null {
  const match = line.match(/^([\s\u200B\uFEFF]*)(`{3,}|~{3,})([^\r\n]*)$/)
  if (match === null) {
    return null
  }
  const marker = match[2]
  const info = (match[3] || '').trim()
  if (marker[0] === '`' && info.includes('`')) {
    return null
  }
  return {
    marker: marker[0],
    length: marker.length
  }
}

function isFenceClose(line: string, fence: MarkdownFence): boolean {
  const match = line.match(/^[\s\u200B\uFEFF]*(`+|~+)[\s\u200B\uFEFF]*$/)
  return match !== null && match[1][0] === fence.marker && match[1].length >= fence.length
}

function stripMarkdownCode(input: string): string {
  const lines = input.replace(/\r/g, '').split('\n')
  const visibleLines: string[] = []
  let fence: MarkdownFence | null = null

  for (let index = 0; index < lines.length; index++) {
    const line = lines[index]
    if (fence !== null) {
      if (isFenceClose(line, fence)) {
        fence = null
      }
      visibleLines.push('')
      continue
    }

    const nextFence = getFenceStart(line)
    if (nextFence !== null) {
      fence = nextFence
      visibleLines.push('')
      continue
    }

    // HTML-like text inside a Markdown code span must not switch the whole
    // document to the HTML-to-Markdown conversion path.
    visibleLines.push(line.replace(/(`+)([^`\n]*?)\1/g, ''))
  }

  return visibleLines.join('\n')
}

export function isHtmlLike(input: string): boolean {
  const visibleText = stripMarkdownCode(input)
  return /<(?:h[1-6]|p|div|span|br|ul|ol|li|table|thead|tbody|tr|td|th|a|img|blockquote|pre|code|font)\b[\s/>]/i
    .test(visibleText)
}
