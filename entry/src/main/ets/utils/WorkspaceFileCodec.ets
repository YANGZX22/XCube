import { util } from '@kit.ArkTS'
import { PYTHON_MAX_WORKSPACE_FILE_BYTES } from '../services/PythonSandboxRuntimePolicy'

// UTF-8 remains the default for old snapshots. Base64 is only an internal bridge
// representation; files on disk and in Python always contain their original bytes.
export function decodeWorkspaceContent(content: string, encoding: string = 'utf8'): Uint8Array {
  if (encoding === 'utf8') {
    const bytes = new util.TextEncoder().encodeInto(content)
    if (bytes.byteLength > PYTHON_MAX_WORKSPACE_FILE_BYTES) {
      throw new Error('工作区单文件超过大小限制')
    }
    return bytes
  }
  const padding = content.endsWith('==') ? 2 : content.endsWith('=') ? 1 : 0
  const firstPadding = content.indexOf('=')
  if (encoding !== 'base64' || content.length > 4 * Math.ceil(PYTHON_MAX_WORKSPACE_FILE_BYTES / 3) ||
    content.length % 4 !== 0 || /[^A-Za-z0-9+/=]/.test(content) ||
    (firstPadding >= 0 && firstPadding !== content.length - padding)) {
    throw new Error('工作区文件编码无效')
  }
  const bytes = content === '' ? new Uint8Array(0) : new util.Base64Helper().decodeSync(content)
  if (bytes.byteLength > PYTHON_MAX_WORKSPACE_FILE_BYTES) {
    throw new Error('工作区单文件超过大小限制')
  }
  return bytes
}

export function encodeWorkspaceBytes(bytes: Uint8Array): string {
  return bytes.byteLength === 0 ? '' : new util.Base64Helper().encodeToStringSync(bytes)
}

export function getWorkspaceMimeType(path: string): string {
  const extension = path.substring(path.lastIndexOf('.') + 1).toLowerCase()
  const types: Record<string, string> = {
    'pdf': 'application/pdf', 'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
    'webp': 'image/webp', 'gif': 'image/gif', 'bmp': 'image/bmp', 'heic': 'image/heic', 'heif': 'image/heif',
    'svg': 'image/svg+xml', 'txt': 'text/plain', 'md': 'text/markdown', 'py': 'text/x-python',
    'csv': 'text/csv', 'json': 'application/json', 'html': 'text/html', 'xml': 'application/xml',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'zip': 'application/zip'
  }
  return types[extension] ?? 'application/octet-stream'
}

// Shared by the workspace reader and the chat-attachment readers: the same MIME set
// decides whether the current model can take the raw file instead of extracted text.
export function canUseNativeFileInput(mime: string, supportsVision: boolean,
  supportsDocuments: boolean): boolean {
  if (mime.startsWith('image/')) {
    return supportsVision && mime !== 'image/svg+xml'
  }
  return supportsDocuments && (mime === 'application/pdf' || mime.startsWith('application/vnd.openxmlformats-'))
}

export function decodeWorkspaceText(bytes: Uint8Array, path: string): string | undefined {
  const mime = getWorkspaceMimeType(path)
  if (mime === 'application/pdf' || mime === 'application/zip' ||
    mime.startsWith('application/vnd.') || (mime.startsWith('image/') && mime !== 'image/svg+xml')) {
    return undefined
  }
  // A replacement character can be legitimate text. Check a lossless round trip
  // instead of rejecting every U+FFFD (and never decode binary into editable text).
  try {
    const text = util.TextDecoder.create('utf-8').decodeToString(bytes, { stream: false })
    if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(text)) {
      return undefined
    }
    const encoded = new util.TextEncoder().encodeInto(text)
    const bomOffset = bytes.length >= 3 && bytes[0] === 239 && bytes[1] === 187 && bytes[2] === 191 &&
      encoded.length === bytes.length - 3 ? 3 : 0
    if (encoded.length + bomOffset !== bytes.length) {
      return undefined
    }
    for (let i = 0; i < encoded.length; i++) {
      if (encoded[i] !== bytes[i + bomOffset]) {
        return undefined
      }
    }
    return bomOffset === 3 ? '\uFEFF' + text : text
  } catch (_error) {
    return undefined
  }
}
