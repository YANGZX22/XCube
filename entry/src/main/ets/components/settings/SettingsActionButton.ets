import { getAppUiState } from '../../state/AppUiState'
import { WRAPPED_MATERIAL_REGULAR } from '../../utils/WrappedMaterialSupport'
import { InteractiveMaterialButton } from '../InteractiveMaterialButton'

@ComponentV2
export struct SettingsActionButton {
  @Require @Param label: ResourceStr
  @Param foreground: ResourceColor | undefined = undefined
  @Param leadingSymbol: Resource | undefined = undefined
  @Param trailingSymbol: Resource | undefined = undefined
  @Param accessibilityLabel: string = ''
  @Param compact: boolean = false
  @Param buttonHeight: number = 42
  @Param maxWidth: Length = '100%'
  @Param tint: ResourceColor = Color.Transparent
  @Param applyShadow: boolean = true
  @Param isEnabled: boolean = true
  @Event onActivate: () => void = (): void => {}
  @Local private measuredWidth: number = 0

  private get layoutWidth(): Length {
    if (!this.compact) {
      return '100%'
    }
    const context = this.getUIContext()
    const text = typeof this.label === 'string' ? this.label :
      context.getHostContext()?.resourceManager.getStringSync(this.label.id) ?? ''
    const size = context.getMeasureUtils().measureTextSize({
      textContent: text, fontSize: 12, fontWeight: FontWeight.Medium
    })
    const symbolCount = (this.leadingSymbol ? 1 : 0) + (this.trailingSymbol ? 1 : 0)
    const symbolWidth = symbolCount * (context.px2vp(context.fp2px(13)) + 4)
    return Math.ceil(context.px2vp(Number(size.width)) + symbolWidth) + 20
  }

  @Builder
  private ActionSymbol(trailing: boolean) {
    SymbolGlyph(trailing ? this.trailingSymbol : this.leadingSymbol)
      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontSize(13)
      .fontColor([this.foreground ?? getAppUiState().themePrimary])
      .accessibilityLevel('no')
  }

  build() {
    Stack() {
      InteractiveMaterialButton({
        surfaceWidth: this.measuredWidth,
        surfaceHeight: this.buttonHeight,
        buttonType: ButtonType.Capsule,
        materialStyle: WRAPPED_MATERIAL_REGULAR,
        materialColor: this.tint,
        applyShadow: this.applyShadow,
        isEnabled: this.isEnabled,
        interactive: this.isEnabled,
        accessibilityLabel: this.accessibilityLabel || this.label,
        onActivate: (): void => this.onActivate()
      }) {
        Row({ space: 4 }) {
          if (this.leadingSymbol) {
            this.ActionSymbol(false)
          }
          Text(this.label)
            .fontSize(this.compact ? 12 : 14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.foreground ?? getAppUiState().themePrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.trailingSymbol) {
            this.ActionSymbol(true)
          }
        }
      }
    }
    .width(this.layoutWidth)
    .constraintSize({ maxWidth: this.maxWidth })
    .height(this.buttonHeight)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
    .onSizeChange((_previous: SizeOptions, size: SizeOptions): void => {
      const width = Number(size.width)
      if (Number.isFinite(width) && width >= 0 && this.measuredWidth !== width) {
        this.measuredWidth = width
      }
    })
  }
}
