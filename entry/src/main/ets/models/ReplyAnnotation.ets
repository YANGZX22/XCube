import { pickPromptText, PromptLanguage } from '../utils/PromptLanguageUtils'

export const MAX_REPLY_ANNOTATIONS: number = 5

export interface ReplyAnnotation {
  quote: string
  comment: string
}

export function parseReplyAnnotations(raw: string): ReplyAnnotation[] {
  if (raw === '') return []
  try {
    return normalizeReplyAnnotations(JSON.parse(raw) as ReplyAnnotation[])
  } catch (_) {
    return []
  }
}

export function normalizeReplyAnnotations(entries?: ReplyAnnotation[]): ReplyAnnotation[] {
  const notes: ReplyAnnotation[] = []
  if (!Array.isArray(entries)) return notes
  for (const entry of entries) {
    if (entry && typeof entry.quote === 'string' && entry.quote.trim() !== '' && typeof entry.comment === 'string') {
      notes.push({ quote: entry.quote, comment: entry.comment })
      if (notes.length === MAX_REPLY_ANNOTATIONS) break
    }
  }
  return notes
}

export function formatAnnotatedMessage(text: string, count: number, language: PromptLanguage): string {
  if (count === 0) return text
  const label = pickPromptText(language, `${count} 条注释`, `${count} ${count === 1 ? 'annotation' : 'annotations'}`)
  return text.trim() === '' ? label : label + '\n' + text
}

export function buildAnnotatedRequest(text: string, notes: ReplyAnnotation[], language: PromptLanguage): string {
  if (notes.length === 0) return text
  const instruction = pickPromptText(language,
    '用户特别强调了先前助手回复中的以下片段。请重点回应每处选文（quote），并结合对应的用户评论（comment）。',
    'The user highlighted the following passages from earlier assistant replies. Focus on each quoted passage (quote) and address its accompanying user comment (comment), if present.')
  const context = instruction + '\n' + JSON.stringify(notes)
  return text.trim() === '' ? context : text + '\n\n' + context
}
