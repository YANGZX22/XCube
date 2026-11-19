// The archive stays in memory. Imported paths are virtual and never used as device paths.
import { unzipSync, zipSync, strToU8, strFromU8 } from 'fflate'
import { parseDocument, isMap } from 'yaml'

export const SKILL_ENTRY = 'SKILL.md'
export const MAX_SKILL_BYTES = 30 * 1024 * 1024
export const MAX_SKILL_FILES = 4096

export class SkillFile {
  constructor(public path: string, public bytes: Uint8Array) {}
}

export class SkillPackage {
  constructor(public name: string, public files: SkillFile[]) {}
}

export class SkillMetadata {
  constructor(public name: string, public description: string, public body: string, public header: string,
    public manualOnly: boolean) {}
}

export function isSkillMarkdown(path: string): boolean {
  return /\.(md|markdown)$/i.test(path)
}

export function skillTextFile(path: string, text: string): SkillFile {
  return new SkillFile(path, strToU8(text))
}

export function skillFileText(file: SkillFile): string {
  const text = strFromU8(file.bytes)
  // Reject invalid UTF-8 instead of silently rewriting binary or damaged documents on save.
  const encoded = strToU8(text)
  const bom = file.bytes[0] === 0xef && file.bytes[1] === 0xbb && file.bytes[2] === 0xbf
  const offset = bom && encoded.length + 3 === file.bytes.length ? 3 : 0
  if (encoded.length + offset !== file.bytes.length ||
      encoded.some((byte, i) => byte !== file.bytes[i + offset])) {
    throw new Error('Invalid UTF-8: ' + file.path)
  }
  return offset === 3 ? '\uFEFF' + text : text
}

export function checkSkillPath(path: string): string {
  if (!path || path.startsWith('/') || /[\\:\x00-\x1f\x7f]/.test(path) ||
      path.split('/').some(part => !part || part === '.' || part === '..' || part === '__proto__')) {
    throw new Error('Invalid file path: ' + path)
  }
  return path
}

export function skillLinkTarget(from: string, url: string): string {
  try {
    const target = decodeURIComponent(url.split(/[?#]/)[0])
    if (!target || target.startsWith('/') || /[\\:]/.test(target)) return ''
    const parts = from.split('/').slice(0, -1)
    for (const part of target.split('/')) {
      if (part === '..') {
        if (parts.pop() === undefined) return ''
      } else if (part !== '.' && part !== '') {
        parts.push(part)
      }
    }
    return checkSkillPath(parts.join('/'))
  } catch {
    return ''
  }
}

export function readSkillMetadata(raw: string, fallbackName: string, fallbackDescription: string = ''): SkillMetadata {
  const source = raw.replace(/^\uFEFF/, '')
  const match = /^---[ \t]*\r?\n([\s\S]*?)^(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/m.exec(source)
  let name = fallbackName
  let description = fallbackDescription
  let body = source
  let header = ''
  let manualOnly = false
  if (match && match.index === 0) {
    const doc = parseDocument(match[1], { schema: 'core' })
    if (doc.errors.length) throw new Error('Invalid SKILL.md YAML: ' + doc.errors[0].message)
    if (!isMap(doc.contents) && doc.contents !== null) {
      return new SkillMetadata(name, description, source, '', false)
    }
    const fields = doc.toJS({ maxAliasCount: 64 }) || {}
    manualOnly = fields['disable-model-invocation'] === true
    for (const key of ['name', 'description']) {
      const value = fields[key]
      if (value === undefined || value === null) continue
      if (typeof value !== 'string') throw new Error('Invalid SKILL.md field: ' + key)
      if (key === 'name') name = value.trim() || name
      else description = value.trim() || description
    }
    header = match[0]
    body = source.slice(header.length)
  }
  if (!description) description = (body.trim().split(/\r?\n/)[0] || '').replace(/^#+\s*/, '').slice(0, 1024)
  return new SkillMetadata(name, description, body, header, manualOnly)
}

// Older XCube skills allowed arbitrary Markdown, including text between horizontal rules.
export function readStoredSkillMetadata(raw: string, name: string, description: string): SkillMetadata {
  try {
    return readSkillMetadata(raw, name, description)
  } catch {
    return new SkillMetadata(name, description, raw, '', false)
  }
}

// Keep comments and additional Claude fields intact when editing an imported skill.
export function editSkillEntry(original: string, name: string, description: string, body: string,
  originalName: string = name, originalDescription: string = description): string {
  const previous = readStoredSkillMetadata(original, originalName, originalDescription)
  if (previous.name === name && previous.description === description && previous.body === body) return original
  if (!previous.header) return body
  if (previous.name === name && previous.description === description) return previous.header + body
  const yaml = previous.header.replace(/^---[^\n]*\n/, '').replace(/^(?:---|\.\.\.)[ \t]*\r?\n?$/m, '')
  const doc = parseDocument(yaml)
  doc.set('name', name)
  doc.set('description', description)
  return '---\n' + doc.toString() + '---\n' + body
}

export function isSkillPackagingNoise(path: string): boolean {
  return path.split('/').some(part => part === '__MACOSX' || part === '.DS_Store' || part.startsWith('._') || part === '.git')
}

export function normalizeSkillBundle(files: SkillFile[]): SkillPackage {
  const paths = new Set<string>()
  let total = 0
  for (const file of files) {
    checkSkillPath(file.path)
    if (paths.has(file.path)) throw new Error('Duplicate file: ' + file.path)
    paths.add(file.path)
    total += file.bytes.length
  }
  if (files.length > MAX_SKILL_FILES || total > MAX_SKILL_BYTES) throw new Error('Skill exceeds 30 MiB or 4096 files')
  const entries = files.filter(file => file.path.split('/').pop() === SKILL_ENTRY)
  const root = entries.find(entry => {
    const prefix = entry.path.slice(0, -SKILL_ENTRY.length)
    return files.every(file => file.path.startsWith(prefix))
  })
  if (!root) throw new Error('Select one skill containing a top-level SKILL.md')
  const prefix = root.path.slice(0, -SKILL_ENTRY.length)
  const sorted = files.map(file => new SkillFile(file.path.slice(prefix.length), file.bytes))
    .sort((a, b) => a.path === b.path ? 0 : a.path === SKILL_ENTRY ? -1 : b.path === SKILL_ENTRY ? 1 : a.path.localeCompare(b.path))
  return new SkillPackage(prefix.split('/').slice(-2, -1).join(''), sorted)
}

export function unpackSkill(bytes: Uint8Array): SkillPackage {
  if (bytes.length > MAX_SKILL_BYTES + 1024 * 1024) throw new Error('Skill archive exceeds 31 MiB')
  let count = 0
  let total = 0
  const names = new Set<string>()
  const entries = unzipSync(bytes, { filter: e => {
    if (++count > MAX_SKILL_FILES * 2) throw new Error('Too many archive entries')
    const name = e.name.replace(/^(?:\.\/)+/, '')
    if (!name && e.name.endsWith('/')) return false
    const directory = name.endsWith('/')
    const path = checkSkillPath(directory ? name.slice(0, -1) : name)
    if (directory || isSkillPackagingNoise(path)) return false
    if (names.has(path)) throw new Error('Duplicate file: ' + path)
    names.add(path)
    total += e.originalSize
    if (names.size > MAX_SKILL_FILES || total > MAX_SKILL_BYTES) throw new Error('Skill exceeds 30 MiB or 4096 files')
    return true
  } })
  return normalizeSkillBundle(Object.keys(entries).map(path => new SkillFile(path.replace(/^(?:\.\/)+/, ''), entries[path])))
}

export function packSkill(files: SkillFile[]): Uint8Array {
  const entries: Record<string, Uint8Array> = Object.create(null)
  for (const file of normalizeSkillBundle(files).files) entries[file.path] = file.bytes
  const archive = zipSync(entries, { level: 0 })
  if (archive.length > MAX_SKILL_BYTES + 1024 * 1024) throw new Error('Skill archive exceeds 31 MiB')
  return archive
}

// Stored archives were validated at import/save. Inflate just the requested document.
export function readPackedSkillFile(bytes: Uint8Array, path: string): SkillFile {
  checkSkillPath(path)
  const entry = unzipSync(bytes, { filter: e => e.name === path })[path]
  if (!entry) throw new Error('File not found: ' + path)
  return new SkillFile(path, entry)
}
