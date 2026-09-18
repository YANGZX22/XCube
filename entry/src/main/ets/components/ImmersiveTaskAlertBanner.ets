import { ImmersiveListSurface } from './ImmersiveListSurface'
import { shouldUseWrappedMaterial } from '../utils/WrappedMaterialSupport'
import { getAppUiState } from '../state/AppUiState'
import { VisualEffectsMode } from '../models/ThemeColors'

/**
 * 会话任务完成后的应用内提示。
 *
 * 材质模式使用独立沉浸背板，模糊模式保留原样；前景按钮仍负责原生点击。
 */
@ComponentV2
export struct ImmersiveTaskAlertBanner {
  @Param message: string = ''
  @Param failed: boolean = false
  @Param actionText: ResourceStr = ''
  @Param bottomInset: number = 0
  @Param accentColor: ResourceColor = $r('app.color.primary')
  @Param cardStrokeColor: ResourceColor = $r('app.color.divider')
  @Param darkMode: boolean = false
  @Event onView: () => void = (): void => {}
  @Event onDismiss: () => void = (): void => {}

  private get useImmersiveMaterial(): boolean {
    return getAppUiState().visualEffectsMode !== VisualEffectsMode.MANUSCRIPT && shouldUseWrappedMaterial()
  }

  private get statusColor(): ResourceColor {
    return this.failed ? $r('app.color.status_error') : $r('app.color.status_success')
  }

  private get statusSymbol(): Resource {
    return this.failed
      ? $r('sys.symbol.exclamationmark_circle')
      : $r('sys.symbol.checkmark_circle_fill')
  }

  @Builder
  private BannerContent() {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.statusSymbol)
          .fontSize(23)
          .fontColor([this.statusColor])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.failed ? 'rgba(239, 68, 68, 0.12)' : 'rgba(34, 197, 94, 0.12)')

      Text(this.message)
        .fontSize(14)
        .lineHeight(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Button(this.actionText, { type: ButtonType.Capsule, stateEffect: false })
        .height(32)
        .padding({ left: 8, right: 8 })
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentColor)
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          this.onView()
        })

      Button({ type: ButtonType.Circle, stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(14)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(30)
      .height(30)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .onClick((): void => {
        this.onDismiss()
      })
    }
    .width('100%')
    .constraintSize({ minHeight: 60, maxWidth: 620 })
    .padding({ left: 12, right: 8, top: 10, bottom: 10 })
    .borderRadius(22)
    .backgroundColor(Color.Transparent)
    .border({ width: this.useImmersiveMaterial ? 0 : 0.5, color: this.cardStrokeColor })
    .backdropBlur(this.useImmersiveMaterial ? 0 : 24)
    .shadow(this.useImmersiveMaterial ? undefined : {
      radius: 28,
      color: this.darkMode ? 'rgba(0, 0, 0, 0.42)' : 'rgba(31, 24, 72, 0.16)',
      offsetX: 0,
      offsetY: 10
    })
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        ImmersiveListSurface({
          isImmersive: this.useImmersiveMaterial,
          cornerRadius: 22
        }) {
          this.BannerContent()
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 620 })
      .clip(false)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 12, right: 12, bottom: this.bottomInset + 12 })
    .position({ x: 0, y: '100%' })
    .translate({ x: 0, y: '-100%' })
    .zIndex(200)
    .transition(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: 14 }))
        .animation({ duration: 260, curve: Curve.EaseOut })
    )
  }
}
