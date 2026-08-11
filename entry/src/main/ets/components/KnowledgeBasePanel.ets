import { picker } from '@kit.CoreFileKit'
import { uiMaterial } from '@kit.ArkUI'
import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit'
import {
  KnowledgeDocument,
  KnowledgeDocumentService,
  KnowledgeDocumentStatus,
  KnowledgeImportResult,
  KnowledgeTextPreview
} from '../services/KnowledgeDocumentService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { getAppUiState } from '../state/AppUiState'
import { VisualEffectsMode } from '../models/ThemeColors'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import {
  MANUSCRIPT_BODY_FONT,
  MANUSCRIPT_HEADING_FONT,
  toRomanNumeral
} from '../utils/ManuscriptVisualUtils'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'
import { ManuscriptPageTitle } from './index/ManuscriptPageTitle'

@ComponentV2
export struct KnowledgeBasePanel {
  @Param uploadRequestTick: number = 0
  @Param refreshRequestTick: number = 0
  @Param listScroller: ListScroller = new ListScroller()
  @Param topSpacerHeight: number = 0
  @Param bottomSpacerHeight: number = 100
  @Local documents: KnowledgeDocument[] = []
  @Local isLoading: boolean = true
  @Local isWorking: boolean = false
  @Local processingDocumentId: string = ''
  @Local showPreviewSheet: boolean = false
  @Local previewTitle: string = ''
  @Local previewKind: string = ''
  @Local previewPath: string = ''
  @Local previewText: string = ''
  @Local previewTextTruncated: boolean = false
  @Local previewLoading: boolean = false
  @Local previewError: string = ''

  private service: KnowledgeDocumentService = ServiceRegistry.knowledgeDocuments()
  private handledUploadRequestTick: number = 0
  private handledRefreshRequestTick: number = 0
  private previewDocumentId: string = ''
  private pdfPreviewController: pdfViewManager.PdfController = new pdfViewManager.PdfController()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get knowledgeListImmersiveMaterial(): boolean {
    return getAppUiState().knowledgeListImmersiveMaterial
  }

  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  aboutToAppear(): void {
    this.loadKnowledgeBase()
  }

  aboutToDisappear(): void {
    this.closePreviewResources()
  }

  @Monitor('uploadRequestTick')
  onUploadRequestTickMonitor(): void {
    if (this.uploadRequestTick <= 0 || this.uploadRequestTick === this.handledUploadRequestTick) {
      return
    }
    this.handledUploadRequestTick = this.uploadRequestTick
    this.chooseDocuments()
  }

  @Monitor('refreshRequestTick')
  onRefreshRequestTickMonitor(): void {
    if (this.refreshRequestTick <= 0 || this.refreshRequestTick === this.handledRefreshRequestTick) {
      return
    }
    this.handledRefreshRequestTick = this.refreshRequestTick
    this.refreshAllDocuments()
  }

  private loadKnowledgeBase(): void {
    this.performLoadKnowledgeBase().catch((error: Object): void => {
      console.error('KnowledgeBasePanel', `Failed to load knowledge base: ${JSON.stringify(error)}`)
      this.showKnowledgeSnack(
        pickLocalizedText('加载知识库失败', 'Failed to load knowledge base'),
        SnackBarTone.ERROR
      )
      this.isLoading = false
    })
  }

  private async performLoadKnowledgeBase(): Promise<void> {
    this.isLoading = true
    if (!this.service.isReady()) {
      const context = this.getUIContext().getHostContext()
      if (context !== undefined) {
        await this.service.initialize(context)
      }
    }
    this.documents = [...await this.service.listDocuments()]
    this.isLoading = false
  }

  private chooseDocuments(): void {
    if (this.isWorking) {
      return
    }
    this.performChooseDocuments().catch((error: Object): void => {
      console.error('KnowledgeBasePanel', `Document picker failed: ${JSON.stringify(error)}`)
      this.showKnowledgeSnack(
        pickLocalizedText('无法打开文件选择器', 'Could not open the file picker'),
        SnackBarTone.ERROR
      )
      this.isWorking = false
    })
  }

  private async performChooseDocuments(): Promise<void> {
    const context = this.getUIContext().getHostContext()
    if (context === undefined) {
      this.showKnowledgeSnack(
        pickLocalizedText('当前页面上下文不可用', 'The current page context is unavailable'),
        SnackBarTone.ERROR
      )
      return
    }

    const options = new picker.DocumentSelectOptions()
    options.maxSelectNumber = 10
    options.fileSuffixFilters = [
      '.pdf',
      '.txt',
      '.md',
      '.markdown',
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.bmp'
    ]
    const documentPicker = new picker.DocumentViewPicker(context)
    const uris = await documentPicker.select(options)
    if (uris.length === 0) {
      return
    }

    this.isWorking = true
    let succeeded = 0
    let failed = 0
    let vectorReady = 0
    let lastMessage = ''
    let lastVectorMessage = ''
    try {
      for (let i = 0; i < uris.length; i++) {
        const uri = uris[i]
        const result = await this.service.importDocument(uri, this.getFileNameFromUri(uri))
        lastMessage = result.message
        if (result.ok) {
          succeeded += 1
          if (result.vectorReady) {
            vectorReady += 1
          } else if (result.vectorMessage.trim() !== '') {
            lastVectorMessage = result.vectorMessage
          }
        } else {
          failed += 1
        }
        this.documents = [...await this.service.listDocuments()]
      }
    } finally {
      this.isWorking = false
    }

    if (failed === 0 && vectorReady === succeeded) {
      this.showKnowledgeSnack(
        pickLocalizedText(
          `已处理 ${succeeded} 个知识文件，关键词索引与语义向量均已就绪`,
          `Processed ${succeeded} knowledge file(s); keyword indexes and semantic vectors are ready`
        ),
        SnackBarTone.SUCCESS
      )
      return
    }
    if (failed === 0) {
      const vectorDetail = lastVectorMessage.trim() === ''
        ? pickLocalizedText('未完成的文件继续使用关键词检索',
          'Files without vectors continue to use keyword retrieval')
        : lastVectorMessage
      this.showKnowledgeSnack(
        pickLocalizedText(
          `已处理 ${succeeded} 个知识文件；语义向量 ${vectorReady}/${succeeded}，${vectorDetail}`,
          `Processed ${succeeded} knowledge file(s); semantic vectors ${vectorReady}/${succeeded}, ` +
            `${vectorDetail}`
        ),
        SnackBarTone.DEFAULT
      )
      return
    }
    this.showKnowledgeSnack(
      pickLocalizedText(
        `成功 ${succeeded} 个，失败 ${failed} 个，语义向量 ${vectorReady}/${succeeded}：${lastMessage}`,
        `${succeeded} succeeded, ${failed} failed; semantic vectors ` +
          `${vectorReady}/${succeeded}: ${lastMessage}`
      ),
      SnackBarTone.ERROR
    )
  }

  private rebuildDocument(document: KnowledgeDocument): void {
    if (this.isWorking) {
      return
    }
    this.performRebuildDocument(document).catch((error: Object): void => {
      console.error('KnowledgeBasePanel', `Rebuild failed: ${JSON.stringify(error)}`)
      this.showKnowledgeSnack(
        pickLocalizedText('重建知识索引失败', 'Failed to rebuild the knowledge index'),
        SnackBarTone.ERROR
      )
      this.processingDocumentId = ''
      this.isWorking = false
    })
  }

  private async performRebuildDocument(document: KnowledgeDocument): Promise<void> {
    this.isWorking = true
    this.processingDocumentId = document.id
    const result: KnowledgeImportResult = await this.service.rebuildDocument(document.id)
    this.documents = [...await this.service.listDocuments()]
    this.processingDocumentId = ''
    this.isWorking = false
    this.showKnowledgeSnack(
      result.message,
      result.ok ? SnackBarTone.SUCCESS : SnackBarTone.ERROR
    )
  }

  private refreshAllDocuments(): void {
    if (this.isWorking) {
      this.showKnowledgeSnack(
        pickLocalizedText('知识库正在处理，请稍后再试', 'The knowledge base is busy. Try again shortly.')
      )
      return
    }
    if (this.documents.length === 0) {
      this.showKnowledgeSnack(
        pickLocalizedText('暂无知识文件可更新', 'There are no knowledge files to update.')
      )
      return
    }
    this.performRefreshAllDocuments().catch((error: Object): void => {
      console.error('KnowledgeBasePanel', `Refresh all documents failed: ${JSON.stringify(error)}`)
      this.processingDocumentId = ''
      this.isWorking = false
      this.showKnowledgeSnack(
        pickLocalizedText('更新知识库失败', 'Failed to update the knowledge base'),
        SnackBarTone.ERROR
      )
    })
  }

  private async performRefreshAllDocuments(): Promise<void> {
    this.closeAllSwipeActions()
    this.isWorking = true
    const pendingDocuments = this.documents.slice()
    let succeeded = 0
    let failed = 0
    let vectorReady = 0
    let lastMessage = ''
    let lastVectorMessage = ''
    try {
      for (let index = 0; index < pendingDocuments.length; index++) {
        const document = pendingDocuments[index]
        this.processingDocumentId = document.id
        try {
          const result = await this.service.rebuildDocument(document.id)
          lastMessage = result.message
          if (result.ok) {
            succeeded += 1
            if (result.vectorReady) {
              vectorReady += 1
            } else if (result.vectorMessage.trim() !== '') {
              lastVectorMessage = result.vectorMessage
            }
          } else {
            failed += 1
          }
        } catch (error) {
          failed += 1
          lastMessage = error instanceof Error && error.message.trim() !== ''
            ? error.message
            : pickLocalizedText('更新知识文件失败', 'Failed to update a knowledge file')
          console.error(
            'KnowledgeBasePanel',
            `Failed to refresh document ${document.id}: ${JSON.stringify(error)}`
          )
        }
        this.documents = [...await this.service.listDocuments()]
      }
    } finally {
      this.processingDocumentId = ''
      this.isWorking = false
    }

    if (failed === 0 && vectorReady === succeeded) {
      this.showKnowledgeSnack(
        pickLocalizedText(
          `已更新 ${succeeded} 个知识文件，关键词索引与语义向量均已就绪`,
          `Updated ${succeeded} knowledge file(s); keyword indexes and semantic vectors are ready`
        ),
        SnackBarTone.SUCCESS
      )
      return
    }
    if (failed === 0) {
      const vectorDetail = lastVectorMessage.trim() === ''
        ? pickLocalizedText('未完成的文件继续使用关键词检索',
          'Files without vectors continue to use keyword retrieval')
        : lastVectorMessage
      this.showKnowledgeSnack(
        pickLocalizedText(
          `已更新 ${succeeded} 个知识文件；语义向量 ${vectorReady}/${succeeded}，${vectorDetail}`,
          `Updated ${succeeded} knowledge file(s); semantic vectors ${vectorReady}/${succeeded}, ` +
            `${vectorDetail}`
        ),
        SnackBarTone.DEFAULT
      )
      return
    }
    this.showKnowledgeSnack(
      pickLocalizedText(
        `知识索引成功 ${succeeded} 个、失败 ${failed} 个，语义向量 ${vectorReady}/${succeeded}：${lastMessage}`,
        `Knowledge indexes: ${succeeded} succeeded, ${failed} failed; semantic vectors ` +
          `${vectorReady}/${succeeded}: ${lastMessage}`
      ),
      succeeded > 0 ? SnackBarTone.DEFAULT : SnackBarTone.ERROR
    )
  }

  private requestDeleteDocument(document: KnowledgeDocument): void {
    if (this.isWorking) {
      return
    }
    this.getUIContext().showAlertDialog({
      title: pickLocalizedText('删除知识文件', 'Delete knowledge file'),
      message: pickLocalizedText(
        `将删除“${document.originalName}”及其本地索引。`,
        `This removes “${document.originalName}” and its local index.`
      ),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: Color.Red,
        action: () => {
          this.deleteDocument(document)
        }
      }
    })
  }

  private deleteDocument(document: KnowledgeDocument): void {
    this.performDeleteDocument(document).catch((error: Object): void => {
      console.error('KnowledgeBasePanel', `Delete failed: ${JSON.stringify(error)}`)
      this.showKnowledgeSnack(
        pickLocalizedText('删除知识文件失败', 'Failed to delete the knowledge file'),
        SnackBarTone.ERROR
      )
      this.processingDocumentId = ''
      this.isWorking = false
    })
  }

  private async performDeleteDocument(document: KnowledgeDocument): Promise<void> {
    this.isWorking = true
    this.processingDocumentId = document.id
    const deleted = await this.service.deleteDocument(document.id)
    this.documents = [...await this.service.listDocuments()]
    this.processingDocumentId = ''
    this.isWorking = false
    this.showKnowledgeSnack(
      deleted
        ? pickLocalizedText('知识文件已删除', 'Knowledge file deleted')
        : pickLocalizedText('删除知识文件失败', 'Failed to delete the knowledge file'),
      deleted ? SnackBarTone.SUCCESS : SnackBarTone.ERROR
    )
  }

  private openDocumentPreview(document: KnowledgeDocument): void {
    this.closePreviewResources()
    this.previewDocumentId = document.id
    this.previewTitle = document.originalName
    this.previewPath = document.filePath
    this.previewText = ''
    this.previewTextTruncated = false
    this.previewError = ''
    this.previewLoading = false

    if (this.isImageDocument(document)) {
      this.previewKind = 'image'
      this.showPreviewSheet = true
      return
    }
    if (this.isPdfDocument(document)) {
      this.previewKind = 'pdf'
      this.previewLoading = true
      this.showPreviewSheet = true
      this.loadPdfPreview(document).catch((error: Object): void => {
        console.error('KnowledgeBasePanel', `PDF preview failed: ${JSON.stringify(error)}`)
        if (this.previewDocumentId === document.id) {
          this.previewError = pickLocalizedText('PDF 预览失败', 'Failed to preview PDF')
          this.previewLoading = false
        }
      })
      return
    }

    this.previewKind = 'text'
    this.previewLoading = true
    this.showPreviewSheet = true
    this.loadTextPreview(document).catch((error: Object): void => {
      console.error('KnowledgeBasePanel', `Text preview failed: ${JSON.stringify(error)}`)
      if (this.previewDocumentId === document.id) {
        this.previewError = pickLocalizedText('文本预览失败', 'Failed to preview text')
        this.previewLoading = false
      }
    })
  }

  private async loadPdfPreview(document: KnowledgeDocument): Promise<void> {
    const result = await this.pdfPreviewController.loadDocument(document.filePath)
    if (this.previewDocumentId !== document.id) {
      return
    }
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
      this.previewError = pickLocalizedText(`PDF 加载失败 (${result})`, `Failed to load PDF (${result})`)
    }
    this.previewLoading = false
  }

  private async loadTextPreview(document: KnowledgeDocument): Promise<void> {
    const result: KnowledgeTextPreview = await this.service.loadTextPreview(document.id)
    if (this.previewDocumentId !== document.id) {
      return
    }
    this.previewText = result.text
    this.previewTextTruncated = result.truncated
    this.previewLoading = false
  }

  private closeDocumentPreview(): void {
    this.closePreviewResources()
    this.showPreviewSheet = false
    this.previewDocumentId = ''
    this.previewTitle = ''
    this.previewKind = ''
    this.previewPath = ''
    this.previewText = ''
    this.previewTextTruncated = false
    this.previewLoading = false
    this.previewError = ''
  }

  private closePreviewResources(): void {
    try {
      this.pdfPreviewController.releaseDocument()
    } catch (_error) {
    }
  }

  private isPdfDocument(document: KnowledgeDocument): boolean {
    return document.originalName.toLowerCase().endsWith('.pdf') ||
      document.mimeType.toLowerCase() === 'application/pdf'
  }

  private isImageDocument(document: KnowledgeDocument): boolean {
    return document.mimeType.toLowerCase().startsWith('image/')
  }

  private getImagePreviewSource(): string {
    if (this.previewPath.startsWith('file://')) {
      return this.previewPath
    }
    return `file://${this.previewPath}`
  }

  private getFileNameFromUri(uri: string): string {
    const parts = uri.split('/')
    const encodedName = parts[parts.length - 1] || 'knowledge-file'
    try {
      return decodeURIComponent(encodedName)
    } catch (_error) {
      return encodedName
    }
  }

  private getStatusText(document: KnowledgeDocument): string {
    if (document.status === KnowledgeDocumentStatus.READY) {
      return pickLocalizedText(`${document.chunkCount} 个片段`, `${document.chunkCount} chunks`)
    }
    if (document.status === KnowledgeDocumentStatus.INDEXING) {
      return pickLocalizedText('正在建立索引', 'Indexing')
    }
    if (document.status === KnowledgeDocumentStatus.DELETING) {
      return pickLocalizedText('正在删除', 'Deleting')
    }
    return document.errorMessage !== ''
      ? document.errorMessage
      : pickLocalizedText('索引失败', 'Index failed')
  }

  private getStatusColor(document: KnowledgeDocument): string {
    if (document.status === KnowledgeDocumentStatus.READY) {
      return '#2E8B57'
    }
    if (document.status === KnowledgeDocumentStatus.FAILED) {
      return '#D9485F'
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

  private getDocumentSymbol(document: KnowledgeDocument): Resource {
    if (this.isPdfDocument(document)) {
      return $r('sys.symbol.pdf_doc')
    }
    if (this.isImageDocument(document)) {
      return $r('sys.symbol.picture')
    }
    return $r('sys.symbol.doc_text')
  }

  private showKnowledgeSnack(
    message: string | Resource,
    tone: SnackBarTone = SnackBarTone.DEFAULT
  ): void {
    const options = new SnackBarDisplayOptions()
    options.message = message
    options.duration = tone === SnackBarTone.ERROR ? 3000 : 2200
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  private getSwipeButtonHeight(): number {
    return 56
  }

  private closeAllSwipeActions(): void {
    try {
      this.listScroller.closeAllSwipeActions()
    } catch (_error) {
    }
  }

  @Builder
  private UpdateSwipeContent() {
    Column() {
      SymbolGlyph($r('sys.symbol.doc_text_badge_leaf'))
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontSize(18)
        .fontColor([this.themePrimary])

      Text(pickLocalizedText('更新', 'Update'))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.themePrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .margin({ top: 2 })
    }
    .width('100%')
    .height(this.getSwipeButtonHeight())
    .padding({ left: 4, right: 4 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private UpdateSwipePanel(document: KnowledgeDocument) {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        this.UpdateSwipeContent()
      }
      .width(this.getSwipeButtonHeight())
      .height(this.getSwipeButtonHeight())
      .backgroundColor(Color.Transparent)
      .padding(0)
      .enabled(!this.isWorking)
      .onClick(() => {
        this.closeAllSwipeActions()
        this.rebuildDocument(document)
      })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true,
        lightEffect: { color: undefined }
      }))
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .clip(false)
  }

  @Builder
  private DeleteSwipeContent() {
    Column() {
      SymbolGlyph($r('sys.symbol.trash'))
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontSize(18)
        .fontColor([$r('app.color.status_error')])

      Text($r('app.string.delete'))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.status_error'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .margin({ top: 2 })
    }
    .width('100%')
    .height(this.getSwipeButtonHeight())
    .padding({ left: 4, right: 4 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private DeleteSwipePanel(document: KnowledgeDocument) {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        this.DeleteSwipeContent()
      }
      .width(this.getSwipeButtonHeight())
      .height(this.getSwipeButtonHeight())
      .backgroundColor(Color.Transparent)
      .padding(0)
      .enabled(!this.isWorking)
      .onClick(() => {
        this.closeAllSwipeActions()
        this.requestDeleteDocument(document)
      })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true,
        lightEffect: { color: undefined }
      }))
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .clip(false)
  }

  @Builder
  private DocumentCardContent(document: KnowledgeDocument) {
    Column() {
      SymbolGlyph(this.getDocumentSymbol(document))
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontSize(18)
        .fontColor([this.themePrimary])
    }
    .width(38)
    .height(38)
    .borderRadius(12)
    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '24' : '12'))
    .justifyContent(FlexAlign.Center)

    Column({ space: 4 }) {
      Text(document.originalName)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: 6 }) {
        Text(this.formatFileSize(document.size))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))

        Text('·')
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))

        Text(this.getStatusText(document))
          .fontSize(10)
          .fontColor(this.getStatusColor(document))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)

    if (this.processingDocumentId === document.id) {
      LoadingProgress()
        .width(20)
        .height(20)
        .color(this.themePrimary)
    } else {
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontSize(14)
        .fontColor([$r('app.color.text_tertiary')])
    }
  }

  private handleDocumentTap(document: KnowledgeDocument): void {
    this.closeAllSwipeActions()
    this.openDocumentPreview(document)
  }

  @Builder
  private ImmersiveDocumentCard(document: KnowledgeDocument) {
    Row({ space: 10 }) {
      this.DocumentCardContent(document)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(12)
    .border({ width: 0.5, color: getAppUiState().themeDivider })
    .onClick(() => {
      this.handleDocumentTap(document)
    })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      interactive: false,
      lightEffect: { color: undefined }
    }))
  }

  @Builder
  private GaussianBlurDocumentCard(document: KnowledgeDocument) {
    Row({ space: 10 }) {
      this.DocumentCardContent(document)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(12)
    .clip(true)
    .border({ width: 0.5, color: getAppUiState().themeDivider })
    .backgroundColor(Color.Transparent)
    .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
    .onClick(() => {
      this.handleDocumentTap(document)
    })
  }

  @Builder
  private DocumentCard(document: KnowledgeDocument) {
    if (this.isManuscriptMode) {
      this.ManuscriptDocumentRow(document)
    } else if (this.knowledgeListImmersiveMaterial) {
      this.ImmersiveDocumentCard(document)
    } else {
      this.GaussianBlurDocumentCard(document)
    }
  }

  private getDocumentOrdinal(document: KnowledgeDocument): number {
    for (let index = 0; index < this.documents.length; index++) {
      if (this.documents[index].id === document.id) {
        return index + 1
      }
    }
    return 1
  }

  @Builder
  private ManuscriptDocumentRow(document: KnowledgeDocument) {
    Column({ space: 5 }) {
      Row({ space: 8 }) {
        Text(toRomanNumeral(this.getDocumentOrdinal(document)))
          .width(26)
          .fontFamily(MANUSCRIPT_HEADING_FONT)
          .fontSize(15)
          .fontWeight(600)
          .fontColor(this.isDarkMode ? '#D9B274' : '#8A6228')
          .fontFeature('tnum')

        Text(document.originalName)
          .fontFamily(MANUSCRIPT_HEADING_FONT)
          .fontSize(18)
          .fontWeight(600)
          .fontColor(getAppUiState().themeTextPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '56%' })

        Column()
          .height(1)
          .border({
            width: { top: 1 },
            color: this.isDarkMode ? '#4A463F' : '#C9C4BB',
            style: BorderStyle.Dotted
          })
          .layoutWeight(1)
          .constraintSize({ minWidth: 18 })

        if (this.processingDocumentId === document.id) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(this.themePrimary)
        } else {
          Text(this.formatFileSize(document.size))
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontSize(11.5)
            .fontColor(getAppUiState().themeTextTertiary)
            .fontFeature('tnum')
            .maxLines(1)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 7 }) {
        SymbolGlyph(this.getDocumentSymbol(document))
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .fontSize(12)
          .fontColor([this.getStatusColor(document)])

        Text(this.getStatusText(document))
          .fontFamily(MANUSCRIPT_BODY_FONT)
          .fontSize(12.5)
          .fontStyle(FontStyle.Italic)
          .fontColor(getAppUiState().themeTextSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 34 })
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 14, bottom: 12 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: getAppUiState().themeDivider })
    .onClick(() => {
      this.handleDocumentTap(document)
    })
  }

  @Builder
  private PreviewSheetContent() {
    Column() {
      ImmersiveSheetHeader({
        title: this.previewTitle !== '' ? this.previewTitle : pickLocalizedText('文件预览', 'File preview'),
        onLeadingClick: (): void => {
          this.showPreviewSheet = false
        }
      })

      if (this.previewError !== '') {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
            .fontSize(28)
            .fontColor([$r('app.color.status_error')])

          Text(this.previewError)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding(24)
      } else if (this.previewLoading) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.themePrimary)

          Text(pickLocalizedText('正在加载预览...', 'Loading preview...'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.previewKind === 'image' && this.previewPath !== '') {
        Stack() {
          Image(this.getImagePreviewSource())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .draggable(false)
            .onError(() => {
              this.previewError = pickLocalizedText('图片预览失败', 'Failed to preview image')
            })
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(Color.Black)
      } else if (this.previewKind === 'pdf' && this.previewPath !== '') {
        PdfView({
          controller: this.pdfPreviewController,
          pageLayout: pdfService.PageLayout.LAYOUT_SINGLE,
          isContinuous: true,
          showScroll: true,
          pageFit: pdfService.PageFit.FIT_WIDTH
        })
          .width('100%')
          .layoutWeight(1)
      } else if (this.previewKind === 'text') {
        Scroll() {
          Column({ space: 12 }) {
            Text(this.previewText)
              .width('100%')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .lineHeight(22)

            if (this.previewTextTruncated) {
              Text(pickLocalizedText(
                '预览已达到 200 万字符上限，索引同样只使用此前内容。',
                'Preview reached the 2,000,000-character limit; the index uses the same prefix.'
              ))
                .width('100%')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .padding({ top: 8, bottom: 16 })
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 28 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  build() {
    Stack() {
      List({ space: 0, scroller: this.listScroller }) {
        if (this.topSpacerHeight > 0) {
          ListItem() {
            Column()
              .height(this.topSpacerHeight)
          }
          .focusable(false)
          .selectable(false)
        }

        if (this.isManuscriptMode) {
          ListItem() {
            ManuscriptPageTitle({
              title: $r('app.string.tab_knowledge'),
              subtitle: pickLocalizedText('参考书目', 'REFERENCE LIBRARY')
            })
          }
          .focusable(false)
          .selectable(false)
        }

        if (this.isLoading) {
          ListItem() {
            Row() {
              LoadingProgress()
                .width(28)
                .height(28)
                .color(this.themePrimary)
            }
            .width('100%')
            .height(this.isManuscriptMode ? 160 : 220)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
          }
          .focusable(false)
          .selectable(false)
        } else if (this.documents.length === 0) {
          ListItem() {
            Column({ space: 10 }) {
              if (this.isManuscriptMode) {
                Text('❦')
                  .fontFamily(MANUSCRIPT_HEADING_FONT)
                  .fontSize(22)
                  .fontColor(this.isDarkMode ? '#C99A52' : '#B68235')
              } else {
                Column() {
                  SymbolGlyph($r('sys.symbol.doc_text_badge_magnifyingglass'))
                    .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                    .fontSize(28)
                    .fontColor([this.themePrimary])
                }
                .width(64)
                .height(64)
                .borderRadius(20)
                .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '26' : '12'))
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }

              Text($r('app.string.knowledge_empty_title'))
                .fontFamily(this.isManuscriptMode ? MANUSCRIPT_HEADING_FONT : undefined)
                .fontSize(this.isManuscriptMode ? 19 : 16)
                .fontWeight(this.isManuscriptMode ? 600 : FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))

              Text($r('app.string.knowledge_empty_hint'))
                .fontFamily(this.isManuscriptMode ? MANUSCRIPT_BODY_FONT : undefined)
                .fontSize(this.isManuscriptMode ? 12.5 : 12)
                .fontStyle(this.isManuscriptMode ? FontStyle.Italic : FontStyle.Normal)
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .height(this.isManuscriptMode ? 190 : 260)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .padding({ left: 16, right: 16 })
          }
          .focusable(false)
          .selectable(false)
        } else {
          ForEach(this.documents, (document: KnowledgeDocument, index: number) => {
            ListItem({ style: ListItemStyle.NONE }) {
              this.DocumentCard(document)
            }
            .margin({
              left: this.isManuscriptMode ? 32 : 16,
              right: this.isManuscriptMode ? 32 : 16,
              top: this.isManuscriptMode ? 0 : (index === 0 ? 4 : 0),
              bottom: this.isManuscriptMode ? 0 : 8
            })
            .swipeAction({
              start: this.UpdateSwipePanel(document),
              end: this.DeleteSwipePanel(document)
            })
            .borderRadius(this.isManuscriptMode ? 0 : 12)
            .clip(false)
          }, (document: KnowledgeDocument) => document.id)
        }

        if (this.isManuscriptMode && !this.isLoading && this.documents.length > 0) {
          ListItem() {
            Text('❦')
              .fontFamily(MANUSCRIPT_HEADING_FONT)
              .fontSize(18)
              .fontColor(this.isDarkMode ? '#C99A52' : '#B68235')
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 18, bottom: 12 })
          }
          .focusable(false)
          .selectable(false)
        }

        if (this.bottomSpacerHeight > 0) {
          ListItem() {
            Column()
              .height(this.bottomSpacerHeight)
          }
          .focusable(false)
          .selectable(false)
        }
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(4)

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showPreviewSheet, this.PreviewSheetContent(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          dragBar: true,
          showClose: false,
          onDisappear: () => {
            this.closeDocumentPreview()
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }
}
