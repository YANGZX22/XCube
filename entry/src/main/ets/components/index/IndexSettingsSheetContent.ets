import { getSettingsTypography, SETTINGS_SUBTITLE_LINE_HEIGHT } from '../settings/SettingsTypography'
import { ImmersiveButtonSurface } from '../ImmersiveButtonSurface'
import { IMMERSIVE_MATERIAL_SHADOW_OUTSET } from '../ImmersiveMaterialBackdrop'
import { TabSegmentButtonV2, ColorMetrics, LengthMetrics, SegmentButtonV2Items, uiMaterial } from '@kit.ArkUI'
import { HandAdaptiveFollowTarget } from '../../config/HandAdaptiveSettings'
import { VisualEffectsMode } from '../../models/ThemeColors'
import { isWrappedMaterialApiAvailable, shouldUseWrappedMaterial } from '../../utils/WrappedMaterialSupport'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { ThemeMode, AppLanguage } from '../../services/PreferencesService'
import { SettingsSheetType } from '../../pages/index/IndexPageTypes'
import { IndexSettingsSheetActionCallbacks } from '../../pages/index/IndexSettingsSheetCoordinator'
import { getAppUiState } from '../../state/AppUiState'

const FOLLOW_TARGET_BUTTON_HEIGHT: number = 48

@ComponentV2
export struct IndexSettingsSheetContent {
  @Param settingsSheetType: SettingsSheetType = SettingsSheetType.NONE
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themeDivider(): string {
    return getAppUiState().themeDivider
  }
  @Param currentThemeMode: ThemeMode = ThemeMode.SYSTEM
  @Param currentLanguage: AppLanguage = AppLanguage.SYSTEM
  @Param notifyEnabled: boolean = true
  @Param notifyOnComplete: boolean = true
  @Param notifyOnFailed: boolean = true
  @Param chatInputEnterKeySend: boolean = false
  @Param chatOrderedResponseHistory: boolean = false
  @Param handAdaptiveEnabled: boolean = false
  @Param handAdaptiveFollowTarget: HandAdaptiveFollowTarget = HandAdaptiveFollowTarget.PLUS
  @Param handAdaptiveUnsupported: boolean = false
  @Param callbacks: IndexSettingsSheetActionCallbacks = new IndexSettingsSheetActionCallbacks()
  @Local followTargetWidth: number = 0
  private followTargetItems: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: $r('app.string.hand_adaptive_follow_taskbar') },
    { text: $r('app.string.hand_adaptive_follow_plus') }
  ])

  private useFollowTargetMaterial(): boolean {
    return getAppUiState().visualEffectsMode !== VisualEffectsMode.MANUSCRIPT && shouldUseWrappedMaterial()
  }

  private getFollowTargetMaterial(): uiMaterial.Material | undefined {
    if (!isWrappedMaterialApiAvailable()) {
      return undefined
    }
    if (!this.useFollowTargetMaterial()) {
      return uiMaterial.Material.empty
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: withColorAlpha(this.themePrimary, '14'),
      colorInvert: true,
      interactive: true,
      lightEffect: {}
    })
  }

  private getFollowTargetBlurEffect(): BackgroundEffectOptions | undefined {
    if (this.useFollowTargetMaterial()) {
      return undefined
    }
    return { radius: 24, saturation: 1, brightness: 1, color: Color.Transparent }
  }

  private selectFollowTarget(index: number): void {
    if (index !== 0 && index !== 1) {
      return
    }
    const target = index === 0 ? HandAdaptiveFollowTarget.TASKBAR : HandAdaptiveFollowTarget.PLUS
    if (target === this.handAdaptiveFollowTarget) {
      return
    }
    // V2 自己处理点击和拖拽的选中动画，不再嵌套外层 animateTo。
    this.callbacks.onSelectHandAdaptiveFollowTarget(target)
  }

  private interceptFollowTargetTouch(event: TouchEvent): HitTestMode {
    const touch = event.changedTouches.length > 0 ? event.changedTouches[0] : event.touches[0]
    if (touch && touch.x >= 0 && touch.x < this.followTargetWidth &&
      touch.y >= 0 && touch.y < FOLLOW_TARGET_BUTTON_HEIGHT) {
      return HitTestMode.Transparent
    }
    // 透明宿主外扩仅用于绘制，不能抢走标题、说明文字或相邻控件的触摸。
    return HitTestMode.BLOCK_DESCENDANTS
  }

  @Builder
  private FollowTargetSegmentButton() {
    TabSegmentButtonV2({
      items: this.followTargetItems,
      selectedIndex: this.handAdaptiveFollowTarget === HandAdaptiveFollowTarget.TASKBAR ? 0 : 1,
      $selectedIndex: (index: number): void => {
        this.selectFollowTarget(index)
      },
      itemFontColor: ColorMetrics.resourceColor($r('sys.color.font_primary')),
      itemSelectedFontColor: ColorMetrics.resourceColor(this.useFollowTargetMaterial() ?
        $r('sys.color.font_primary') : $r('sys.color.font_on_primary')),
      // 材质模式只叠加半透明主题色，避免实心滑块盖住透射与反色效果。
      itemSelectedBackgroundColor: ColorMetrics.resourceColor(this.useFollowTargetMaterial() ?
        withColorAlpha(this.themePrimary, '33') : this.themePrimary),
      itemMinHeight: LengthMetrics.vp(40),
      buttonPadding: LengthMetrics.vp(4),
      backgroundSystemMaterial: this.getFollowTargetMaterial(),
      // undefined 会回退到 SDK 的默认底色，必须显式清空。
      buttonBackgroundColor: ColorMetrics.resourceColor(Color.Transparent),
      buttonBackgroundEffect: this.getFollowTargetBlurEffect(),
      enableStateAnimation: true
    })
      .width('100%')
      .clip(false)
  }

  @Builder
  private FollowTargetMaterialTitle() {
    Column() {
      this.FollowTargetSegmentButton()
    }
    .width('100%')
    .height('100%')
    .padding(IMMERSIVE_MATERIAL_SHADOW_OUTSET)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Transparent)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private FollowTargetSelector() {
    if (this.useFollowTargetMaterial()) {
      // 原生 V2 内部用 Stack 绘制材质。按官方示例把组件本身放进标题栏作用域，
      // 而不是额外覆盖一个材质背板，保留其原生拖拽、点击和文字反色。
      Stack({ alignContent: Alignment.TopStart }) {
        Navigation() {}
          .title({ builder: this.FollowTargetMaterialTitle, height: '100%' }, {
            backgroundColor: Color.Transparent,
            backgroundBlurStyle: BlurStyle.NONE
          })
          .titleMode(NavigationTitleMode.Mini)
          .hideBackButton(true)
          .hideToolBar(true)
          .mode(NavigationMode.Stack)
          // Navigation 内部标题栏有自己的裁剪边界，必须给阴影和形变留出真实空间。
          .width(`calc(100% + ${IMMERSIVE_MATERIAL_SHADOW_OUTSET * 2}vp)`)
          .height(FOLLOW_TARGET_BUTTON_HEIGHT + IMMERSIVE_MATERIAL_SHADOW_OUTSET * 2)
          .position({ x: -IMMERSIVE_MATERIAL_SHADOW_OUTSET, y: -IMMERSIVE_MATERIAL_SHADOW_OUTSET })
          .backgroundColor(Color.Transparent)
          .clip(false)
          .hitTestBehavior(HitTestMode.Transparent)
      }
        // 布局占位和点击区域仍是原来的按钮尺寸，按钮本身没有缩小或移位。
        .width('100%')
        .height(FOLLOW_TARGET_BUTTON_HEIGHT)
        .clip(false)
        .hitTestBehavior(HitTestMode.Transparent)
        .onTouchIntercept((event: TouchEvent): HitTestMode => this.interceptFollowTargetTouch(event))
        .onSizeChange((_oldSize: SizeOptions, size: SizeOptions) => {
          const width = Number(size.width)
          if (Number.isFinite(width) && width > 0 && Math.abs(width - this.followTargetWidth) > 0.1) {
            this.followTargetWidth = width
          }
        })
    } else {
      // 降级模式仍使用原生分段按钮的透明高斯模糊，不创建材质宿主。
      this.FollowTargetSegmentButton()
    }
  }

  @Builder
  private ThemeOptionItem(mode: ThemeMode, label: Resource) {
    Row() {
      Text(label)
        .font(getSettingsTypography().itemTitle)
        .fontColor(getAppUiState().themeTextPrimary)

      Blank()

      if (this.currentThemeMode === mode) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([this.themePrimary])
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .onClick(() => {
      this.callbacks.onSelectTheme(mode)
    })
  }

  @Builder
  private LanguageOptionItem(language: AppLanguage, label: Resource) {
    Row() {
      Text(label)
        .font(getSettingsTypography().itemTitle)
        .fontColor(getAppUiState().themeTextPrimary)

      Blank()

      if (this.currentLanguage === language) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([this.themePrimary])
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .onClick(() => {
      this.callbacks.onSelectLanguage(language)
    })
  }

  @Builder
  private HandAdaptiveToggleItem(title: Resource, desc: Resource, checked: boolean, enabled: boolean,
    onChanged: (value: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .font(getSettingsTypography().itemTitle)
          .fontColor(enabled ? getAppUiState().themeTextPrimary : getAppUiState().themeTextTertiary)

        Text(desc)
          .font(getSettingsTypography().subtitle)
          .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
          .fontColor(enabled ? getAppUiState().themeTextSecondary : getAppUiState().themeTextTertiary)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor(this.themePrimary)
        .enabled(enabled)
        .systemMaterial(new uiMaterial.Material())
        .switchPointColor(Color.White)
        .onChange((value: boolean) => {
          onChanged(value)
        })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 12, bottom: 12 })
  }

  @Builder
  private HandAdaptiveSheetContent() {
    Column() {
      this.HandAdaptiveToggleItem($r('app.string.hand_adaptive_master_title'),
        $r('app.string.hand_adaptive_master_desc'), this.handAdaptiveEnabled, true, (value: boolean) => {
          this.callbacks.onToggleHandAdaptiveEnabled(value)
        })

      if (this.handAdaptiveEnabled) {
        Divider().color(this.themeDivider)

        Column({ space: 10 }) {
          Text($r('app.string.hand_adaptive_follow_target_title'))
            .font(getSettingsTypography().itemTitle)
            .fontColor(getAppUiState().themeTextPrimary)

          this.FollowTargetSelector()

          Text($r('app.string.hand_adaptive_follow_target_desc'))
            .font(getSettingsTypography().subtitle)
            .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
            .fontColor(getAppUiState().themeTextSecondary)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 8, right: 8, top: 16, bottom: 12 })

        if (this.handAdaptiveUnsupported) {
          Text($r('app.string.hand_adaptive_unsupported_tip'))
            .font(getSettingsTypography().subtitle)
            .width('100%')
            .textAlign(TextAlign.Start)
            .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
            .fontColor($r('app.color.status_error'))
            .margin({ top: 12 })
            .padding({ left: 8, right: 8 })
        }
      }
    }
    .width('100%')
  }

  @Builder
  private NotificationToggleItem(title: Resource, desc: Resource, checked: boolean, onChanged: (value: boolean) =>
    void) {
    Row() {
      Column() {
        Text(title)
          .font(getSettingsTypography().itemTitle)
          .fontColor(getAppUiState().themeTextPrimary)

        Text(desc)
          .font(getSettingsTypography().subtitle)
          .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
          .fontColor(getAppUiState().themeTextSecondary)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor(this.themePrimary)
        .systemMaterial(new uiMaterial.Material())
        .switchPointColor(Color.White)
        .onChange((value: boolean) => {
          onChanged(value)
        })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 12, bottom: 12 })
  }

  @Builder
  private ChatInputSheetContent() {
    Column() {
      this.NotificationToggleItem($r('app.string.chat_input_independent_send_button_title'),
        $r('app.string.chat_input_independent_send_button_desc'), this.chatInputEnterKeySend, (value: boolean) => {
          this.callbacks.onToggleChatInputEnterKeySend(value)
        })

      Divider().color(this.themeDivider)

      this.NotificationToggleItem($r('app.string.chat_ordered_response_history_title'),
        $r('app.string.chat_ordered_response_history_desc'), this.chatOrderedResponseHistory, (value: boolean) => {
          this.callbacks.onToggleChatOrderedResponseHistory(value)
        })
    }
    .width('100%')
  }

  @Builder
  private OpenSystemNotificationSettingsEntry() {
    Column() {
      Text($r('app.string.notification_system_settings_tip'))
        .font(getSettingsTypography().subtitle)
        .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
        .fontColor(getAppUiState().themeTextSecondary)
        .margin({ top: 10, bottom: 10 })

      Stack({ alignContent: Alignment.TopStart }) {
        ImmersiveButtonSurface({
          materialFactory: () => (new uiMaterial.ImmersiveMaterial({
              style: uiMaterial.ImmersiveStyle.REGULAR,
              interactive: true,
              lightEffect: { color: undefined }
            })),
          cornerRadius: 12
        }) {
          Button($r('app.string.notification_open_system_settings'))
            .width('100%')
            .height(40)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
            .backgroundColor(Color.Transparent)
            .borderRadius(12)
            .onClick(() => {
              this.callbacks.onOpenSystemNotificationSettings()
            })
        }
      }
      .width('100%')
      .height(40)
      .clip(false)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      if (this.settingsSheetType === SettingsSheetType.THEME) {
        this.ThemeOptionItem(ThemeMode.SYSTEM, $r('app.string.theme_system'))
        Divider().color(this.themeDivider)
        this.ThemeOptionItem(ThemeMode.LIGHT, $r('app.string.theme_light'))
        Divider().color(this.themeDivider)
        this.ThemeOptionItem(ThemeMode.DARK, $r('app.string.theme_dark'))
      } else if (this.settingsSheetType === SettingsSheetType.LANGUAGE) {
        this.LanguageOptionItem(AppLanguage.SYSTEM, $r('app.string.language_system'))
        Divider().color(this.themeDivider)
        this.LanguageOptionItem(AppLanguage.ZH_CN, $r('app.string.language_zh_cn'))
        Divider().color(this.themeDivider)
        this.LanguageOptionItem(AppLanguage.EN_US, $r('app.string.language_en_us'))
      } else if (this.settingsSheetType === SettingsSheetType.HAND_ADAPTIVE) {
        this.HandAdaptiveSheetContent()
      } else if (this.settingsSheetType === SettingsSheetType.NOTIFICATION) {
        this.NotificationToggleItem($r('app.string.notification_enabled_title'),
          $r('app.string.notification_enabled_desc'), this.notifyEnabled, (value: boolean) => {
            this.callbacks.onToggleNotifyEnabled(value)
          })

        Divider().color(this.themeDivider)

        this.NotificationToggleItem($r('app.string.notification_on_complete_title'),
          $r('app.string.notification_on_complete_desc'), this.notifyOnComplete, (value: boolean) => {
            this.callbacks.onToggleNotifyOnComplete(value)
          })

        Divider().color(this.themeDivider)

        this.NotificationToggleItem($r('app.string.notification_on_failed_title'),
          $r('app.string.notification_on_failed_desc'), this.notifyOnFailed, (value: boolean) => {
            this.callbacks.onToggleNotifyOnFailed(value)
          })

        Divider().color(this.themeDivider).margin({ top: 6 })
        this.OpenSystemNotificationSettingsEntry()
      } else if (this.settingsSheetType === SettingsSheetType.CHAT_INPUT) {
        this.ChatInputSheetContent()
      } else {
        Column()
          .width('100%')
          .height(1)
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      bottom: 32
    })
  }
}
