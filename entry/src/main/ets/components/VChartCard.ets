import { VChart } from '@visactor/harmony-vchart'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

class VChartDisplayPadding {
  top: number = 32
  right: number = 16
  bottom: number = 86
  left: number = 58

  constructor(top: number, right: number, bottom: number, left: number) {
    this.top = top
    this.right = right
    this.bottom = bottom
    this.left = left
  }
}

class VChartDisplayBottomAxisLabelStyle {
  fontSize: number = 10
  lineHeight: number = 13
  maxLineWidth: number = 88
}

class VChartDisplaySideAxisLabelStyle {
  fontSize: number = 10
  lineHeight: number = 13
}

class VChartDisplayAxisTitleStyle {
  fontSize: number = 11
  lineHeight: number = 15
}

class VChartDisplayAxisLabel {
  visible: boolean = true
  autoHide: boolean = true
  autoLimit: boolean = true
  autoRotate: boolean = false
  autoWrap: boolean = false
  space: number = 6
  style: Object = new VChartDisplaySideAxisLabelStyle()

  constructor(isBottomAxis: boolean) {
    if (isBottomAxis) {
      this.autoHide = false
      this.autoLimit = false
      this.autoWrap = true
      this.space = 8
      this.style = new VChartDisplayBottomAxisLabelStyle()
    }
  }
}

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
  @State private chartViewportWidth: number = 320

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
      const parsed = JSON.parse(this.specJson) as Record<string, Object>
      this.applyDisplayDefaults(parsed)
      this.spec = parsed
      this.parseError = ''
    } catch (e) {
      this.spec = null
      this.parseError = '图表配置解析失败'
    }
  }

  private applyDisplayDefaults(spec: Record<string, Object>): void {
    const hasCartesianAxes = this.hasCartesianAxes(spec)
    if (hasCartesianAxes) {
      spec['padding'] = new VChartDisplayPadding(28, this.getAxisRightPadding(spec), this.getAxisBottomPadding(spec),
        this.getAxisLeftPadding(spec))
      this.enhanceAxes(spec)
    } else {
      spec['padding'] = new VChartDisplayPadding(26, 14, 40, 14)
    }
    this.enhanceTitle(spec)
    this.enhanceLegends(spec)
  }

  private hasCartesianAxes(spec: Record<string, Object>): boolean {
    const axes = spec['axes']
    return Array.isArray(axes) && axes.length > 0
  }

  private getAxisBottomPadding(spec: Record<string, Object>): number {
    let bottom = this.hasDenseCategoryLabels(spec) ? 116 : (this.hasLongCategoryLabels(spec) ? 102 : 82)
    if (this.hasVisibleBottomLegend(spec)) {
      bottom += 16
    }
    return Math.min(bottom, 136)
  }

  private getAxisLeftPadding(spec: Record<string, Object>): number {
    return this.hasLeftAxisTitle(spec) ? 62 : 52
  }

  private getAxisRightPadding(spec: Record<string, Object>): number {
    return this.hasLeftAxisTitle(spec) ? 62 : 52
  }

  private enhanceAxes(spec: Record<string, Object>): void {
    const axes = spec['axes']
    if (!Array.isArray(axes)) {
      return
    }
    for (let i = 0; i < axes.length; i++) {
      const axis = axes[i] as Record<string, Object>
      const orient = `${axis['orient'] ?? ''}`
      const isBottomAxis = orient === 'bottom'
      if (isBottomAxis || orient === 'left' || orient === 'right') {
        axis['label'] = new VChartDisplayAxisLabel(isBottomAxis)
        axis['sampling'] = true
      }
      if (isBottomAxis) {
        axis['labelFlush'] = true
      }
      this.enhanceAxisTitle(axis)
    }
  }

  private enhanceAxisTitle(axis: Record<string, Object>): void {
    const title = axis['title']
    if (title === undefined || title === null || typeof title !== 'object') {
      return
    }
    const titleRecord = title as Record<string, Object>
    titleRecord['space'] = 24
    titleRecord['style'] = new VChartDisplayAxisTitleStyle()
  }

  private enhanceTitle(spec: Record<string, Object>): void {
    const title = spec['title']
    if (title === undefined || title === null || typeof title !== 'object') {
      return
    }
    const titleRecord = title as Record<string, Object>
    titleRecord['padding'] = new VChartDisplayPadding(0, 0, 8, 0)
  }

  private enhanceLegends(spec: Record<string, Object>): void {
    const legends = spec['legends']
    if (legends === undefined || legends === null || typeof legends !== 'object') {
      return
    }
    const legendRecord = legends as Record<string, Object>
    legendRecord['padding'] = new VChartDisplayPadding(8, 0, 0, 0)
  }

  private hasVisibleBottomLegend(spec: Record<string, Object>): boolean {
    const legends = spec['legends']
    if (legends === undefined || legends === null || typeof legends !== 'object') {
      return false
    }
    const legendRecord = legends as Record<string, Object>
    return legendRecord['visible'] === true && `${legendRecord['orient'] ?? 'bottom'}` === 'bottom'
  }

  private hasLeftAxisTitle(spec: Record<string, Object>): boolean {
    const axes = spec['axes']
    if (!Array.isArray(axes)) {
      return false
    }
    for (let i = 0; i < axes.length; i++) {
      const axis = axes[i] as Record<string, Object>
      if (`${axis['orient'] ?? ''}` !== 'left') {
        continue
      }
      const title = axis['title']
      if (title !== undefined && title !== null && typeof title === 'object') {
        const titleRecord = title as Record<string, Object>
        if (titleRecord['visible'] === true && `${titleRecord['text'] ?? ''}`.trim() !== '') {
          return true
        }
      }
    }
    return false
  }

  private hasLongCategoryLabels(spec: Record<string, Object>): boolean {
    const labels = this.getCategoryLabels(spec)
    if (labels.length > 5) {
      return true
    }
    for (let i = 0; i < labels.length; i++) {
      if (labels[i].length > 8 || labels[i].indexOf('\n') >= 0) {
        return true
      }
    }
    return false
  }

  private hasDenseCategoryLabels(spec: Record<string, Object>): boolean {
    return this.getCategoryLabels(spec).length > 6
  }

  private getCategoryLabels(spec: Record<string, Object>): string[] {
    const values = this.getDataValues(spec)
    const labels: string[] = []
    for (let i = 0; i < values.length; i++) {
      const item = values[i] as Record<string, Object>
      const label = `${item['category'] ?? ''}`
      if (label !== '' && !labels.includes(label)) {
        labels.push(label)
      }
    }
    return labels
  }

  private getDataValues(spec: Record<string, Object>): Object[] {
    const data = spec['data']
    if (data === undefined || data === null || typeof data !== 'object') {
      return []
    }
    const dataRecord = data as Record<string, Object>
    const values = dataRecord['values']
    return Array.isArray(values) ? values as Object[] : []
  }

  private handleChartAreaChange(newArea: Area): void {
    const width = Number(newArea.width)
    if (!Number.isFinite(width) || width <= 0) {
      return
    }
    const nextWidth = Math.max(260, Math.min(Math.floor(width), 560))
    if (Math.abs(nextWidth - this.chartViewportWidth) >= 2) {
      this.chartViewportWidth = nextWidth
      this.parseSpec()
    }
  }

  private getChartWidth(): number {
    const currentSpec = this.spec as Record<string, Object> | null
    if (currentSpec === null || !this.hasCartesianAxes(currentSpec)) {
      return this.chartViewportWidth
    }
    const categoryCount = this.getCategoryLabels(currentSpec).length
    if (categoryCount <= 4) {
      return this.chartViewportWidth
    }
    const slotWidth = this.hasLongCategoryLabels(currentSpec) ? 96 : 80
    return Math.max(this.chartViewportWidth, Math.min(900, categoryCount * slotWidth + 108))
  }

  private isChartScrollable(): boolean {
    return this.getChartWidth() > this.chartViewportWidth + 2
  }

  private getChartHeight(): number {
    if (this.chartType === 'pie' || this.chartType === 'donut' || this.chartType === 'rose' ||
      this.chartType === 'funnel') {
      return 268
    }
    if (this.chartType === 'wordCloud' || this.chartType === 'sankey') {
      return 300
    }
    const currentSpec = this.spec as Record<string, Object> | null
    if (currentSpec !== null && this.hasDenseCategoryLabels(currentSpec)) {
      return this.hasVisibleBottomLegend(currentSpec) ? 362 : 342
    }
    if (currentSpec !== null && this.hasLongCategoryLabels(currentSpec)) {
      return this.hasVisibleBottomLegend(currentSpec) ? 342 : 322
    }
    return currentSpec !== null && this.hasVisibleBottomLegend(currentSpec) ? 324 : 300
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
        Scroll() {
          Row() {
            VChart({ spec: this.spec, w: this.getChartWidth(), h: this.getChartHeight() })
          }
          .width(this.getChartWidth())
          .height(this.getChartHeight())
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height(this.getChartHeight())
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(this.isChartScrollable() ? BarState.Auto : BarState.Off)
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.handleChartAreaChange(newArea)
        })
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
