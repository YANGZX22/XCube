import { ColorTheme, ThemeInfo, ALL_THEMES } from '../models/ThemeColors'
import { getThemeService } from '../services/ThemeService'
import { getAppUiState } from '../state/AppUiState'

@ComponentV2
export struct ThemeColorPicker {
  @Local currentTheme: ColorTheme = ColorTheme.LAVENDER
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  @Event onThemeSelected: (theme: ColorTheme) => void = () => {}

  aboutToAppear(): void {
    this.currentTheme = getThemeService().getColorTheme()
  }

  build() {
    Column() {
      // 主题网格（每行2个）
      Grid() {
        ForEach(ALL_THEMES, (theme: ThemeInfo) => {
          GridItem() {
            this.ThemeCard(theme)
          }
        }, (theme: ThemeInfo) => theme.id)
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(12)
      .rowsGap(12)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 32 })
    }
    .width('100%')
  }

  @Builder
  ThemeCard(theme: ThemeInfo) {
    Column() {
      // 预览色块区域
      Row() {
        // 背景色预览
        Column()
          .width(22)
          .height(22)
          .borderRadius(11)
          .backgroundColor(theme.previewColors[0])
          .border({
            width: 1,
            color: this.isDarkMode ? theme.dark.divider : theme.light.divider
          })

        // 弱染色（primaryLight）
        Column()
          .width(22)
          .height(22)
          .borderRadius(11)
          .backgroundColor(theme.previewColors[1])
          .margin({ left: 6 })

        // 主色调
        Column()
          .width(22)
          .height(22)
          .borderRadius(11)
          .backgroundColor(theme.previewColors[2])
          .margin({ left: 6 })

        // 气泡色
        Column()
          .width(22)
          .height(22)
          .borderRadius(11)
          .backgroundColor(theme.previewColors[3])
          .margin({ left: 6 })

        Blank()

        // 选中标记
        if (this.currentTheme === theme.id) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(20)
            .fontColor([this.isDarkMode ? theme.dark.primary : theme.light.primary])
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12 })

      // 主题名称
      Text(this.getThemeName(theme.id))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8 })
        .alignSelf(ItemAlign.Start)
        .padding({ left: 12 })

      // 主题描述
      Text(this.getThemeDescription(theme.id))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 2, bottom: 12 })
        .alignSelf(ItemAlign.Start)
        .padding({ left: 12 })
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .border({
      width: this.currentTheme === theme.id ? 2 : 1,
      color: this.currentTheme === theme.id ?
        (this.isDarkMode ? theme.dark.primary : theme.light.primary) :
        $r('app.color.divider')
    })
    .onClick(() => {
      this.currentTheme = theme.id
      this.onThemeSelected(theme.id)
    })
  }

  private getThemeName(themeId: ColorTheme): Resource {
    if (themeId === ColorTheme.ATELIER) {
      return $r('app.string.theme_color_atelier')
    } else if (themeId === ColorTheme.LAVENDER) {
      return $r('app.string.theme_color_lavender')
    } else if (themeId === ColorTheme.CLAUDE) {
      return $r('app.string.theme_color_claude')
    } else if (themeId === ColorTheme.PORCELAIN) {
      return $r('app.string.theme_color_porcelain')
    } else {
      return $r('app.string.theme_color_lavender')
    }
  }

  private getThemeDescription(themeId: ColorTheme): Resource {
    if (themeId === ColorTheme.ATELIER) {
      return $r('app.string.theme_color_atelier_desc')
    } else if (themeId === ColorTheme.LAVENDER) {
      return $r('app.string.theme_color_lavender_desc')
    } else if (themeId === ColorTheme.CLAUDE) {
      return $r('app.string.theme_color_claude_desc')
    } else if (themeId === ColorTheme.PORCELAIN) {
      return $r('app.string.theme_color_porcelain_desc')
    } else {
      return $r('app.string.theme_color_lavender_desc')
    }
  }
}
