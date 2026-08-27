export const PYTHON_SANDBOX_FILE_URL_PREFIX: string = 'xcube-file://'
export const PYTHON_SANDBOX_FILE_ATTACHMENT_PREFIX: string = 'python_file_'
export const PYTHON_SANDBOX_IMAGE_URL_PREFIX: string = 'xcube-image://'
export const PYTHON_SANDBOX_IMAGE_ATTACHMENT_PREFIX: string = 'python_img_'

const PYTHON_SANDBOX_ATTACHMENT_ID_PATTERN: RegExp = /^[A-Za-z0-9_-]{1,128}$/

export function isPythonSandboxFileAttachmentId(attachmentId: string): boolean {
  const normalized = attachmentId.trim()
  return normalized.startsWith(PYTHON_SANDBOX_FILE_ATTACHMENT_PREFIX) &&
    PYTHON_SANDBOX_ATTACHMENT_ID_PATTERN.test(normalized)
}

export function isPythonSandboxImageAttachmentId(attachmentId: string): boolean {
  const normalized = attachmentId.trim()
  return normalized.startsWith(PYTHON_SANDBOX_IMAGE_ATTACHMENT_PREFIX) &&
    PYTHON_SANDBOX_ATTACHMENT_ID_PATTERN.test(normalized)
}

export function buildPythonSandboxFileUrl(attachmentId: string): string {
  const normalized = attachmentId.trim()
  if (!isPythonSandboxFileAttachmentId(normalized)) {
    return ''
  }
  return `${PYTHON_SANDBOX_FILE_URL_PREFIX}${normalized}`
}

export function parsePythonSandboxFileUrl(url: string): string {
  const normalized = url.trim()
  if (!normalized.startsWith(PYTHON_SANDBOX_FILE_URL_PREFIX)) {
    return ''
  }
  const attachmentId = normalized.substring(PYTHON_SANDBOX_FILE_URL_PREFIX.length)
  return isPythonSandboxFileAttachmentId(attachmentId) ? attachmentId : ''
}

export function buildPythonSandboxImageUrl(attachmentId: string): string {
  const normalized = attachmentId.trim()
  if (!isPythonSandboxImageAttachmentId(normalized)) {
    return ''
  }
  return `${PYTHON_SANDBOX_IMAGE_URL_PREFIX}${normalized}`
}

export function parsePythonSandboxImageUrl(url: string): string {
  const normalized = url.trim()
  if (!normalized.startsWith(PYTHON_SANDBOX_IMAGE_URL_PREFIX)) {
    return ''
  }
  const attachmentId = normalized.substring(PYTHON_SANDBOX_IMAGE_URL_PREFIX.length)
  return isPythonSandboxImageAttachmentId(attachmentId) ? attachmentId : ''
}

export function escapePythonSandboxMarkdownLabel(label: string): string {
  return label.replace(/\\/g, '\\\\').replace(/\[/g, '\\[').replace(/\]/g, '\\]')
}

export function buildPythonSandboxFileMarkdown(name: string, attachmentId: string): string {
  const url = buildPythonSandboxFileUrl(attachmentId)
  if (url === '') {
    return ''
  }
  return `[${escapePythonSandboxMarkdownLabel(name)}](${url})`
}

export function buildPythonSandboxImageMarkdown(name: string, attachmentId: string): string {
  const url = buildPythonSandboxImageUrl(attachmentId)
  if (url === '') {
    return ''
  }
  return `![${escapePythonSandboxMarkdownLabel(name)}](${url})`
}
