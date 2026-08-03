import { ModelProvider, ModelInfo, ModelInfoExtendedJson } from '../../models/ChatModels'
import { ModelSelectorContent } from '../ModelSelector'
import { ModelEditSheet } from '../ModelEditSheet'
import { ImmersiveSheetHeader } from '../ImmersiveSheetHeader'

@ComponentV2
export struct ChatModelSelectorSheetContent {
  @Param providers: ModelProvider[] = []
  @Param currentModelId: string = ''
  @Param currentProviderId: string = ''
  @Param activePanel: string = 'selector'
  @Param editingModel: ModelInfo | null = null
  @Event $editingModel: (value: ModelInfo | null) => void = (_value: ModelInfo | null) => {}
  @Event onSelectModel: (providerId: string, modelId: string, modelName: string) => void =
    (_providerId: string, _modelId: string, _modelName: string): void => {}
  @Event onStartEdit: (model: ModelInfo, provider: ModelProvider) => void =
    (_model: ModelInfo, _provider: ModelProvider): void => {}
  @Event onSaveEdit: (draft: ModelInfoExtendedJson) => Promise<void> =
    async (_draft: ModelInfoExtendedJson): Promise<void> => {}
  @Event onCancelEdit: () => void = (): void => {}
  @Event onEditAdvancedExpandedChange: (expanded: boolean) => void =
    (_expanded: boolean): void => {}
  @Event onClose: () => void = (): void => {}

  @Builder
  private ModelEditSheetBuilder() {
    if (this.editingModel !== null) {
      ModelEditSheet({
        model: this.editingModel,
        onSave: (draft: ModelInfoExtendedJson) => {
          return this.onSaveEdit(draft)
        },
        onCancel: () => {
          this.onCancelEdit()
        },
        onAdvancedExpandedChange: (expanded: boolean): void => {
          this.onEditAdvancedExpandedChange(expanded)
        }
      })
    }
  }

  build() {
    if (this.activePanel === 'selector') {
      Column() {
        ImmersiveSheetHeader({
          title: $r('app.string.select_model'),
          onLeadingClick: (): void => {
            this.onClose()
          }
        })

        ModelSelectorContent({
          providers: this.providers,
          currentModelId: this.currentModelId,
          currentProviderId: this.currentProviderId,
          immersiveMaterial: true,
          onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
            this.onSelectModel(providerId, modelId, modelName)
          },
          onLongPressModel: (model: ModelInfo, provider: ModelProvider): void => {
            this.onStartEdit(model, provider)
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
    } else {
      // 编辑页直接作为 Sheet 内容，避免无高度的中间容器截断内部 Scroll。
      this.ModelEditSheetBuilder()
    }
  }
}
