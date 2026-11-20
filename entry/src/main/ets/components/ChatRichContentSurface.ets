import { uiMaterial } from '@kit.ArkUI'
import { VisualEffectsMode } from '../models/ThemeColors'
import { getAppUiState } from '../state/AppUiState'
import { ImmersiveMaterialBackdrop } from './ImmersiveMaterialBackdrop'

@Builder
export function chatRichContentBackdrop(radius: number) {
  ImmersiveMaterialBackdrop({
    cornerRadius: radius,
    materialFactory: () => new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      interactive: false,
      lightEffect: null,
      applyShadow: true
    })
  })
}

@ComponentV2
export struct ChatRichContentSurface {
  @Param cornerRadius: number = 12
  @Param layoutWidth: Length | LayoutPolicy = '100%'
  @BuilderParam content: () => void

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (getAppUiState().visualEffectsMode !== VisualEffectsMode.MANUSCRIPT) {
        chatRichContentBackdrop(this.cornerRadius)
      }
      this.content()
    }
    .width(this.layoutWidth)
    .height(LayoutPolicy.wrapContent)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
    .accessibilityLevel('no')
  }
}
