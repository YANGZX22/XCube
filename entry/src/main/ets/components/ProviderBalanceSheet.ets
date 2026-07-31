/**
 * 服务商余额弹层
 * 展示已开启余额查询的各服务商余额，支持刷新。
 */
import { getAppUiState } from '../state/AppUiState'
import { BalanceResult } from '../services/ProviderBalanceService'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { ChatFloatingImmersiveButton } from './ChatFloatingImmersiveButton'
import { ProviderIcon } from './ProviderIcon'
import { uiMaterial } from '@kit.ArkUI'

@ObservedV2
export class BalanceSheetState {
  @Trace results: BalanceResult[] = []
  @Trace loading: boolean = false
  @Trace revision: number = 0
}

@ComponentV2
export struct ProviderBalanceSheet {
  @Param state: BalanceSheetState = new BalanceSheetState()
  @Event onRefresh: () => void = (): void => {}
  @Event onClose: () => void = (): void => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  build() {
    Column() {
      // 顶部标题与操作
      Row() {
        ChatFloatingImmersiveButton({
          barWidth: 34,
          barHeight: 34,
          iconResource: $r('sys.symbol.xmark'),
          iconSize: 15,
          iconColor: [this.themePrimary],
          responsePadding: 3,
          onButtonClick: (): void => {
            this.onClose()
          }
        }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(15)
              .fontColor([this.themePrimary])
          }
          .width(34)
          .height(34)
        }

        Text($r('app.string.balance_query'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        ChatFloatingImmersiveButton({
          barWidth: 34,
          barHeight: 34,
          iconResource: $r('sys.symbol.arrow_clockwise'),
          iconSize: 16,
          iconColor: [this.themePrimary],
          responsePadding: 3,
          onButtonClick: (): void => {
            if (!this.state.loading) {
              this.onRefresh()
            }
          }
        }) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.state.loading) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(this.themePrimary)
            } else {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(16)
                .fontColor([this.themePrimary])
            }
          }
          .width(34)
          .height(34)
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 6, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      // 列表 / 空态
      if (this.state.results.length === 0 && this.state.loading) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.themePrimary)
            .margin({ bottom: 10 })
          Text($r('app.string.loading'))
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .padding({ top: 28, bottom: 34, left: 20, right: 20 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.state.results.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.creditcard'))
            .fontSize(34)
            .fontColor([$r('app.color.text_tertiary')])
            .margin({ bottom: 10 })
          Text($r('app.string.balance_query_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ top: 26, bottom: 32, left: 20, right: 20 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column({ space: 8 }) {
          ForEach(this.state.results, (item: BalanceResult) => {
            this.BalanceRow(item)
          }, (item: BalanceResult) => `${this.state.revision}:${item.providerId}`)
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 14 })
      }
    }
    .width('100%')
    .padding({ bottom: 6 })
  }

  @Builder
  BalanceRow(item: BalanceResult) {
    Row({ space: 10 }) {
      ProviderIcon({
        iconType: item.providerIconType,
        iconPath: item.providerIconPath,
        textIcon: item.providerTextIcon,
        textIconBgColor: item.providerTextIconBgColor,
        customImagePath: item.providerCustomImagePath,
        iconSize: 36,
        radius: 10,
        bgColor: $r('app.color.divider'),
        brandColor: item.providerBrandColor,
        fallbackSymbol: $r('sys.symbol.cloud'),
        fallbackColor: $r('app.color.text_secondary')
      })

      Column() {
        Text(item.providerName)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (!item.success) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(11)
              .fontColor([$r('app.color.status_error')])

            Text(item.error !== '' ? item.error : $r('app.string.balance_query_failed'))
              .fontSize(11)
              .fontColor($r('app.color.status_error'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .margin({ top: 3 })
          .alignItems(VerticalAlign.Center)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (item.success) {
        Row({ space: 5 }) {
          Text(item.balance)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.themePrimary)

          if (item.currency !== '') {
            Text(item.currency)
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .margin({ bottom: 2 })
          }
        }
        .alignItems(VerticalAlign.Bottom)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(16)
    .border({
      width: 1,
      color: withColorAlpha(this.themePrimary, '38')
    })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: false,
      lightEffect: { color: undefined }
    }))
    .alignItems(VerticalAlign.Center)
  }
}
