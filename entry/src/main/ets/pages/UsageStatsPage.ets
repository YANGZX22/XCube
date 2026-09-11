import { DrawnFloatingTabBar } from '../components/DrawnFloatingTabBar'
import { UsageActivityCard } from '../components/UsageActivityCard'
import { DailyUsageActivity, getUsageActivityPeriod } from '../utils/UsageActivityUtils'
import { shouldUseDrawnNavigation } from '../utils/DrawnNavigationSupport'
import {
  HdsNavigation,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode,
  HdsTabs
} from '@kit.UIDesignKit'
import { getHdsSystemMaterialEffect, HdsTabsBlurModifier, DrawnTabsContentModifier, getHdsMaterialLightColor } from '../utils/HdsMaterialSupport'
import { shouldUseWrappedMaterial } from '../utils/WrappedMaterialSupport'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  buildPointLightBorderEffect,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'
import {
  getDatabaseService,
  ModelUsageRankingItem,
  UsageBillingSummary
} from '../services/DatabaseService'
import { formatBillingAmount } from '../utils/ModelBillingUtils'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'

const TAG = 'UsageStatsPage'
const RANGE_30D_MS: number = 30 * 24 * 60 * 60 * 1000
const RANKING_LIMIT: number = 10
const RANGE_SWIPE_THRESHOLD: number = 72
const RANGE_DRAG_MAX_OFFSET: number = 44
const RANKING_ANIMATION_DELAY_MS: number = 40
const RANKING_ANIMATION_DURATION_MS: number = 640
const RANGE_FLOATING_TAB_BAR_HEIGHT: number = 52
const RANGE_FLOATING_TAB_BAR_WIDTH: number = 220
const RANGE_FLOATING_TAB_BAR_SIDE_MARGIN: number = 16
const RANGE_FLOATING_TAB_BAR_BOTTOM_MARGIN: number = 12
const RANGE_FLOATING_TAB_BAR_SAFE_BOTTOM_MARGIN: number = 24
const RANGE_FLOATING_TAB_CONTENT_SPACING: number = 16

let usageStatsPagePathStack: NavPathStack | null = null

enum UsageRangeKey {
  ALL = 'all',
  LAST_30D = 'last_30d'
}

@ComponentV2
struct UsageMetricCard {
  @Param icon: Resource = $r('sys.symbol.circle')
  @Param title: ResourceStr = ''
  @Param value: number = 0
  @Param unit: ResourceStr = ''
  @Param primaryColor: string = '#7A68F0'
  @Param primaryLightColor: string = '#E6E1FD'
  @Param surfaceColor: string = '#FDFCFF'

  build() {
    Column() {
      Row({ space: 8 }) {
        Column() {
          SymbolGlyph(this.icon)
            .fontSize(16)
            .fontColor([this.primaryColor])
        }
        .width(28)
        .height(28)
        .borderRadius(9)
        .backgroundColor(this.primaryLightColor)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Text(this.title)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 4 }) {
        Text(this.value.toString())
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.unit)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ bottom: 4 })
      }
      .width('100%')
      .margin({ top: 10 })
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.surfaceColor)
    .borderRadius(16)
    .border({ width: 1, color: this.primaryLightColor })
    .visualEffect(buildPointLightBorderEffect())
  }
}

@Entry
@ComponentV2
struct UsageStatsPage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get bottomAvoidHeight(): number {
    return getAppUiState().bottomAvoidHeight
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }
  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }
  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }
  private get settingsDetailPresentationMode(): string {
    return getAppUiState().settingsDetailPresentationMode
  }
  private get materialType(): number {
    return getAppUiState().materialType
  }
  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }

  @Local currentRange: UsageRangeKey = UsageRangeKey.ALL
  @Local sessionCount: number = 0
  @Local messageCount: number = 0
  @Local distinctModelCount: number = 0
  @Local activeDayCount: number = 0
  @Local ranking: ModelUsageRankingItem[] = []
  @Local billingSummaries: UsageBillingSummary[] = []
  @Local isLoading: boolean = true
  @Local rankingAnimationProgress: number = 0
  @Local rangeSwipeOffsetX: number = 0
  @Local activityDays: DailyUsageActivity[] = []
  @Local activityStartMs: number = 0
  @Local activityEndMs: number = 0
  @Local activityLoading: boolean = true
  @Local activityLoadFailed: boolean = false

  private allRangeScroller: Scroller = new Scroller()
  private last30DaysRangeScroller: Scroller = new Scroller()
  private statsLoadToken: number = 0
  private rankingAnimationTimer: number = -1
  private rangePanDirection: string = 'none'
  private activityLoadToken: number = 0
  private activityTouching: boolean = false

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    this.loadStats()
    this.loadActivity()
  }

  aboutToDisappear(): void {
    this.clearRankingAnimationTimer()
    this.statsLoadToken += 1
    this.activityLoadToken += 1
  }

  // The annual activity calendar is independent of the overview's All / 30-day tabs.
  private async loadActivity(): Promise<void> {
    const loadToken = ++this.activityLoadToken
    const period = getUsageActivityPeriod()
    this.activityStartMs = period.startMs
    this.activityEndMs = period.endMs
    this.activityLoading = true
    this.activityLoadFailed = false
    try {
      const days = await getDatabaseService().getDailyUsageActivity(period.startMs, period.endMs)
      if (loadToken === this.activityLoadToken) {
        this.activityDays = days
      }
    } catch (error) {
      if (loadToken === this.activityLoadToken) {
        this.activityLoadFailed = true
      }
      console.error(TAG, `Failed to load usage activity: ${JSON.stringify(error)}`)
    } finally {
      if (loadToken === this.activityLoadToken) {
        this.activityLoading = false
      }
    }
  }

  private getRangeStartMs(): number {
    if (this.currentRange === UsageRangeKey.LAST_30D) {
      return Date.now() - RANGE_30D_MS
    }
    return 0
  }

  private async loadStats(): Promise<void> {
    const loadToken = this.statsLoadToken + 1
    this.statsLoadToken = loadToken
    this.isLoading = true
    this.rankingAnimationProgress = 0
    this.clearRankingAnimationTimer()
    try {
      const db = getDatabaseService()
      const rangeStart = this.getRangeStartMs()
      const overview = await db.getUsageOverview(rangeStart)
      const ranking = await db.getModelUsageRanking(rangeStart, RANKING_LIMIT)
      const billingSummaries = await db.getUsageBillingSummary(rangeStart)
      if (loadToken !== this.statsLoadToken) {
        return
      }
      this.sessionCount = overview.sessionCount
      this.messageCount = overview.messageCount
      this.distinctModelCount = overview.distinctModelCount
      this.activeDayCount = overview.activeDayCount
      this.ranking = ranking
      this.billingSummaries = billingSummaries
      this.startRankingAnimation()
    } catch (error) {
      console.error(TAG, `Failed to load usage stats: ${JSON.stringify(error)}`)
    } finally {
      if (loadToken === this.statsLoadToken) {
        this.isLoading = false
      }
    }
  }

  private clearRankingAnimationTimer(): void {
    if (this.rankingAnimationTimer !== -1) {
      clearTimeout(this.rankingAnimationTimer)
      this.rankingAnimationTimer = -1
    }
  }

  private startRankingAnimation(): void {
    this.clearRankingAnimationTimer()
    if (this.ranking.length === 0) {
      this.rankingAnimationProgress = 1
      return
    }
    this.rankingAnimationTimer = setTimeout((): void => {
      this.rankingAnimationTimer = -1
      this.getUIContext().animateTo({ duration: RANKING_ANIMATION_DURATION_MS, curve: Curve.EaseOut }, () => {
        this.rankingAnimationProgress = 1
      })
    }, RANKING_ANIMATION_DELAY_MS)
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private handleBack(): void {
    if (usageStatsPagePathStack !== null && usageStatsPagePathStack.size() > 0) {
      usageStatsPagePathStack.pop()
    }
  }

  private getCompactContentTopPadding(): number {
    return getHdsTopNavigationContentTopPadding(this.px2vp(this.topAvoidHeight), this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp, this.windowHeightVp, (): void => this.CompactTitleStackBuilder(), [], this)
  }

  private getMaxRankingCount(): number {
    let max = 0
    for (let i = 0; i < this.ranking.length; i++) {
      const c = this.ranking[i].count
      if (c > max) {
        max = c
      }
    }
    return max
  }

  private getRankingFraction(count: number): number {
    const max = this.getMaxRankingCount()
    if (max <= 0) {
      return 0
    }
    const fraction = count / max
    if (fraction < 0.04) {
      return 0.04
    }
    return fraction
  }

  private getAnimatedRankingFraction(count: number): number {
    return this.getRankingFraction(count) * this.rankingAnimationProgress
  }

  private getAnimatedRankingCount(count: number): number {
    if (this.rankingAnimationProgress >= 1) {
      return count
    }
    return Math.floor(count * this.rankingAnimationProgress)
  }

  private getRankingDisplayName(item: ModelUsageRankingItem): string {
    if (item.modelName !== '') {
      return item.modelName
    }
    if (item.modelId !== '') {
      return item.modelId
    }
    return '—'
  }

  private formatTokenCount(value: number): string {
    const safeValue = Math.max(0, value)
    if (safeValue >= 1_000_000) {
      return `${(safeValue / 1_000_000).toFixed(2)}M`
    }
    if (safeValue >= 1_000) {
      return `${(safeValue / 1_000).toFixed(1)}K`
    }
    return safeValue.toString()
  }

  private isEmpty(): boolean {
    return this.ranking.length === 0 && this.messageCount === 0
  }

  private switchRange(rangeKey: UsageRangeKey): void {
    if (this.currentRange === rangeKey) {
      return
    }
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
      this.currentRange = rangeKey
      this.rangeSwipeOffsetX = 0
      this.rankingAnimationProgress = 0
    })
    this.loadStats()
  }

  private getCurrentRangeIndex(): number {
    return this.currentRange === UsageRangeKey.ALL ? 0 : 1
  }

  private getRangeByIndex(index: number): UsageRangeKey {
    return index === 0 ? UsageRangeKey.ALL : UsageRangeKey.LAST_30D
  }

  private getRangeScroller(rangeKey: UsageRangeKey): Scroller {
    return rangeKey === UsageRangeKey.ALL ? this.allRangeScroller : this.last30DaysRangeScroller
  }

  private getFloatingRangeTabBottomMargin(): number {
    return this.px2vp(this.bottomAvoidHeight) > 0 ? RANGE_FLOATING_TAB_BAR_SAFE_BOTTOM_MARGIN :
      RANGE_FLOATING_TAB_BAR_BOTTOM_MARGIN
  }

  private getRangeContentBottomPadding(): number {
    return RANGE_FLOATING_TAB_BAR_HEIGHT + this.getFloatingRangeTabBottomMargin() +
      RANGE_FLOATING_TAB_CONTENT_SPACING
  }

  private getRangeBySwipeOffset(offsetX: number): UsageRangeKey | null {
    if (offsetX <= -RANGE_SWIPE_THRESHOLD && this.currentRange === UsageRangeKey.ALL) {
      return UsageRangeKey.LAST_30D
    }
    if (offsetX >= RANGE_SWIPE_THRESHOLD && this.currentRange === UsageRangeKey.LAST_30D) {
      return UsageRangeKey.ALL
    }
    return null
  }

  private getDampedRangeSwipeOffset(offsetX: number): number {
    let offset = offsetX * 0.18
    if ((this.currentRange === UsageRangeKey.ALL && offset > 0) ||
      (this.currentRange === UsageRangeKey.LAST_30D && offset < 0)) {
      offset = offset * 0.35
    }
    if (offset > RANGE_DRAG_MAX_OFFSET) {
      return RANGE_DRAG_MAX_OFFSET
    }
    if (offset < -RANGE_DRAG_MAX_OFFSET) {
      return -RANGE_DRAG_MAX_OFFSET
    }
    return offset
  }

  private handleRangeSwipeStart(): void {
    // Latch the touch origin until the gesture ends, even after the finger lifts.
    this.rangePanDirection = this.activityTouching ? 'activity' : 'none'
  }

  private handleRangeSwipeUpdate(event: GestureEvent): void {
    const absX = Math.abs(event.offsetX)
    const absY = Math.abs(event.offsetY)
    if (this.rangePanDirection === 'none' && (absX > 12 || absY > 12)) {
      this.rangePanDirection = absX > absY * 1.25 ? 'horizontal' : 'vertical'
    }
    if (this.rangePanDirection !== 'horizontal') {
      return
    }
    this.rangeSwipeOffsetX = this.getDampedRangeSwipeOffset(event.offsetX)
  }

  private handleRangeSwipeEnd(event: GestureEvent): void {
    const nextRange = this.rangePanDirection === 'horizontal' ? this.getRangeBySwipeOffset(event.offsetX) : null
    this.rangePanDirection = 'none'
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.rangeSwipeOffsetX = 0
    })
    if (nextRange !== null) {
      this.switchRange(nextRange)
    }
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.settings_usage_stats'),
      onBack: () => {
        this.handleBack()
      }
    })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.settings_usage_stats'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(64)
      .padding({ left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(this.themeBackground)
    .border({ width: { bottom: 1 }, color: this.themePrimaryLight })
  }

  @Builder
  private FloatingRangeTab(rangeKey: UsageRangeKey, title: ResourceStr) {
    Column() {
      Text(title)
        .fontSize(13)
        .fontWeight(this.currentRange === rangeKey ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentRange === rangeKey ? (shouldUseDrawnNavigation() ? Color.White : this.themePrimary) : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private SectionTitle(title: ResourceStr, subtitle: ResourceStr | null) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      if (subtitle !== null) {
        Text(subtitle)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 4, bottom: 6 })
  }

  @Builder
  private MetricsGrid() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column() {
          UsageMetricCard({
            icon: $r('sys.symbol.message'),
            title: $r('app.string.usage_stats_metric_sessions'),
            value: this.sessionCount,
            unit: $r('app.string.usage_stats_unit_count'),
            primaryColor: this.themePrimary,
            primaryLightColor: this.themePrimaryLight,
            surfaceColor: this.themeSurface
          })
        }.layoutWeight(1)
        Column() {
          UsageMetricCard({
            icon: $r('sys.symbol.ellipsis_message'),
            title: $r('app.string.usage_stats_metric_messages'),
            value: this.messageCount,
            unit: $r('app.string.usage_stats_unit_count'),
            primaryColor: this.themePrimary,
            primaryLightColor: this.themePrimaryLight,
            surfaceColor: this.themeSurface
          })
        }.layoutWeight(1)
      }
      .width('100%')

      Row({ space: 10 }) {
        Column() {
          UsageMetricCard({
            icon: $r('sys.symbol.square_stack_3d'),
            title: $r('app.string.usage_stats_metric_models'),
            value: this.distinctModelCount,
            unit: $r('app.string.usage_stats_unit_count'),
            primaryColor: this.themePrimary,
            primaryLightColor: this.themePrimaryLight,
            surfaceColor: this.themeSurface
          })
        }.layoutWeight(1)
        Column() {
          UsageMetricCard({
            icon: $r('sys.symbol.calendar'),
            title: $r('app.string.usage_stats_metric_active_days'),
            value: this.activeDayCount,
            unit: $r('app.string.usage_stats_unit_day'),
            primaryColor: this.themePrimary,
            primaryLightColor: this.themePrimaryLight,
            surfaceColor: this.themeSurface
          })
        }.layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private RankingRow(item: ModelUsageRankingItem, rank: number) {
    Column({ space: 8 }) {
      Row() {
        Text(`${rank}`)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(rank <= 3 ? this.themePrimary : $r('app.color.text_tertiary'))
          .width(22)

        Text(this.getRankingDisplayName(item))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`${this.getAnimatedRankingCount(item.count)}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 进度条
      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width('100%')
          .height(6)
          .borderRadius(3)
          .backgroundColor(this.themePrimaryLight)

        Column()
          .width(`${this.getAnimatedRankingFraction(item.count) * 100}%`)
          .height(6)
          .borderRadius(3)
          .backgroundColor(this.themePrimary)
      }
      .width('100%')
      .margin({ left: 22 })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 14, right: 14 })
  }

  @Builder
  private RankingCard() {
    Column() {
      ForEach(this.ranking, (item: ModelUsageRankingItem, index: number) => {
        Column() {
          this.RankingRow(item, index + 1)
          if (index < this.ranking.length - 1) {
            Divider()
              .color(this.themePrimaryLight)
              .margin({ left: 50, right: 14 })
          }
        }
      }, (item: ModelUsageRankingItem, index: number) => `${index}_${item.modelName}_${item.modelId}`)
    }
    .width('100%')
    .backgroundColor(this.themeSurface)
    .borderRadius(18)
    .clip(true)
    .border({ width: 1, color: this.themePrimaryLight })
    .visualEffect(buildPointLightBorderEffect())
  }

  @Builder
  private BillingSummaryRow(item: UsageBillingSummary) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.creditcard'))
            .fontSize(17)
            .fontColor([this.themePrimary])
        }
        .width(32)
        .height(32)
        .borderRadius(10)
        .backgroundColor(this.themePrimaryLight)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column({ space: 2 }) {
          Text(formatBillingAmount(item.currency, item.estimatedCost))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Text(pickLocalizedText(
            `${item.currency} · ${item.messageCount} 条计费消息`,
            `${item.currency} · ${item.messageCount} billed messages`
          ))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 10 }) {
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.arrow_down'))
            .fontSize(11)
            .fontColor([this.themePrimary])
          Text(pickLocalizedText(
            `输入 ${this.formatTokenCount(item.inputTokens)} Token`,
            `Input ${this.formatTokenCount(item.inputTokens)} tokens`
          ))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)

        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.arrow_up'))
            .fontSize(11)
            .fontColor([this.themePrimary])
          Text(pickLocalizedText(
            `输出 ${this.formatTokenCount(item.outputTokens)} Token`,
            `Output ${this.formatTokenCount(item.outputTokens)} tokens`
          ))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
  }

  @Builder
  private BillingSummaryCard() {
    Column() {
      if (this.billingSummaries.length === 0) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(15)
            .fontColor([$r('app.color.text_tertiary')])
          Text($r('app.string.usage_stats_billing_empty'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
        }
        .width('100%')
        .padding(14)
        .alignItems(VerticalAlign.Center)
      } else {
        ForEach(this.billingSummaries, (item: UsageBillingSummary, index: number) => {
          Column() {
            this.BillingSummaryRow(item)
            if (index < this.billingSummaries.length - 1) {
              Divider()
                .color(this.themePrimaryLight)
                .margin({ left: 14, right: 14 })
            }
          }
        }, (item: UsageBillingSummary) => item.currency)
      }
    }
    .width('100%')
    .backgroundColor(this.themeSurface)
    .borderRadius(18)
    .clip(true)
    .border({ width: 1, color: this.themePrimaryLight })
    .visualEffect(buildPointLightBorderEffect())
  }

  @Builder
  private EmptyState() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])
        .margin({ bottom: 4 })
      Text($r('app.string.usage_stats_empty_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      Text($r('app.string.usage_stats_empty_desc'))
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .padding({ top: 64, bottom: 64 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private RangePageContent(rangeKey: UsageRangeKey) {
    Scroll(this.getRangeScroller(rangeKey)) {
      Row() {
        Column() {
          Blank()
            .width('100%')
            .height(this.getCompactContentTopPadding())

          UsageActivityCard({
            days: this.activityDays,
            startMs: this.activityStartMs,
            endMs: this.activityEndMs,
            loading: this.activityLoading,
            loadFailed: this.activityLoadFailed,
            active: this.currentRange === rangeKey,
            onRetry: (): void => { this.loadActivity() },
            onHeatmapTouchChanged: (touching: boolean): void => { this.activityTouching = touching }
          })
            .margin({ top: 6, bottom: 18 })

          if (this.isEmpty() && !this.isLoading) {
            this.EmptyState()
          } else {
            // 总览
            Column() {
              this.SectionTitle($r('app.string.usage_stats_overview_title'), null)
              this.MetricsGrid()
            }
            .width('100%')
            .margin({ top: 6 })

            // 计费统计
            Column() {
              this.SectionTitle(
                $r('app.string.usage_stats_billing_title'),
                $r('app.string.usage_stats_billing_subtitle')
              )
              this.BillingSummaryCard()
            }
            .width('100%')
            .margin({ top: 18 })

            // 模型排行
            if (this.ranking.length > 0) {
              Column() {
                this.SectionTitle($r('app.string.usage_stats_ranking_title'),
                  $r('app.string.usage_stats_ranking_subtitle'))
                this.RankingCard()
              }
              .width('100%')
              .margin({ top: 18 })
            }
          }

          Blank().width('100%').height(this.getRangeContentBottomPadding())
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .translate({ x: this.rangeSwipeOffsetX, y: 0 })
    .parallelGesture(
      PanGesture({ fingers: 1, distance: 18 })
        .onActionStart(() => {
          this.handleRangeSwipeStart()
        })
        .onActionUpdate((event: GestureEvent) => {
          this.handleRangeSwipeUpdate(event)
        })
        .onActionEnd((event: GestureEvent) => {
          this.handleRangeSwipeEnd(event)
        })
    )
  }

  @Builder
  private DrawnRangeTab(index: number) {
    if (index === 0) {
      this.FloatingRangeTab(UsageRangeKey.ALL, $r('app.string.usage_stats_range_all'))
    }
    else {
      this.FloatingRangeTab(UsageRangeKey.LAST_30D, $r('app.string.usage_stats_range_30d'))
    }
  }

  @Builder
  private PageContent() {
    Stack({ alignContent: Alignment.Bottom }) {
      HdsTabs({ barPosition: BarPosition.End, index: this.getCurrentRangeIndex() }) {
        TabContent() {
          this.RangePageContent(UsageRangeKey.ALL)
        }
        .tabBar(this.FloatingRangeTab(UsageRangeKey.ALL, $r('app.string.usage_stats_range_all')))

        TabContent() {
          this.RangePageContent(UsageRangeKey.LAST_30D)
        }
        .tabBar(this.FloatingRangeTab(UsageRangeKey.LAST_30D, $r('app.string.usage_stats_range_30d')))
      }
      .width('100%')
      .height('100%')
      .barMode(BarMode.Fixed)
      .barHeight(shouldUseDrawnNavigation() ? 0 : RANGE_FLOATING_TAB_BAR_HEIGHT)
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .scrollable(false)
      .animationDuration(300)
      .barFloatingStyle(shouldUseDrawnNavigation() ? undefined : {
        barBottomMargin: this.getFloatingRangeTabBottomMargin(),
        barSideMargin: RANGE_FLOATING_TAB_BAR_SIDE_MARGIN,
        barWidth: {
          smallWidth: RANGE_FLOATING_TAB_BAR_WIDTH,
          mediumWidth: RANGE_FLOATING_TAB_BAR_WIDTH,
          largeWidth: RANGE_FLOATING_TAB_BAR_WIDTH
        },
        gradientMask: { maskColor: Color.Transparent },
        lightColor: getHdsMaterialLightColor(Color.White),
        systemMaterialEffect: getHdsSystemMaterialEffect()
      })
      .attributeModifier(shouldUseDrawnNavigation() ? new DrawnTabsContentModifier() : new HdsTabsBlurModifier(shouldUseWrappedMaterial()))
      .backgroundColor(Color.Transparent)
      .clip(false)
      .onChange((index: number) => {
        this.switchRange(this.getRangeByIndex(index))
      })
      if (shouldUseDrawnNavigation()) {
        DrawnFloatingTabBar({
          tabCount: 2,
          selectedIndex: this.getCurrentRangeIndex(),
          barWidth: RANGE_FLOATING_TAB_BAR_WIDTH,
          barHeight: RANGE_FLOATING_TAB_BAR_HEIGHT,
          itemContent: (index: number): void => this.DrawnRangeTab(index),
          onSelect: (index: number) => {
            this.switchRange(this.getRangeByIndex(index))
          }
        })
        .margin({ bottom: this.getFloatingRangeTabBottomMargin() })
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        HdsNavigation() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .titleMode(HdsNavigationTitleMode.MINI)
        .systemBarStyle(
          { statusBarContentColor: getHdsStatusBarContentColor() },
          { statusBarContentColor: getHdsStatusBarContentColor() }
        )
        .hideBackButton(shouldUseDrawnNavigation())
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      } else {
        HdsNavigation() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .titleMode(HdsNavigationTitleMode.MINI)
        .systemBarStyle(
          { statusBarContentColor: getHdsStatusBarContentColor() },
          { statusBarContentColor: getHdsStatusBarContentColor() }
        )
        .hideBackButton(shouldUseDrawnNavigation())
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }
}

@Builder
export function UsageStatsPageBuilder(name: string, param: Object) {
  NavDestination() {
    UsageStatsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    usageStatsPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (usageStatsPagePathStack !== null && usageStatsPagePathStack.size() > 0) {
      usageStatsPagePathStack.pop()
    }
    return true
  })
}
