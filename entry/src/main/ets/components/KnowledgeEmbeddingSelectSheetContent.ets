import { ImmersiveListSurface, LIST_MATERIAL_CARD_RADIUS } from './ImmersiveListSurface'
import { deviceInfo } from '@kit.BasicServicesKit'
import { ModelProvider } from '../models/ChatModels'
import {
  KnowledgeEmbeddingSelection
} from '../services/KnowledgeEmbeddingService'
import { getAppUiState } from '../state/AppUiState'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { ModelSelectorContent } from './ModelSelector'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'

const EMBEDDING_OPTION_CORNER_RADIUS: number = 16

@ComponentV2
export struct KnowledgeEmbeddingSelectSheetContent {
  @Param providers: ModelProvider[] = []
  @Param currentSelection: KnowledgeEmbeddingSelection = KnowledgeEmbeddingSelection.createLocal()
  @Param isLoading: boolean = false
  @Param isApplying: boolean = false
  @Event onSelectLocal: () => void = (): void => {}
  @Event onSelectApi: (providerId: string, modelId: string, modelName: string) => void =
    (_providerId: string, _modelId: string, _modelName: string): void => {}
  @Event onClose: () => void = (): void => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get isLocalEmbeddingSupported(): boolean {
    return deviceInfo.deviceType === deviceInfo.DeviceTypes.TYPE_2IN1
  }

  @Builder
  private Header() {
    ImmersiveSheetHeader({
      title: pickLocalizedText('向量模型', 'Embedding model'),
      materialFeedback: false,
      leadingButtonEnabled: !this.isApplying,
      onLeadingClick: (): void => {
        this.onClose()
      }
    })
  }

  @Builder
  private CurrentSelectionRow() {
    Row({ space: 6 }) {
      Text(pickLocalizedText('当前选择', 'Current selection'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))

      Text(this.currentSelection.displayName())
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.themePrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '68%' })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: 2, bottom: 12 })
  }

  @Builder
  private LocalModelRow() {
    Stack() {
      ImmersiveListSurface({ isImmersive: true, cornerRadius: LIST_MATERIAL_CARD_RADIUS }) {
        Row() {
          Column() {
            SymbolGlyph($r('sys.symbol.square_stack_3d'))
              .fontSize(20)
              .fontColor([this.themePrimary])
          }
          .width(36)
          .height(36)
          .borderRadius(10)
          .backgroundColor($r('app.color.model_icon_bg'))
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          Column({ space: 3 }) {
            Text(pickLocalizedText('本地 ArkData', 'Local ArkData'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.currentSelection.isApi() ? $r('app.color.text_primary') : this.themePrimary)

            Text(pickLocalizedText(
              this.isLocalEmbeddingSupported
                ? '在设备侧生成向量，不上传文档片段'
                : 'ArkData 文本向量仅支持 PC/2in1；当前设备不可用。',
              this.isLocalEmbeddingSupported
                ? 'Generate vectors on device without uploading document chunks'
                : 'ArkData text embeddings require a 2-in-1 device; use an API here'
            ))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(2)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 10 })

          if (!this.currentSelection.isApi()) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(20)
              .fontColor([this.themePrimary])
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 12, right: 12, top: 11, bottom: 11 })
        .borderRadius(LIST_MATERIAL_CARD_RADIUS)
        .clip(true)
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(this.isApplying || !this.isLocalEmbeddingSupported
          ? HitTestMode.None
          : HitTestMode.Block)
        .onClick(() => {
          if (!this.isApplying && this.isLocalEmbeddingSupported) {
            this.onSelectLocal()
          }
        })
      }
    }
    .width('100%')
    .opacity(this.isApplying || !this.isLocalEmbeddingSupported ? 0.55 : 1)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private ProviderSectionDivider() {
    Row({ space: 10 }) {
      Divider()
        .layoutWeight(1)
        .strokeWidth(1.5)
        .color(this.themePrimary)

      Text(pickLocalizedText('服务商模型', 'Provider models'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.themePrimary)

      Divider()
        .layoutWeight(1)
        .strokeWidth(1.5)
        .color(this.themePrimary)
    }
    .width('100%')
    .padding({ top: 4, bottom: 2 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ApiNotice() {
    ImmersiveListSurface({ isImmersive: true, cornerRadius: LIST_MATERIAL_CARD_RADIUS }) {
      Row() {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(16)
          .fontColor([this.themePrimary])

        Text(pickLocalizedText(
          'API 模式会把文档片段发送给所选服务商并重新生成全部向量；实际检索 query 仅在模型调用知识库工具后发送，可能产生费用。',
          'API mode sends document chunks to the selected provider and rebuilds all vectors. Query text is sent only after the model calls the knowledge tool, and charges may apply.'
        ))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .margin({ left: 8 })
      }
      .width('100%')
      .padding(12)
      .borderRadius(LIST_MATERIAL_CARD_RADIUS)
      .backgroundColor(Color.Transparent)
      .alignItems(VerticalAlign.Top)
    }
  }

  @Builder
  private ApiEmptyState() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(32)
        .fontColor([$r('app.color.text_tertiary')])

      Text(pickLocalizedText('暂无可选 API 模型', 'No API models available'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))

      Text(pickLocalizedText(
        '请先在设置中启用 OpenAI 兼容服务商并添加模型。',
        'Enable an OpenAI-compatible provider and add a model in Settings first.'
      ))
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 32, right: 32 })
  }

  @Builder
  private ApplyingOverlay() {
    ImmersiveListSurface({ isImmersive: true, layoutWidth: 240, cornerRadius: LIST_MATERIAL_CARD_RADIUS }) {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(34)
          .height(34)
          .color(this.themePrimary)

        Text(pickLocalizedText(
          '正在检查并重建语义向量...',
          'Checking and rebuilding semantic vectors...'
        ))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)

        Text(pickLocalizedText(
          '重建期间关键词检索仍可使用',
          'Keyword retrieval remains available during the rebuild'
        ))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width(240)
      .padding({ left: 20, right: 20, top: 22, bottom: 22 })
      .borderRadius(LIST_MATERIAL_CARD_RADIUS)
      .backgroundColor(Color.Transparent)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        this.Header()
        this.CurrentSelectionRow()

        Column({ space: 10 }) {
          this.LocalModelRow()
          this.ProviderSectionDivider()
          this.ApiNotice()
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 6 })

        if (this.isLoading) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(30)
              .height(30)
              .color(this.themePrimary)

            Text(pickLocalizedText('正在加载模型...', 'Loading models...'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.providers.length === 0) {
          this.ApiEmptyState()
        } else {
          ModelSelectorContent({
            providers: this.providers,
            currentModelId: this.currentSelection.isApi() ? this.currentSelection.modelId : '',
            currentProviderId: this.currentSelection.isApi() ? this.currentSelection.providerId : '',
            showEditEntry: false,
            showFavoriteActions: false,
            showFavoriteFilter: false,
            searchPlaceholder: pickLocalizedText('搜索 API Embedding 模型', 'Search API embedding models'),
            includeModelIdInSearch: true,
            emptyStateMode: 'default',
            immersiveMaterial: true,
            onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
              if (!this.isApplying) {
                this.onSelectApi(providerId, modelId, modelName)
              }
            }
          })
          .layoutWeight(1)
          .enabled(!this.isApplying)
          .opacity(this.isApplying ? 0.45 : 1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)

      if (this.isApplying) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.isDarkMode ? '#52000000' : '#33000000')

        this.ApplyingOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
