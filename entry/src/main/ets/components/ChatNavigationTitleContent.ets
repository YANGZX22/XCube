import { uiMaterial } from '@kit.ArkUI'
import { ChatMarkdownHybridRenderer } from './ChatMarkdownHybridRenderer'
import { ProviderIconSmall } from './ProviderIcon'
import { getAppUiState } from '../state/AppUiState'
import { buildIconResourcePath, getModelIconPath, isNetworkIconPath, isSandboxIconPath } from '../utils/ProviderIconUtils'
import { VisualEffectsMode } from '../models/ThemeColors'
import {
  ensureManuscriptFonts,
  MANUSCRIPT_BODY_FONT,
  MANUSCRIPT_HEADING_FONT
} from '../utils/ManuscriptVisualUtils'

export const CHAT_NAVIGATION_TITLE_STACK_BUILDER_HEIGHT = 56
export const CHAT_NAVIGATION_MANUSCRIPT_STACK_BUILDER_HEIGHT = 88
export const CHAT_NAVIGATION_MANUSCRIPT_BOTTOM_EXTENSION_HEIGHT =
  CHAT_NAVIGATION_MANUSCRIPT_STACK_BUILDER_HEIGHT - CHAT_NAVIGATION_TITLE_STACK_BUILDER_HEIGHT
const CHAT_NAVIGATION_CONTENT_VERTICAL_OFFSET = -1
// 书稿标题比系统 56vp 标题槽高 32vp；自绘内容会被居中并向上溢出一半，需要整体下移 16vp 对齐槽顶。
const CHAT_NAVIGATION_MANUSCRIPT_CONTENT_VERTICAL_OFFSET =
  CHAT_NAVIGATION_MANUSCRIPT_BOTTOM_EXTENSION_HEIGHT / 2
// 标题栏尾部操作按钮尺寸，与 HDS 系统菜单图标保持一致
const CHAT_NAVIGATION_ACTION_BUTTON_SIZE = 40
const CHAT_NAVIGATION_ACTION_BUTTON_ICON_SIZE = 20
const CHAT_NAVIGATION_ACTION_BUTTON_SPACE = 4
const CHAT_NAVIGATION_MANUSCRIPT_ACTION_BUTTON_SIZE = 30
const CHAT_NAVIGATION_MANUSCRIPT_ACTION_BUTTON_ICON_SIZE = 16

@ComponentV2
export struct ChatNavigationTitleContent {
  @Param sessionTitle: string = '新对话'
  @Param currentModelId: string = ''
  @Param currentProviderId: string = ''
  @Param currentModelName: string = ''
  @Param currentProviderName: string = ''
  @Param currentProviderIconType: string = 'svg'
  @Param currentProviderIconPath: string = ''
  @Param currentProviderTextIcon: string = ''
  @Param currentProviderTextIconBgColor: string = ''
  @Param currentProviderCustomImagePath: string = ''
  @Param currentProviderBrandColor: ResourceColor = ''
  @Param isTitleGenerating: boolean = false
  @Param titleGenerateFailed: boolean = false
  @Param isSending: boolean = false
  @Param titleStartInset: number = 64
  @Param titleEndInset: number = 16
  @Param showLeadingBackAction: boolean = false
  // 尾部操作区：新对话、上下文长度窗口、更多菜单。
  // 上下文用量以基础类型传入，保证压缩后父组件重算能可靠触发按钮重绘。
  @Param showNewChatAction: boolean = false
  @Param showContextProgress: boolean = false
  @Param contextPercent: number = 0
  @Param contextOverThreshold: boolean = false

  @Event onModelSelect: () => void = () => {}
  @Event onRegenerateTitle: () => void = () => {}
  @Event onWillEditTitle: () => void = () => {}
  @Event onTitleChanged: (newTitle: string) => void = (_newTitle: string): void => {}
  @Event onNewChat: () => void = () => {}
  @Event onContextProgressClick: () => void = () => {}
  @Event onDeleteChat: () => void = () => {}
  @Event onBack: () => void = () => {}

  @Local private isEditingTitle: boolean = false
  @Local private editingTitleInput: string = ''
  @Local private manuscriptTitleMarqueeActive: boolean = false
  private readonly titleInputFocusId: string = 'chat_navigation_title_input'
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private getActionButtonSize(): number {
    return this.isManuscriptMode
      ? CHAT_NAVIGATION_MANUSCRIPT_ACTION_BUTTON_SIZE : CHAT_NAVIGATION_ACTION_BUTTON_SIZE
  }

  private getActionButtonIconSize(): number {
    return this.isManuscriptMode
      ? CHAT_NAVIGATION_MANUSCRIPT_ACTION_BUTTON_ICON_SIZE : CHAT_NAVIGATION_ACTION_BUTTON_ICON_SIZE
  }

  aboutToAppear(): void {
    ensureManuscriptFonts()
  }

  private getModelIdentityTextColor(): string {
    return this.isDarkMode ? '#F3F5F7' : '#1F2329'
  }

  private getModelIdentityChevronColor(): string {
    return this.isDarkMode ? '#C7CDD5' : '#5A6573'
  }

  private hasCurrentModelIdentity(): boolean {
    return this.currentModelId !== '' || this.currentModelName !== ''
  }

  private getCurrentModelIconPath(): string {
    if (this.currentModelId !== '') {
      const iconById = getModelIconPath(this.currentModelId, this.currentProviderId, '')
      if (iconById !== '') {
        return iconById
      }
    }
    if (this.currentModelName !== '') {
      return getModelIconPath(this.currentModelName, this.currentProviderId, '')
    }
    return ''
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

  private isRawfileCurrentModelIcon(): boolean {
    const resourcePath = this.getCurrentModelIconResourcePath()
    return resourcePath !== '' && !isNetworkIconPath(resourcePath) && !isSandboxIconPath(resourcePath)
  }

  private hasProviderIdentity(): boolean {
    return this.currentProviderName !== '' ||
      this.currentProviderTextIcon !== '' ||
      this.currentProviderIconPath !== '' ||
      this.currentProviderCustomImagePath !== ''
  }

  private getCurrentModelTitle(): string | Resource {
    if (this.currentModelName !== '') {
      return this.currentModelName
    }
    return $r('app.string.select_model')
  }

  private titleContainsLatex(): boolean {
    return /\$.+?\$/.test(this.sessionTitle) ||
      this.sessionTitle.includes('\\(') ||
      this.sessionTitle.includes('\\[')
  }

  private normalizeLatexInTitle(title: string): string {
    let result = title
    result = result.replace(/\\\[([\s\S]*?)\\\]/g, (_match: string, p1: string): string => `$$${p1}$$`)
    result = result.replace(/\\\(([\s\S]*?)\\\)/g, (_match: string, p1: string): string => `$${p1}$`)
    return result
  }

  private startEditingTitle(): void {
    if (this.isEditingTitle) {
      return
    }
    this.onWillEditTitle()
    this.editingTitleInput = this.sessionTitle
    this.isEditingTitle = true
    setTimeout(() => {
      if (this.isEditingTitle) {
        this.getUIContext().getFocusController().requestFocus(this.titleInputFocusId)
      }
    }, 60)
  }

  private finishEditingTitle(): void {
    this.isEditingTitle = false
    const nextTitle = this.editingTitleInput.trim()
    if (nextTitle !== '' && nextTitle !== this.sessionTitle) {
      this.onTitleChanged(nextTitle)
    }
  }

  @Builder
  private IdentityIconBuilder() {
    if (this.hasCurrentModelIcon()) {
      Column() {
        if (this.isRawfileCurrentModelIcon()) {
          Image($rawfile(this.getCurrentModelIconResourcePath()))
            .width(14)
            .height(14)
            .objectFit(ImageFit.Contain)
        } else {
          Image(this.getCurrentModelIconResourcePath())
            .width(14)
            .height(14)
            .objectFit(ImageFit.Contain)
        }
      }
      .width(22)
      .height(22)
      .borderRadius(6)
      .backgroundColor($r('app.color.model_icon_bg'))
      .border({ width: 1, color: this.themePrimaryLight })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else if (this.hasProviderIdentity()) {
      ProviderIconSmall({
        iconPath: this.currentProviderIconPath,
        iconSize: 20,
        iconType: this.currentProviderIconType,
        textIcon: this.currentProviderTextIcon,
        textIconBgColor: this.currentProviderTextIconBgColor,
        customImagePath: this.currentProviderCustomImagePath,
        brandColor: this.currentProviderBrandColor,
        isDarkMode: this.isDarkMode
      })
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.ai_edit'))
          .fontSize(14)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width(22)
      .height(22)
      .borderRadius(6)
      .backgroundColor($r('app.color.model_icon_bg'))
      .border({ width: 1, color: this.themePrimaryLight })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  // 上下文接近或超出窗口时用警示色，其余沿用主题色
  private getContextProgressColor(): ResourceColor {
    if (this.contextPercent >= 100) {
      return $r('app.color.status_error')
    }
    if (this.contextOverThreshold) {
      return $r('app.color.status_warning')
    }
    return this.themePrimary
  }

  // 超窗时进度环填满，具体数值由颜色和对话框呈现
  private getContextProgressValue(): number {
    return Math.min(100, Math.max(0, this.contextPercent))
  }

  @Builder
  private MoreMenuBuilder() {
    Menu() {
      MenuItem({
        startIcon: $r('sys.symbol.square_and_pencil'),
        content: $r('app.string.edit_chat_title')
      })
        .onClick(() => {
          this.startEditingTitle()
        })

      MenuItem({
        startIcon: $r('sys.symbol.arrow_clockwise'),
        content: $r('app.string.regenerate_title')
      })
        .enabled(!this.isTitleGenerating && !this.isSending)
        .onClick(() => {
          this.onRegenerateTitle()
        })

      MenuItemGroup() {
        MenuItem({
          startIcon: $r('sys.symbol.trash'),
          content: $r('app.string.delete_chat')
        })
          .contentFontColor($r('app.color.status_error'))
          .onClick(() => {
            this.onDeleteChat()
          })
      }
    }
  }

  @Builder
  private TrailingActionsBuilder() {
    Row({ space: CHAT_NAVIGATION_ACTION_BUTTON_SPACE }) {
      if (this.showNewChatAction) {
        Button({ type: this.isManuscriptMode ? ButtonType.Normal : ButtonType.Circle,
          stateEffect: false }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(this.getActionButtonIconSize())
            .fontColor([this.isManuscriptMode ? getAppUiState().themeTextSecondary :
              $r('app.color.text_primary')])
        }
        .width(this.getActionButtonSize())
        .height(this.getActionButtonSize())
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(this.isManuscriptMode ? 0 : this.getActionButtonSize() / 2)
        .clip(!this.isManuscriptMode)
        .onClick(() => {
          this.onNewChat()
        })
        .systemMaterial(this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR,
          interactive: true,
          lightEffect: { color: undefined }
        }))
      }

      if (this.showContextProgress) {
        Button({ type: this.isManuscriptMode ? ButtonType.Normal : ButtonType.Circle,
          stateEffect: false }) {
          Progress({
            value: this.getContextProgressValue(),
            total: 100,
            type: ProgressType.Eclipse
          })
            .color(this.getContextProgressColor())
            .width(this.getActionButtonIconSize())
            .height(this.getActionButtonIconSize())
        }
        .width(this.getActionButtonSize())
        .height(this.getActionButtonSize())
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(this.isManuscriptMode ? 0 : this.getActionButtonSize() / 2)
        .clip(!this.isManuscriptMode)
        .accessibilityText(`${this.contextPercent}%`)
        .onClick(() => {
          this.onContextProgressClick()
        })
        .systemMaterial(this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR,
          interactive: true,
          lightEffect: { color: undefined }
        }))
      }

      Button({ type: this.isManuscriptMode ? ButtonType.Normal : ButtonType.Circle,
        stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
          .fontSize(this.getActionButtonIconSize())
          .fontColor([this.isManuscriptMode ? getAppUiState().themeTextSecondary :
            $r('app.color.text_primary')])
      }
      .width(this.getActionButtonSize())
      .height(this.getActionButtonSize())
      .padding(0)
      .backgroundColor(Color.Transparent)
      .borderRadius(this.isManuscriptMode ? 0 : this.getActionButtonSize() / 2)
      .clip(!this.isManuscriptMode)
      .bindMenu(this.MoreMenuBuilder(), {
        systemMaterial: new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THICK
        })
      })
      .systemMaterial(this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true,
        lightEffect: { color: undefined }
      }))
    }
    .height(this.getActionButtonSize())
    .padding({ left: this.isManuscriptMode ? 2 : 0, right: this.isManuscriptMode ? 2 : 0 })
    .borderRadius(this.isManuscriptMode ? 0 : this.getActionButtonSize() / 2)
    .border({ width: 0, color: Color.Transparent })
    .clip(false)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ManuscriptHeaderBuilder() {
    Column({ space: 0 }) {
      Row() {
        if (this.showLeadingBackAction) {
          Button({ type: ButtonType.Normal, stateEffect: false }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(this.getActionButtonIconSize())
              .fontColor([getAppUiState().themeTextSecondary])
          }
          .width(this.getActionButtonSize())
          .height(this.getActionButtonSize())
          .padding(0)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .border({ width: 0, color: Color.Transparent })
          .clip(false)
          .onClick(() => {
            this.onBack()
          })
        }

        Blank()

        this.TrailingActionsBuilder()
      }
      .width('100%')
      .height(32)
      .alignItems(VerticalAlign.Center)

      Column({ space: 0 }) {
        if (this.isEditingTitle) {
          TextInput({ text: this.editingTitleInput, placeholder: $r('app.string.chat_title_input_placeholder') })
            .id(this.titleInputFocusId)
            .defaultFocus(true)
            .fontFamily(MANUSCRIPT_HEADING_FONT)
            .fontSize(18)
            .fontColor(getAppUiState().themeTextPrimary)
            .placeholderColor(getAppUiState().themeTextTertiary)
            .backgroundColor(Color.Transparent)
            .border({ width: { bottom: 1 }, color: this.themePrimary })
            .borderRadius(0)
            .maxLength(50)
            .height(42)
            .width('100%')
            .textAlign(TextAlign.Center)
            .onChange((value: string) => {
              this.editingTitleInput = value
            })
            .onSubmit(() => {
              this.finishEditingTitle()
            })
            .onBlur(() => {
              this.finishEditingTitle()
            })
        } else {
          Text($r('app.string.manuscript_conversation_kicker'))
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontSize(8)
            .fontWeight(FontWeight.Medium)
            .fontColor(getAppUiState().themeTextSecondary)
            .letterSpacing(1.5)
            .fontFeature('tnum')
            .maxLines(1)
            .onClick(() => {
              this.onModelSelect()
            })

          Text(this.sessionTitle)
            .fontFamily(MANUSCRIPT_HEADING_FONT)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor(getAppUiState().themeTextPrimary)
            .lineHeight(25)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.MARQUEE })
            .marqueeOptions({
              start: this.manuscriptTitleMarqueeActive,
              step: 3,
              loop: -1,
              fromStart: true,
              delay: 600,
              fadeout: true
            })
            .width('100%')
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.manuscriptTitleMarqueeActive = !this.manuscriptTitleMarqueeActive
            })
        }
      }
      .width('100%')
      .height(55)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .gesture(
        LongPressGesture()
          .onAction(() => {
            this.startEditingTitle()
          })
      )

      Divider()
        .width('100%')
        .strokeWidth(0.5)
        .color(getAppUiState().themeDivider)
    }
    .width('100%')
    .height(CHAT_NAVIGATION_MANUSCRIPT_STACK_BUILDER_HEIGHT)
    .padding({ left: 24, right: 24 })
    .translate({ y: CHAT_NAVIGATION_MANUSCRIPT_CONTENT_VERTICAL_OFFSET })
    .backgroundColor(Color.Transparent)
    .renderGroup(false)
  }

  build() {
    if (this.isManuscriptMode) {
      this.ManuscriptHeaderBuilder()
    } else {
      Row() {
      if (this.showLeadingBackAction) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(CHAT_NAVIGATION_ACTION_BUTTON_ICON_SIZE)
            .fontColor([this.themePrimary])
        }
        .width(CHAT_NAVIGATION_ACTION_BUTTON_SIZE)
        .height(CHAT_NAVIGATION_ACTION_BUTTON_SIZE)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .border({ width: { bottom: 1 }, color: this.themePrimary })
        .onClick(() => {
          this.onBack()
        })
      }

      Column() {
        if (this.isManuscriptMode && !this.isEditingTitle) {
          Column({ space: 0 }) {
            Text($r('app.string.manuscript_conversation_kicker'))
              .fontFamily(MANUSCRIPT_BODY_FONT)
              .fontSize(8)
              .fontWeight(FontWeight.Medium)
              .fontColor(getAppUiState().themeTextSecondary)
              .letterSpacing(1.5)
              .fontFeature('tnum')
              .maxLines(1)
              .onClick(() => {
                this.onModelSelect()
              })

            Text(this.sessionTitle)
              .fontFamily(MANUSCRIPT_HEADING_FONT)
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor(getAppUiState().themeTextPrimary)
              .lineHeight(23)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.MARQUEE })
              .marqueeOptions({
                start: this.manuscriptTitleMarqueeActive,
                step: 3,
                loop: -1,
                fromStart: true,
                delay: 600,
                fadeout: true
              })
              .width('100%')
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.manuscriptTitleMarqueeActive = !this.manuscriptTitleMarqueeActive
              })

            Divider()
              .width('100%')
              .strokeWidth(0.5)
              .color(getAppUiState().themeDivider)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .gesture(
            LongPressGesture()
              .onAction(() => {
                this.startEditingTitle()
              })
          )
        } else if (this.isEditingTitle) {
          TextInput({ text: this.editingTitleInput, placeholder: $r('app.string.chat_title_input_placeholder') })
            .id(this.titleInputFocusId)
            .defaultFocus(true)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .backgroundColor(Color.Transparent)
            .border({ width: { bottom: 1 }, color: this.themePrimary })
            .maxLength(50)
            .height(36)
            .width('100%')
            .onChange((value: string) => {
              this.editingTitleInput = value
            })
            .onSubmit(() => {
              this.finishEditingTitle()
            })
            .onBlur(() => {
              this.finishEditingTitle()
            })
        } else {
          Row({ space: 8 }) {
            Row() {
              this.IdentityIconBuilder()
            }
            .margin({ top: 1 })

            Column({ space: 1 }) {
              Row() {
                if (this.titleContainsLatex()) {
                  ChatMarkdownHybridRenderer({
                    content: this.normalizeLatexInTitle(this.sessionTitle),
                    isInputEnded: true,
                    incrementalAnalysis: false,
                    useCangjieComponent: true,
                    chatFontSize: 15,
                    compact: true,
                    latexFontSize: 15,
                    textColorOverride: getAppUiState().themeTextPrimary,
                    titleColorOverride: getAppUiState().themeTextPrimary,
                    themeRenderKey: this.sessionTitle
                  })
                    .layoutWeight(1)
                    .constraintSize({ maxHeight: 22 })
                    .clip(true)
                    .backgroundColor(Color.Transparent)
                } else {
                  Text(this.sessionTitle)
                    .layoutWeight(1)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .lineHeight(17)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }

                if (this.isTitleGenerating) {
                  LoadingProgress()
                    .width(12)
                    .height(12)
                    .color($r('app.color.text_tertiary'))
                    .margin({ left: 4 })
                }

                if (this.titleGenerateFailed && !this.isTitleGenerating) {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(12)
                    .fontColor([$r('app.color.text_tertiary')])
                    .margin({ left: 4 })
                    .onClick(() => {
                      this.onRegenerateTitle()
                    })
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .gesture(
                LongPressGesture()
                  .onAction(() => {
                    this.startEditingTitle()
                  })
              )

              Row({ space: 3 }) {
                Text(this.getCurrentModelTitle())
                  .layoutWeight(1)
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.getModelIdentityTextColor())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                SymbolGlyph($r('sys.symbol.chevron_down'))
                  .fontSize(12)
                  .fontColor([this.getModelIdentityChevronColor()])
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.onModelSelect()
              })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      }
      .layoutWeight(1)
      .height(CHAT_NAVIGATION_TITLE_STACK_BUILDER_HEIGHT)
      .padding({
        left: this.isEditingTitle ? 6 : 4,
        right: this.isEditingTitle ? 8 : 6,
        top: this.isEditingTitle ? 4 : 2,
        bottom: this.isEditingTitle ? 4 : 2
      })
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Color.Transparent)

      // 编辑标题时让输入框占满整行，尾部按钮暂时隐藏
      if (!this.isEditingTitle) {
        this.TrailingActionsBuilder()
      }
    }
    .width('100%')
    .height(CHAT_NAVIGATION_TITLE_STACK_BUILDER_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({ left: this.titleStartInset, right: this.titleEndInset })
    .translate({ y: CHAT_NAVIGATION_CONTENT_VERTICAL_OFFSET })
    .backgroundColor(Color.Transparent)
      .renderGroup(false)
    }
  }
}
