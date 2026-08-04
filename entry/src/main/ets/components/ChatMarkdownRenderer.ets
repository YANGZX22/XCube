import { Markdown, MarkdownController } from '@luvi/lv-markdown-in'
import { ChatMarkdownHybridRenderer } from './ChatMarkdownHybridRenderer'
import { MarkdownRenderer } from '../services/PreferencesService'
import { getAppUiState } from '../state/AppUiState'
import { ensureLvMarkdownCodeFont } from '../utils/LvMarkdownFontUtils'
import {
  getMarkdownBlockSpacing,
  getMarkdownQuotePadding,
  getMarkdownTextLineHeight,
  getMarkdownTitleLineHeights,
  getMarkdownTitleSizes
} from '../utils/MarkdownTypographyUtils'

@ComponentV2
struct ChatLvMarkdownRenderer {
  @Param content: string = ''
  @Param isInputEnded: boolean = true
  @Param chatFontSize: number = 15
  @Param compact: boolean = false
  @Param latexFontSize: number = 0
  @Param textColorOverride: string = ''
  @Param titleColorOverride: string = ''
  @Param textTypeface: string = 'HarmonyOS Sans'
  @Param themeRenderKey: string = ''

  @Event onOpenLink: (title: string, url: string) => void =
    (_title: string, _url: string): void => {}
  @Event onImageClick: (src: string) => void = (_src: string): void => {}
  @Event onCopyText: (text: string) => void = (_text: string): void => {}
  @Event onCopyCode: (code: string) => void = (_code: string): void => {}

  private controller: MarkdownController = new MarkdownController()
  private configuredSignature: string = ''
  private codeFontFamily: string = ensureLvMarkdownCodeFont()

  private parseThemeColor(value: string, fallback: number): number {
    let color = value.trim()
    if (color.startsWith('#')) {
      color = color.substring(1)
    }
    if (color.length === 3) {
      color = color[0] + color[0] + color[1] + color[1] + color[2] + color[2]
    }
    if (color.length === 6) {
      const parsed = Number.parseInt(color, 16)
      return Number.isNaN(parsed) ? fallback : 0xFF000000 + parsed
    }
    if (color.length === 8) {
      const parsed = Number.parseInt(color, 16)
      return Number.isNaN(parsed) ? fallback : parsed
    }
    return fallback
  }

  private buildConfigurationSignature(): string {
    const uiState = getAppUiState()
    return [
      this.themeRenderKey,
      this.chatFontSize.toString(),
      this.isInputEnded ? 'ended' : 'streaming',
      this.compact ? 'compact' : 'normal',
      this.latexFontSize.toString(),
      this.textColorOverride,
      this.titleColorOverride,
      this.textTypeface,
      uiState.isDarkMode ? 'dark' : 'light',
      uiState.themeMarkdownTitle,
      uiState.themeMarkdownText,
      uiState.themeMarkdownLink,
      uiState.themeMarkdownLinkBg,
      uiState.themeMarkdownCodeBg,
      uiState.themeMarkdownCodeText,
      uiState.themeMarkdownQuoteBg,
      uiState.themeMarkdownTableBg,
      uiState.themeMarkdownTableHeaderBg,
      uiState.themeMarkdownTableAltBg,
      uiState.themeMarkdownTableBorder
    ].join('|')
  }

  private configureController(): MarkdownController {
    const signature = this.buildConfigurationSignature()
    if (signature === this.configuredSignature) {
      return this.controller
    }

    const uiState = getAppUiState()
    const textSize = Math.max(this.chatFontSize - (this.compact ? 2 : 1), 10)
    const titleSizes = getMarkdownTitleSizes(textSize, this.compact)
    const textColor = this.textColorOverride !== '' ? this.textColorOverride : uiState.themeMarkdownText
    const titleColor = this.titleColorOverride !== '' ? this.titleColorOverride : uiState.themeMarkdownTitle
    const codeTheme = uiState.isDarkMode ? 'dark' : 'light'
    const latexColor = this.parseThemeColor(textColor, uiState.isDarkMode ? 0xFFE7E0D4 : 0xFF3D3830)

    this.controller
      .setTitleColor(titleColor)
      .setTitleSize(titleSizes)
      .setTitleLineHeight(getMarkdownTitleLineHeights(titleSizes, this.compact))
      .setTitleFontFamily(this.textTypeface)
      .setTextColor(textColor)
      .setTextSize(textSize)
      .setTextLineHeight(getMarkdownTextLineHeight(textSize, this.compact))
      .setTextFontFamily(this.textTypeface)
      .setQuoteTextColor(textColor)
      .setQuoteBackgroundColor(uiState.themeMarkdownQuoteBg)
      .setQuoteBorderColor(uiState.themeMarkdownLink)
      .setQuotePadding(getMarkdownQuotePadding(textSize, this.compact))
      .setHyperlinkTextColor(uiState.themeMarkdownLink)
      .setHyperlinkTextSize(textSize)
      .setHyperlinkBackgroundColor(uiState.themeMarkdownLinkBg)
      .setInlineCodeColor(uiState.themeMarkdownCodeText)
      .setInlineCodeBackgroundColor(uiState.themeMarkdownCodeBg)
      .setCodeBlockTheme(codeTheme)
      .setCodeBlockFontFamily(this.codeFontFamily)
      .setCodeBlockAutoCollapseEnable(false)
      .setLatexMathTextColor(latexColor)
      .setLatexMathTextSize(this.latexFontSize > 0 ? this.latexFontSize : this.chatFontSize + (this.compact ? 0 : 2))
      .setTableBackgroundColor(uiState.themeMarkdownTableBg)
      .setTableTitleBackgroundColor(uiState.themeMarkdownTableHeaderBg)
      .setTableInterleaveBackgroundColor(uiState.themeMarkdownTableAltBg)
      .setTableTitleTextColor(titleColor)

    this.controller.setTableInterleaveTextColor(textColor)
    this.controller.setTableNormalTextColor(textColor)

    this.controller
      .setTableOuterBorderColor(uiState.themeMarkdownTableBorder)
      .setTableInnerBorderColor(uiState.themeMarkdownTableBorder)
      .setUlPointColor(textColor)
      .setLineColor(uiState.themeMarkdownTableBorder)
      .setFootnoteTextColor(uiState.themeMarkdownLink)
      .setTodoSelectedColor(uiState.themeMarkdownLink)
      .setMermaidEnable(true)
      .setMermaidTheme(codeTheme)
      .setSetextHeadingEnable(true)
      .setThreadRenderEnable(true)
      .setTextSelectionEnable(this.isInputEnded)
      .setHyperlinkClickListener((title: string, src: string): boolean => {
        this.onOpenLink(title, src)
        return true
      })
      .setImageClickListener((src: string): boolean => {
        this.onImageClick(src)
        return true
      })
      .setCodeCopyListener((code: string): void => {
        this.onCopyCode(code)
      })
      .setTextSelectionCopyListener((text: string): void => {
        this.onCopyText(text)
      })
      .setBlockSpacing(getMarkdownBlockSpacing(textSize, this.compact))

    this.configuredSignature = signature
    return this.controller
  }

  build() {
    Markdown({
      controller: this.configureController(),
      text: this.content
    })
      .width('100%')
      .backgroundColor(Color.Transparent)
  }
}

@ComponentV2
export struct ChatMarkdownRenderer {
  @Param content: string = ''
  @Param isInputEnded: boolean = true
  @Param incrementalAnalysis: boolean = false
  @Param useCangjieComponent: boolean = true
  @Param chatFontSize: number = 15
  @Param compact: boolean = false
  @Param latexFontSize: number = 0
  @Param textColorOverride: string = ''
  @Param titleColorOverride: string = ''
  @Param textTypeface: string = 'HarmonyOS Sans'
  @Param themeRenderKey: string = ''
  @Param showCodeFullScreen: boolean = true

  @Event onOpenLink: (title: string, url: string) => void =
    (_title: string, _url: string): void => {}
  @Event onImageClick: (src: string) => void = (_src: string): void => {}
  @Event onCopyText: (text: string) => void = (_text: string): void => {}
  @Event onCopyCode: (code: string) => void = (_code: string): void => {}
  @Event onCodeFullScreen: (code: string, codeType: string) => void =
    (_code: string, _codeType: string): void => {}

  build() {
    if (getAppUiState().markdownRenderer === MarkdownRenderer.LV_MARKDOWN_IN) {
      ChatLvMarkdownRenderer({
        content: this.content,
        isInputEnded: this.isInputEnded,
        chatFontSize: this.chatFontSize,
        compact: this.compact,
        latexFontSize: this.latexFontSize,
        textColorOverride: this.textColorOverride,
        titleColorOverride: this.titleColorOverride,
        textTypeface: this.textTypeface,
        themeRenderKey: this.themeRenderKey,
        onOpenLink: (title: string, url: string): void => {
          this.onOpenLink(title, url)
        },
        onImageClick: (src: string): void => {
          this.onImageClick(src)
        },
        onCopyText: (text: string): void => {
          this.onCopyText(text)
        },
        onCopyCode: (code: string): void => {
          this.onCopyCode(code)
        }
      })
    } else {
      ChatMarkdownHybridRenderer({
        content: this.content,
        isInputEnded: this.isInputEnded,
        incrementalAnalysis: this.incrementalAnalysis,
        useCangjieComponent: this.useCangjieComponent,
        chatFontSize: this.chatFontSize,
        compact: this.compact,
        latexFontSize: this.latexFontSize,
        textColorOverride: this.textColorOverride,
        titleColorOverride: this.titleColorOverride,
        textTypeface: this.textTypeface,
        themeRenderKey: this.themeRenderKey,
        showCodeFullScreen: this.showCodeFullScreen,
        onOpenLink: (title: string, url: string): void => {
          this.onOpenLink(title, url)
        },
        onImageClick: (src: string): void => {
          this.onImageClick(src)
        },
        onCopyText: (text: string): void => {
          this.onCopyText(text)
        },
        onCopyCode: (code: string): void => {
          this.onCopyCode(code)
        },
        onCodeFullScreen: (code: string, codeType: string): void => {
          this.onCodeFullScreen(code, codeType)
        }
      })
    }
  }
}
