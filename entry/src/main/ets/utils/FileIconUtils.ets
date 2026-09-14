import {
  MATERIAL_FILE_EXTENSIONS,
  MATERIAL_FILE_NAMES,
  MATERIAL_FILE_NAME_MAX_DEPTH,
  MATERIAL_LIGHT_ICONS
} from '../config/MaterialFileIcons'

const MIME_ICONS: Map<string, string> = new Map<string, string>([
  ['application/pdf', 'pdf'],
  ['application/msword', 'word'],
  ['application/rtf', 'word'],
  ['application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'word'],
  ['application/vnd.oasis.opendocument.text', 'word'],
  ['application/vnd.ms-excel', 'table'],
  ['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'table'],
  ['application/vnd.oasis.opendocument.spreadsheet', 'table'],
  ['text/csv', 'table'],
  ['text/tab-separated-values', 'table'],
  ['application/vnd.ms-powerpoint', 'powerpoint'],
  ['application/vnd.openxmlformats-officedocument.presentationml.presentation', 'powerpoint'],
  ['application/vnd.oasis.opendocument.presentation', 'powerpoint'],
  ['application/json', 'json'],
  ['application/ld+json', 'json'],
  ['application/xml', 'xml'],
  ['text/xml', 'xml'],
  ['text/markdown', 'markdown'],
  ['application/zip', 'zip'],
  ['application/gzip', 'zip'],
  ['application/x-tar', 'zip'],
  ['application/x-7z-compressed', 'zip'],
  ['application/vnd.rar', 'zip'],
  ['application/x-rar-compressed', 'zip']
])

function normalizeFileIconPath(path: string): string {
  let normalized = path.trim().replace(/\\/g, '/')
  // 本地文件名可以包含 # 或 ?，仅 URI 去除查询串并解码。
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(normalized)) {
    normalized = normalized.split(/[?#]/)[0]
    try {
      normalized = decodeURIComponent(normalized)
    } catch (_error) {
      // 畸形转义仍可按原始文件名后缀匹配。
    }
  }
  return normalized.replace(/\/+$/, '').toLowerCase()
}

export function resolveFileIconName(path: string, mimeType: string = ''): string {
  const normalized = normalizeFileIconPath(path)
  const parts = normalized.split('/')
  const name = parts[parts.length - 1]
  // 上游包含 .config/xxx 等带父目录的特例，最长路径优先。
  for (let i = Math.max(0, parts.length - MATERIAL_FILE_NAME_MAX_DEPTH); i < parts.length; i++) {
    const icon = MATERIAL_FILE_NAMES.get(parts.slice(i).join('/'))
    if (icon !== undefined) {
      return icon
    }
  }
  if (name === '.env' || name.startsWith('.env.')) {
    return 'tune'
  }
  if (name.startsWith('dockerfile.')) {
    return 'docker'
  }
  if (/^readme[._-][a-z]{2}(?:[-_][a-z]{2})?\.(?:md|markdown|txt|rst)$/.test(name)) {
    return 'readme'
  }
  // 从第一个点开始尝试：d.ts、test.ts、schema.json 等比最终扩展名更具体。
  let dot = name.indexOf('.')
  while (dot >= 0) {
    const icon = MATERIAL_FILE_EXTENSIONS.get(name.substring(dot + 1))
    if (icon !== undefined) {
      return icon
    }
    dot = name.indexOf('.', dot + 1)
  }
  const mime = mimeType.split(';')[0].trim().toLowerCase()
  const mimeIcon = MIME_ICONS.get(mime)
  if (mimeIcon !== undefined) {
    return mimeIcon
  }
  if (mime.startsWith('image/')) {
    return 'image'
  }
  if (mime.startsWith('audio/')) {
    return 'audio'
  }
  if (mime.startsWith('video/')) {
    return 'video'
  }
  if (mime.startsWith('font/')) {
    return 'font'
  }
  return mime.startsWith('text/') ? 'document' : 'file'
}

export function resolveFileIconResourcePath(path: string, mimeType: string = '', isDarkMode: boolean = false): string {
  const icon = resolveFileIconName(path, mimeType)
  const themedIcon = isDarkMode ? icon : (MATERIAL_LIGHT_ICONS.get(icon) ?? icon)
  return `file-icons/material/${themedIcon}.svg`
}
