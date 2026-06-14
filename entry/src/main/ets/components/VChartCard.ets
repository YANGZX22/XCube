import { VChart } from '@visactor/harmony-vchart'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

// VChartCard 使用 V1 @Component：VChart 的 spec 是 @Link，需要 V1 的 $$ 双向绑定，
// 故本卡片与 VChart 同属 V1 状态体系；父组件（MessageBubble，V2）仅作纯组件树嵌套，
// 通过构造参数传入不可变的 spec JSON 字符串，不依赖 V1/V2 状态自动同步。
@Component
export struct VChartCard {
  @Prop specJson: string = ''
  @Prop summary: string = ''
  @Prop chartType: string = ''
  @State private spec: Object | null = null
  @State private parseError: string = ''

  private get themePrimary(): string {
    const value = getAppUiState().themePrimary as string | null | undefined
    return value !== undefined && value !== null && value !== '' ? value : '#4E6F9E'
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode === true
  }

  aboutToAppear(): void {
    this.parseSpec()
  }

  private parseSpec(): void {
    try {
      this.spec = JSON.parse(this.specJson) as Object
      this.parseError = ''
    } catch (e) {
      this.spec = null
      this.parseError = '图表配置解析失败'
    }
  }

  build() {
    Column() {
      Row() {
        Column()
          .width(4)
          .height(16)
          .borderRadius(2)
          .backgroundColor(this.themePrimary)

        Text(this.getChartTypeLabel())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 6 })

        Blank()
      }
      .width('100%')
      .height(30)
      .alignItems(VerticalAlign.Center)

      if (this.spec !== null) {
        Row() {
          VChart({ spec: this.spec, w: 320, h: 240 })
        }
        .width('100%')
        .height(240)
        .justifyContent(FlexAlign.Center)
        .clip(true)
      } else {
        Text(this.parseError)
          .fontSize(12)
          .fontColor($r('app.color.status_error'))
          .width('100%')
          .height(120)
          .textAlign(TextAlign.Center)
      }

      if (this.summary.trim().length > 0) {
        Text(this.summary)
          .fontSize(12)
          .lineHeight(17)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 12 })
    .backgroundColor(this.isDarkMode ? '#14171F' : '#FFFFFF')
    .border({
      width: 1,
      color: withColorAlpha(this.themePrimary, this.isDarkMode ? '33' : '22')
    })
    .borderRadius(12)
    .clip(true)
  }

  private getChartTypeLabel(): string {
    switch (this.chartType) {
      case 'bar':
        return '柱状图'
      case 'area':
        return '面积图'
      case 'scatter':
        return '散点图'
      case 'pie':
        return '饼图'
      case 'donut':
        return '环形图'
      case 'rose':
        return '玫瑰图'
      case 'funnel':
        return '漏斗图'
      case 'wordCloud':
        return '词云图'
      case 'sankey':
        return '桑基图'
      case 'dualAxis':
        return '双轴图'
      default:
        return '折线图'
    }
  }
}
