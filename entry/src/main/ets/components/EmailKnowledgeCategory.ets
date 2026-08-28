import { uiMaterial } from '@kit.ArkUI'
import {
  EmailAccountConfig,
  EmailAttachmentPart,
  EmailImportResult,
  EmailListRequest,
  EmailMessageDetail,
  EmailMessageSummary
} from '../models/EmailModels'
import { EmailService } from '../services/EmailService'
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
import { KnowledgeDocument, KnowledgeDocumentStatus } from '../services/KnowledgeDocumentService'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'

const EMAIL_CATEGORY_COLLAPSED_VISIBLE_COUNT: number = 1
const EMAIL_CATEGORY_STACK_LIMIT: number = 3

/** Email is presented as one knowledge-source category beside PDF, Word, spreadsheets, and images. */
@ComponentV2
export struct EmailKnowledgeCategory {
  @Param importedDocuments: KnowledgeDocument[] = []
  @Param processingDocumentId: string = ''
  @Param knowledgeWorking: boolean = false
  @Param listScroller: ListScroller = new ListScroller()
  @Event onImported: () => void = (): void => {}
  @Event onOpenDocument: (document: KnowledgeDocument) => void = (_document: KnowledgeDocument): void => {}
  @Event onRebuildDocument: (document: KnowledgeDocument) => void = (_document: KnowledgeDocument): void => {}
  @Event onDeleteDocument: (document: KnowledgeDocument) => void = (_document: KnowledgeDocument): void => {}
  @Local account: EmailAccountConfig = new EmailAccountConfig()
  @Local messages: EmailMessageSummary[] = []
  @Local selectedUids: string[] = []
  @Local searchQuery: string = ''
  @Local isLoading: boolean = true
  @Local isWorking: boolean = false
  @Local showSearchSheet: boolean = false
  @Local showPreviewSheet: boolean = false
  @Local previewLoading: boolean = false
  @Local previewMessage: EmailMessageDetail = new EmailMessageDetail()
  @Local previewError: string = ''
  @Local importStatusMessage: string = ''
  @Local importStatusError: boolean = false
  @Local isCategoryExpanded: boolean = false

  private service: EmailService = ServiceRegistry.email()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  private get knowledgeListImmersiveMaterial(): boolean {
    return getAppUiState().knowledgeListImmersiveMaterial
  }

  private getSearchSheetMaterial(interactive: boolean = false): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: interactive,
      lightEffect: { color: undefined }
    })
  }

  aboutToAppear(): void {
    this.loadAccount()
  }

  private loadAccount(): void {
    this.service.loadConfig()
      .then((config: EmailAccountConfig): void => {
        this.account = config
        this.isLoading = false
      })
      .catch((error: Object): void => {
        this.isLoading = false
        this.showMailSnack(this.errorMessage(error), SnackBarTone.ERROR)
      })
  }

  private refreshInbox(): void {
    if (this.isWorking) {
      return
    }
    this.service.loadConfig()
      .then((config: EmailAccountConfig): void => {
        this.account = config
        if (!config.configured) {
          this.showMailSnack(
            pickLocalizedText('请先在设置 → 工具 → 邮件中完成授权',
              'Authorize a mailbox under Settings → Tools → Email first.')
          )
          return
        }
        this.performRefreshInbox().catch((error: Object): void => {
          this.isWorking = false
          this.showMailSnack(this.errorMessage(error), SnackBarTone.ERROR)
        })
      })
      .catch((error: Object): void => {
        this.showMailSnack(this.errorMessage(error), SnackBarTone.ERROR)
      })
  }

  private openSearchSheet(): void {
    if (this.isWorking) {
      return
    }
    this.service.loadConfig()
      .then((config: EmailAccountConfig): void => {
        this.account = config
        if (!config.configured) {
          this.showMailSnack(
            pickLocalizedText('请先在设置 → 工具 → 邮件中完成授权',
              'Authorize a mailbox under Settings → Tools → Email first.')
          )
          return
        }
        this.showSearchSheet = true
      })
      .catch((error: Object): void => {
        this.showMailSnack(this.errorMessage(error), SnackBarTone.ERROR)
      })
  }

  private async performRefreshInbox(): Promise<void> {
    this.isWorking = true
    this.importStatusMessage = ''
    this.importStatusError = false
    try {
      const request = new EmailListRequest()
      request.query = this.searchQuery
      request.sinceDays = 90
      request.limit = 50
      this.messages = [...await this.service.listMessages(request)]
      this.selectedUids = []
      if (this.messages.length === 0) {
        this.showMailSnack(pickLocalizedText('没有找到匹配邮件', 'No matching email found'))
      }
    } finally {
      this.isWorking = false
    }
  }

  private isSelected(uid: string): boolean {
    return this.selectedUids.includes(uid)
  }

  private toggleSelected(uid: string): void {
    const next = [...this.selectedUids]
    const index = next.indexOf(uid)
    if (index >= 0) {
      next.splice(index, 1)
    } else {
      next.push(uid)
    }
    this.selectedUids = next
  }

  private toggleSelectAll(): void {
    if (this.messages.length > 0 && this.selectedUids.length === this.messages.length) {
      this.selectedUids = []
      return
    }
    this.selectedUids = this.messages.map((message: EmailMessageSummary): string => message.uid)
  }

  private importSelected(): void {
    if (this.isWorking || this.selectedUids.length === 0) {
      return
    }
    this.performImportSelected().catch((error: Object): void => {
      this.isWorking = false
      this.showMailSnack(this.errorMessage(error), SnackBarTone.ERROR)
    })
  }

  private async performImportSelected(): Promise<void> {
    this.isWorking = true
    try {
      const result: EmailImportResult = await this.service.importMessagesToKnowledge(this.selectedUids)
      if (result.importedDocuments > 0) {
        this.selectedUids = []
        this.onImported()
      }
      if (result.ok && result.failedParts === 0) {
        this.showSearchSheet = false
      }
      const tone = result.failedParts > 0 ? SnackBarTone.ERROR :
        (result.ok ? SnackBarTone.SUCCESS : SnackBarTone.ERROR)
      this.importStatusMessage = result.message
      this.importStatusError = tone === SnackBarTone.ERROR
      this.showMailSnack(result.message, tone, 5200)
    } finally {
      this.isWorking = false
    }
  }

  private openPreview(message: EmailMessageSummary): void {
    if (this.previewLoading) {
      return
    }
    this.previewMessage = new EmailMessageDetail(message.uid)
    this.previewMessage.subject = message.subject
    this.previewMessage.from = message.from
    this.previewMessage.date = message.date
    this.previewError = ''
    this.previewLoading = true
    this.showPreviewSheet = true
    this.service.fetchMessage(message.uid)
      .then((detail: EmailMessageDetail): void => {
        if (this.previewMessage.uid === detail.uid) {
          this.previewMessage = detail
          this.previewLoading = false
        }
      })
      .catch((error: Object): void => {
        this.previewError = this.errorMessage(error)
        this.previewLoading = false
      })
  }

  private formatDate(message: EmailMessageSummary): string {
    if (message.timestamp <= 0) {
      return message.date
    }
    const date = new Date(message.timestamp)
    const now = new Date()
    if (date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth() &&
      date.getDate() === now.getDate()) {
      return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`
    }
    return `${date.getMonth() + 1}/${date.getDate()}`
  }

  private formatSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`
    }
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  private errorMessage(error: Object): string {
    return error instanceof Error && error.message.trim() !== ''
      ? error.message
      : pickLocalizedText('邮件操作失败', 'Email operation failed')
  }

  private showMailSnack(message: string | Resource, tone: SnackBarTone = SnackBarTone.DEFAULT,
    duration: number = 3000): void {
    const options = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  private getVisibleImportedDocuments(): KnowledgeDocument[] {
    if (this.isCategoryExpanded ||
      this.importedDocuments.length <= EMAIL_CATEGORY_COLLAPSED_VISIBLE_COUNT) {
      return this.importedDocuments
    }
    return this.importedDocuments.slice(0, EMAIL_CATEGORY_COLLAPSED_VISIBLE_COUNT)
  }

  private getCollapsedStackCount(): number {
    if (this.isCategoryExpanded) {
      return 0
    }
    return Math.min(
      EMAIL_CATEGORY_STACK_LIMIT,
      Math.max(0, this.importedDocuments.length - EMAIL_CATEGORY_COLLAPSED_VISIBLE_COUNT)
    )
  }

  private toggleCategoryExpanded(): void {
    if (this.importedDocuments.length <= EMAIL_CATEGORY_COLLAPSED_VISIBLE_COUNT) {
      return
    }
    this.closeAllSwipeActions()
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, (): void => {
      this.isCategoryExpanded = !this.isCategoryExpanded
    })
  }

  private getCategorySummary(): string {
    if (!this.account.configured) {
      return pickLocalizedText('在设置 → 工具中配置', 'Configure under Settings → Tools')
    }
    const count = this.importedDocuments.length
    if (count === 0) {
      return pickLocalizedText(
        `已授权 ${this.account.emailAddress}`,
        `Authorized ${this.account.emailAddress}`
      )
    }
    if (count > EMAIL_CATEGORY_COLLAPSED_VISIBLE_COUNT && this.isCategoryExpanded) {
      return pickLocalizedText(`${count} 个知识文件 · 已展开全部`, `${count} knowledge files · Showing all`)
    }
    if (count > EMAIL_CATEGORY_COLLAPSED_VISIBLE_COUNT) {
      return pickLocalizedText(`${count} 个知识文件 · 显示最新 1 个`, `${count} knowledge files · Latest 1`)
    }
    return pickLocalizedText('已导入 1 个知识文件', '1 knowledge file imported')
  }

  @Builder
  private CategoryHeader() {
    Row({ space: 10 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.envelope'))
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .fontSize(18)
          .fontColor(['#C97936'])
      }
      .width(36)
      .height(36)
      .borderRadius(this.isManuscriptMode ? 0 : 12)
      .backgroundColor(this.isManuscriptMode ? Color.Transparent : withColorAlpha('#C97936',
        this.isDarkMode ? '26' : '14'))
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text(pickLocalizedText('邮件', 'Email'))
          .fontFamily(this.isManuscriptMode ? MANUSCRIPT_HEADING_FONT : undefined)
          .fontSize(this.isManuscriptMode ? 18 : 14)
          .fontWeight(this.isManuscriptMode ? 600 : FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.getCategorySummary())
          .fontFamily(this.isManuscriptMode ? MANUSCRIPT_BODY_FONT : undefined)
          .fontSize(this.isManuscriptMode ? 11.5 : 10.5)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.importedDocuments.length > EMAIL_CATEGORY_COLLAPSED_VISIBLE_COUNT) {
        Row({ space: 4 }) {
          Text(this.isCategoryExpanded
            ? pickLocalizedText('收起', 'Collapse')
            : pickLocalizedText('展开', 'Expand'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor('#C97936')

          SymbolGlyph($r('sys.symbol.chevron_down'))
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .fontSize(12)
            .fontColor(['#C97936'])
            .rotate({ angle: this.isCategoryExpanded ? 180 : 0 })
            .animation({ duration: 220, curve: Curve.EaseOut })
        }
        .height(32)
        .padding({ left: 9, right: 9 })
        .borderRadius(999)
        .backgroundColor(withColorAlpha('#C97936', this.isDarkMode ? '24' : '10'))
        .stateStyles({
          normal: {
            .opacity(1)
          },
          pressed: {
            .opacity(0.62)
          }
        })
        .onClick((): void => {
          this.toggleCategoryExpanded()
        })
      }

      Button({ type: ButtonType.Circle, stateEffect: false }) {
        if (this.isWorking) {
          LoadingProgress().width(18).height(18).color('#C97936')
        } else {
          SymbolGlyph($r('sys.symbol.doc_plaintext_and_envelope_open'))
            .fontSize(17)
            .fontColor(['#C97936'])
        }
      }
      .width(36)
      .height(36)
      .padding(0)
      .backgroundColor(withColorAlpha('#C97936', this.isDarkMode ? '24' : '10'))
      .enabled(!this.isWorking)
      .onClick(() => this.openSearchSheet())
    }
    .width('100%')
    .height(this.isManuscriptMode ? 64 : 60)
    .padding({ left: this.isManuscriptMode ? 4 : 12, right: this.isManuscriptMode ? 4 : 10 })
    .margin({ bottom: this.isManuscriptMode ? 0 : 8 })
    .borderRadius(this.isManuscriptMode ? 0 : 14)
    .backgroundColor(this.isManuscriptMode ? Color.Transparent : getAppUiState().themePrimaryLight)
    .border({
      width: this.isManuscriptMode ? { bottom: 1 } : 0.5,
      color: this.isManuscriptMode ? getAppUiState().themeDivider : getAppUiState().themePrimaryLight
    })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: this.isManuscriptMode ? Color.Transparent : getAppUiState().themePrimaryLight,
      applyShadow: !this.isManuscriptMode,
      interactive: false,
      lightEffect: this.isManuscriptMode ? undefined : { color: undefined }
    }))
  }

  @Builder
  private AccountHint() {
    Column({ space: 8 }) {
      Text(pickLocalizedText('尚未授权邮箱', 'No mailbox authorized'))
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text(pickLocalizedText('请在“设置 → 工具 → 邮件”中配置 SMTP 与 IMAP 授权。',
        'Configure SMTP and IMAP under Settings → Tools → Email.'))
        .fontSize(11).lineHeight(17).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(18)
    .borderRadius(this.isManuscriptMode ? 0 : 12)
    .backgroundColor(this.isManuscriptMode ? Color.Transparent : Color.Transparent)
    .border({ width: 0.5, color: getAppUiState().themeDivider })
  }

  @Builder
  private SearchAndSelectionRow() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.envelope'))
          .fontSize(14)
          .fontColor([this.themePrimary])
        Text(this.account.emailAddress)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(pickLocalizedText('近 90 天', 'Last 90 days'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding({ left: 4, right: 4 })

      Row({ space: 6 }) {
        Search({
          value: this.searchQuery,
          placeholder: pickLocalizedText('主题、正文或发件人', 'Subject, body, or sender')
        })
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          .systemMaterial(this.getSearchSheetMaterial(true))
          .onChange((value: string): void => { this.searchQuery = value })
          .onSubmit((): void => { this.refreshInbox() })

        Button({ type: ButtonType.Circle, stateEffect: false }) {
          if (this.isWorking) {
            LoadingProgress().width(17).height(17).color(this.themePrimary)
          } else {
            SymbolGlyph($r('sys.symbol.doc_plaintext_and_envelope_open'))
              .fontSize(17)
              .fontColor([this.themePrimary])
          }
        }
        .width(36)
        .height(36)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .enabled(!this.isWorking)
        .systemMaterial(this.getSearchSheetMaterial(!this.isWorking))
        .onClick(() => this.refreshInbox())
      }
      .width('100%')

      if (this.messages.length > 0) {
        Row() {
          Text(pickLocalizedText(`${this.messages.length} 封 · 已选 ${this.selectedUids.length} 封`,
            `${this.messages.length} messages · ${this.selectedUids.length} selected`))
            .fontSize(11)
            .fontColor(this.selectedUids.length > 0 ? this.themePrimary : $r('app.color.text_tertiary'))
          Blank()
          Button(this.selectedUids.length === this.messages.length
            ? pickLocalizedText('取消全选', 'Clear all') : pickLocalizedText('全选', 'Select all'))
            .height(28)
            .padding({ left: 10, right: 10 })
            .fontSize(11)
            .fontColor(this.themePrimary)
            .type(ButtonType.Capsule)
            .stateEffect(false)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.toggleSelectAll())
        }
        .width('100%')
        .height(30)
        .padding({ left: 4, right: 2 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
  }

  @Builder
  private MessageRow(message: EmailMessageSummary, isLast: boolean) {
    Column() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          SymbolGlyph(this.isSelected(message.uid)
            ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
            .fontSize(21)
            .fontColor([this.isSelected(message.uid) ? this.themePrimary : $r('app.color.text_tertiary')])
        }
        .width(32).height(32).padding(0).backgroundColor(Color.Transparent)
        .onClick(() => this.toggleSelected(message.uid))

        Column({ space: 4 }) {
          Row({ space: 8 }) {
            if (message.unread) {
              Circle().width(6).height(6).fill(this.themePrimary)
            }
            Text(message.from).fontSize(12).fontWeight(message.unread ? FontWeight.Bold : FontWeight.Medium)
              .fontColor($r('app.color.text_primary')).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Text(this.formatDate(message)).fontSize(10.5).fontColor($r('app.color.text_tertiary'))
          }.width('100%')
          Text(message.subject).fontSize(13.5).lineHeight(18)
            .fontWeight(message.unread ? FontWeight.Bold : FontWeight.Normal)
            .fontColor($r('app.color.text_primary')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Row({ space: 7 }) {
            SymbolGlyph($r('sys.symbol.envelope_open')).fontSize(11)
              .fontColor([$r('app.color.text_tertiary')])
            Text(this.formatSize(message.size)).fontSize(10).fontColor($r('app.color.text_tertiary'))
            Blank()
            Text(pickLocalizedText('查看详情', 'Preview'))
              .fontSize(10)
              .fontColor(this.themePrimary)
          }.width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => this.openPreview(message))
      }
      .width('100%')
      .padding({ left: 10, right: 12, top: 9, bottom: 9 })

      if (!isLast) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 50, right: 12 })
      }
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }

  private getKnowledgeStatusText(document: KnowledgeDocument): string {
    if (document.status === KnowledgeDocumentStatus.READY) {
      return pickLocalizedText(`${document.chunkCount} 个片段`, `${document.chunkCount} chunks`)
    }
    if (document.status === KnowledgeDocumentStatus.INDEXING) {
      return pickLocalizedText('正在建立索引', 'Indexing')
    }
    return document.errorMessage !== '' ? document.errorMessage : pickLocalizedText('索引失败', 'Index failed')
  }

  private getKnowledgeStatusColor(document: KnowledgeDocument): string {
    if (document.status === KnowledgeDocumentStatus.READY) {
      return '#2E8B57'
    }
    if (document.status === KnowledgeDocumentStatus.FAILED) {
      return '#D9485F'
    }
    return this.themePrimary
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

  private getDocumentSymbol(document: KnowledgeDocument): Resource {
    if (this.isPdfDocument(document)) {
      return $r('sys.symbol.pdf_doc')
    }
    if (this.isImageDocument(document)) {
      return $r('sys.symbol.picture')
    }
    return $r('sys.symbol.doc_text')
  }

  @Builder
  private DocumentIcon(document: KnowledgeDocument, size: number, color: ResourceColor) {
    if (this.isDocxDocument(document)) {
      Image($r('app.media.doc_docx')).width(size).height(size).fillColor(color)
    } else if (this.isXlsxDocument(document)) {
      Image($r('app.media.doc_xlsx')).width(size).height(size).fillColor(color)
    } else {
      SymbolGlyph(this.getDocumentSymbol(document))
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontSize(size)
        .fontColor([color])
    }
  }

  @Builder
  private DocumentCardContent(document: KnowledgeDocument) {
    Column() {
      this.DocumentIcon(document, 18, this.themePrimary)
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
        Text(this.formatSize(document.size)).fontSize(10).fontColor($r('app.color.text_tertiary'))
        Text('·').fontSize(10).fontColor($r('app.color.text_tertiary'))
        Text(this.getKnowledgeStatusText(document))
          .fontSize(10)
          .fontColor(this.getKnowledgeStatusColor(document))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%')
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)

    if (this.processingDocumentId === document.id) {
      LoadingProgress().width(20).height(20).color(this.themePrimary)
    } else {
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontSize(14)
        .fontColor([$r('app.color.text_tertiary')])
    }
  }

  private closeAllSwipeActions(): void {
    try {
      this.listScroller.closeAllSwipeActions()
    } catch (_error) {}
  }

  private handleDocumentTap(document: KnowledgeDocument): void {
    this.closeAllSwipeActions()
    this.onOpenDocument(document)
  }

  @Builder
  private ImmersiveDocumentCard(document: KnowledgeDocument) {
    Row({ space: 10 }) { this.DocumentCardContent(document) }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .borderRadius(12)
      .border({ width: 0.5, color: getAppUiState().themeDivider })
      .onClick(() => this.handleDocumentTap(document))
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: false,
        lightEffect: { color: undefined }
      }))
  }

  @Builder
  private GaussianBlurDocumentCard(document: KnowledgeDocument) {
    Row({ space: 10 }) { this.DocumentCardContent(document) }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .borderRadius(12)
      .clip(true)
      .border({ width: 0.5, color: getAppUiState().themeDivider })
      .backgroundColor(Color.Transparent)
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .onClick(() => this.handleDocumentTap(document))
  }

  @Builder
  private ManuscriptDocumentRow(document: KnowledgeDocument) {
    Column({ space: 5 }) {
      Row({ space: 8 }) {
        Text(toRomanNumeral(this.importedDocuments.indexOf(document) + 1))
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
        Column().height(1).border({
          width: { top: 1 },
          color: this.isDarkMode ? '#4A463F' : '#C9C4BB',
          style: BorderStyle.Dotted
        }).layoutWeight(1).constraintSize({ minWidth: 18 })
        if (this.processingDocumentId === document.id) {
          LoadingProgress().width(16).height(16).color(this.themePrimary)
        } else {
          Text(this.formatSize(document.size))
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontSize(11.5)
            .fontColor(getAppUiState().themeTextTertiary)
            .fontFeature('tnum')
            .maxLines(1)
        }
      }.width('100%').alignItems(VerticalAlign.Center)
      Row({ space: 7 }) {
        this.DocumentIcon(document, 12, this.getKnowledgeStatusColor(document))
        Text(this.getKnowledgeStatusText(document))
          .fontFamily(MANUSCRIPT_BODY_FONT)
          .fontSize(12.5)
          .fontStyle(FontStyle.Italic)
          .fontColor(getAppUiState().themeTextSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').padding({ left: 34 })
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 14, bottom: 12 })
    .backgroundColor(Color.Transparent)
    .border({ width: { bottom: 0.5 }, color: getAppUiState().themeDivider })
    .onClick(() => this.handleDocumentTap(document))
  }

  @Builder
  private ImportedDocumentRow(document: KnowledgeDocument) {
    if (this.isManuscriptMode) {
      this.ManuscriptDocumentRow(document)
    } else if (this.knowledgeListImmersiveMaterial) {
      this.ImmersiveDocumentCard(document)
    } else {
      this.GaussianBlurDocumentCard(document)
    }
  }

  @Builder
  private ImmersiveCollapsedStackLayer(layer: number) {
    Row()
      .width(`${100 - layer * 4}%`)
      .height(12)
      .borderRadius({ bottomLeft: 12, bottomRight: 12 })
      .backgroundColor(getAppUiState().themePrimaryLight)
      .border({ width: 0.5, color: getAppUiState().themeDivider })
      .opacity(1 - layer * 0.12)
      .translate({ y: -8 + (layer - 1) * 4 })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        materialColor: getAppUiState().themePrimaryLight,
        applyShadow: true,
        interactive: false,
        lightEffect: { color: undefined }
      }))
  }

  @Builder
  private GaussianCollapsedStackLayer(layer: number) {
    Row()
      .width(`${100 - layer * 4}%`)
      .height(12)
      .borderRadius({ bottomLeft: 12, bottomRight: 12 })
      .clip(true)
      .backgroundColor(getAppUiState().themePrimaryLight)
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .border({ width: 0.5, color: getAppUiState().themeDivider })
      .opacity(1 - layer * 0.12)
      .translate({ y: -8 + (layer - 1) * 4 })
  }

  @Builder
  private CollapsedCategoryStack() {
    if (!this.isManuscriptMode && this.getCollapsedStackCount() > 0) {
      ListItem({ style: ListItemStyle.NONE }) {
        Stack({ alignContent: Alignment.Top }) {
          if (this.getCollapsedStackCount() >= 3) {
            if (this.knowledgeListImmersiveMaterial) {
              this.ImmersiveCollapsedStackLayer(3)
            } else {
              this.GaussianCollapsedStackLayer(3)
            }
          }
          if (this.getCollapsedStackCount() >= 2) {
            if (this.knowledgeListImmersiveMaterial) {
              this.ImmersiveCollapsedStackLayer(2)
            } else {
              this.GaussianCollapsedStackLayer(2)
            }
          }
          if (this.getCollapsedStackCount() >= 1) {
            if (this.knowledgeListImmersiveMaterial) {
              this.ImmersiveCollapsedStackLayer(1)
            } else {
              this.GaussianCollapsedStackLayer(1)
            }
          }
        }
        .width('100%')
        .height(8 + this.getCollapsedStackCount() * 4)
        .clip(false)
        .onClick((): void => {
          this.toggleCategoryExpanded()
        })
      }
      .clip(false)
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.combine(TransitionEffect.scale({
          x: 0.96,
          y: 0.72,
          centerX: '50%',
          centerY: '0%'
        })).animation({ duration: 220, curve: Curve.EaseOut }),
        TransitionEffect.OPACITY.combine(TransitionEffect.scale({
          x: 0.98,
          y: 0.6,
          centerX: '50%',
          centerY: '0%'
        })).animation({ duration: 140, curve: Curve.EaseIn })
      ))
    }
  }

  @Builder
  private RebuildSwipePanel(document: KnowledgeDocument) {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        Column({ space: 2 }) {
          SymbolGlyph($r('sys.symbol.doc_text_badge_leaf')).fontSize(18).fontColor([this.themePrimary])
          Text(pickLocalizedText('更新', 'Update')).fontSize(11).fontColor(this.themePrimary)
        }.width('100%').height(56).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      }
      .width(56).height(56).padding(0).backgroundColor(Color.Transparent)
      .enabled(!this.knowledgeWorking)
      .onClick(() => {
        this.closeAllSwipeActions()
        this.onRebuildDocument(document)
      })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true,
        lightEffect: { color: undefined }
      }))
    }.width(72).height('100%').justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center).clip(false)
  }

  @Builder
  private DeleteSwipePanel(document: KnowledgeDocument) {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        Column({ space: 2 }) {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([$r('app.color.status_error')])
          Text(pickLocalizedText('删除', 'Delete')).fontSize(11).fontColor($r('app.color.status_error'))
        }.width('100%').height(56).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      }
      .width(56).height(56).padding(0).backgroundColor(Color.Transparent)
      .enabled(!this.knowledgeWorking)
      .onClick(() => {
        this.closeAllSwipeActions()
        this.onDeleteDocument(document)
      })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true,
        lightEffect: { color: undefined }
      }))
    }.width(64).height('100%').justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center).clip(false)
  }

  @Builder
  private PreviewSheetContent() {
    Column() {
      ImmersiveSheetHeader({
        title: this.previewMessage.subject || pickLocalizedText('邮件预览', 'Email Preview'),
        onLeadingClick: (): void => { this.showPreviewSheet = false }
      })
      if (this.previewLoading) {
        Column() { LoadingProgress().width(30).height(30).color(this.themePrimary) }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.previewError !== '') {
        Text(this.previewError).fontSize(14).fontColor($r('app.color.status_error'))
          .padding(24).layoutWeight(1).width('100%')
      } else {
        Scroll() {
          Column({ space: 8 }) {
            Column() {
              Column({ space: 5 }) {
                Row({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.envelope')).fontSize(16).fontColor([this.themePrimary])
                  Text(this.previewMessage.from).fontSize(13).fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary')).width('100%').layoutWeight(1)
                }.width('100%')
                Text(this.previewMessage.date).fontSize(11).fontColor($r('app.color.text_tertiary')).width('100%')
                if (this.previewMessage.to !== '') {
                  Text(pickLocalizedText(`收件人：${this.previewMessage.to}`, `To: ${this.previewMessage.to}`))
                    .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 11, bottom: 10 })

              Divider().color($r('app.color.divider')).margin({ left: 12, right: 12 })

              Column({ space: 6 }) {
                Text(pickLocalizedText('邮件正文', 'Message'))
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                Text(this.previewMessage.bodyText || pickLocalizedText('(无可解析正文)', '(No readable body)'))
                  .fontSize(14).lineHeight(21).fontColor($r('app.color.text_primary')).width('100%')
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 12 })
            }
            .width('100%')
            .borderRadius(16)
            .border({ width: 1, color: getAppUiState().themePrimaryLight })
            .systemMaterial(this.getSearchSheetMaterial(false))

            if (this.previewMessage.attachments.length > 0) {
              Column() {
                Text(pickLocalizedText('附件与内嵌图片', 'Attachments and Inline Images'))
                  .fontSize(12).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_secondary'))
                  .width('100%').padding({ left: 12, right: 12, top: 11, bottom: 7 })
                ForEach(this.previewMessage.attachments, (item: EmailAttachmentPart, index: number) => {
                  Column() {
                    Row({ space: 10 }) {
                      SymbolGlyph(item.inline ? $r('sys.symbol.picture') : $r('sys.symbol.doc'))
                        .fontSize(18).fontColor([this.themePrimary])
                      Column({ space: 2 }) {
                        Text(item.name).fontSize(13).fontColor($r('app.color.text_primary')).maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                        Text(`${item.mimeType} · ${this.formatSize(item.bytes.byteLength)}`)
                          .fontSize(10).fontColor($r('app.color.text_tertiary')).width('100%')
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
                    if (index < this.previewMessage.attachments.length - 1) {
                      Divider().color($r('app.color.divider')).margin({ left: 40, right: 12 })
                    }
                  }
                  .width('100%')
                }, (item: EmailAttachmentPart, index: number): string => `${item.name}_${index}`)
              }
              .width('100%')
              .borderRadius(16)
              .border({ width: 1, color: getAppUiState().themePrimaryLight })
              .systemMaterial(this.getSearchSheetMaterial(false))
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 16 })
          .alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }
    }
    .width('100%').height('100%').backgroundColor(Color.Transparent)
  }

  @Builder
  private SearchSheetContent() {
    Column() {
      ImmersiveSheetHeader({
        title: pickLocalizedText('搜索并导入邮件', 'Search and Import Email'),
        showTrailing: this.messages.length > 0,
        trailingColor: this.selectedUids.length > 0 ? this.themePrimary : $r('app.color.text_tertiary'),
        trailingButtonEnabled: !this.isWorking && this.selectedUids.length > 0,
        trailingLoading: this.isWorking && this.selectedUids.length > 0,
        onTrailingClick: (): void => { this.importSelected() },
        onLeadingClick: (): void => { this.showSearchSheet = false }
      })

      this.SearchAndSelectionRow()

      List() {
        if (this.isWorking && this.messages.length === 0) {
          ListItem() {
            Column({ space: 10 }) {
              LoadingProgress().width(30).height(30).color(this.themePrimary)
              Text(pickLocalizedText('正在连接邮箱并搜索…', 'Connecting to your mailbox…'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .height(160)
            .justifyContent(FlexAlign.Center)
          }
        } else if (this.messages.length === 0) {
          ListItem() {
            Column({ space: 9 }) {
              SymbolGlyph($r('sys.symbol.doc_plaintext_and_envelope_open'))
                .fontSize(42)
                .fontColor([$r('app.color.text_tertiary')])
              Text(pickLocalizedText('搜索邮箱中的知识', 'Find knowledge in your mailbox'))
                .fontSize(15)
                .fontColor($r('app.color.text_secondary'))
              Text(pickLocalizedText('可按主题、正文或发件人搜索近 90 天邮件，预览后再选择导入。',
                'Search the last 90 days by subject, body, or sender. Preview messages before importing.'))
                .fontSize(11)
                .lineHeight(17)
                .fontColor($r('app.color.text_tertiary'))
                .textAlign(TextAlign.Center)
                .constraintSize({ maxWidth: 300 })
            }
            .width('100%')
            .height(180)
            .padding({ left: 20, right: 20 })
            .justifyContent(FlexAlign.Center)
          }
        } else {
          ListItemGroup() {
            ForEach(this.messages, (message: EmailMessageSummary, index: number) => {
              ListItem({ style: ListItemStyle.NONE }) {
                this.MessageRow(message, index === this.messages.length - 1)
              }
            }, (message: EmailMessageSummary): string => `email_search_${message.uid}`)
          }
          .divider(null)
          .margin({ left: 16, right: 16, top: 4, bottom: 8 })
          .borderRadius(16)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: getAppUiState().themePrimaryLight })
          .systemMaterial(this.getSearchSheetMaterial(true))
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ bottom: 12 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .bindSheet($$this.showPreviewSheet, this.PreviewSheetContent(), {
      height: SheetSize.LARGE,
      detents: [SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      backgroundColor: Color.Transparent,
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR
      }),
      preferType: SheetType.BOTTOM,
      onDisappear: (): void => {
        this.previewLoading = false
        this.previewError = ''
      }
    })
  }

  build() {
    ListItemGroup({ header: this.CategoryHeader() }) {
      if (this.isLoading) {
        ListItem() {
          Row() { LoadingProgress().width(24).height(24).color(this.themePrimary) }
            .width('100%').height(90).justifyContent(FlexAlign.Center)
        }
      } else if (!this.account.configured) {
        ListItem() { this.AccountHint() }
      }
      if (this.importedDocuments.length > 0) {
        ForEach(this.getVisibleImportedDocuments(), (document: KnowledgeDocument) => {
          ListItem({ style: ListItemStyle.NONE }) { this.ImportedDocumentRow(document) }
            .margin({
              bottom: this.isManuscriptMode ? 0 : (this.getCollapsedStackCount() > 0 ? 0 : 8)
            })
            .swipeAction({
              start: this.RebuildSwipePanel(document),
              end: this.DeleteSwipePanel(document)
            })
            .borderRadius(this.isManuscriptMode ? 0 : 12)
            .clip(false)
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 }))
                .animation({ duration: 220, curve: Curve.EaseOut }),
              TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -5 }))
                .animation({ duration: 140, curve: Curve.EaseIn })
            ))
        }, (document: KnowledgeDocument): string => `email_document_${document.id}`)

        this.CollapsedCategoryStack()
      }
    }
    .divider(null)
    .margin({
      left: this.isManuscriptMode ? 32 : 16,
      right: this.isManuscriptMode ? 32 : 16,
      top: this.isManuscriptMode ? 12 : 10
    })
    .bindSheet($$this.showSearchSheet, this.SearchSheetContent(), {
      height: SheetSize.LARGE,
      detents: [SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      backgroundColor: Color.Transparent,
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR
      }),
      preferType: SheetType.BOTTOM,
      onDisappear: (): void => {
        this.showPreviewSheet = false
        this.previewLoading = false
        this.previewError = ''
        this.importStatusMessage = ''
        this.importStatusError = false
      }
    })
  }
}
