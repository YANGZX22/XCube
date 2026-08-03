import {
  CJMarkdown,
  LatexMathColorFormat,
  MarkdownConfiguration,
  MarkdownPlugin,
  MarkdownTheme
} from '@cangjie-tpc/markdown_hybrid'
import { getAppUiState } from '../state/AppUiState'
import {
  getMarkdownBlockSpacing,
  getMarkdownTextLineHeight,
  getMarkdownTitleLineHeights,
  getMarkdownTitleSizes,
  MarkdownTitleScale
} from '../utils/MarkdownTypographyUtils'

@ComponentV2
export struct ChatMarkdownHybridRenderer {
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

  private cachedConfig: MarkdownConfiguration | null = null
  private cachedConfigSignature: string = ''
  private cachedPlugin: MarkdownPlugin | null = null

  private isCustomTextTypeface(): boolean {
    return this.textTypeface !== '' && this.textTypeface !== 'HarmonyOS Sans'
  }

  /**
   * markdown_hybrid 没有提供有序列表前缀的字体接口。使用衬线字体时保留原列表结构，
   * 隐藏组件生成的前缀，并把同一编号放进列表正文，使编号与正文使用相同字体。
   */
  private getTypefaceAwareContent(): string {
    if (!this.isCustomTextTypeface() || this.content === '') {
      return this.content
    }
    const lines: Array<string> = this.content.split('\n')
    let inFencedCodeBlock: boolean = false
    const orderedListPattern = new RegExp('^(\\s*)([0-9]+)([.)])(\\s+)(.*)$')
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index]
      const trimmedLine = line.trim()
      if (trimmedLine.startsWith('```') || trimmedLine.startsWith('~~~')) {
        inFencedCodeBlock = !inFencedCodeBlock
        continue
      }
      if (inFencedCodeBlock) {
        continue
      }
      const match = line.match(orderedListPattern)
      if (match !== null && match.length >= 6 && match[5] !== '') {
        // 转义正文中的分隔符，避免复制出的 “1.” 再次被解析成一层嵌套列表。
        lines[index] = match[1] + match[2] + match[3] + match[4] + match[2] + '\\' + match[3] + ' ' + match[5]
      }
    }
    return lines.join('\n')
  }

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

  private buildConfigSignature(): string {
    const uiState = getAppUiState()
    return [
      this.themeRenderKey,
      this.chatFontSize.toString(),
      this.isInputEnded ? 'ended' : 'streaming',
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
      uiState.themeMarkdownTableBorder,
      this.compact ? 'compact' : 'normal',
      this.latexFontSize.toString(),
      this.textColorOverride,
      this.titleColorOverride,
      this.textTypeface,
      this.showCodeFullScreen ? 'fullscreen' : 'no_fullscreen'
    ].join('|')
  }

  private applyHeadingTheme(theme: MarkdownTheme, titleSizes: MarkdownTitleScale,
    titleLineHeights: MarkdownTitleScale, titleColor: number, borderColor: number): void {
    theme.setHeadingTextColor(titleColor)
    theme.setHeadingBreakColor(borderColor)
    theme.setHeadingTextSize1(titleSizes[0])
    theme.setHeadingTextSize2(titleSizes[1])
    theme.setHeadingTextSize3(titleSizes[2])
    theme.setHeadingTextSize4(titleSizes[3])
    theme.setHeadingTextSize5(titleSizes[4])
    theme.setHeadingTextSize6(titleSizes[5])
    theme.setHeadingTextLineHeight1(titleLineHeights[0])
    theme.setHeadingTextLineHeight2(titleLineHeights[1])
    theme.setHeadingTextLineHeight3(titleLineHeights[2])
    theme.setHeadingTextLineHeight4(titleLineHeights[3])
    theme.setHeadingTextLineHeight5(titleLineHeights[4])
    theme.setHeadingTextLineHeight6(titleLineHeights[5])
    theme.setHeadingTextColor1(titleColor)
    theme.setHeadingTextColor2(titleColor)
    theme.setHeadingTextColor3(titleColor)
    theme.setHeadingTextColor4(titleColor)
    theme.setHeadingTextColor5(titleColor)
    theme.setHeadingTextColor6(titleColor)
  }

  private applyListTheme(theme: MarkdownTheme, textSize: number, textLineHeight: number, textColor: number): void {
    const listItemSpacing = Math.max(Math.round(textSize * (this.compact ? 0.12 : 0.18)), this.compact ? 1 : 2)
    const listLeftMargin = Math.max(Math.round(textSize * 0.65), this.compact ? 7 : 8)
    const bulletSize = Math.max(Math.round(textSize * 0.35), 4)

    theme.setBlockOrderedAndBulletTopAndBottomMargins(listItemSpacing)
    theme.setBlockLeftMargin(listLeftMargin)
    theme.setBlockRightMargin(0)
    theme.setOrderedListItemPrefixBold(false)
    // 自定义字体下，编号会作为正文绘制；组件自身不支持为此前缀指定字体。
    theme.setOrderedListItemColor(this.isCustomTextTypeface() ? 0x00000000 : textColor)
    theme.setOrderedListItemSize(textSize)
    theme.setOrderedListItemLineHeight(textLineHeight)
    theme.setBulletListItemColor(textColor)
    theme.setBulletListItemSize(bulletSize)
    theme.setBulletListItemLineHeight(textLineHeight)
  }

  private applyInlineDecorationTheme(theme: MarkdownTheme, textSize: number, textColor: number): void {
    const subSupTextSize = Math.max(Math.round(textSize * 0.72), 8)
    theme.setStrikethroughColor(textColor)
    theme.setUnderlineColor(textColor)
    theme.setSubTextColor(textColor)
    theme.setSubTextSize(subSupTextSize)
    theme.setSupTextColor(textColor)
    theme.setSupTextSize(subSupTextSize)
  }

  private buildMarkdownConfig(): MarkdownConfiguration {
    const uiState = getAppUiState()
    const config = new MarkdownConfiguration()
    const theme = new MarkdownTheme()
    const hostContext = this.getUIContext().getHostContext()
    if (hostContext !== undefined && hostContext !== null) {
      theme.setContext(hostContext)
    }

    const textSize = Math.max(this.chatFontSize - (this.compact ? 2 : 1), 10)
    const titleSizes = getMarkdownTitleSizes(textSize, this.compact)
    const titleLineHeights = getMarkdownTitleLineHeights(titleSizes, this.compact)
    const textColor = this.parseThemeColor(
      this.textColorOverride !== '' ? this.textColorOverride : uiState.themeMarkdownText,
      uiState.isDarkMode ? 0xFFE7E0D4 : 0xFF3D3830
    )
    const titleColor = this.parseThemeColor(
      this.titleColorOverride !== '' ? this.titleColorOverride : uiState.themeMarkdownTitle,
      uiState.isDarkMode ? 0xFFF3EFE6 : 0xFF24211C
    )
    const linkColor = this.parseThemeColor(uiState.themeMarkdownLink, uiState.isDarkMode ? 0xFF9CBFE8 : 0xFF4E6F9E)
    const linkBgColor = this.parseThemeColor(uiState.themeMarkdownLinkBg, 0x00000000)
    const codeBgColor = this.parseThemeColor(uiState.themeMarkdownCodeBg, uiState.isDarkMode ? 0xFF24221E : 0xFFF3EFE8)
    const codeTextColor = this.parseThemeColor(uiState.themeMarkdownCodeText, uiState.isDarkMode ? 0xFFD7C4A9 : 0xFF8F5E45)
    const quoteBgColor = this.parseThemeColor(uiState.themeMarkdownQuoteBg, uiState.isDarkMode ? 0xFF24221E : 0xFFF3EFE8)
    const tableBgColor = this.parseThemeColor(uiState.themeMarkdownTableBg, uiState.isDarkMode ? 0xFF1E1C19 : 0xFFFFFDF8)
    const tableHeaderBgColor =
      this.parseThemeColor(uiState.themeMarkdownTableHeaderBg, uiState.isDarkMode ? 0xFF24221E : 0xFFF3EFE8)
    const tableAltBgColor =
      this.parseThemeColor(uiState.themeMarkdownTableAltBg, uiState.isDarkMode ? 0xFF25231F : 0xFFFAF7F0)
    const tableBorderColor =
      this.parseThemeColor(uiState.themeMarkdownTableBorder, uiState.isDarkMode ? 0xFF514C45 : 0xFFDED8CC)
    const textLineHeight = getMarkdownTextLineHeight(textSize, this.compact)
    const codeTextSize = Math.max(textSize - 1, 10)
    const codeLineHeight = getMarkdownTextLineHeight(codeTextSize)
    const blockSpacing = getMarkdownBlockSpacing(textSize, this.compact)
    const codeMultilineMargin = Math.max(Math.round(codeTextSize * (this.compact ? 0.65 : 0.75)), this.compact ? 8 : 10)
    // 左竖条与正文之间的内边距：留足避免文字贴线
    const quoteLeftMargin =
      Math.max(Math.round(textSize * (this.compact ? 0.9 : 1.0)), this.compact ? 12 : 14)
    // 右侧内边距：原本为 0 会导致正文溢出引用背景右缘，这里给与左侧相当的留白
    const quoteRightMargin =
      Math.max(Math.round(textSize * (this.compact ? 0.72 : 0.8)), this.compact ? 10 : 12)
    const quoteVerticalSpacing =
      Math.max(Math.round(textSize * (this.compact ? 0.4 : 0.45)), this.compact ? 5 : 6)

    theme.setIsMarkdownParserSync(false)
    theme.setIsCodeBlockParserSync(false)
    theme.setIsOnCopy(this.isInputEnded)
    theme.setBlockFirstTopMargin(0)
    theme.setBlockLastBottomMargin(0)
    theme.setBlockTopAndBottomMargins(blockSpacing)
    theme.setOpenGestureSwipe(false)

    theme.setParagraphTextSize(textSize)
    theme.setParagraphTextLineHeight(textLineHeight)
    theme.setParagraphTextColor(textColor)
    theme.setParagraphTypeface(this.textTypeface)
    theme.setParagraphTopMargins(0)
    theme.setParagraphBottomMargins(0)
    this.applyHeadingTheme(theme, titleSizes, titleLineHeights, titleColor, tableBorderColor)
    theme.setHeadingTypeface(this.textTypeface)
    theme.setHeadingTopMargins(blockSpacing)
    theme.setHeadingBottomMargins(Math.max(Math.round(textSize * 0.35), 4))

    theme.setLinkColor(linkColor)
    theme.setLinkSize(textSize)
    theme.setLinkLineHeight(textLineHeight)
    theme.setLinkBackGroupColor(linkBgColor)
    theme.setIsLinkUnderlined(false)

    theme.setBlockQuoteColor(linkColor)
    theme.setBlockQuoteBackGroupColor(quoteBgColor)
    theme.setBlockQuoteWidth(3)
    theme.setBlockQuoteLeftMargin(quoteLeftMargin)
    theme.setBlockQuoteRightMargin(quoteRightMargin)
    theme.setBlockQuoteTopAndBottomMargins(quoteVerticalSpacing)

    this.applyListTheme(theme, textSize, textLineHeight, textColor)

    theme.setCodeTextColor(codeTextColor)
    theme.setCodeBackgroundColor(codeBgColor)
    theme.setCodeTextSize(codeTextSize)
    theme.setCodeTypeface('monospace')
    theme.setCodeBlockTextColor(codeTextColor)
    theme.setCodeBlockTypeTextColor(codeTextColor)
    theme.setCodeBlockTypeTextPadding(4)
    theme.setCodeBlockBackgroundColor(codeBgColor)
    theme.setCodeMultilineMargin(codeMultilineMargin)
    theme.setCodeBlockTypeface('monospace')
    theme.setCodeBlockTextSize(codeTextSize)
    theme.setCodeBlockLineHeight(codeLineHeight)
    theme.setCodeBlockRadius(8)
    theme.setCodeBlockLineNumberHide(false)
    theme.setCodeBlockIconTextHide(false)
    theme.setIsCodeFullScreen(this.showCodeFullScreen)
    theme.setIconWidthAndHeight(22)
    theme.setCodeCopyIcon($r('app.media.markdown_code_copy'))
    theme.setCodeFullScreenIcon($r('app.media.markdown_code_fullscreen'))
    theme.setCodeListTitleTextSize(codeTextSize)
    theme.setCodeListTitleSelectTextSize(codeTextSize)
    theme.setCodeListTitleSelectTextColor(codeTextColor)
    theme.setCodeListTitleUnSelectTextColor(textColor)
    theme.setCodeListTitleSelectBackGroupColor(codeBgColor)
    theme.setCodeListTitleUnSelectBackGroupColor(0x00000000)
    theme.setIsSeparateCodeBlock(false)

    theme.setTableCellPadding(8)
    theme.setTableBorderColor(tableBorderColor)
    theme.setTableBorderWidth(1)
    theme.setTableOddRowBackgroundColor(tableBgColor)
    theme.setTableEvenRowBackgroundColor(tableAltBgColor)
    theme.setTableHeaderRowBackgroundColor(tableHeaderBgColor)
    theme.setTableTitleTextColor(titleColor)
    theme.setTableTitleTextSize(textSize)
    theme.setTableTextLineHeight(textLineHeight)
    theme.setTableTitleLineHeight(textLineHeight)
    theme.setTableContentTextColor(textColor)
    theme.setTableContentTextSize(textSize)
    theme.setTableContentTextLineHeight(textLineHeight)
    theme.setTableRadius(6)
    theme.setTableScrollBarShow(false)
    theme.setTableScrollBarColor(tableBorderColor)

    theme.setThematicBreakColor(tableBorderColor)
    this.applyInlineDecorationTheme(theme, textSize, textColor)
    theme.setLatexDefaultText(true)
    theme.setLatexMathTextSize(this.latexFontSize > 0 ? this.latexFontSize : this.chatFontSize + (this.compact ? 0 : 2))
    theme.setLatexMathTextColor(textColor)
    theme.setLatexMathBackGroupColor(0x00000000)
    theme.setLatexMathColorFormat(LatexMathColorFormat.COLOR_FORMAT_BGRA_8888)
    theme.setLatexMathBlockCenter(false)
    theme.setIsDark(uiState.isDarkMode)

    config.setMarkdownTheme(theme)
    config.setLinkCallback((url: string): void => {
      this.onOpenLink('', url)
    })
    config.setImageCallback((src: string, _sources: Array<string>): void => {
      this.onImageClick(src)
    })
    config.setTextCopyCallback((text: string): void => {
      this.onCopyText(text)
    })
    config.setCodeCopyCallback((code: string): void => {
      this.onCopyCode(code)
    })
    config.setCodeFullScreenCallback((code: string, codeType: string | undefined): void => {
      this.onCodeFullScreen(code, codeType ?? '')
    })
    return config
  }

  private getMarkdownConfig(): MarkdownConfiguration {
    const signature = this.buildConfigSignature()
    if (this.cachedConfig !== null && this.cachedConfigSignature === signature) {
      return this.cachedConfig
    }
    const config = this.buildMarkdownConfig()
    this.cachedConfig = config
    this.cachedConfigSignature = signature
    return config
  }

  private getMarkdownPlugin(): MarkdownPlugin {
    if (this.cachedPlugin !== null) {
      return this.cachedPlugin
    }
    const plugin = new MarkdownPlugin()
    plugin.setIsTablePlugin(true)
    plugin.setIsLatexMathPlugin(true)
    plugin.setIsStrikethroughPlugin(true)
    plugin.setIsTaskListPlugin(true)
    plugin.setIsLinkifyPlugin(true, [])
    plugin.setIsHtmlPlugin(true)
    plugin.setIsSubPlugin(true)
    plugin.setIsSupPlugin(true)
    plugin.setIsTocPlugin(true)
    plugin.setIsFootnotePlugin(true)
    this.cachedPlugin = plugin
    return plugin
  }


  build() {
    Column() {
      ForEach([this.buildConfigSignature()], (_renderKey: string) => {
        CJMarkdown({
          content: this.getTypefaceAwareContent(),
          isInputEnded: this.isInputEnded,
          incrementalAnalysis: this.incrementalAnalysis,
          useCangjieComponent: this.useCangjieComponent,
          config: this.getMarkdownConfig(),
          plugin: this.getMarkdownPlugin()
        })
      }, (renderKey: string): string => renderKey)
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }
}
