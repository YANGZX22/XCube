import { Context } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { getAppUiState, setAppUiStateValue } from '../state/AppUiState'
import {
  PYTHON_MAX_WORKSPACE_FILES,
  PYTHON_MAX_WORKSPACE_FILE_BYTES,
  PYTHON_MAX_WORKSPACE_TOTAL_BYTES
} from './PythonSandboxRuntimePolicy'

const PYTHON_WORKSPACES_DIRECTORY: string = 'python_workspaces'
const PYTHON_WORKSPACE_DIRECTORY_PREFIX: string = 'session_'
export const PYTHON_WORKSPACE_MAX_FILES: number = PYTHON_MAX_WORKSPACE_FILES
export const PYTHON_WORKSPACE_MAX_FILE_BYTES: number = PYTHON_MAX_WORKSPACE_FILE_BYTES
export const PYTHON_WORKSPACE_MAX_TOTAL_BYTES: number = PYTHON_MAX_WORKSPACE_TOTAL_BYTES
export const PYTHON_WORKSPACE_MAX_READ_LINES: number = 400
export const PYTHON_WORKSPACE_MAX_READ_CHARACTERS: number = 64 * 1024
export const PYTHON_WORKSPACE_CACHE_GRACE_PERIOD_MS: number = 5 * 60 * 1000

export class PythonWorkspaceFileData {
  path: string = ''
  content: string = ''
  size: number = 0

  constructor(path: string = '', content: string = '', size: number = 0) {
    this.path = path
    this.content = content
    this.size = size
  }
}

export class PythonWorkspaceFileInfo {
  path: string = ''
  size: number = 0
  modifiedAt: number = 0

  constructor(path: string, size: number, modifiedAt: number) {
    this.path = path
    this.size = size
    this.modifiedAt = modifiedAt
  }
}

export class PythonWorkspaceReadResult {
  path: string = ''
  content: string = ''
  startLine: number = 1
  endLine: number = 0
  totalLines: number = 0
  truncated: boolean = false
}

export class PythonWorkspaceCleanupResult {
  scannedFiles: number = 0
  deletedFiles: number = 0
  failedFiles: number = 0
}

export function normalizePythonWorkspacePath(rawPath: string): string {
  let normalized = rawPath.trim().replace(/\\/g, '/')
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2)
  }
  if (normalized === '' || normalized.length > 240 || normalized.startsWith('/')) {
    throw new Error('工作区文件路径必须是长度不超过 240 的相对路径')
  }
  const segments = normalized.split('/')
  if (segments.length > 8) {
    throw new Error('工作区文件路径最多允许 8 层目录')
  }
  for (let i = 0; i < segments.length; i++) {
    const segment = segments[i]
    if (segment === '' || segment === '.' || segment === '..' ||
      !/^[A-Za-z0-9._-]+$/.test(segment)) {
      throw new Error('工作区文件路径仅支持字母、数字、点、下划线、短横线和安全的相对目录')
    }
  }
  return segments.join('/')
}

export function encodePythonWorkspaceSessionDirectory(sessionId: string): string {
  const normalized = sessionId.trim()
  if (normalized === '') {
    throw new Error('当前没有活动会话，无法使用 Python 工作区')
  }
  const bytes = new util.TextEncoder().encodeInto(normalized)
  if (bytes.byteLength > 128) {
    throw new Error('会话标识过长，无法创建 Python 工作区')
  }
  let encoded = ''
  for (let i = 0; i < bytes.length; i++) {
    encoded += bytes[i].toString(16).padStart(2, '0')
  }
  return `${PYTHON_WORKSPACE_DIRECTORY_PREFIX}${encoded}`
}

export function validatePythonWorkspaceReplacement(oldText: string, newText: string): void {
  if (oldText === '') {
    throw new Error('old_text 不能为空')
  }
  if (oldText === newText) {
    throw new Error('new_text 与 old_text 相同，未执行任何修改')
  }
}

export class PythonWorkspaceService {
  private static instance: PythonWorkspaceService | null = null
  private rootDirectory: string = ''
  private initialized: boolean = false
  private mutationBatchDepth: number = 0
  private mutationNotificationPending: boolean = false

  private constructor() {}

  static getInstance(): PythonWorkspaceService {
    if (PythonWorkspaceService.instance === null) {
      PythonWorkspaceService.instance = new PythonWorkspaceService()
    }
    return PythonWorkspaceService.instance
  }

  initialize(context: Context): void {
    if (this.initialized) {
      return
    }
    this.rootDirectory = `${context.filesDir}/${PYTHON_WORKSPACES_DIRECTORY}`
    if (!this.pathExists(this.rootDirectory)) {
      fileIo.mkdirSync(this.rootDirectory, true)
    }
    this.initialized = true
  }

  isReady(): boolean {
    return this.initialized && this.rootDirectory !== ''
  }

  writeFile(sessionId: string, rawPath: string, content: string): PythonWorkspaceFileInfo {
    this.ensureReady()
    const path = normalizePythonWorkspacePath(rawPath)
    const contentBytes = this.encodeContent(content)
    this.validateFileSize(contentBytes.byteLength)
    const existing = this.listFiles(sessionId)
    let existingSize = 0
    for (let i = 0; i < existing.length; i++) {
      if (existing[i].path === path) {
        existingSize = existing[i].size
        break
      }
    }
    if (existing.length >= PYTHON_WORKSPACE_MAX_FILES && existingSize === 0) {
      throw new Error(`Python 工作区最多允许 ${PYTHON_WORKSPACE_MAX_FILES} 个文件`)
    }
    let currentTotal = 0
    for (let i = 0; i < existing.length; i++) {
      currentTotal += existing[i].size
    }
    if (currentTotal - existingSize + contentBytes.byteLength > PYTHON_WORKSPACE_MAX_TOTAL_BYTES) {
      throw new Error(`Python 工作区总大小不能超过 ${PYTHON_WORKSPACE_MAX_TOTAL_BYTES} 字节`)
    }

    const sessionDirectory = this.ensureSessionDirectory(sessionId)
    const filePath = `${sessionDirectory}/${path}`
    const slashIndex = filePath.lastIndexOf('/')
    const parentDirectory = slashIndex > 0 ? filePath.substring(0, slashIndex) : ''
    if (parentDirectory !== '' && !this.pathExists(parentDirectory)) {
      fileIo.mkdirSync(parentDirectory, true)
    }
    const file = fileIo.openSync(
      filePath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
    )
    try {
      fileIo.writeSync(file.fd, contentBytes.buffer)
    } finally {
      fileIo.closeSync(file)
    }
    const stat = fileIo.statSync(filePath)
    this.notifyWorkspaceChanged()
    return new PythonWorkspaceFileInfo(path, stat.size, stat.mtime)
  }

  appendFile(sessionId: string, rawPath: string, content: string): PythonWorkspaceFileInfo {
    const path = normalizePythonWorkspacePath(rawPath)
    const existing = this.fileExists(sessionId, path) ? this.readWholeFile(sessionId, path) : ''
    return this.writeFile(sessionId, path, existing + content)
  }

  replaceInFile(sessionId: string, rawPath: string, oldText: string,
    newText: string): PythonWorkspaceFileInfo {
    const path = normalizePythonWorkspacePath(rawPath)
    validatePythonWorkspaceReplacement(oldText, newText)
    const existing = this.readWholeFile(sessionId, path)
    const firstIndex = existing.indexOf(oldText)
    if (firstIndex < 0) {
      throw new Error('没有在文件中找到 old_text')
    }
    if (existing.indexOf(oldText, firstIndex + oldText.length) >= 0) {
      throw new Error('old_text 在文件中出现多次，请提供更精确的匹配片段')
    }
    const updated = existing.substring(0, firstIndex) + newText +
      existing.substring(firstIndex + oldText.length)
    return this.writeFile(sessionId, path, updated)
  }

  readFile(sessionId: string, rawPath: string, requestedStartLine: number = 1,
    requestedEndLine: number = 0): PythonWorkspaceReadResult {
    const path = normalizePythonWorkspacePath(rawPath)
    const content = this.readWholeFile(sessionId, path)
    const lines = content.split('\n')
    const startLine = Math.max(1, Math.floor(requestedStartLine))
    const defaultEndLine = startLine + PYTHON_WORKSPACE_MAX_READ_LINES - 1
    const requestedEnd = requestedEndLine > 0 ? Math.floor(requestedEndLine) : defaultEndLine
    const endLine = Math.min(lines.length, Math.max(startLine, requestedEnd), defaultEndLine)
    let selected = startLine <= lines.length ? lines.slice(startLine - 1, endLine).join('\n') : ''
    let truncatedByCharacters = false
    if (selected.length > PYTHON_WORKSPACE_MAX_READ_CHARACTERS) {
      selected = selected.substring(0, PYTHON_WORKSPACE_MAX_READ_CHARACTERS)
      truncatedByCharacters = true
    }
    const result = new PythonWorkspaceReadResult()
    result.path = path
    result.content = selected
    result.startLine = startLine
    result.endLine = endLine
    result.totalLines = lines.length
    result.truncated = truncatedByCharacters || endLine < lines.length
    return result
  }

  listFiles(sessionId: string): PythonWorkspaceFileInfo[] {
    this.ensureReady()
    const sessionDirectory = this.getSessionDirectory(sessionId)
    if (!this.pathExists(sessionDirectory)) {
      return []
    }
    const files: PythonWorkspaceFileInfo[] = []
    this.collectFileInfo(sessionDirectory, '', 0, files)
    files.sort((left: PythonWorkspaceFileInfo, right: PythonWorkspaceFileInfo): number =>
      left.path.localeCompare(right.path))
    return files
  }

  snapshot(sessionId: string): PythonWorkspaceFileData[] {
    const infos = this.listFiles(sessionId)
    const snapshot: PythonWorkspaceFileData[] = []
    for (let i = 0; i < infos.length; i++) {
      snapshot.push(new PythonWorkspaceFileData(
        infos[i].path,
        this.readWholeFile(sessionId, infos[i].path),
        infos[i].size
      ))
    }
    return snapshot
  }

  syncSnapshot(sessionId: string, files: PythonWorkspaceFileData[]): void {
    this.validateSnapshot(files)
    this.mutationBatchDepth += 1
    try {
      const existing = this.listFiles(sessionId)
      const incomingPaths: string[] = []
      const incomingSizes: number[] = []
      for (let i = 0; i < files.length; i++) {
        incomingPaths.push(normalizePythonWorkspacePath(files[i].path))
        incomingSizes.push(this.encodeContent(files[i].content).byteLength)
      }
      for (let i = 0; i < existing.length; i++) {
        if (!incomingPaths.includes(existing[i].path)) {
          this.deleteFile(sessionId, existing[i].path)
        }
      }

      // 先写入体积缩小的文件，再写入新增或增长的文件。这样即使最终快照在总量限制内，
      // 也不会因回写顺序造成短暂超限，同时避免先清空整个工作区带来的数据丢失窗口。
      const writeOrder: number[] = []
      for (let i = 0; i < files.length; i++) {
        writeOrder.push(i)
      }
      writeOrder.sort((left: number, right: number): number =>
        this.fileSizeDelta(incomingPaths[left], incomingSizes[left], existing) -
          this.fileSizeDelta(incomingPaths[right], incomingSizes[right], existing))
      for (let i = 0; i < writeOrder.length; i++) {
        const index = writeOrder[i]
        this.writeFile(sessionId, incomingPaths[index], files[index].content)
      }
    } finally {
      this.finishMutationBatch()
    }
  }

  deleteFile(sessionId: string, rawPath: string): boolean {
    this.ensureReady()
    const path = normalizePythonWorkspacePath(rawPath)
    const sessionDirectory = this.getSessionDirectory(sessionId)
    const filePath = `${sessionDirectory}/${path}`
    if (!this.pathExists(filePath)) {
      return false
    }
    fileIo.unlinkSync(filePath)
    this.pruneEmptyDirectories(filePath.substring(0, filePath.lastIndexOf('/')), sessionDirectory)
    this.notifyWorkspaceChanged()
    return true
  }

  deleteSessionWorkspace(sessionId: string): boolean {
    this.ensureReady()
    const directory = this.getSessionDirectory(sessionId)
    if (!this.pathExists(directory)) {
      return true
    }
    this.deleteRecursively(directory)
    this.notifyWorkspaceChanged()
    return true
  }

  cleanupOrphanedWorkspaces(validSessionIds: string[], cleanupStartedAt: number): PythonWorkspaceCleanupResult {
    this.ensureReady()
    const result = new PythonWorkspaceCleanupResult()
    const validDirectories: string[] = []
    for (let i = 0; i < validSessionIds.length; i++) {
      validDirectories.push(encodePythonWorkspaceSessionDirectory(validSessionIds[i]))
    }
    const entries = fileIo.listFileSync(this.rootDirectory)
    for (let i = 0; i < entries.length; i++) {
      const entryPath = `${this.rootDirectory}/${entries[i]}`
      const stat = fileIo.statSync(entryPath)
      if (!stat.isDirectory()) {
        continue
      }
      const fileCount = this.countFiles(entryPath)
      result.scannedFiles += fileCount
      if (validDirectories.includes(entries[i]) ||
        this.getLatestModifiedAt(entryPath) > cleanupStartedAt - PYTHON_WORKSPACE_CACHE_GRACE_PERIOD_MS) {
        continue
      }
      try {
        this.deleteRecursively(entryPath)
        result.deletedFiles += fileCount
      } catch (error) {
        console.error('PythonWorkspaceService', `Failed to clean orphan workspace: ${JSON.stringify(error)}`)
        result.failedFiles += Math.max(1, fileCount)
      }
    }
    if (result.deletedFiles > 0) {
      this.notifyWorkspaceChanged()
    }
    return result
  }

  private notifyWorkspaceChanged(): void {
    if (this.mutationBatchDepth > 0) {
      this.mutationNotificationPending = true
      return
    }
    this.publishWorkspaceChanged()
  }

  private finishMutationBatch(): void {
    this.mutationBatchDepth = Math.max(0, this.mutationBatchDepth - 1)
    if (this.mutationBatchDepth === 0 && this.mutationNotificationPending) {
      this.mutationNotificationPending = false
      this.publishWorkspaceChanged()
    }
  }

  private publishWorkspaceChanged(): void {
    const current = getAppUiState().pythonWorkspaceRefreshAt
    const now = Date.now()
    setAppUiStateValue(AppStorageKeys.PYTHON_WORKSPACE_REFRESH_AT, now > current ? now : current + 1)
  }

  private validateSnapshot(files: PythonWorkspaceFileData[]): void {
    if (files.length > PYTHON_WORKSPACE_MAX_FILES) {
      throw new Error(`Python 工作区最多允许 ${PYTHON_WORKSPACE_MAX_FILES} 个文件`)
    }
    const paths: string[] = []
    let totalBytes = 0
    for (let i = 0; i < files.length; i++) {
      const path = normalizePythonWorkspacePath(files[i].path)
      if (paths.includes(path)) {
        throw new Error(`Python 工作区包含重复路径: ${path}`)
      }
      paths.push(path)
      const size = this.encodeContent(files[i].content).byteLength
      this.validateFileSize(size)
      totalBytes += size
    }
    if (totalBytes > PYTHON_WORKSPACE_MAX_TOTAL_BYTES) {
      throw new Error(`Python 工作区总大小不能超过 ${PYTHON_WORKSPACE_MAX_TOTAL_BYTES} 字节`)
    }
  }

  private collectFileInfo(directory: string, relativeDirectory: string, depth: number,
    files: PythonWorkspaceFileInfo[]): void {
    if (depth > 8 || files.length >= PYTHON_WORKSPACE_MAX_FILES) {
      return
    }
    const entries = fileIo.listFileSync(directory)
    for (let i = 0; i < entries.length && files.length < PYTHON_WORKSPACE_MAX_FILES; i++) {
      const fullPath = `${directory}/${entries[i]}`
      const relativePath = relativeDirectory === '' ? entries[i] : `${relativeDirectory}/${entries[i]}`
      const stat = fileIo.statSync(fullPath)
      if (stat.isDirectory()) {
        this.collectFileInfo(fullPath, relativePath, depth + 1, files)
      } else {
        files.push(new PythonWorkspaceFileInfo(relativePath, stat.size, stat.mtime))
      }
    }
  }

  private readWholeFile(sessionId: string, path: string): string {
    this.ensureReady()
    const normalizedPath = normalizePythonWorkspacePath(path)
    const filePath = `${this.getSessionDirectory(sessionId)}/${normalizedPath}`
    if (!this.pathExists(filePath)) {
      throw new Error(`工作区文件不存在: ${normalizedPath}`)
    }
    const stat = fileIo.statSync(filePath)
    this.validateFileSize(stat.size)
    return fileIo.readTextSync(filePath)
  }

  private fileExists(sessionId: string, path: string): boolean {
    return this.pathExists(`${this.getSessionDirectory(sessionId)}/${normalizePythonWorkspacePath(path)}`)
  }

  private validateFileSize(size: number): void {
    if (size > PYTHON_WORKSPACE_MAX_FILE_BYTES) {
      throw new Error(`单个工作区文件不能超过 ${PYTHON_WORKSPACE_MAX_FILE_BYTES} 字节`)
    }
  }

  private fileSizeDelta(path: string, incomingSize: number, existing: PythonWorkspaceFileInfo[]): number {
    for (let i = 0; i < existing.length; i++) {
      if (existing[i].path === path) {
        return incomingSize - existing[i].size
      }
    }
    return incomingSize
  }

  private encodeContent(content: string): Uint8Array {
    return new util.TextEncoder().encodeInto(content)
  }

  private ensureReady(): void {
    if (!this.isReady()) {
      throw new Error('Python 工作区存储尚未初始化')
    }
  }

  private getSessionDirectory(sessionId: string): string {
    this.ensureReady()
    return `${this.rootDirectory}/${encodePythonWorkspaceSessionDirectory(sessionId)}`
  }

  private ensureSessionDirectory(sessionId: string): string {
    const directory = this.getSessionDirectory(sessionId)
    if (!this.pathExists(directory)) {
      fileIo.mkdirSync(directory, true)
    }
    return directory
  }

  private pathExists(path: string): boolean {
    try {
      return fileIo.accessSync(path)
    } catch (_error) {
      return false
    }
  }

  private pruneEmptyDirectories(directory: string, sessionDirectory: string): void {
    let current = directory
    while (current.startsWith(`${sessionDirectory}/`) && current !== sessionDirectory) {
      if (fileIo.listFileSync(current).length > 0) {
        return
      }
      fileIo.rmdirSync(current)
      current = current.substring(0, current.lastIndexOf('/'))
    }
  }

  private deleteRecursively(path: string): void {
    const children = fileIo.listFileSync(path)
    for (let i = 0; i < children.length; i++) {
      const childPath = `${path}/${children[i]}`
      const stat = fileIo.statSync(childPath)
      if (stat.isDirectory()) {
        this.deleteRecursively(childPath)
      } else {
        fileIo.unlinkSync(childPath)
      }
    }
    fileIo.rmdirSync(path)
  }

  private countFiles(path: string): number {
    let count = 0
    const entries = fileIo.listFileSync(path)
    for (let i = 0; i < entries.length; i++) {
      const childPath = `${path}/${entries[i]}`
      const stat = fileIo.statSync(childPath)
      count += stat.isDirectory() ? this.countFiles(childPath) : 1
    }
    return count
  }

  private getLatestModifiedAt(path: string): number {
    let latest = fileIo.statSync(path).mtime
    const entries = fileIo.listFileSync(path)
    for (let i = 0; i < entries.length; i++) {
      const childPath = `${path}/${entries[i]}`
      const stat = fileIo.statSync(childPath)
      latest = Math.max(latest, stat.isDirectory() ? this.getLatestModifiedAt(childPath) : stat.mtime)
    }
    return latest
  }
}

export function getPythonWorkspaceService(): PythonWorkspaceService {
  return PythonWorkspaceService.getInstance()
}
