/**
 * Python 工作区页面。
 *
 * 从工具栏的"工作区"按钮进入，是一个独立页面而不是半屏面板：
 * 文件多、路径深的时候半屏容纳不下，代码也需要整屏来读。
 *
 * 布局参照 PC IDE：左侧资源管理器（可折叠的目录树 + 文件过滤），
 * 右侧只读编辑器（带行号槽）。宽屏左右并排，窄屏则由列表推进到编辑器。
 */

import {
  PythonWorkspaceFileInfo,
  PYTHON_WORKSPACE_MAX_FILE_BYTES,
  PythonWorkspaceReadResult,
  PythonWorkspaceService,
  normalizePythonWorkspacePath
} from '../services/PythonWorkspaceService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { getAppUiState } from '../state/AppUiState'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { showToast } from '../utils/ToastUtil'
import { pasteboard } from '@kit.BasicServicesKit'
import { fileIo, picker } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import {
  buildWorkspaceExplorerRows,
  describeWorkspaceDirectory,
  formatWorkspaceFileSize,
  formatWorkspaceModifiedAt,
  getWorkspaceFileExtension,
  getWorkspaceFileName,
  WorkspaceExplorerRow
} from '../utils/WorkspaceExplorerTree'

export interface PythonWorkspacePageParams {
  sessionId?: string
  sessionTitle?: string
}

let pythonWorkspacePagePathStack: NavPathStack | null = null

function resolvePythonWorkspacePageParams(param: Object): PythonWorkspacePageParams {
  return param as PythonWorkspacePageParams
}

function popPythonWorkspacePage(): boolean {
  if (pythonWorkspacePagePathStack === null || pythonWorkspacePagePathStack.size() <= 0) {
    return false
  }
  pythonWorkspacePagePathStack.pop()
  return true
}

// 宽到能并排放下资源管理器和编辑器时才分栏，否则窄屏由列表推进到编辑器
const WIDE_LAYOUT_MIN_WIDTH_VP: number = 720
const EXPLORER_PANE_WIDTH_VP: number = 292
const EXPLORER_INDENT_VP: number = 14
const CODE_FONT_SIZE: number = 12.5
const CODE_LINE_HEIGHT: number = 20

class WorkspaceCodeLine {
  lineNumber: number = 0
  text: string = ''

  constructor(lineNumber: number, text: string) {
    this.lineNumber = lineNumber
    this.text = text
  }
}

class WorkspaceUploadData {
  path: string = ''
  content: string = ''

  constructor(path: string, content: string) {
    this.path = path
    this.content = content
  }
}

@ComponentV2
struct PythonWorkspacePageContent {
  @Param sessionId: string = ''
  @Param sessionTitle: string = ''
  @Event onClose: () => void = (): void => {}

  @Local files: PythonWorkspaceFileInfo[] = []
  @Local directories: string[] = []
  @Local isLoading: boolean = true
  @Local loadError: string = ''
  @Local filterText: string = ''
  @Local collapsedDirectories: string[] = []
  @Local selectedPath: string = ''
  @Local previewLines: WorkspaceCodeLine[] = []
  @Local previewStartLine: number = 1
  @Local previewEndLine: number = 0
  @Local previewTotalLines: number = 0
  @Local previewTruncated: boolean = false
  @Local previewError: string = ''
  @Local createItemName: string = ''
  @Local createItemDirectory: string = ''
  @Local createItemKind: string = 'file'

  private workspaceService: PythonWorkspaceService = ServiceRegistry.pythonWorkspace()
  private previewContent: string = ''
  private createItemDialogId: number = -1

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  // 与 MapRoutePage 一致的 px→vp 换算（全局 px2vp 已废弃）
  private px2vp(value: number): number {
    const density = this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3
    return value / density * 160
  }

  private get topInsetVp(): number {
    return this.px2vp(getAppUiState().topAvoidHeight)
  }

  private get bottomInsetVp(): number {
    return this.px2vp(getAppUiState().bottomAvoidHeight)
  }

  private isWideLayout(): boolean {
    return getAppUiState().windowWidthVp >= WIDE_LAYOUT_MIN_WIDTH_VP
  }

  aboutToAppear(): void {
    this.loadWorkspace()
  }

  @Monitor('sessionId')
  onSessionIdChanged(): void {
    this.closeFile()
    this.loadWorkspace()
  }

  // 刷新保留当前打开的文件：还在就重新读，已经没了才退回空态
  private loadWorkspace(): void {
    this.isLoading = true
    this.loadError = ''
    try {
      this.files = this.sessionId.trim() === '' ? [] : this.workspaceService.listFiles(this.sessionId)
      this.directories = this.sessionId.trim() === '' ? [] : this.workspaceService.listDirectories(this.sessionId)
    } catch (error) {
      console.error('PythonWorkspacePage', `Failed to load workspace: ${JSON.stringify(error)}`)
      this.files = []
      this.directories = []
      this.loadError = this.stringifyError(error)
    } finally {
      this.isLoading = false
    }

    if (this.selectedPath === '') {
      return
    }
    if (this.findFile(this.selectedPath) === null) {
      this.closeFile()
      return
    }
    this.readSelectedFile()
  }

  private findFile(path: string): PythonWorkspaceFileInfo | null {
    for (let i = 0; i < this.files.length; i++) {
      if (this.files[i].path === path) {
        return this.files[i]
      }
    }
    return null
  }

  private getSelectedFileSize(): number {
    const file = this.findFile(this.selectedPath)
    return file === null ? 0 : file.size
  }

  private getSelectedFileModifiedAt(): number {
    const file = this.findFile(this.selectedPath)
    return file === null ? 0 : file.modifiedAt
  }

  private openFile(path: string): void {
    this.selectedPath = path
    this.readSelectedFile()
  }

  private readSelectedFile(): void {
    this.previewError = ''
    this.previewContent = ''
    this.previewLines = []
    this.previewStartLine = 1
    this.previewEndLine = 0
    this.previewTotalLines = 0
    this.previewTruncated = false
    try {
      const result: PythonWorkspaceReadResult = this.workspaceService.readFile(this.sessionId, this.selectedPath)
      this.previewContent = result.content
      this.previewStartLine = result.startLine
      this.previewEndLine = result.endLine
      this.previewTotalLines = result.totalLines
      this.previewTruncated = result.truncated
      this.previewLines = this.buildCodeLines(result.content, result.startLine)
    } catch (error) {
      this.previewError = this.stringifyError(error)
    }
  }

  private buildCodeLines(content: string, startLine: number): WorkspaceCodeLine[] {
    const lines: WorkspaceCodeLine[] = []
    const rawLines = content.split('\n')
    for (let i = 0; i < rawLines.length; i++) {
      lines.push(new WorkspaceCodeLine(startLine + i, rawLines[i]))
    }
    return lines
  }

  private closeFile(): void {
    this.selectedPath = ''
    this.previewContent = ''
    this.previewLines = []
    this.previewStartLine = 1
    this.previewEndLine = 0
    this.previewTotalLines = 0
    this.previewTruncated = false
    this.previewError = ''
  }

  private toggleDirectory(path: string): void {
    const next = this.collapsedDirectories.slice()
    const index = next.indexOf(path)
    if (index >= 0) {
      next.splice(index, 1)
    } else {
      next.push(path)
    }
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => {
      this.collapsedDirectories = next
    })
  }

  private copyPreviewContent(): void {
    if (this.previewContent === '') {
      return
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.previewContent)
      pasteboard.getSystemPasteboard().setData(data)
      showToast(this.getUIContext(), $r('app.string.copy_success'))
    } catch (error) {
      console.error('PythonWorkspacePage', `Copy failed: ${JSON.stringify(error)}`)
    }
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message
    }
    return JSON.stringify(error)
  }

  private getExplorerRows(): WorkspaceExplorerRow[] {
    return buildWorkspaceExplorerRows(this.files, this.directories, this.collapsedDirectories, this.filterText)
  }

  private buildChildPath(directory: string, name: string): string {
    const trimmedName = name.trim()
    return normalizePythonWorkspacePath(directory === '' ? trimmedName : `${directory}/${trimmedName}`)
  }

  private openCreateItemDialog(directory: string, kind: string): void {
    if (this.sessionId.trim() === '') {
      return
    }
    this.createItemDirectory = directory
    this.createItemKind = kind
    this.createItemName = ''
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: (): void => {
        this.CreateWorkspaceItemDialog()
      },
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 24,
      backgroundColor: this.getSurfaceColor()
    }).then((dialogId: number): void => {
      this.createItemDialogId = dialogId
    }).catch((error: Object): void => {
      console.error('PythonWorkspacePage', `Failed to open create dialog: ${JSON.stringify(error)}`)
    })
  }

  private closeCreateItemDialog(): void {
    if (this.createItemDialogId < 0) {
      return
    }
    this.getUIContext().getPromptAction().closeCustomDialog(this.createItemDialogId)
    this.createItemDialogId = -1
  }

  private createWorkspaceItem(): void {
    this.performCreateWorkspaceItem().catch((error: Object): void => {
      showToast(this.getUIContext(), this.stringifyError(error))
    })
  }

  private async performCreateWorkspaceItem(): Promise<void> {
    const path = this.buildChildPath(this.createItemDirectory, this.createItemName)
    await this.workspaceService.runSessionExclusive(this.sessionId, async (): Promise<void> => {
      this.workspaceService.assertSessionWritable(this.sessionId)
      if (this.createItemKind === 'directory') {
        this.workspaceService.createDirectory(this.sessionId, path)
      } else {
        this.workspaceService.writeFile(this.sessionId, path, '', 0)
      }
    })
    this.closeCreateItemDialog()
    this.loadWorkspace()
    showToast(this.getUIContext(), this.createItemKind === 'directory'
      ? pickLocalizedText('文件夹已创建', 'Folder created')
      : pickLocalizedText('文件已创建', 'File created'))
  }

  private chooseWorkspaceFiles(directory: string): void {
    this.performChooseWorkspaceFiles(directory).catch((error: Object): void => {
      console.error('PythonWorkspacePage', `Workspace upload failed: ${JSON.stringify(error)}`)
      showToast(this.getUIContext(), this.stringifyError(error))
    })
  }

  private async performChooseWorkspaceFiles(directory: string): Promise<void> {
    const context = this.getUIContext().getHostContext()
    if (context === undefined) {
      throw new Error(pickLocalizedText('当前页面上下文不可用', 'The current page context is unavailable'))
    }
    const options = new picker.DocumentSelectOptions()
    options.maxSelectNumber = 10
    const uris = await new picker.DocumentViewPicker(context).select(options)
    if (uris.length === 0) {
      return
    }
    const uploads: WorkspaceUploadData[] = []
    for (let i = 0; i < uris.length; i++) {
      uploads.push(this.readWorkspaceUpload(uris[i], directory))
    }
    await this.workspaceService.runSessionExclusive(this.sessionId, async (): Promise<void> => {
      this.workspaceService.assertSessionWritable(this.sessionId)
      const existing = this.workspaceService.listFiles(this.sessionId)
      const pendingPaths: string[] = []
      for (let i = 0; i < uploads.length; i++) {
        const path = uploads[i].path
        if (pendingPaths.includes(path)) {
          throw new Error(`选择的文件包含重复名称: ${path}`)
        }
        pendingPaths.push(path)
        for (let j = 0; j < existing.length; j++) {
          if (existing[j].path === path) {
            throw new Error(`工作区文件已存在: ${path}`)
          }
        }
      }
      for (let i = 0; i < uploads.length; i++) {
        this.workspaceService.writeFile(this.sessionId, uploads[i].path, uploads[i].content, 0)
      }
    })
    this.loadWorkspace()
    showToast(this.getUIContext(), pickLocalizedText(
      `已上传 ${uploads.length} 个文件`, `Uploaded ${uploads.length} file(s)`))
  }

  private readWorkspaceUpload(uri: string, directory: string): WorkspaceUploadData {
    const fileName = this.getFileNameFromUri(uri)
    const path = this.buildChildPath(directory, fileName)
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
    try {
      const stat = fileIo.statSync(file.fd)
      if (stat.size > PYTHON_WORKSPACE_MAX_FILE_BYTES) {
        throw new Error(`${fileName} 超过工作区单文件大小限制`)
      }
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      const content = util.TextDecoder.create('utf-8')
        .decodeToString(new Uint8Array(buffer), { stream: false })
      if (content.includes('\uFFFD')) {
        throw new Error(`${fileName} 不是有效的 UTF-8 文本，无法加入 Python 文本工作区`)
      }
      return new WorkspaceUploadData(path, content)
    } finally {
      fileIo.closeSync(file)
    }
  }

  private getFileNameFromUri(uri: string): string {
    const parts = uri.split('/')
    const encodedName = (parts[parts.length - 1] || 'workspace-file').split('?')[0].split('#')[0]
    try {
      return decodeURIComponent(encodedName)
    } catch (_error) {
      return encodedName
    }
  }

  private requestDeleteWorkspaceItem(row: WorkspaceExplorerRow): void {
    const itemKind = row.isDirectory
      ? pickLocalizedText('文件夹', 'folder') : pickLocalizedText('文件', 'file')
    this.getUIContext().showAlertDialog({
      title: row.isDirectory
        ? pickLocalizedText('删除文件夹', 'Delete folder')
        : pickLocalizedText('删除文件', 'Delete file'),
      message: row.isDirectory
        ? pickLocalizedText(`将递归删除${itemKind}“${row.path}”及其中全部内容。`,
          `This recursively deletes ${itemKind} “${row.path}” and all of its contents.`)
        : pickLocalizedText(`将删除${itemKind}“${row.path}”。`, `This deletes ${itemKind} “${row.path}”.`),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: Color.Red,
        action: () => {
          this.deleteWorkspaceItem(row)
        }
      }
    })
  }

  private deleteWorkspaceItem(row: WorkspaceExplorerRow): void {
    this.performDeleteWorkspaceItem(row).catch((error: Object): void => {
      showToast(this.getUIContext(), this.stringifyError(error))
      this.loadWorkspace()
    })
  }

  private async performDeleteWorkspaceItem(row: WorkspaceExplorerRow): Promise<void> {
    await this.workspaceService.runSessionExclusive(this.sessionId, async (): Promise<void> => {
      this.workspaceService.assertSessionWritable(this.sessionId)
      const deleted = row.isDirectory
        ? this.workspaceService.deleteDirectory(this.sessionId, row.path)
        : this.workspaceService.deleteFile(this.sessionId, row.path, row.modifiedAt)
      if (!deleted) {
        throw new Error(`${row.path} 已不存在`)
      }
    })
    if (this.selectedPath === row.path ||
      (row.isDirectory && this.selectedPath.startsWith(`${row.path}/`))) {
      this.closeFile()
    }
    this.loadWorkspace()
    showToast(this.getUIContext(), pickLocalizedText('已删除', 'Deleted'))
  }

  private getDisplaySessionTitle(): string {
    const title = this.sessionTitle.trim()
    return title !== '' ? title : pickLocalizedText('当前会话', 'Current conversation')
  }

  private getTotalSize(): number {
    let total = 0
    for (let i = 0; i < this.files.length; i++) {
      total += this.files[i].size
    }
    return total
  }

  private getFileAccentColor(path: string): string {
    const extension = getWorkspaceFileExtension(path)
    if (extension === 'py') {
      return '#3776AB'
    }
    if (extension === 'md' || extension === 'markdown' || extension === 'txt') {
      return '#8057C8'
    }
    if (extension === 'json' || extension === 'yaml' || extension === 'yml' || extension === 'toml') {
      return '#C07A20'
    }
    if (extension === 'csv' || extension === 'tsv') {
      return '#2E8B57'
    }
    return this.themePrimary
  }

  // 行号槽宽度跟着最大行号走，位数变了也不会挤到代码
  private getGutterWidth(): number {
    const digits = Math.max(2, this.previewEndLine.toString().length)
    return 14 + digits * 8
  }

  private getSurfaceColor(): string {
    return getAppUiState().themeSurface
  }

  private getDividerColor(): string {
    return getAppUiState().themeDivider
  }

  private getSoftAccentColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '24' : '12')
  }

  private isRowSelected(row: WorkspaceExplorerRow): boolean {
    return !row.isDirectory && this.selectedPath === row.path
  }

  @Builder
  private IconButton(icon: Resource, action: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      SymbolGlyph(icon)
        .fontSize(17)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width(36)
    .height(36)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .onClick(action)
  }

  @Builder
  private CreateWorkspaceItemDialog() {
    Column({ space: 16 }) {
      Text(this.createItemKind === 'directory'
        ? pickLocalizedText('新建文件夹', 'New folder')
        : pickLocalizedText('新建文件', 'New file'))
        .width('100%')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text(pickLocalizedText(
        `位置：${describeWorkspaceDirectory(this.createItemDirectory)}`,
        `Location: ${describeWorkspaceDirectory(this.createItemDirectory)}`))
        .width('100%')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(2)

      TextInput({
        text: this.createItemName,
        placeholder: this.createItemKind === 'directory'
          ? pickLocalizedText('文件夹名称', 'Folder name')
          : pickLocalizedText('文件名，例如 main.py', 'File name, e.g. main.py')
      })
        .width('100%')
        .height(44)
        .fontSize(14)
        .caretColor(this.themePrimary)
        .onChange((value: string): void => {
          this.createItemName = value
        })

      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .layoutWeight(1)
          .height(40)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.closeCreateItemDialog()
          })

        Button(pickLocalizedText('创建', 'Create'))
          .layoutWeight(1)
          .height(40)
          .fontColor(Color.White)
          .backgroundColor(this.themePrimary)
          .enabled(this.createItemName.trim() !== '')
          .opacity(this.createItemName.trim() !== '' ? 1 : 0.45)
          .onClick((): void => {
            this.createWorkspaceItem()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private WorkspaceDirectoryContextMenu(directory: string) {
    Menu() {
      MenuItem({
        startIcon: $r('sys.symbol.paperclip'),
        content: pickLocalizedText('上传文件', 'Upload files')
      })
        .onClick((): void => {
          this.chooseWorkspaceFiles(directory)
        })
      MenuItem({
        startIcon: $r('sys.symbol.doc'),
        content: pickLocalizedText('新建文件', 'New file')
      })
        .onClick((): void => {
          this.openCreateItemDialog(directory, 'file')
        })
      MenuItem({
        startIcon: $r('sys.symbol.folder'),
        content: pickLocalizedText('新建文件夹', 'New folder')
      })
        .onClick((): void => {
          this.openCreateItemDialog(directory, 'directory')
        })
    }
  }

  @Builder
  private WorkspaceItemContextMenu(row: WorkspaceExplorerRow) {
    Menu() {
      if (row.isDirectory) {
        MenuItem({
          startIcon: $r('sys.symbol.paperclip'),
          content: pickLocalizedText('上传到此文件夹', 'Upload to this folder')
        })
          .onClick((): void => {
            this.chooseWorkspaceFiles(row.path)
          })
        MenuItem({
          startIcon: $r('sys.symbol.doc'),
          content: pickLocalizedText('在此新建文件', 'New file here')
        })
          .onClick((): void => {
            this.openCreateItemDialog(row.path, 'file')
          })
        MenuItem({
          startIcon: $r('sys.symbol.folder'),
          content: pickLocalizedText('在此新建文件夹', 'New folder here')
        })
          .onClick((): void => {
            this.openCreateItemDialog(row.path, 'directory')
          })
      }
      MenuItem({ startIcon: $r('sys.symbol.trash'), content: $r('app.string.delete') })
        .contentFontColor(Color.Red)
        .onClick((): void => {
          this.requestDeleteWorkspaceItem(row)
        })
    }
  }

  @Builder
  private TopBar() {
    Row({ space: 4 }) {
      this.IconButton($r('sys.symbol.chevron_left'), (): void => {
        this.onClose()
      })

      Column({ space: 1 }) {
        Text(pickLocalizedText('工作区', 'Workspace'))
          .width('100%')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.getDisplaySessionTitle())
          .width('100%')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.IconButton($r('sys.symbol.arrow_clockwise'), (): void => {
        this.loadWorkspace()
      })
    }
    .width('100%')
    .height(52)
    .padding({ left: 8, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ExplorerHeader() {
    Row() {
      Text(pickLocalizedText('资源管理器', 'Explorer'))
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .letterSpacing(0.8)
        .fontColor($r('app.color.text_tertiary'))

      Blank().layoutWeight(1)

      Text(`${this.files.length} / ${this.directories.length} · ${formatWorkspaceFileSize(this.getTotalSize())}`)
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .height(28)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private FilterField() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(13)
        .fontColor([$r('app.color.text_tertiary')])

      TextInput({ text: this.filterText, placeholder: pickLocalizedText('过滤文件', 'Filter files') })
        .layoutWeight(1)
        .height(32)
        .padding(0)
        .borderRadius(0)
        .backgroundColor(Color.Transparent)
        .fontSize(12)
        .placeholderFont({ size: 12 })
        .placeholderColor($r('app.color.text_tertiary'))
        .caretColor(this.themePrimary)
        .onChange((value: string): void => {
          this.filterText = value
        })

      if (this.filterText !== '') {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(12)
          .fontColor([$r('app.color.text_tertiary')])
          .onClick((): void => {
            this.filterText = ''
          })
      }
    }
    .width('100%')
    .height(34)
    .padding({ left: 10, right: 10 })
    .borderRadius(9)
    .backgroundColor(this.getSurfaceColor())
    .border({ width: 0.5, color: this.getDividerColor() })
    .margin({ left: 12, right: 12, bottom: 8 })
  }

  @Builder
  private ExplorerRowView(row: WorkspaceExplorerRow) {
    Row({ space: 6 }) {
      if (row.isDirectory) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(11)
          .fontColor([$r('app.color.text_tertiary')])
          .rotate({ angle: row.expanded ? 90 : 0 })
          .animation({ duration: 180, curve: Curve.EaseOut })

        SymbolGlyph(row.expanded ? $r('sys.symbol.folder') : $r('sys.symbol.folder_fill'))
          .fontSize(14)
          .fontColor([this.themePrimary])
      } else {
        // 文件行左侧留出与目录箭头等宽的位置，同级的名字才对得齐
        Row().width(11)

        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(14)
          .fontColor([this.getFileAccentColor(row.path)])
      }

      Column({ space: 1 }) {
        Text(row.name)
          .width('100%')
          .fontFamily(row.isDirectory ? '' : 'monospace')
          .fontSize(12.5)
          .fontWeight(row.isDirectory || this.isRowSelected(row) ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.isRowSelected(row) ? this.themePrimary : $r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (!row.isDirectory && this.filterText.trim() !== '') {
          Text(describeWorkspaceDirectory(row.parentPath))
            .width('100%')
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (row.isDirectory) {
        Text(`${row.fileCount}`)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      } else {
        Text(formatWorkspaceFileSize(row.size))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .height(!row.isDirectory && this.filterText.trim() !== '' ? 40 : 32)
    .padding({ left: 12 + row.depth * EXPLORER_INDENT_VP, right: 12 })
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: {
        .backgroundColor(this.isRowSelected(row) ? this.getSoftAccentColor() : Color.Transparent)
      },
      pressed: {
        .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '1F' : '12'))
      }
    })
    .onClick((): void => {
      if (row.isDirectory) {
        this.toggleDirectory(row.path)
        return
      }
      this.openFile(row.path)
    })
    .bindContextMenu(this.WorkspaceItemContextMenu(row), ResponseType.LongPress)
  }

  @Builder
  private EmptyState(icon: Resource, title: ResourceStr, description: ResourceStr) {
    Column({ space: 10 }) {
      Column() {
        SymbolGlyph(icon)
          .fontSize(28)
          .fontColor([this.themePrimary])
      }
      .width(60)
      .height(60)
      .borderRadius(18)
      .backgroundColor(this.getSoftAccentColor())
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)

      Text(description)
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 28, right: 28, bottom: 32 })
  }

  @Builder
  private ExplorerPane() {
    Column() {
      this.ExplorerHeader()

      if (this.files.length > 0 || this.directories.length > 0 || this.filterText !== '') {
        this.FilterField()
      }

      if (this.sessionId.trim() === '') {
        this.EmptyState(
          $r('sys.symbol.ellipsis_message'),
          pickLocalizedText('暂无活动会话', 'No active conversation'),
          pickLocalizedText('请先打开一个会话，再查看对应工作区。',
            'Open a conversation first to view its workspace.')
        )
      } else if (this.isLoading) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(26)
            .height(26)
            .color(this.themePrimary)
          Text(pickLocalizedText('正在读取工作区...', 'Loading workspace...'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.loadError !== '') {
        this.EmptyState(
          $r('sys.symbol.exclamationmark_triangle'),
          pickLocalizedText('工作区读取失败', 'Unable to load workspace'),
          this.loadError
        )
      } else if (this.files.length === 0 && this.directories.length === 0) {
        this.EmptyState(
          $r('sys.symbol.folder'),
          pickLocalizedText('工作区暂无文件', 'Workspace is empty'),
          pickLocalizedText('模型创建的内容会显示在这里；长按空白处可上传或新建。',
            'Model-created content appears here; long-press empty space to upload or create.')
        )
      } else if (this.getExplorerRows().length === 0) {
        this.EmptyState(
          $r('sys.symbol.magnifyingglass'),
          pickLocalizedText('没有匹配的文件', 'No matching files'),
          pickLocalizedText('换个关键词再试试。', 'Try a different keyword.')
        )
      } else {
        List({ space: 2 }) {
          ForEach(this.getExplorerRows(), (row: WorkspaceExplorerRow) => {
            ListItem() {
              this.ExplorerRowView(row)
            }
            .focusable(true)
            .selectable(false)
          }, (row: WorkspaceExplorerRow): string => `${row.key}:${row.expanded}:${this.selectedPath === row.path}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 6, right: 6, bottom: 12 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(8)
      }
    }
    .width('100%')
    .height('100%')
    .bindContextMenu(this.WorkspaceDirectoryContextMenu(''), ResponseType.LongPress)
  }

  @Builder
  private EditorHeader() {
    Column() {
      Row({ space: 8 }) {
        if (!this.isWideLayout()) {
          this.IconButton($r('sys.symbol.chevron_left'), (): void => {
            this.closeFile()
          })
        }

        Column({ space: 2 }) {
          Text(getWorkspaceFileName(this.selectedPath))
            .width('100%')
            .fontFamily('monospace')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.selectedPath)
            .width('100%')
            .fontFamily('monospace')
            .fontSize(10.5)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.IconButton($r('sys.symbol.checkmark_square_on_square'), (): void => {
          this.copyPreviewContent()
        })
      }
      .width('100%')
      .height(52)
      .padding({ left: this.isWideLayout() ? 16 : 8, right: 10 })
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        Text(pickLocalizedText(`${this.previewTotalLines} 行`, `${this.previewTotalLines} lines`))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))

        Text(formatWorkspaceFileSize(this.getSelectedFileSize()))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))

        Text(formatWorkspaceModifiedAt(this.getSelectedFileModifiedAt()))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))

        Blank().layoutWeight(1)

        Text(pickLocalizedText('只读', 'Read only'))
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(9)
          .backgroundColor(this.getSoftAccentColor())
      }
      .width('100%')
      .height(28)
      .padding({ left: this.isWideLayout() ? 16 : 14, right: 14 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }

  @Builder
  private CodeLineRow(line: WorkspaceCodeLine) {
    Row() {
      Text(`${line.lineNumber}`)
        .width(this.getGutterWidth())
        .fontFamily('monospace')
        .fontSize(CODE_FONT_SIZE)
        .lineHeight(CODE_LINE_HEIGHT)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.End)
        .padding({ right: 10 })

      // 长行按 IDE 的自动换行处理：行号停在首行，续行自然缩在代码列里
      Text(line.text === '' ? ' ' : line.text)
        .layoutWeight(1)
        .fontFamily('monospace')
        .fontSize(CODE_FONT_SIZE)
        .lineHeight(CODE_LINE_HEIGHT)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ right: 14 })
  }

  @Builder
  private EditorPane() {
    Column() {
      if (this.selectedPath === '') {
        this.EmptyState(
          $r('sys.symbol.doc_text'),
          pickLocalizedText('未打开文件', 'No file open'),
          pickLocalizedText('在左侧选择一个文件查看内容。', 'Pick a file on the left to read it.')
        )
      } else {
        this.EditorHeader()

        Divider()
          .strokeWidth(0.5)
          .color(this.getDividerColor())

        if (this.previewError !== '') {
          this.EmptyState(
            $r('sys.symbol.exclamationmark_triangle'),
            pickLocalizedText('无法读取文件', 'Unable to read file'),
            this.previewError
          )
        } else {
          List() {
            ForEach(this.previewLines, (line: WorkspaceCodeLine) => {
              ListItem() {
                this.CodeLineRow(line)
              }
              .focusable(false)
              .selectable(false)
            }, (line: WorkspaceCodeLine): string => `${this.selectedPath}:${line.lineNumber}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ top: 10, bottom: 16 })
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .cachedCount(20)

          if (this.previewTruncated) {
            Text(pickLocalizedText(
              `只读预览显示第 ${this.previewStartLine}-${this.previewEndLine} 行，共 ${this.previewTotalLines} 行；可由模型继续读取其余内容。`,
              `Preview shows lines ${this.previewStartLine}-${this.previewEndLine} of ${this.previewTotalLines}; the model can read the rest.`
            ))
              .width('100%')
              .fontSize(10.5)
              .lineHeight(16)
              .fontColor($r('app.color.text_tertiary'))
              .padding({ left: 16, right: 16, top: 8, bottom: 12 })
              .backgroundColor(this.getSoftAccentColor())
          }
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      this.TopBar()

      Divider()
        .strokeWidth(0.5)
        .color(this.getDividerColor())

      if (this.isWideLayout()) {
        Row() {
          Column() {
            this.ExplorerPane()
          }
          .width(EXPLORER_PANE_WIDTH_VP)
          .height('100%')

          Divider()
            .vertical(true)
            .strokeWidth(0.5)
            .color(this.getDividerColor())

          Column() {
            this.EditorPane()
          }
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
      } else if (this.selectedPath === '') {
        Column() {
          this.ExplorerPane()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Column() {
          this.EditorPane()
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topInsetVp, bottom: this.bottomInsetVp })
    .backgroundColor(getAppUiState().themeBackground)
  }
}

@Builder
export function PythonWorkspacePageBuilder(name: string, param: Object) {
  NavDestination() {
    PythonWorkspacePageContent({
      sessionId: resolvePythonWorkspacePageParams(param).sessionId ?? '',
      sessionTitle: resolvePythonWorkspacePageParams(param).sessionTitle ?? '',
      onClose: (): void => {
        popPythonWorkspacePage()
      }
    })
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext): void => {
    pythonWorkspacePagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => popPythonWorkspacePage())
}
