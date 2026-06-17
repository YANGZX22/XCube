import { hdsMaterial, HdsTabs } from '@kit.UIDesignKit'

/**
 * HdsTabs-based immersive mini bar button.
 */
@ComponentV2
export struct HdsMiniBarButton {
  @Param barWidth: number = 50
  @Param barHeight: number = 50
  @Param contentPadding: number = 8
  @Param containerSize: SizeOptions | undefined = undefined

  @Param iconResource: Resource = $r('sys.symbol.plus')
  @Param iconSize: number = 27
  @Param iconColor: ResourceColor[] = [Color.Gray]
  @Param iconOffsetY: number = 0
  @Param barBackgroundColor: ResourceColor = Color.Transparent
  @Param clipToBarShape: boolean = false

  @Param maskColor: ResourceColor = Color.Transparent
  @Param enableGradientMask: boolean = true
  @Param barBottomMargin: number = 8
  @Param materialType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.IMMERSIVE
  @Param materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE

  @Param barPosition: BarPosition = BarPosition.End
  @Param barOverlap: boolean = true
  @Param onButtonClick: (() => void) | undefined = undefined

  @Builder
  defaultButtonBuilder() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(this.iconResource)
        .fontSize(this.iconSize)
        .fontColor(this.iconColor)
        .translate({ y: this.iconOffsetY })
    }
    .width(this.barWidth)
    .height(this.barHeight)
  }

  @BuilderParam buttonContent: () => void = this.defaultButtonBuilder

  private getComputedContainerSize(): SizeOptions {
    if (this.containerSize !== undefined) {
      return this.containerSize
    }
    return {
      width: this.barWidth + this.contentPadding * 4,
      height: this.barHeight + this.contentPadding * 4
    }
  }

  build() {
    Row() {
      if (this.enableGradientMask) {
        HdsTabs() {
          TabContent()
            .tabBar(this.buttonContent())
        }
        .barWidth(this.barWidth)
        .barHeight(this.barHeight)
        .barOverlap(this.barOverlap)
        .barPosition(this.barPosition)
        .vertical(false)
        .barBackgroundColor(this.barBackgroundColor)
        .width(this.barWidth)
        .height(this.barHeight)
        .backgroundColor(Color.Transparent)
        .borderRadius(Math.min(this.barWidth, this.barHeight) / 2)
        .clip(this.clipToBarShape)
        .barFloatingStyle({
          gradientMask: {
            maskColor: this.maskColor
          },
          barBottomMargin: this.barBottomMargin,
          systemMaterialEffect: {
            materialType: this.materialType,
            materialLevel: this.materialLevel
          }
        })
        .onTabBarClick(() => {
          if (this.onButtonClick) {
            this.onButtonClick()
          }
        })
      } else {
        HdsTabs() {
          TabContent()
            .tabBar(this.buttonContent())
        }
        .barWidth(this.barWidth)
        .barHeight(this.barHeight)
        .barOverlap(this.barOverlap)
        .barPosition(this.barPosition)
        .vertical(false)
        .barBackgroundColor(this.barBackgroundColor)
        .width(this.barWidth)
        .height(this.barHeight)
        .backgroundColor(Color.Transparent)
        .borderRadius(Math.min(this.barWidth, this.barHeight) / 2)
        .clip(this.clipToBarShape)
        .barFloatingStyle({
          barBottomMargin: this.barBottomMargin,
          systemMaterialEffect: {
            materialType: this.materialType,
            materialLevel: this.materialLevel
          }
        })
        .onTabBarClick(() => {
          if (this.onButtonClick) {
            this.onButtonClick()
          }
        })
      }
    }
    .size(this.getComputedContainerSize())
    .padding(this.contentPadding)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
  }
}
