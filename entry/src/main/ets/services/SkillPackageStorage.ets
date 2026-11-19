import { fileIo, fileUri } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { checkSkillPath, isSkillPackagingNoise, MAX_SKILL_BYTES, MAX_SKILL_FILES, normalizeSkillBundle,
  SKILL_ENTRY, SkillFile, SkillPackage, unpackSkill } from '../utils/SkillPackage'

export async function readSkillBytes(path: string, limit: number = MAX_SKILL_BYTES + 1024 * 1024): Promise<Uint8Array> {
  const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY)
  try {
    const size = (await fileIo.stat(file.fd)).size
    if (size > limit) throw new Error('Skill exceeds the import size limit')
    const result = new Uint8Array(size)
    let offset = 0
    while (offset < size) {
      const buffer = new ArrayBuffer(Math.min(size - offset, 1024 * 1024))
      const count = await fileIo.read(file.fd, buffer)
      if (count === 0) throw new Error('Incomplete file read')
      result.set(new Uint8Array(buffer, 0, count), offset)
      offset += count
    }
    return result
  } finally {
    await fileIo.close(file)
  }
}

export class SkillPackageStorage {
  private directory: string

  constructor(directory: string) {
    this.directory = directory
  }

  private path(key: string): string {
    if (!/^[0-9a-f-]{36}$/i.test(key)) throw new Error('Invalid skill storage key')
    return this.directory + '/' + key + '.zip'
  }

  async read(key: string): Promise<Uint8Array> {
    return readSkillBytes(this.path(key))
  }

  async write(bytes: Uint8Array): Promise<string> {
    if (!fileIo.accessSync(this.directory)) fileIo.mkdirSync(this.directory, true)
    const key = util.generateRandomUUID()
    const path = this.path(key)
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
    try {
      try {
        let offset = 0
        while (offset < bytes.length) {
          const chunk = bytes.slice(offset, offset + 1024 * 1024)
          const count = await fileIo.write(file.fd, chunk.buffer as ArrayBuffer)
          if (count === 0) throw new Error('Incomplete skill write')
          offset += count
        }
      } finally {
        await fileIo.close(file)
      }
    } catch (error) {
      await this.remove(key)
      throw error as Error
    }
    return key
  }

  async remove(key: string): Promise<void> {
    if (!key) return
    try {
      await fileIo.unlink(this.path(key))
    } catch (error) {
      console.warn('SkillPackageStorage', 'Failed to remove obsolete bundle: ' + JSON.stringify(error))
    }
  }
}

export async function readPickedSkill(uri: string, directory: boolean): Promise<SkillPackage> {
  const selected = new fileUri.FileUri(uri)
  const files: SkillFile[] = []
  let total = 0
  let visited = 0
  const visit = async (parent: string, prefix: string): Promise<void> => {
    const directoryFile = await fileIo.open(parent, fileIo.OpenMode.READ_ONLY)
    let names: string[]
    try {
      names = await fileIo.listFile(directoryFile.path)
    } finally {
      await fileIo.close(directoryFile)
    }
    for (const name of names) {
      if (isSkillPackagingNoise(name)) continue
      const path = checkSkillPath(prefix + name)
      if (++visited > MAX_SKILL_FILES * 2) throw new Error('Too many files in this skill')
      const child = parent.replace(/\/$/, '') + '/' + encodeURIComponent(name)
      const stat = await fileIo.lstat(child)
      if (stat.isSymbolicLink()) continue
      if (stat.isDirectory()) {
        await visit(child, path + '/')
      } else if (stat.isFile()) {
        if (files.length >= MAX_SKILL_FILES) throw new Error('Too many files in this skill')
        const bytes = await readSkillBytes(child, MAX_SKILL_BYTES - total)
        files.push(new SkillFile(path, bytes))
        total += bytes.length
      }
    }
  }
  if (directory) {
    await visit(uri, '')
    const bundle = normalizeSkillBundle(files)
    return new SkillPackage(bundle.name || selected.name, bundle.files)
  }
  const bytes = await readSkillBytes(uri)
  if (/\.(zip|skill)$/i.test(selected.name)) {
    const bundle = unpackSkill(bytes)
    return new SkillPackage(bundle.name || selected.name.replace(/\.[^.]+$/, ''), bundle.files)
  }
  if (!/^skill\.md$/i.test(selected.name)) throw new Error('Select SKILL.md, .skill, or .zip')
  return new SkillPackage(selected.path.split('/').slice(-2, -1).join(''), [new SkillFile(SKILL_ENTRY, bytes)])
}
