/**
 * 模型编辑半模态组件
 * 单页滚动布局：核心信息 → 能力标签 → 可折叠高级参数
 */
import { ModelInfo, InputMode, OutputMode, ModelInfoExtendedJson } from '../models/ChatModels'
import { LengthMetrics, uiMaterial } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'

@ComponentV2
struct ModelCapabilityButton {
  @Param icon: Resource = $r('sys.symbol.checkmark_circle')
  @Param label: string = ''
  @Param selected: boolean = false
  @Event onTap: () => void = () => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  build() {
    Button({ type: ButtonType.Capsule, stateEffect: false }) {
      Row({ space: 6 }) {
        SymbolGlyph(this.icon)
          .fontSize(16)
          .fontColor([this.selected ? this.themePrimary : $r('app.color.text_primary')])

        Text(this.label)
          .fontSize(13)
          .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.selected ? this.themePrimary : $r('app.color.text_primary'))
      }
      .alignItems(VerticalAlign.Center)
    }
    .height(36)
    .padding({ left: 12, right: 14 })
    .backgroundColor(Color.Transparent)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .border({
      width: this.selected ? 1.2 : 0.5,
      color: this.selected ? this.themePrimary : $r('app.color.divider')
    })
    .onClick(() => {
      this.onTap()
    })
  }
}

@ComponentV2
export struct ModelEditSheet {
  @Param model: ModelInfo = new ModelInfo('', '')
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  @Local tempName: string = ''
  // 能力开关状态（用于触发 UI 刷新）
  @Local capSupportsTools: boolean = false
  @Local capSupportsReasoning: boolean = false
  @Local capSupportsWebSearch: boolean = false
  @Local capSupportsVision: boolean = false
  @Local capSupportsDocuments: boolean = false
  @Local capSupportsStreaming: boolean = false
  @Local capOutputImage: boolean = false
  @Local reasoningStrategyOverride: string = ''
  // 高级参数折叠状态
  @Local isAdvancedExpanded: boolean = false
  // 高级参数本地状态（驱动 Slider 实时刷新）
  @Local paramTemperature: number = 0.7
  @Local paramTopP: number = 1.0
  @Local paramPresencePenalty: number = 0
  @Local paramFrequencyPenalty: number = 0
  // 回调函数
  @Event onSave: (draft: ModelInfoExtendedJson) => Promise<void> = async (_draft: ModelInfoExtendedJson): Promise<void> => {
  }
  @Event onCancel: () => void = () => {
  }
  @Event onAdvancedExpandedChange: (expanded: boolean) => void = (_expanded: boolean): void => {
  }

  aboutToAppear(): void {
    this.syncDraftFromModel()
  }

  private syncDraftFromModel(): void {
    this.tempName = this.model.name
    this.capSupportsTools = this.model.capabilities.supportsTools
    this.capSupportsReasoning = this.model.capabilities.supportsReasoning
    this.capSupportsWebSearch = this.model.capabilities.supportsWebSearch
    this.capSupportsVision = this.model.capabilities.supportsVision
    this.capSupportsDocuments = this.model.capabilities.supportsDocuments
    this.capSupportsStreaming = this.model.capabilities.supportsStreaming
    this.capOutputImage = this.model.outputMode === OutputMode.IMAGE
    this.reasoningStrategyOverride = this.model.reasoningStrategyOverride
    this.paramTemperature = this.model.parameters.temperature
    this.paramTopP = this.model.parameters.topP
    this.paramPresencePenalty = this.model.parameters.presencePenalty
    this.paramFrequencyPenalty = this.model.parameters.frequencyPenalty
  }

  private buildDraft(): ModelInfoExtendedJson {
    return {
      id: this.model.id,
      name: this.tempName,
      contextLength: this.model.contextLength,
      isEnabled: this.model.isEnabled,
      isRecommended: this.model.isRecommended,
      modelType: this.model.modelType,
      inputMode: this.capSupportsVision ? InputMode.VISION : InputMode.TEXT,
      outputMode: this.capOutputImage ? OutputMode.IMAGE : OutputMode.TEXT,
      capabilities: {
        supportsTools: this.capSupportsTools,
        supportsReasoning: this.capSupportsReasoning,
        supportsWebSearch: this.capSupportsWebSearch,
        supportsVision: this.capSupportsVision,
        supportsDocuments: this.capSupportsDocuments,
        supportsStreaming: this.capSupportsStreaming
      },
      reasoningStrategyOverride: this.reasoningStrategyOverride,
      parameters: {
        temperature: this.paramTemperature,
        topP: this.paramTopP,
        maxTokens: this.model.parameters.maxTokens,
        presencePenalty: this.paramPresencePenalty,
        frequencyPenalty: this.paramFrequencyPenalty
      }
    }
  }

  build() {
    Column() {
      this.HeaderBar()

      Divider()
        .color($r('app.color.divider'))
        .margin({ left: 20, right: 20 })

      Scroll() {
        Column() {
          // 核心信息区
          this.ModelIdSection()

          Divider()
            .color($r('app.color.divider'))
            .margin({ left: 16, right: 16 })

          this.ModelNameSection()

          Divider()
            .color($r('app.color.divider'))
            .margin({ left: 16, right: 16 })

          // 能力标签区
          this.CapabilityChipsSection()

          Divider()
            .color($r('app.color.divider'))
            .margin({ left: 16, right: 16 })

          // 可折叠高级参数区
          this.AdvancedParametersSection()
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 34 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(this.isAdvancedExpanded ? 1 : 0)
    }
    .width('100%')
    .height(this.isAdvancedExpanded ? '100%' : 'auto')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  HeaderBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([$r('app.color.text_primary')])
      }
      .type(ButtonType.Circle)
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true,
        lightEffect: { color: undefined }
      }))
      .onClick(() => {
        this.onCancel()
      })

      Text('编辑模型')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Button() {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([this.themePrimary])
      }
      .type(ButtonType.Circle)
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true,
        lightEffect: { color: undefined }
      }))
      .onClick(async () => {
        await this.onSave(this.buildDraft())
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 20, right: 20 })
  }

  @Builder
  ModelIdSection() {
    Row() {
      Column() {
        Text('模型 ID')
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 4 })

        Text(this.model.id)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button() {
        SymbolGlyph($r('sys.symbol.rectangle_on_rectangle'))
          .fontSize(16)
          .fontColor([$r('app.color.text_primary')])
      }
      .type(ButtonType.Circle)
      .width(32)
      .height(32)
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  ModelNameSection() {
    Column() {
      Text('模型名称')
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 })

      TextInput({ text: this.tempName, placeholder: '输入模型显示名称' })
        .width('100%')
        .height(44)
        .backgroundColor(Color.Transparent)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .borderRadius(12)
        .border({ width: 0.5, color: $r('app.color.divider') })
        .clip(true)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.tempName = value
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  CapabilityChipsSection() {
    Column() {
      Text('模型能力')
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 12 })

      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ModelCapabilityButton({
          icon: $r('sys.symbol.wrench_and_screwdriver'),
          label: '工具调用',
          selected: this.capSupportsTools,
          onTap: (): void => {
            this.capSupportsTools = !this.capSupportsTools
          }
        })
        ModelCapabilityButton({
          icon: $r('sys.symbol.AI_deep_thinking'),
          label: '推理',
          selected: this.capSupportsReasoning,
          onTap: (): void => {
            this.capSupportsReasoning = !this.capSupportsReasoning
          }
        })
        ModelCapabilityButton({
          icon: $r('sys.symbol.ohos_wifi'),
          label: '联网搜索',
          selected: this.capSupportsWebSearch,
          onTap: (): void => {
            this.capSupportsWebSearch = !this.capSupportsWebSearch
          }
        })
        ModelCapabilityButton({
          icon: $r('sys.symbol.pdf_doc'),
          label: '文档阅读',
          selected: this.capSupportsDocuments,
          onTap: (): void => {
            this.capSupportsDocuments = !this.capSupportsDocuments
          }
        })
        ModelCapabilityButton({
          icon: $r('sys.symbol.ohos_photo'),
          label: '视觉理解',
          selected: this.capSupportsVision,
          onTap: (): void => {
            this.capSupportsVision = !this.capSupportsVision
          }
        })
        ModelCapabilityButton({
          icon: $r('sys.symbol.picture'),
          label: '图片生成',
          selected: this.capOutputImage,
          onTap: (): void => {
            this.capOutputImage = !this.capOutputImage
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  AdvancedParametersSection() {
    Column() {
      // 折叠标题行
      Row() {
        Text('高级参数')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.text_tertiary')])
          .rotate({ angle: this.isAdvancedExpanded ? 90 : 0 })
          .animation({ duration: 200, curve: Curve.EaseOut })
      }
      .width('100%')
      .height(48)
      .onClick(() => {
        const expanded = !this.isAdvancedExpanded
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
          this.isAdvancedExpanded = expanded
          this.onAdvancedExpandedChange(expanded)
        })
      })

      // 展开内容
      if (this.isAdvancedExpanded) {
        Divider()
          .color($r('app.color.divider'))

        Column() {
          // 温度
          Column() {
            Row() {
              Column() {
                Text('温度 (Temperature)')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('控制输出的随机性，值越高越有创意')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.paramTemperature.toFixed(2))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
                .width(50)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Slider({
              value: this.paramTemperature,
              min: 0,
              max: 2,
              step: 0.1,
              style: SliderStyle.InSet
            })
              .systemMaterial(new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
                materialColor: this.themePrimary,
                interactive: true,
                lightEffect: { color: undefined }
              }))
              .selectedColor(this.themePrimaryLight)
              .trackColor(Color.White)
              .blockColor(this.themePrimary)
              .blockBorderColor(this.themePrimary)
              .blockBorderWidth(1)
              .showSteps(false)
              .showTips(false)
              .margin({ top: 8 })
              .onChange((v: number) => {
                this.paramTemperature = v
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })

          Divider()
            .color($r('app.color.divider'))

          // Top P
          Column() {
            Row() {
              Column() {
                Text('Top P')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('核采样参数，控制词汇选择范围')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.paramTopP.toFixed(2))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
                .width(50)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Slider({
              value: this.paramTopP,
              min: 0,
              max: 1,
              step: 0.05,
              style: SliderStyle.InSet
            })
              .systemMaterial(new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
                materialColor: this.themePrimary,
                interactive: true,
                lightEffect: { color: undefined }
              }))
              .selectedColor(this.themePrimaryLight)
              .trackColor(Color.White)
              .blockColor(this.themePrimary)
              .blockBorderColor(this.themePrimary)
              .blockBorderWidth(1)
              .showSteps(false)
              .showTips(false)
              .margin({ top: 8 })
              .onChange((v: number) => {
                this.paramTopP = v
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })

          Divider()
            .color($r('app.color.divider'))

          // 存在惩罚
          Column() {
            Row() {
              Column() {
                Text('存在惩罚 (Presence Penalty)')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('减少重复话题的出现')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.paramPresencePenalty.toFixed(2))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
                .width(50)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Slider({
              value: this.paramPresencePenalty,
              min: -2,
              max: 2,
              step: 0.1,
              style: SliderStyle.InSet
            })
              .systemMaterial(new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
                materialColor: this.themePrimary,
                interactive: true,
                lightEffect: { color: undefined }
              }))
              .selectedColor(this.themePrimaryLight)
              .trackColor(Color.White)
              .blockColor(this.themePrimary)
              .blockBorderColor(this.themePrimary)
              .blockBorderWidth(1)
              .showSteps(false)
              .showTips(false)
              .margin({ top: 8 })
              .onChange((v: number) => {
                this.paramPresencePenalty = v
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })

          Divider()
            .color($r('app.color.divider'))

          // 频率惩罚
          Column() {
            Row() {
              Column() {
                Text('频率惩罚 (Frequency Penalty)')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('减少重复词汇的出现')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.paramFrequencyPenalty.toFixed(2))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
                .width(50)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Slider({
              value: this.paramFrequencyPenalty,
              min: -2,
              max: 2,
              step: 0.1,
              style: SliderStyle.InSet
            })
              .systemMaterial(new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
                materialColor: this.themePrimary,
                interactive: true,
                lightEffect: { color: undefined }
              }))
              .selectedColor(this.themePrimaryLight)
              .trackColor(Color.White)
              .blockColor(this.themePrimary)
              .blockBorderColor(this.themePrimary)
              .blockBorderWidth(1)
              .showSteps(false)
              .showTips(false)
              .margin({ top: 8 })
              .onChange((v: number) => {
                this.paramFrequencyPenalty = v
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })

          Divider()
            .color($r('app.color.divider'))

          // 重置按钮
          Button('重置为默认值')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor(Color.Transparent)
            .borderRadius(12)
            .border({ width: 0.5, color: $r('app.color.divider') })
            .height(44)
            .width('100%')
            .margin({ top: 12 })
            .onClick(() => {
              this.paramTemperature = 0.7
              this.paramTopP = 1.0
              this.paramPresencePenalty = 0
              this.paramFrequencyPenalty = 0
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 0,
      bottom: 16
    })
    .backgroundColor(Color.Transparent)
  }
}
