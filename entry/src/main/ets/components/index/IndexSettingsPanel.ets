import { bundleManager } from '@kit.AbilityKit'
import { uiMaterial } from '@kit.ArkUI'
import { SettingsRouteName } from '../../config/SettingsRouteName'
import { VisualEffectsMode } from '../../models/ThemeColors'
import { getAppUiState } from '../../state/AppUiState'
import {
  MANUSCRIPT_BODY_FONT,
  MANUSCRIPT_HEADING_FONT,
  toRomanNumeral
} from '../../utils/ManuscriptVisualUtils'

class SettingsListItemModel {
  key: string = ''
  ordinal: number = 1
  icon: Resource = $r('sys.symbol.square_stack_3d')
  title: ResourceStr = ''
  subtitle: ResourceStr = ''
  action: (() => void) | null = null
}

class SettingsGroupModel {
  key: string = ''
  title: Resource = $r('app.string.settings_app_settings')
  items: SettingsListItemModel[] = []
}

@ComponentV2
export struct IndexSettingsPanel {
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get themeDivider(): string {
    return getAppUiState().themeDivider
  }
  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }
  @Local versionName: string = ''

  @Param sidebarMode: boolean = false
  @Param selectedRouteName: string = ''
  @Param highlightSelection: boolean = false
  @Event onOpenModelManage: () => void = () => {}
  @Event onOpenDefaultModel: () => void = () => {}
  @Event onOpenToolsCenter: () => void = () => {}
  @Event onOpenSystemPrompt: () => void = () => {}
  @Event onOpenChatInput: () => void = () => {}
  @Event onOpenTTS: () => void = () => {}
  @Event onOpenHandAdaptive: () => void = () => {}
  @Event onOpenTheme: () => void = () => {}
  @Event onOpenLanguage: () => void = () => {}
  @Event onOpenNotification: () => void = () => {}
  @Event onOpenExportData: () => void = () => {}
  @Event onOpenImportData: () => void = () => {}
  @Event onOpenWebDAVSync: () => void = () => {}
  @Event onOpenUsageStats: () => void = () => {}
  @Event onOpenAbout: () => void = () => {}

  aboutToAppear(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      this.versionName = info.versionName
    } catch (err) {
      console.error('IndexSettingsPanel', `Get version failed: ${JSON.stringify(err)}`)
      this.versionName = '1.3.6'
    }
  }

  private isSelectedItem(item: SettingsListItemModel): boolean {
    if (!this.highlightSelection || item.key === '') {
      return false
    }
    return item.key === this.selectedRouteName
  }

  private buildGroups(): SettingsGroupModel[] {
    const groups: SettingsGroupModel[] = [
      {
        key: 'model',
        title: $r('app.string.settings_model_config'),
        items: [
          {
            key: SettingsRouteName.MODEL_MANAGE,
            icon: $r('sys.symbol.square_stack_3d'),
            title: $r('app.string.settings_model_manage'),
            subtitle: $r('app.string.settings_model_manage_desc'),
            action: (): void => { this.onOpenModelManage() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.DEFAULT_MODEL,
            icon: $r('sys.symbol.wand_and_stars'),
            title: $r('app.string.settings_default_model'),
            subtitle: $r('app.string.settings_default_model_desc'),
            action: (): void => { this.onOpenDefaultModel() }
          } as SettingsListItemModel
        ]
      } as SettingsGroupModel,
      {
        key: 'app',
        title: $r('app.string.settings_app_settings'),
        items: [
          {
            key: SettingsRouteName.THEME_MODE,
            icon: $r('sys.symbol.moon_and_message_fill'),
            title: $r('app.string.settings_appearance'),
            subtitle: $r('app.string.settings_appearance_desc'),
            action: (): void => { this.onOpenTheme() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.TOOLS_CENTER,
            icon: $r('sys.symbol.puzzle'),
            title: $r('app.string.settings_tools_center'),
            subtitle: $r('app.string.settings_tools_center_desc'),
            action: (): void => { this.onOpenToolsCenter() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.SYSTEM_PROMPT,
            icon: $r('sys.symbol.message'),
            title: $r('app.string.settings_system_prompt'),
            subtitle: $r('app.string.settings_system_prompt_desc'),
            action: (): void => { this.onOpenSystemPrompt() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.CHAT_INPUT,
            icon: $r('sys.symbol.textformat'),
            title: $r('app.string.settings_chat_input'),
            subtitle: $r('app.string.settings_chat_input_desc'),
            action: (): void => { this.onOpenChatInput() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.TTS,
            icon: $r('sys.symbol.speaker_wave_2'),
            title: $r('app.string.settings_tts'),
            subtitle: $r('app.string.settings_tts_desc'),
            action: (): void => { this.onOpenTTS() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.HAND_ADAPTIVE,
            icon: $r('sys.symbol.phone_and_hand'),
            title: $r('app.string.settings_hand_adaptive'),
            subtitle: $r('app.string.settings_hand_adaptive_desc'),
            action: (): void => { this.onOpenHandAdaptive() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.LANGUAGE,
            icon: $r('sys.symbol.globe_badge_message'),
            title: $r('app.string.settings_language'),
            subtitle: $r('app.string.settings_language_desc'),
            action: (): void => { this.onOpenLanguage() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.NOTIFICATION,
            icon: $r('sys.symbol.bell_badge_gearshape'),
            title: $r('app.string.settings_notifications'),
            subtitle: $r('app.string.settings_notifications_desc'),
            action: (): void => { this.onOpenNotification() }
          } as SettingsListItemModel
        ]
      } as SettingsGroupModel,
      {
        key: 'data',
        title: $r('app.string.settings_data_management'),
        items: [
          {
            key: SettingsRouteName.EXPORT_DATA,
            icon: $r('sys.symbol.arrow_up_and_rectangle_on_rectangle'),
            title: $r('app.string.settings_export_data'),
            subtitle: $r('app.string.settings_export_data_desc'),
            action: (): void => { this.onOpenExportData() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.IMPORT_DATA,
            icon: $r('sys.symbol.arrow_down_and_rectangle_on_rectangle'),
            title: $r('app.string.settings_import_data'),
            subtitle: $r('app.string.settings_import_data_desc'),
            action: (): void => { this.onOpenImportData() }
          } as SettingsListItemModel,
          {
            key: SettingsRouteName.WEBDAV_SYNC,
            icon: $r('sys.symbol.icloud'),
            title: $r('app.string.settings_webdav_sync'),
            subtitle: $r('app.string.settings_webdav_sync_desc'),
            action: (): void => { this.onOpenWebDAVSync() }
          } as SettingsListItemModel
        ]
      } as SettingsGroupModel,
      {
        key: 'usage',
        title: $r('app.string.settings_usage_stats_group'),
        items: [
          {
            key: SettingsRouteName.USAGE_STATS,
            icon: $r('sys.symbol.line_3_horizontal'),
            title: $r('app.string.settings_usage_stats'),
            subtitle: $r('app.string.settings_usage_stats_desc'),
            action: (): void => { this.onOpenUsageStats() }
          } as SettingsListItemModel
        ]
      } as SettingsGroupModel,
      {
        key: 'about',
        title: $r('app.string.settings_about'),
        items: [
          {
            key: SettingsRouteName.ABOUT,
            icon: $r('sys.symbol.exclamationmark_message'),
            title: $r('app.string.settings_about_xcube'),
            subtitle: `v${this.versionName}`,
            action: (): void => { this.onOpenAbout() }
          } as SettingsListItemModel
        ]
      } as SettingsGroupModel
    ]
    let ordinal = 1
    for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      for (let itemIndex = 0; itemIndex < groups[groupIndex].items.length; itemIndex++) {
        groups[groupIndex].items[itemIndex].ordinal = ordinal
        ordinal += 1
      }
    }
    return groups
  }

  @Builder
  private SectionTitle(title: Resource) {
    if (this.isManuscriptMode) {
      Row({ space: 10 }) {
        Text(title)
          .fontFamily(MANUSCRIPT_BODY_FONT)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(getAppUiState().isDarkMode ? '#D9B274' : '#8A6228')
          .letterSpacing(1.4)
          .textCase(TextCase.UpperCase)
          .maxLines(1)

        Column()
          .height(1)
          .backgroundColor(this.themeDivider)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 4, right: 4, top: 16, bottom: 5 })
      .alignItems(VerticalAlign.Center)
    } else {
      Text(title)
        .fontSize(this.sidebarMode ? 11 : 12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: this.sidebarMode ? 6 : 4, bottom: this.sidebarMode ? 8 : 6 })
        .width('100%')
    }
  }

  @Builder
  private PrefixIcon(icon: Resource) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(this.sidebarMode ? 18 : 17)
        .fontColor([this.themePrimary])
    }
    .width(this.sidebarMode ? 32 : 30)
    .height(this.sidebarMode ? 32 : 30)
    .borderRadius(this.sidebarMode ? 11 : 10)
    .backgroundColor(this.themePrimaryLight)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ChevronSuffix() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(16)
      .fontColor([$r('app.color.text_tertiary')])
  }

  @Builder
  private ItemText(item: SettingsListItemModel) {
    if (this.hasSubtitle(item)) {
      Column() {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.subtitle)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .wordBreak(WordBreak.BREAK_WORD)
          .textOverflow({ overflow: TextOverflow.Clip })
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    } else {
      Text(item.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  private hasSubtitle(item: SettingsListItemModel): boolean {
    return item.subtitle !== undefined && item.subtitle !== ''
  }

  private hasRowAction(item: SettingsListItemModel): boolean {
    return item.action !== null && item.action !== undefined
  }

  @Builder
  private SettingsItemRow(item: SettingsListItemModel, isLast: boolean) {
    if (this.isManuscriptMode) {
      this.ManuscriptSettingsItemRow(item)
    } else {
      Column() {
        Row({ space: 12 }) {
          this.PrefixIcon(item.icon)
          this.ItemText(item)
          if (this.hasRowAction(item)) {
            this.ChevronSuffix()
          }
        }
        .width('100%')
        .padding({
          left: this.sidebarMode ? 18 : 16,
          right: 12,
          top: this.hasSubtitle(item) ? (this.sidebarMode ? 13 : 14) : (this.sidebarMode ? 15 : 16),
          bottom: this.hasSubtitle(item) ? (this.sidebarMode ? 13 : 14) : (this.sidebarMode ? 15 : 16)
        })
        .backgroundColor(this.isSelectedItem(item) ? this.themePrimaryLight : Color.Transparent)
        .borderRadius(this.sidebarMode ? 16 : 14)
        .onClick(() => {
          const rowAction = item.action
          if (rowAction !== null && rowAction !== undefined) {
            rowAction()
          }
        })

        if (!isLast) {
          Divider()
            .color(this.themeDivider)
            .margin({ left: this.sidebarMode ? 62 : 58, right: 12 })
        }
      }
    }
  }

  @Builder
  private ManuscriptSettingsItemRow(item: SettingsListItemModel) {
    Column({ space: 5 }) {
      Row({ space: 8 }) {
        Text(toRomanNumeral(item.ordinal))
          .width(26)
          .fontFamily(MANUSCRIPT_HEADING_FONT)
          .fontSize(15)
          .fontWeight(600)
          .fontColor(getAppUiState().isDarkMode ? '#D9B274' : '#8A6228')
          .fontFeature('tnum')

        Text(item.title)
          .fontFamily(MANUSCRIPT_HEADING_FONT)
          .fontSize(17.5)
          .fontWeight(600)
          .fontColor(getAppUiState().themeTextPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '58%' })

        Column()
          .height(1)
          .border({
            width: { top: 1 },
            color: getAppUiState().isDarkMode ? '#4A463F' : '#C9C4BB',
            style: BorderStyle.Dotted
          })
          .layoutWeight(1)
          .constraintSize({ minWidth: 16 })

        if (this.hasRowAction(item)) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(13)
            .fontColor([getAppUiState().themeTextTertiary])
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.hasSubtitle(item)) {
        Text(item.subtitle)
          .width('100%')
          .fontFamily(MANUSCRIPT_BODY_FONT)
          .fontSize(12)
          .fontStyle(FontStyle.Italic)
          .fontColor(getAppUiState().themeTextSecondary)
          .maxLines(2)
          .wordBreak(WordBreak.BREAK_WORD)
          .textOverflow({ overflow: TextOverflow.Clip })
          .padding({ left: 34, right: 18 })
      }
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 12, bottom: 11 })
    .backgroundColor(this.isSelectedItem(item) ?
      (getAppUiState().isDarkMode ? '#33291B' : '#F5EDE0') : Color.Transparent)
    .border({
      width: {
        bottom: 0.5,
        left: this.isSelectedItem(item) ? 2 : 0
      },
      color: this.isSelectedItem(item) ? this.themePrimary : this.themeDivider
    })
    .onClick(() => {
      const rowAction = item.action
      if (rowAction !== null && rowAction !== undefined) {
        rowAction()
      }
    })
  }

  @Builder
  private SettingsGroupCard(group: SettingsGroupModel) {
    Column() {
      ForEach(group.items, (item: SettingsListItemModel) => {
        this.SettingsItemRow(item, item.key === group.items[group.items.length - 1].key)
      }, (item: SettingsListItemModel) => item.key)
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .borderRadius(this.isManuscriptMode ? 0 : (this.sidebarMode ? 20 : 22))
    .clip(!this.isManuscriptMode)
    .systemMaterial(this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      interactive: false,
      lightEffect: { color: undefined }
    }))
  }

  build() {
    Column({ space: this.isManuscriptMode ? 0 : (this.sidebarMode ? 12 : 14) }) {
      ForEach(this.buildGroups(), (group: SettingsGroupModel) => {
        Column() {
          this.SectionTitle(group.title)
          this.SettingsGroupCard(group)
        }
        .width('100%')
      }, (group: SettingsGroupModel) => group.key)

      if (this.isManuscriptMode) {
        Text('❦')
          .fontFamily(MANUSCRIPT_HEADING_FONT)
          .fontSize(18)
          .fontColor(getAppUiState().isDarkMode ? '#C99A52' : '#B68235')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 18, bottom: 12 })
      }
    }
    .width('100%')
    .padding({
      left: this.isManuscriptMode ? 32 : 16,
      right: this.isManuscriptMode ? 32 : 16,
      top: this.isManuscriptMode ? 0 : (this.sidebarMode ? 8 : 0),
      bottom: 28
    })
    .backgroundColor(this.themeBackground)
  }
}
