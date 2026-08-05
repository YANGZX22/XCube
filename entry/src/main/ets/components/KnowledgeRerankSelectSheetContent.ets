import { uiMaterial } from '@kit.ArkUI'
import { ModelProvider } from '../models/ChatModels'
import { KnowledgeRerankSelection } from '../services/KnowledgeRerankService'
import { getAppUiState } from '../state/AppUiState'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { ModelSelectorContent } from './ModelSelector'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'

const RERANK_OPTION_CORNER_RADIUS: number = 16

@ComponentV2
export struct KnowledgeRerankSelectSheetContent {
  @Param providers: ModelProvider[] = []
  @Param currentSelection: KnowledgeRerankSelection = KnowledgeRerankSelection.createDisabled()
  @Param isLoading: boolean = false
  @Param isApplying: boolean = false
  @Event onSelectNone: () => void = (): void => {}
  @Event onSelectApi: (providerId: string, modelId: string, modelName: string) => void =
    (_providerId: string, _modelId: string, _modelName: string): void => {}
  @Event onClose: () => void = (): void => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  @Builder
  private Header() {
    ImmersiveSheetHeader({
      title: pickLocalizedText('重排序模型', 'Rerank model'),
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

      Text(this.currentSelection.isEnabled()
        ? this.currentSelection.displayName()
        : pickLocalizedText('不使用重排序', 'Rerank disabled'))
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
  private DisabledOptionRow() {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.ranking'))
          .fontSize(20)
          .fontColor([this.currentSelection.isEnabled()
            ? this.themePrimary
            : Color.White])
      }
      .width(36)
      .height(36)
      .borderRadius(10)
      .backgroundColor(this.currentSelection.isEnabled()
        ? withColorAlpha(this.themePrimary, this.isDarkMode ? '2E' : '16')
        : '#24FFFFFF')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 3 }) {
        Text(pickLocalizedText('不使用重排序', 'No reranking'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.currentSelection.isEnabled() ? $r('app.color.text_primary') : Color.White)

        Text(pickLocalizedText(
          '按关键词与向量的融合排名返回，不额外调用模型',
          'Return results by keyword/vector fusion rank without extra model calls'
        ))
          .fontSize(11)
          .fontColor(this.currentSelection.isEnabled()
            ? $r('app.color.text_secondary')
            : Color.White)
          .opacity(this.currentSelection.isEnabled() ? 1 : 0.82)
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })

      if (!this.currentSelection.isEnabled()) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(20)
          .fontColor([Color.White])
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 12, right: 12, top: 11, bottom: 11 })
    .borderRadius(RERANK_OPTION_CORNER_RADIUS)
    .clip(true)
    .backgroundColor(this.currentSelection.isEnabled() ? Color.Transparent : this.themePrimary)
    .border({
      width: !this.currentSelection.isEnabled() ? 1 : 0.5,
      color: !this.currentSelection.isEnabled() ? this.themePrimary : getAppUiState().themePrimaryLight
    })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: this.currentSelection.isEnabled() ? Color.Transparent : this.themePrimary,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .hitTestBehavior(this.isApplying ? HitTestMode.None : HitTestMode.Block)
    .opacity(this.isApplying ? 0.55 : 1)
    .onClick(() => {
      if (!this.isApplying) {
        this.onSelectNone()
      }
    })
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
    Row() {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(16)
        .fontColor([this.themePrimary])

      Text(pickLocalizedText(
        '重排序会在每次知识库检索后，把 query 和召回片段发送给所选服务商重新打分，可能产生费用。切换模型无需重建向量，立即生效；调用失败时自动保留原有融合排序。',
        'Reranking sends the query and retrieved chunks to the selected provider for rescoring after each knowledge search, and charges may apply. Switching takes effect immediately without rebuilding vectors, and falls back to the original fusion order if the call fails.'
      ))
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
        .margin({ left: 8 })
    }
    .width('100%')
    .padding(12)
    .borderRadius(RERANK_OPTION_CORNER_RADIUS)
    .backgroundColor(Color.Transparent)
    .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: Color.Transparent,
      applyShadow: false
    }))
    .alignItems(VerticalAlign.Top)
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
        '请先在设置中启用 OpenAI 兼容服务商并添加 Rerank 模型。',
        'Enable an OpenAI-compatible provider and add a rerank model in Settings first.'
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
    Column({ space: 12 }) {
      LoadingProgress()
        .width(34)
        .height(34)
        .color(this.themePrimary)

      Text(pickLocalizedText(
        '正在校验重排序模型...',
        'Validating the rerank model...'
      ))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
    }
    .width(240)
    .padding({ left: 20, right: 20, top: 22, bottom: 22 })
    .borderRadius(18)
    .backgroundColor(Color.Transparent)
    .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      applyShadow: true
    }))
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        this.Header()
        this.CurrentSelectionRow()

        Column({ space: 10 }) {
          this.DisabledOptionRow()
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
            currentModelId: this.currentSelection.isEnabled() ? this.currentSelection.modelId : '',
            currentProviderId: this.currentSelection.isEnabled() ? this.currentSelection.providerId : '',
            showEditEntry: false,
            showFavoriteActions: false,
            showFavoriteFilter: false,
            searchPlaceholder: pickLocalizedText('搜索 Rerank 模型', 'Search rerank models'),
            includeModelIdInSearch: true,
            emptyStateMode: 'default',
            immersiveMaterial: true,
            narrowSearchBar: true,
            showImmersiveGroupBorder: true,
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
