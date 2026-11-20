import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { ImmersiveMaterialAnchor } from './ImmersiveMaterialBackdrop'

const BUBBLE_CORNERS: BorderRadiuses = { topLeft: 20, topRight: 20, bottomLeft: 20, bottomRight: 6 }

@ComponentV2
export struct UserMessageSurface {
  @Param hasAttachments: boolean = false
  @Param isEditing: boolean = false
  @Param isSelected: boolean = false
  @BuilderParam content: () => void
  @Local private widthVp: number = 0
  @Local private heightVp: number = 0

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ImmersiveMaterialAnchor({
        surfaceWidth: this.widthVp,
        surfaceHeight: this.heightVp,
        cornerRadius: BUBBLE_CORNERS
      })

      Column() {
        this.content()
      }
      .alignItems(HorizontalAlign.Start)
      .padding(this.hasAttachments ? 8 : { left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(Color.Transparent)
      .borderRadius(BUBBLE_CORNERS)
      .clip(true)
      .constraintSize({ maxWidth: '75%' })
      .border({
        width: this.isEditing ? 2 : (this.isSelected ? 1.2 : 0.5),
        color: this.isEditing ? '#FFFFFF' :
          (this.isSelected ? withColorAlpha(getAppUiState().themePrimary, '66') : 'rgba(255, 255, 255, 0.15)')
      })
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
        const width = Number(size.width)
        const height = Number(size.height)
        if (Number.isFinite(width) && width > 0 && Math.abs(width - this.widthVp) > 0.1) {
          this.widthVp = width
        }
        if (Number.isFinite(height) && height > 0 && Math.abs(height - this.heightVp) > 0.1) {
          this.heightVp = height
        }
      })
    }
    .clip(false)
  }
}
