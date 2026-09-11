import { uiMaterial } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'
import { getBlurBottomShadow } from '../utils/BlurShadowUtils'
import { isWrappedMaterialApiAvailable, shouldUseWrappedMaterial } from '../utils/WrappedMaterialSupport'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { formatBillingAmount } from '../utils/ModelBillingUtils'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import {
  buildUsageActivityCalendar,
  DailyUsageActivity,
  getUsageActivityDayKey,
  UsageActivityCalendar,
  UsageActivityCell,
  UsageActivityMonth,
  UsageActivityWeek
} from '../utils/UsageActivityUtils'

const ACTIVITY_CELL_PITCH: number = 22
const ACTIVITY_CELL_SIZE: number = 18
const ACTIVITY_MONTH_HEIGHT: number = 24

@ComponentV2
export struct UsageActivityCard {
  @Param days: DailyUsageActivity[] = []
  @Param startMs: number = 0
  @Param endMs: number = 0
  @Param loading: boolean = true
  @Param loadFailed: boolean = false
  @Param active: boolean = true
  @Event onRetry: () => void = (): void => {}
  @Event onHeatmapTouchChanged: (touching: boolean) => void = (_touching: boolean): void => {}
  @Local selectedDayKey: string = ''
  private scroller: Scroller = new Scroller()
  private positionedAtToday: boolean = false
  private readonly weekdays: number[] = [0, 1, 2, 3, 4, 5, 6]
  private readonly levels: number[] = [0, 1, 2, 3, 4]

  @Computed
  private get calendar(): UsageActivityCalendar {
    return buildUsageActivityCalendar(this.days, this.startMs, this.endMs)
  }

  @Computed
  private get popupSystemMaterial(): uiMaterial.Material | undefined {
    if (!isWrappedMaterialApiAvailable()) {
      return undefined
    }
    if (!shouldUseWrappedMaterial()) {
      return uiMaterial.Material.empty
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN
    })
  }

  @Monitor('active', 'loading')
  private onVisibilityChanged(): void {
    this.selectedDayKey = ''
    if (this.loading) {
      this.positionedAtToday = false
    }
  }

  private getLevelColor(level: number): string {
    const alpha = level === 0 ? (getAppUiState().isDarkMode ? '16' : '0F') :
      (level === 1 ? '30' : (level === 2 ? '68' : (level === 3 ? 'AA' : 'FF')))
    return withColorAlpha(getAppUiState().themePrimary, alpha)
  }

  private getMonthLabel(month: number): string {
    const english: string[] = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    return pickLocalizedText(`${month}月`, english[month - 1])
  }

  private getWeekdayLabel(weekday: number): string {
    if (weekday === 0) {
      return pickLocalizedText('一', 'M')
    }
    if (weekday === 2) {
      return pickLocalizedText('三', 'W')
    }
    return weekday === 4 ? pickLocalizedText('五', 'F') : ''
  }

  private formatTokens(tokens: number): string {
    return tokens.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  }

  private getDayDetails(day: DailyUsageActivity): string {
    let text = `${day.dayKey}\n${this.formatTokens(day.totalTokens)} Token`
    text += pickLocalizedText(`\n输入 ${this.formatTokens(day.inputTokens)} · 输出 ${this.formatTokens(day.outputTokens)}`,
      `\nInput ${this.formatTokens(day.inputTokens)} · Output ${this.formatTokens(day.outputTokens)}`)
    if (day.messageCount === 0) {
      return text + pickLocalizedText('\n预估费用：0（无使用记录）', '\nEstimated cost: 0 (no usage recorded)')
    }
    if (day.totalTokens === 0) {
      text += pickLocalizedText('\n这些消息未记录 Token 用量', '\nNo token usage was saved for these messages')
    }
    if (day.costs.length === 0) {
      text += pickLocalizedText('\n预估费用：暂无计费记录', '\nEstimated cost: no billing data')
    } else {
      text += pickLocalizedText('\n预估费用：', '\nEstimated cost:')
      for (const cost of day.costs) {
        text += `\n${cost.currency} ${formatBillingAmount(cost.currency, cost.estimatedCost)}`
      }
    }
    if (day.unpricedMessageCount > 0) {
      text += pickLocalizedText(`\n${day.unpricedMessageCount} 条回复未配置计费或缺少费用记录`,
        `\n${day.unpricedMessageCount} replies have no pricing or cost data`)
    }
    return text
  }

  private handleHeatmapTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.onHeatmapTouchChanged(true)
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.onHeatmapTouchChanged(false)
    }
  }

  private positionAtToday(): void {
    if (!this.positionedAtToday && this.active) {
      this.scroller.scrollTo({ xOffset: this.calendar.weeks.length * ACTIVITY_CELL_PITCH, yOffset: 0, animation: false })
      this.positionedAtToday = true
    }
  }

  private handleDayPopupStateChange(dayKey: string, isVisible: boolean): void {
    // Dismissing a previous popup must not clear a newly selected date.
    if (!isVisible && this.selectedDayKey === dayKey) {
      this.selectedDayKey = ''
    }
  }

  private getDayPopupOptions(day: DailyUsageActivity): PopupOptions | CustomPopupOptions {
    if (shouldUseWrappedMaterial()) {
      // Use the native text Popup and its own material scope, as in the SDK example.
      // Leave its background, shadow and content rendering to the system.
      const options: PopupOptions = {
        message: this.getDayDetails(day),
        placement: Placement.Top,
        systemMaterial: this.popupSystemMaterial,
        onStateChange: (event) => {
          this.handleDayPopupStateChange(day.dayKey, event.isVisible)
        }
      }
      return options
    }

    const options: CustomPopupOptions = {
      builder: (): void => { this.BlurDayPopupContent(day) },
      placement: Placement.Top,
      width: 300,
      radius: 20,
      enableArrow: false,
      // Only the fallback content supplies a transparent Gaussian blur. Remove the
      // host's default opaque mask so it does not cover the sampled background.
      popupColor: Color.Transparent,
      backgroundBlurStyle: BlurStyle.NONE,
      shadow: getBlurBottomShadow(),
      onStateChange: (event) => {
        this.handleDayPopupStateChange(day.dayKey, event.isVisible)
      }
    }
    const material = this.popupSystemMaterial
    if (material !== undefined) {
      options.systemMaterial = material
    }
    return options
  }

  @Builder
  private BlurDayPopupContent(day: DailyUsageActivity) {
    Row() {
      Text(this.getDayDetails(day))
        .width('100%')
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(23)
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor(Color.Transparent)
    .backdropBlur(24)
    .clip(true)
  }

  @Builder
  private DayCell(cell: UsageActivityCell) {
    if (cell.inRange) {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Row()
          .width(ACTIVITY_CELL_SIZE)
          .height(ACTIVITY_CELL_SIZE)
          .borderRadius(4)
          .backgroundColor(this.getLevelColor(cell.level))
          .hitTestBehavior(HitTestMode.None)
      }
      .width(ACTIVITY_CELL_PITCH)
      .height(ACTIVITY_CELL_PITCH)
      .padding(1)
      .backgroundColor(Color.Transparent)
      .borderRadius(6)
      // Keep border and padding geometry identical before/after selection.
      .border({ width: 1, color: this.selectedDayKey === cell.usage.dayKey ? getAppUiState().themePrimary : Color.Transparent })
      .accessibilityText(this.getDayDetails(cell.usage))
      .onClick(() => {
        this.selectedDayKey = this.selectedDayKey === cell.usage.dayKey ? '' : cell.usage.dayKey
      })
      .bindPopup(this.active && this.selectedDayKey === cell.usage.dayKey, this.getDayPopupOptions(cell.usage))
    } else {
      Blank().width(ACTIVITY_CELL_PITCH).height(ACTIVITY_CELL_PITCH).accessibilityLevel('no')
    }
  }

  @Builder
  private Heatmap() {
    Row() {
      Column() {
        Blank().height(ACTIVITY_MONTH_HEIGHT)
        ForEach(this.weekdays, (weekday: number) => {
          Text(this.getWeekdayLabel(weekday))
            .height(ACTIVITY_CELL_PITCH)
            .width(18)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Start)
        }, (weekday: number): string => weekday.toString())
      }
      .width(18)
      .accessibilityLevel('no')

      Scroll(this.scroller) {
        Column() {
          Row() {
            ForEach(this.calendar.months, (month: UsageActivityMonth) => {
              Text(this.getMonthLabel(month.month))
                .width(month.weekCount * ACTIVITY_CELL_PITCH)
                .height(ACTIVITY_MONTH_HEIGHT)
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }, (month: UsageActivityMonth): string => month.key)
          }
          Row() {
            ForEach(this.calendar.weeks, (week: UsageActivityWeek) => {
              Column() {
                ForEach(week.cells, (cell: UsageActivityCell) => {
                  this.DayCell(cell)
                }, (cell: UsageActivityCell): string => cell.usage.dayKey)
              }
              .width(ACTIVITY_CELL_PITCH)
            }, (week: UsageActivityWeek): string => week.key)
          }
        }
        .width(this.calendar.weeks.length * ACTIVITY_CELL_PITCH)
      }
      .layoutWeight(1)
      .height(ACTIVITY_MONTH_HEIGHT + ACTIVITY_CELL_PITCH * 7)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .onAreaChange(() => {
        this.positionAtToday()
      })
      .onVisibleAreaChange([0.01], (isVisible: boolean) => {
        if (isVisible) {
          this.positionAtToday()
        }
      })
      .onScrollStart(() => {
        this.selectedDayKey = ''
      })
    }
    .width('100%')
    .onTouch((event: TouchEvent) => this.handleHeatmapTouch(event))

    Row({ space: 4 }) {
      Text(pickLocalizedText('少', 'Less'))
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
      ForEach(this.levels, (level: number) => {
        Row().width(10).height(10).borderRadius(3).backgroundColor(this.getLevelColor(level))
      }, (level: number): string => level.toString())
      Text(pickLocalizedText('多', 'More'))
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .margin({ top: 10 })

    Text(pickLocalizedText('左右滑动查看，点击方块查看当日 Token 与预估费用。',
      'Swipe to browse. Tap a day for tokens and estimated cost.'))
      .width('100%')
      .fontSize(11)
      .fontColor($r('app.color.text_tertiary'))
      .margin({ top: 8 })
  }

  build() {
    Column() {
      Row() {
        Text(pickLocalizedText('Token 活动', 'Token activity'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(pickLocalizedText('最近一年', 'Past year'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      Text(this.startMs > 0 ? `${getUsageActivityDayKey(this.startMs)} — ${getUsageActivityDayKey(this.endMs - 1)}` : '')
        .width('100%')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 6, bottom: 12 })

      if (this.loading) {
        Row({ space: 8 }) {
          LoadingProgress().width(20).height(20).color(getAppUiState().themePrimary)
          Text(pickLocalizedText('正在读取活动记录…', 'Loading activity…'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height(190)
        .justifyContent(FlexAlign.Center)
      } else if (this.loadFailed) {
        Column({ space: 12 }) {
          Text(pickLocalizedText('活动记录读取失败', 'Could not load activity'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Button(pickLocalizedText('重试', 'Retry'))
            .fontSize(13)
            .fontColor(getAppUiState().themePrimary)
            .backgroundColor(getAppUiState().themePrimaryLight)
            .onClick(() => this.onRetry())
        }
        .width('100%')
        .height(190)
        .justifyContent(FlexAlign.Center)
      } else {
        this.Heatmap()
      }

      Text(pickLocalizedText('按本机已保存消息统计；不同币种分别计费。',
        'Based on locally saved messages; currencies are kept separate.'))
        .width('100%')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 6 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(getAppUiState().themeSurface)
    .borderRadius(22)
    .border({ width: 1, color: getAppUiState().themePrimaryLight })
  }
}
