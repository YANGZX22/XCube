import { ImmersiveButtonSurface } from './ImmersiveButtonSurface'
import { FileIcon } from './FileIcon'
import { ImmersiveListSurface, LIST_MATERIAL_CARD_RADIUS } from './ImmersiveListSurface'
import { getBlurBottomShadow } from '../utils/BlurShadowUtils'
import { picker } from '@kit.CoreFileKit'
import { curves, uiMaterial } from '@kit.ArkUI'
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
import { EmailKnowledgeCategory } from './EmailKnowledgeCategory'
import { ManuscriptPageTitle } from './index/ManuscriptPageTitle'

const KNOWLEDGE_CATEGORY_COLLAPSED_VISIBLE_COUNT: number = 1
const KNOWLEDGE_CATEGORY_STACK_LIMIT: number = 3
const KNOWLEDGE_CATEGORY_STACK_STEP: number = 14
const KNOWLEDGE_DOCUMENT_CARD_HEIGHT: number = 58
const KNOWLEDGE_DOCUMENT_CARD_GAP: number = 8

interface KnowledgeCardMeasurement {
  documentId: string
  height: number
}

const KNOWLEDGE_CATEGORY_PDF: string = 'pdf'
const KNOWLEDGE_CATEGORY_WORD: string = 'word'
const KNOWLEDGE_CATEGORY_SPREADSHEET: string = 'spreadsheet'
const KNOWLEDGE_CATEGORY_TEXT: string = 'text'
const KNOWLEDGE_CATEGORY_IMAGE: string = 'image'
const KNOWLEDGE_CATEGORY_EMAIL: string = 'email'
const KNOWLEDGE_CATEGORY_OTHER: string = 'other'
const KNOWLEDGE_CATEGORY_KEYS: string[] = [
  KNOWLEDGE_CATEGORY_PDF,
  KNOWLEDGE_CATEGORY_WORD,
  KNOWLEDGE_CATEGORY_SPREADSHEET,
  KNOWLEDGE_CATEGORY_TEXT,
  KNOWLEDGE_CATEGORY_IMAGE,
  KNOWLEDGE_CATEGORY_OTHER
]

@ComponentV2
export struct KnowledgeBasePanel {
  @Param uploadRequestTick: number = 0
  @Param refreshRequestTick: number = 0
  @Param listScroller: ListScroller = new ListScroller()
  @Param topSpacerHeight: number = 0
  @Param bottomSpacerHeight: number = 100
  @Param splitPreviewMode: boolean = false
  @Param splitListPaneWidth: number = 340
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
  @Local expandedCategoryKeys: string[] = []
  @Local cardMeasurements: KnowledgeCardMeasurement[] = []

  private service: KnowledgeDocumentService = ServiceRegistry.knowledgeDocuments()
  private handledUploadRequestTick: number = 0
  private handledRefreshRequestTick: number = 0
  private previewDocumentId: string = ''
  private deckScrollers: Map<string, ListScroller> = new Map<string, ListScroller>()
  private pdfPreviewController: pdfViewManager.PdfController = new pdfViewManager.PdfController()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  private get listHorizontalPadding(): number {
    return this.isManuscriptMode ? 32 : 16
  }

  private get knowledgeListImmersiveMaterial(): boolean {
    return !this.isManuscriptMode && getAppUiState().knowledgeListImmersiveMaterial
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
      '.docx',
      '.xlsx',
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
    this.getUIContext().showAlertDialog({
      title: pickLocalizedText('确认更新知识库', 'Update knowledge base?'),
      backgroundColor: Color.Transparent,
      backgroundBlurStyle: BlurStyle.NONE,
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THICK
      }),
      message: pickLocalizedText(
        `将重新处理全部 ${this.documents.length} 个知识文件，并重建关键词索引与语义向量。是否继续？`,
        `This will process all ${this.documents.length} knowledge file(s) again and rebuild their ` +
          'keyword indexes and semantic vectors. Continue?'
      ),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: pickLocalizedText('确认更新', 'Update'),
        action: () => {
          this.startRefreshAllDocuments()
        }
      }
    })
  }

  private startRefreshAllDocuments(): void {
    if (this.isWorking) {
      this.showKnowledgeSnack(
        pickLocalizedText('知识库正在处理，请稍后再试', 'The knowledge base is busy. Try again shortly.')
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
    if (this.previewDocumentId === document.id) {
      this.closeDocumentPreview()
    }
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

  private isDocxDocument(document: KnowledgeDocument): boolean {
    return document.originalName.toLowerCase().endsWith('.docx') ||
      document.mimeType.toLowerCase() ===
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  }

  private isXlsxDocument(document: KnowledgeDocument): boolean {
    return document.originalName.toLowerCase().endsWith('.xlsx') ||
      document.mimeType.toLowerCase() ===
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  }

  private getDocumentCategoryKey(document: KnowledgeDocument): string {
    const name = document.originalName.toLowerCase()
    const mimeType = document.mimeType.toLowerCase()
    if (document.originalName.startsWith('邮件-')) {
      return KNOWLEDGE_CATEGORY_EMAIL
    }
    if (this.isPdfDocument(document)) {
      return KNOWLEDGE_CATEGORY_PDF
    }
    if (this.isDocxDocument(document) || name.endsWith('.doc') || mimeType === 'application/msword') {
      return KNOWLEDGE_CATEGORY_WORD
    }
    if (this.isXlsxDocument(document) || name.endsWith('.xls') || name.endsWith('.csv') ||
      mimeType === 'application/vnd.ms-excel' || mimeType === 'text/csv') {
      return KNOWLEDGE_CATEGORY_SPREADSHEET
    }
    if (this.isImageDocument(document)) {
      return KNOWLEDGE_CATEGORY_IMAGE
    }
    if (name.endsWith('.txt') || name.endsWith('.md') || name.endsWith('.markdown') ||
      mimeType.startsWith('text/') || mimeType === 'application/json' ||
      mimeType === 'application/xml' || mimeType === 'application/x-yaml') {
      return KNOWLEDGE_CATEGORY_TEXT
    }
    return KNOWLEDGE_CATEGORY_OTHER
  }

  private getDocumentsForCategory(categoryKey: string): KnowledgeDocument[] {
    const categoryDocuments = this.documents.filter((document: KnowledgeDocument): boolean => {
      return this.getDocumentCategoryKey(document) === categoryKey
    })
    categoryDocuments.sort((left: KnowledgeDocument, right: KnowledgeDocument): number => {
      if (left.createdAt !== right.createdAt) {
        return right.createdAt - left.createdAt
      }
      return right.updatedAt - left.updatedAt
    })
    return categoryDocuments
  }

  private getVisibleCategoryKeys(): string[] {
    return KNOWLEDGE_CATEGORY_KEYS.filter((categoryKey: string): boolean => {
      return this.getDocumentsForCategory(categoryKey).length > 0
    })
  }

  private isCategoryExpanded(categoryKey: string): boolean {
    return this.expandedCategoryKeys.includes(categoryKey)
  }

  private getVisibleCategoryDocuments(categoryKey: string): KnowledgeDocument[] {
    const categoryDocuments = this.getDocumentsForCategory(categoryKey)
    if (this.isCategoryExpanded(categoryKey) ||
      categoryDocuments.length <= KNOWLEDGE_CATEGORY_COLLAPSED_VISIBLE_COUNT) {
      return categoryDocuments
    }
    return categoryDocuments.slice(0, KNOWLEDGE_CATEGORY_COLLAPSED_VISIBLE_COUNT)
  }

  private isDocumentStacked(document: KnowledgeDocument): boolean {
    return !this.isManuscriptMode &&
      !this.isCategoryExpanded(this.getDocumentCategoryKey(document)) &&
      this.getDocumentsForCategory(this.getDocumentCategoryKey(document)).length > 1
  }

  private getDocumentCardHeight(document: KnowledgeDocument): number {
    const measurement = this.cardMeasurements.find((item: KnowledgeCardMeasurement): boolean => {
      return item.documentId === document.id
    })
    return measurement?.height ?? KNOWLEDGE_DOCUMENT_CARD_HEIGHT
  }

  private measureDocumentCard(document: KnowledgeDocument, size: SizeOptions): void {
    const height = Number(size.height)
    if (!Number.isFinite(height) || height <= 0 ||
      Math.abs(height - this.getDocumentCardHeight(document)) < 0.5) {
      return
    }
    this.cardMeasurements = this.cardMeasurements.filter((item: KnowledgeCardMeasurement): boolean => {
      return item.documentId !== document.id
    }).concat([{ documentId: document.id, height: height }])
  }

  private getDeckCardOffset(categoryKey: string, index: number): number {
    if (!this.isCategoryExpanded(categoryKey)) {
      return Math.min(index, KNOWLEDGE_CATEGORY_STACK_LIMIT) * KNOWLEDGE_CATEGORY_STACK_STEP
    }
    const documents = this.getDocumentsForCategory(categoryKey)
    let offset = 0
    for (let i = 0; i < index; i++) {
      offset += this.getDocumentCardHeight(documents[i]) + KNOWLEDGE_DOCUMENT_CARD_GAP
    }
    return offset
  }

  private getDeckHeight(categoryKey: string): number {
    const documents = this.getDocumentsForCategory(categoryKey)
    const expanded = this.isCategoryExpanded(categoryKey)
    let height = 0
    for (let index = 0; index < documents.length; index++) {
      if (expanded) {
        height += this.getDocumentCardHeight(documents[index]) + KNOWLEDGE_DOCUMENT_CARD_GAP
      } else if (index <= KNOWLEDGE_CATEGORY_STACK_LIMIT) {
        height = Math.max(height, index * KNOWLEDGE_CATEGORY_STACK_STEP +
          this.getDocumentCardHeight(documents[index]) + KNOWLEDGE_DOCUMENT_CARD_GAP)
      } else {
        break
      }
    }
    return height
  }

  private toggleCategoryExpanded(categoryKey: string): void {
    if (this.getDocumentsForCategory(categoryKey).length <= KNOWLEDGE_CATEGORY_COLLAPSED_VISIBLE_COUNT) {
      return
    }
    this.closeAllSwipeActions()
    this.getUIContext().animateTo({ duration: 460, curve: curves.springMotion(0.42, 0.9) }, (): void => {
      if (this.isCategoryExpanded(categoryKey)) {
        this.expandedCategoryKeys = this.expandedCategoryKeys.filter((key: string): boolean => {
          return key !== categoryKey
        })
      } else {
        this.expandedCategoryKeys = this.expandedCategoryKeys.concat([categoryKey])
      }
    })
  }

  private getCategoryTitle(categoryKey: string): string {
    if (categoryKey === KNOWLEDGE_CATEGORY_PDF) {
      return 'PDF'
    }
    if (categoryKey === KNOWLEDGE_CATEGORY_WORD) {
      return 'Word'
    }
    if (categoryKey === KNOWLEDGE_CATEGORY_SPREADSHEET) {
      return pickLocalizedText('表格', 'Spreadsheets')
    }
    if (categoryKey === KNOWLEDGE_CATEGORY_TEXT) {
      return pickLocalizedText('文本文档', 'Texts')
    }
    if (categoryKey === KNOWLEDGE_CATEGORY_IMAGE) {
      return pickLocalizedText('图片', 'Images')
    }
    return pickLocalizedText('其他文档', 'Others')
  }

  private getCategorySummary(categoryKey: string): string {
    const count = this.getDocumentsForCategory(categoryKey).length
    if (count > KNOWLEDGE_CATEGORY_COLLAPSED_VISIBLE_COUNT && this.isManuscriptMode &&
      !this.isCategoryExpanded(categoryKey)) {
      return pickLocalizedText(`${count} 个文档 · 显示最新 1 个`, `${count} documents · Latest 1`)
    }
    return pickLocalizedText(`${count} 个文档`, `${count} document${count === 1 ? '' : 's'}`)
  }

  private getCategoryColor(categoryKey: string): string {
    if (categoryKey === KNOWLEDGE_CATEGORY_PDF) {
      return '#D9485F'
    }
    if (categoryKey === KNOWLEDGE_CATEGORY_WORD) {
      return '#3E6FDB'
    }
    if (categoryKey === KNOWLEDGE_CATEGORY_SPREADSHEET) {
      return '#2E8B57'
    }
    if (categoryKey === KNOWLEDGE_CATEGORY_IMAGE) {
      return '#A15BC5'
    }
    return this.themePrimary
  }

  private getDocumentCategoryColor(document: KnowledgeDocument): string {
    return this.getCategoryColor(this.getDocumentCategoryKey(document))
  }

  private getCategoryCardTint(categoryKey: string): string {
    return withColorAlpha(this.getCategoryColor(categoryKey), this.isDarkMode ? '26' : '16')
  }

  private getCategoryCardBorderColor(categoryKey: string): string {
    return withColorAlpha(this.getCategoryColor(categoryKey), this.isDarkMode ? '40' : '2E')
  }

  @Builder
  private DocumentCategoryIcon(categoryKey: string) {
    if (categoryKey === KNOWLEDGE_CATEGORY_WORD) {
      Image($r('app.media.doc_docx'))
        .width(18)
        .height(18)
        .fillColor(this.getCategoryColor(categoryKey))
    } else if (categoryKey === KNOWLEDGE_CATEGORY_SPREADSHEET) {
      Image($r('app.media.doc_xlsx'))
        .width(18)
        .height(18)
        .fillColor(this.getCategoryColor(categoryKey))
    } else {
      SymbolGlyph(categoryKey === KNOWLEDGE_CATEGORY_PDF
        ? $r('sys.symbol.pdf_doc')
        : categoryKey === KNOWLEDGE_CATEGORY_IMAGE
          ? $r('sys.symbol.picture')
          : $r('sys.symbol.doc_text'))
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontSize(18)
        .fontColor([this.getCategoryColor(categoryKey)])
    }
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

  @Builder
  private DocumentIcon(document: KnowledgeDocument, size: number) {
    FileIcon({
      fileName: document.originalName,
      mimeType: document.mimeType,
      iconSize: size,
      tintColor: this.getDocumentCategoryColor(document)
    })
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

  private getDeckScroller(documentId: string): ListScroller {
    let scroller = this.deckScrollers.get(documentId)
    if (scroller === undefined) {
      scroller = new ListScroller()
      this.deckScrollers.set(documentId, scroller)
    }
    return scroller
  }

  private closeAllSwipeActions(): void {
    try {
      this.listScroller.closeAllSwipeActions()
    } catch (_error) {
    }
    this.deckScrollers.forEach((scroller: ListScroller, documentId: string): void => {
      try {
        scroller.closeAllSwipeActions()
      } catch (_error) {
      }
      if (!this.documents.some((document: KnowledgeDocument): boolean => document.id === documentId)) {
        this.deckScrollers.delete(documentId)
      }
    })
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
      Stack({ alignContent: Alignment.TopStart }) {
        ImmersiveButtonSurface({
          materialFactory: () => (new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR,
            interactive: true,
            lightEffect: { color: undefined }
          })),
          cornerRadius: undefined
        }) {
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
        }
      }
      .width(this.getSwipeButtonHeight())
      .height(this.getSwipeButtonHeight())
      .enabled(!this.isWorking)
      .clip(false)
    }
    .width(this.getSwipeButtonHeight() + this.listHorizontalPadding)
    .height('100%')
    .padding({ left: this.listHorizontalPadding })
    .justifyContent(FlexAlign.Start)
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
      Stack({ alignContent: Alignment.TopStart }) {
        ImmersiveButtonSurface({
          materialFactory: () => (new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR,
            interactive: true,
            lightEffect: { color: undefined }
          })),
          cornerRadius: undefined
        }) {
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
        }
      }
      .width(this.getSwipeButtonHeight())
      .height(this.getSwipeButtonHeight())
      .enabled(!this.isWorking)
      .clip(false)
    }
    .width(this.getSwipeButtonHeight() + this.listHorizontalPadding)
    .height('100%')
    .padding({ right: this.listHorizontalPadding })
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    .clip(false)
  }

  @Builder
  private DocumentCardContent(document: KnowledgeDocument) {
    Column() {
      this.DocumentIcon(document, 18)
    }
    .width(38)
    .height(38)
    .borderRadius(LIST_MATERIAL_CARD_RADIUS)
    .backgroundColor(withColorAlpha(
      this.getDocumentCategoryColor(document),
      this.isDarkMode ? '2E' : '1A'
    ))
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
  private StandardDocumentCard(document: KnowledgeDocument) {
    Row({ space: 10 }) {
      this.DocumentCardContent(document)
    }
    .width('100%')
    .constraintSize({ minHeight: KNOWLEDGE_DOCUMENT_CARD_HEIGHT, maxHeight: 4096 })
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(LIST_MATERIAL_CARD_RADIUS)
    .border({ width: 0.5, color: getAppUiState().themeDivider })
    // 与对话卡片一致：前景始终透明，折叠/展开不切换背景色或材质类型。
    .backgroundColor(Color.Transparent)
    .backdropBlur(this.knowledgeListImmersiveMaterial ? 0 : 24)
    .shadow(getBlurBottomShadow(!this.knowledgeListImmersiveMaterial))
    .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
      this.measureDocumentCard(document, size)
    })
    .onClick(() => {
      this.handleDocumentTap(document)
    })
  }

  @Builder
  private DocumentCard(document: KnowledgeDocument) {
    Column() {
      if (this.isManuscriptMode) {
        this.ManuscriptDocumentRow(document)
      } else {
        // 材质背板与完整卡片一起常驻在堆叠中；使用对话列表的同款 REGULAR 沉浸表面。
        ImmersiveListSurface({ isImmersive: this.knowledgeListImmersiveMaterial }) {
          this.StandardDocumentCard(document)
        }
      }
    }
    .width('100%')
    // 与对话列表一致：留白随卡片侧滑，气泡仍相对完整列表宽度定位。
    .padding({ left: this.listHorizontalPadding, right: this.listHorizontalPadding })
    .clip(false)
  }

  @Builder
  private DocumentCategoryHeaderContent(categoryKey: string) {
    Column() {
      this.DocumentCategoryIcon(categoryKey)
    }
    .width(36)
    .height(36)
    .borderRadius(this.isManuscriptMode ? 0 : LIST_MATERIAL_CARD_RADIUS)
    .backgroundColor(this.isManuscriptMode
      ? Color.Transparent
      : withColorAlpha(this.getCategoryColor(categoryKey), this.isDarkMode ? '26' : '14'))
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)

    Column({ space: 2 }) {
      Text(this.getCategoryTitle(categoryKey))
        .fontFamily(this.isManuscriptMode ? MANUSCRIPT_HEADING_FONT : undefined)
        .fontSize(this.isManuscriptMode ? 18 : 14)
        .fontWeight(this.isManuscriptMode ? 600 : FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.getCategorySummary(categoryKey))
        .fontFamily(this.isManuscriptMode ? MANUSCRIPT_BODY_FONT : undefined)
        .fontSize(this.isManuscriptMode ? 11.5 : 10.5)
        .fontStyle(this.isManuscriptMode ? FontStyle.Italic : FontStyle.Normal)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)

    if (this.getDocumentsForCategory(categoryKey).length > KNOWLEDGE_CATEGORY_COLLAPSED_VISIBLE_COUNT) {
      Row({ space: 4 }) {
        Text(this.isCategoryExpanded(categoryKey)
          ? pickLocalizedText('收起', 'Collapse')
          : pickLocalizedText('展开', 'Expand'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getCategoryColor(categoryKey))

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .fontSize(12)
          .fontColor([this.getCategoryColor(categoryKey)])
          .rotate({ angle: this.isCategoryExpanded(categoryKey) ? 180 : 0 })
          .animation({ duration: 220, curve: Curve.EaseOut })
      }
      .height(32)
      .padding({ left: 10, right: 10 })
      .borderRadius(999)
      .backgroundColor(withColorAlpha(
        this.getCategoryColor(categoryKey),
        this.isDarkMode ? '24' : '10'
      ))
      .stateStyles({
        normal: {
          .opacity(1)
        },
        pressed: {
          .opacity(0.62)
        }
      })
      .onClick((): void => {
        this.toggleCategoryExpanded(categoryKey)
      })
    }
  }

  @Builder
  private DocumentCategoryHeader(categoryKey: string) {
    Column() {
      ImmersiveListSurface({
        isImmersive: this.knowledgeListImmersiveMaterial, cornerRadius: LIST_MATERIAL_CARD_RADIUS
      }) {
        this.DocumentCategoryHeaderRow(categoryKey)
      }
    }
    .width('100%')
    .padding({ left: this.listHorizontalPadding, right: this.listHorizontalPadding })
    .clip(false)
    .margin({ bottom: this.isManuscriptMode ? 0 : 8 })
  }

  @Builder
  private DocumentCategoryHeaderRow(categoryKey: string) {
    Row({ space: 10 }) {
      this.DocumentCategoryHeaderContent(categoryKey)
    }
    .width('100%')
    .height(this.isManuscriptMode ? 64 : 60)
    .padding({ left: this.isManuscriptMode ? 4 : 12, right: this.isManuscriptMode ? 4 : 10 })
    .borderRadius(this.isManuscriptMode ? 0 : LIST_MATERIAL_CARD_RADIUS)
    .backgroundColor(Color.Transparent)
    .border({
      width: this.isManuscriptMode ? { bottom: 1 } : 0.5,
      color: this.isManuscriptMode
        ? getAppUiState().themeDivider
        : this.getCategoryCardBorderColor(categoryKey)
    })
    .backdropBlur(this.isManuscriptMode || this.knowledgeListImmersiveMaterial ? 0 : 24)
    .shadow(getBlurBottomShadow(!this.isManuscriptMode && !this.knowledgeListImmersiveMaterial))
  }

  @Builder
  private DeckDocumentCard(categoryKey: string, document: KnowledgeDocument, index: number, count: number) {
    // 每张卡片保留完整高度的原生侧滑行；层叠由外面的同一个 Stack 统一绘制。
    // 内层列表只承载水平侧滑，纵向滚动交给知识库的外层列表。
    Column() {
      List({ scroller: this.getDeckScroller(document.id) }) {
        ListItem({ style: ListItemStyle.NONE }) {
          this.DocumentCard(document)
        }
        .swipeAction({
          start: this.UpdateSwipePanel(document),
          end: this.DeleteSwipePanel(document)
        })
        .borderRadius(LIST_MATERIAL_CARD_RADIUS)
        .clip(false)
      }
      .width('100%')
      .height(this.getDocumentCardHeight(document))
      .backgroundColor(Color.Transparent)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .enableScrollInteraction(false)
      .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.PARENT_FIRST })
      .clip(false)
      .hitTestBehavior(this.isDocumentStacked(document) && index > 0
        ? HitTestMode.BLOCK_DESCENDANTS : HitTestMode.Default)
    }
    .width('100%')
    .height(this.getDocumentCardHeight(document))
    .position({ x: 0, y: 0 })
    .translate({ y: this.getDeckCardOffset(categoryKey, index) })
    .scale({
      x: this.isDocumentStacked(document) ? 1 - Math.min(index, KNOWLEDGE_CATEGORY_STACK_LIMIT) * 0.04 : 1,
      y: 1,
      centerX: '50%',
      centerY: '0%'
    })
    .zIndex(count - index)
    .opacity(this.isDocumentStacked(document) && index > KNOWLEDGE_CATEGORY_STACK_LIMIT ? 0 : 1)
    .hitTestBehavior(this.isDocumentStacked(document) && index > KNOWLEDGE_CATEGORY_STACK_LIMIT
      ? HitTestMode.BLOCK_DESCENDANTS : HitTestMode.Default)
    .accessibilityLevel(this.isDocumentStacked(document) && index > 0 ? 'no-hide-descendants' : 'auto')
    .clip(false)
    .onClick((): void => {
      if (this.isDocumentStacked(document) && index > 0) {
        this.toggleCategoryExpanded(categoryKey)
      }
    })
  }

  @Builder
  private DocumentCategoryDeck(categoryKey: string) {
    ListItem({ style: ListItemStyle.NONE }) {
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(this.getDocumentsForCategory(categoryKey), (document: KnowledgeDocument, index: number) => {
          this.DeckDocumentCard(categoryKey, document, index, this.getDocumentsForCategory(categoryKey).length)
        }, (document: KnowledgeDocument): string => document.id)
      }
      .width('100%')
      .height(this.getDeckHeight(categoryKey))
      .clip(false)
    }
    .clip(false)
  }

  @Builder
  private DocumentCategoryGroup(categoryKey: string) {
    ListItemGroup({
      header: this.DocumentCategoryHeader(categoryKey)
    }) {
      if (this.isManuscriptMode) {
        ForEach(this.getVisibleCategoryDocuments(categoryKey), (document: KnowledgeDocument) => {
          ListItem({ style: ListItemStyle.NONE }) {
            this.DocumentCard(document)
          }
          .swipeAction({
            start: this.UpdateSwipePanel(document),
            end: this.DeleteSwipePanel(document)
          })
          .transition(TransitionEffect.OPACITY)
        }, (document: KnowledgeDocument): string => `${categoryKey}_${document.id}`)
      } else {
        this.DocumentCategoryDeck(categoryKey)
      }
    }
    .divider(null)
    .margin({
      top: this.isManuscriptMode ? 12 : 10
    })
  }

  private getDocumentOrdinal(document: KnowledgeDocument): number {
    const categoryDocuments = this.getDocumentsForCategory(this.getDocumentCategoryKey(document))
    for (let index = 0; index < categoryDocuments.length; index++) {
      if (categoryDocuments[index].id === document.id) {
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
        this.DocumentIcon(document, 12)

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
          this.closeDocumentPreview()
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

  @Builder
  private KnowledgeDocumentList() {
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

        EmailKnowledgeCategory({
          importedDocuments: this.getDocumentsForCategory(KNOWLEDGE_CATEGORY_EMAIL),
          processingDocumentId: this.processingDocumentId,
          knowledgeWorking: this.isWorking,
          listScroller: this.listScroller,
          onImported: (): void => {
            this.loadKnowledgeBase()
          },
          onOpenDocument: (document: KnowledgeDocument): void => {
            this.handleDocumentTap(document)
          },
          onRebuildDocument: (document: KnowledgeDocument): void => {
            this.rebuildDocument(document)
          },
          onDeleteDocument: (document: KnowledgeDocument): void => {
            this.requestDeleteDocument(document)
          }
        })

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
          ForEach(this.getVisibleCategoryKeys(), (categoryKey: string) => {
            this.DocumentCategoryGroup(categoryKey)
          }, (categoryKey: string): string => categoryKey)
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
  }

  @Builder
  private SplitPreviewPlaceholder() {
    Column({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.doc_text_badge_magnifyingglass'))
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .fontSize(30)
          .fontColor([this.themePrimary])
      }
      .width(64)
      .height(64)
      .borderRadius(20)
      .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '26' : '12'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text(pickLocalizedText('选择知识文件以预览', 'Select a knowledge file to preview'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)

      Text(pickLocalizedText(
        '点击左侧列表中的文件，预览内容将在这里显示。',
        'Choose a file from the list on the left to show its preview here.'
      ))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 320 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(24)
  }

  @Builder
  private SplitPreviewPane() {
    Column() {
      if (this.topSpacerHeight > 0) {
        Column()
          .width('100%')
          .height(this.topSpacerHeight)
      }

      Stack() {
        if (this.showPreviewSheet) {
          this.PreviewSheetContent()
        } else {
          this.SplitPreviewPlaceholder()
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .height('100%')
    .layoutWeight(1)
    .border({
      width: { left: 1 },
      color: getAppUiState().themeDivider
    })
    .backgroundColor(getAppUiState().themeBackground)
  }

  build() {
    Stack() {
      if (this.splitPreviewMode) {
        Row() {
          Column() {
            this.KnowledgeDocumentList()
          }
          .width(this.splitListPaneWidth)
          .height('100%')

          this.SplitPreviewPane()
        }
        .width('100%')
        .height('100%')
      } else {
        this.KnowledgeDocumentList()

        Column()
          .width(0)
          .height(0)
          .bindSheet($$this.showPreviewSheet, this.PreviewSheetContent(), {
            height: SheetSize.LARGE,
            detents: [SheetSize.LARGE],
            dragBar: true,
            showClose: false,
            onDisappear: () => {
              if (!this.splitPreviewMode) {
                this.closeDocumentPreview()
              }
            }
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }
}
