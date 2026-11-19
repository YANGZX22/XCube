import { getSettingsTypography } from '../settings/SettingsTypography'
import { ModelProvider } from '../../models/ChatModels'
import { ModelSelectorContent } from '../ModelSelector'
import { getAppUiState } from '../../state/AppUiState'
import { ImmersiveSheetHeader } from '../ImmersiveSheetHeader'

@ComponentV2
export struct DefaultModelSelectSheetContent {
  @Param title: string | Resource = ''
  @Param currentSelectionText: string | Resource = ''
  @Param isProvidersLoaded: boolean = false
  @Param providers: ModelProvider[] = []
  @Param currentModelId: string = ''
  @Param currentProviderId: string = ''
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  @Event onSelectModel: (providerId: string, modelId: string, modelName: string) => void =
    (_providerId: string, _modelId: string, _modelName: string): void => {}
  @Event onClearSelection: () => void = (): void => {}
  @Event onClose: () => void = (): void => {}

  build() {
    Column() {
      ImmersiveSheetHeader({
        titleFont: getSettingsTypography().pageTitle,
        titleColor: getAppUiState().themeTextPrimary,
        title: this.title,
        materialFeedback: false,
        onLeadingClick: (): void => {
          this.onClose()
        }
      })

      Row() {
        Text($r('app.string.default_model_current_selection'))
          .font(getSettingsTypography().fieldLabel)
          .fontColor($r('app.color.text_secondary'))

        Text(this.currentSelectionText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_caption'))
          .constraintSize({ maxWidth: '60%' })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ left: 16, right: 16, top: 8, bottom: 12 })

      if (!this.isProvidersLoaded) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.themePrimary)
          Text($r('app.string.loading'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        ModelSelectorContent({
          providers: this.providers,
          currentModelId: this.currentModelId,
          currentProviderId: this.currentProviderId,
          showEditEntry: false,
          showFavoriteActions: false,
          showFavoriteFilter: false,
          showClearSelectionOption: true,
          clearSelectionText: $r('app.string.default_model_clear_selection'),
          searchPlaceholder: $r('app.string.filter_models_placeholder'),
          includeModelIdInSearch: true,
          emptyStateMode: 'default',
          immersiveMaterial: true,
          onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
            this.onSelectModel(providerId, modelId, modelName)
          },
          onClearSelection: () => {
            this.onClearSelection()
          }
        })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
