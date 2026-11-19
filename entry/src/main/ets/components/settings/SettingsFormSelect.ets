import { getSettingsTypography, SETTINGS_HEADING_CONTENT_GAP } from './SettingsTypography'
import { uiMaterial } from '@kit.ArkUI'
import { getAppUiState } from '../../state/AppUiState'
import { shouldUseWrappedMaterial, WrappedMaterialModifier } from '../../utils/WrappedMaterialSupport'

export const SETTINGS_FORM_VALUE_FONT_SIZE: number = 13

@ComponentV2
export struct SettingsFormSelect {
  @Require @Param label: ResourceStr
  @Require @Param options: SelectOption[]
  @Require @Param selectedIndex: number
  @Param displayValue: ResourceStr | undefined = undefined
  @Event onSelect: (index: number, value: string) => void = (_index: number, _value: string): void => {}

  build() {
    Column({ space: SETTINGS_HEADING_CONTENT_GAP }) {
      Text(this.label)
        .font(getSettingsTypography().fieldLabel)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Select(this.options)
        .selected(this.selectedIndex)
        .value(this.displayValue ?? this.options[this.selectedIndex]?.value ?? '')
        .onSelect((index: number, value: string): void => this.onSelect(index, value))
        .font({ size: SETTINGS_FORM_VALUE_FONT_SIZE })
        .optionFont({ size: SETTINGS_FORM_VALUE_FONT_SIZE })
        .selectedOptionFont({ size: SETTINGS_FORM_VALUE_FONT_SIZE })
        .fontColor($r('app.color.text_primary'))
        .selectedOptionFontColor(getAppUiState().themePrimary)
        .width('100%')
        .height(40)
        .align(Alignment.Start)
        .menuAlign(MenuAlignType.START)
        .backgroundColor(Color.Transparent)
        .borderRadius(10)
        .attributeModifier(new WrappedMaterialModifier(() => new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: Color.Transparent,
          applyShadow: false
        }), shouldUseWrappedMaterial(), true))
        .menuSystemMaterial(shouldUseWrappedMaterial() ? new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THICK
        }) : undefined)
        .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
