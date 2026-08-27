import { AssistantResponseSegment, AssistantResponseSegmentType, ChatMessage, MessageRole, MessageAttachment, AttachmentType, ContextCompactionUiState, ToolCall, ToolResult } from '../models/ChatModels'
import { VisualEffectsMode } from '../models/ThemeColors'
import { pasteboard } from '@kit.BasicServicesKit'
import { image } from '@kit.ImageKit'
import { showToast } from '../utils/ToastUtil'
import { getModelIconPath, buildIconResourcePath } from '../utils/ProviderIconUtils'
import { shouldShowAssistantMessageToolbar } from '../utils/MessageBubbleDisplayUtils'
import { SearchReferenceCard } from './SearchReferenceCard'
import { ToolCallCard, ToolCallCardEntry } from './ToolCallCard'
import { SubAgentPreviewSheetContent } from './SubAgentPreviewSheetContent'
import { SUB_AGENT_SOURCE_LABEL_PREFIX } from '../services/SubAgentService'
import { AskUserCard } from './AskUserCard'
import { HtmlPreviewCard } from './HtmlPreviewCard'
import { VChartCard } from './VChartCard'
import { MapResultCard } from './map/MapResultCard'
import { TypingDots } from './TypingDots'
import { ChatMarkdownRenderer } from './ChatMarkdownRenderer'
import { AssistantAvatarView } from './AssistantAvatar'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { MAP_SEARCH_ROUTE_TOOL_ID, MATH_CHART_TOOL_ID } from '../config/BuiltinTools'
import { formatBillingAmount, formatCacheHitPercent } from '../utils/ModelBillingUtils'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'
import { resolveChatSerifFontFamily } from '../utils/ChatSerifFontUtils'
import {
  ensureManuscriptFonts,
  MANUSCRIPT_BODY_FONT,
  MANUSCRIPT_HEADING_FONT,
  MANUSCRIPT_COMPACT_BAR_HEIGHT
} from '../utils/ManuscriptVisualUtils'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import {
  isPythonSandboxFileAttachmentId,
  parsePythonSandboxFileUrl
} from '../services/PythonSandboxArtifactLink'

const DOMAIN = 0x0002
const TAG = 'MessageBubble'

// 翻译目标语言配置
interface TranslateLanguage {
  code: string
  name: string
  nativeName: string
}

// 内容分段（用于 HTML 代码块内联预览）
interface ContentSegment {
  isHtml: boolean
  renderContent: string
}

interface ImageAttachmentEntry {
  attachment: MessageAttachment
  originalIndex: number
}

interface MathChartToolPayload {
  ok?: boolean
  chartType?: string
  chart_type?: string
  summary?: string
  chart_spec?: string
}

// 工具调用渲染分组：同一工具（同名 + 同来源）的多次调用合并成一张卡片
class ToolCallRenderGroup {
  key: string = ''
  isAskUser: boolean = false
  askUserCalls: ToolCall[] = []
  entries: ToolCallCardEntry[] = []
  anyExecuting: boolean = false
}

class MessageVChartPayload {
  id: string = ''
  specJson: string = ''
  summary: string = ''
  chartType: string = ''

  constructor(id: string, specJson: string, summary: string, chartType: string) {
    this.id = id
    this.specJson = specJson
    this.summary = summary
    this.chartType = chartType
  }
}

class MessageMapPayload {
  id: string = ''
  resultContent: string = ''

  constructor(id: string, resultContent: string) {
    this.id = id
    this.resultContent = resultContent
  }
}

// @Local 数组要整体替换才会触发刷新，这两个 helper 统一返回新数组
function appendUniqueId(ids: string[], id: string): string[] {
  if (ids.includes(id)) {
    return ids
  }
  const next = ids.slice()
  next.push(id)
  return next
}

function removeId(ids: string[], id: string): string[] {
  const index = ids.indexOf(id)
  if (index < 0) {
    return ids
  }
  const next = ids.slice()
  next.splice(index, 1)
  return next
}

@ComponentV2
export struct MessageBubble {
  @Param message: ChatMessage = new ChatMessage('', MessageRole.USER, '')
  @Param renderSignature: string = ''
  @Param contentRenderSignature: string = ''
  @Param showHeader: boolean = true  // 是否显示消息头部（模型信息）
  @Param currentModelId: string = ''  // 当前会话的模型 ID（用于图标匹配回退）
  @Param assistantName: string = '默认助手'
  @Param assistantAvatarSymbol: string = 'AI'
  @Param assistantAvatarColor: string = '#7A68F0'
  @Param assistantAvatarCacheKey: number = 0
  @Param themeRenderKey: string = ''
  @Param isMultiSelectMode: boolean = false  // 是否处于多选模式
  @Param isSelected: boolean = false  // 是否被选中
  @Param isEditing: boolean = false  // 是否处于编辑状态（被编辑的消息高亮显示）
  @Param previewContent: string = ''  // 编辑时的实时预览内容
  @Param previewAttachments: MessageAttachment[] = []  // 编辑时的实时预览附件
  @Param isFirstAssistantMessage: boolean = false
  @Local isReasoningExpanded: boolean = false  // 推理内容是否展开
  // 用户显式展开/折叠过的推理段。两个列表都需要：生成中的推理段默认展开，
  // 只记录"展开过"就无法表达"用户主动折叠了正在生成的推理段"。
  @Local expandedTimelineReasoningIds: string[] = []
  @Local collapsedTimelineReasoningIds: string[] = []
  @Local translatedText: string = ''  // 翻译结果
  @Local isTranslating: boolean = false  // 是否正在翻译
  @Local showTranslation: boolean = false  // 是否显示翻译结果
  @Local isTranslationExpanded: boolean = true  // 翻译结果是否展开
  @Local currentTranslateLang: string = ''  // 当前翻译的目标语言
  @Local showEstimatedCostPopup: boolean = false
  @Local showCacheHitPopup: boolean = false
  @Local showLatexPreview: boolean = false
  // 子智能体实时预览面板（bindSheet 挂在工具区域 Column 上，避免卡片重建时被关闭）
  @Local showSubAgentPreviewSheet: boolean = false
  @Local latexPreviewText: string = ''
  @Local latexPreviewPixelMap: image.PixelMap | undefined = undefined
  @Local latexPreviewImageWidth: number = 0
  @Local latexPreviewImageHeight: number = 0
  // 深色模式状态（用于主题适配）
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  // 主题颜色（从 ThemeService 同步）
  private get themeUserBubble(): string {
    return getAppUiState().themeUserBubble
  }
  private get themeUserBubbleText(): string {
    return getAppUiState().themeUserBubbleText
  }
  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get chatBubbleTypeface(): string {
    const uiState = getAppUiState()
    if (uiState.visualEffectsMode === VisualEffectsMode.MANUSCRIPT) {
      return MANUSCRIPT_BODY_FONT
    }
    return uiState.chatSerifFontEnabled ? resolveChatSerifFontFamily(uiState.chatSerifFontFamily) : 'HarmonyOS Sans'
  }
  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }
  private get manuscriptAssistantLabel(): string {
    const name = this.assistantName.trim()
    return (name !== '' ? name : 'AI').toUpperCase()
  }
  private get manuscriptAccent(): string {
    return this.isDarkMode ? '#C99A52' : '#B68235'
  }
  private get manuscriptAccentDeep(): string {
    return this.isDarkMode ? '#D9B274' : '#8A6228'
  }
  private get messageToolbarIconColor(): ResourceColor {
    return this.isManuscriptMode ? this.manuscriptAccentDeep : $r('app.color.text_tertiary')
  }
  private get translationLightSurface(): string {
    return '#FFFFFF'
  }
  private get translationLightBorder(): string {
    return '#E5E7EB'
  }
  private get translationLightTextPrimary(): string {
    return '#111827'
  }
  private get translationLightTextSecondary(): string {
    return '#6B7280'
  }
  private get translationLightTextTertiary(): string {
    return '#9CA3AF'
  }

  // 聊天字体大小
  @Param chatFontSize: number = 15

  private multiSelectTouchStartX: number = 0
  private multiSelectTouchStartY: number = 0
  private multiSelectTouchActive: boolean = false
  private static readonly MULTI_SELECT_TAP_THRESHOLD_VP: number = 8

  // ========== 流式渲染优化 ==========
  // lv-markdown-in 自带流式渲染，无需手动节流
  private boundMessageId: string = ''
  private translationRequestToken: number = 0
  private get speakingMessageId(): string {
    return getAppUiState().speakingMessageId
  }
  private get ttsLoadingMessageId(): string {
    return getAppUiState().ttsLoadingMessageId
  }
  // 聊天图片紧凑展示参数
  private compactImageMaxHeight: number = 100
  private compactImageContainerWidth: number = 180
  private compactImageGap: number = 6
  private cachedDisplayContent: string = ''
  private cachedHasDisplayAttachments: boolean = false
  private cachedHasPreviewTextContent: boolean = false
  private cachedHasMessageTextContent: boolean = false
  private cachedHasToolbarPayload: boolean = false
  private cachedCurrentMessageModelIconResourcePath: string = ''
  private cachedReadonlyMessageContent: string = ''
  private cachedReadonlyReasoningContent: string = ''
  private cachedReadonlyTranslatedText: string = ''
  private cachedHasHtmlSegments: boolean = false
  private cachedContentSegments: ContentSegment[] = []
  private cachedPreviewImageEntries: ImageAttachmentEntry[] = []
  private cachedMessageImageEntries: ImageAttachmentEntry[] = []
  private cachedMessageFileAttachments: MessageAttachment[] = []
  private cachedPreviewImageGridRows: number[] = []
  private cachedMessageImageGridRows: number[] = []
  private derivedCacheSignature: string = ''

  @Event onRegenerate: () => void = () => {}
  @Event onCopy: () => void = () => {}
  @Event onDelete: () => void = () => {}
  @Event onEdit: () => void = () => {}
  @Event onCancelEdit: () => void = () => {}  // 取消编辑回调
  @Event onShareMessage: () => void = () => {}
  @Event onTranslate: (content: string, targetLang: string, callback: (result: string, errorMessage: string) => void) => void = () => {}
  @Event onTranslationUpdated: (messageId: string, translatedText: string, translatedLang: string) => void =
    (_messageId: string, _translatedText: string, _translatedLang: string): void => {}
  // 图片点击预览回调
  @Event onImageClick: (images: Array<string>, index: number) => void = () => {}
  @Event onFileAttachmentClick: (attachment: MessageAttachment) => void = (_attachment: MessageAttachment): void => {}
  @Event onOpenLink: (title: string, url: string) => void = () => {}
  @Event onOpenMap: (visualizationJson: string) => void = (_visualizationJson: string): void => {}
  // TTS朗读回调
  @Event onTTS: (messageId: string, content: string) => void = () => {}
  @Event onTTSStop: () => void = () => {}
  @Event onAskUserAnswer: (toolCallId: string, answerJson: string) => void =
    (_toolCallId: string, _answerJson: string): void => {}
  @Event onAskUserOpen: (toolCallId: string) => void = (_toolCallId: string): void => {}
  // 多选模式回调
  @Event onSelect: (messageId: string) => void = () => {}
  @Event onEnterMultiSelect: (messageId: string) => void = () => {}
  @Event onSwitchVersion: (delta: number) => void = (_delta: number): void => {}

  // 支持的翻译语言列表
  private translateLanguages: TranslateLanguage[] = [
    { code: 'zh-CN', name: 'Chinese', nativeName: '简体中文' },
    { code: 'en', name: 'English', nativeName: 'English' },
    { code: 'zh-TW', name: 'Traditional Chinese', nativeName: '繁體中文' },
    { code: 'ja', name: 'Japanese', nativeName: '日本語' },
    { code: 'ko', name: 'Korean', nativeName: '한국어' },
    { code: 'fr', name: 'French', nativeName: 'Français' },
    { code: 'de', name: 'German', nativeName: 'Deutsch' },
    { code: 'it', name: 'Italian', nativeName: 'Italiano' },
    { code: 'es', name: 'Spanish', nativeName: 'Español' }
  ]

  // 获取当前消息模型图标文件名（空字符串表示无可用图标）
  private getCurrentMessageModelIconPath(): string {
    // 优先用 modelId → 回退到当前会话模型 ID → 最后回退到 modelName
    let id = this.message.modelId
    if (id === '' || id === undefined) {
      id = this.currentModelId
    }
    if (id === '' || id === undefined) {
      id = this.message.modelName
    }
    if (id === '' || id === undefined) {
      return ''
    }
    return getModelIconPath(id, '', '')
  }

  // 获取当前消息模型图标资源路径（空字符串表示无可用图标）
  private computeCurrentMessageModelIconResourcePath(): string {
    const iconPath = this.getCurrentMessageModelIconPath()
    if (iconPath === '') {
      return ''
    }
    return buildIconResourcePath(iconPath)
  }

  private getPrimaryTouchPoint(event: TouchEvent): TouchObject | null {
    if (event.changedTouches && event.changedTouches.length > 0) {
      return event.changedTouches[0]
    }
    if (event.touches && event.touches.length > 0) {
      return event.touches[0]
    }
    return null
  }

  private resetMultiSelectTouchState(): void {
    this.multiSelectTouchActive = false
    this.multiSelectTouchStartX = 0
    this.multiSelectTouchStartY = 0
  }

  private handleMultiSelectTouch(event: TouchEvent): void {
    if (!this.isMultiSelectMode) {
      return
    }
    const touchPoint = this.getPrimaryTouchPoint(event)
    switch (event.type) {
      case TouchType.Down:
        if (touchPoint === null) {
          this.resetMultiSelectTouchState()
          return
        }
        this.multiSelectTouchStartX = touchPoint.x
        this.multiSelectTouchStartY = touchPoint.y
        this.multiSelectTouchActive = true
        break
      case TouchType.Move:
        if (!this.multiSelectTouchActive || touchPoint === null) {
          return
        }
        if (Math.abs(touchPoint.x - this.multiSelectTouchStartX) > MessageBubble.MULTI_SELECT_TAP_THRESHOLD_VP ||
          Math.abs(touchPoint.y - this.multiSelectTouchStartY) > MessageBubble.MULTI_SELECT_TAP_THRESHOLD_VP) {
          this.multiSelectTouchActive = false
        }
        break
      case TouchType.Up:
        if (this.multiSelectTouchActive && touchPoint !== null &&
          Math.abs(touchPoint.x - this.multiSelectTouchStartX) <= MessageBubble.MULTI_SELECT_TAP_THRESHOLD_VP &&
          Math.abs(touchPoint.y - this.multiSelectTouchStartY) <= MessageBubble.MULTI_SELECT_TAP_THRESHOLD_VP) {
          event.stopPropagation()
          this.onSelect(this.message.id)
        }
        this.resetMultiSelectTouchState()
        break
      case TouchType.Cancel:
        this.resetMultiSelectTouchState()
        break
      default:
        break
    }
  }

  aboutToAppear(): void {
    ensureManuscriptFonts()
    this.syncMessageScopedState()
    this.syncDerivedRenderCaches()
    this.isReasoningExpanded = false
    this.expandedTimelineReasoningIds = []
    this.collapsedTimelineReasoningIds = []
  }

  // 消息状态变化回调（优化跳动点动画性能）
  @Monitor('message')
  onMessageStateChange(): void {
    this.syncMessageScopedState()
    this.syncDerivedRenderCaches()
  }

  @Monitor('contentRenderSignature')
  onContentRenderSignatureChange(): void {
    this.syncMessageScopedState()
    this.syncDerivedRenderCaches()
  }

  @Monitor('previewContent')
  onPreviewContentChange(): void {
    this.syncDerivedRenderCaches()
  }

  @Monitor('previewAttachments')
  onPreviewAttachmentsChange(): void {
    this.syncDerivedRenderCaches()
  }

  @Monitor('isEditing')
  onIsEditingChange(): void {
    this.syncDerivedRenderCaches()
  }

  @Monitor('currentModelId')
  onCurrentModelIdChange(): void {
    this.syncDerivedRenderCaches()
  }

  @Monitor('translatedText')
  onTranslatedTextChange(): void {
    this.syncDerivedRenderCaches()
  }

  private syncMessageScopedState(): void {
    if (this.message.id === this.boundMessageId) {
      return
    }
    this.boundMessageId = this.message.id
    this.resetMessageScopedState()
  }

  private resetMessageScopedState(): void {
    this.translationRequestToken++
    this.isReasoningExpanded = false
    this.expandedTimelineReasoningIds = []
    this.collapsedTimelineReasoningIds = []
    this.translatedText = this.message.translatedText
    this.isTranslating = false
    this.showTranslation = this.message.translatedText !== ''
    this.isTranslationExpanded = true
    this.currentTranslateLang = this.message.translatedLang
    this.showCacheHitPopup = false
    this.showLatexPreview = false
    this.latexPreviewText = ''
    this.latexPreviewPixelMap = undefined
    this.latexPreviewImageWidth = 0
    this.latexPreviewImageHeight = 0
  }

  private buildAttachmentSignature(attachments: MessageAttachment[]): string {
    if (attachments.length <= 0) {
      return '0'
    }
    const segments: string[] = []
    for (let i = 0; i < attachments.length; i++) {
      const attachment = attachments[i]
      segments.push([
        attachment.id,
        attachment.type,
        attachment.name,
        attachment.filePath,
        attachment.mimeType,
        attachment.size.toString(),
        attachment.base64Data.length.toString()
      ].join(':'))
    }
    return segments.join('|')
  }

  private buildDerivedCacheSignature(): string {
    return [
      this.message.id,
      this.message.role,
      this.message.timestamp.toString(),
      this.message.modelId,
      this.message.modelName,
      this.message.billingEnabled ? '1' : '0',
      this.message.billingCurrency,
      this.message.estimatedInputTokens.toString(),
      this.message.estimatedOutputTokens.toString(),
      this.message.estimatedCost.toString(),
      this.message.uncachedInputTokens.toString(),
      this.message.cacheReadTokens.toString(),
      this.message.cacheWriteTokens.toString(),
      this.message.content,
      this.message.reasoningContent,
      this.message.isGenerating ? '1' : '0',
      this.message.isSearching ? '1' : '0',
      this.message.contextCompactionState,
      this.currentModelId,
      this.isEditing ? '1' : '0',
      this.previewContent,
      this.translatedText,
      this.message.documentToolHint,
      this.buildAttachmentSignature(this.previewAttachments),
      this.buildAttachmentSignature(this.message.attachments)
    ].join('\u0001')
  }

  private ensureDerivedRenderCaches(): void {
    const nextSignature = this.buildDerivedCacheSignature()
    if (nextSignature === this.derivedCacheSignature) {
      return
    }
    this.derivedCacheSignature = nextSignature
    this.syncDerivedRenderCaches()
  }

  private syncDerivedRenderCaches(): void {
    this.cachedDisplayContent = this.computeDisplayContent()
    this.cachedHasDisplayAttachments = this.isEditing
      ? this.hasRenderableAttachments(this.previewAttachments)
      : this.hasRenderableAttachments(this.message.attachments)
    this.cachedHasPreviewTextContent = this.cachedDisplayContent.length > 0
    this.cachedHasMessageTextContent = this.message.content.trim().length > 0
    this.cachedHasToolbarPayload = this.cachedHasMessageTextContent || this.message.hasAttachments()
    this.cachedCurrentMessageModelIconResourcePath = this.computeCurrentMessageModelIconResourcePath()
    this.cachedReadonlyMessageContent = this.convertTaskListToReadonly(this.message.content)
    this.cachedReadonlyReasoningContent = this.convertTaskListToReadonly(this.message.reasoningContent)
    this.cachedReadonlyTranslatedText = this.convertTaskListToReadonly(this.translatedText)
    this.cachedHasHtmlSegments = !this.message.isGenerating && this.hasHtmlBlocks(this.message.content)
    this.cachedContentSegments = this.cachedHasHtmlSegments ? this.splitContentToSegments(this.message.content) : []
    this.cachedPreviewImageEntries = this.buildImageAttachmentEntries(this.previewAttachments)
    this.cachedMessageImageEntries = this.buildImageAttachmentEntries(this.message.attachments)
    this.cachedMessageFileAttachments = this.getFileAttachments(this.message.attachments)
    this.cachedPreviewImageGridRows = this.buildImageGridRows(this.cachedPreviewImageEntries.length)
    this.cachedMessageImageGridRows = this.buildImageGridRows(this.cachedMessageImageEntries.length)
  }

  // 流式正文渲染：必须在 Builder 内直接访问 this.message.content（@Trace 字段），
  // 才能让当前 Markdown 组件的 text 建立响应式依赖，流式增量追加才会实时刷新。
  // 若把 content 在父 Builder 提取成 string 再传参，依赖会在参数边界断链，表现为正文流式不刷新。
  @Builder
  MessageContentMarkdown() {
    ChatMarkdownRenderer({
      content: this.message.content,
      isInputEnded: !this.message.isGenerating,
      incrementalAnalysis: this.message.isGenerating,
      useCangjieComponent: true,
      chatFontSize: this.chatFontSize,
      latexFontSize: this.chatFontSize,
      textTypeface: this.chatBubbleTypeface,
      themeRenderKey: this.themeRenderKey,
      onOpenLink: (title: string, url: string): void => {
        this.openWebSheetForLink(title, url)
      },
      onImageClick: (src: string): void => {
        this.onImageClick([src], 0)
      },
      onCopyText: (text: string): void => {
        this.copyToClipboard(text)
      },
      onCopyCode: (code: string,): void => {
        this.copyToClipboard(code)
      },
      onCodeFullScreen: (code: string, _codeType: string): void => {
        this.copyToClipboard(code)
      }
    })
      .constraintSize({ maxWidth: '100%' })
      .backgroundColor(Color.Transparent)
  }

  // 流式推理内容渲染：同样需在 Builder 内直接访问 this.message.reasoningContent（@Trace 字段）。
  @Builder
  ReasoningMarkdown() {
    ChatMarkdownRenderer({
      content: this.message.reasoningContent,
      isInputEnded: !this.message.isGenerating,
      incrementalAnalysis: this.message.isGenerating,
      useCangjieComponent: true,
      chatFontSize: this.chatFontSize,
      compact: true,
      latexFontSize: this.chatFontSize,
      textColorOverride: getAppUiState().themeTextSecondary,
      titleColorOverride: getAppUiState().themeTextSecondary,
      themeRenderKey: this.themeRenderKey,
      onOpenLink: (title: string, url: string): void => {
        this.openWebSheetForLink(title, url)
      },
      onImageClick: (src: string): void => {
        this.onImageClick([src], 0)
      },
      onCopyText: (text: string): void => {
        this.copyToClipboard(text)
      },
      onCopyCode: (code: string): void => {
        this.copyToClipboard(code)
      },
      onCodeFullScreen: (code: string, _codeType: string): void => {
        this.copyToClipboard(code)
      }
    })
      .constraintSize({ maxWidth: '100%' })
      .backgroundColor(Color.Transparent)
  }

  // 静态内容渲染（翻译结果 / HTML 分段正文）：仅在非流式时出现，传参不涉及响应式断链问题。
  @Builder
  StaticMarkdown(content: string, compact: boolean, textColorOverride: string = '', titleColorOverride: string = '',
    useChatBubbleTypeface: boolean = false) {
    ChatMarkdownRenderer({
      content: content,
      isInputEnded: true,
      incrementalAnalysis: false,
      useCangjieComponent: true,
      chatFontSize: this.chatFontSize,
      compact: compact,
      latexFontSize: this.chatFontSize,
      textColorOverride: textColorOverride,
      titleColorOverride: titleColorOverride,
      textTypeface: useChatBubbleTypeface ? this.chatBubbleTypeface : 'HarmonyOS Sans',
      themeRenderKey: this.themeRenderKey,
      onOpenLink: (title: string, url: string): void => {
        this.openWebSheetForLink(title, url)
      },
      onImageClick: (src: string): void => {
        this.onImageClick([src], 0)
      },
      onCopyText: (text: string): void => {
        this.copyToClipboard(text)
      },
      onCopyCode: (code: string): void => {
        this.copyToClipboard(code)
      },
      onCodeFullScreen: (code: string, _codeType: string): void => {
        this.copyToClipboard(code)
      }
    })
      .constraintSize({ maxWidth: '100%' })
      .backgroundColor(Color.Transparent)
  }

  // 计算是否应该显示推理内容（生成中自动展开）
  private get shouldShowReasoning(): boolean {
    return this.isReasoningExpanded || (this.message.isGenerating && this.message.reasoningContent.length > 0)
  }

  private isPlainManuscriptContent(content: string): boolean {
    if (content === '') {
      return true
    }
    return !/(^|\n)\s{0,3}(#{1,6}|>|[-+*]|[0-9]+[.)])\s|[`\[\]_*~]|https?:\/\//m.test(content)
  }

  build() {
    Column() {
      // 编辑状态标签（点击可取消编辑）
      if (this.isEditing) {
        Row() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(10)
            .fontColor([this.themePrimary])

          Text($r('app.string.editing_message'))
            .fontSize(10)
            .fontColor(this.themePrimary)
            .margin({ left: 4 })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.themeAiBubble)
        .borderRadius(10)
        .margin({ bottom: 4 })
        .alignSelf(ItemAlign.End)
        .onClick(() => {
          this.onCancelEdit()
        })
      }

      if (this.message.role === MessageRole.USER) {
        if (this.isManuscriptMode) {
          this.ManuscriptUserMessage()
        } else {
          this.UserMessage()
        }
      } else {
        this.AssistantMessage()
      }
    }
    .width('100%')
    // 新消息入场动画：用户消息从右侧滑入，AI消息从左侧滑入
    .transition(
      TransitionEffect.asymmetric(
        // 入场：滑入 + 淡入
        TransitionEffect.translate(this.isManuscriptMode ? { y: 12 } : {
          x: this.message.role === MessageRole.USER ? 30 : -30
        }).combine(TransitionEffect.OPACITY),
        // 退场：仅淡出
        TransitionEffect.OPACITY
      ).animation({ duration: this.isManuscriptMode ? 500 : 250, curve: Curve.EaseOut })
    )
    .bindSheet($$this.showLatexPreview, this.LatexPreviewSheet(), {
      height: '25%',
      detents: ['25%'],
      dragBar: true,
      showClose: false,
      maskColor: '#00000000'
    })
  }

  @Builder
  ManuscriptUserMessage() {
    Column({ space: 5 }) {
      Text($r('app.string.manuscript_you'))
        .fontFamily(MANUSCRIPT_BODY_FONT)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.manuscriptAccentDeep)
        .letterSpacing(2)
        .width('100%')
        .textAlign(TextAlign.End)

      if (this.hasDisplayAttachments()) {
        Row() {
          if (this.isEditing) {
            this.PreviewAttachments()
          } else {
            this.UserAttachments()
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }

      if (this.getDisplayContent().length > 0) {
        Text(this.getDisplayContent())
          .fontFamily(MANUSCRIPT_BODY_FONT)
          .fontSize(15)
          .fontStyle(FontStyle.Italic)
          .fontColor(getAppUiState().themeTextPrimary)
          .lineHeight(25)
          .textAlign(TextAlign.End)
          .width('100%')
      }

      if (this.shouldShowUserToolbar()) {
        Row({ space: 0 }) {
          if (this.shouldShowVersionSwitcher()) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(this.getMessageToolbarIconSize())
                .fontColor([this.canSwitchToPreviousVersion() ? this.manuscriptAccentDeep :
                  getAppUiState().themeDivider])
            }
            .width(this.getMessageToolbarButtonSize())
            .height(this.getMessageToolbarButtonSize())
            .padding(0)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              if (this.canSwitchToPreviousVersion()) {
                this.onSwitchVersion(-1)
              }
            })

            Text(`${this.message.versionIndex + 1}/${this.message.versionCount}`)
              .fontFamily(MANUSCRIPT_BODY_FONT)
              .fontSize(11)
              .fontColor(this.manuscriptAccentDeep)
              .width(this.getMessageToolbarButtonSize())
              .textAlign(TextAlign.Center)

            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(this.getMessageToolbarIconSize())
                .fontColor([this.canSwitchToNextVersion() ? this.manuscriptAccentDeep :
                  getAppUiState().themeDivider])
            }
            .width(this.getMessageToolbarButtonSize())
            .height(this.getMessageToolbarButtonSize())
            .padding(0)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              if (this.canSwitchToNextVersion()) {
                this.onSwitchVersion(1)
              }
            })

            Divider()
              .vertical(true)
              .height(14)
              .color(getAppUiState().themeDivider)
              .margin(0)
          }

          if (this.canCopyMessageContent()) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.checkmark_square_on_square'))
                .fontSize(this.getMessageToolbarIconSize())
                .fontColor([this.manuscriptAccentDeep])
            }
            .width(this.getMessageToolbarButtonSize())
            .height(this.getMessageToolbarButtonSize())
            .padding(0)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.handleCopy()
            })
          }

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(this.getMessageToolbarIconSize())
              .fontColor([this.manuscriptAccentDeep])
          }
          .width(this.getMessageToolbarButtonSize())
          .height(this.getMessageToolbarButtonSize())
          .padding(0)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onRegenerate()
          })

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.square_and_pencil'))
              .fontSize(this.getMessageToolbarIconSize())
              .fontColor([this.manuscriptAccentDeep])
          }
          .width(this.getMessageToolbarButtonSize())
          .height(this.getMessageToolbarButtonSize())
          .padding(0)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onEdit()
          })

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
              .fontSize(this.getMessageToolbarIconSize())
              .fontColor([this.manuscriptAccentDeep])
          }
          .width(this.getMessageToolbarButtonSize())
          .height(this.getMessageToolbarButtonSize())
          .padding(0)
          .backgroundColor(Color.Transparent)
          .bindMenu(this.UserMoreMenu(), {
            systemMaterial: new uiMaterial.ImmersiveMaterial({
              style: uiMaterial.ImmersiveStyle.THICK
            })
          })
        }
        .height(this.getMessageToolbarHeight())
        .padding({ left: 3, right: 3 })
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Center)
        .borderRadius(0)
        .border({ width: 0, color: Color.Transparent })
        .clip(false)
      }
    }
    .width('100%')
    .padding({ left: 34, right: 34 })
    .alignItems(HorizontalAlign.End)
    .onTouch((event: TouchEvent) => {
      this.handleMultiSelectTouch(event)
    })
  }

  @Builder
  ManuscriptAssistantMessage() {
    Row() {
      if (this.isMultiSelectMode && this.isSelected) {
        Column()
          .width(2)
          .backgroundColor(this.manuscriptAccentDeep)
          .alignSelf(ItemAlign.Stretch)
          .margin({ right: 8 })
      }

      Column({ space: 8 }) {
        if (this.hasRenderableAttachments(this.message.attachments)) {
          this.AssistantAttachments()
        }

        if (!getAppUiState().chatOrderedResponseHistory &&
          this.message.contextCompactionState !== ContextCompactionUiState.NONE) {
          this.ContextCompactionStatusBar(this.message.contextCompactionState)
        }

        if (this.message.content.length === 0 &&
          this.message.contextCompactionState === ContextCompactionUiState.NONE &&
          (this.message.isGenerating || this.message.isSearching)) {
          Text('…')
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontSize(15)
            .fontColor(getAppUiState().themeTextTertiary)
        } else if (this.isPlainManuscriptContent(this.message.content)) {
          Text(this.message.content)
            .width('100%')
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontSize(15)
            .fontWeight(FontWeight.Regular)
            .fontColor(getAppUiState().themeTextPrimary)
            .lineHeight(25)
            .textAlign(TextAlign.JUSTIFY)
        } else {
          this.MessageContentMarkdown()
        }
      }
      .layoutWeight(1)
      .padding({ left: 34, right: 34 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .onTouch((event: TouchEvent) => {
      this.handleMultiSelectTouch(event)
    })
  }

  @Builder
  SubAgentPreviewSheet() {
    SubAgentPreviewSheetContent({
      onClose: (): void => {
        this.showSubAgentPreviewSheet = false
      }
    })
  }

  @Builder
  LatexPreviewSheet() {
    Column() {
      ImmersiveSheetHeader({
        title: '公式预览',
        onLeadingClick: (): void => {
          this.showLatexPreview = false
        }
      })

      if (this.latexPreviewPixelMap !== undefined) {
        Scroll() {
          Row() {
            Image(this.latexPreviewPixelMap as image.PixelMap)
              .width(this.latexPreviewImageWidth * 1.5)
              .height(this.latexPreviewImageHeight * 1.5)
              .objectFit(ImageFit.Contain)
          }
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .justifyContent(FlexAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Auto)
      } else {
        Blank()
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  // 处理翻译
  private handleTranslate(targetLang: string): void {
    if (this.isTranslating) {
      return
    }
    const requestToken = ++this.translationRequestToken
    const requestMessageId = this.message.id
    this.isTranslating = true
    this.showTranslation = true
    this.isTranslationExpanded = true
    this.translatedText = ''
    this.currentTranslateLang = targetLang

    this.onTranslate(this.message.content, targetLang, (result: string, errorMessage: string) => {
      if (requestToken !== this.translationRequestToken || this.message.id !== requestMessageId) {
        return
      }
      this.translatedText = result
      this.isTranslating = false
      if (result !== '') {
        this.message.translatedText = result
        this.message.translatedLang = targetLang
        this.onTranslationUpdated(this.message.id, this.message.translatedText, this.message.translatedLang)
      }
      if (result === '' && errorMessage !== '') {
        this.translatedText = this.message.translatedText
        this.currentTranslateLang = this.message.translatedLang
        this.showTranslation = this.message.translatedText !== ''
        showToast(this.getUIContext(), errorMessage, 3000)
      }
    })
  }

  // 获取显示内容（编辑模式下使用预览内容）
  private computeDisplayContent(): string {
    if (this.isEditing) {
      return this.previewContent
    }
    return this.message.content
  }

  private getDisplayContent(): string {
    this.ensureDerivedRenderCaches()
    return this.cachedDisplayContent
  }

  // 检查内容是否包含完整的 HTML 代码块
  private hasHtmlBlocks(content: string): boolean {
    return /```html?\s*\n[\s\S]*?```/.test(content)
  }

  // 将内容按 HTML 代码块边界分段，用于内联预览渲染
  private splitContentToSegments(content: string): ContentSegment[] {
    const segments: ContentSegment[] = []
    const pattern = /```html?\s*\n([\s\S]*?)```/g
    let lastIndex = 0
    let match = pattern.exec(content)

    while (match !== null) {
      const matchIndex = match.index
      // 添加 HTML 代码块之前的文本段
      if (matchIndex > lastIndex) {
        const textContent = content.substring(lastIndex, matchIndex)
        if (textContent.trim().length > 0) {
          segments.push({
            isHtml: false,
            renderContent: this.convertTaskListToReadonly(textContent)
          } as ContentSegment)
        }
      }
      // 添加 HTML 代码块段
      segments.push({ isHtml: true, renderContent: match[1] } as ContentSegment)
      lastIndex = matchIndex + match[0].length
      match = pattern.exec(content)
    }

    // 添加最后一个 HTML 代码块之后的剩余文本
    if (lastIndex < content.length) {
      const remaining = content.substring(lastIndex)
      if (remaining.trim().length > 0) {
        segments.push({
          isHtml: false,
          renderContent: this.convertTaskListToReadonly(remaining)
        } as ContentSegment)
      }
    }

    return segments
  }

  // 是否有显示附件（编辑模式下使用预览附件）
  private hasDisplayAttachments(): boolean {
    this.ensureDerivedRenderCaches()
    return this.cachedHasDisplayAttachments
  }

  // 获取附件图片数据源（优先 file://，其次 base64）
  private getAttachmentImageSource(attachment: MessageAttachment): string {
    if (attachment.filePath !== '') {
      return 'file://' + attachment.filePath
    }
    if (attachment.base64Data !== '') {
      return `data:${attachment.mimeType};base64,${attachment.base64Data}`
    }
    return ''
  }

  // 提取图片附件并保留原始索引（用于正确映射预览索引）
  private buildImageAttachmentEntries(attachments: MessageAttachment[]): ImageAttachmentEntry[] {
    const imageEntries: ImageAttachmentEntry[] = []
    for (let i = 0; i < attachments.length; i++) {
      if (attachments[i].type === AttachmentType.IMAGE) {
        imageEntries.push({
          attachment: attachments[i],
          originalIndex: i
        })
      }
    }
    return imageEntries
  }

  private getFileAttachments(attachments: MessageAttachment[]): MessageAttachment[] {
    const fileAttachments: MessageAttachment[] = []
    for (let i = 0; i < attachments.length; i++) {
      if (attachments[i].type === AttachmentType.FILE &&
        !isPythonSandboxFileAttachmentId(attachments[i].id)) {
        fileAttachments.push(attachments[i])
      }
    }
    return fileAttachments
  }

  private hasRenderableAttachments(attachments: MessageAttachment[]): boolean {
    for (let i = 0; i < attachments.length; i++) {
      if (attachments[i].type === AttachmentType.IMAGE ||
        (attachments[i].type === AttachmentType.FILE &&
          !isPythonSandboxFileAttachmentId(attachments[i].id))) {
        return true
      }
    }
    return false
  }

  private isPdfAttachment(attachment: MessageAttachment): boolean {
    const mimeType = attachment.mimeType.toLowerCase()
    const name = attachment.name.toLowerCase()
    return mimeType === 'application/pdf' || name.endsWith('.pdf')
  }

  private getFileAttachmentSymbol(attachment: MessageAttachment): Resource {
    return this.isPdfAttachment(attachment) ? $r('sys.symbol.pdf_doc') : $r('sys.symbol.doc')
  }

  private getPreviewImageEntries(): ImageAttachmentEntry[] {
    this.ensureDerivedRenderCaches()
    return this.cachedPreviewImageEntries
  }

  private getPreviewImageGridRows(): number[] {
    this.ensureDerivedRenderCaches()
    return this.cachedPreviewImageGridRows
  }

  private hasPreviewTextContent(): boolean {
    this.ensureDerivedRenderCaches()
    return this.cachedHasPreviewTextContent
  }

  private getMessageImageEntries(): ImageAttachmentEntry[] {
    this.ensureDerivedRenderCaches()
    return this.cachedMessageImageEntries
  }

  private getMessageImageGridRows(): number[] {
    this.ensureDerivedRenderCaches()
    return this.cachedMessageImageGridRows
  }

  private getMessageFileAttachments(): MessageAttachment[] {
    this.ensureDerivedRenderCaches()
    return this.cachedMessageFileAttachments
  }

  private hasMessageTextContent(): boolean {
    this.ensureDerivedRenderCaches()
    return this.cachedHasMessageTextContent
  }

  private hasToolbarPayload(): boolean {
    this.ensureDerivedRenderCaches()
    return this.cachedHasToolbarPayload
  }

  private getCurrentMessageModelIconResourcePath(): string {
    this.ensureDerivedRenderCaches()
    return this.cachedCurrentMessageModelIconResourcePath
  }

  private hasHtmlSegments(): boolean {
    this.ensureDerivedRenderCaches()
    return this.cachedHasHtmlSegments
  }

  private getContentSegments(): ContentSegment[] {
    this.ensureDerivedRenderCaches()
    return this.cachedContentSegments
  }

  private getReadonlyMessageContent(): string {
    this.ensureDerivedRenderCaches()
    return this.cachedReadonlyMessageContent
  }

  private getReadonlyReasoningContent(): string {
    this.ensureDerivedRenderCaches()
    return this.cachedReadonlyReasoningContent
  }

  private getReadonlyTranslatedText(): string {
    this.ensureDerivedRenderCaches()
    return this.cachedReadonlyTranslatedText
  }

  private shouldShowUserToolbar(): boolean {
    return !this.isMultiSelectMode && !this.isEditing && this.hasToolbarPayload()
  }

  private shouldShowDocumentToolHint(): boolean {
    return !this.isEditing && this.message.role === MessageRole.USER && this.message.documentToolHint.trim() !== ''
  }

  private shouldShowAssistantToolbar(): boolean {
    return shouldShowAssistantMessageToolbar(this.message, this.isMultiSelectMode)
  }

  private shouldShowEstimatedCost(): boolean {
    return this.message.role === MessageRole.ASSISTANT &&
      this.message.billingEnabled &&
      !this.message.isGenerating &&
      this.message.billingCurrency !== ''
  }

  private getEstimatedCostText(): string {
    return `${formatBillingAmount(this.message.billingCurrency, this.message.estimatedCost)} ` +
      this.message.billingCurrency
  }

  private getCacheHitText(): string {
    const percent = formatCacheHitPercent(
      this.message.uncachedInputTokens,
      this.message.cacheReadTokens,
      this.message.cacheWriteTokens
    )
    if (percent === null) {
      return '--%'
    }
    return `${percent}%`
  }

  private hasAskUserToolCall(): boolean {
    for (let i = 0; i < this.message.toolCalls.length; i++) {
      if (this.isAskUserToolCall(this.message.toolCalls[i])) {
        return true
      }
    }
    return false
  }

  private canCopyMessageContent(): boolean {
    return this.hasMessageTextContent()
  }

  private canTranslateMessageContent(): boolean {
    return this.hasMessageTextContent()
  }

  private canReadMessageContent(): boolean {
    return getAppUiState().ttsEnabled && this.hasMessageTextContent()
  }

  private shouldShowVersionSwitcher(): boolean {
    return !this.isMultiSelectMode && !this.isEditing && this.message.versionCount > 1
  }

  private canSwitchToPreviousVersion(): boolean {
    return this.message.versionIndex > 0
  }

  private canSwitchToNextVersion(): boolean {
    return this.message.versionIndex < this.message.versionCount - 1
  }

  private normalizeToolFunctionName(raw: string): string {
    const value = raw as string | null | undefined
    if (value === undefined || value === null) {
      return ''
    }
    return value.trim().toLowerCase().replace(/[\s\-]+/g, '_')
  }

  private isAskUserToolCall(toolCall: ToolCall): boolean {
    const normalized = this.normalizeToolFunctionName(toolCall.functionName)
    return normalized === 'ask_user' || normalized === 'user_input' || normalized === 'ask'
  }

  private isMathChartToolCall(toolCall: ToolCall): boolean {
    const normalizedFunctionName = this.normalizeToolFunctionName(toolCall.functionName)
    const normalizedToolId = this.normalizeToolFunctionName(toolCall.toolId)
    return normalizedFunctionName === MATH_CHART_TOOL_ID || normalizedToolId === MATH_CHART_TOOL_ID
  }

  private isMapSearchToolCall(toolCall: ToolCall): boolean {
    const normalizedFunctionName = this.normalizeToolFunctionName(toolCall.functionName)
    const normalizedToolId = this.normalizeToolFunctionName(toolCall.toolId)
    return normalizedFunctionName === MAP_SEARCH_ROUTE_TOOL_ID || normalizedToolId === MAP_SEARCH_ROUTE_TOOL_ID
  }

  // 按工具身份（规范化函数名 + 来源标签）合并同一消息内的多次调用；
  // 同一消息的 AskUser 调用合并成一个结果栏，被隐藏的调用（如已有搜索引用的联网搜索）不入组
  private containsToolCallId(toolCallIds: string[], toolCallId: string): boolean {
    if (toolCallIds.length === 0) {
      return true
    }
    for (let i = 0; i < toolCallIds.length; i++) {
      if (toolCallIds[i] === toolCallId) {
        return true
      }
    }
    return false
  }

  private getToolCallRenderGroups(toolCallIds: string[] = []): ToolCallRenderGroup[] {
    const groups: ToolCallRenderGroup[] = []
    const groupIndex = new Map<string, ToolCallRenderGroup>()
    let askGroup: ToolCallRenderGroup | undefined = undefined
    for (let i = 0; i < this.message.toolCalls.length; i++) {
      const toolCall = this.message.toolCalls[i]
      if (!this.containsToolCallId(toolCallIds, toolCall.id)) {
        continue
      }
      if (this.isAskUserToolCall(toolCall)) {
        if (askGroup === undefined) {
          askGroup = new ToolCallRenderGroup()
          askGroup.key = 'ask_group'
          askGroup.isAskUser = true
          groups.push(askGroup)
        }
        askGroup.askUserCalls.push(toolCall)
        continue
      }
      if (this.shouldHideToolCallCard(toolCall)) {
        continue
      }
      const identity = this.normalizeToolFunctionName(toolCall.functionName) + '|' + toolCall.sourceLabel.trim()
      let group = groupIndex.get(identity)
      if (group === undefined) {
        group = new ToolCallRenderGroup()
        group.key = 'tool_' + identity
        groupIndex.set(identity, group)
        groups.push(group)
      }
      // 按 toolCallId 关联结果：子智能体镜像的调用会与主循环的调用交错追加，
      // 位置配对会错位，必须用 id 配对
      const toolResult = this.findToolResultForCall(toolCall.id)
      group.entries.push(new ToolCallCardEntry(toolCall, toolResult))
      if (this.message.isGenerating && toolResult === null) {
        group.anyExecuting = true
      }
    }
    return groups
  }

  // 分组卡片的入参是本次 build 里临时创建的普通对象，不具备 @Trace 可观察性；
  // 把结果数量与执行状态编入 ForEach 键值，状态变化时重建卡片以保证刷新
  private buildToolCallRenderGroupKey(group: ToolCallRenderGroup, index: number): string {
    if (group.isAskUser) {
      let resolvedResults = 0
      for (let i = 0; i < group.askUserCalls.length; i++) {
        if (this.findToolResultForCall(group.askUserCalls[i].id) !== null) {
          resolvedResults++
        }
      }
      return group.key + '_' + group.askUserCalls.length.toString() + '_' + resolvedResults.toString() + '_' +
        index.toString()
    }
    let resolvedResults = 0
    for (let i = 0; i < group.entries.length; i++) {
      if (group.entries[i].toolResult !== null) {
        resolvedResults++
      }
    }
    return group.key + '_' + group.entries.length.toString() + '_' + resolvedResults.toString() +
      (group.anyExecuting ? '_e' : '_d') + '_' + index.toString()
  }

  private findToolResultForCall(toolCallId: string): ToolResult | null {
    for (let i = 0; i < this.message.toolResults.length; i++) {
      if (this.message.toolResults[i].toolCallId === toolCallId) {
        return this.message.toolResults[i]
      }
    }
    return null
  }

  private getToolResultContentForCall(toolCallId: string): string {
    const result = this.findToolResultForCall(toolCallId)
    return result !== null ? result.content : ''
  }

  private getAskUserResultContents(toolCalls: ToolCall[]): string[] {
    const contents: string[] = []
    for (let i = 0; i < toolCalls.length; i++) {
      contents.push(this.getToolResultContentForCall(toolCalls[i].id))
    }
    return contents
  }

  private areAllAskUserCallsAnswered(toolCalls: ToolCall[]): boolean {
    if (toolCalls.length === 0) {
      return false
    }
    for (let i = 0; i < toolCalls.length; i++) {
      if (this.findToolResultForCall(toolCalls[i].id) === null) {
        return false
      }
    }
    return true
  }

  private parseMathChartToolPayload(content: string): MathChartToolPayload | null {
    try {
      return JSON.parse(content) as MathChartToolPayload
    } catch (_error) {
      return null
    }
  }

  private getVChartPayloads(toolCallIds: string[] = []): MessageVChartPayload[] {
    const payloads: MessageVChartPayload[] = []
    for (let i = 0; i < this.message.toolCalls.length; i++) {
      const toolCall = this.message.toolCalls[i]
      if (!this.containsToolCallId(toolCallIds, toolCall.id)) {
        continue
      }
      if (!this.isMathChartToolCall(toolCall)) {
        continue
      }
      const toolResult = this.findToolResultForCall(toolCall.id)
      if (toolResult === null || toolResult.isError) {
        continue
      }
      const payload = this.parseMathChartToolPayload(toolResult.content)
      if (payload === null || payload.chart_spec === undefined) {
        continue
      }
      const specJson = payload.chart_spec.trim()
      if (specJson === '') {
        continue
      }
      payloads.push(new MessageVChartPayload(
        toolCall.id,
        specJson,
        payload.summary ?? '',
        payload.chartType ?? payload.chart_type ?? 'line'
      ))
    }
    return payloads
  }

  private getMapPayloads(toolCallIds: string[] = []): MessageMapPayload[] {
    const payloads: MessageMapPayload[] = []
    for (let i = 0; i < this.message.toolCalls.length; i++) {
      const toolCall = this.message.toolCalls[i]
      if (!this.containsToolCallId(toolCallIds, toolCall.id) || !this.isMapSearchToolCall(toolCall)) {
        continue
      }
      const toolResult = this.findToolResultForCall(toolCall.id)
      if (toolResult === null || toolResult.isError || toolResult.content.trim() === '') {
        continue
      }
      payloads.push(new MessageMapPayload(toolCall.id, toolResult.content))
    }
    return payloads
  }

  private openLatexPreview(text: string, pixelMap: image.PixelMap): boolean {
    const size = pixelMap.getImageInfoSync().size
    this.latexPreviewText = text
    this.latexPreviewPixelMap = pixelMap
    this.latexPreviewImageWidth = Math.max(1, px2vp(size.width))
    this.latexPreviewImageHeight = Math.max(1, px2vp(size.height))
    this.showLatexPreview = true
    return true
  }

  // 生成两列网格行索引
  private buildImageGridRows(imageCount: number): number[] {
    const rows: number[] = []
    if (imageCount <= 0) {
      return rows
    }
    const rowCount = Math.ceil(imageCount / 2)
    for (let i = 0; i < rowCount; i++) {
      rows.push(i)
    }
    return rows
  }

  // 清空翻译
  private clearTranslation(): void {
    this.translationRequestToken++
    this.showTranslation = false
    this.translatedText = ''
    this.isTranslating = false
    this.isTranslationExpanded = true
    this.currentTranslateLang = ''
    this.message.translatedText = ''
    this.message.translatedLang = ''
    this.onTranslationUpdated(this.message.id, '', '')
  }

  // 将 hex 颜色向白色方向混合（用于多选选中态）
  private lightenColor(hex: string, amount: number): string {
    let c = hex.replace('#', '')
    if (c.length === 3) {
      c = c[0] + c[0] + c[1] + c[1] + c[2] + c[2]
    }
    const r = Math.min(255, Math.round(parseInt(c.substring(0, 2), 16) + (255 - parseInt(c.substring(0, 2), 16)) * amount))
    const g = Math.min(255, Math.round(parseInt(c.substring(2, 4), 16) + (255 - parseInt(c.substring(2, 4), 16)) * amount))
    const b = Math.min(255, Math.round(parseInt(c.substring(4, 6), 16) + (255 - parseInt(c.substring(4, 6), 16)) * amount))
    return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`
  }

  private openWebSheetForLink(title: string, src: string): boolean {
    let url = src.trim()
    if (url === '') {
      return false
    }
    if (parsePythonSandboxFileUrl(url) !== '') {
      this.onOpenLink(title.trim(), url)
      return true
    }
    if (url.startsWith('mailto:') || url.startsWith('tel:')) {
      return false
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      // 兼容 markdown 中的裸域名链接
      if (url.indexOf('://') < 0) {
        url = 'https://' + url
      } else {
        return false
      }
    }

    this.onOpenLink(title.trim(), url)
    return true
  }

  @Builder
  VersionSwitcher() {
    Row({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(13)
        .fontColor([this.canSwitchToPreviousVersion() ? $r('app.color.text_tertiary') : $r('app.color.divider')])
        .onClick(() => {
          if (this.canSwitchToPreviousVersion()) {
            this.onSwitchVersion(-1)
          }
        })

      Text(`${this.message.versionIndex + 1}/${this.message.versionCount}`)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .width(34)
        .textAlign(TextAlign.Center)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontColor([this.canSwitchToNextVersion() ? $r('app.color.text_tertiary') : $r('app.color.divider')])
        .onClick(() => {
          if (this.canSwitchToNextVersion()) {
            this.onSwitchVersion(1)
          }
        })
    }
    .height(24)
    .padding({ left: 6, right: 6 })
    .borderRadius(12)
    .backgroundColor(this.themePrimaryLight)
  }

  private getMessageToolbarHeight(): number {
    return this.isManuscriptMode ? 30 : 34
  }

  private getMessageToolbarButtonSize(): number {
    return this.isManuscriptMode ? 26 : 28
  }

  private getMessageToolbarIconSize(): number {
    return this.isManuscriptMode ? 14 : 13
  }

  @Builder
  UserMessage() {
    Column() {
      Row() {
        Blank()

        Row() {
          Column() {
            // 图片附件显示
            if (this.hasDisplayAttachments()) {
              if (this.isEditing) {
                this.PreviewAttachments()
              } else {
                this.UserAttachments()
              }
            }

            if (this.shouldShowDocumentToolHint()) {
              this.DocumentToolHintBlock()
            }

            // 文本内容
            if (this.getDisplayContent().length > 0) {
              Text(this.getDisplayContent())
                .fontSize(this.chatFontSize)
                .fontFamily(this.chatBubbleTypeface)
                .fontColor(this.themeUserBubbleText)
                .lineHeight(Math.round(this.chatFontSize * 1.4))
                .textAlign(TextAlign.Start)
                .alignSelf(ItemAlign.Start)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding(this.hasDisplayAttachments() ? { left: 8, right: 8, top: 8, bottom: 8 } : { left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor(this.isMultiSelectMode && this.isSelected
            ? this.lightenColor(this.themeUserBubble, 0.15)
            : this.themeUserBubble)
          .borderRadius({
            topLeft: 20,
            topRight: 20,
            bottomLeft: 20,
            bottomRight: 6
          })
          .clip(true)
          .constraintSize({
            minWidth: this.hasDisplayAttachments() || this.shouldShowDocumentToolHint() ? 280 : 0,
            maxWidth: this.hasDisplayAttachments() || this.shouldShowDocumentToolHint() ? '88%' : '75%'
          })
          .border({
            width: this.isEditing ? 2 : (this.isMultiSelectMode && this.isSelected ? 1.2 : 0.5),
            color: this.isEditing
              ? '#FFFFFF'
              : (this.isMultiSelectMode && this.isSelected ? withColorAlpha(this.themePrimary, '66') : 'rgba(255, 255, 255, 0.15)')
          })
          .systemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR,
            materialColor: this.isMultiSelectMode && this.isSelected
              ? this.lightenColor(this.themeUserBubble, 0.15)
              : this.themeUserBubble
          }))

          // 多选选中竖条
          if (this.isMultiSelectMode && this.isSelected) {
            Column()
              .width(3)
              .borderRadius(1.5)
              .backgroundColor(this.themePrimary)
              .alignSelf(ItemAlign.Stretch)
              .margin({ left: 4 })
              .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
          }
        }
        .enabled(!this.isMultiSelectMode)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 用户消息工具栏
      if (this.shouldShowUserToolbar()) {
        Row() {
          Blank()

          Row({ space: 2 }) {
            if (this.shouldShowVersionSwitcher()) {
              Button({ type: ButtonType.Circle, stateEffect: false }) {
                SymbolGlyph($r('sys.symbol.chevron_left'))
                  .fontSize(13)
                  .fontColor([this.canSwitchToPreviousVersion()
                    ? $r('app.color.text_tertiary') : $r('app.color.divider')])
              }
              .width(this.getMessageToolbarButtonSize())
              .height(this.getMessageToolbarButtonSize())
              .padding(0)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                if (this.canSwitchToPreviousVersion()) {
                  this.onSwitchVersion(-1)
                }
              })

              Text(`${this.message.versionIndex + 1}/${this.message.versionCount}`)
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .width(this.getMessageToolbarButtonSize())
                .textAlign(TextAlign.Center)

              Button({ type: ButtonType.Circle, stateEffect: false }) {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(13)
                  .fontColor([this.canSwitchToNextVersion()
                    ? $r('app.color.text_tertiary') : $r('app.color.divider')])
              }
              .width(this.getMessageToolbarButtonSize())
              .height(this.getMessageToolbarButtonSize())
              .padding(0)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                if (this.canSwitchToNextVersion()) {
                  this.onSwitchVersion(1)
                }
              })

              Divider()
                .vertical(true)
                .height(14)
                .color($r('app.color.divider'))
                .margin({ left: 3, right: 3 })
            }

            // 复制
            if (this.canCopyMessageContent()) {
              Button({ type: ButtonType.Circle, stateEffect: false }) {
                SymbolGlyph($r('sys.symbol.checkmark_square_on_square'))
                  .fontSize(13)
                  .fontColor([$r('app.color.text_tertiary')])
              }
              .width(this.getMessageToolbarButtonSize())
              .height(this.getMessageToolbarButtonSize())
              .padding(0)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.handleCopy()
              })
            }

            // 重新生成
            Button({ type: ButtonType.Circle, stateEffect: false }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(13)
                .fontColor([$r('app.color.text_tertiary')])
            }
            .width(this.getMessageToolbarButtonSize())
            .height(this.getMessageToolbarButtonSize())
            .padding(0)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.onRegenerate()
            })

            // 编辑
            Button({ type: ButtonType.Circle, stateEffect: false }) {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(13)
                .fontColor([$r('app.color.text_tertiary')])
            }
            .width(this.getMessageToolbarButtonSize())
            .height(this.getMessageToolbarButtonSize())
            .padding(0)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.onEdit()
            })

            // 更多
            Button({ type: ButtonType.Circle, stateEffect: false }) {
              SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
                .fontSize(13)
                .fontColor([$r('app.color.text_tertiary')])
            }
            .width(this.getMessageToolbarButtonSize())
            .height(this.getMessageToolbarButtonSize())
            .padding(0)
            .backgroundColor(Color.Transparent)
            .bindMenu(this.UserMoreMenu(), {
              systemMaterial: new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.THICK
              })
            })
          }
          .height(this.getMessageToolbarHeight())
          .padding({ left: 3, right: 3 })
          .borderRadius(this.getMessageToolbarHeight() / 2)
          .clip(true)
          .alignItems(VerticalAlign.Center)
          .systemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR,
            interactive: true,
            lightEffect: { color: undefined }
          }))
        }
        .width('100%')
        .margin({ top: 6 })
      }

    }
    .width('100%')
    .alignItems(HorizontalAlign.End)
    .onTouch((event: TouchEvent) => {
      this.handleMultiSelectTouch(event)
    })
  }

  @Builder
  DocumentToolHintBlock() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.gearshape'))
        .fontSize(13)
        .fontColor(['rgba(255,255,255,0.86)'])

      Text(this.message.documentToolHint)
        .fontSize(12)
        .fontColor('rgba(255,255,255,0.92)')
        .maxLines(2)
        .wordBreak(WordBreak.BREAK_WORD)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .alignSelf(ItemAlign.Stretch)
    .padding({ left: 8, right: 9, top: 6, bottom: 6 })
    .backgroundColor('rgba(255,255,255,0.16)')
    .borderRadius(8)
    .margin({ bottom: this.getDisplayContent().length > 0 ? 6 : 0 })
  }

  // 编辑模式下的简化附件预览（无手势交互）
  @Builder
  PreviewAttachments() {
    Column() {
      if (this.getPreviewImageEntries().length === 1) {
        this.CompactPreviewSingleImage(
          this.getPreviewImageEntries()[0].attachment,
          this.hasPreviewTextContent() ? 6 : 0
        )
      } else if (this.getPreviewImageEntries().length > 1) {
        Column({ space: this.compactImageGap }) {
          ForEach(this.getPreviewImageGridRows(), (rowIndex: number) => {
            Row({ space: this.compactImageGap }) {
              this.CompactPreviewGridImage(this.getPreviewImageEntries()[rowIndex * 2].attachment)

              if (rowIndex * 2 + 1 < this.getPreviewImageEntries().length) {
                this.CompactPreviewGridImage(this.getPreviewImageEntries()[rowIndex * 2 + 1].attachment)
              } else {
                Blank()
                  .layoutWeight(1)
              }
            }
            .width(this.compactImageContainerWidth)
          }, (rowIndex: number) => rowIndex.toString())
        }
        .margin({ bottom: this.hasPreviewTextContent() ? 6 : 0 })
      }
    }
  }

  @Builder
  CompactPreviewSingleImage(attachment: MessageAttachment, bottomMargin: number) {
    if (this.getAttachmentImageSource(attachment) !== '') {
      Image(this.getAttachmentImageSource(attachment))
        .width(this.compactImageContainerWidth)
        .height(this.compactImageMaxHeight)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .clip(true)
        .margin({ bottom: bottomMargin })
    }
  }

  @Builder
  CompactPreviewGridImage(attachment: MessageAttachment) {
    if (this.getAttachmentImageSource(attachment) !== '') {
      Image(this.getAttachmentImageSource(attachment))
        .width('100%')
        .height(this.compactImageMaxHeight)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .clip(true)
        .layoutWeight(1)
    }
  }

  @Builder
  CompactSingleImage(attachment: MessageAttachment, attachmentIndex: number, bottomMargin: number) {
    if (this.getAttachmentImageSource(attachment) !== '') {
      Image(this.getAttachmentImageSource(attachment))
        .id('img_' + attachment.id)
        .width(this.compactImageContainerWidth)
        .height(this.compactImageMaxHeight)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .clip(true)
        .margin({ bottom: bottomMargin })
        .onClick(() => {
          this.handleImagePreview(attachmentIndex)
        })
    }
  }

  @Builder
  CompactGridImage(attachment: MessageAttachment, attachmentIndex: number) {
    if (this.getAttachmentImageSource(attachment) !== '') {
      Image(this.getAttachmentImageSource(attachment))
        .id('img_' + attachment.id)
        .width('100%')
        .height(this.compactImageMaxHeight)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .clip(true)
        .layoutWeight(1)
        .onClick(() => {
          this.handleImagePreview(attachmentIndex)
        })
    }
  }

  @Builder
  UserAttachments() {
    Column() {
      if (this.getMessageImageEntries().length === 1) {
        this.CompactSingleImage(
          this.getMessageImageEntries()[0].attachment,
          this.getMessageImageEntries()[0].originalIndex,
          this.hasMessageTextContent() ? 6 : 0
        )
      } else if (this.getMessageImageEntries().length > 1) {
        Column({ space: this.compactImageGap }) {
          ForEach(this.getMessageImageGridRows(), (rowIndex: number) => {
            Row({ space: this.compactImageGap }) {
              this.CompactGridImage(
                this.getMessageImageEntries()[rowIndex * 2].attachment,
                this.getMessageImageEntries()[rowIndex * 2].originalIndex
              )

              if (rowIndex * 2 + 1 < this.getMessageImageEntries().length) {
                this.CompactGridImage(
                  this.getMessageImageEntries()[rowIndex * 2 + 1].attachment,
                  this.getMessageImageEntries()[rowIndex * 2 + 1].originalIndex
                )
              } else {
                Blank()
                  .layoutWeight(1)
              }
            }
            .width(this.compactImageContainerWidth)
          }, (rowIndex: number) => `${this.message.id}_user_${rowIndex}`)
        }
        .margin({ bottom: this.hasMessageTextContent() ? 6 : 0 })
      }

      ForEach(this.getMessageFileAttachments(), (attachment: MessageAttachment, index: number) => {
        Row() {
          SymbolGlyph(this.getFileAttachmentSymbol(attachment))
            .fontSize(18)
            .fontColor([this.isManuscriptMode ? this.manuscriptAccentDeep : 'rgba(255,255,255,0.8)'])

          Text(attachment.name)
            .fontFamily(this.isManuscriptMode ? MANUSCRIPT_BODY_FONT : 'HarmonyOS Sans')
            .fontSize(12)
            .fontColor(this.isManuscriptMode ? getAppUiState().themeTextPrimary : 'rgba(255,255,255,0.9)')
            .margin({ left: 6 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .alignSelf(ItemAlign.Stretch)
        .padding(8)
        .backgroundColor(this.isManuscriptMode ? withColorAlpha(this.manuscriptAccent, '14') :
          'rgba(255,255,255,0.15)')
        .border({
          width: this.isManuscriptMode ? 0.5 : 0,
          color: this.isManuscriptMode ? withColorAlpha(this.manuscriptAccentDeep, '4D') : Color.Transparent
        })
        .borderRadius(8)
        .margin({ bottom: this.hasMessageTextContent() ? 6 : 0 })
        .onClick(() => {
          if (this.isPdfAttachment(attachment)) {
            this.onFileAttachmentClick(attachment)
          }
        })
      }, (attachment: MessageAttachment, index: number) => attachment.id || attachment.filePath || index.toString())
    }
    // 由气泡内容区决定宽度。这里不能使用 100%，否则百分比会按气泡的
    // 外部约束计算，叠加气泡 padding 后附件栏会越过右侧圆角。
    .alignSelf(ItemAlign.Stretch)
    .alignItems(HorizontalAlign.End)
  }

  @Builder
  AssistantAttachments() {
    Column() {
      if (this.getMessageImageEntries().length === 1) {
        this.CompactSingleImage(
          this.getMessageImageEntries()[0].attachment,
          this.getMessageImageEntries()[0].originalIndex,
          8
        )
      } else if (this.getMessageImageEntries().length > 1) {
        Column({ space: this.compactImageGap }) {
          ForEach(this.getMessageImageGridRows(), (rowIndex: number) => {
            Row({ space: this.compactImageGap }) {
              this.CompactGridImage(
                this.getMessageImageEntries()[rowIndex * 2].attachment,
                this.getMessageImageEntries()[rowIndex * 2].originalIndex
              )

              if (rowIndex * 2 + 1 < this.getMessageImageEntries().length) {
                this.CompactGridImage(
                  this.getMessageImageEntries()[rowIndex * 2 + 1].attachment,
                  this.getMessageImageEntries()[rowIndex * 2 + 1].originalIndex
                )
              } else {
                Blank()
                  .layoutWeight(1)
              }
            }
            .width(this.compactImageContainerWidth)
          }, (rowIndex: number) => `${this.message.id}_ai_${rowIndex}`)
        }
        .margin({ bottom: 8 })
      }

      ForEach(this.getMessageFileAttachments(), (attachment: MessageAttachment, index: number) => {
        Row() {
          SymbolGlyph(this.getFileAttachmentSymbol(attachment))
            .fontSize(18)
            .fontColor([$r('app.color.text_tertiary')])

          Text(attachment.name)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 6 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .padding(8)
        .backgroundColor($r('app.color.divider'))
        .borderRadius(8)
        .margin({ bottom: 8 })
        .onClick(() => {
          if (this.isPdfAttachment(attachment)) {
            this.onFileAttachmentClick(attachment)
          }
        })
      }, (attachment: MessageAttachment, index: number) => attachment.id || attachment.filePath || index.toString())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 处理图片预览点击
  private handleImagePreview(clickedIndex: number): void {
    // 收集所有图片附件的路径
    const imageAttachments = this.message.getImageAttachments()
    const imagePaths: Array<string> = []

    for (let i = 0; i < imageAttachments.length; i++) {
      const attachment = imageAttachments[i]
      if (attachment.filePath !== '') {
        imagePaths.push('file://' + attachment.filePath)
      } else if (attachment.base64Data !== '') {
        imagePaths.push(`data:${attachment.mimeType};base64,${attachment.base64Data}`)
      }
    }

    if (imagePaths.length > 0) {
      // 计算点击的图片在纯图片列表中的索引
      let imageIndex = 0
      let imageCount = 0
      for (let i = 0; i < this.message.attachments.length; i++) {
        if (this.message.attachments[i].type === AttachmentType.IMAGE) {
          if (i === clickedIndex) {
            imageIndex = imageCount
            break
          }
          imageCount++
        }
      }
      this.onImageClick(imagePaths, imageIndex)
    }
  }

  // 翻译子菜单
  @Builder
  TranslateSubMenu() {
    Menu() {
      ForEach(this.translateLanguages, (lang: TranslateLanguage) => {
        MenuItem({ content: lang.nativeName })
          .contentFont({ size: 14 })
          .contentFontColor($r('app.color.text_primary'))
          .onClick(() => { this.handleTranslate(lang.name) })
      }, (lang: TranslateLanguage) => lang.code)
    }
    .backgroundColor(Color.Transparent)
    .borderRadius(12)
  }

  // AI 消息更多菜单（分享/多选/删除）
  @Builder
  AssistantMoreMenu() {
    Menu() {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.share')).fontSize(16), content: $r('app.string.menu_share') })
        .contentFont({ size: 14 })
        .onClick(() => { this.onShareMessage() })

      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')).fontSize(16), content: $r('app.string.menu_multi_select') })
        .contentFont({ size: 14 })
        .onClick(() => { this.onEnterMultiSelect(this.message.id) })

      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontSize(16), content: $r('app.string.delete') })
        .contentFont({ size: 14 })
        .contentFontColor($r('app.color.status_error'))
        .onClick(() => { this.onDelete() })
    }
    .backgroundColor(Color.Transparent)
    .borderRadius(12)
  }

  // 用户消息更多菜单（分享/多选/删除）
  @Builder
  UserMoreMenu() {
    Menu() {
      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.share')).fontSize(16), content: $r('app.string.menu_share') })
        .contentFont({ size: 14 })
        .onClick(() => { this.onShareMessage() })

      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')).fontSize(16), content: $r('app.string.menu_multi_select') })
        .contentFont({ size: 14 })
        .onClick(() => { this.onEnterMultiSelect(this.message.id) })

      MenuItem({ symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontSize(16), content: $r('app.string.delete') })
        .contentFont({ size: 14 })
        .contentFontColor($r('app.color.status_error'))
        .onClick(() => { this.onDelete() })
    }
    .backgroundColor(Color.Transparent)
    .borderRadius(12)
  }

  @Builder
  private AssistantActionToolbar() {
    Row({ space: this.isManuscriptMode ? 0 : 2 }) {
      if (this.shouldShowVersionSwitcher()) {
        Button({ type: ButtonType.Circle, stateEffect: this.isManuscriptMode }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(this.getMessageToolbarIconSize())
            .fontColor([this.canSwitchToPreviousVersion()
              ? this.messageToolbarIconColor : $r('app.color.divider')])
        }
        .width(this.getMessageToolbarButtonSize())
        .height(this.getMessageToolbarButtonSize())
        .padding(0)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (this.canSwitchToPreviousVersion()) {
            this.onSwitchVersion(-1)
          }
        })

        Text(`${this.message.versionIndex + 1}/${this.message.versionCount}`)
          .fontSize(12)
          .fontColor(this.messageToolbarIconColor)
          .width(this.getMessageToolbarButtonSize())
          .textAlign(TextAlign.Center)

        Button({ type: ButtonType.Circle, stateEffect: this.isManuscriptMode }) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(this.getMessageToolbarIconSize())
            .fontColor([this.canSwitchToNextVersion()
              ? this.messageToolbarIconColor : $r('app.color.divider')])
        }
        .width(this.getMessageToolbarButtonSize())
        .height(this.getMessageToolbarButtonSize())
        .padding(0)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (this.canSwitchToNextVersion()) {
            this.onSwitchVersion(1)
          }
        })

        Divider()
          .vertical(true)
          .height(14)
          .color($r('app.color.divider'))
          .margin(this.isManuscriptMode ? 0 : { left: 3, right: 3 })
      }

      if (this.canCopyMessageContent()) {
        Button({ type: ButtonType.Circle, stateEffect: this.isManuscriptMode }) {
          SymbolGlyph($r('sys.symbol.checkmark_square_on_square'))
            .fontSize(this.getMessageToolbarIconSize())
            .fontColor([this.messageToolbarIconColor])
        }
        .width(this.getMessageToolbarButtonSize())
        .height(this.getMessageToolbarButtonSize())
        .padding(0)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.handleCopy()
        })
      }

      Button({ type: ButtonType.Circle, stateEffect: this.isManuscriptMode }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(this.getMessageToolbarIconSize())
          .fontColor([this.messageToolbarIconColor])
      }
      .width(this.getMessageToolbarButtonSize())
      .height(this.getMessageToolbarButtonSize())
      .padding(0)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.onRegenerate()
      })

      if (this.canReadMessageContent()) {
        Button({ type: ButtonType.Circle, stateEffect: this.isManuscriptMode }) {
          if (this.ttsLoadingMessageId === this.message.id) {
            LoadingProgress()
              .width(this.getMessageToolbarIconSize())
              .height(this.getMessageToolbarIconSize())
              .color(this.themePrimary)
          } else {
            SymbolGlyph((this.speakingMessageId === this.message.id)
              ? $r('sys.symbol.pause') : $r('sys.symbol.speaker_wave_2'))
              .fontSize(this.getMessageToolbarIconSize())
              .fontColor([(this.speakingMessageId === this.message.id)
                ? this.themePrimary : this.messageToolbarIconColor])
          }
        }
        .width(this.getMessageToolbarButtonSize())
        .height(this.getMessageToolbarButtonSize())
        .padding(0)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (this.ttsLoadingMessageId === this.message.id ||
            this.speakingMessageId === this.message.id) {
            this.onTTSStop()
          } else {
            this.onTTS(this.message.id, this.message.content)
          }
        })
      }

      if (this.canTranslateMessageContent()) {
        Button({ type: ButtonType.Circle, stateEffect: this.isManuscriptMode }) {
          SymbolGlyph($r('sys.symbol.translate'))
            .fontSize(this.getMessageToolbarIconSize())
            .fontColor([this.messageToolbarIconColor])
        }
        .width(this.getMessageToolbarButtonSize())
        .height(this.getMessageToolbarButtonSize())
        .padding(0)
        .backgroundColor(Color.Transparent)
        .bindMenu(this.TranslateSubMenu(), {
          systemMaterial: new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.THICK
          })
        })
      }

      Divider()
        .vertical(true)
        .height(14)
        .color($r('app.color.divider'))
        .margin(this.isManuscriptMode ? 0 : { left: 3, right: 3 })

      Button({ type: ButtonType.Circle, stateEffect: this.isManuscriptMode }) {
        SymbolGlyph($r('sys.symbol.dart_target'))
          .fontSize(this.getMessageToolbarIconSize())
          .fontColor([this.messageToolbarIconColor])
      }
      .width(this.getMessageToolbarButtonSize())
      .height(this.getMessageToolbarButtonSize())
      .padding(0)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.showCacheHitPopup = !this.showCacheHitPopup
      })
      .bindPopup(this.showCacheHitPopup, {
        message: this.getCacheHitText(),
        placement: Placement.Top,
        systemMaterial: new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN
        }),
        onStateChange: (event) => {
          this.showCacheHitPopup = event.isVisible
        }
      })

      if (this.shouldShowEstimatedCost()) {
        Button({ type: ButtonType.Circle, stateEffect: this.isManuscriptMode }) {
          SymbolGlyph($r('sys.symbol.yuansign_coupon'))
            .fontSize(this.getMessageToolbarIconSize())
            .fontColor([this.messageToolbarIconColor])
        }
        .width(this.getMessageToolbarButtonSize())
        .height(this.getMessageToolbarButtonSize())
        .padding(0)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showEstimatedCostPopup = !this.showEstimatedCostPopup
        })
        .bindPopup(this.showEstimatedCostPopup, {
          message: this.getEstimatedCostText(),
          placement: Placement.Top,
          systemMaterial: new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.THIN
          }),
          onStateChange: (event) => {
            this.showEstimatedCostPopup = event.isVisible
          }
        })
      }

      Button({ type: ButtonType.Circle, stateEffect: this.isManuscriptMode }) {
        SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
          .fontSize(this.getMessageToolbarIconSize())
          .fontColor([this.messageToolbarIconColor])
      }
      .width(this.getMessageToolbarButtonSize())
      .height(this.getMessageToolbarButtonSize())
      .padding(0)
      .backgroundColor(Color.Transparent)
      .bindMenu(this.AssistantMoreMenu(), {
        systemMaterial: new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THICK
        })
      })
    }
    .height(this.getMessageToolbarHeight())
    .padding({ left: 3, right: 3 })
    .borderRadius(this.isManuscriptMode ? 0 : this.getMessageToolbarHeight() / 2)
    .border({
      width: 0,
      color: this.isManuscriptMode ? this.manuscriptAccent : this.manuscriptAccentDeep
    })
    .clip(!this.isManuscriptMode)
    .alignItems(VerticalAlign.Center)
    .systemMaterial(this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      interactive: true,
      lightEffect: { color: undefined }
    }))
  }

  private getOrderedResponseSegments(): AssistantResponseSegment[] {
    if (this.message.responseSegments.length > 0) {
      let hasCompactionSegment = false
      for (let i = 0; i < this.message.responseSegments.length; i++) {
        if (this.message.responseSegments[i].type === AssistantResponseSegmentType.CONTEXT_COMPACTION) {
          hasCompactionSegment = true
          break
        }
      }
      // 兼容升级前已经持久化完成状态、但时间线里尚无压缩节点的消息。
      if (!hasCompactionSegment && this.message.contextCompactionState !== ContextCompactionUiState.NONE) {
        return [new AssistantResponseSegment(
          `${this.message.id}_legacy_context_compaction`,
          AssistantResponseSegmentType.CONTEXT_COMPACTION,
          this.message.contextCompactionState
        ), ...this.message.responseSegments]
      }
      return this.message.responseSegments
    }

    // 旧消息没有时间线字段，只能按现有可恢复信息生成稳定的兼容顺序。
    const segments: AssistantResponseSegment[] = []
    if (this.message.contextCompactionState !== ContextCompactionUiState.NONE) {
      segments.push(new AssistantResponseSegment(
        `${this.message.id}_legacy_context_compaction`,
        AssistantResponseSegmentType.CONTEXT_COMPACTION,
        this.message.contextCompactionState
      ))
    }
    if (this.message.reasoningContent.trim() !== '') {
      segments.push(new AssistantResponseSegment(
        `${this.message.id}_legacy_reasoning`,
        AssistantResponseSegmentType.REASONING,
        this.message.reasoningContent
      ))
    }
    if (this.message.toolCalls.length > 0) {
      const toolCallIds: string[] = []
      for (let i = 0; i < this.message.toolCalls.length; i++) {
        toolCallIds.push(this.message.toolCalls[i].id)
      }
      segments.push(new AssistantResponseSegment(
        `${this.message.id}_legacy_tools`,
        AssistantResponseSegmentType.TOOL_CALLS,
        '',
        toolCallIds
      ))
    }
    if (this.message.content.trim() !== '') {
      segments.push(new AssistantResponseSegment(
        `${this.message.id}_legacy_content`,
        AssistantResponseSegmentType.CONTENT,
        this.message.content
      ))
    }
    return segments
  }

  private getUserGuidanceSegments(): AssistantResponseSegment[] {
    const result: AssistantResponseSegment[] = []
    for (let i = 0; i < this.message.responseSegments.length; i++) {
      if (this.message.responseSegments[i].type === AssistantResponseSegmentType.USER_GUIDANCE) {
        result.push(this.message.responseSegments[i])
      }
    }
    return result
  }

  private isTimelineReasoningExpanded(segment: AssistantResponseSegment): boolean {
    // 用户的显式选择优先于"生成中默认展开"，否则思考过程中永远折不起来
    if (this.collapsedTimelineReasoningIds.includes(segment.id)) {
      return false
    }
    if (this.expandedTimelineReasoningIds.includes(segment.id)) {
      return true
    }
    return this.isActiveTimelineSegment(segment)
  }

  private isActiveTimelineSegment(segment: AssistantResponseSegment): boolean {
    const segments = this.getOrderedResponseSegments()
    return this.message.isGenerating && segments.length > 0 && segments[segments.length - 1].id === segment.id
  }

  // 以当前实际展示状态为准取反，保证一次点击就有可见变化
  private toggleTimelineReasoning(segment: AssistantResponseSegment): void {
    const shouldExpand = !this.isTimelineReasoningExpanded(segment)
    this.expandedTimelineReasoningIds =
      shouldExpand ? appendUniqueId(this.expandedTimelineReasoningIds, segment.id)
        : removeId(this.expandedTimelineReasoningIds, segment.id)
    this.collapsedTimelineReasoningIds =
      shouldExpand ? removeId(this.collapsedTimelineReasoningIds, segment.id)
        : appendUniqueId(this.collapsedTimelineReasoningIds, segment.id)
  }

  private shouldShowTimelineSearchReferences(segment: AssistantResponseSegment): boolean {
    if (!this.message.hasSearchReferences()) {
      return false
    }
    let lastWebSearchCallId = ''
    for (let i = 0; i < this.message.toolCalls.length; i++) {
      if (this.isWebSearchToolCall(this.message.toolCalls[i])) {
        lastWebSearchCallId = this.message.toolCalls[i].id
      }
    }
    return lastWebSearchCallId !== '' && this.containsToolCallId(segment.toolCallIds, lastWebSearchCallId)
  }

  @Builder
  private TimelineSegmentMarkdown(segment: AssistantResponseSegment, compact: boolean = false) {
    ChatMarkdownRenderer({
      content: segment.content,
      isInputEnded: !this.isActiveTimelineSegment(segment),
      incrementalAnalysis: this.isActiveTimelineSegment(segment),
      useCangjieComponent: true,
      chatFontSize: this.chatFontSize,
      compact: compact,
      latexFontSize: this.chatFontSize,
      textColorOverride: compact ? getAppUiState().themeTextSecondary : '',
      titleColorOverride: compact ? getAppUiState().themeTextSecondary : '',
      textTypeface: compact ? 'HarmonyOS Sans' : this.chatBubbleTypeface,
      themeRenderKey: this.themeRenderKey,
      onOpenLink: (title: string, url: string): void => {
        this.openWebSheetForLink(title, url)
      },
      onImageClick: (src: string): void => {
        this.onImageClick([src], 0)
      },
      onCopyText: (text: string): void => {
        this.copyToClipboard(text)
      },
      onCopyCode: (code: string): void => {
        this.copyToClipboard(code)
      },
      onCodeFullScreen: (code: string, _codeType: string): void => {
        this.copyToClipboard(code)
      }
    })
      .constraintSize({ maxWidth: '100%' })
      .backgroundColor(Color.Transparent)
  }

  @Builder
  private TimelineReasoningSection(segment: AssistantResponseSegment) {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.AI_deep_thinking'))
          .fontSize(14)
          .fontColor([this.isManuscriptMode || this.isActiveTimelineSegment(segment)
            ? this.themePrimary : $r('app.color.text_secondary')])

        Text(this.isActiveTimelineSegment(segment) ?
          $r('app.string.reasoning_thinking') : $r('app.string.reasoning_process'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isManuscriptMode || this.isActiveTimelineSegment(segment)
            ? this.themePrimary : $r('app.color.text_secondary'))
          .margin({ left: 6 })

        Blank().layoutWeight(1)

        Row() {
          Text(this.isTimelineReasoningExpanded(segment) ?
            $r('app.string.common_collapse') : $r('app.string.common_details'))
            .fontSize(11)
            .fontColor(this.isManuscriptMode ? this.themePrimary : $r('app.color.text_tertiary'))

          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(12)
            .fontColor([this.isManuscriptMode ? this.themePrimary : $r('app.color.text_tertiary')])
            .rotate({ angle: this.isTimelineReasoningExpanded(segment) ? 180 : 0 })
            .margin({ left: 2 })
        }
      }
      .width('100%')
      .height(this.isManuscriptMode ? MANUSCRIPT_COMPACT_BAR_HEIGHT : 36)
      .padding({ left: this.isManuscriptMode ? 14 : 10, right: this.isManuscriptMode ? 14 : 10 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.toggleTimelineReasoning(segment)
      })

      if (this.isTimelineReasoningExpanded(segment) && segment.content.trim().length > 0) {
        Column() {
          this.TimelineSegmentMarkdown(segment, true)
        }
        .width('100%')
        .padding({ left: 10, right: 10, bottom: 8 })
      }
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .borderRadius(this.isManuscriptMode ? 0 : 12)
    .border({
      width: this.isManuscriptMode ? { top: 1, bottom: 1 } : 0.5,
      color: this.isManuscriptMode ? getAppUiState().themeDivider : this.getTimelineRailColor()
    })
    .clip(false)
    .systemMaterial(this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: this.getTimelineBackgroundColor(),
      applyShadow: false,
      interactive: false,
      lightEffect: { color: undefined }
    }))
    .shadow({
      radius: this.isManuscriptMode ? 0 : 12,
      color: this.isManuscriptMode ? Color.Transparent :
        (this.isDarkMode ? 'rgba(0, 0, 0, 0.32)' : 'rgba(15, 23, 42, 0.14)'),
      offsetX: 0,
      offsetY: 0
    })
    .margin({ bottom: 8 })
  }

  @Builder
  private TimelineToolSection(segment: AssistantResponseSegment) {
    Column() {
      ForEach(this.getToolCallRenderGroups(segment.toolCallIds), (group: ToolCallRenderGroup) => {
        if (group.isAskUser) {
          AskUserCard({
            toolCall: group.askUserCalls.length > 0 ? group.askUserCalls[0] : new ToolCall(),
            toolCalls: group.askUserCalls,
            isAnswered: this.areAllAskUserCallsAnswered(group.askUserCalls),
            compactMode: true,
            resultContents: this.getAskUserResultContents(group.askUserCalls),
            onAnswer: (toolCallId: string, answerJson: string): void => {
              this.onAskUserAnswer(toolCallId, answerJson)
            },
            onRequestAnswer: (toolCallId: string): void => {
              this.onAskUserOpen(toolCallId)
            }
          })
            .margin({ bottom: 6 })
        } else {
          ToolCallCard({
            entries: group.entries,
            isExecuting: group.anyExecuting,
            onSubAgentPreview: (): void => {
              this.showSubAgentPreviewSheet = true
            }
          })
            .margin({ bottom: 6 })
        }
      }, (group: ToolCallRenderGroup, index: number) => this.buildToolCallRenderGroupKey(group, index))

      if (this.shouldShowTimelineSearchReferences(segment)) {
        SearchReferenceCard({
          query: this.extractSearchQuery(),
          searchEngine: this.message.searchEngine || 'Web',
          references: this.message.searchReferences,
          sourceLabel: this.getSearchSourceLabel()
        })
          .margin({ bottom: 6 })
      }

      if (this.getVChartPayloads(segment.toolCallIds).length > 0) {
        ForEach(this.getVChartPayloads(segment.toolCallIds), (payload: MessageVChartPayload) => {
          VChartCard({
            specJson: payload.specJson,
            summary: payload.summary,
            chartType: payload.chartType
          })
            .margin({ bottom: 6 })
        }, (payload: MessageVChartPayload) => payload.id)
      }

      if (this.getMapPayloads(segment.toolCallIds).length > 0) {
        ForEach(this.getMapPayloads(segment.toolCallIds), (payload: MessageMapPayload) => {
          MapResultCard({
            toolResultContent: payload.resultContent,
            onOpenMap: (visualizationJson: string): void => {
              this.onOpenMap(visualizationJson)
            }
          })
            .margin({ bottom: 6 })
        }, (payload: MessageMapPayload) => payload.id)
      }
    }
    .width('100%')
  }

  @Builder
  private TimelineContentSection(segment: AssistantResponseSegment) {
    Column() {
      if (!this.isActiveTimelineSegment(segment) && this.hasHtmlBlocks(segment.content)) {
        ForEach(this.splitContentToSegments(segment.content), (contentSegment: ContentSegment) => {
          if (contentSegment.isHtml) {
            HtmlPreviewCard({
              htmlCode: contentSegment.renderContent,
              onCopyCode: (code: string): void => {
                this.copyToClipboard(code)
                showToast(this.getUIContext(), $r('app.string.copy_success'))
              }
            })
          } else {
            this.StaticMarkdown(contentSegment.renderContent, false, '', '', true)
          }
        }, (contentSegment: ContentSegment, index: number) => `${segment.id}_${index}`)
      } else {
        this.TimelineSegmentMarkdown(segment)
      }
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  private OrderedResponseTimeline() {
    Column() {
      ForEach(this.getOrderedResponseSegments(), (segment: AssistantResponseSegment) => {
        if (segment.type === AssistantResponseSegmentType.REASONING && segment.content.trim().length > 0) {
          this.TimelineReasoningSection(segment)
        } else if (segment.type === AssistantResponseSegmentType.TOOL_CALLS) {
          this.TimelineToolSection(segment)
        } else if (segment.type === AssistantResponseSegmentType.CONTEXT_COMPACTION) {
          this.ContextCompactionStatusBar(segment.content)
        } else if (segment.type === AssistantResponseSegmentType.USER_GUIDANCE && segment.content.trim().length > 0) {
          this.UserGuidanceSection(segment)
        } else if (segment.type === AssistantResponseSegmentType.CONTENT && segment.content.trim().length > 0) {
          this.TimelineContentSection(segment)
        }
      }, (segment: AssistantResponseSegment) => segment.id)
    }
    .width('100%')
  }

  @Builder
  AssistantMessage() {
    Row() {
      // 多选选中竖条
      if (this.isMultiSelectMode && this.isSelected) {
        Column()
          .width(3)
          .borderRadius(1.5)
          .backgroundColor(this.themePrimary)
          .alignSelf(ItemAlign.Stretch)
          .margin({ right: 4 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }

      Column() {
        // 消息头部：图标 + 模型名 + 时间（水平排列）
        // 只在 showHeader 为 true 时显示
        if (this.showHeader && !this.isManuscriptMode) {
          Row() {
            // 助手头像
            Column() {
              AssistantAvatarView({
                value: this.assistantAvatarSymbol,
                color: this.assistantAvatarColor,
                avatarSize: 30,
                radius: 8,
                fontSize: 14,
                cacheKey: this.assistantAvatarCacheKey,
                avatarBorderWidth: 1,
                avatarBorderColor: this.themePrimaryLight
              })
            }
            .width(30)
            .height(30)
            .borderRadius(8)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)

            // 模型名称
            Text(this.message.modelName || 'AI')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .margin({ left: 10 })

            Blank()
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }

        // 内容区域 - 无气泡，全宽显示
        Column({ space: this.isManuscriptMode ? 5 : 0 }) {
          if (this.isManuscriptMode) {
            Text(this.manuscriptAssistantLabel)
              .fontFamily(MANUSCRIPT_BODY_FONT)
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.manuscriptAccentDeep)
              .letterSpacing(2)
              .width('100%')
              .textAlign(TextAlign.Start)
          }

          Column() {
            // ========== 工具调用区域 ==========
            if (!getAppUiState().chatOrderedResponseHistory && this.message.hasToolCalls()) {
              ForEach(this.getToolCallRenderGroups(), (group: ToolCallRenderGroup) => {
                if (group.isAskUser) {
                  AskUserCard({
                    toolCall: group.askUserCalls.length > 0 ? group.askUserCalls[0] : new ToolCall(),
                    toolCalls: group.askUserCalls,
                    isAnswered: this.areAllAskUserCallsAnswered(group.askUserCalls),
                    compactMode: true,
                    resultContents: this.getAskUserResultContents(group.askUserCalls),
                    onAnswer: (toolCallId: string, answerJson: string): void => {
                      this.onAskUserAnswer(toolCallId, answerJson)
                    },
                    onRequestAnswer: (toolCallId: string): void => {
                      this.onAskUserOpen(toolCallId)
                    }
                  })
                    .margin({ bottom: 6 })
                } else {
                  ToolCallCard({
                    entries: group.entries,
                    isExecuting: group.anyExecuting,
                    onSubAgentPreview: (): void => {
                      this.showSubAgentPreviewSheet = true
                    }
                  })
                    .margin({ bottom: 6 })
                }
              }, (group: ToolCallRenderGroup, index: number) => this.buildToolCallRenderGroupKey(group, index))
            }

            if (!getAppUiState().chatOrderedResponseHistory && this.getVChartPayloads().length > 0) {
              ForEach(this.getVChartPayloads(), (payload: MessageVChartPayload) => {
                VChartCard({
                  specJson: payload.specJson,
                  summary: payload.summary,
                  chartType: payload.chartType
                })
                  .margin({ bottom: 6 })
              }, (payload: MessageVChartPayload) => payload.id)
            }


            if (!getAppUiState().chatOrderedResponseHistory && this.getMapPayloads().length > 0) {
              ForEach(this.getMapPayloads(), (payload: MessageMapPayload) => {
                MapResultCard({
                  toolResultContent: payload.resultContent,
                  onOpenMap: (visualizationJson: string): void => {
                    this.onOpenMap(visualizationJson)
                  }
                })
                  .margin({ bottom: 6 })
              }, (payload: MessageMapPayload) => payload.id)
            }

            // ========== 搜索引用区域 ==========
            if (!getAppUiState().chatOrderedResponseHistory && this.message.hasSearchReferences()) {
              SearchReferenceCard({
                query: this.extractSearchQuery(),
                searchEngine: this.message.searchEngine || 'Web',
                references: this.message.searchReferences,
                sourceLabel: this.getSearchSourceLabel()
              })
                .margin({ bottom: 6 })
            }

            // ========== 附件区域（AI 生成的图片） ==========
            if (this.hasRenderableAttachments(this.message.attachments)) {
              this.AssistantAttachments()
            }

            // ========== 应用侧上下文压缩状态/结果栏 ==========
            if (!getAppUiState().chatOrderedResponseHistory &&
              this.message.contextCompactionState !== ContextCompactionUiState.NONE) {
              this.ContextCompactionStatusBar(this.message.contextCompactionState)
            }

            if (!getAppUiState().chatOrderedResponseHistory && this.getUserGuidanceSegments().length > 0) {
              ForEach(this.getUserGuidanceSegments(), (segment: AssistantResponseSegment) => {
                this.UserGuidanceSection(segment)
              }, (segment: AssistantResponseSegment) => segment.id)
            }

            // ========== 推理内容区域（可折叠） ==========
            if (!getAppUiState().chatOrderedResponseHistory && this.message.hasReasoningContent()) {
              this.ReasoningSection()
            }

            // ========== 加载状态或主要内容区域 ==========
            if (getAppUiState().chatOrderedResponseHistory) {
              if (this.getOrderedResponseSegments().length > 0) {
                this.OrderedResponseTimeline()
              } else if (this.message.isSearching) {
                this.SearchingIndicatorInline()
              }
            } else {
              if (this.message.content.length === 0 && this.message.reasoningContent.length === 0 &&
                  (this.message.isGenerating || this.message.isSearching)) {
                if (this.message.isSearching) {
                  this.SearchingIndicatorInline()
                }
              } else {
                if (this.hasHtmlSegments()) {
                  ForEach(this.getContentSegments(),
                    (segment: ContentSegment, index: number) => {
                      if (segment.isHtml) {
                        HtmlPreviewCard({
                          htmlCode: segment.renderContent,
                          onCopyCode: (code: string) => {
                            this.copyToClipboard(code)
                            showToast(this.getUIContext(), $r('app.string.copy_success'))
                          }
                        })
                      } else {
                        this.StaticMarkdown(segment.renderContent, false, '', '', true)
                      }
                    },
                    (segment: ContentSegment, index: number) => {
                      return 'segment_' + this.message.id + '_' + index.toString()
                    }
                  )
                } else {
                  Column() {
                    this.MessageContentMarkdown()
                  }
                    .width('100%')
                    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
                }
              }
            }

            // ========== 翻译结果区域（嵌入式可折叠卡片） ==========
            if (this.showTranslation) {
              this.TranslationCard()
            }
          }
          .width('100%')
          .onClick(() => {
            if (!this.isMultiSelectMode &&
              (this.ttsLoadingMessageId === this.message.id || this.speakingMessageId === this.message.id)) {
              this.onTTSStop()
            }
          })
          .bindSheet($$this.showSubAgentPreviewSheet, this.SubAgentPreviewSheet(), {
            height: '75%',
            detents: ['75%', '100%'],
            dragBar: false,
            showClose: false,
            backgroundColor: Color.Transparent,
            systemMaterial: new uiMaterial.ImmersiveMaterial({
              style: uiMaterial.ImmersiveStyle.REGULAR,
              materialColor: Color.Transparent
            })
          })
        }
        .width('100%')
        .margin({ top: this.showHeader && !this.isManuscriptMode ? 8 : 0 })
        .padding(this.isManuscriptMode ? { left: 34, right: 34 } :
          { left: 14, right: 14, top: 12, bottom: 10 })
          .backgroundColor(this.isMultiSelectMode && this.isSelected
            ? this.themePrimaryLight
            : (this.isManuscriptMode ? Color.Transparent : this.themeAiBubble))
          .borderRadius(this.isManuscriptMode ? 0 : 16)
          .border({
            width: this.isManuscriptMode ? 0 :
              (this.isMultiSelectMode && this.isSelected ? 1.2 : (this.hasAskUserToolCall() ? 1 : 0.5)),
            color: this.isMultiSelectMode && this.isSelected ? this.themePrimary :
              (this.hasAskUserToolCall() ? this.themePrimaryLight : $r('app.color.bubble_border'))
          })
          .clip(false)
          .systemMaterial(this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR,
            materialColor: this.isMultiSelectMode && this.isSelected
              ? this.themePrimaryLight
              : this.themeAiBubble
          }))

        if (this.shouldShowAssistantToolbar()) {
          Row() {
            this.AssistantActionToolbar()
          }
          .width('100%')
          .justifyContent(this.isManuscriptMode ? FlexAlign.End : FlexAlign.Start)
          .margin({ top: this.isManuscriptMode ? 10 : 6 })
          .padding(this.isManuscriptMode ? { left: 34, right: 34 } : 0)
        }
      }
      .enabled(!this.isMultiSelectMode)
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ maxWidth: this.isManuscriptMode ? '100%' : '92%' })
    .alignItems(VerticalAlign.Top)
    .onTouch((event: TouchEvent) => {
      this.handleMultiSelectTouch(event)
    })
  }

  @Builder
  UserGuidanceSection(segment: AssistantResponseSegment) {
    Row() {
      Column() {
        Text(segment.content)
          .fontSize(13)
          .fontFamily(this.chatBubbleTypeface)
          .fontColor(this.isManuscriptMode ? $r('app.color.text_primary') : this.themeUserBubbleText)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .constraintSize({ maxWidth: '88%' })
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor(this.isManuscriptMode ? Color.Transparent : this.themeUserBubble)
      .borderRadius(this.isManuscriptMode ? 0 : 10)
      .border({
        width: this.isManuscriptMode ? { top: 1, bottom: 1 } : 0.5,
        color: this.isManuscriptMode ? getAppUiState().themeDivider : this.themePrimaryLight
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .margin({ bottom: 8 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 160 }))
  }

  @Builder
  ContextCompactionStatusBar(state: string) {
    Row({ space: 8 }) {
      SymbolGlyph(state === ContextCompactionUiState.COMPACTING ?
        $r('sys.symbol.doc_zipper') : $r('sys.symbol.checkmark_circle_fill'))
        .fontSize(14)
        .fontColor([this.isManuscriptMode ? this.manuscriptAccentDeep : this.themePrimary])

      Text(state === ContextCompactionUiState.COMPACTING ?
        pickLocalizedText('正在压缩上下文', 'Compacting context') :
        pickLocalizedText('已经压缩上下文', 'Context compacted'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isManuscriptMode ? this.manuscriptAccentDeep : $r('app.color.text_secondary'))
        .maxLines(1)

      Blank()

      if (state === ContextCompactionUiState.COMPACTING) {
        TypingDots({ dotSize: 4, spacing: 2 })
      }
    }
    .width('100%')
    .height(34)
    .padding({ left: 11, right: 11 })
    .margin({ bottom: 8 })
    .backgroundColor(this.isManuscriptMode ? Color.Transparent : withColorAlpha(this.themePrimary, '12'))
    .borderRadius(this.isManuscriptMode ? 0 : 10)
    .border({
      width: this.isManuscriptMode ? { top: 1, bottom: 1 } : 0.5,
      color: this.isManuscriptMode ? getAppUiState().themeDivider : withColorAlpha(this.themePrimary, '30')
    })
    .transition(TransitionEffect.OPACITY.animation({ duration: 160 }))
  }

  // 搜索状态指示器（AI 消息区域内联显示）
  @Builder
  SearchingIndicatorInline() {
    Row() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(13)
          .fontColor([this.themePrimary])

        Text(this.getSearchingIndicatorText())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .constraintSize({ maxWidth: 150 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 三个跳动的点
        TypingDots({ dotSize: 4, spacing: 2 })
      }
      .constraintSize({ maxWidth: 220 })
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.isManuscriptMode ? Color.Transparent : this.themeAiBubble)
      .borderRadius(this.isManuscriptMode ? 0 : 14)
      .border({
        width: this.isManuscriptMode ? { top: 1, bottom: 1 } : 0,
        color: this.isManuscriptMode ? getAppUiState().themeDivider : this.manuscriptAccentDeep
      })
      .clip(true)
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    // 搜索指示器淡出过渡动画
    .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
  }

  // 翻译结果卡片（嵌入式可折叠）
  @Builder
  TranslationCard() {
    Column() {
      // 翻译标题栏（点击可折叠）
      Row() {
        SymbolGlyph($r('sys.symbol.translate'))
          .fontSize(14)
          .fontColor([this.translationLightTextSecondary])

        Text($r('app.string.translation_label'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.translationLightTextSecondary)
          .margin({ left: 6 })

        Blank()

        // 展开/折叠箭头
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([this.translationLightTextTertiary])
          .rotate({ angle: this.isTranslationExpanded ? 0 : -90 })
          .animation({ duration: 200, curve: Curve.EaseOut })
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
          this.isTranslationExpanded = !this.isTranslationExpanded
        })
      })

      // 翻译内容
      if (this.isTranslationExpanded) {
        Column() {
          if (this.isTranslating) {
            Row() {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(this.themePrimary)
              Text($r('app.string.translation_loading'))
                .fontSize(13)
                .fontColor(this.translationLightTextSecondary)
                .margin({ left: 8 })
            }
            .padding({ left: 12, right: 12, bottom: 12 })
          } else if (this.translatedText !== '') {
            Column() {
              this.StaticMarkdown(
                this.getReadonlyTranslatedText(),
                true,
                this.translationLightTextPrimary,
                this.translationLightTextPrimary
              )
            }
            .width('100%')
            .padding({ left: 12, right: 12, bottom: 12 })
          }
        }
        .width('100%')
        .backgroundColor(Color.Transparent)
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }
    }
    .width('100%')
    .margin({ top: 8 })
    .backgroundColor(Color.Transparent)
    .border({
      width: this.isManuscriptMode ? { top: 1, bottom: 1 } : 0.5,
      color: this.isManuscriptMode ? getAppUiState().themeDivider : this.getTimelineRailColor()
    })
    .borderRadius(this.isManuscriptMode ? 0 : 12)
    .clip(false)
    .systemMaterial(this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: this.getTimelineBackgroundColor(),
      applyShadow: false,
      interactive: false,
      lightEffect: { color: undefined }
    }))
    .shadow({
      radius: this.isManuscriptMode ? 0 : 12,
      color: this.isManuscriptMode ? Color.Transparent :
        (this.isDarkMode ? 'rgba(0, 0, 0, 0.32)' : 'rgba(15, 23, 42, 0.14)'),
      offsetX: 0,
      offsetY: 0
    })
  }

  // ===== Timeline 主题色 helper（与设计稿一致：底色跟随 AI 气泡，竖线/边框用主题色半透明） =====
  private getTimelineBackgroundColor(): string {
    return this.themeAiBubble
  }
  private getTimelineRailColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '88' : '55')
  }

  private toggleReasoningExpansion(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
      this.isReasoningExpanded = !this.isReasoningExpanded
    })
  }

  // 推理内容区域：标题栏与工具结果栏使用同一套披露式结构。
  @Builder
  ReasoningSection() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.AI_deep_thinking'))
          .fontSize(14)
          .fontColor([this.isManuscriptMode || this.message.isGenerating
            ? this.themePrimary : $r('app.color.text_secondary')])

        Text(this.message.isGenerating ? $r('app.string.reasoning_thinking') : $r('app.string.reasoning_process'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isManuscriptMode || this.message.isGenerating
            ? this.themePrimary : $r('app.color.text_secondary'))
          .margin({ left: 6 })

        Blank()
          .layoutWeight(1)

        Row() {
          Text(this.isReasoningExpanded ? $r('app.string.common_collapse') : $r('app.string.common_details'))
            .fontSize(11)
            .fontColor(this.isManuscriptMode ? this.themePrimary : $r('app.color.text_tertiary'))

          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(12)
            .fontColor([this.isManuscriptMode ? this.themePrimary : $r('app.color.text_tertiary')])
            .rotate({ angle: this.isReasoningExpanded ? 180 : 0 })
            .animation({ duration: 200, curve: Curve.EaseOut })
            .margin({ left: 2 })
        }
      }
      .width('100%')
      .height(this.isManuscriptMode ? MANUSCRIPT_COMPACT_BAR_HEIGHT : 36)
      .padding({ left: this.isManuscriptMode ? 14 : 10, right: this.isManuscriptMode ? 14 : 10 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.toggleReasoningExpansion()
      })

      if (this.isReasoningExpanded && this.message.reasoningContent.length > 0) {
        Column() {
          this.ReasoningMarkdown()
        }
        .width('100%')
        .padding({ left: 10, right: 10, bottom: 8 })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .borderRadius(this.isManuscriptMode ? 0 : 12)
    .border({
      width: this.isManuscriptMode ? { top: 1, bottom: 1 } : 0.5,
      color: this.isManuscriptMode ? getAppUiState().themeDivider : this.getTimelineRailColor()
    })
    .systemMaterial(this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: this.getTimelineBackgroundColor(),
      applyShadow: false,
      interactive: false,
      lightEffect: { color: undefined }
    }))
    .shadow({
      radius: this.isManuscriptMode ? 0 : 12,
      color: this.isManuscriptMode ? Color.Transparent :
        (this.isDarkMode ? 'rgba(0, 0, 0, 0.32)' : 'rgba(15, 23, 42, 0.14)'),
      offsetX: 0,
      offsetY: 0
    })
    .margin({ bottom: 8 })
  }

  /**
   * 将 Markdown 任务列表语法转换为只读字符
   * 避免 lv-markdown-in 渲染出可交互的 checkbox
   * - [ ] → - ☐ (空心方框)
   * - [x] 或 - [X] → - ☑ (勾选方框)
   */
  private convertTaskListToReadonly(content: string): string {
    if (content.length === 0) {
      return content
    }
    // 替换未完成任务: - [ ] 或 * [ ]
    let result = content.replace(/^(\s*[-*])\s*\[ \]/gm, '$1 ☐')
    // 替换已完成任务: - [x] 或 - [X] 或 * [x] 或 * [X]
    result = result.replace(/^(\s*[-*])\s*\[[xX]\]/gm, '$1 ☑')
    // 转换 LaTeX 分隔符: \[...\] -> $$...$$ , \(...\) -> $...$
    // 部分模型(如 OpenAI 系列)使用 \[...\] 和 \(...\) 格式，lv-markdown-in 只识别 $/$$ 格式
    result = this.normalizeLatexDelimiters(result)
    result = this.convertHeadingsWithLatex(result)
    return result
  }

  /**
   * lv-markdown-in 不渲染 Markdown 标题(##)内嵌的 LaTeX 公式，也不渲染加粗(**)内的 LaTeX。
   * 将含 LaTeX 的标题拆分：纯文本部分保留为标题，LaTeX 及后续内容移至下方独立段落渲染。
   */
  private convertHeadingsWithLatex(content: string): string {
    const codeBlocks: string[] = []
    let result = content.replace(/```[\s\S]*?```/g, (m: string): string => {
      codeBlocks.push(m)
      return `\u0000HCB${(codeBlocks.length - 1).toString()}\u0000`
    })

    result = result.replace(
      /^(#{1,6})\s+(.+)$/gm,
      (match: string, hashes: string, text: string): string => {
        if (!/\$.+?\$/.test(text)) {
          return match
        }
        const firstDollar = text.indexOf('$')
        const headingText = text.substring(0, firstDollar).trimEnd()
        const latexAndRest = text.substring(firstDollar)

        if (headingText.length > 0) {
          return `${hashes} ${headingText}\n\n${latexAndRest}`
        }
        return latexAndRest
      }
    )

    result = result.replace(/\u0000HCB(\d+)\u0000/g, (_m: string, idx: string): string => {
      return codeBlocks[parseInt(idx)]
    })
    return result
  }

  private normalizeLatexDelimiters(content: string): string {
    // 先保护代码块内容，避免误转换
    const codeBlocks: string[] = []
    let protected_ = content.replace(/```[\s\S]*?```|`[^`\n]+`/g, (match: string): string => {
      codeBlocks.push(match)
      return `\u0000CODE${(codeBlocks.length - 1).toString()}\u0000`
    })

    // 块级公式: \[...\] -> $$...$$
    protected_ = protected_.replace(/\\\[([\s\S]*?)\\\]/g, (_match: string, p1: string): string => {
      return `$$${p1}$$`
    })
    // 行内公式: \(...\) -> $...$
    protected_ = protected_.replace(/\\\(([\s\S]*?)\\\)/g, (_match: string, p1: string): string => {
      return `$${p1}$`
    })

    // 恢复代码块
    protected_ = protected_.replace(/\u0000CODE(\d+)\u0000/g, (_match: string, idx: string): string => {
      return codeBlocks[parseInt(idx)]
    })
    return protected_
  }

  // 提取搜索查询内容
  private extractSearchQuery(): string {
    if (this.message.searchQuery !== '') {
      return this.message.searchQuery
    }
    if (this.message.searchReferences.length > 0) {
      return pickLocalizedText('搜索结果', 'Search Results')
    }
    return ''
  }

  private shouldHideToolCallCard(toolCall: ToolCall): boolean {
    // 子智能体发起的工具调用不在主对话中渲染卡片（活动可在“实时预览”面板查看）；
    // ask_user 结果栏在分组前单独处理，不受此过滤影响，图表提取同样不走卡片渲染
    if (this.isSubAgentOriginToolCall(toolCall)) {
      return true
    }
    return this.message.hasSearchReferences() && this.isWebSearchToolCall(toolCall)
  }

  private isSubAgentOriginToolCall(toolCall: ToolCall): boolean {
    return toolCall.sourceLabel.startsWith(SUB_AGENT_SOURCE_LABEL_PREFIX)
  }

  private isWebSearchToolCall(toolCall: ToolCall): boolean {
    if (toolCall.toolId.trim() === 'web_search') {
      return true
    }
    return this.isWebSearchFunctionName(toolCall.functionName)
  }

  private isWebSearchFunctionName(functionName: string): boolean {
    const normalizedName = functionName.trim().toLowerCase().replace(/[\s\-]+/g, '_')
    return normalizedName === 'web_search' ||
      normalizedName === 'exa_search' ||
      normalizedName === 'websearch' ||
      normalizedName === 'search_web' ||
      normalizedName === 'internet_search' ||
      normalizedName === 'web_search_exa'
  }

  private getSearchSourceLabel(): string {
    const source = this.message.searchSource.trim()
    if (source === 'tool') {
      return pickLocalizedText('工具调用', 'Tool Call')
    }
    if (source === 'manual') {
      return ''
    }
    // 兼容旧数据：没有持久化 searchSource 时，只展示工具调用，不暴露手动执行链路。
    return this.message.hasToolCalls() ? pickLocalizedText('工具调用', 'Tool Call') : ''
  }

  private getSearchingIndicatorText(): string {
    const engine = this.message.searchEngine.trim()
    if (this.message.searchQuery !== '') {
      if (engine !== '') {
        return pickLocalizedText(
          `我将为你通过${engine}查询：${this.message.searchQuery}`,
          `I'll search with ${engine}: ${this.message.searchQuery}`)
      }
      return pickLocalizedText(`我将为你查询：${this.message.searchQuery}`,
        `I'll search for: ${this.message.searchQuery}`)
    }
    if (engine !== '') {
      return pickLocalizedText(`正在通过${engine}查询...`, `Searching with ${engine}...`)
    }
    return pickLocalizedText('正在查询...', 'Searching...')
  }

  private handleCopy() {
    try {
      const copyContent = this.message.content
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, copyContent)
      const systemPasteboard = pasteboard.getSystemPasteboard()
      systemPasteboard.setData(pasteboardData)
      showToast(this.getUIContext(), $r('app.string.copy_success'))
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Copy message failed: ${JSON.stringify(error)}`)
    }
  }

  // 复制指定文本到剪贴板（用于代码块复制）
  private copyToClipboard(text: string) {
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      const systemPasteboard = pasteboard.getSystemPasteboard()
      systemPasteboard.setData(pasteboardData)
      showToast(this.getUIContext(), $r('app.string.copy_success'))
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Copy code failed: ${JSON.stringify(error)}`)
    }
  }
}
