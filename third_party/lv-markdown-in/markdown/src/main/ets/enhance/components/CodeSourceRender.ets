import { markdownCodeThemeChangeEventName } from '../constant/CodeTheme'
import { MDBaseController } from '../controller/BaseController'
import { CodeBlockImpl } from '../impl/CodeBlockImpl'
import { HighlightCode, HighlightNode } from '../model/highlightNode'
import { PrismHighlightUtil } from '../utils/PrismHighlightUtil'

import { BlockSelectionStartInfo, TextSelectionSegment } from '../model/TextSelectionInfo'
import { TextSelectionController } from '../controller/TextSelectionController'
import { TextSelectionMouseTracker } from '../utils/TextSelectionMouseUtil'
import { generateRandomString } from '../utils/RandomString'

const HIGHLIGHT_DEBOUNCE_MS = 90

@Component
export struct CodeSourceRender {
  @Prop transparentBackground: boolean = false
  @Prop markdownUnion: string = ''
  @Prop @Watch('refreshHighlight') text: string = ''
  @Prop @Watch('refreshHighlight') lang: string = 'code'
  @Prop autoCollapse: boolean = true
  @Prop selectionUnion: string = ''
  private codeController: TextController = new TextController()
  private selectionId: string = 'md_code_' + generateRandomString()
  private mouseTracker: TextSelectionMouseTracker = new TextSelectionMouseTracker()
  private selectionMounted: boolean = false
  @Prop selectable: boolean = false
  @Prop lineNumberWidth: number = 34
  @Prop contentBottomPadding: number = 12
  @Prop contentTopPadding: number = 0
  @State highlightNode: HighlightNode[] = []
  @State MAX_ROWS: number = 10
  @State codeTextStyleVersion: number = 0
  BASE_ROWS: number = 10
  private highlightVersion: number = 0
  private highlightDebounceTimer: number = 0
  private codeThemeListener: (() => void) | null = null
  private codeTextStyleListener: (() => void) | null = null

  aboutToAppear(): void {
    this.refreshHighlight()
    this.codeThemeListener = (): void => {
      this.refreshHighlight()
    }
    getContext().eventHub.on(markdownCodeThemeChangeEventName, this.codeThemeListener)
    this.codeTextStyleListener = (): void => {
      this.codeTextStyleVersion++
    }
    getContext().eventHub.on(
      CodeBlockImpl.getTextStyleChangeEventName(this.markdownUnion),
      this.codeTextStyleListener
    )
  }

  aboutToDisappear(): void {
    this.highlightVersion++
    if (this.codeThemeListener) {
      getContext().eventHub.off(markdownCodeThemeChangeEventName, this.codeThemeListener)
      this.codeThemeListener = null
    }
    if (this.codeTextStyleListener) {
      getContext().eventHub.off(
        CodeBlockImpl.getTextStyleChangeEventName(this.markdownUnion),
        this.codeTextStyleListener
      )
      this.codeTextStyleListener = null
    }
    if (this.highlightDebounceTimer) {
      clearTimeout(this.highlightDebounceTimer)
      this.highlightDebounceTimer = 0
    }
  }

  refreshHighlight() {
    const controller = MDBaseController.getMarkdownController(this.markdownUnion)
    const colors = controller.getCodeHighlight()
    const text = this.text || ''
    const lang = this.lang || 'code'
    const isDarkTheme = controller.getCodeBlockTheme() == 'dark'
    const autoCollapse = this.shouldAutoCollapse()
    const autoCollapseThreshold = controller.getCodeBlockAutoCollapseThreshold()
    const version = ++this.highlightVersion

    const cached = PrismHighlightUtil.getCached(text, colors, lang, isDarkTheme)
    if (cached) {
      this.applyHighlightRows(cached, autoCollapse, autoCollapseThreshold)
    } else {
      this.applyHighlightRows(this.buildPlainTextRows(text, colors.normal as string), autoCollapse,
        autoCollapseThreshold)
    }

    if (this.highlightDebounceTimer) {
      clearTimeout(this.highlightDebounceTimer)
    }
    this.highlightDebounceTimer = setTimeout(() => {
      this.highlightDebounceTimer = 0
      PrismHighlightUtil.highlight(text, colors, lang, isDarkTheme).then((result: HighlightNode[]) => {
        if (version != this.highlightVersion) {
          return
        }
        this.applyHighlightRows(result, autoCollapse, autoCollapseThreshold)
      })
    }, HIGHLIGHT_DEBOUNCE_MS)
  }

  private shouldAutoCollapse(): boolean {
    return this.autoCollapse && MDBaseController.getMarkdownController(this.markdownUnion)
      .getCodeBlockAutoCollapseEnable()
  }

  private applyHighlightRows(rows: HighlightNode[], autoCollapse: boolean, autoCollapseThreshold: number) {
    this.highlightNode = rows
    this.BASE_ROWS = rows.length
    this.MAX_ROWS = autoCollapse ? Math.min(autoCollapseThreshold, this.BASE_ROWS) : this.BASE_ROWS
    this.registerSelectionBlock()
  }

  private registerSelectionBlock(): void {
    if (!this.selectionMounted || this.selectionUnion === '') return
    const text = this.visibleRows().map((row: HighlightNode) =>
      row.code.map((token: HighlightCode) => token.text).join('')).join('\n')
    TextSelectionController.getInstance(this.selectionUnion).registerBlock(this.selectionId, this.codeController,
      [new TextSelectionSegment(text.length, text)])
  }

  private buildPlainTextRows(text: string, normalColor: string): HighlightNode[] {
    return text.split('\n').map((line: string): HighlightNode => {
      const cell: HighlightCode = { color: normalColor, text: line, type: 'normal' }
      const row: HighlightNode = { type: 'row', code: [cell] }
      return row
    })
  }

  private visibleRows(): HighlightNode[] {
    return this.highlightNode.slice(0, this.MAX_ROWS)
  }

  private visibleRowCount(): number {
    return Math.min(this.highlightNode.length, this.MAX_ROWS)
  }

  private showMore() {
    animateTo({ duration: 300 }, () => {
      this.MAX_ROWS = this.BASE_ROWS
      this.registerSelectionBlock()
    })
  }

  private isDarkTheme(): boolean {
    return MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockTheme() == 'dark'
  }

  private showLineNumber(): boolean {
    return MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockIdxState()
  }

  private getCodeFontFamily(): ResourceStr {
    return MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockFontFamily()
  }

  private getCodeFontSize(): ResourceStr | number {
    // 建立对样式版本的依赖，保证控制器动态更新时现有代码行同步重绘。
    if (this.codeTextStyleVersion < 0) {
      return 14.8
    }
    return MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockFontSize()
  }

  private getCodeLineHeight(): ResourceStr | number {
    return MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockLineHeight()
  }

  @Builder
  private CodeSpans() {
    ForEach(this.visibleRows(), (row: HighlightNode, rowIndex: number) => {
      ForEach(row.code, (code: HighlightCode) => {
        Span(code.text)
          .fontColor(code.color)
      })
      if (rowIndex < this.visibleRowCount() - 1) {
        Span('\n')
      }
    })
  }

  build() {
    Column() {
      Row() {
        if (this.showLineNumber()) {
          Column() {
            ForEach(this.visibleRows(), (_row: HighlightNode, idx: number) => {
              Row() {
                Text(idx + 1 + '')
                  .lineHeight(this.getCodeLineHeight())
                  .fontSize(this.getCodeFontSize())
                  .fontFamily(this.getCodeFontFamily())
                  .fontColor(this.isDarkTheme() ? '#ff6d7273' : '#606366')
              }
              .justifyContent(FlexAlign.End)
              .padding({ right: 6 })
              .height(this.getCodeLineHeight())
              .border({
                width: {
                  top: 0,
                  left: 0,
                  bottom: 0,
                  right: 0.8
                },
                color: this.isDarkTheme() ? '#2cd8dfe7' : '#2c4d5053'
              })
              .width(this.lineNumberWidth)
            })
          }
          .width(this.lineNumberWidth)
        }

        Scroll() {
          Column() {
            if (this.selectionUnion !== '') {
              Text('', { controller: this.codeController }) {
                this.CodeSpans()
              }
              .id(this.selectionId)
              .lineHeight(this.getCodeLineHeight())
              .fontSize(this.getCodeFontSize())
              .fontFamily(this.getCodeFontFamily())
              .gesture(LongPressGesture().onAction((event: GestureEvent) => {
                const finger = event.fingerList[0]
                if (finger) TextSelectionController.getInstance(this.selectionUnion).triggerStartSelection(
                  new BlockSelectionStartInfo(this.selectionId, finger.localX, finger.localY, true, finger.globalX, finger.globalY))
              }))
              .onMouse((event: MouseEvent) => this.mouseTracker.handleBlockSelectionMouseEvent(this.selectionUnion, this.selectionId, event))
              .onAppear(() => {
                this.selectionMounted = true
                this.registerSelectionBlock()
              })
              .onDisAppear(() => {
                this.selectionMounted = false
                this.mouseTracker.reset()
                TextSelectionController.getInstance(this.selectionUnion).unregisterBlock(this.selectionId)
              })
            } else if (this.selectable) {
              Row() {
                Text() {
                  this.CodeSpans()
                }
                .lineHeight(this.getCodeLineHeight())
                .fontSize(this.getCodeFontSize())
                .fontFamily(this.getCodeFontFamily())
                .copyOption(CopyOptions.LocalDevice)
                .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
              }
            } else {
              ForEach(this.visibleRows(), (row: HighlightNode) => {
                Row() {
                  Text() {
                    ForEach(row.code, (code: HighlightCode) => {
                      Span(code.text)
                        .fontColor(code.color)
                    })
                  }
                  .lineHeight(this.getCodeLineHeight())
                  .fontSize(this.getCodeFontSize())
                  .fontFamily(this.getCodeFontFamily())
                }
                .height(this.getCodeLineHeight())
              })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding({
            left: 12,
            right: 12,
            bottom: this.contentBottomPadding
          })
        }
        .layoutWeight(1)
        .align(Alignment.Start)
        .scrollable(ScrollDirection.Horizontal)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
      }
      .alignItems(VerticalAlign.Top)
      .width('100%')
      .padding({ top: this.contentTopPadding })

      if (this.shouldAutoCollapse() &&
        this.BASE_ROWS > MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockAutoCollapseThreshold() &&
        this.BASE_ROWS != this.MAX_ROWS) {
        Row() {
          Row() {
            Image($rawfile('imgs/down_b.png')).width(20).height(20)
          }
          .justifyContent(FlexAlign.Center)
          .width(60)
          .height(25)
          .borderRadius(99)
          .backgroundColor('#5cffffff')
          .margin({ bottom: 7 })
          .onClick(() => {
            this.showMore()
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.transparentBackground ? Color.Transparent :
      CodeBlockImpl.handleBackgroundColor(MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockTheme()))
  }
}
