import { extname } from 'node:path'

export const MAX_IMAGE_BYTES = 25 * 1024 * 1024
export const MAX_JSON_BODY_BYTES = 36 * 1024 * 1024
export const MAX_PROMPT_CHARACTERS = 4000

const MIME_EXTENSIONS = new Map([
  ['image/jpeg', '.jpg'],
  ['image/png', '.png'],
  ['image/gif', '.gif'],
  ['image/webp', '.webp']
])

function hasBytes(buffer, expected, offset = 0) {
  if (buffer.length < offset + expected.length) {
    return false
  }
  for (let index = 0; index < expected.length; index += 1) {
    if (buffer[offset + index] !== expected[index]) {
      return false
    }
  }
  return true
}

export function sniffImageMime(buffer) {
  if (hasBytes(buffer, [0xff, 0xd8, 0xff])) {
    return 'image/jpeg'
  }
  if (hasBytes(buffer, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return 'image/png'
  }
  if (buffer.length >= 6) {
    const signature = buffer.subarray(0, 6).toString('ascii')
    if (signature === 'GIF87a' || signature === 'GIF89a') {
      return 'image/gif'
    }
  }
  if (buffer.length >= 12 && buffer.subarray(0, 4).toString('ascii') === 'RIFF' &&
    buffer.subarray(8, 12).toString('ascii') === 'WEBP') {
    return 'image/webp'
  }
  return ''
}

export function sanitizeFileName(value, mimeType) {
  const fallbackExtension = MIME_EXTENSIONS.get(mimeType) ?? '.img'
  const rawName = typeof value === 'string' ? value.trim() : ''
  const leafName = rawName.replace(/\\/g, '/').split('/').pop() ?? ''
  const safeName = leafName.replace(/[^a-zA-Z0-9._-]+/g, '_').replace(/^\.+/, '').slice(0, 120)
  if (safeName === '') {
    return `image${fallbackExtension}`
  }
  const suppliedExtension = extname(safeName).toLowerCase()
  if (suppliedExtension === fallbackExtension ||
    (mimeType === 'image/jpeg' && suppliedExtension === '.jpeg')) {
    return safeName
  }
  const stem = suppliedExtension === '' ? safeName : safeName.slice(0, -suppliedExtension.length)
  return `${stem}${fallbackExtension}`
}

export function isModLensOutput(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return false
  }
  const result = value.result
  if (typeof value.provider !== 'string' || value.provider.trim() === '' ||
    result === null || typeof result !== 'object' || Array.isArray(result)) {
    return false
  }
  return typeof result.summary === 'string' &&
    result.ocr !== null && typeof result.ocr === 'object' &&
    result.layout !== null && typeof result.layout === 'object' &&
    result.semantics !== null && typeof result.semantics === 'object' &&
    result.visual !== null && typeof result.visual === 'object' &&
    Array.isArray(result.uncertainty)
}

export function parseModLensOutput(stdout) {
  const normalized = stdout.trim()
  if (normalized === '') {
    throw new Error('ModLens returned an empty response')
  }
  let parsed
  try {
    parsed = JSON.parse(normalized)
  } catch (_error) {
    throw new Error('ModLens returned invalid JSON')
  }
  if (!isModLensOutput(parsed)) {
    throw new Error('ModLens response does not match the expected vision schema')
  }
  return parsed
}

export function validateAnalyzePayload(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('Request body must be a JSON object')
  }
  const image = value.image
  if (image === null || typeof image !== 'object' || Array.isArray(image) ||
    typeof image.data !== 'string' || image.data.trim() === '') {
    throw new Error('image.data must contain a base64-encoded image')
  }
  const compactData = image.data.replace(/\s/g, '')
  if (!/^[a-zA-Z0-9+/]*={0,2}$/.test(compactData) || compactData.length % 4 !== 0) {
    throw new Error('image.data is not valid base64')
  }
  const imageBuffer = Buffer.from(compactData, 'base64')
  if (imageBuffer.length === 0) {
    throw new Error('The decoded image is empty')
  }
  if (imageBuffer.length > MAX_IMAGE_BYTES) {
    throw new Error(`Image exceeds the ${MAX_IMAGE_BYTES} byte limit`)
  }
  const mimeType = sniffImageMime(imageBuffer)
  if (mimeType === '') {
    throw new Error('Unsupported or invalid image format')
  }
  const prompt = typeof value.prompt === 'string' ? value.prompt.trim() : ''
  if (prompt.length > MAX_PROMPT_CHARACTERS) {
    throw new Error(`prompt exceeds ${MAX_PROMPT_CHARACTERS} characters`)
  }
  return {
    imageBuffer,
    mimeType,
    fileName: sanitizeFileName(image.fileName, mimeType),
    prompt
  }
}

export function isLoopbackHost(host) {
  const normalized = host.trim().toLowerCase().replace(/^\[|\]$/g, '')
  return normalized === '127.0.0.1' || normalized === 'localhost' || normalized === '::1'
}
