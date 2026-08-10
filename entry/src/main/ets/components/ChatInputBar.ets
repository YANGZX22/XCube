import { getModelIconPath, buildIconResourcePath } from '../utils/ProviderIconUtils'
import { MessageAttachment, AttachmentType } from '../models/ChatModels'
import {
  BaseItemInfo,
  PhotoSource,
  RecentPhotoComponent,
  RecentPhotoOptions,
  photoAccessHelper
} from '@kit.MediaLibraryKit'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { uiMaterial } from '@kit.ArkUI'
import { getAttachmentStorageService } from '../services/AttachmentStorageService'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { VisualEffectsMode } from '../models/ThemeColors'
import {
  ensureManuscriptFonts,
  MANUSCRIPT_BODY_FONT,
  MANUSCRIPT_HEADING_FONT
} from '../utils/ManuscriptVisualUtils'

@ComponentV2
export struct ChatInputBar {
  // 图标动画触发器
  @Local iconTrigger: number = 0
  @Local attachIconTrigger: number = 0
  // pause 呼吸动效透明度
  @Local breathOpacity: number = 1
  // 按钮按下状态
  @Local sendBtnPressed: boolean = false
  @Local sendBtnScale: number = 1
  @Local sendBtnRotation: number = 0
  @Local modelBtnPressed: boolean = false
  @Local attachmentBtnPressed: boolean = false
  @Local immersiveBarHeightVp: number = 52
  private readonly editingHeaderHeightVp: number = 28
  @Param inputText: string = ''
  @Event onInputTextChange: (value: string) => void = (_value: string): void => {}
  @Param attachments: MessageAttachment[] = []
  @Event onAttachmentsChange: (value: MessageAttachment[]) => void = (_value: MessageAttachment[]): void => {}
  @Param isSending: boolean = false
  @Param isSendDispatching: boolean = false
  // isSending 为 true 时，pause 在整个发送期都保留轻微呼吸感
  @Param isAwaitingResponse: boolean = false
  @Param currentModelId: string = ''
  @Param currentProviderId: string = ''
  @Param currentModelName: string = ''
  @Param currentProviderIconType: string = 'svg'
  @Param currentProviderIconPath: string = ''
  @Param currentProviderTextIcon: string = ''
  @Param currentProviderTextIconBgColor: string = ''
  @Param currentProviderCustomImagePath: string = ''
  @Param currentProviderBrandColor: ResourceColor = ''
  // 是否自动聚焦输入框
  @Param autoFocus: boolean = false
  // 主题颜色（从 ThemeService 同步）
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get themeDivider(): string {
    return getAppUiState().themeDivider
  }
  private get themeUserBubble(): string {
    return getAppUiState().themeUserBubble
  }
  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }
  private get inputButtonIconColor(): ResourceColor {
    return getAppUiState().isDarkMode ? Color.White : this.themePrimary
  }
  private get chatInputEnterKeySend(): boolean {
    return getAppUiState().chatInputEnterKeySend
  }
  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }
  private get manuscriptAccent(): string {
    return getAppUiState().isDarkMode ? '#C99A52' : '#B68235'
  }
  private get manuscriptAccentDeep(): string {
    return getAppUiState().isDarkMode ? '#D9B274' : '#8A6228'
  }
  // ========== 最近截图相关 ==========
  private recentPhotoOptions: RecentPhotoOptions = new RecentPhotoOptions()
  @Local hasRecentPhoto: boolean = false // 当前是否存在符合时间条件的截图
  // ========== 编辑模式相关属性 ==========
  @Param isEditing: boolean = false // 是否编辑模式
  @Event onCancelEdit: () => void = () => {
  } // 取消编辑回调
  @Event onSend: () => void = () => {
  }
  @Event onStop: () => void = () => {
  }
  @Event onModelIconClick: () => void = () => {
  }
  @Param isAttachmentPanelOpen: boolean = false
  @Event onAttachmentClick: () => void = () => {
  }
  @Event onInputFocus: () => void = () => {
  } // 输入框获得焦点回调
  @Event onInputBlur: () => void = () => {
  } // 输入框失去焦点回调
  @Event onComposerContentChanged: () => void = () => {
  }
  // 书稿模式页脚快捷操作：由聊天页沿用原有显示条件与业务回调。
  @Param showManuscriptScrollTop: boolean = false
  @Param showManuscriptScrollBottom: boolean = false
  @Param manuscriptScrollBottomLoading: boolean = false
  @Param showManuscriptHistory: boolean = false
  @Param showManuscriptCanvas: boolean = false
  @Event onManuscriptScrollTop: () => void = () => {}
  @Event onManuscriptScrollBottom: () => void = () => {}
  @Event onManuscriptHistory: () => void = () => {}
  @Event onManuscriptCanvas: () => void = () => {}
  // 最近截图检测回调（通知父组件渲染 banner）
  @Event onRecentPhotoDetected: (detected: boolean) => void = () => {
  }
  private lastHasContent: boolean = false
  private breatheTimerId: number = -1
  // 焦点控制器
  private focusController: TextAreaController = new TextAreaController()

  private getCurrentModelIconPath(): string {
    if (this.currentModelId === '' || this.currentProviderId === '') {
      return ''
    }
    return getModelIconPath(this.currentModelId, this.currentProviderId, '')
  }

  private getCurrentModelIconResourcePath(): string {
    const iconPath = this.getCurrentModelIconPath()
    if (iconPath === '') {
      return ''
    }
    return buildIconResourcePath(iconPath)
  }

  private hasCurrentModelIcon(): boolean {
    return this.getCurrentModelIconResourcePath() !== ''
  }

  aboutToAppear(): void {
    ensureManuscriptFonts()
    this.lastHasContent = this.computeHasContent()
    this.updateBreathing()
    this.initRecentPhotoOptions()
  }

  aboutToDisappear(): void {
    this.stopBreathing()
  }

  // 监听 autoFocus 变化
  @Monitor('autoFocus')
  onAutoFocusChanged(): void {
    if (this.autoFocus) {
      // 延迟聚焦，确保组件已渲染
      setTimeout(() => {
        focusControl.requestFocus(this.isManuscriptMode ? 'manuscriptChatInputTextArea' : 'chatInputTextArea')
      }, 50)
    }
  }

  build() {
    Column() {
      // 隐藏的 RecentPhotoComponent 用于检测截图
      this.HiddenRecentPhotoDetector()

      // 附件预览区域
      this.AttachmentPreview()

      if (this.isManuscriptMode) {
        this.ManuscriptBar()
      } else if (this.isEditing) {
        Stack({ alignContent: Alignment.Top }) {
          // 编辑态底板始终比当前输入栏高一个标题区，并随多行输入实时撑高。
          Column()
            .width('100%')
            .height(this.immersiveBarHeightVp + this.editingHeaderHeightVp)
            .backgroundColor(this.themeAiBubble)
            .borderRadius(24)

          Column() {
            Blank()
              .height(this.editingHeaderHeightVp)

            this.ImmersiveBar()
          }
          .width('100%')

          Row() {
            SymbolGlyph($r('sys.symbol.square_and_pencil'))
              .fontSize(12)
              .fontColor([this.themePrimary])

            Text($r('app.string.editing_message'))
              .fontSize(12)
              .fontColor(this.themePrimary)
              .margin({ left: 4 })
          }
          .width('100%')
          .height(this.editingHeaderHeightVp)
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height(this.immersiveBarHeightVp + this.editingHeaderHeightVp)
      } else {
        // 输入栏主体（整条沉浸光感浮动面）
        this.ImmersiveBar()
      }
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .clip(false)
  }

  @Builder
  private ManuscriptFooterIconButton(icon: Resource, isLoading: boolean, onClick: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Stack({ alignContent: Alignment.Center }) {
        if (isLoading) {
          Progress({ value: 25, total: 100, type: ProgressType.Ring })
            .width(28)
            .height(28)
            .color(this.manuscriptAccent)
            .backgroundColor(Color.Transparent)
            .style({ strokeWidth: 1.5 })
            .hitTestBehavior(HitTestMode.None)
        }

        SymbolGlyph(icon)
          .fontSize(isLoading ? 14 : 16)
          .fontColor([this.manuscriptAccentDeep])
      }
      .width(36)
      .height(36)
    }
    .width(40)
    .height(40)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(0)
    .border({ width: 0, color: Color.Transparent })
    .responseRegion({ x: -2, y: -2, width: 44, height: 44 })
    .onClick(onClick)
  }

  @Builder
  ManuscriptBar() {
    Column({ space: 9 }) {
      if (this.isEditing) {
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(11)
            .fontColor([this.manuscriptAccentDeep])
          Text($r('app.string.editing_message'))
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontSize(11)
            .fontStyle(FontStyle.Italic)
            .fontColor(this.manuscriptAccentDeep)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.onCancelEdit()
        })
      }

      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          if (this.currentModelId !== '' && this.hasCurrentModelIcon()) {
            Image(this.getCurrentModelIconResourcePath())
              .width(18)
              .height(18)
              .objectFit(ImageFit.Contain)
              .fillColor(this.modelBtnPressed ? this.manuscriptAccentDeep : getAppUiState().themeTextSecondary)
          } else {
            SymbolGlyph($r('sys.symbol.ai_edit'))
              .fontSize(18)
              .fontColor([this.modelBtnPressed ? this.manuscriptAccentDeep : getAppUiState().themeTextSecondary])
          }
        }
        .width(44)
        .height(44)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .onTouch((event: TouchEvent) => {
          this.modelBtnPressed = event.type === TouchType.Down
        })
        .onClick(() => {
          this.onModelIconClick()
        })

        TextArea({ text: this.inputText, placeholder: $r('app.string.manuscript_reply_placeholder') })
          .id('manuscriptChatInputTextArea')
          .placeholderColor(getAppUiState().themeTextTertiary)
          .placeholderFont({ size: 15, style: FontStyle.Italic, family: MANUSCRIPT_BODY_FONT })
          .fontFamily(MANUSCRIPT_BODY_FONT)
          .fontSize(15)
          .fontColor(getAppUiState().themeTextPrimary)
          .caretColor(this.manuscriptAccentDeep)
          .enterKeyType(this.chatInputEnterKeySend ? EnterKeyType.Send : EnterKeyType.NEW_LINE)
          .backgroundColor(Color.Transparent)
          .border({ width: { bottom: 1 }, color: getAppUiState().themeTextSecondary })
          .borderRadius(0)
          .padding({ left: 0, right: 4, top: 8, bottom: 7 })
          .layoutWeight(1)
          .constraintSize({ minHeight: 44, maxHeight: 112 })
          .onChange((value: string) => {
            this.onInputTextChange(value)
          })
          .onSubmit(() => {
            if (this.chatInputEnterKeySend && !this.isSendBusy() && this.computeHasContent()) {
              this.onSend()
            }
          })
          .onFocus(() => {
            this.onInputFocus()
          })
          .onBlur(() => {
            this.onInputBlur()
          })

        Button({ type: ButtonType.Normal, stateEffect: false }) {
          SymbolGlyph(this.getAttachmentButtonSymbol())
            .fontSize(18)
            .fontColor([this.attachmentBtnPressed ? this.manuscriptAccentDeep :
              getAppUiState().themeTextSecondary])
            .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), this.attachIconTrigger)
        }
        .width(44)
        .height(44)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .onTouch((event: TouchEvent) => {
          this.attachmentBtnPressed = event.type === TouchType.Down
        })
        .onClick(() => {
          this.onAttachmentClick()
        })

        Button({ type: ButtonType.Normal, stateEffect: false }) {
          Text(this.isSending ? $r('app.string.manuscript_stop') : $r('app.string.manuscript_send'))
            .fontFamily(MANUSCRIPT_HEADING_FONT)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.sendBtnPressed ? this.manuscriptAccent : this.manuscriptAccentDeep)
            .letterSpacing(2)
            .padding({ left: 2, right: 2 })
        }
        .width(58)
        .height(44)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .opacity(this.isSending || (!this.isSendDispatching && this.computeHasContent()) ? 1 : 0.45)
        .onTouch((event: TouchEvent) => {
          this.sendBtnPressed = event.type === TouchType.Down
        })
        .onClick(() => {
          if (this.isSending) {
            this.onStop()
          } else if (!this.isSendDispatching && this.computeHasContent()) {
            this.onSend()
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      Row() {
        Text($r('app.string.manuscript_folio_label'))
          .fontFamily(MANUSCRIPT_BODY_FONT)
          .fontSize(10)
          .fontColor(getAppUiState().themeTextTertiary)
          .fontFeature('tnum')

        Blank()

        Row({ space: 4 }) {
          if (this.showManuscriptScrollTop) {
            this.ManuscriptFooterIconButton($r('sys.symbol.arrow_up_to_line'), false, () => {
              this.onManuscriptScrollTop()
            })
          }

          if (this.showManuscriptScrollBottom) {
            this.ManuscriptFooterIconButton($r('sys.symbol.chevron_down'),
              this.manuscriptScrollBottomLoading, () => {
                this.onManuscriptScrollBottom()
              })
          }

          if (this.showManuscriptHistory) {
            this.ManuscriptFooterIconButton($r('sys.symbol.ellipsis_message'), false, () => {
              this.onManuscriptHistory()
            })
          }

          if (this.showManuscriptCanvas) {
            this.ManuscriptFooterIconButton($r('sys.symbol.paintbrush_pointed_waveform'), false, () => {
              this.onManuscriptCanvas()
            })
          }
        }
        .height(40)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 4, bottom: 2 })
    .backgroundColor(Color.Transparent)
    .transition(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 }))
        .animation({ duration: 550, curve: Curve.EaseInOut })
    )
  }

  // 整条输入栏作为单一沉浸光感浮动面（Row + systemMaterial）；高度随输入内容自适应展开
  @Builder
  ImmersiveBar() {
    Row() {
      this.InputRow()
    }
    .width('100%')
    .constraintSize({ minHeight: 52, maxHeight: 132 })
    .backgroundColor(Color.Transparent)
    .borderRadius(24)
    .clip(false)
    .border({
      width: this.isEditing ? 2 : 0,
      color: this.isEditing ? this.themePrimary : Color.Transparent
    })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      // 输入栏底板只保留材质外观，禁用按压时的整体形变。
      interactive: false,
      lightEffect: { color: undefined }
    }))
    .shadow({
      radius: this.isEditing ? 16 : 32,
      color: this.isEditing ? withColorAlpha(this.themePrimary, '26') : 'rgba(0, 0, 0, 0.1)',
      offsetX: 0,
      offsetY: this.isEditing ? -4 : 8
    })
    .animation({ duration: 200, curve: Curve.EaseOut })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const measuredHeight = Number(newArea.height)
      if (Number.isFinite(measuredHeight) && measuredHeight > 0 &&
        Math.abs(this.immersiveBarHeightVp - measuredHeight) > 0.5) {
        this.immersiveBarHeightVp = measuredHeight
      }
    })
  }

  @Builder
  InputRow() {
    Row() {
      // 模型图标按钮 - 点击触发快速切换（编辑模式下也可点击切换模型）
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.currentModelId !== '') {
            if (this.hasCurrentModelIcon()) {
              Column() {
                Image(this.getCurrentModelIconResourcePath())
                  .width(18)
                  .height(18)
                  .objectFit(ImageFit.Contain)
                  .fillColor(this.inputButtonIconColor)
              }
              .width(28)
              .height(28)
              .borderRadius(7)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else {
              Column() {
                SymbolGlyph($r('sys.symbol.ai_edit'))
                  .fontSize(14)
                  .fontColor([this.themePrimary])
              }
              .width(28)
              .height(28)
              .borderRadius(7)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }
          } else {
            SymbolGlyph($r('sys.symbol.ai_edit'))
              .fontSize(22)
              .fontColor([this.themePrimary])
          }
        }
        .width(40)
        .height(40)
      }
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        materialColor: withColorAlpha(this.themeUserBubble, '40'),
        applyShadow: false,
        interactive: true,
        lightEffect: { color: undefined }
      }))
      .scale({ x: this.modelBtnPressed ? 0.95 : 1, y: this.modelBtnPressed ? 0.95 : 1 })
      .animation({ duration: 150, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.modelBtnPressed = true
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.modelBtnPressed = false
        }
      })
      .onClick(() => {
        this.onModelIconClick()
      })

        // 输入框
        TextArea({ text: this.inputText, placeholder: $r('app.string.input_placeholder') })
          .id('chatInputTextArea')
          .placeholderColor($r('app.color.text_tertiary'))
          .placeholderFont({ size: 16 })
          .enterKeyType(this.chatInputEnterKeySend ? EnterKeyType.Send : EnterKeyType.NEW_LINE)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .constraintSize({ minHeight: 40, maxHeight: 120 })
          .padding({
            left: 12,
            right: 12,
            top: 10,
            bottom: 10
          })
          .onChange((value: string) => {
            this.onInputTextChange(value)
          })
          .onSubmit(() => {
            if (!this.chatInputEnterKeySend) {
              return
            }
            if (!this.isSendBusy() && this.computeHasContent()) {
              this.onSend()
            }
          })
          .onFocus(() => {
            this.onInputFocus()
          })
          .onBlur(() => {
            this.onInputBlur()
          })

        // 附件按钮（+号 / x号）
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          SymbolGlyph(this.getAttachmentButtonSymbol())
            .fontSize(20)
            .fontColor([$r('app.color.text_secondary')])
            .symbolEffect(
              new ReplaceSymbolEffect(EffectScope.WHOLE),
              this.attachIconTrigger
            )
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onAttachmentClick()
        })

        // 发送/停止按钮（编辑模式下为"保存并发送"）
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          SymbolGlyph(this.getSendButtonSymbol())
            .fontSize(this.isSending ? 20 : 22)
            .fontColor([this.themePrimary])
            .symbolEffect(
              new ScaleSymbolEffect(EffectScope.WHOLE),
              this.iconTrigger
            )
        }
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR,
          materialColor: withColorAlpha(this.themeUserBubble, '40'),
          applyShadow: false,
          interactive: true,
          lightEffect: { color: undefined }
        }))
        .opacity(this.breathOpacity)
        .scale({
          x: this.sendBtnPressed ? 0.95 * this.sendBtnScale : this.sendBtnScale,
          y: this.sendBtnPressed ? 0.95 * this.sendBtnScale : this.sendBtnScale
        })
        .rotate({ angle: this.sendBtnRotation })
        .animation({ duration: 200, curve: Curve.EaseInOut })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.sendBtnPressed = true
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.sendBtnPressed = false
          }
        })
        .onClick(() => {
          if (this.isSending) {
            this.onStop()
          } else if (this.isSendDispatching) {
            return
          } else {
            if (!this.computeHasContent()) {
              return
            }
            this.onSend()
          }
        })
      }
      .width('100%')
      .padding({
        left: 6,
        right: 6,
        top: 6,
        bottom: 6
      })
  }

  @Builder
  AttachmentPreview() {
    Scroll() {
      Row() {
        ForEach(this.attachments, (attachment: MessageAttachment, index: number) => {
          this.AttachmentItem(attachment, index)
        })
      }
      .justifyContent(FlexAlign.Start)
      .padding({
        left: 8,
        right: 8,
        top: this.attachments.length > 0 ? 8 : 0,
        bottom: this.attachments.length > 0 ? 4 : 0
      })
      .height(this.attachments.length > 0 ? 'auto' : 0)
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
    .height(this.attachments.length > 0 ? 'auto' : 0)
  }

  // 隐藏的 RecentPhotoComponent 用于检测截图
  @Builder
  HiddenRecentPhotoDetector() {
    RecentPhotoComponent({
      recentPhotoOptions: this.recentPhotoOptions,
      onRecentPhotoClick: (info: BaseItemInfo): boolean => {
        // 无需处理，我们使用自定义UI
        return true
      },
      onRecentPhotoCheckResult: (exists: boolean): void => this.onReceiveCheckResult(exists)
    })
      .width(0)
      .height(0)
      .opacity(0)
  }

  @Builder
  AttachmentItem(attachment: MessageAttachment, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (attachment.type === AttachmentType.IMAGE) {
        // 图片预览 - 优先使用文件路径（需要 file:// 协议），备选使用 base64
        if (attachment.filePath !== '') {
          Image('file://' + attachment.filePath)
            .width(60)
            .height(60)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
        } else if (attachment.base64Data !== '') {
          Image(`data:${attachment.mimeType};base64,${attachment.base64Data}`)
            .width(60)
            .height(60)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
        }
      } else {
        // 文件预览
        Column() {
          SymbolGlyph($r('sys.symbol.doc'))
            .fontSize(24)
            .fontColor([$r('app.color.text_secondary')])

          Text(attachment.name)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 50 })
        }
        .width(60)
        .height(60)
        .borderRadius(8)
        .backgroundColor(this.themeBackground)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      // 删除按钮
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(10)
          .fontColor([Color.White])
      }
      .width(18)
      .height(18)
      .backgroundColor('rgba(0, 0, 0, 0.6)')
      .margin({ top: -4, right: -4 })
      .onClick(() => {
        this.removeAttachment(index)
      })
    }
    .margin({ right: 8 })
  }

  private removeAttachment(index: number): void {
    const newAttachments = [...this.attachments]
    newAttachments.splice(index, 1)
    this.onAttachmentsChange([...newAttachments])
  }

  // ========== 最近截图相关方法 ==========

  // 初始化最近截图组件配置
  private initRecentPhotoOptions(): void {
    // 只监听图片类型
    this.recentPhotoOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
    // 时间范围：1分钟（60秒），适合刚截图的场景
    this.recentPhotoOptions.period = 60
    // 只监听截图来源
    this.recentPhotoOptions.photoSource = PhotoSource.SCREENSHOT
    console.info('ChatInputBar', 'RecentPhoto options initialized')
  }

  // 最近截图检查结果回调
  private onReceiveCheckResult(exists: boolean): void {
    console.info('ChatInputBar', `RecentPhoto check result: exists=${exists}`)
    this.hasRecentPhoto = exists
    // 通知父组件
    this.onRecentPhotoDetected(exists)
  }

  private computeHasContent(): boolean {
    return this.inputText.trim() !== '' || this.attachments.length > 0
  }

  private isSendBusy(): boolean {
    return this.isSending || this.isSendDispatching
  }

  private getSendButtonSymbol(): Resource {
    if (this.isSending) {
      return $r('sys.symbol.pause_round_triangle')
    }

    if (this.computeHasContent()) {
      return $r('sys.symbol.paperplane_fill')
    }

    return $r('sys.symbol.paperplane')
  }

  private getAttachmentButtonSymbol(): Resource {
    return this.isAttachmentPanelOpen ? $r('sys.symbol.xmark') : $r('sys.symbol.plus')
  }

  @Monitor('inputText', 'attachments')
  onInputOrAttachmentsChanged(): void {
    if (!this.isSendBusy()) {
      this.onComposerContentChanged()
    }
    if (this.isSendBusy()) {
      return
    }

    const hasContent = this.computeHasContent()
    if (hasContent === this.lastHasContent) {
      return
    }

    this.lastHasContent = hasContent
    this.iconTrigger++
  }

  @Monitor('isSending')
  onSendingChanged(): void {
    this.iconTrigger++
    this.lastHasContent = this.computeHasContent()
    this.updateBreathing()
    // 发送按钮状态切换动画
    this.animateSendButton()
  }

  @Monitor('isSendDispatching')
  onSendDispatchingChanged(): void {
    this.iconTrigger++
    this.updateBreathing()
    this.animateSendButton()
  }

  @Monitor('isAttachmentPanelOpen')
  onAttachmentPanelOpenChanged(): void {
    this.attachIconTrigger++
  }

  // 发送按钮状态切换动画
  private animateSendButton(): void {
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.sendBtnScale = this.isSendBusy() ? 0.9 : 1
      this.sendBtnRotation = 0
    })
  }


  @Monitor('isAwaitingResponse')
  onAwaitingChanged(): void {
    this.updateBreathing()
  }

  private updateBreathing(): void {
    if (this.isSendBusy()) {
      this.startBreathing()
      return
    }

    this.stopBreathing()
  }

  private startBreathing(): void {
    if (this.breatheTimerId >= 0) {
      return
    }

    this.breathOpacity = 1
    this.breatheTimerId = setInterval(() => {
      this.breathOpacity = this.breathOpacity > 0.8 ? 0.35 : 1
    }, 850)
  }

  private stopBreathing(): void {
    if (this.breatheTimerId < 0) {
      this.breathOpacity = 1
      return
    }

    clearInterval(this.breatheTimerId)
    this.breatheTimerId = -1
    this.breathOpacity = 1
  }
}
