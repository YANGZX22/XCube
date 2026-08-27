import {
  PythonWorkspaceFileInfo,
  PythonWorkspaceReadResult,
  PythonWorkspaceService
} from '../../services/PythonWorkspaceService'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { getAppUiState } from '../../state/AppUiState'
import { pickLocalizedText } from '../../utils/LocalizedTextUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { ImmersiveSheetHeader } from '../ImmersiveSheetHeader'

@ComponentV2
export struct PythonWorkspaceSheetContent {
  @Param sessionId: string = ''
  @Param sessionTitle: string = ''
  @Event onClose: () => void = (): void => {}
  @Local files: PythonWorkspaceFileInfo[] = []
  @Local isLoading: boolean = true
  @Local loadError: string = ''
  @Local previewPath: string = ''
  @Local previewText: string = ''
  @Local previewStartLine: number = 1
  @Local previewEndLine: number = 0
  @Local previewTotalLines: number = 0
  @Local previewTruncated: boolean = false

  private workspaceService: PythonWorkspaceService = ServiceRegistry.pythonWorkspace()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    this.loadWorkspace()
  }

  @Monitor('sessionId')
  onSessionIdChanged(): void {
    this.closePreview()
    this.loadWorkspace()
  }

  private loadWorkspace(): void {
    this.isLoading = true
    this.loadError = ''
    try {
      if (this.sessionId.trim() === '') {
        this.files = []
      } else {
        this.files = this.workspaceService.listFiles(this.sessionId)
      }
    } catch (error) {
      console.error('PythonWorkspaceSheetContent', `Failed to load workspace: ${JSON.stringify(error)}`)
      this.files = []
      this.loadError = this.stringifyError(error)
    } finally {
      this.isLoading = false
    }
  }

  private openPreview(file: PythonWorkspaceFileInfo): void {
    this.previewPath = file.path
    this.previewText = ''
    this.previewStartLine = 1
    this.previewEndLine = 0
    this.previewTotalLines = 0
    this.previewTruncated = false
    try {
      const result: PythonWorkspaceReadResult = this.workspaceService.readFile(this.sessionId, file.path)
      this.previewText = result.content
      this.previewStartLine = result.startLine
      this.previewEndLine = result.endLine
      this.previewTotalLines = result.totalLines
      this.previewTruncated = result.truncated
    } catch (error) {
      this.previewText = pickLocalizedText(
        `无法读取文件：${this.stringifyError(error)}`,
        `Unable to read file: ${this.stringifyError(error)}`
      )
    }
  }

  private closePreview(): void {
    this.previewPath = ''
    this.previewText = ''
    this.previewStartLine = 1
    this.previewEndLine = 0
    this.previewTotalLines = 0
    this.previewTruncated = false
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message
    }
    return JSON.stringify(error)
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

  private getFileName(path: string): string {
    const index = path.lastIndexOf('/')
    return index >= 0 ? path.substring(index + 1) : path
  }

  private getDirectoryName(path: string): string {
    const index = path.lastIndexOf('/')
    return index >= 0 ? path.substring(0, index) : pickLocalizedText('根目录', 'Workspace root')
  }

  private getFileExtension(path: string): string {
    const name = this.getFileName(path)
    const index = name.lastIndexOf('.')
    return index > 0 ? name.substring(index + 1).toLowerCase() : ''
  }

  private getFileAccentColor(path: string): string {
    const extension = this.getFileExtension(path)
    if (extension === 'py') {
      return '#3776AB'
    }
    if (extension === 'md' || extension === 'markdown') {
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

  private formatFileSize(size: number): string {
    if (size < 1024) {
      return `${size} B`
    }
    if (size < 1024 * 1024) {
      return `${(size / 1024).toFixed(1)} KB`
    }
    return `${(size / 1024 / 1024).toFixed(1)} MB`
  }

  private formatModifiedAt(value: number): string {
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

  private buildNumberedPreview(): string {
    if (this.previewText === '') {
      return pickLocalizedText('（空文件）', '(Empty file)')
    }
    const lines = this.previewText.split('\n')
    const lastLine = this.previewStartLine + lines.length - 1
    const numberWidth = Math.max(2, lastLine.toString().length)
    const numbered: string[] = []
    for (let i = 0; i < lines.length; i++) {
      numbered.push(`${(this.previewStartLine + i).toString().padStart(numberWidth, ' ')}  ${lines[i]}`)
    }
    return numbered.join('\n')
  }

  @Builder
  private SummaryCard() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(24)
            .fontColor([this.themePrimary])
        }
        .width(46)
        .height(46)
        .borderRadius(14)
        .backgroundColor(withColorAlpha(this.themePrimary, getAppUiState().isDarkMode ? '24' : '12'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column({ space: 4 }) {
          Text(this.getDisplaySessionTitle())
            .width('100%')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(pickLocalizedText('Python 会话工作区', 'Python session workspace'))
            .width('100%')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row() {
          Text(pickLocalizedText('只读', 'Read only'))
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
        }
        .height(24)
        .padding({ left: 9, right: 9 })
        .borderRadius(12)
        .backgroundColor(withColorAlpha(this.themePrimary, getAppUiState().isDarkMode ? '24' : '12'))
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        this.StatPill(
          `${this.files.length}`,
          pickLocalizedText('文件', this.files.length === 1 ? 'file' : 'files')
        )
        this.StatPill(this.formatFileSize(this.getTotalSize()), pickLocalizedText('总大小', 'total'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(18)
    .backgroundColor(getAppUiState().themeSurface)
    .border({ width: 0.5, color: getAppUiState().themeDivider })
  }

  @Builder
  private StatPill(value: string, label: string) {
    Row({ space: 4 }) {
      Text(value)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
    }
    .height(28)
    .padding({ left: 10, right: 10 })
    .borderRadius(14)
    .backgroundColor(getAppUiState().themeBackground)
  }

  @Builder
  private EmptyState(icon: Resource, title: ResourceStr, description: ResourceStr) {
    Column({ space: 10 }) {
      Column() {
        SymbolGlyph(icon)
          .fontSize(30)
          .fontColor([this.themePrimary])
      }
      .width(64)
      .height(64)
      .borderRadius(20)
      .backgroundColor(withColorAlpha(this.themePrimary, getAppUiState().isDarkMode ? '24' : '12'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)

      Text(description)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 28, right: 28, bottom: 40 })
  }

  @Builder
  private FileRow(file: PythonWorkspaceFileInfo) {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(20)
          .fontColor([this.getFileAccentColor(file.path)])
      }
      .width(40)
      .height(40)
      .borderRadius(12)
      .backgroundColor(withColorAlpha(this.getFileAccentColor(file.path), getAppUiState().isDarkMode ? '24' : '12'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 4 }) {
        Text(this.getFileName(file.path))
          .width('100%')
          .fontFamily('monospace')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 6 }) {
          Text(this.getDirectoryName(file.path))
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(this.formatFileSize(file.size))
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))

          Text(this.formatModifiedAt(file.modifiedAt))
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(14)
    .backgroundColor(getAppUiState().themeSurface)
    .border({ width: 0.5, color: getAppUiState().themeDivider })
    .onClick(() => {
      this.openPreview(file)
    })
  }

  @Builder
  private FileListContent() {
    Column() {
      ImmersiveSheetHeader({
        title: pickLocalizedText('工作区', 'Workspace'),
        trailingSymbol: $r('sys.symbol.arrow_clockwise'),
        showTrailing: true,
        onLeadingClick: (): void => {
          this.onClose()
        },
        onTrailingClick: (): void => {
          this.loadWorkspace()
        }
      })

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
            .width(28)
            .height(28)
            .color(this.themePrimary)
          Text(pickLocalizedText('正在读取工作区...', 'Loading workspace...'))
            .fontSize(13)
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
      } else {
        List({ space: 10 }) {
          ListItem() {
            this.SummaryCard()
          }
          .focusable(false)
          .selectable(false)

          if (this.files.length === 0) {
            ListItem() {
              Column({ space: 10 }) {
                SymbolGlyph($r('sys.symbol.folder'))
                  .fontSize(36)
                  .fontColor([$r('app.color.text_tertiary')])

                Text(pickLocalizedText('工作区暂无文件', 'Workspace is empty'))
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))

                Text(pickLocalizedText(
                  '模型在 Python 工作区创建的文件会显示在这里。',
                  'Files created by the model in the Python workspace will appear here.'
                ))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .height(220)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .padding({ left: 24, right: 24 })
            }
            .focusable(false)
            .selectable(false)
          } else {
            ForEach(this.files, (file: PythonWorkspaceFileInfo) => {
              ListItem() {
                this.FileRow(file)
              }
              .focusable(true)
              .selectable(false)
            }, (file: PythonWorkspaceFileInfo): string => `${file.path}:${file.size}:${file.modifiedAt}`)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 24 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(6)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private PreviewContent() {
    Column() {
      ImmersiveSheetHeader({
        title: this.getFileName(this.previewPath),
        leadingSymbol: $r('sys.symbol.chevron_left'),
        onLeadingClick: (): void => {
          this.closePreview()
        }
      })

      Row({ space: 8 }) {
        Text(this.previewPath)
          .fontFamily('monospace')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Text(pickLocalizedText('只读', 'Read only'))
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
      }
      .width('100%')
      .height(36)
      .padding({ left: 18, right: 18 })
      .backgroundColor(withColorAlpha(this.themePrimary, getAppUiState().isDarkMode ? '16' : '0A'))

      Scroll() {
        Text(this.buildNumberedPreview())
          .width('100%')
          .fontFamily('monospace')
          .fontSize(12)
          .lineHeight(19)
          .fontColor($r('app.color.text_primary'))
          .padding({ left: 16, right: 16, top: 14, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)

      if (this.previewTruncated) {
        Text(pickLocalizedText(
          `只读预览显示第 ${this.previewStartLine}-${this.previewEndLine} 行，共 ${this.previewTotalLines} 行；可由模型继续读取其余内容。`,
          `Read-only preview shows lines ${this.previewStartLine}-${this.previewEndLine} of ${this.previewTotalLines}; the model can read the remaining content.`
        ))
          .width('100%')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .padding({ left: 18, right: 18, top: 10, bottom: 18 })
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      if (this.previewPath !== '') {
        this.PreviewContent()
      } else {
        this.FileListContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }
}
