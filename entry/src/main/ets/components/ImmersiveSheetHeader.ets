import { uiMaterial } from '@kit.ArkUI'

/**
 * bindSheet 统一标题栏。
 *
 * 左右操作位始终等宽，确保标题不受按钮数量影响并严格居中。
 * 标题栏中的操作统一使用 36vp 原生圆形沉浸光感 Button。
 */
@ComponentV2
export struct ImmersiveSheetHeader {
  @Param title: string | Resource = ''
  @Param leadingSymbol: Resource = $r('sys.symbol.xmark')
  @Param trailingSymbol: Resource = $r('sys.symbol.checkmark')
  @Param showLeading: boolean = true
  @Param showTrailing: boolean = false
  @Param showSecondaryTrailing: boolean = false
  @Param leadingButtonEnabled: boolean = true
  @Param trailingButtonEnabled: boolean = true
  @Param trailingLoading: boolean = false
  @Param secondaryTrailingSymbol: Resource = $r('sys.symbol.clean')
  @Param secondaryTrailingColor: ResourceColor = $r('app.color.status_error')
  @Param leadingColor: ResourceColor = $r('app.color.text_primary')
  @Param trailingColor: ResourceColor = $r('app.color.text_primary')
  @Param titleColor: ResourceColor = $r('app.color.text_primary')
  @Event onLeadingClick: () => void = (): void => {}
  @Event onTrailingClick: () => void = (): void => {}
  @Event onSecondaryTrailingClick: () => void = (): void => {}

  private getActionMaterial(interactive: boolean): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: interactive,
      lightEffect: { color: undefined }
    })
  }

  build() {
    Row() {
      Row() {
        if (this.showLeading) {
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
          .systemMaterial(this.getActionMaterial(this.leadingButtonEnabled))
          .onClick(() => {
            if (this.leadingButtonEnabled) {
              this.onLeadingClick()
            }
          })
        }
      }
      .width(this.showSecondaryTrailing ? 80 : 36)
      .height(36)
      .justifyContent(FlexAlign.Start)

      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.titleColor)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 8, right: 8 })

      Row({ space: 8 }) {
        if (this.showSecondaryTrailing) {
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
          .systemMaterial(this.getActionMaterial(true))
          .onClick(() => {
            this.onSecondaryTrailingClick()
          })
        }

        if (this.showTrailing) {
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
          .systemMaterial(this.getActionMaterial(this.trailingButtonEnabled && !this.trailingLoading))
          .onClick(() => {
            if (this.trailingButtonEnabled && !this.trailingLoading) {
              this.onTrailingClick()
            }
          })
        }
      }
      .width(this.showSecondaryTrailing ? 80 : 36)
      .height(36)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }
}
