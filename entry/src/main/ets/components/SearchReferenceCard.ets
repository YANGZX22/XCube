import { SearchReference } from '../models/ChatModels'
import { webview } from '@kit.ArkWeb'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { uiMaterial } from '@kit.ArkUI'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'
import { VisualEffectsMode } from '../models/ThemeColors'
import {
  buildTimelineBarExpandTransition,
  getTimelineBarExpandAnimation
} from '../utils/TimelineBarTransitionUtils'

@ComponentV2
export struct SearchReferenceCard {
  @Param query: string = ''
  @Param searchEngine: string = ''
  @Param references: SearchReference[] = []
  @Param sourceLabel: string = ''
  // 合并进条目块时由外层统一提供边框、材质与投影，卡片自身只出内容
  @Param embedded: boolean = false
  @Local isExpanded: boolean = false
  @Local showWebSheet: boolean = false
  @Local sheetUrl: string = ''
  @Local sheetTitle: string = ''
  private sheetWebController: webview.WebviewController = new webview.WebviewController()
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }
  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  // 获取引用数量文本
  private getReferenceCountText(): string {
    return `${this.references.length}`
  }

  // 统一格式化展示的搜索关键词（单行、去掉多余空白）
  private getDisplayQuery(): string {
    const trimmed = this.query.trim()
    if (trimmed === '') {
      return ''
    }
    return trimmed.replace(/\s+/g, ' ')
  }

  private getTimelineRailColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '88' : '55')
  }

  build() {
    // 与 ToolCallCard 一致的沉浸材质卡片：标题栏 + 可折叠引用列表
    Column() {
      // ========== 联网查询标题栏 ==========
      Row() {
        // 联网搜索图标
        SymbolGlyph($r('sys.symbol.worldclock_fill_2'))
          .fontSize(13)
          .fontColor([this.isManuscriptMode ? this.themePrimary : $r('app.color.text_secondary')])

        // 标题文本
        Text($r('app.string.web_search'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isManuscriptMode ? this.themePrimary : $r('app.color.text_secondary'))
          .margin({ left: 4 })

        // 来源标签（区分：Function Calling vs 手动搜索链路）
        if (this.sourceLabel.trim() !== '') {
          Text(this.sourceLabel.trim())
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: 6 })
        }

        if (this.searchEngine.trim() !== '') {
          Text(this.searchEngine.trim())
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.MARQUEE })
            .marqueeOptions({
              start: true,
              step: 3,
              loop: -1,
              fromStart: true,
              delay: 600,
              fadeout: true
            })
            .constraintSize({ maxWidth: 88 })
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(this.isManuscriptMode ? 0 : 8)
            .backgroundColor(this.isManuscriptMode ? Color.Transparent : this.themePrimaryLight)
            .border({ width: 0, color: this.themePrimary })
            .margin({ left: 6 })
        }

        // 实际搜索关键词（占据剩余空间，便于排查“关键词优化”是否跑偏）
        if (this.getDisplayQuery() !== '') {
          Text(this.getDisplayQuery())
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        } else {
          Text('')
            .layoutWeight(1)
        }

        // 分隔线
        Row()
          .width(1)
          .height(10)
          .backgroundColor($r('app.color.divider'))
          .margin({ left: 8, right: 8 })

        // 引用数量
        Text(this.getReferenceCountText())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        // 展开/折叠箭头
        SymbolGlyph(this.isExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([$r('app.color.text_tertiary')])
          .margin({ left: 6 })
          .width(12)
          .height(12)
      }
      .width('100%')
      .height(36)
      .padding({ left: 10, right: 8 })
      .borderRadius(this.isManuscriptMode ? 0 : 12)
      .stateStyles({
        normal: {
          .backgroundColor(Color.Transparent)
        },
        pressed: {
          .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '1F' : '12'))
        }
      })
      .onClick(() => {
        this.getUIContext().animateTo(getTimelineBarExpandAnimation(), () => {
          this.isExpanded = !this.isExpanded
        })
      })

      // 引用列表（可折叠）
      if (this.isExpanded) {
        Column({ space: 0 }) {
          ForEach(this.references, (ref: SearchReference, index: number) => {
            this.ReferenceItem(ref, index + 1)
          }, (ref: SearchReference) => ref.id)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .transition(buildTimelineBarExpandTransition())
      }
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .borderRadius(this.embedded || this.isManuscriptMode ? 0 : 12)
    .border({
      width: this.embedded ? 0 : (this.isManuscriptMode ? { top: 1, bottom: 1 } : 0.5),
      color: this.isManuscriptMode ? getAppUiState().themeDivider : this.getTimelineRailColor()
    })
    .clip(false)
    .systemMaterial(this.embedded || this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: this.themeAiBubble,
      applyShadow: false,
      interactive: false,
      lightEffect: { color: undefined }
    }))
    .shadow({
      radius: this.embedded || this.isManuscriptMode ? 0 : 12,
      color: this.embedded || this.isManuscriptMode ? Color.Transparent :
        (this.isDarkMode ? 'rgba(0, 0, 0, 0.32)' : 'rgba(15, 23, 42, 0.14)'),
      offsetX: 0,
      offsetY: 0
    })
    .bindSheet($$this.showWebSheet, this.WebSheetBuilder(), {
      height: SheetSize.LARGE,
      detents: [SheetSize.LARGE],
      dragBar: true,
      showClose: false,
      onDisappear: () => {
        this.sheetUrl = ''
        this.sheetTitle = ''
      }
    })
  }

  @Builder
  WebSheetBuilder() {
    Column() {
      ImmersiveSheetHeader({
        title: this.sheetTitle !== '' ? this.sheetTitle : $r('app.string.common_web_page'),
        onLeadingClick: (): void => {
          this.showWebSheet = false
        }
      })

      if (this.sheetUrl !== '') {
        Web({ src: this.sheetUrl, controller: this.sheetWebController })
          .width('100%')
          .layoutWeight(1)
      } else {
        Column() {
          Text($r('app.string.common_invalid_link'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  ReferenceItem(ref: SearchReference, index: number) {
    Column({ space: 6 }) {
      // 标题行：序号 + 标题
      Row({ space: 8 }) {
        // 序号圆圈
        Text(`${index}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .fontWeight(FontWeight.Medium)
          .width(18)
          .height(18)
          .textAlign(TextAlign.Center)
          .borderRadius(9)
          .backgroundColor(this.themePrimaryLight)

        // 标题
        Text(ref.title)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')

      // 摘要
      if (ref.snippet !== '') {
        Text(ref.snippet)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 26 })
      }

      // URL
      Text(ref.url)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 26 })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 4, right: 4 })
    .stateStyles({
      normal: {
        .backgroundColor(Color.Transparent)
      },
      pressed: {
        .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '1F' : '12'))
      }
    })
    .onClick(() => {
      this.sheetUrl = ref.url
      this.sheetTitle = ref.title
      this.showWebSheet = true
    })
  }
}
