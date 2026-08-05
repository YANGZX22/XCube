import { curves } from '@kit.ArkUI'
import { ColorTheme, ThemeInfo, ALL_THEMES } from '../models/ThemeColors'
import { getThemeService } from '../services/ThemeService'
import { getAppUiState } from '../state/AppUiState'
import {
  CHAT_SERIF_FONT_COMMON,
  detectAndRegisterChatSerifFonts,
  resolveChatSerifFontFamily
} from '../utils/ChatSerifFontUtils'

@ComponentV2
export struct ThemeColorPicker {
  @Local currentTheme: ColorTheme = ColorTheme.LAVENDER
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get themeCardTypeface(): string {
    return resolveChatSerifFontFamily(CHAT_SERIF_FONT_COMMON)
  }
  @Event onThemeSelected: (theme: ColorTheme) => void = () => {}

  aboutToAppear(): void {
    detectAndRegisterChatSerifFonts(this.getUIContext())
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
            .transition(
              TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.6, y: 0.6 }))
                .animation({ duration: 350, curve: curves.springMotion(0.35, 0.8) })
            )
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12 })

      // 主题名称
      Text(this.getThemeName(theme.id))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.themeCardTypeface)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })
        .alignSelf(ItemAlign.Start)
        .padding({ left: 12, right: 12 })

      // 主题描述
      Text(this.getThemeDescription(theme.id))
        .fontSize(12)
        .fontFamily(this.themeCardTypeface)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .height(20)
        .textOverflow({ overflow: TextOverflow.MARQUEE })
        .marqueeOptions({
          start: true,
          step: 3,
          loop: -1,
          fromStart: true,
          delay: 1200,
          fadeout: true
        })
        .margin({ top: 2, bottom: 12 })
        .alignSelf(ItemAlign.Start)
        .padding({ left: 12, right: 12 })
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
      animateTo({ duration: 450, curve: Curve.EaseInOut }, () => {
        this.currentTheme = theme.id
      })
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
    } else if (themeId === ColorTheme.HERBARIUM) {
      return $r('app.string.theme_color_herbarium')
    } else if (themeId === ColorTheme.SALON) {
      return $r('app.string.theme_color_salon')
    } else if (themeId === ColorTheme.GALLERY) {
      return $r('app.string.theme_color_gallery')
    } else if (themeId === ColorTheme.NOCTURNE) {
      return $r('app.string.theme_color_nocturne')
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
    } else if (themeId === ColorTheme.HERBARIUM) {
      return $r('app.string.theme_color_herbarium_desc')
    } else if (themeId === ColorTheme.SALON) {
      return $r('app.string.theme_color_salon_desc')
    } else if (themeId === ColorTheme.GALLERY) {
      return $r('app.string.theme_color_gallery_desc')
    } else if (themeId === ColorTheme.NOCTURNE) {
      return $r('app.string.theme_color_nocturne_desc')
    } else {
      return $r('app.string.theme_color_lavender_desc')
    }
  }
}
