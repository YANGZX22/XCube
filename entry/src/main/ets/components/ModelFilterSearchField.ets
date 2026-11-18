import { ImmersiveFieldSurface } from './ImmersiveFieldSurface'

export const MODEL_FILTER_SEARCH_HEIGHT: number = 40
export const MODEL_FILTER_SEARCH_RADIUS: number = 20
export const MODEL_FILTER_SEARCH_HORIZONTAL_INSET: number = 16

// 模型选择、模型导入及服务商模型列表共用尺寸；附加筛选按钮不改变搜索条外框。
@ComponentV2
export struct ModelFilterSearchField {
  @Param value: string = ''
  @Param placeholder: ResourceStr = $r('app.string.filter_models_placeholder')
  @Event onChange: (value: string) => void = (_value: string): void => {}
  @BuilderParam trailingContent: () => void = this.EmptyTrailingContent

  @Builder
  private EmptyTrailingContent() {}

  build() {
    Row() {
      ImmersiveFieldSurface({ cornerRadius: MODEL_FILTER_SEARCH_RADIUS }) {
        Row() {
          Search({ value: this.value, placeholder: this.placeholder })
            .layoutWeight(1)
            .height(MODEL_FILTER_SEARCH_HEIGHT)
            .backgroundColor(Color.Transparent)
            .borderRadius(MODEL_FILTER_SEARCH_RADIUS)
            .padding({ left: 12, right: 12 })
            .onChange((value: string): void => {
              this.onChange(value)
            })

          this.trailingContent()
        }
        .width('100%')
        .height(MODEL_FILTER_SEARCH_HEIGHT)
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({
      left: MODEL_FILTER_SEARCH_HORIZONTAL_INSET,
      right: MODEL_FILTER_SEARCH_HORIZONTAL_INSET,
      top: 6,
      bottom: 6
    })
  }
}
