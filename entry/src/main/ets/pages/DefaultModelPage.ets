import { SettingsSectionHeading } from '../components/settings/SettingsSectionHeading'
import { getSettingsTypography, SETTINGS_HEADING_CONTENT_GAP, SETTINGS_SUBTITLE_LINE_HEIGHT } from '../components/settings/SettingsTypography'
import { ImmersiveListSurface, LIST_MATERIAL_CARD_RADIUS } from '../components/ImmersiveListSurface'
import { ImmersiveFieldSurface } from '../components/ImmersiveFieldSurface'
import { ImmersiveButtonSurface } from '../components/ImmersiveButtonSurface'
import { ImmersiveSheetHeader } from '../components/ImmersiveSheetHeader'
import { LengthMetrics } from '@kit.ArkUI'
import { shouldUseDrawnNavigation } from '../utils/DrawnNavigationSupport'
// 默认模型配置页面
import { DefaultModelService } from '../services/DefaultModelService'
import { ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { DefaultModelConfig, ModelRole, ModelProvider } from '../models/ChatModels'
import { DefaultPrompts } from '../config/DefaultPrompts'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { DefaultModelSelectSheetContent } from '../components/defaultmodel/DefaultModelSelectSheetContent'
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { LayoutSizeClass } from '../config/LayoutProfile'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth, isSettingsPageExpandedLayout } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'
import { createStaticRegularMaterial, getStaticSheetMaterial, shouldUseWrappedMaterial } from '../utils/WrappedMaterialSupport'

let defaultModelPagePathStack: NavPathStack | null = null
const PROMPT_EDITOR_ID: string = 'default_model_prompt_editor'

@Extend(Button)
function promptCapsule() {
  .backgroundColor(Color.Transparent)
  .height(40)
  .padding({ left: 14, right: 14 })
  .focusOnTouch(false)
}

@Entry
@ComponentV2
struct DefaultModelPage {
  // 主题颜色
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }
  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }
  private get settingsDetailPresentationMode(): string {
    return getAppUiState().settingsDetailPresentationMode
  }
  private get materialType(): number {
    return getAppUiState().materialType
  }
  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }

  @Local chatModel: DefaultModelConfig = new DefaultModelConfig()
  @Local titleModel: DefaultModelConfig = new DefaultModelConfig()
  @Local searchOptimizationModel: DefaultModelConfig = new DefaultModelConfig()

  @Local providers: ModelProvider[] = []
  @Local isProvidersLoaded: boolean = false
  @Local showModelSheet: boolean = false
  @Local currentEditRole: ModelRole = ModelRole.CHAT
  @Local showPromptSheet: boolean = false
  @Local currentPrompt: string = ''
  private promptEditor: TextAreaController = new TextAreaController()
  private promptEditorFocused: boolean = false
  private promptSelection: TextRange | undefined = undefined
  private defaultModelService: DefaultModelService = ServiceRegistry.defaultModel()
  private providerViewModel: ProviderViewModel = ServiceRegistry.provider()
  private compactScroller: Scroller = new Scroller()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  private isExpandedLayout(): boolean {
    return isSettingsPageExpandedLayout(this.layoutSizeClass, this.settingsDetailPresentationMode, this.windowWidthVp,
      this.windowHeightVp)
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private handleBack(): void {
    if (defaultModelPagePathStack !== null && defaultModelPagePathStack.size() > 0) {
      defaultModelPagePathStack.pop()
    }
  }

  private getCompactContentTopPadding(): number {
    return getHdsTopNavigationContentTopPadding(this.px2vp(this.topAvoidHeight), this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp, this.windowHeightVp, (): void => this.CompactTitleStackBuilder(), [], this)
  }

  aboutToAppear(): void {
    this.loadConfig()
    this.loadProviders()
  }

  async loadConfig(): Promise<void> {
    await this.defaultModelService.loadConfig()
    this.chatModel = this.defaultModelService.getModel(ModelRole.CHAT)
    this.titleModel = this.defaultModelService.getModel(ModelRole.TITLE)
    this.searchOptimizationModel = this.defaultModelService.getModel(ModelRole.SEARCH_OPTIMIZATION)
  }

  async loadProviders(): Promise<void> {
    // 只加载启用的供应商（不包括禁用的）
    this.providers = await this.providerViewModel.loadProviders()
    this.isProvidersLoaded = true
    console.info(`[DefaultModelPage] Loaded ${this.providers.length} enabled providers`)
  }

  @Builder
  private PageContent() {
    Scroll(this.compactScroller) {
      Row() {
        Column() {
          Blank()
            .width('100%')
            .height(this.getCompactContentTopPadding())

          if (this.isExpandedLayout()) {
            this.ExpandedModelSections()
          } else {
            this.CompactModelSections()
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.settings_default_model'))
          .font(getSettingsTypography().pageTitle)
          .fontColor(getAppUiState().themeTextPrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .height(64)
      .padding({ left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(getAppUiState().themeBackground)
    .border({ width: { bottom: 1 }, color: getAppUiState().themePrimaryLight })
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.settings_default_model'),
      onBack: () => {
        this.handleBack()
      }
    })
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        HdsNavigation() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(getAppUiState().themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .titleMode(HdsNavigationTitleMode.MINI)
        .systemBarStyle(
          { statusBarContentColor: getHdsStatusBarContentColor() },
          { statusBarContentColor: getHdsStatusBarContentColor() }
        )
        .hideBackButton(shouldUseDrawnNavigation())
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      } else {
        HdsNavigation() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(getAppUiState().themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .titleMode(HdsNavigationTitleMode.MINI)
        .systemBarStyle(
          { statusBarContentColor: getHdsStatusBarContentColor() },
          { statusBarContentColor: getHdsStatusBarContentColor() }
        )
        .hideBackButton(shouldUseDrawnNavigation())
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      }

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showModelSheet, this.ModelSelectSheet(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          blurStyle: shouldUseWrappedMaterial() ? undefined : BlurStyle.Regular,
          systemMaterial: getStaticSheetMaterial(),
          preferType: SheetType.BOTTOM
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showPromptSheet, this.PromptEditSheet(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          blurStyle: shouldUseWrappedMaterial() ? undefined : BlurStyle.Regular,
          systemMaterial: getStaticSheetMaterial(),
          preferType: SheetType.BOTTOM,
          keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  @Builder
  CompactModelSections() {
    Column() {
      this.ChatModelSection()
      this.TitleModelSection()
      this.SearchOptimizationModelSection()
      Column().height(40)
    }
    .width('100%')
  }

  @Builder
  ExpandedModelSections() {
    Column({ space: 20 }) {
      Row({ space: 16 }) {
        Column() {
          this.ChatModelSection()
        }
        .layoutWeight(1)

        Column() {
          this.TitleModelSection()
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.SearchOptimizationModelSection()

      Column().height(40)
    }
    .width('100%')
  }

  @Builder
  ChatModelSection() {
    Column() {
      SettingsSectionHeading({ title: $r('app.string.default_model_section_chat'), topGap: 24 })
      ModelConfigCard({
        roleName: $r('app.string.default_model_role_chat'),
        description: $r('app.string.default_model_desc_chat'),
        showPromptEdit: false,
        isConfigured: this.chatModel.isConfigured(),
        displayName: this.chatModel.getDisplayName(),
        isDefaultPrompt: true,
        onCardClick: () => {
          this.showPromptSheet = false
          this.currentEditRole = ModelRole.CHAT
          this.showModelSheet = true
        },
        onPromptClick: () => {}
      })
    }
    .width('100%')
  }

  @Builder
  TitleModelSection() {
    Column() {
      SettingsSectionHeading({ title: $r('app.string.default_model_section_title_generation'), topGap: 24 })
      ModelConfigCard({
        roleName: $r('app.string.default_model_role_title_generation'),
        description: $r('app.string.default_model_desc_title_generation'),
        showPromptEdit: true,
        isConfigured: this.titleModel.isConfigured(),
        displayName: this.titleModel.getDisplayName(),
        isDefaultPrompt: this.defaultModelService.isDefaultTitlePrompt(),
        onCardClick: () => {
          this.showPromptSheet = false
          this.currentEditRole = ModelRole.TITLE
          this.showModelSheet = true
        },
        onPromptClick: () => {
          this.openPromptEditor()
        }
      })
    }
    .width('100%')
  }

  @Builder
  SearchOptimizationModelSection() {
    Column() {
      SettingsSectionHeading({ title: $r('app.string.search_optimization_model'), topGap: 24 })
      ModelConfigCard({
        roleName: $r('app.string.search_optimization_model'),
        description: $r('app.string.search_optimization_desc'),
        showPromptEdit: false,
        isConfigured: this.searchOptimizationModel.isConfigured(),
        displayName: this.searchOptimizationModel.getDisplayName(),
        isDefaultPrompt: true,
        onCardClick: () => {
          this.showPromptSheet = false
          this.currentEditRole = ModelRole.SEARCH_OPTIMIZATION
          this.showModelSheet = true
        },
        onPromptClick: () => {}
      })
    }
    .width('100%')
  }

  @Builder
  ModelSelectSheet() {
    DefaultModelSelectSheetContent({
      title: this.getSheetTitle(),
      currentSelectionText: this.getCurrentModelDisplayName(),
      isProvidersLoaded: this.isProvidersLoaded,
      providers: this.providers,
      currentModelId: this.currentModelConfig.modelId,
      currentProviderId: this.currentModelConfig.providerId,
      onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
        this.selectModel(providerId, modelId, modelName)
      },
      onClearSelection: () => {
        this.clearModelSelection()
      },
      onClose: () => {
        this.showModelSheet = false
      }
    })
  }

  @Builder
  private PromptVariableButton(label: Resource, token: string) {
    ImmersiveButtonSurface({ materialFactory: () => createStaticRegularMaterial() }) {
      Button({ type: ButtonType.Capsule, stateEffect: false }) {
        Row({ space: 6 }) {
          Text(label)
            .fontSize(14)
            .fontColor(this.themePrimary)
          Text(token)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .promptCapsule()
      .onClick(() => this.insertPromptVariable(token))
    }
  }

  @Builder
  PromptEditSheet() {
    Column() {
      ImmersiveSheetHeader({
        titleFont: getSettingsTypography().pageTitle,
        titleColor: getAppUiState().themeTextPrimary,
        title: $r('app.string.default_model_prompt_edit_title_title'),
        materialFeedback: false,
        showTrailing: true,
        trailingColor: this.themePrimary,
        onLeadingClick: (): void => { this.showPromptSheet = false },
        onTrailingClick: (): void => { this.savePrompt() }
      })

      Column() {
        Text($r('app.string.default_model_prompt_variables'))
          .font(getSettingsTypography().fieldLabel)
          .fontColor(getAppUiState().themeTextSecondary)
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
          this.PromptVariableButton($r('app.string.default_model_variable_content'), '{content}')
          this.PromptVariableButton($r('app.string.default_model_variable_locale'), '{locale}')
        }
        .width('100%')
        .margin({ top: SETTINGS_HEADING_CONTENT_GAP, bottom: 12 })

        ImmersiveFieldSurface({ cornerRadius: 16, fillHeight: true, layoutWeightValue: 1 }) {
          TextArea({ text: this.currentPrompt, controller: this.promptEditor })
            .id(PROMPT_EDITOR_ID)
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Transparent)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .padding(16)
            .borderRadius(16)
            .onChange((value: string) => { this.currentPrompt = value })
            .onFocus(() => { this.promptEditorFocused = true })
            .onBlur(() => { this.promptEditorFocused = false })
            .onTextSelectionChange((start: number, end: number) => {
              if (this.promptEditorFocused) {
                this.promptSelection = { start: start, end: end }
              }
            })
        }

        Row() {
          ImmersiveButtonSurface({ materialFactory: () => createStaticRegularMaterial() }) {
            Button($r('app.string.default_model_reset_prompt'), { type: ButtonType.Capsule, stateEffect: false })
              .promptCapsule()
              .fontSize(15)
              .fontColor(this.themePrimary)
              .onClick(() => { this.resetPrompt() })
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  private openPromptEditor(): void {
    this.showModelSheet = false
    this.currentPrompt = this.defaultModelService.getTitlePromptTemplate()
    this.promptSelection = undefined
    this.promptEditorFocused = false
    this.showPromptSheet = true
  }

  private insertPromptVariable(token: string): void {
    const selection = this.promptEditorFocused ? this.promptEditor.getSelection() : this.promptSelection
    this.getUIContext().getFocusController().requestFocus(PROMPT_EDITOR_ID)
    let offset: number | undefined = undefined
    if (selection?.start !== undefined && selection.end !== undefined && selection.start >= 0 && selection.end >= 0) {
      offset = Math.min(selection.start, selection.end)
      const end = Math.max(selection.start, selection.end)
      if (end > offset) {
        this.promptEditor.deleteText({ start: offset, end: end })
      }
    }
    const caret = this.promptEditor.addText(token, offset === undefined ? undefined : { offset: offset })
    this.promptSelection = { start: caret, end: caret }
  }

  private getSheetTitle(): Resource {
    if (this.currentEditRole === ModelRole.CHAT) {
      return $r('app.string.default_model_select_chat_model')
    } else if (this.currentEditRole === ModelRole.TITLE) {
      return $r('app.string.default_model_select_title_model')
    }
    return $r('app.string.default_model_select_search_model')
  }

  // 获取当前选择的模型显示名称
  private getCurrentModelDisplayName(): string | Resource {
    const config = this.currentModelConfig

    if (config.isConfigured()) {
      return config.getDisplayName()
    }
    return $r('app.string.default_model_unconfigured')
  }

  private get currentModelConfig(): DefaultModelConfig {
    if (this.currentEditRole === ModelRole.CHAT) {
      return this.chatModel
    }
    if (this.currentEditRole === ModelRole.TITLE) {
      return this.titleModel
    }
    return this.searchOptimizationModel
  }

  private getProviderNameById(providerId: string): string {
    for (let i = 0; i < this.providers.length; i++) {
      if (this.providers[i].id === providerId) {
        return this.providers[i].name
      }
    }
    return ''
  }

  private async selectModel(providerId: string, modelId: string, modelName: string): Promise<void> {
    console.info(`[DefaultModelPage] Selecting model: ${modelId} from provider: ${providerId} for role: ${this.currentEditRole}`)
    const resolvedModelName = modelName !== '' ? modelName : modelId
    const providerName = this.getProviderNameById(providerId)
    const config = new DefaultModelConfig(modelId, providerId, resolvedModelName, providerName)
    await this.defaultModelService.setModel(this.currentEditRole, config)
    console.info(`[DefaultModelPage] Model saved, updating UI...`)

    // 立即更新状态变量
    if (this.currentEditRole === ModelRole.CHAT) {
      this.chatModel = new DefaultModelConfig(config.modelId, config.providerId, config.modelName, config.providerName)
    } else if (this.currentEditRole === ModelRole.TITLE) {
      this.titleModel = new DefaultModelConfig(config.modelId, config.providerId, config.modelName, config.providerName)
    } else {
      this.searchOptimizationModel = new DefaultModelConfig(config.modelId, config.providerId, config.modelName, config.providerName)
    }

    // 关闭 sheet
    this.showModelSheet = false
    console.info(`[DefaultModelPage] Model selection complete`)
  }

  private async clearModelSelection(): Promise<void> {
    console.info(`[DefaultModelPage] Clearing model selection for role: ${this.currentEditRole}`)
    const config = new DefaultModelConfig()
    await this.defaultModelService.setModel(this.currentEditRole, config)

    // 立即更新状态变量
    if (this.currentEditRole === ModelRole.CHAT) {
      this.chatModel = new DefaultModelConfig()
    } else if (this.currentEditRole === ModelRole.TITLE) {
      this.titleModel = new DefaultModelConfig()
    } else {
      this.searchOptimizationModel = new DefaultModelConfig()
    }

    // 关闭 sheet
    this.showModelSheet = false
  }

  private async resetPrompt(): Promise<void> {
    await this.defaultModelService.resetTitlePrompt()
    this.currentPrompt = DefaultPrompts.TITLE_PROMPT
  }

  private async savePrompt(): Promise<void> {
    await this.defaultModelService.setTitlePromptTemplate(this.currentPrompt)
    this.showPromptSheet = false
  }

}

// 独立的模型配置卡片组件，解决 @Builder 响应式问题
@ComponentV2
struct ModelConfigCard {
  @Param roleName: string | Resource = ''
  @Param description: string | Resource = ''
  @Param showPromptEdit: boolean = false
  @Param isDefaultPrompt: boolean = true

  // 使用基本类型避免对象响应式问题
  @Param isConfigured: boolean = false
  @Param displayName: string = ''

  @Event onCardClick: () => void = () => {}
  @Event onPromptClick: () => void = () => {}

  build() {
    ImmersiveListSurface({ isImmersive: true, cornerRadius: LIST_MATERIAL_CARD_RADIUS }) {
      Column() {
        Row() {
          Column() {
            Row() {
              Text(this.roleName)
                .font(getSettingsTypography().itemTitle)
                .fontColor(getAppUiState().themeTextPrimary)

              if (this.isConfigured) {
                Text(this.displayName)
                  .fontSize(13)
                  .fontColor($r('app.color.text_caption'))
                  .margin({ left: 8 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              } else {
                Text($r('app.string.default_model_unconfigured'))
                  .fontSize(13)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ left: 8 })
              }
            }
            .width('100%')

            Text(this.description)
              .font(getSettingsTypography().subtitle)
              .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
              .fontColor($r('app.color.text_caption'))
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(18)
            .fontColor([$r('app.color.text_tertiary')])
        }
        .width('100%')
        .padding(16)
        .onClick(() => {
          this.onCardClick()
        })

        if (this.showPromptEdit) {
          Divider().color(getAppUiState().themePrimaryLight).margin({ left: 16 })

          Row() {
            Text($r('app.string.default_model_prompt_template'))
              .font(getSettingsTypography().itemTitle)
              .fontColor(getAppUiState().themeTextPrimary)

            Blank()

            Text(this.isDefaultPrompt ?
              $r('app.string.default_model_prompt_template_default') :
              $r('app.string.default_model_prompt_template_custom'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))

            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(16)
              .fontColor([$r('app.color.text_tertiary')])
              .margin({ left: 8 })
          }
          .width('100%')
          .padding(16)
          .onClick(() => {
            this.onPromptClick()
          })
        }
      }
      .width('100%')
      .backgroundColor(Color.Transparent)
      .borderRadius(LIST_MATERIAL_CARD_RADIUS)
    }
  }
}

@Builder
export function DefaultModelPageBuilder(name: string, param: Object) {
  NavDestination() {
    DefaultModelPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    defaultModelPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (defaultModelPagePathStack !== null && defaultModelPagePathStack.size() > 0) {
      defaultModelPagePathStack.pop()
    }
    return true
  })
}
