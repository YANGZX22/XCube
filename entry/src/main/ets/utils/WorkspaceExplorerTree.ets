/**
 * Python 工作区文件树。
 *
 * 服务层给出的是扁平的相对路径列表，这里折成 PC IDE 资源管理器那样的层级：
 * 目录在前、文件在后，各自按名称排序，折叠状态由调用方持有，
 * 输出的是"当前可见行"的线性数组，直接喂给 List 渲染。
 */

import { PythonWorkspaceFileInfo } from '../services/PythonWorkspaceService'
import { pickLocalizedText } from './LocalizedTextUtils'

export class WorkspaceExplorerRow {
  key: string = ''
  name: string = ''
  // 目录行是目录路径，文件行是文件相对路径
  path: string = ''
  depth: number = 0
  isDirectory: boolean = false
  expanded: boolean = false
  size: number = 0
  modifiedAt: number = 0
  // 目录：递归统计的文件数；文件：恒为 0
  fileCount: number = 0
  // 搜索结果里用来显示文件所在目录
  parentPath: string = ''
}

function compareText(left: string, right: string): number {
  if (left === right) {
    return 0
  }
  return left < right ? -1 : 1
}

export function getWorkspaceFileName(path: string): string {
  const index = path.lastIndexOf('/')
  return index >= 0 ? path.substring(index + 1) : path
}

export function getWorkspaceDirectoryPath(path: string): string {
  const index = path.lastIndexOf('/')
  return index >= 0 ? path.substring(0, index) : ''
}

export function getWorkspaceFileExtension(path: string): string {
  const name = getWorkspaceFileName(path)
  const index = name.lastIndexOf('.')
  return index > 0 ? name.substring(index + 1).toLowerCase() : ''
}

export function formatWorkspaceFileSize(size: number): string {
  if (size < 1024) {
    return `${size} B`
  }
  if (size < 1024 * 1024) {
    return `${(size / 1024).toFixed(1)} KB`
  }
  return `${(size / 1024 / 1024).toFixed(1)} MB`
}

export function formatWorkspaceModifiedAt(value: number): string {
  if (value <= 0) {
    return ''
  }
  const date = new Date(value)
  const month = (date.getMonth() + 1).toString().padStart(2, '0')
  const day = date.getDate().toString().padStart(2, '0')
  const hour = date.getHours().toString().padStart(2, '0')
  const minute = date.getMinutes().toString().padStart(2, '0')
  return `${month}-${day} ${hour}:${minute}`
}

export function describeWorkspaceDirectory(path: string): string {
  return path === '' ? pickLocalizedText('根目录', 'Workspace root') : path
}

// 收集每个目录（含祖先目录）下递归的文件数，目录行上直接显示
function collectDirectoryFileCounts(files: PythonWorkspaceFileInfo[]): Map<string, number> {
  const counts = new Map<string, number>()
  for (let i = 0; i < files.length; i++) {
    const segments = files[i].path.split('/')
    let prefix = ''
    for (let j = 0; j < segments.length - 1; j++) {
      prefix = prefix === '' ? segments[j] : `${prefix}/${segments[j]}`
      counts.set(prefix, (counts.get(prefix) ?? 0) + 1)
    }
  }
  return counts
}

function buildFilteredRows(files: PythonWorkspaceFileInfo[], keyword: string): WorkspaceExplorerRow[] {
  const matched: PythonWorkspaceFileInfo[] = []
  for (let i = 0; i < files.length; i++) {
    if (files[i].path.toLowerCase().includes(keyword)) {
      matched.push(files[i])
    }
  }
  matched.sort((left: PythonWorkspaceFileInfo, right: PythonWorkspaceFileInfo): number =>
    compareText(getWorkspaceFileName(left.path).toLowerCase(), getWorkspaceFileName(right.path).toLowerCase()))

  const rows: WorkspaceExplorerRow[] = []
  for (let i = 0; i < matched.length; i++) {
    const row = new WorkspaceExplorerRow()
    row.key = `file:${matched[i].path}`
    row.name = getWorkspaceFileName(matched[i].path)
    row.path = matched[i].path
    row.size = matched[i].size
    row.modifiedAt = matched[i].modifiedAt
    row.parentPath = getWorkspaceDirectoryPath(matched[i].path)
    rows.push(row)
  }
  return rows
}

export function buildWorkspaceExplorerRows(
  files: PythonWorkspaceFileInfo[],
  collapsedDirectories: string[],
  filterText: string
): WorkspaceExplorerRow[] {
  const keyword = filterText.trim().toLowerCase()
  if (keyword !== '') {
    return buildFilteredRows(files, keyword)
  }

  const childDirectories = new Map<string, string[]>()
  const directoryFiles = new Map<string, PythonWorkspaceFileInfo[]>()
  const knownDirectories = new Set<string>()

  for (let i = 0; i < files.length; i++) {
    const directory = getWorkspaceDirectoryPath(files[i].path)
    const bucket = directoryFiles.get(directory)
    if (bucket === undefined) {
      directoryFiles.set(directory, [files[i]])
    } else {
      bucket.push(files[i])
    }

    // 把路径上的每一级目录都登记到父目录下，中间目录没有直属文件也要出现
    const segments = files[i].path.split('/')
    let parent = ''
    for (let j = 0; j < segments.length - 1; j++) {
      const current = parent === '' ? segments[j] : `${parent}/${segments[j]}`
      if (!knownDirectories.has(current)) {
        knownDirectories.add(current)
        const siblings = childDirectories.get(parent)
        if (siblings === undefined) {
          childDirectories.set(parent, [current])
        } else {
          siblings.push(current)
        }
      }
      parent = current
    }
  }

  const fileCounts = collectDirectoryFileCounts(files)
  const rows: WorkspaceExplorerRow[] = []
  appendDirectoryRows(rows, '', 0, childDirectories, directoryFiles, fileCounts, collapsedDirectories)
  return rows
}

function appendDirectoryRows(
  rows: WorkspaceExplorerRow[],
  directory: string,
  depth: number,
  childDirectories: Map<string, string[]>,
  directoryFiles: Map<string, PythonWorkspaceFileInfo[]>,
  fileCounts: Map<string, number>,
  collapsedDirectories: string[]
): void {
  const children = childDirectories.get(directory) ?? []
  children.sort((left: string, right: string): number =>
    compareText(getWorkspaceFileName(left).toLowerCase(), getWorkspaceFileName(right).toLowerCase()))

  for (let i = 0; i < children.length; i++) {
    const childPath = children[i]
    const expanded = !collapsedDirectories.includes(childPath)
    const row = new WorkspaceExplorerRow()
    row.key = `dir:${childPath}`
    row.name = getWorkspaceFileName(childPath)
    row.path = childPath
    row.depth = depth
    row.isDirectory = true
    row.expanded = expanded
    row.fileCount = fileCounts.get(childPath) ?? 0
    rows.push(row)

    if (expanded) {
      appendDirectoryRows(rows, childPath, depth + 1, childDirectories, directoryFiles, fileCounts,
        collapsedDirectories)
    }
  }

  const ownFiles = directoryFiles.get(directory) ?? []
  ownFiles.sort((left: PythonWorkspaceFileInfo, right: PythonWorkspaceFileInfo): number =>
    compareText(getWorkspaceFileName(left.path).toLowerCase(), getWorkspaceFileName(right.path).toLowerCase()))

  for (let i = 0; i < ownFiles.length; i++) {
    const row = new WorkspaceExplorerRow()
    row.key = `file:${ownFiles[i].path}`
    row.name = getWorkspaceFileName(ownFiles[i].path)
    row.path = ownFiles[i].path
    row.depth = depth
    row.size = ownFiles[i].size
    row.modifiedAt = ownFiles[i].modifiedAt
    row.parentPath = directory
    rows.push(row)
  }
}
