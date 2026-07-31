import { uiMaterial } from '@kit.ArkUI'

@ComponentV2
export struct ChatFloatingImmersiveButton {
  @Param barWidth: number = 40
  @Param barHeight: number = 40
  @Param contentPadding: number = 0
  @Param iconResource: Resource = $r('sys.symbol.chevron_down')
  @Param iconSize: number = 20
  @Param iconColor: ResourceColor[] = [Color.Gray]
  @Param iconOffsetY: number = 0
  @Param responsePadding: number = 8
  @Param enableShadow: boolean = false
  @Param shadowRadius: number = 18
  @Param shadowColor: ResourceColor = 'rgba(15, 23, 42, 0.18)'
  @Param shadowOffsetY: number = 6
  @Event onButtonClick: () => void = () => {}
  private lastClickAt: number = 0

  private emitButtonClick(): void {
    const now = Date.now()
    if (now - this.lastClickAt < 120) {
      return
    }
    this.lastClickAt = now
    this.onButtonClick()
  }

  @Builder
  DefaultContentBuilder() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(this.iconResource)
        .fontSize(this.iconSize)
        .fontColor(this.iconColor)
        .translate({ y: this.iconOffsetY })
    }
    .width(this.barWidth)
    .height(this.barHeight)
  }

  @BuilderParam contentBuilder: () => void = this.DefaultContentBuilder

  build() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      this.contentBuilder()
    }
    .width(this.barWidth)
    .height(this.barHeight)
    .padding(this.contentPadding)
    .backgroundColor(Color.Transparent)
    .borderRadius(Math.min(this.barWidth, this.barHeight) / 2)
    .clip(false)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      applyShadow: this.enableShadow,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .shadow({
      radius: this.enableShadow ? this.shadowRadius : 0,
      color: this.enableShadow ? this.shadowColor : Color.Transparent,
      offsetX: 0,
      offsetY: this.shadowOffsetY
    })
    .responseRegion({
      x: -this.responsePadding,
      y: -this.responsePadding,
      width: this.barWidth + this.responsePadding * 2,
      height: this.barHeight + this.responsePadding * 2
    })
    .onClick(() => {
      this.emitButtonClick()
    })
  }
}
