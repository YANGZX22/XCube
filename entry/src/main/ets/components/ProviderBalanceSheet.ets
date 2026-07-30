/**
 * 服务商余额弹层
 * 展示已开启余额查询的各服务商余额，支持刷新。
 */
import { getAppUiState } from '../state/AppUiState'
import { BalanceResult } from '../services/ProviderBalanceService'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { ChatFloatingImmersiveButton } from './ChatFloatingImmersiveButton'

@ObservedV2
export class BalanceSheetState {
  @Trace results: BalanceResult[] = []
  @Trace loading: boolean = false
}

@ComponentV2
export struct ProviderBalanceSheet {
  @Param state: BalanceSheetState = new BalanceSheetState()
  @Event onRefresh: () => void = (): void => {}
  @Event onClose: () => void = (): void => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }

  build() {
    Column() {
      // 顶部标题 + 刷新
      Row() {
        ChatFloatingImmersiveButton({
          barWidth: 40,
          barHeight: 40,
          iconResource: $r('sys.symbol.xmark'),
          iconSize: 17,
          iconColor: [this.themePrimary],
          iconOffsetY: -4,
          responsePadding: 0,
          onButtonClick: (): void => {
            this.onClose()
          }
        }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(17)
              .fontColor([this.themePrimary])
          }
          .width(40)
          .height(40)
          .translate({ y: -4 })
        }

        Text($r('app.string.balance_query'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        ChatFloatingImmersiveButton({
          barWidth: 40,
          barHeight: 40,
          iconResource: $r('sys.symbol.arrow_clockwise'),
          iconSize: 18,
          iconColor: [this.themePrimary],
          iconOffsetY: -4,
          responsePadding: 0,
          onButtonClick: (): void => {
            if (!this.state.loading) {
              this.onRefresh()
            }
          }
        }) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.state.loading) {
              LoadingProgress()
                .width(20)
                .height(20)
                .color(this.themePrimary)
            } else {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(18)
                .fontColor([this.themePrimary])
            }
          }
          .width(40)
          .height(40)
          .translate({ y: -4 })
        }
      }
      .width('100%')
      .padding({ left: 20, right: 16, top: 8, bottom: 12 })

      // 列表 / 空态
      if (this.state.results.length === 0 && this.state.loading) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(this.themePrimary)
            .margin({ bottom: 14 })
          Text($r('app.string.loading'))
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .padding({ top: 34, bottom: 42, left: 24, right: 24 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.state.results.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.creditcard'))
            .fontSize(40)
            .fontColor([$r('app.color.text_tertiary')])
            .margin({ bottom: 12 })
          Text($r('app.string.balance_query_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ top: 32, bottom: 40, left: 24, right: 24 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          ForEach(this.state.results, (item: BalanceResult) => {
            this.BalanceRow(item)
          }, (item: BalanceResult) => item.providerId)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
    }
    .width('100%')
    .padding({ bottom: 8 })
  }

  @Builder
  BalanceRow(item: BalanceResult) {
    Row() {
      Column() {
        Text(item.providerName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (!item.success) {
          Text(item.error !== '' ? item.error : $r('app.string.balance_query_failed'))
            .fontSize(12)
            .fontColor($r('app.color.status_error'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (item.success) {
        Row() {
          Text(item.balance)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.themePrimary)
          if (item.currency !== '') {
            Text(item.currency)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
        }
        .alignItems(VerticalAlign.Bottom)
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor(withColorAlpha(this.themeBackground, 'CC'))
    .margin({ bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }
}
