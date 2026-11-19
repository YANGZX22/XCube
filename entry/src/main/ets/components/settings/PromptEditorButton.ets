import { uiMaterial } from '@kit.ArkUI'
import { getAppUiState } from '../../state/AppUiState'
import { createButtonTouchHandler, getButtonAnimation, getButtonScale } from '../../utils/ButtonAnimationUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { shouldUseWrappedMaterial, WRAPPED_MATERIAL_REGULAR, WRAPPED_MATERIAL_THIN } from '../../utils/WrappedMaterialSupport'
import { InteractiveMaterialButton } from '../InteractiveMaterialButton'

const HORIZONTAL_PADDING = 14
const LABEL_GAP = 6
const LABEL_FONT_SIZE = 14
const TOKEN_FONT_SIZE = 12

@ComponentV2
export struct PromptEditorButton {
  @Require @Param label: Resource
  @Param token: string = ''
  @Param fillWidth: boolean = false
  @Param isEnabled: boolean = true
  @Param labelColor: ResourceColor | undefined = undefined
  @Param materialColor: ResourceColor = Color.Transparent
  @Param materialStyle: uiMaterial.ImmersiveStyle = WRAPPED_MATERIAL_REGULAR
  @Event onActivate: () => void = () => {}

  @Local private measuredWidth: number = 0
  @Local private blurPressed: boolean = false

  private get labelWeight(): FontWeight {
    return this.token === '' ? FontWeight.Medium : FontWeight.Regular
  }

  private get layoutWidth(): Length {
    if (this.fillWidth) {
      return '100%'
    }
    const context = this.getUIContext()
    const measure = context.getMeasureUtils()
    const label = measure.measureTextSize({
      textContent: this.label, fontSize: LABEL_FONT_SIZE, fontWeight: this.labelWeight
    })
    const token = measure.measureTextSize({ textContent: this.token, fontSize: TOKEN_FONT_SIZE })
    const gap = this.token === '' ? 0 : LABEL_GAP
    return Math.ceil(context.px2vp(Number(label.width) + Number(token.width))) + HORIZONTAL_PADDING * 2 + gap
  }

  build() {
    Stack() {
      InteractiveMaterialButton({
        surfaceWidth: this.measuredWidth,
        surfaceHeight: this.fillWidth ? 44 : 40,
        buttonType: ButtonType.Capsule,
        materialStyle: this.materialStyle,
        materialColor: this.materialColor,
        interactive: this.isEnabled,
        isEnabled: this.isEnabled,
        applyShadow: true,
        accessibilityLabel: this.label,
        onActivate: this.onActivate
      }) {
        Row({ space: LABEL_GAP }) {
          Text(this.label)
            .fontSize(LABEL_FONT_SIZE)
            .fontWeight(this.labelWeight)
            .fontColor(this.labelColor ?? getAppUiState().themePrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          if (this.token !== '') {
            Text(this.token)
              .fontSize(TOKEN_FONT_SIZE)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
          }
        }
        .width('100%')
        .padding({ left: HORIZONTAL_PADDING, right: HORIZONTAL_PADDING })
        .justifyContent(this.token === '' ? FlexAlign.Center : FlexAlign.Start)
      }
    }
    .scale(getButtonScale(this.isEnabled && this.blurPressed))
    .animation(getButtonAnimation())
    .width(this.layoutWidth)
    .constraintSize({ maxWidth: '100%' })
    .height(this.fillWidth ? 44 : 40)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
    .onSizeChange((_previous: SizeOptions, size: SizeOptions): void => {
      const width = Number(size.width)
      if (Number.isFinite(width) && width >= 0 && width !== this.measuredWidth) {
        this.measuredWidth = width
      }
    })
    .onTouch(createButtonTouchHandler((pressed: boolean): void => {
      this.blurPressed = pressed && this.isEnabled && !shouldUseWrappedMaterial()
    }))
  }
}

@ComponentV2
export struct SystemPromptActions {
  @Event onReset: () => void = () => {}
  @Event onSave: () => void = () => {}

  build() {
    Row({ space: 12 }) {
      PromptEditorButton({
        label: $r('app.string.system_prompt_clear'),
        fillWidth: true,
        labelColor: $r('app.color.text_secondary'),
        onActivate: this.onReset
      })
        .layoutWeight(1)

      PromptEditorButton({
        label: $r('app.string.save'),
        fillWidth: true,
        materialStyle: WRAPPED_MATERIAL_THIN,
        materialColor: withColorAlpha(getAppUiState().themePrimary, '26'),
        onActivate: this.onSave
      })
        .layoutWeight(1)
    }
    .width('100%')
    .clip(false)
  }
}
