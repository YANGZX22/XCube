import { hdsMaterial } from '@kit.UIDesignKit'
import { HdsMiniBarButton } from 'hds_button'
import {
  createButtonTouchHandler,
  getButtonAnimation,
  getButtonScale
} from '../utils/ButtonAnimationUtils'

@ComponentV2
export struct ChatFloatingImmersiveButton {
  @Param barWidth: number = 40
  @Param barHeight: number = 40
  @Param contentPadding: number = 0
  @Param iconResource: Resource = $r('sys.symbol.chevron_down')
  @Param iconSize: number = 20
  @Param iconColor: ResourceColor[] = [Color.Gray]
  @Param iconOffsetY: number = -4
  @Event onButtonClick: () => void = () => {}
  @Local private pressed: boolean = false

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
    Row() {
      HdsMiniBarButton({
        barWidth: this.barWidth,
        barHeight: this.barHeight,
        contentPadding: this.contentPadding,
        containerSize: {
          width: this.barWidth + this.contentPadding * 4,
          height: this.barHeight + this.contentPadding * 4
        },
        maskColor: Color.Transparent,
        enableGradientMask: true,
        barBottomMargin: 0,
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE,
        barBackgroundColor: Color.Transparent,
        clipToBarShape: false,
        onButtonClick: (): void => {
          this.onButtonClick()
        }
      }) {
        this.contentBuilder()
      }
    }
    .scale(getButtonScale(this.pressed))
    .animation(getButtonAnimation())
    .onTouch(createButtonTouchHandler((pressed: boolean): void => {
      this.pressed = pressed
    }))
  }
}
