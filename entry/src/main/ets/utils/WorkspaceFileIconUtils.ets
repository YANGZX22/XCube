/**
 * 工作区文件图标映射。
 *
 * 目标是 VSCode 文件图标主题那种"扫一眼就知道是什么文件"的效果：按类别给不同字形，
 * 而不是所有文件共用一个 doc_text 只换颜色——只靠颜色区分，在小字号和深色模式下
 * 几乎读不出差别。
 *
 * 所有 sys.symbol 名称都对照过 SDK 的 id_defined.json；凭印象写名字会直接 BUILD FAILED。
 * docx/xlsx 没有合适的系统字形，沿用知识库与工具卡片已经在用的位图资源。
 */

import { getWorkspaceFileExtension, getWorkspaceFileName } from './WorkspaceExplorerTree'

// 文件类别。图标与配色按类别分配，新扩展名只需要归类，不必再加一套图标。
export const WORKSPACE_FILE_KIND_PYTHON: string = 'python'
export const WORKSPACE_FILE_KIND_NOTEBOOK: string = 'notebook'
export const WORKSPACE_FILE_KIND_CODE: string = 'code'
export const WORKSPACE_FILE_KIND_MARKUP: string = 'markup'
export const WORKSPACE_FILE_KIND_STYLE: string = 'style'
export const WORKSPACE_FILE_KIND_DATA: string = 'data'
export const WORKSPACE_FILE_KIND_CONFIG: string = 'config'
export const WORKSPACE_FILE_KIND_MARKDOWN: string = 'markdown'
export const WORKSPACE_FILE_KIND_TEXT: string = 'text'
export const WORKSPACE_FILE_KIND_TABLE: string = 'table'
export const WORKSPACE_FILE_KIND_SHEET: string = 'sheet'
export const WORKSPACE_FILE_KIND_WORD: string = 'word'
export const WORKSPACE_FILE_KIND_PDF: string = 'pdf'
export const WORKSPACE_FILE_KIND_IMAGE: string = 'image'
export const WORKSPACE_FILE_KIND_AUDIO: string = 'audio'
export const WORKSPACE_FILE_KIND_VIDEO: string = 'video'
export const WORKSPACE_FILE_KIND_ARCHIVE: string = 'archive'
export const WORKSPACE_FILE_KIND_BINARY: string = 'binary'
export const WORKSPACE_FILE_KIND_UNKNOWN: string = 'unknown'

const PYTHON_EXTENSIONS: string[] = ['py', 'pyw', 'pyi', 'pyx', 'pyd']
const NOTEBOOK_EXTENSIONS: string[] = ['ipynb']
const CODE_EXTENSIONS: string[] = [
  'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'ets', 'java', 'kt', 'kts', 'c', 'h', 'cpp', 'cc', 'cxx',
  'hpp', 'cs', 'go', 'rs', 'rb', 'php', 'swift', 'm', 'mm', 'scala', 'dart', 'lua', 'pl', 'r',
  'sql', 'sh', 'bash', 'zsh', 'fish', 'ps1', 'bat', 'cmd', 'vb', 'asm', 'hs', 'ex', 'exs'
]
const MARKUP_EXTENSIONS: string[] = ['html', 'htm', 'xhtml', 'xml', 'svg', 'vue', 'jsp', 'plist']
const STYLE_EXTENSIONS: string[] = ['css', 'scss', 'sass', 'less', 'styl']
const DATA_EXTENSIONS: string[] = ['json', 'jsonl', 'json5', 'yaml', 'yml', 'toml', 'proto', 'graphql']
const CONFIG_EXTENSIONS: string[] = [
  'ini', 'cfg', 'conf', 'config', 'env', 'properties', 'editorconfig', 'gitignore',
  'gitattributes', 'dockerignore', 'lock'
]
const MARKDOWN_EXTENSIONS: string[] = ['md', 'markdown', 'mdx', 'rst', 'adoc']
const TEXT_EXTENSIONS: string[] = ['txt', 'text', 'log', 'out', 'err', 'diff', 'patch']
const TABLE_EXTENSIONS: string[] = ['csv', 'tsv', 'parquet']
const SHEET_EXTENSIONS: string[] = ['xlsx', 'xls', 'xlsm', 'ods']
const WORD_EXTENSIONS: string[] = ['docx', 'doc', 'rtf', 'odt']
const PDF_EXTENSIONS: string[] = ['pdf']
const IMAGE_EXTENSIONS: string[] = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'heic', 'heif', 'tiff', 'tif', 'avif']
const AUDIO_EXTENSIONS: string[] = ['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'opus', 'wma', 'aiff']
const VIDEO_EXTENSIONS: string[] = ['mp4', 'mov', 'avi', 'mkv', 'webm', 'flv', 'wmv', 'm4v', 'mpeg', 'mpg']
const ARCHIVE_EXTENSIONS: string[] = ['zip', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'rar', '7z', 'whl', 'jar', 'hap', 'har']
const BINARY_EXTENSIONS: string[] = ['db', 'sqlite', 'sqlite3', 'pkl', 'pickle', 'npy', 'npz', 'bin', 'dat', 'so', 'dylib', 'dll', 'pt', 'pth', 'onnx', 'safetensors']

function includesExtension(list: string[], extension: string): boolean {
  return list.indexOf(extension) >= 0
}

// 无扩展名或扩展名不足以说明用途的文件（Dockerfile、Makefile、README…）按文件名归类，
// 与 VSCode 图标主题的做法一致。
function classifyByFileName(path: string): string {
  const name = getWorkspaceFileName(path).toLowerCase()
  if (name === 'dockerfile' || name.startsWith('dockerfile.') || name === 'makefile' ||
    name === 'cmakelists.txt' || name === '.gitignore' || name === '.gitattributes' ||
    name === '.editorconfig' || name === '.env' || name.startsWith('.env.')) {
    return WORKSPACE_FILE_KIND_CONFIG
  }
  if (name === 'requirements.txt' || name === 'pipfile' || name === 'pyproject.toml' ||
    name === 'package.json' || name === 'oh-package.json5') {
    return WORKSPACE_FILE_KIND_DATA
  }
  if (name === 'license' || name === 'licence' || name === 'notice' || name === 'authors') {
    return WORKSPACE_FILE_KIND_TEXT
  }
  if (name.startsWith('readme')) {
    return WORKSPACE_FILE_KIND_MARKDOWN
  }
  return WORKSPACE_FILE_KIND_UNKNOWN
}

export function classifyWorkspaceFile(path: string): string {
  const byName = classifyByFileName(path)
  if (byName !== WORKSPACE_FILE_KIND_UNKNOWN) {
    return byName
  }
  const extension = getWorkspaceFileExtension(path)
  if (extension === '') {
    return WORKSPACE_FILE_KIND_UNKNOWN
  }
  if (includesExtension(PYTHON_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_PYTHON
  }
  if (includesExtension(NOTEBOOK_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_NOTEBOOK
  }
  if (includesExtension(MARKUP_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_MARKUP
  }
  if (includesExtension(STYLE_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_STYLE
  }
  if (includesExtension(CODE_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_CODE
  }
  if (includesExtension(DATA_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_DATA
  }
  if (includesExtension(CONFIG_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_CONFIG
  }
  if (includesExtension(MARKDOWN_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_MARKDOWN
  }
  if (includesExtension(TEXT_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_TEXT
  }
  if (includesExtension(TABLE_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_TABLE
  }
  if (includesExtension(SHEET_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_SHEET
  }
  if (includesExtension(WORD_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_WORD
  }
  if (includesExtension(PDF_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_PDF
  }
  if (includesExtension(IMAGE_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_IMAGE
  }
  if (includesExtension(AUDIO_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_AUDIO
  }
  if (includesExtension(VIDEO_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_VIDEO
  }
  if (includesExtension(ARCHIVE_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_ARCHIVE
  }
  if (includesExtension(BINARY_EXTENSIONS, extension)) {
    return WORKSPACE_FILE_KIND_BINARY
  }
  return WORKSPACE_FILE_KIND_UNKNOWN
}

// docx/xlsx 沿用位图资源（系统字形里没有对应图案）。与 ToolCallCard 一样由调用方
// 按 kind 分支，$r() 写在渲染处，避免返回可空 Resource。
export function hasWorkspaceFileImageIcon(path: string): boolean {
  const kind = classifyWorkspaceFile(path)
  return kind === WORKSPACE_FILE_KIND_WORD || kind === WORKSPACE_FILE_KIND_SHEET
}

export function resolveWorkspaceFileSymbol(path: string): Resource {
  switch (classifyWorkspaceFile(path)) {
    case WORKSPACE_FILE_KIND_PYTHON:
      return $r('sys.symbol.code')
    case WORKSPACE_FILE_KIND_NOTEBOOK:
      return $r('sys.symbol.book_pages')
    case WORKSPACE_FILE_KIND_CODE:
      return $r('sys.symbol.code_square')
    case WORKSPACE_FILE_KIND_MARKUP:
      return $r('sys.symbol.code_slash')
    case WORKSPACE_FILE_KIND_STYLE:
      return $r('sys.symbol.paintbrush')
    case WORKSPACE_FILE_KIND_DATA:
      return $r('sys.symbol.list_bullet_square')
    case WORKSPACE_FILE_KIND_CONFIG:
      return $r('sys.symbol.gearshape')
    case WORKSPACE_FILE_KIND_MARKDOWN:
      return $r('sys.symbol.doc_plaintext')
    case WORKSPACE_FILE_KIND_TEXT:
      return $r('sys.symbol.doc_text')
    case WORKSPACE_FILE_KIND_TABLE:
      return $r('sys.symbol.grid')
    case WORKSPACE_FILE_KIND_SHEET:
      return $r('sys.symbol.grid')
    case WORKSPACE_FILE_KIND_WORD:
      return $r('sys.symbol.doc_text')
    case WORKSPACE_FILE_KIND_PDF:
      return $r('sys.symbol.pdf_doc')
    case WORKSPACE_FILE_KIND_IMAGE:
      return $r('sys.symbol.picture')
    case WORKSPACE_FILE_KIND_AUDIO:
      return $r('sys.symbol.music')
    case WORKSPACE_FILE_KIND_VIDEO:
      return $r('sys.symbol.movie')
    case WORKSPACE_FILE_KIND_ARCHIVE:
      return $r('sys.symbol.doc_zipper')
    case WORKSPACE_FILE_KIND_BINARY:
      return $r('sys.symbol.archivebox')
    default:
      return $r('sys.symbol.doc')
  }
}

// 深色模式单独给一档更亮的颜色：品牌原色（Python 蓝、Word 蓝）在深色底上会糊成一团。
// fallbackColor 用于未识别的类型，由调用方传入主题色，保持与页面其余部分一致。
export function resolveWorkspaceFileIconColor(path: string, isDarkMode: boolean, fallbackColor: string): string {
  switch (classifyWorkspaceFile(path)) {
    case WORKSPACE_FILE_KIND_PYTHON:
      return isDarkMode ? '#5A9FD4' : '#3776AB'
    case WORKSPACE_FILE_KIND_NOTEBOOK:
      return isDarkMode ? '#F0A95C' : '#D9822B'
    case WORKSPACE_FILE_KIND_CODE:
      return isDarkMode ? '#E0925F' : '#C2683A'
    case WORKSPACE_FILE_KIND_MARKUP:
      return isDarkMode ? '#F08060' : '#D9543A'
    case WORKSPACE_FILE_KIND_STYLE:
      return isDarkMode ? '#5FA8E8' : '#2C7FD4'
    case WORKSPACE_FILE_KIND_DATA:
      return isDarkMode ? '#DCA84C' : '#C07A20'
    case WORKSPACE_FILE_KIND_CONFIG:
      return isDarkMode ? '#9BA3B0' : '#6E7785'
    case WORKSPACE_FILE_KIND_MARKDOWN:
      return isDarkMode ? '#A07FE0' : '#8057C8'
    case WORKSPACE_FILE_KIND_TEXT:
      return isDarkMode ? '#9AA0AC' : '#6E7480'
    case WORKSPACE_FILE_KIND_TABLE:
      return isDarkMode ? '#4FB37C' : '#2E8B57'
    case WORKSPACE_FILE_KIND_SHEET:
      return isDarkMode ? '#45A06A' : '#1D6F42'
    case WORKSPACE_FILE_KIND_WORD:
      return isDarkMode ? '#5B8FD6' : '#2B579A'
    case WORKSPACE_FILE_KIND_PDF:
      return isDarkMode ? '#E86A62' : '#D5433B'
    case WORKSPACE_FILE_KIND_IMAGE:
      return isDarkMode ? '#D97BAA' : '#C2578F'
    case WORKSPACE_FILE_KIND_AUDIO:
      return isDarkMode ? '#E0915C' : '#C9743B'
    case WORKSPACE_FILE_KIND_VIDEO:
      return isDarkMode ? '#9B80E8' : '#7A5BD0'
    case WORKSPACE_FILE_KIND_ARCHIVE:
      return isDarkMode ? '#CCA155' : '#B0873A'
    case WORKSPACE_FILE_KIND_BINARY:
      return isDarkMode ? '#8C96A4' : '#5F6975'
    default:
      return fallbackColor
  }
}
