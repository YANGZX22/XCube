import { promptAction } from '@kit.ArkUI'
import { ChatMessage } from '../../models/ChatModels'
import { getAppUiState } from '../../state/AppUiState'
import { pickLocalizedText } from '../../utils/LocalizedTextUtils'
import { getMessageCacheHitPercent } from '../../utils/ModelBillingUtils'
import {
  countReplySteps, formatReplySpeed, getReplySpeedTier, ReplyStepCounts, replyTokensPerSecond
} from '../../utils/ReplyStatistics'
import { getSettingsSheetContentMaxHeight } from '../../utils/SettingsPageLayoutHelper'
import { getPopupMaterial, shouldUseWrappedMaterial } from '../../utils/WrappedMaterialSupport'
import { ImmersiveSheetHeader } from '../ImmersiveSheetHeader'
import { getSettingsTypography } from '../settings/SettingsTypography'
import { ReplySpeedIcon } from './ReplySpeedIcon'

function hasReplyUsage(message: ChatMessage): boolean {
  return message.tokenUsageTracked || message.estimatedInputTokens > 0 || message.estimatedOutputTokens > 0
}

function formatReplyUsage(message: ChatMessage, value: string): string {
  if (!hasReplyUsage(message)) return '—'
  return message.tokenUsageExact ? value : '≈ ' + value
}

@ComponentV2
struct ReplyTiming {
  @Require @Param message: ChatMessage
  @Param showRate: boolean = false
  @Param foreground: ResourceColor = $r('app.color.text_secondary')
  @Local private now: number = 0
  private clock: number = -1

  aboutToAppear(): void {
    this.syncClock()
  }

  aboutToDisappear(): void {
    this.stopClock()
  }

  @Monitor('message', 'message.isGenerating', 'message.generationStartedAt', 'message.modelRoundStartedAt', 'showRate')
  syncClock(): void {
    const running = this.showRate ? this.message.modelRoundStartedAt >= 0 : this.message.generationStartedAt > 0
    if (this.message.isGenerating && running) {
      this.now = Date.now()
      if (this.clock === -1) {
        this.clock = setInterval((): void => { this.now = Date.now() }, 1000)
      }
    } else {
      this.stopClock()
    }
  }

  private stopClock(): void {
    if (this.clock !== -1) {
      clearInterval(this.clock)
      this.clock = -1
    }
  }

  @Computed
  private get elapsedMs(): number {
    return this.message.elapsedGenerationMs(this.now)
  }

  private get elapsedText(): string {
    if (this.elapsedMs < 0) return pickLocalizedText('用时未记录', 'Time not recorded')
    const seconds = Math.floor(this.elapsedMs / 1000)
    if (seconds < 60) return pickLocalizedText(`已用时 ${seconds} 秒`, `Elapsed ${seconds}s`)
    const minutes = Math.floor(seconds / 60)
    return pickLocalizedText(`已用时 ${minutes} 分 ${seconds % 60} 秒`, `Elapsed ${minutes}m ${seconds % 60}s`)
  }

  @Computed
  private get rate(): number | undefined {
    if (!hasReplyUsage(this.message)) return undefined
    return replyTokensPerSecond(this.message, this.now)
  }

  private get speedText(): string {
    return this.rate === undefined ? '—' : formatReplyUsage(this.message, formatReplySpeed(this.rate))
  }

  build() {
    if (this.showRate) {
      Row({ space: 8 }) {
        ReplySpeedIcon({
          tier: getReplySpeedTier(this.rate),
          isGenerating: this.message.isGenerating,
          modelRoundActive: this.message.modelRoundStartedAt >= 0
        })
        Text(pickLocalizedText('平均输出速度', 'Average output speed'))
          .font(getSettingsTypography().sectionTitle)
          .fontColor(getAppUiState().themeTextPrimary)
          .layoutWeight(1)
        Text(this.speedText)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(getAppUiState().themeTextPrimary)
        Text('token/s')
          .font(getSettingsTypography().subtitle)
          .fontColor($r('app.color.text_caption'))
      }
      .width('100%')
    } else {
      Text(this.elapsedText)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.foreground)
    }
  }
}

@ComponentV2
struct ReplyStatCell {
  @Require @Param label: string
  @Require @Param value: string
  @Require @Param symbol: Resource

  build() {
    Column({ space: 5 }) {
      Row({ space: 5 }) {
        SymbolGlyph(this.symbol)
          .fontSize(14)
          .fontColor([getAppUiState().themePrimary])
          .accessibilityLevel('no')
        Text(this.label)
          .font(getSettingsTypography().subtitle)
          .fontColor(getAppUiState().themeTextSecondary)
          .flexShrink(1)
      }
      Text(this.value)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(getAppUiState().themeTextPrimary)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@ComponentV2
struct ReplyStatisticsDialog {
  @Require @Param message: ChatMessage
  @Event onClose: () => void = (): void => {}

  @Computed
  private get steps(): ReplyStepCounts {
    return countReplySteps(this.message)
  }

  @Computed
  private get cacheHitPercent(): string | null {
    return getMessageCacheHitPercent(this.message)
  }

  @Builder
  private ColumnDivider() {
    Divider()
      .vertical(true)
      .height(32)
      .strokeWidth(0.5)
      .color(getAppUiState().themePrimary)
  }

  @Builder
  private TotalLine(label: string, icon: Resource, value: () => string) {
    Row({ space: 8 }) {
      Image(icon)
        .width(20)
        .height(20)
        .supportSvg2(true)
        .colorFilter(getAppUiState().themePrimary)
        .draggable(false)
        .accessibilityLevel('no')
      Text(label)
        .font(getSettingsTypography().sectionTitle)
        .fontColor(getAppUiState().themeTextPrimary)
        .layoutWeight(1)
      Text(value())
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(getAppUiState().themeTextPrimary)
    }
    .width('100%')
  }

  build() {
    Column() {
      ImmersiveSheetHeader({
        title: pickLocalizedText('回复统计', 'Reply statistics'),
        titleFont: getSettingsTypography().pageTitle,
        onLeadingClick: (): void => this.onClose()
      })

      Scroll() {
        Column({ space: 20 }) {
          Column({ space: 12 }) {
            this.TotalLine(pickLocalizedText('Token 总计', 'Total tokens'), $r('app.media.lucide_square_sparkles'),
              (): string => formatReplyUsage(this.message,
                (this.message.estimatedInputTokens + this.message.estimatedOutputTokens).toLocaleString()))
            Row({ space: 12 }) {
              ReplyStatCell({
                label: pickLocalizedText('累计输入', 'Input tokens'),
                symbol: $r('sys.symbol.arrow_down'),
                value: formatReplyUsage(this.message, this.message.estimatedInputTokens.toLocaleString())
              }).layoutWeight(1)
              this.ColumnDivider()
              ReplyStatCell({
                label: pickLocalizedText('累计输出', 'Output tokens'),
                symbol: $r('sys.symbol.arrow_up'),
                value: formatReplyUsage(this.message, this.message.estimatedOutputTokens.toLocaleString())
              }).layoutWeight(1)
            }
            .width('100%')
            Row({ space: 12 }) {
              ReplyStatCell({
                label: pickLocalizedText('命中 Token', 'Cache-hit tokens'),
                symbol: $r('sys.symbol.arrow_down_layer'),
                value: this.cacheHitPercent === null ? '—' : this.message.cacheReadTokens.toLocaleString()
              }).layoutWeight(1)
              this.ColumnDivider()
              ReplyStatCell({
                label: pickLocalizedText('命中率', 'Cache hit rate'),
                symbol: $r('sys.symbol.dart_target'),
                value: `${this.cacheHitPercent ?? '--'}%`
              }).layoutWeight(1)
            }
            .width('100%')
          }
          .width('100%')
          ReplyTiming({ message: this.message, showRate: true })
          Column({ space: 12 }) {
            this.TotalLine(pickLocalizedText('总步数', 'Total steps'), $r('app.media.lucide_footprints'),
              (): string => this.steps.total.toString())
            Row({ space: 8 }) {
              ReplyStatCell({ label: pickLocalizedText('思考', 'Reasoning'),
                symbol: $r('sys.symbol.lightbulb'), value: this.steps.reasoning.toString() }).layoutWeight(1)
              this.ColumnDivider()
              ReplyStatCell({ label: pickLocalizedText('回答', 'Answers'),
                symbol: $r('sys.symbol.text_bubble_left_2'), value: this.steps.answers.toString() }).layoutWeight(1)
              this.ColumnDivider()
              ReplyStatCell({ label: pickLocalizedText('工具调用', 'Tool calls'),
                symbol: $r('sys.symbol.wrench_and_screwdriver'), value: this.steps.tools.toString() }).layoutWeight(1)
            }
            .width('100%')
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 20, right: 20, top: 8, bottom: 24 })
      }
      .width('100%')
      .constraintSize({ maxHeight: getSettingsSheetContentMaxHeight(getAppUiState().windowHeightVp) })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
  }
}

@ComponentV2
export struct ReplyStatisticsHeader {
  @Require @Param message: ChatMessage
  @Param foreground: ResourceColor = $r('app.color.text_secondary')

  @Builder
  private Details(message: ChatMessage, dialog: promptAction.DialogController) {
    ReplyStatisticsDialog({ message: message, onClose: (): void => dialog.close() })
  }

  private openDetails(): void {
    const message = this.message
    const dialog = new promptAction.DialogController()
    this.getUIContext().getPromptAction().presentCustomDialog(
      (): void => this.Details(message, dialog), dialog, {
        alignment: DialogAlignment.Center,
        autoCancel: true,
        cornerRadius: 24,
        backgroundColor: Color.Transparent,
        backgroundBlurStyle: shouldUseWrappedMaterial() ? BlurStyle.NONE : BlurStyle.COMPONENT_THICK,
        systemMaterial: getPopupMaterial()
      }
    ).catch((error: Error): void => {
      console.error('ReplyStatistics', error.message)
    })
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 5 }) {
        Image($r('app.media.lucide_gauge'))
          .width(15)
          .height(15)
          .supportSvg2(true)
          .colorFilter(this.foreground)
          .draggable(false)
          .accessibilityLevel('no')
        ReplyTiming({ message: this.message, foreground: this.foreground })
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(11)
          .fontColor([this.foreground])
          .accessibilityLevel('no')
      }
    }
    .height(28)
    .padding(0)
    .borderRadius(4)
    .backgroundColor(Color.Transparent)
    .accessibilityDescription(pickLocalizedText('查看回复统计', 'View reply statistics'))
    .onClick((): void => this.openDetails())
  }
}
