import { ImmersiveButtonSurface } from './ImmersiveButtonSurface'
import { InteractiveMaterialButton } from './InteractiveMaterialButton'
import { shouldUseWrappedMaterial, WRAPPED_MATERIAL_REGULAR } from '../utils/WrappedMaterialSupport'
import { getBlurBottomShadow, getBlurFloatingActionShadow } from '../utils/BlurShadowUtils'
import { uiMaterial } from '@kit.ArkUI'
import { VisualEffectsMode } from '../models/ThemeColors'
import { getAppUiState } from '../state/AppUiState'

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
  @Param enableMaterialInteraction: boolean = false
  @Param enableShadow: boolean = false
  @Param shadowRadius: number = 18
  @Param shadowColor: ResourceColor = 'rgba(15, 23, 42, 0.18)'
  @Param shadowOffsetY: number = 6
  @Event onButtonClick: () => void = () => {}
  private lastClickAt: number = 0

  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  private emitButtonClick(): void {
    const now = Date.now()
    if (now - this.lastClickAt < 120) {
      return
    }
    this.lastClickAt = now
    this.onButtonClick()
  }

  private getButtonShadow(): ShadowOptions {
    if (!shouldUseWrappedMaterial()) {
      return this.enableShadow ? getBlurFloatingActionShadow() : getBlurBottomShadow(false)
    }
    return {
      radius: this.enableShadow ? this.shadowRadius : 0,
      color: this.enableShadow ? this.shadowColor : Color.Transparent,
      offsetX: 0,
      offsetY: this.shadowOffsetY
    }
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
    if (this.isManuscriptMode) {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        this.contentBuilder()
      }
      .width(this.barWidth)
      .height(this.barHeight)
      .padding(this.contentPadding)
      .backgroundColor(Color.Transparent)
      .borderRadius(0)
      .border({ width: 0, color: Color.Transparent })
      .clip(false)
      .responseRegion({
        x: -this.responsePadding,
        y: -this.responsePadding,
        width: this.barWidth + this.responsePadding * 2,
        height: this.barHeight + this.responsePadding * 2
      })
      .onClick(() => {
        this.emitButtonClick()
      })
    } else if (this.enableMaterialInteraction) {
      InteractiveMaterialButton({
        surfaceWidth: this.barWidth,
        surfaceHeight: this.barHeight,
        buttonPadding: this.contentPadding,
        responsePadding: this.responsePadding,
        materialStyle: WRAPPED_MATERIAL_REGULAR,
        applyShadow: this.enableShadow,
        buttonShadow: this.getButtonShadow(),
        onActivate: () => {
          this.emitButtonClick()
        }
      }) {
        this.contentBuilder()
      }
    } else {
      Stack({ alignContent: Alignment.TopStart }) {
        ImmersiveButtonSurface({
          materialFactory: () => (new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR,
            materialColor: Color.Transparent,
            applyShadow: this.enableShadow,
            interactive: true,
            lightEffect: { color: undefined }
          })),
          // 降级阴影只由前景 Button 绘制，避免背板再叠一层。
          fallbackShadow: false,
          cornerRadius: Math.min(this.barWidth, this.barHeight) / 2
        }) {
          Button({ type: ButtonType.Normal, stateEffect: false }) {
            this.contentBuilder()
          }
          .width(this.barWidth)
          .height(this.barHeight)
          .padding(this.contentPadding)
          .backgroundColor(Color.Transparent)
          .borderRadius(Math.min(this.barWidth, this.barHeight) / 2)
          .clip(false)
          .shadow(this.getButtonShadow())
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
      .width(this.barWidth)
      .height(this.barHeight)
      .responseRegion({
        x: -this.responsePadding,
        y: -this.responsePadding,
        width: this.barWidth + this.responsePadding * 2,
        height: this.barHeight + this.responsePadding * 2
      })
      .clip(false)
    }
  }
}
