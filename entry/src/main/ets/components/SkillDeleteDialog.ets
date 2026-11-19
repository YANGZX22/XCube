import { UIContext } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'
import { getPopupMaterial, shouldUseWrappedMaterial } from '../utils/WrappedMaterialSupport'
import { SettingsActionButton } from './settings/SettingsActionButton'
import { getSettingsTypography } from './settings/SettingsTypography'

export function openSkillDeleteDialog(context: UIContext, builder: (dialogId: number) => void): void {
  context.getPromptAction().presentCustomDialog(builder, undefined, {
    alignment: DialogAlignment.Center,
    autoCancel: true,
    cornerRadius: 24,
    backgroundColor: Color.Transparent,
    backgroundBlurStyle: shouldUseWrappedMaterial() ? BlurStyle.NONE : BlurStyle.COMPONENT_THICK,
    systemMaterial: getPopupMaterial()
  }).catch((error: Error): void => {
    console.error('SkillDeleteDialog', error.message)
  })
}

@ComponentV2
export struct SkillDeleteDialog {
  @Require @Param dialogId: number
  @Require @Param title: string
  @Require @Param message: string
  @Event onDelete: () => void = (): void => {}
  private dismissed: boolean = false

  private dismiss(confirmed: boolean): void {
    if (this.dismissed) return
    this.dismissed = true
    this.getUIContext().getPromptAction().closeCustomDialog(this.dialogId)
    if (confirmed) this.onDelete()
  }

  build() {
    Column({ space: 16 }) {
      Text(this.title)
        .font(getSettingsTypography().pageTitle)
        .fontColor(getAppUiState().themeTextPrimary)
        .textAlign(TextAlign.Center)
      Text(this.message)
        .fontSize(14)
        .fontColor($r('app.color.text_caption'))
        .width('100%')
      Row({ space: 12 }) {
        SettingsActionButton({
          label: $r('app.string.cancel'),
          onActivate: (): void => this.dismiss(false)
        }).layoutWeight(1)
        SettingsActionButton({
          label: $r('app.string.delete'),
          foreground: $r('app.color.status_error'),
          onActivate: (): void => this.dismiss(true)
        }).layoutWeight(1)
      }.width('100%')
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Center)
  }
}
