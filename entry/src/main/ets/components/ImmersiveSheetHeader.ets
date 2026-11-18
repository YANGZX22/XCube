import { ImmersiveButtonSurface } from './ImmersiveButtonSurface'
import { uiMaterial } from '@kit.ArkUI'

/**
 * bindSheet 统一标题栏。
 *
 * 左右操作区等宽，标题始终对准弹窗中线。
 * 标题栏中的操作统一使用 36vp 原生圆形沉浸光感 Button。
 */
@ComponentV2
export struct ImmersiveSheetHeader {
  @Param title: string | Resource = ''
  @Param titleFont: Font = { size: 17, weight: FontWeight.Bold }
  @Param leadingSymbol: Resource = $r('sys.symbol.xmark')
  @Param trailingSymbol: Resource = $r('sys.symbol.checkmark')
  @Param showLeading: boolean = true
  @Param showTrailing: boolean = false
  @Param showSecondaryTrailing: boolean = false
  @Param leadingButtonEnabled: boolean = true
  @Param trailingButtonEnabled: boolean = true
  @Param trailingLoading: boolean = false
  @Param materialFeedback: boolean = true
  @Param secondaryTrailingSymbol: Resource = $r('sys.symbol.clean')
  @Param secondaryTrailingColor: ResourceColor = $r('app.color.status_error')
  @Param leadingColor: ResourceColor = $r('app.color.text_primary')
  @Param trailingColor: ResourceColor = $r('app.color.text_primary')
  @Param titleColor: ResourceColor = $r('app.color.text_primary')
  @Event onLeadingClick: () => void = (): void => {}
  @Event onTrailingClick: () => void = (): void => {}
  @Event onSecondaryTrailingClick: () => void = (): void => {}

  private get actionSlotWidth(): number {
    if (this.showTrailing && this.showSecondaryTrailing) {
      return 80
    }
    return this.showLeading || this.showTrailing || this.showSecondaryTrailing ? 36 : 0
  }

  private getActionMaterial(interactive: boolean): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: this.materialFeedback && interactive,
      lightEffect: this.materialFeedback ? { color: undefined } : null
    })
  }

  build() {
    Row() {
      Row() {
        if (this.showLeading) {
          Stack({ alignContent: Alignment.TopStart }) {
            ImmersiveButtonSurface({
              materialFactory: () => (this.getActionMaterial(this.leadingButtonEnabled)),
              cornerRadius: 18
            }) {
              Button({ type: ButtonType.Circle, stateEffect: false }) {
                SymbolGlyph(this.leadingSymbol)
                  .fontSize(17)
                  .fontColor([this.leadingColor])
              }
              .width(36)
              .height(36)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .borderRadius(18)
              .enabled(this.leadingButtonEnabled)
              .onClick(() => {
                if (this.leadingButtonEnabled) {
                  this.onLeadingClick()
                }
              })
            }
          }
          .width(36)
          .height(36)
          .enabled(this.leadingButtonEnabled)
          .clip(false)
        }
      }
      .width(this.actionSlotWidth)
      .height(36)
      .justifyContent(FlexAlign.Start)

      Text(this.title)
        .font(this.titleFont)
        .fontColor(this.titleColor)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 8, right: 8 })

      Row({ space: 8 }) {
        if (this.showSecondaryTrailing) {
          Stack({ alignContent: Alignment.TopStart }) {
            ImmersiveButtonSurface({
              materialFactory: () => (this.getActionMaterial(true)),
              cornerRadius: 18
            }) {
              Button({ type: ButtonType.Circle, stateEffect: false }) {
                SymbolGlyph(this.secondaryTrailingSymbol)
                  .fontSize(17)
                  .fontColor([this.secondaryTrailingColor])
              }
              .width(36)
              .height(36)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .borderRadius(18)
              .onClick(() => {
                this.onSecondaryTrailingClick()
              })
            }
          }
          .width(36)
          .height(36)
          .clip(false)
        }

        if (this.showTrailing) {
          Stack({ alignContent: Alignment.TopStart }) {
            ImmersiveButtonSurface({
              materialFactory: () => (this.getActionMaterial(this.trailingButtonEnabled && !this.trailingLoading)),
              cornerRadius: 18
            }) {
              Button({ type: ButtonType.Circle, stateEffect: false }) {
                if (this.trailingLoading) {
                  LoadingProgress()
                    .width(17)
                    .height(17)
                    .color(this.trailingColor)
                } else {
                  SymbolGlyph(this.trailingSymbol)
                    .fontSize(17)
                    .fontColor([this.trailingColor])
                }
              }
              .width(36)
              .height(36)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .borderRadius(18)
              .enabled(this.trailingButtonEnabled && !this.trailingLoading)
              .onClick(() => {
                if (this.trailingButtonEnabled && !this.trailingLoading) {
                  this.onTrailingClick()
                }
              })
            }
          }
          .width(36)
          .height(36)
          .enabled(this.trailingButtonEnabled && !this.trailingLoading)
          .clip(false)
        }
      }
      .width(this.actionSlotWidth)
      .height(36)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .margin({ bottom: 4 })
    .alignItems(VerticalAlign.Center)
  }
}
