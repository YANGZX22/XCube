/**
 * OpenAI-compatible gateways are not fully consistent about streamed text.
 * The official Chat Completions shape uses a string, while a few relays reuse
 * the Responses-style text-part array inside choices[0].delta.content.
 */
export interface OpenAIStreamTextPart {
  type?: string
  text?: string
  content?: string
}

export interface OpenAIStreamReasoningDetail {
  type?: string
  text?: string
}

export interface NormalizedOpenAIStreamContent {
  content: string
  reasoningContent: string
}

export interface OpenAIResponsesFunctionCallItem {
  type?: string
  id?: string
  call_id?: string
  name?: string
  arguments?: string
}

interface OpenAIResponsesStreamError {
  message?: string
}

interface OpenAIResponsesStreamResponse {
  status?: string
  error?: OpenAIResponsesStreamError
}

export interface OpenAIResponsesCompatibleStreamEvent {
  type?: string
  delta?: string
  arguments?: string
  output_index?: number
  call_id?: string
  item?: OpenAIResponsesFunctionCallItem
  error?: OpenAIResponsesStreamError
  response?: OpenAIResponsesStreamResponse
}

export interface NormalizedOpenAIResponsesToolDelta {
  index: number
  id?: string
  functionName?: string
  arguments?: string
  argumentsAreSnapshot?: boolean
}

export interface NormalizedOpenAIResponsesStreamEvent {
  content: string
  reasoningContent: string
  toolCallDeltas: NormalizedOpenAIResponsesToolDelta[]
  finishReason?: string
  errorMessage?: string
}

export function normalizeOpenAIStreamText(
  value?: string | OpenAIStreamTextPart | OpenAIStreamTextPart[] | null
): string {
  if (typeof value === 'string') {
    return value
  }
  if (value !== undefined && value !== null && !Array.isArray(value)) {
    if (typeof value.text === 'string') {
      return value.text
    }
    return typeof value.content === 'string' ? value.content : ''
  }
  if (!Array.isArray(value)) {
    return ''
  }

  let result = ''
  for (let i = 0; i < value.length; i++) {
    const part = value[i]
    if (typeof part.text === 'string') {
      result += part.text
    } else if (typeof part.content === 'string') {
      result += part.content
    }
  }
  return result
}

export function splitOpenAIStreamContent(
  value?: string | OpenAIStreamTextPart | OpenAIStreamTextPart[] | null
): NormalizedOpenAIStreamContent {
  const result: NormalizedOpenAIStreamContent = { content: '', reasoningContent: '' }
  if (typeof value === 'string') {
    result.content = value
    return result
  }
  if (value === undefined || value === null) {
    return result
  }

  const parts: OpenAIStreamTextPart[] = Array.isArray(value) ? value : [value]
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i]
    const text = typeof part.text === 'string' ? part.text :
      (typeof part.content === 'string' ? part.content : '')
    if (text === '') {
      continue
    }
    const type = part.type !== undefined ? part.type.toLowerCase() : ''
    if (type.includes('reasoning') || type.includes('thinking') || type.includes('analysis')) {
      result.reasoningContent += text
    } else {
      result.content += text
    }
  }
  return result
}

export function joinOpenAIStreamReasoningDetails(
  details?: OpenAIStreamReasoningDetail[] | null
): string {
  if (!Array.isArray(details)) {
    return ''
  }

  let result = ''
  for (let i = 0; i < details.length; i++) {
    const text = details[i].text
    if (typeof text === 'string') {
      result += text
    }
  }
  return result
}

/** Normalize LF, CRLF and legacy CR streams before splitting SSE lines. */
export function normalizeSseLineEndings(value: string): string {
  return value.replace(/\r\n/g, '\n').replace(/\r/g, '\n')
}

/** Some compatible gateways prefix the first SSE line with a UTF-8 BOM. */
export function stripSseBom(value: string): string {
  return value.startsWith('\uFEFF') ? value.substring(1) : value
}

/** Return one JSON payload from an SSE data line, or an empty string for metadata/DONE lines. */
export function extractSseDataPayload(line: string): string {
  const trimmedLine = stripSseBom(line.trim()).trim()
  if (trimmedLine === '' || trimmedLine === '[DONE]' ||
    trimmedLine === 'data: [DONE]' || trimmedLine === 'data:[DONE]') {
    return ''
  }
  if (trimmedLine.startsWith('data:')) {
    const payload = trimmedLine.substring(5).trim()
    return payload === '[DONE]' ? '' : payload
  }
  if (trimmedLine.startsWith('{') || trimmedLine.startsWith('[')) {
    return trimmedLine
  }
  return ''
}

/**
 * Normalize the fine-grained Responses API event family into the same deltas
 * used by the chat UI. This covers both the documented OfoxAI events and the
 * reasoning-summary events emitted by OpenAI-compatible reasoning models.
 */
export function normalizeOpenAIResponsesStreamEvent(
  eventObject: object
): NormalizedOpenAIResponsesStreamEvent {
  const event = eventObject as OpenAIResponsesCompatibleStreamEvent
  const result: NormalizedOpenAIResponsesStreamEvent = {
    content: '',
    reasoningContent: '',
    toolCallDeltas: []
  }
  const eventType = event.type !== undefined ? event.type : ''

  if ((eventType === 'response.output_text.delta' || eventType === 'response.refusal.delta') &&
    event.delta !== undefined) {
    result.content = event.delta
    return result
  }
  if ((eventType === 'response.reasoning_summary_text.delta' ||
    eventType === 'response.reasoning_text.delta' ||
    eventType === 'response.reasoning_summary.delta' ||
    eventType === 'response.reasoning.delta' ||
    eventType === 'response.reasoning_content.delta' ||
    eventType === 'response.thinking.delta') && event.delta !== undefined) {
    result.reasoningContent = event.delta
    return result
  }

  if (eventType === 'response.output_item.added' || eventType === 'response.output_item.done') {
    const item = event.item
    if (item !== undefined && item.type === 'function_call') {
      const index = event.output_index !== undefined ? event.output_index : 0
      const callId = item.call_id || event.call_id || item.id || ''
      result.toolCallDeltas.push({
        index: index,
        id: callId !== '' ? callId : undefined,
        functionName: item.name !== undefined && item.name !== '' ? item.name : undefined,
        arguments: item.arguments !== undefined && item.arguments !== '' ? item.arguments : undefined,
        argumentsAreSnapshot: eventType === 'response.output_item.done'
      })
    }
    return result
  }

  if (eventType === 'response.function_call_arguments.delta' ||
    eventType === 'response.function_call_arguments.done') {
    const index = event.output_index !== undefined ? event.output_index : 0
    const callId = event.call_id !== undefined ? event.call_id : ''
    const args = eventType === 'response.function_call_arguments.done'
      ? (event.arguments !== undefined ? event.arguments : event.delta)
      : event.delta
    result.toolCallDeltas.push({
      index: index,
      id: callId !== '' ? callId : undefined,
      arguments: args !== undefined && args !== '' ? args : undefined,
      argumentsAreSnapshot: eventType === 'response.function_call_arguments.done'
    })
    return result
  }

  if (eventType === 'response.completed') {
    result.finishReason = 'stop'
    return result
  }
  if (eventType === 'error' || eventType === 'response.failed' || eventType === 'response.incomplete') {
    const errorMessage = event.error?.message || event.response?.error?.message || ''
    result.errorMessage = errorMessage !== '' ? errorMessage :
      (eventType === 'response.incomplete' ? 'Responses API response incomplete' : 'Responses API response failed')
  }
  return result
}
