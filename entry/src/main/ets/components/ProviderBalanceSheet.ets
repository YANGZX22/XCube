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
          barWidth: 40,
          barHeight: 40,
          iconResource: $r('sys.symbol.xmark'),
          iconSize: 17,
          iconColor: [this.themePrimary],
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
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 14 })
      .alignItems(VerticalAlign.Center)

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
        Column({ space: 10 }) {
          ForEach(this.state.results, (item: BalanceResult) => {
            this.BalanceRow(item)
          }, (item: BalanceResult) => `${this.state.revision}:${item.providerId}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 18 })
      }
    }
    .width('100%')
    .padding({ bottom: 8 })
  }

  @Builder
  BalanceRow(item: BalanceResult) {
    Row({ space: 12 }) {
      ProviderIcon({
        iconType: item.providerIconType,
        iconPath: item.providerIconPath,
        textIcon: item.providerTextIcon,
        textIconBgColor: item.providerTextIconBgColor,
        customImagePath: item.providerCustomImagePath,
        iconSize: 42,
        radius: 11,
        bgColor: $r('app.color.divider'),
        brandColor: item.providerBrandColor,
        fallbackSymbol: $r('sys.symbol.cloud'),
        fallbackColor: $r('app.color.text_secondary')
      })

      Column() {
        Text(item.providerName)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (!item.success) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(12)
              .fontColor([$r('app.color.status_error')])

            Text(item.error !== '' ? item.error : $r('app.string.balance_query_failed'))
              .fontSize(12)
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
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.themePrimary)

          if (item.currency !== '') {
            Text(item.currency)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .margin({ bottom: 2 })
          }
        }
        .alignItems(VerticalAlign.Bottom)
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .borderRadius(18)
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
