import { curves, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI'
import { ConfigurationConstant, common } from '@kit.AbilityKit'
import { notificationManager } from '@kit.NotificationKit'
import { motion } from '@kit.MultimodalAwarenessKit'
import { BusinessError } from '@kit.BasicServicesKit'
import abilityAccessCtrl, { Permissions, PermissionRequestResult } from '@ohos.abilityAccessCtrl'
import {
  HdsNavigation,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode,
  HdsTabs,
  hdsMaterial
} from '@kit.UIDesignKit'
import {
  ApiStyle,
  ChatSession,
  ChatMessage,
  ModelInfo,
  ModelProvider,
  ModelType,
  ProviderType
} from '../models/ChatModels'
import { Assistant, DEFAULT_ASSISTANT_ID } from '../models/AssistantModels'
import { ChatViewModel } from '../viewmodels/ChatViewModel'
import { SettingsChangeCallback } from '../viewmodels/SettingsManager'
import { ThemeMode, AppLanguage, PreferenceKeys } from '../services/PreferencesService'
import { dismissActiveSnackBarOnBack, showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { MultiSelectToolbar } from '../components/MultiSelectToolbar'
import { SharePreviewSheet } from '../components/SharePreviewSheet'
import { ProviderBalanceSheet, BalanceSheetState } from '../components/ProviderBalanceSheet'
import { ColorTheme, ThemeColorConfig, VisualEffectsMode } from '../models/ThemeColors'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { detectAndRegisterChatSerifFonts } from '../utils/ChatSerifFontUtils'
import { BalanceResult, getProviderBalanceService, ProviderBalanceService } from '../services/ProviderBalanceService'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { SettingsRouteName } from '../config/SettingsRouteName'
import {
  getIndexChatListPaneWidth,
  getIndexPageHorizontalPadding,
  LayoutSizeClass
} from '../config/LayoutProfile'
import { createButtonTouchHandler, getButtonScale } from '../utils/ButtonAnimationUtils'
import {
  countSelectedIdsInCandidates,
  mergeSelectAllIds,
  removeCandidateIds,
  toggleSelectionById
} from '../utils/SelectionHelper'
import { ChatTaskStatus } from '../models/ChatTaskModels'
import {
  parseInAppTaskAlertPayload,
  parseOpenSessionPayload
} from '../utils/TaskAlertUtils'
import { IndexBottomTabItem } from '../components/index/IndexBottomTabItem'
import { IndexEmptyStateCard } from '../components/index/IndexEmptyStateCard'
import { IndexSettingsPanel } from '../components/index/IndexSettingsPanel'
import { IndexSettingsSheetContent } from '../components/index/IndexSettingsSheetContent'
import { IndexSessionListSection } from '../components/index/IndexSessionListSection'
import { ManuscriptPageTitle } from '../components/index/ManuscriptPageTitle'
import { ManuscriptTopArcButton } from '../components/index/ManuscriptTopArcButton'
import { ChatMultiSelectToolbar } from '../components/chat/ChatMultiSelectToolbar'
import { ChatFloatingImmersiveButton } from '../components/ChatFloatingImmersiveButton'
import { KnowledgeBasePanel } from '../components/KnowledgeBasePanel'
import { KnowledgeEmbeddingSelectSheetContent } from '../components/KnowledgeEmbeddingSelectSheetContent'
import { ModelSelectorContent } from '../components/ModelSelector'
import {
  AssistantAvatarView,
  buildAssistantModelAvatarValue,
  isModelAssistantAvatar,
  normalizeAssistantAvatarValue,
  refreshAssistantAvatarCache
} from '../components/AssistantAvatar'
import { AssistantAvatarEditorSheet } from '../components/AssistantAvatarEditorSheet'
import { SettingsSheetType, SessionFilterType, SessionGroupData } from './index/IndexPageTypes'
import { getFilteredSessionsForIndex, buildSessionGroupsForIndex } from './index/IndexSessionGroupHelper'
import { SessionListGroupViewModel, rebuildSessionListGroupViewModels } from './index/IndexSessionListDataSource'
import {
  getFabOffsetXForIndex,
  getFabOffsetYForIndex,
  INDEX_NEW_CHAT_FAB_BOTTOM_SPACING,
  INDEX_NEW_CHAT_FAB_STACK_HEIGHT,
  INDEX_NEW_CHAT_FAB_SIZE,
  isHandAdaptiveActiveForIndex,
  shouldPlaceFabOnLeftForIndex
} from './index/IndexHandAdaptiveHelper'
import {
  INDEX_TAB_ASSISTANTS,
  INDEX_TAB_CHAT,
  INDEX_TAB_KNOWLEDGE,
  INDEX_TAB_SETTINGS,
  shouldHideCompactTabsBarForIndex,
  shouldHideCompactTabsHostForIndex
} from './index/IndexTabsVisibilityHelper'
import {
  getSettingsSheetTitleText
} from './index/IndexSettingsTextHelper'
import { ChatPageRouteParams } from './chat/ChatPageRouteTypes'
import {
  IndexSettingsSheetActionCallbacks
} from './index/IndexSettingsSheetCoordinator'
import {
  buildHdsTopNavigationTitleBarOptions,
  getHdsTopNavigationBlurEffectiveEndOffset,
  getHdsTopNavigationContentTopPadding,
  getHdsTopNavigationMaskExtraHeight,
  HdsTopNavigationBlurOptions,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'
import {
  normalizeSystemPromptTemplate,
  SystemPromptTemplateDefaults
} from '../utils/SystemPromptTemplateUtils'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getAppUiState, observeAppUiState, setAppUiStateValue } from '../state/AppUiState'
import { tryHandleProviderDetailInternalBack } from '../components/ProviderDetailSheet'
import { tryHandleModelManageInternalBack } from './ModelManagePage'
import { TRANSPARENT_BG_COLOR } from '../utils/IconGeneratorUtils'
import { DEFAULT_PRIMARY_COLOR } from '../config/ThemeDefaults'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import {
  buildKnowledgeEmbeddingEndpointFingerprint,
  getKnowledgeEmbeddingService,
  KnowledgeEmbeddingBackend,
  KnowledgeEmbeddingSelection
} from '../services/KnowledgeEmbeddingService'
import { KnowledgeEmbeddingMigrationResult } from '../services/KnowledgeDocumentService'
import {
  buildKnowledgeRerankEndpointFingerprint,
  getKnowledgeRerankService,
  KnowledgeRerankSelection
} from '../services/KnowledgeRerankService'
import { KnowledgeRerankSelectSheetContent } from '../components/KnowledgeRerankSelectSheetContent'
import { ImmersiveSheetHeader } from '../components/ImmersiveSheetHeader'
import {
  MANUSCRIPT_BODY_FONT,
  MANUSCRIPT_HEADING_FONT,
  toRomanNumeral
} from '../utils/ManuscriptVisualUtils'

@Entry
@ComponentV2
struct Index {
  private static readonly COMPACT_TABS_BAR_HEIGHT: number = 56
  private static readonly TAB_TITLE_BAR_HEIGHT: number = 56
  private static readonly TAB_TITLE_FONT_SIZE: number = 18
  private static readonly TAB_TITLE_VERTICAL_OFFSET: number = -2
  private static readonly TAB_CONTENT_HORIZONTAL_PADDING: number = 16
  private static readonly TAB_TITLE_BAR_HORIZONTAL_PADDING: number = 16
  private static readonly TAB_TITLE_CONTENT_HORIZONTAL_PADDING: number = 8
  private static readonly COMPACT_TABS_FLOATING_SIDE_MARGIN: number = 16
  private static readonly COMPACT_TABS_FLOATING_TAB_OUTER_MARGIN: number = 12
  private static readonly COMPACT_TABS_WITH_ACTION_SMALL_WIDTH: number = 284
  private static readonly COMPACT_TABS_WITH_ACTION_MEDIUM_WIDTH: number = 316
  private static readonly COMPACT_TABS_WITH_ACTION_LARGE_WIDTH: number = 348
  private static readonly COMPACT_MINI_BAR_WIDTH: number = 56
  private static readonly TAB_ASSISTANTS: number = INDEX_TAB_ASSISTANTS
  private static readonly TAB_CHAT: number = INDEX_TAB_CHAT
  private static readonly TAB_KNOWLEDGE: number = INDEX_TAB_KNOWLEDGE
  private static readonly TAB_SETTINGS: number = INDEX_TAB_SETTINGS
  @Local currentTabIndex: number = Index.TAB_CHAT
  @Local knowledgeUploadRequestTick: number = 0
  @Local knowledgeRefreshRequestTick: number = 0
  @Local showKnowledgeEmbeddingSheet: boolean = false
  @Local knowledgeEmbeddingProviders: ModelProvider[] = []
  @Local knowledgeEmbeddingSelection: KnowledgeEmbeddingSelection =
    KnowledgeEmbeddingSelection.createLocal()
  @Local knowledgeEmbeddingLoading: boolean = false
  @Local knowledgeEmbeddingApplying: boolean = false
  @Local showKnowledgeRerankSheet: boolean = false
  @Local knowledgeRerankProviders: ModelProvider[] = []
  @Local knowledgeRerankSelection: KnowledgeRerankSelection =
    KnowledgeRerankSelection.createDisabled()
  @Local knowledgeRerankLoading: boolean = false
  @Local knowledgeRerankApplying: boolean = false
  @Local sessions: ChatSession[] = []
  @Local isLoading: boolean = false
  @Local currentThemeMode: ThemeMode = ThemeMode.SYSTEM
  @Local currentLanguage: AppLanguage = AppLanguage.SYSTEM
  @Local notifyEnabled: boolean = true
  @Local notifyOnComplete: boolean = true
  @Local notifyOnFailed: boolean = true
  @Local handAdaptiveEnabled: boolean = false
  @Local handAdaptiveNewChat: boolean = false
  @Local handAdaptiveUnsupported: boolean = false
  @Local compactBottomBarsWidthVp: number = 0
  private get handAdaptiveSettingsChangedAt(): number {
    return getAppUiState().settingsHandAdaptiveChangedAt
  }
  @Local currentHoldingHand: motion.HoldingHandStatus = motion.HoldingHandStatus.UNKNOWN_STATUS
  @Local fabPressed: boolean = false
  @Local currentColorTheme: ColorTheme = ColorTheme.LAVENDER
  @Local showSettingsSheet: boolean = false
  @Local activeSettingsSheetType: SettingsSheetType = SettingsSheetType.NONE
  @Local showSystemPromptSheet: boolean = false
  @Local customSystemPrompt: string = ''
  @Local searchText: string = ''
  @Local isSearchExpanded: boolean = false
  @Local currentSessionFilter: SessionFilterType = SessionFilterType.ALL
  @Local assistants: Assistant[] = []
  @Local currentAssistantName: string = '默认助手'
  @Local currentAssistantAvatarSymbol: string = 'AI'
  @Local currentAssistantColor: string = DEFAULT_PRIMARY_COLOR
  @Local assistantProviders: ModelProvider[] = []
  @Local currentAssistantId: string = DEFAULT_ASSISTANT_ID
  @Local showAssistantSwitchSheet: boolean = false
  @Local openingAssistantId: string = ''
  @Local showAssistantEditorSheet: boolean = false
  @Local showAssistantModelSheet: boolean = false
  @Local showAssistantAvatarEditorSheet: boolean = false
  @Local assistantAvatarRenderTick: number = 0
  @Local editingAssistantId: string = ''
  @Local editingAssistantCreatedAt: number = 0
  @Local editingAssistantSortOrder: number = 0
  @Local editingAssistantIsDefault: boolean = false
  @Local assistantFormName: string = ''
  @Local assistantFormAvatarSymbol: string = 'AI'
  @Local assistantFormColor: string = DEFAULT_PRIMARY_COLOR
  @Local assistantFormSystemPrompt: string = ''
  @Local assistantFormDefaultProviderId: string = ''
  @Local assistantFormDefaultModelId: string = ''
  @Local assistantFormDefaultModelName: string = ''
  @Local assistantFormTemperatureEnabled: boolean = false
  @Local assistantFormTemperature: number = 0.7
  @Local currentChatRouteName: string = ''
  @Local chatTabTopSessionId: string = ''
  private get activeChatSessionId(): string {
    return getAppUiState().activeChatSessionId
  }
  // 避让区域高度
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get bottomAvoidHeight(): number {
    return getAppUiState().bottomAvoidHeight
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
  // 主题颜色
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }
  private get themeDivider(): string {
    return getAppUiState().themeDivider
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get fabShadowColor(): string {
    return this.isDarkMode ? 'rgba(0, 0, 0, 0.8)' : 'rgba(15, 23, 42, 0.8)'
  }
  private get sessionListThemeRenderKey(): string {
    const uiState = getAppUiState()
    return `${this.currentColorTheme}_${uiState.isDarkMode ? '1' : '0'}`
  }
  @Local chatFontSize: number = 15
  @Local chatInputEnterKeySend: boolean = false
  @Local materialType: number = 100
  @Local materialLevel: number = 10
  @Local lightColorMode: string = 'default'
  // 监听从服务卡片打开新聊天的事件
  private get openNewChatTimestamp(): number {
    return getAppUiState().openNewChatTimestamp
  }
  private get openSessionPayload(): string {
    return getAppUiState().openSessionPayload
  }
  private get taskEventTick(): number {
    return getAppUiState().taskEventTick
  }
  @Computed
  get inAppTaskAlertPayload(): string {
    return getAppUiState().inAppTaskAlertPayload
  }

  @Monitor('inAppTaskAlertPayload')
  onInAppAlertPayloadMonitor(): void {
    const payload = this.inAppTaskAlertPayload
    if (payload === '') {
      return
    }
    this.handleInAppTaskAlertPayload(payload)
  }
  @Local filteredSessionCount: number = 0
  @Local sessionListGroups: SessionListGroupViewModel[] = []
  // 监听会话列表刷新信号（标题更新、创建、删除等）
  @Computed
  get sessionListRefreshAt(): number {
    return getAppUiState().sessionListRefreshAt
  }

  @Monitor('sessionListRefreshAt')
  onSessionListRefreshMonitor(): void {
    this.onSessionListRefresh()
  }

  @Computed
  get assistantAvatarRefreshAt(): number {
    return getAppUiState().assistantAvatarRefreshAt
  }

  @Monitor('assistantAvatarRefreshAt')
  onAssistantAvatarRefreshMonitor(): void {
    if (this.assistantAvatarRefreshAt > 0 && this.assistantAvatarRefreshAt !== this.handledAssistantAvatarRefreshAt) {
      this.handledAssistantAvatarRefreshAt = this.assistantAvatarRefreshAt
      this.bumpAssistantAvatarRenderTick()
      this.loadAssistants()
    }
  }
  @Monitor('isMultiSelectMode')
  onMultiSelectModeMonitor(): void {
    this.compactMultiSelectToolbarHeightVp = 0
  }
  // 多选模式状态
  @Local isMultiSelectMode: boolean = false
  @Local selectedSessionIds: Array<string> = []
  @Local compactMultiSelectToolbarHeightVp: number = 0
  // 分享预览弹窗状态
  @Local showSharePreview: boolean = false
  @Local shareMessages: ChatMessage[] = []
  // 服务商余额查询弹窗状态
  @Local showBalanceSheet: boolean = false
  @Local balanceSheetState: BalanceSheetState = new BalanceSheetState()
  // Settings Sheet 关闭动画期间的状态机（避免“关闭回调晚到”误关新弹窗）
  private settingsSheetClosing: boolean = false
  private pendingSettingsSheetType: SettingsSheetType = SettingsSheetType.NONE
  private chatTabNavStack: NavPathStack = new NavPathStack()
  private settingsNavPathStack: NavPathStack = new NavPathStack()
  private static readonly CHAT_DETAIL_EMPTY_ROUTE: string = 'ChatDetailEmpty'
  private static readonly CHAT_PAGE_ROUTE: string = 'ChatPage'
  private settingsReturnTabIndex: number = Index.TAB_SETTINGS
  @Local currentSettingsRouteName: string = ''
  // 返回键退出控制
  private lastBackPressTime: number = 0
  private chatViewModel: ChatViewModel = ServiceRegistry.chat()
  private settingsManager = ServiceRegistry.settings()
  private preferencesService = ServiceRegistry.preferences()
  private assistantService = ServiceRegistry.assistant()
  private providerViewModel = ServiceRegistry.provider()
  private providerBalanceService: ProviderBalanceService = getProviderBalanceService()
  private assistantListScroller: ListScroller = new ListScroller()
  private sessionListScroller: ListScroller = new ListScroller()
  private knowledgeScroller: ListScroller = new ListScroller()
  private settingsRootScroller: Scroller = new Scroller()
  private settingsCallback: SettingsChangeCallback | null = null
  private holdingHandSubscribed: boolean = false
  private handAdaptiveLoadSeq: number = 0
  private sessionLoadSeq: number = 0
  private assistantLoadSeq: number = 0
  private balanceQuerySeq: number = 0
  private assistantAvatarStateKey: string = ''
  private appUiStateDisposers: Array<() => void> = []
  private handledAssistantAvatarRefreshAt: number = 0
  private searchInputFocusId: string = 'index_session_search_input'
  private holdingHandCallback: (status: motion.HoldingHandStatus) => void = (status: motion.HoldingHandStatus): void => {
    this.currentHoldingHand = status
  }

  private showIndexSnack(message: string | Resource, duration: number = 2000,
    tone: SnackBarTone = SnackBarTone.DEFAULT): void {
    const options: SnackBarDisplayOptions = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  onLayoutSizeClassChanged(): void {
    if (this.currentTabIndex === Index.TAB_SETTINGS && this.settingsNavPathStack.size() > 0) {
      this.syncSettingsDetailPresentationMode()
    }
    if (this.isSettingsSplitMode()) {
      this.dismissSettingsSheetForNavigation()
      if (this.currentTabIndex === Index.TAB_SETTINGS) {
        this.ensureSettingsSplitLandingRoute()
      }
      return
    }
    this.syncChatDetailPlaceholder()
    this.refreshSessionListProjection()
  }

  private isExpandedLayout(): boolean {
    return this.layoutSizeClass === LayoutSizeClass.EXPANDED && this.isLandscapeWindow()
  }

  onWindowMetricsChanged(): void {
    if (this.currentTabIndex === Index.TAB_SETTINGS) {
      this.syncSettingsDetailPresentationMode()
      if (this.isSettingsSplitMode()) {
        this.dismissSettingsSheetForNavigation()
        this.ensureSettingsSplitLandingRoute()
      }
    }
    if (this.currentTabIndex === Index.TAB_CHAT) {
      this.syncChatDetailPlaceholder()
      this.refreshSessionListProjection()
    }
  }

  private isLandscapeWindow(): boolean {
    if (this.windowWidthVp <= 0 || this.windowHeightVp <= 0) {
      return false
    }
    return this.windowWidthVp > this.windowHeightVp
  }

  private getExpandedChatListWidth(): number {
    return getIndexChatListPaneWidth(this.windowWidthVp)
  }

  private getExpandedPageHorizontalPadding(): number {
    return getIndexPageHorizontalPadding(this.windowWidthVp)
  }

  private getExpandedSettingsListWidth(): number {
    return getIndexChatListPaneWidth(this.windowWidthVp)
  }

  private isSettingsSplitMode(): boolean {
    return this.isExpandedLayout() && this.isLandscapeWindow()
  }

  private syncSettingsDetailPresentationMode(): void {
    setAppUiStateValue(
      AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE,
      this.isSettingsSplitMode() ? SettingsPagePresentationMode.DETAIL_PANE : SettingsPagePresentationMode.PAGE
    )
  }

  private dismissSettingsSheetForNavigation(): void {
    this.pendingSettingsSheetType = SettingsSheetType.NONE
    if (this.showSettingsSheet) {
      this.settingsSheetClosing = true
      this.showSettingsSheet = false
      return
    }
    if (!this.settingsSheetClosing) {
      this.activeSettingsSheetType = SettingsSheetType.NONE
    }
  }

  private openSettingsPanelEntry(routeName: SettingsRouteName, sheetType: SettingsSheetType): void {
    if (this.isSettingsSplitMode()) {
      this.openSettingsDestination(routeName)
      return
    }
    this.openSettingsSheet(sheetType)
  }

  private getDefaultSettingsSplitRoute(): SettingsRouteName {
    return SettingsRouteName.MODEL_MANAGE
  }

  private ensureSettingsSplitLandingRoute(): void {
    if (!this.isSettingsSplitMode()) {
      return
    }
    if (this.currentSettingsRouteName !== '' || this.settingsNavPathStack.size() > 0) {
      return
    }
    const routeName = this.getDefaultSettingsSplitRoute()
    this.currentSettingsRouteName = routeName
    this.syncSettingsDetailPresentationMode()
    this.settingsNavPathStack.pushPath({ name: routeName })
  }

  private switchToTab(index: number, shouldEnsureSettingsSplitLanding: boolean = true): void {
    if (index !== Index.TAB_SETTINGS) {
      this.dismissSettingsSheetForNavigation()
    }
    this.currentTabIndex = index
    if (index === Index.TAB_CHAT) {
      this.loadSessions()
      this.syncChatDetailPlaceholder()
      return
    }
    if (index === Index.TAB_ASSISTANTS) {
      this.loadAssistants()
      this.loadSessions()
      return
    }
    if (index === Index.TAB_SETTINGS && shouldEnsureSettingsSplitLanding) {
      setAppUiStateValue(
        AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE,
        this.isSettingsSplitMode() ? SettingsPagePresentationMode.DETAIL_PANE : SettingsPagePresentationMode.PAGE
      )
      this.ensureSettingsSplitLandingRoute()
    }
  }

  private openChatRoute(params: ChatPageRouteParams): void {
    this.switchToTab(Index.TAB_CHAT)
    if (this.isSearchExpanded) {
      this.collapseSearchBeforeRouteChange((): void => {
        this.openChatRouteAfterSearchReset(params)
      })
      return
    }
    this.resetSearchBeforeRouteChange()
    this.openChatRouteAfterSearchReset(params)
  }

  private openChatRouteAfterSearchReset(params: ChatPageRouteParams): void {
    this.currentChatRouteName = Index.CHAT_PAGE_ROUTE
    if (this.isChatSplitLayout() && this.chatTabNavStack.size() > 0) {
      this.chatTabNavStack.replacePath({ name: Index.CHAT_PAGE_ROUTE, param: params as ChatPageRouteParams })
      return
    }
    this.chatTabNavStack.pushPath({ name: Index.CHAT_PAGE_ROUTE, param: params as ChatPageRouteParams })
  }

  private isChatSplitLayout(): boolean {
    return this.layoutSizeClass !== LayoutSizeClass.COMPACT && this.isLandscapeWindow()
  }

  private getChatNavigationMode(): NavigationMode {
    return this.isChatSplitLayout() ? NavigationMode.Split : NavigationMode.Stack
  }

  private syncChatDetailPlaceholder(): void {
    if (this.currentTabIndex !== Index.TAB_CHAT) {
      return
    }
    const wantsPlaceholder = this.isChatSplitLayout()
    const stackSize = this.chatTabNavStack.size()
    if (wantsPlaceholder) {
      if (stackSize === 0) {
        this.currentChatRouteName = Index.CHAT_DETAIL_EMPTY_ROUTE
        this.chatTabNavStack.pushPath({ name: Index.CHAT_DETAIL_EMPTY_ROUTE })
      }
      return
    }
    if (stackSize === 0) {
      this.currentChatRouteName = ''
      return
    }
    if (stackSize === 1 && this.isChatTabTopPlaceholder()) {
      this.currentChatRouteName = ''
      this.chatTabNavStack.clear(false)
    }
  }

  private isChatTabTopPlaceholder(): boolean {
    const size = this.chatTabNavStack.size()
    if (size === 0) {
      return false
    }
    const names = this.chatTabNavStack.getAllPathName()
    return names[size - 1] === Index.CHAT_DETAIL_EMPTY_ROUTE
  }

  private isChatDetailRouteActive(): boolean {
    return this.currentChatRouteName === Index.CHAT_PAGE_ROUTE
  }

  private openSettingsDestination(routeName: SettingsRouteName, param: Object | null = null): void {
    this.settingsReturnTabIndex = this.currentTabIndex !== Index.TAB_SETTINGS ? this.currentTabIndex : Index.TAB_SETTINGS
    this.switchToTab(Index.TAB_SETTINGS, false)
    this.dismissSettingsSheetForNavigation()
    this.currentSettingsRouteName = routeName
    this.syncSettingsDetailPresentationMode()
    if (this.isSettingsSplitMode() && this.settingsNavPathStack.size() > 0) {
      if (param !== null) {
        this.settingsNavPathStack.replacePath({ name: routeName, param: param })
      } else {
        this.settingsNavPathStack.replacePath({ name: routeName })
      }
      return
    }
    if (param !== null) {
      this.settingsNavPathStack.pushPath({ name: routeName, param: param })
    } else {
      this.settingsNavPathStack.pushPath({ name: routeName })
    }
  }

  private clearSettingsDestination(animated: boolean = false): void {
    if (this.settingsNavPathStack.size() > 0) {
      this.settingsNavPathStack.clear(animated)
    }
    this.currentSettingsRouteName = ''
    setAppUiStateValue(AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE, SettingsPagePresentationMode.PAGE)
  }

  onOpenNewChat(): void {
    if (this.openNewChatTimestamp > 0) {
      this.openChatRoute({} as ChatPageRouteParams)
    }
  }

  onOpenSessionPayloadChanged(): void {
    this.handleOpenSessionPayload(this.openSessionPayload)
  }

  onActiveChatSessionIdChanged(): void {
    this.refreshSessionListProjection()
  }

  onTaskEventTickChanged(): void {
    if (this.taskEventTick > 0) {
      this.loadSessions()
    }
  }

  onSessionListRefresh(): void {
    if (this.sessionListRefreshAt > 0) {
      this.loadAssistants()
      this.loadSessions()
    }
  }

  onHandAdaptiveSettingsTickChanged(): void {
    if (this.handAdaptiveSettingsChangedAt > 0) {
      this.loadHandAdaptiveSettings()
    }
  }

  private registerAppUiStateObservers(): void {
    if (this.appUiStateDisposers.length > 0) {
      return
    }
    this.appUiStateDisposers = [
      observeAppUiState(AppStorageKeys.LAYOUT_SIZE_CLASS, (): void => this.onLayoutSizeClassChanged()),
      observeAppUiState([AppStorageKeys.WINDOW_WIDTH_VP, AppStorageKeys.WINDOW_HEIGHT_VP],
        (): void => this.onWindowMetricsChanged()),
      observeAppUiState(AppStorageKeys.OPEN_NEW_CHAT, (): void => this.onOpenNewChat()),
      observeAppUiState(AppStorageKeys.OPEN_SESSION_PAYLOAD, (): void => this.onOpenSessionPayloadChanged()),
      observeAppUiState(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, (): void => this.onActiveChatSessionIdChanged()),
      observeAppUiState(AppStorageKeys.ASSISTANT_AVATAR_REFRESH_AT,
        (): void => this.onAssistantAvatarRefreshMonitor()),
      observeAppUiState(AppStorageKeys.TASK_EVENT_TICK, (): void => this.onTaskEventTickChanged()),
      observeAppUiState(AppStorageKeys.SETTINGS_HAND_ADAPTIVE_CHANGED_AT,
        (): void => this.onHandAdaptiveSettingsTickChanged())
    ]
  }

  private unregisterAppUiStateObservers(): void {
    for (let i = 0; i < this.appUiStateDisposers.length; i++) {
      this.appUiStateDisposers[i]()
    }
    this.appUiStateDisposers = []
  }

  aboutToAppear(): void {
    try {
      if (this.settingsManager.getChatSerifFontEnabled()) {
        detectAndRegisterChatSerifFonts(this.getUIContext())
      }
    } catch (error) {
      console.warn('Index', `Failed to register chat serif fonts: ${JSON.stringify(error)}`)
    }
    this.registerAppUiStateObservers()
    this.chatTabNavStack.setInterception({
      didShow: (from: NavDestinationContext | "navBar", to: NavDestinationContext | "navBar",
        operation: NavigationOperation, isAnimated: boolean): void => {
        const size = this.chatTabNavStack.size()
        if (to === 'navBar' || size <= 0) {
          this.currentChatRouteName = ''
          this.chatTabTopSessionId = ''
          this.refreshSessionListProjection()
          this.loadSessions()
          this.processInAppTaskAlertPayload(this.inAppTaskAlertPayload)
          return
        }
        const names = this.chatTabNavStack.getAllPathName()
        const topName = names[size - 1]
        this.currentChatRouteName = topName
        if (topName === Index.CHAT_PAGE_ROUTE) {
          const topParam = this.chatTabNavStack.getParamByIndex(size - 1) as ChatPageRouteParams | undefined
          this.chatTabTopSessionId = topParam?.sessionId ?? ''
        } else {
          this.chatTabTopSessionId = ''
        }
        this.refreshSessionListProjection()
        this.processInAppTaskAlertPayload(this.inAppTaskAlertPayload)
      }
    })
    this.settingsNavPathStack.setInterception({
      didShow: (from: NavDestinationContext | "navBar", to: NavDestinationContext | "navBar",
        operation: NavigationOperation, isAnimated: boolean): void => {
        if (to === 'navBar' || this.settingsNavPathStack.size() <= 0) {
          this.currentSettingsRouteName = ''
          setAppUiStateValue(AppStorageKeys.SETTINGS_DETAIL_PRESENTATION_MODE, SettingsPagePresentationMode.PAGE)
          const returnTabIndex = this.settingsReturnTabIndex
          this.settingsReturnTabIndex = Index.TAB_SETTINGS
          if (returnTabIndex !== Index.TAB_SETTINGS) {
            this.switchToTab(returnTabIndex, false)
          }
        }
      }
    })

    this.loadAssistants()
    this.loadSessions()
    this.loadSettings()
    this.refreshKnowledgeEmbeddingSelection()
    this.refreshKnowledgeRerankSelection()
    this.registerSettingsCallback()
    this.handleOpenSessionPayload(this.openSessionPayload)
    this.handleInAppTaskAlertPayload(this.inAppTaskAlertPayload)
  }

  onPageShow(): void {
    this.loadAssistants()
    this.loadSessions()
    this.refreshSettingsState()
    this.loadHandAdaptiveSettings()
    this.refreshKnowledgeEmbeddingSelection()
    this.refreshKnowledgeRerankSelection()
    this.processInAppTaskAlertPayload(this.inAppTaskAlertPayload)
  }

  aboutToDisappear(): void {
    this.unregisterAppUiStateObservers()
    this.unsubscribeHoldingHand()
    if (this.settingsCallback !== null) {
      this.settingsManager.unregisterCallback(this.settingsCallback)
      this.settingsCallback = null
    }
  }

  // 处理返回键/返回手势
  onBackPress(): boolean {
    // 如果分享预览弹窗打开，关闭弹窗
    if (this.showSharePreview) {
      this.showSharePreview = false
      return true
    }

    // 如果余额查询弹窗打开，关闭弹窗
    if (this.showBalanceSheet) {
      this.showBalanceSheet = false
      return true
    }

    if (this.showKnowledgeEmbeddingSheet) {
      if (!this.knowledgeEmbeddingApplying) {
        this.showKnowledgeEmbeddingSheet = false
      }
      return true
    }

    if (this.showKnowledgeRerankSheet) {
      if (!this.knowledgeRerankApplying) {
        this.showKnowledgeRerankSheet = false
      }
      return true
    }

    // 如果系统提示词弹窗打开，关闭弹窗
    if (this.showSystemPromptSheet) {
      this.showSystemPromptSheet = false
      return true
    }

    // 如果设置弹窗打开，关闭弹窗
    if (this.isAnySettingsSheetOpen()) {
      this.closeAllSettingsSheets()
      return true
    }

    if (this.currentTabIndex === Index.TAB_SETTINGS && this.settingsNavPathStack.size() > 0) {
      const topSettingsRouteName = this.getTopSettingsRouteName()
      if (topSettingsRouteName === 'ProviderDetailPage' && tryHandleProviderDetailInternalBack()) {
        return true
      }
      if (topSettingsRouteName === SettingsRouteName.MODEL_MANAGE &&
        tryHandleModelManageInternalBack()) {
        return true
      }
      if (this.isSettingsSplitMode()) {
        this.clearSettingsDestination(false)
      } else {
        this.settingsNavPathStack.pop()
      }
      return true
    }

    // 如果在多选模式，退出多选模式
    if (this.isMultiSelectMode) {
      this.handleExitMultiSelectMode()
      return true
    }

    // 如果搜索框展开，收起搜索框
    if (this.isSearchExpanded) {
      this.collapseSearch()
      return true
    }

    if (this.currentTabIndex === Index.TAB_CHAT && this.isChatSplitLayout() && this.isChatDetailRouteActive()) {
      this.currentChatRouteName = Index.CHAT_DETAIL_EMPTY_ROUTE
      this.chatTabNavStack.replacePath({ name: Index.CHAT_DETAIL_EMPTY_ROUTE })
      return true
    }

    if (dismissActiveSnackBarOnBack()) {
      return true
    }

    // 双击返回退出应用
    const currentTime = Date.now()
    if (currentTime - this.lastBackPressTime < 2000) {
      // 两次返回间隔小于 2 秒，退出应用
      return false
    } else {
      // 第一次返回，提示再按一次退出
      this.lastBackPressTime = currentTime
      this.showIndexSnack($r('app.string.back_press_exit_hint'), 2000)
      return true
    }
  }

  private getTopSettingsRouteName(): string {
    const routeNames = this.settingsNavPathStack.getAllPathName()
    if (routeNames.length <= 0) {
      return ''
    }
    return routeNames[routeNames.length - 1]
  }

  private registerSettingsCallback(): void {
    if (this.settingsCallback !== null) {
      return
    }

    this.settingsCallback = {
      onThemeModeChanged: (mode: ThemeMode, _colorMode: ConfigurationConstant.ColorMode): void => {
        this.currentThemeMode = mode
        this.syncSettingsSummaryToStorage()
      },
      onLanguageChanged: (language: AppLanguage): void => {
        this.currentLanguage = language
        this.syncSettingsSummaryToStorage()
      },
      onColorThemeChanged: (theme: ColorTheme, _colors: ThemeColorConfig): void => {
        this.currentColorTheme = theme
        this.syncSettingsSummaryToStorage()
      },
      onNotificationSettingsChanged: (enabled: boolean, notifyOnComplete: boolean, notifyOnFailed: boolean): void => {
        this.notifyEnabled = enabled
        this.notifyOnComplete = notifyOnComplete
        this.notifyOnFailed = notifyOnFailed
        this.syncSettingsSummaryToStorage()
      },
      onChatFontSizeChanged: (size: number): void => {
        this.chatFontSize = size
        this.syncSettingsSummaryToStorage()
      },
      onChatInputSettingsChanged: (enterKeySend: boolean): void => {
        this.chatInputEnterKeySend = enterKeySend
        this.syncSettingsSummaryToStorage()
      },
      onMaterialSettingsChanged: (materialType: number, materialLevel: number, lightColorMode: string): void => {
        this.materialType = materialType
        this.materialLevel = materialLevel
        this.lightColorMode = lightColorMode
        this.syncSettingsSummaryToStorage()
      }
    }
    this.settingsManager.registerCallback(this.settingsCallback)
  }

  async loadSettings(): Promise<void> {
    // 等待 SettingsManager 初始化完成
    await this.settingsManager.waitForInitialization()
    this.currentThemeMode = this.settingsManager.getThemeMode()
    this.currentLanguage = this.settingsManager.getLanguage()
    this.currentColorTheme = this.settingsManager.getColorTheme()
    this.notifyEnabled = this.settingsManager.getNotificationEnabled()
    this.notifyOnComplete = this.settingsManager.getNotifyOnCompleteEnabled()
    this.notifyOnFailed = this.settingsManager.getNotifyOnFailedEnabled()
    this.chatFontSize = this.settingsManager.getChatFontSize()
    this.chatInputEnterKeySend = this.settingsManager.getChatInputEnterKeySend()
    this.materialType = this.settingsManager.getMaterialType()
    this.materialLevel = this.settingsManager.getMaterialLevel()
    this.lightColorMode = this.settingsManager.getLightColorMode()
    await this.loadHandAdaptiveSettings()
    this.syncSettingsSummaryToStorage()
  }

  private patchAssistantInMemory(assistant: Assistant): void {
    const nextAssistants: Assistant[] = []
    let replaced = false
    const previousAvatarStateKey = this.assistantAvatarStateKey
    for (let i = 0; i < this.assistants.length; i++) {
      if (this.assistants[i].id === assistant.id) {
        nextAssistants.push(assistant)
        replaced = true
      } else {
        nextAssistants.push(this.assistants[i])
      }
    }
    if (!replaced) {
      nextAssistants.push(assistant)
    }
    this.assistants = nextAssistants
    if (assistant.id === this.currentAssistantId || this.currentAssistantId === '') {
      this.currentAssistantId = assistant.id !== '' ? assistant.id : DEFAULT_ASSISTANT_ID
      this.applyCurrentAssistantSnapshot(assistant)
    }
    this.assistantAvatarStateKey = this.buildAssistantAvatarStateKey(nextAssistants)
    if (this.assistantAvatarStateKey !== previousAvatarStateKey) {
      this.bumpAssistantAvatarRenderTick()
    }
    this.refreshSessionListProjection()
  }

  private mergeLoadedAssistants(loadedAssistants: Assistant[]): Assistant[] {
    return loadedAssistants
  }

  private applyCurrentAssistantSnapshot(assistant: Assistant | null): void {
    if (assistant === null) {
      this.currentAssistantName = '默认助手'
      this.currentAssistantAvatarSymbol = 'AI'
      this.currentAssistantColor = this.themePrimary
      return
    }
    this.currentAssistantName = assistant.name
    this.currentAssistantAvatarSymbol = this.normalizeAssistantAvatarSymbol(assistant.avatarSymbol)
    this.currentAssistantColor = assistant.color !== '' ? assistant.color : this.themePrimary
  }

  private buildAssistantAvatarStateKey(assistants: Assistant[]): string {
    const parts: string[] = []
    for (let i = 0; i < assistants.length; i++) {
      parts.push(`${assistants[i].id}:${assistants[i].avatarSymbol}:${assistants[i].color}`)
    }
    return parts.join('|')
  }

  private buildAssistantListStateKey(assistants: Assistant[]): string {
    const parts: string[] = []
    for (let i = 0; i < assistants.length; i++) {
      const assistant = assistants[i]
      parts.push(`${assistant.id}:${assistant.name}:${assistant.avatarSymbol}:${assistant.color}:` +
        `${assistant.defaultProviderId}:${assistant.defaultModelId}:${assistant.defaultModelName}:` +
        `${assistant.systemPrompt}:${assistant.temperatureEnabled ? '1' : '0'}:${assistant.temperature}:` +
        `${assistant.isDefault ? '1' : '0'}:${assistant.sortOrder}`)
    }
    return parts.join('|')
  }

  private bumpAssistantAvatarRenderTick(): void {
    this.assistantAvatarRenderTick += 1
  }

  private async loadAssistants(): Promise<void> {
    const seq = this.assistantLoadSeq + 1
    this.assistantLoadSeq = seq
    try {
      const assistants = await this.assistantService.getAllAssistants()
      const current = await this.assistantService.getCurrentAssistant()
      if (seq !== this.assistantLoadSeq) {
        return
      }
      const nextAssistants = this.mergeLoadedAssistants(assistants)
      const nextAvatarStateKey = this.buildAssistantAvatarStateKey(nextAssistants)
      const avatarStateChanged = nextAvatarStateKey !== this.assistantAvatarStateKey
      if (this.buildAssistantListStateKey(nextAssistants) !== this.buildAssistantListStateKey(this.assistants)) {
        this.assistants = nextAssistants
      }
      this.assistantAvatarStateKey = nextAvatarStateKey
      if (avatarStateChanged) {
        this.bumpAssistantAvatarRenderTick()
      }
      this.currentAssistantId = current.id !== '' ? current.id : DEFAULT_ASSISTANT_ID
      const currentAssistant = this.findAssistantById(this.currentAssistantId)
      this.applyCurrentAssistantSnapshot(currentAssistant !== null ? currentAssistant : current)
      this.refreshSessionListProjection()
    } catch (error) {
      if (seq !== this.assistantLoadSeq) {
        return
      }
      console.error('Index', `Failed to load assistants: ${JSON.stringify(error)}`)
      this.currentAssistantId = DEFAULT_ASSISTANT_ID
      this.applyCurrentAssistantSnapshot(null)
    }
  }

  private async loadAssistantProvidersIfNeeded(): Promise<void> {
    if (this.assistantProviders.length > 0) {
      return
    }
    try {
      this.assistantProviders = await this.providerViewModel.loadProviders()
    } catch (error) {
      console.error('Index', `Failed to load assistant providers: ${JSON.stringify(error)}`)
      this.assistantProviders = []
    }
  }

  private async switchAssistant(assistantId: string): Promise<void> {
    const previousAssistantId = this.currentAssistantId
    const assistant = await this.assistantService.setCurrentAssistantId(assistantId)
    this.currentAssistantId = assistant.id !== '' ? assistant.id : DEFAULT_ASSISTANT_ID
    this.patchAssistantInMemory(assistant)
    this.selectedSessionIds = []
    this.isMultiSelectMode = false
    if (this.isSearchExpanded) {
      this.searchText = ''
      this.isSearchExpanded = false
    }
    if (previousAssistantId !== this.currentAssistantId && this.isChatSplitLayout() && this.isChatDetailRouteActive()) {
      this.currentChatRouteName = Index.CHAT_DETAIL_EMPTY_ROUTE
      this.chatTabNavStack.replacePath({ name: Index.CHAT_DETAIL_EMPTY_ROUTE })
    }
    this.refreshSessionListProjection()
  }

  private refreshSettingsState(): void {
    this.currentThemeMode = this.settingsManager.getThemeMode()
    this.currentLanguage = this.settingsManager.getLanguage()
    this.currentColorTheme = this.settingsManager.getColorTheme()
    this.notifyEnabled = this.settingsManager.getNotificationEnabled()
    this.notifyOnComplete = this.settingsManager.getNotifyOnCompleteEnabled()
    this.notifyOnFailed = this.settingsManager.getNotifyOnFailedEnabled()
    this.chatFontSize = this.settingsManager.getChatFontSize()
    this.chatInputEnterKeySend = this.settingsManager.getChatInputEnterKeySend()
    this.materialType = this.settingsManager.getMaterialType()
    this.materialLevel = this.settingsManager.getMaterialLevel()
    this.lightColorMode = this.settingsManager.getLightColorMode()
    this.syncSettingsSummaryToStorage()
  }

  private syncSettingsSummaryToStorage(): void {
    AppStorage.setOrCreate('setting_theme_mode', this.currentThemeMode)
    AppStorage.setOrCreate('setting_language', this.currentLanguage)
    setAppUiStateValue(AppStorageKeys.COLOR_THEME, this.currentColorTheme)
    AppStorage.setOrCreate('setting_notify_enabled', this.notifyEnabled)
    AppStorage.setOrCreate('setting_notify_on_complete', this.notifyOnComplete)
    AppStorage.setOrCreate('setting_notify_on_failed', this.notifyOnFailed)
    AppStorage.setOrCreate(AppStorageKeys.SETTING_HAND_ADAPTIVE_ENABLED, this.handAdaptiveEnabled)
    AppStorage.setOrCreate(AppStorageKeys.SETTING_HAND_ADAPTIVE_NEW_CHAT, this.handAdaptiveNewChat)
    AppStorage.setOrCreate(AppStorageKeys.SETTING_HAND_ADAPTIVE_UNSUPPORTED, this.handAdaptiveUnsupported)
    setAppUiStateValue(AppStorageKeys.CHAT_FONT_SIZE, this.chatFontSize)
    setAppUiStateValue(AppStorageKeys.CHAT_INPUT_ENTER_KEY_SEND, this.chatInputEnterKeySend)
    setAppUiStateValue(AppStorageKeys.MATERIAL_TYPE, this.materialType)
    setAppUiStateValue(AppStorageKeys.MATERIAL_LEVEL, this.materialLevel)
    setAppUiStateValue(AppStorageKeys.LIGHT_COLOR_MODE, this.lightColorMode)
  }

  private async loadHandAdaptiveSettings(): Promise<void> {
    const seq = this.handAdaptiveLoadSeq + 1
    this.handAdaptiveLoadSeq = seq
    const enabled = await this.preferencesService.getBoolean(PreferenceKeys.HAND_ADAPTIVE_ENABLED, false)
    const newChatEnabled = await this.preferencesService.getBoolean(PreferenceKeys.HAND_ADAPTIVE_NEW_CHAT, enabled)
    if (seq !== this.handAdaptiveLoadSeq) {
      return
    }

    this.handAdaptiveEnabled = enabled
    if (!enabled) {
      this.handAdaptiveNewChat = false
      this.handAdaptiveUnsupported = false
      this.currentHoldingHand = motion.HoldingHandStatus.UNKNOWN_STATUS
    } else {
      this.handAdaptiveNewChat = newChatEnabled
    }

    this.updateHoldingHandSubscription()
    this.syncSettingsSummaryToStorage()
  }

  private isHandAdaptiveActive(): boolean {
    return isHandAdaptiveActiveForIndex(this.handAdaptiveEnabled, this.handAdaptiveNewChat)
  }

  private updateHoldingHandSubscription(): void {
    if (!this.isHandAdaptiveActive()) {
      this.unsubscribeHoldingHand()
      return
    }
    this.subscribeHoldingHand()
  }

  private subscribeHoldingHand(): void {
    if (this.holdingHandSubscribed || this.handAdaptiveUnsupported) {
      return
    }
    try {
      motion.on('holdingHandChanged', this.holdingHandCallback)
      this.holdingHandSubscribed = true
      this.currentHoldingHand = motion.HoldingHandStatus.UNKNOWN_STATUS
    } catch (err) {
      const error = err as BusinessError
      if (error.code === 801) {
        this.handAdaptiveUnsupported = true
      }
      console.error('Index', `Failed to subscribe holdingHandChanged, code: ${error.code}`)
      this.holdingHandSubscribed = false
      this.currentHoldingHand = motion.HoldingHandStatus.UNKNOWN_STATUS
      this.syncSettingsSummaryToStorage()
    }
  }

  private unsubscribeHoldingHand(): void {
    if (!this.holdingHandSubscribed) {
      return
    }
    try {
      motion.off('holdingHandChanged', this.holdingHandCallback)
    } catch (err) {
      const error = err as BusinessError
      console.error('Index', `Failed to unsubscribe holdingHandChanged, code: ${error.code}`)
    }
    this.holdingHandSubscribed = false
    this.currentHoldingHand = motion.HoldingHandStatus.UNKNOWN_STATUS
  }

  private requestDetectGesturePermission(): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      const hostContext = this.getUIContext().getHostContext()
      if (hostContext === undefined) {
        resolve(false)
        return
      }
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
      const permissions: Permissions[] = ['ohos.permission.DETECT_GESTURE']
      atManager.requestPermissionsFromUser(
        hostContext as common.UIAbilityContext,
        permissions,
        (err: BusinessError, data: PermissionRequestResult): void => {
          if (err) {
            console.error('Index', `Failed to request DETECT_GESTURE permission: ${JSON.stringify(err)}`)
            resolve(false)
            return
          }
          resolve(data.authResults.length > 0 && data.authResults[0] === 0)
        }
      )
    })
  }

  private shouldPlaceFabOnLeft(): boolean {
    return shouldPlaceFabOnLeftForIndex(this.handAdaptiveEnabled, this.handAdaptiveNewChat, this.handAdaptiveUnsupported,
      this.currentHoldingHand)
  }

  private getFabOffsetX(): number {
    return getFabOffsetXForIndex(this.shouldPlaceFabOnLeft())
  }

  private getFabBaseBottomInset(): number {
    if (!this.isExpandedLayout()) {
      return this.getCompactTabsBottomInset()
    }
    return this.px2vp(this.bottomAvoidHeight)
  }

  private getChatListBottomSpacerHeight(): number {
    const cardBottomBreathingRoom = 12
    return this.getFabBaseBottomInset() + INDEX_NEW_CHAT_FAB_STACK_HEIGHT +
      INDEX_NEW_CHAT_FAB_BOTTOM_SPACING + cardBottomBreathingRoom
  }

  private getCompactMultiSelectToolbarBottomInsetVp(): number {
    return Math.max(this.px2vp(this.bottomAvoidHeight) + 10, 20)
  }

  private getSessionListBottomSpacerHeight(): number {
    if (!this.isMultiSelectMode) {
      return this.getChatListBottomSpacerHeight()
    }
    if (this.isExpandedLayout()) {
      return 16
    }
    if (this.compactMultiSelectToolbarHeightVp > 0) {
      return this.compactMultiSelectToolbarHeightVp
    }
    return this.getCompactMultiSelectToolbarBottomInsetVp() + 118
  }

  private getFabOffsetY(): number {
    return getFabOffsetYForIndex(this.getFabBaseBottomInset())
  }

  private getCompactChatHeaderDefaultHeight(): number {
    return this.px2vp(this.topAvoidHeight) + Index.TAB_TITLE_BAR_HEIGHT
  }

  private getCompactChatHeaderOverlayHeight(): number {
    return this.getCompactChatHeaderDefaultHeight()
  }

  private getChatListTopSpacerHeight(): number {
    // 顶部模糊蒙版会向下渐变 maskExtraHeight，列表第一项需让出这一段，
    // 否则会落在模糊带上（卡片时间被模糊、筛选汇总行无法点击）。
    return this.getCompactChatHeaderOverlayHeight() + this.getCompactChatTitleBarMaskExtraHeight()
  }

  private getCompactSettingsHeaderDefaultHeight(): number {
    return this.px2vp(this.topAvoidHeight) + Index.TAB_TITLE_BAR_HEIGHT
  }

  private getCompactSettingsTitleBarMaskExtraHeight(): number {
    return getHdsTopNavigationMaskExtraHeight(this.windowWidthVp, this.windowHeightVp)
  }

  private getSettingsListTopSpacerHeight(): number {
    if (this.isSettingsSplitMode()) {
      return Index.TAB_TITLE_BAR_HEIGHT + this.getCompactSettingsTitleBarMaskExtraHeight()
    }
    return this.getCompactSettingsHeaderDefaultHeight() + this.getCompactSettingsTitleBarMaskExtraHeight()
  }

  private readMeasuredAreaHeight(area: Area): number {
    const height = area.height
    if (typeof height !== 'number' || Number.isNaN(height)) {
      return 0
    }
    return height
  }

  private handleCompactMultiSelectToolbarAreaChange(area: Area): void {
    const nextHeight = this.readMeasuredAreaHeight(area)
    if (nextHeight <= 0 || Math.abs(nextHeight - this.compactMultiSelectToolbarHeightVp) < 0.5) {
      return
    }
    this.compactMultiSelectToolbarHeightVp = nextHeight
  }

  private async persistHandAdaptiveSettings(): Promise<void> {
    await this.preferencesService.setBoolean(PreferenceKeys.HAND_ADAPTIVE_ENABLED, this.handAdaptiveEnabled)
    await this.preferencesService.setBoolean(PreferenceKeys.HAND_ADAPTIVE_NEW_CHAT, this.handAdaptiveNewChat)
  }

  private async handleHandAdaptiveEnabledChanged(value: boolean): Promise<void> {
    this.handAdaptiveLoadSeq = this.handAdaptiveLoadSeq + 1
    if (value && !await this.requestDetectGesturePermission()) {
      this.handAdaptiveEnabled = false
      this.handAdaptiveNewChat = false
      this.handAdaptiveUnsupported = true
      this.currentHoldingHand = motion.HoldingHandStatus.UNKNOWN_STATUS
      this.syncSettingsSummaryToStorage()
      await this.persistHandAdaptiveSettings()
      this.unsubscribeHoldingHand()
      return
    }
    this.handAdaptiveEnabled = value
    if (value) {
      this.handAdaptiveUnsupported = false
      this.handAdaptiveNewChat = true
    } else {
      this.handAdaptiveNewChat = false
      this.handAdaptiveUnsupported = false
      this.currentHoldingHand = motion.HoldingHandStatus.UNKNOWN_STATUS
    }
    this.syncSettingsSummaryToStorage()
    await this.persistHandAdaptiveSettings()
    this.updateHoldingHandSubscription()
  }

  private async handleHandAdaptiveNewChatChanged(value: boolean): Promise<void> {
    this.handAdaptiveLoadSeq = this.handAdaptiveLoadSeq + 1
    this.handAdaptiveNewChat = value
    this.syncSettingsSummaryToStorage()
    await this.persistHandAdaptiveSettings()
    this.updateHoldingHandSubscription()
  }

  private handleOpenSessionPayload(payloadText: string): void {
    if (payloadText === '') {
      return
    }
    const payload = parseOpenSessionPayload(payloadText)
    if (payload === null) {
      console.error('Index', 'Failed to parse openSession payload')
      return
    }
    this.openChatRoute({ sessionId: payload.sessionId } as ChatPageRouteParams)
    setAppUiStateValue(AppStorageKeys.OPEN_SESSION_PAYLOAD, '')
  }

  private handleInAppTaskAlertPayload(payloadText: string): void {
    if (payloadText === '') {
      return
    }
    if (!this.shouldHandleInAppTaskAlert()) {
      return
    }
    this.processInAppTaskAlertPayload(payloadText)
  }

  // 不含 shouldHandleInAppTaskAlert 守卫的处理逻辑，供 didShow 等确定可见的时机直接调用
  private processInAppTaskAlertPayload(payloadText: string): void {
    if (payloadText === '') {
      return
    }
    const payload = parseInAppTaskAlertPayload(payloadText)
    if (payload === null) {
      console.error('Index', 'Failed to parse in-app alert payload')
      return
    }
    const opts = new SnackBarDisplayOptions()
    opts.message = payload.message
    opts.duration = 5000
    opts.tone = payload.status === ChatTaskStatus.FAILED ? SnackBarTone.ERROR : SnackBarTone.SUCCESS
    opts.actionText = $r('app.string.task_alert_view')
    opts.onAction = (): void => {
      this.openChatRoute({ sessionId: payload.sessionId } as ChatPageRouteParams)
    }
    showSnackBar(this.getUIContext(), opts)
    setAppUiStateValue(AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD, '')
  }

  private shouldHandleInAppTaskAlert(): boolean {
    if (this.isChatDetailRouteActive()) {
      return false
    }
    return true
  }

  private openSettingsSheet(type: SettingsSheetType): void {
    if (type === SettingsSheetType.NONE) {
      return
    }
    // 关闭动画期间的点击：排队到 onDisappear 后再打开，避免 show 状态与可见状态不同步。
    if (this.settingsSheetClosing) {
      this.pendingSettingsSheetType = type
      return
    }
    // 弹窗已打开时，直接切换内容类型，避免“先关后开”造成的点击延迟/吞点击。
    if (this.showSettingsSheet) {
      this.activeSettingsSheetType = type
      return
    }

    this.activeSettingsSheetType = type
    this.showSettingsSheet = true
  }

  private closeAllSettingsSheets(): void {
    if (!this.showSettingsSheet) {
      return
    }
    // 仅当弹窗当前处于打开状态时进入 Closing，避免重复 close 干扰排队打开逻辑。
    this.settingsSheetClosing = true
    this.showSettingsSheet = false
  }

  private isAnySettingsSheetOpen(): boolean {
    return this.showSettingsSheet || this.settingsSheetClosing
  }

  private handleSettingsSheetWillDismiss(dismissAction: DismissSheetAction): void {
    if (dismissAction.reason === DismissReason.PRESS_BACK || dismissAction.reason === DismissReason.SLIDE_DOWN) {
      dismissAction.dismiss()
    }
  }

  private handleSettingsSheetWillSpringBackWhenDismiss(_springBackAction: SpringBackAction): void {
    // ArkUI defaults to a spring-back before dismiss once onWillDismiss is registered.
    // Keep drag-to-close single-phase for this compact settings sheet.
  }

  async loadSessions(): Promise<void> {
    // pop 动画期间完全跳过，由 setInterception.didShow 在动画完成后统一触发
    if (!this.isChatSplitLayout() && this.isChatDetailRouteActive()) {
      return
    }
    this.sessionLoadSeq = this.sessionLoadSeq + 1
    const loadSeq = this.sessionLoadSeq
    const isFirstLoad = this.sessions.length === 0 && !this.isLoading
    if (isFirstLoad) {
      this.isLoading = true
    }
    try {
      const newSessions = await this.chatViewModel.getAllSessions()
      if (loadSeq !== this.sessionLoadSeq) {
        return
      }
      this.mergeSessions(newSessions)
    } catch (error) {
      console.error('Index', `Failed to load sessions: ${JSON.stringify(error)}`)
    } finally {
      if (loadSeq === this.sessionLoadSeq) {
        this.isLoading = false
      }
    }
  }

  /**
   * 合并 sessions：
   * 1) id 集合相同：复用旧对象并按新顺序重建数组，保证排序变化可见；
   * 2) id 集合不同：全量替换。
   */
  private mergeSessions(newSessions: ChatSession[]): void {
    if (this.sessions.length === newSessions.length) {
      const oldMap: Map<string, ChatSession> = new Map()
      for (let i = 0; i < this.sessions.length; i++) {
        oldMap.set(this.sessions[i].id, this.sessions[i])
      }
      let allExist = true
      for (let i = 0; i < newSessions.length; i++) {
        if (!oldMap.has(newSessions[i].id)) {
          allExist = false
          break
        }
      }
      if (allExist) {
        const reorderedSessions: ChatSession[] = []
        for (let i = 0; i < newSessions.length; i++) {
          const fresh = newSessions[i]
          const existing = oldMap.get(fresh.id)
          if (existing !== undefined) {
            existing.title = fresh.title
            existing.updatedAt = fresh.updatedAt
            existing.lastMessagePreview = fresh.lastMessagePreview
            existing.messageCount = fresh.messageCount
            existing.draftText = fresh.draftText
            existing.draftAttachments = [...fresh.draftAttachments]
            existing.isFavorite = fresh.isFavorite
            existing.modelId = fresh.modelId
            existing.providerId = fresh.providerId
            existing.assistantId = this.normalizeSessionAssistantId(fresh.assistantId)
            reorderedSessions.push(existing)
          }
        }
        this.sessions = reorderedSessions
        this.refreshSessionListProjection()
        return
      }
    }
    // id 列表不同（新增或删除了会话），全量替换
    this.sessions = newSessions
    this.refreshSessionListProjection()
  }

  async deleteSession(sessionId: string): Promise<void> {
    await this.chatViewModel.deleteSession(sessionId)
    this.sessions = this.sessions.filter((session: ChatSession): boolean => session.id !== sessionId)
    this.selectedSessionIds = this.selectedSessionIds.filter((selectedId: string): boolean => selectedId !== sessionId)
    if (this.chatTabTopSessionId === sessionId) {
      if (this.isChatSplitLayout()) {
        this.currentChatRouteName = Index.CHAT_DETAIL_EMPTY_ROUTE
        this.chatTabNavStack.replacePath({ name: Index.CHAT_DETAIL_EMPTY_ROUTE })
      } else {
        this.currentChatRouteName = ''
        this.chatTabNavStack.clear(false)
      }
    }
    if (this.activeChatSessionId === sessionId) {
      setAppUiStateValue(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, '')
    }
    this.refreshSessionListProjection()
    this.showIndexSnack($r('app.string.conversation_deleted'), 2000, SnackBarTone.SUCCESS)
  }

  getFilteredSessions(): ChatSession[] {
    return getFilteredSessionsForIndex(this.getAssistantScopedSessions(), this.searchText, this.currentSessionFilter)
  }

  private refreshSessionListProjection(): void {
    const filteredSessions = this.getFilteredSessions()
    const nextSessionGroups: SessionGroupData[] = buildSessionGroupsForIndex(filteredSessions)
    this.filteredSessionCount = filteredSessions.length
    this.sessionListGroups = rebuildSessionListGroupViewModels(
      this.sessionListGroups,
      nextSessionGroups,
      this.selectedSessionIds,
      this.isMultiSelectMode,
      this.getActiveSessionIdForChatList()
    )
  }

  private getSessionGroupTitle(key: string): Resource {
    if (key === 'today') {
      return $r('app.string.group_today')
    } else if (key === 'yesterday') {
      return $r('app.string.group_yesterday')
    } else if (key === 'last7days') {
      return $r('app.string.group_last_7_days')
    }
    return $r('app.string.group_older')
  }

  private getFilterCountText(): string {
    return this.filteredSessionCount.toString()
  }

  private shouldApplyCompactContentTopInset(): boolean {
    return false
  }

  private shouldApplyExpandedContentTopInset(): boolean {
    return true
  }

  private getActiveSessionIdForChatList(): string {
    if (!this.isChatSplitLayout()) {
      return ''
    }
    if (this.activeChatSessionId !== '') {
      return this.activeChatSessionId
    }
    return this.chatTabTopSessionId
  }

  build() {
    Stack() {
      if (this.isExpandedLayout()) {
        this.ExpandedRoot()
      } else {
        this.CompactRoot()
      }

      // bindSheet 宿主：每个 bindSheet 必须挂在独立组件上，避免多 bindSheet 冲突
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showSharePreview, this.SharePreviewBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          systemMaterial: new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR,
            materialColor: Color.Transparent,
            applyShadow: true,
            interactive: false,
            lightEffect: { color: undefined }
          }),
          preferType: SheetType.BOTTOM,
          onDisappear: () => {
            this.showSharePreview = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showBalanceSheet, this.BalanceSheetBuilder(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          systemMaterial: new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR
          }),
          preferType: SheetType.BOTTOM,
          onDisappear: () => {
            this.showBalanceSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showKnowledgeEmbeddingSheet, this.KnowledgeEmbeddingSheetBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          systemMaterial: new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR
          }),
          preferType: SheetType.BOTTOM,
          maskColor: '#66000000',
          onDisappear: () => {
            this.showKnowledgeEmbeddingSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showKnowledgeRerankSheet, this.KnowledgeRerankSheetBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          systemMaterial: new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR
          }),
          preferType: SheetType.BOTTOM,
          maskColor: '#66000000',
          onDisappear: () => {
            this.showKnowledgeRerankSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showSettingsSheet, this.SettingsSheetBuilder(), {
          height: this.getActiveSettingsSheetHeight(),
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          systemMaterial: new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR
          }),
          preferType: SheetType.BOTTOM,
          maskColor: '#66000000',
          onWillDismiss: (dismissAction: DismissSheetAction) => {
            this.handleSettingsSheetWillDismiss(dismissAction)
          },
          onWillSpringBackWhenDismiss: (springBackAction: SpringBackAction) => {
            this.handleSettingsSheetWillSpringBackWhenDismiss(springBackAction)
          },
          onDisappear: () => {
            // Closing 结束：如果有排队的打开请求，直接重开并切换内容。
            this.settingsSheetClosing = false
            if (this.pendingSettingsSheetType !== SettingsSheetType.NONE) {
              const nextType = this.pendingSettingsSheetType
              this.pendingSettingsSheetType = SettingsSheetType.NONE
              this.activeSettingsSheetType = nextType
              this.showSettingsSheet = true
              return
            }
            this.activeSettingsSheetType = SettingsSheetType.NONE
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showSystemPromptSheet, this.SystemPromptSheetBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          backgroundColor: this.themeBackground,
          preferType: SheetType.BOTTOM,
          onDisappear: () => {
            this.showSystemPromptSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showAssistantSwitchSheet, this.AssistantSwitchSheetBuilder(), {
          height: SheetSize.MEDIUM,
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          systemMaterial: new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR
          }),
          preferType: SheetType.BOTTOM,
          onDisappear: () => {
            this.showAssistantSwitchSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showAssistantEditorSheet, this.AssistantEditorSheetBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          systemMaterial: new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR
          }),
          preferType: SheetType.BOTTOM,
          onDisappear: () => {
            this.showAssistantEditorSheet = false
            this.showAssistantModelSheet = false
            this.showAssistantAvatarEditorSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showAssistantAvatarEditorSheet, this.AssistantAvatarEditorSheetBuilder(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          systemMaterial: new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR
          }),
          preferType: SheetType.BOTTOM,
          onDisappear: () => {
            this.showAssistantAvatarEditorSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showAssistantModelSheet, this.AssistantModelSheetBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          systemMaterial: new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR
          }),
          preferType: SheetType.BOTTOM
        })

    }
    .width('100%')
    .height('100%')
  }

  @Builder
  CompactRoot() {
    Column() {
      if (this.shouldApplyCompactContentTopInset()) {
        Column()
          .width('100%')
          .height(this.px2vp(this.topAvoidHeight))
      }

      if (this.shouldHideCompactTabsHost()) {
        Column() {
          this.CompactCurrentTabContent()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Stack() {
          HdsTabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
            TabContent() {
              this.AssistantsTab()
            }
            .tabBar(this.TabBarAssistants())

            TabContent() {
              this.ChatTab()
            }
            .tabBar(this.TabBarChat())

            TabContent() {
              this.KnowledgeTab()
            }
            .tabBar(this.TabBarKnowledge())

            TabContent() {
              this.SettingsTab()
            }
            .tabBar(this.TabBarSettings())
          }
          .width('100%')
          .height('100%')
          .barMode(BarMode.Fixed)
          .barHeight(0)
          .barOverlap(false)
          .barPosition(BarPosition.End)
          .vertical(false)
          .barBackgroundColor(Color.Transparent)
          .scrollable(false)
          .cachedMaxCount(4, TabsCacheMode.CACHE_LATEST_SWITCHED)
          .onChange((index: number) => {
            if (this.currentTabIndex !== index) {
              this.switchToTab(index)
            }
          })

          if (!this.shouldHideCompactTabsBar()) {
            this.CompactBottomBarsOverlay()
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }

  private shouldHideCompactTabsHost(): boolean {
    return shouldHideCompactTabsHostForIndex(this.currentTabIndex, this.isMultiSelectMode)
  }

  private shouldHideCompactTabsBar(): boolean {
    return shouldHideCompactTabsBarForIndex(this.currentTabIndex, this.currentSettingsRouteName,
      this.isChatDetailRouteActive())
  }

  @Builder
  private CompactCurrentTabContent() {
    if (this.currentTabIndex === Index.TAB_CHAT) {
      this.ChatTab()
    } else if (this.currentTabIndex === Index.TAB_ASSISTANTS) {
      this.AssistantsTab()
    } else if (this.currentTabIndex === Index.TAB_KNOWLEDGE) {
      this.KnowledgeTab()
    } else {
      this.SettingsTab()
    }
  }

  private getCompactTabsHostBarHeight(): number {
    return this.shouldHideCompactTabsBar() ? 0 : this.getCompactTabsBarHeight()
  }

  @Builder
  ExpandedRoot() {
    Row() {
      this.ExpandedNavigationRail()

        Column() {
          if (this.shouldApplyExpandedContentTopInset()) {
            Column()
              .width('100%')
              .height(this.px2vp(this.topAvoidHeight))
          }

          if (this.currentTabIndex === Index.TAB_CHAT) {
            Column() {
              this.ChatTab()
            }
            .width('100%')
            .layoutWeight(1)
            .padding({
              left: this.getExpandedPageHorizontalPadding(),
              right: this.getExpandedPageHorizontalPadding(),
              bottom: 12
            })
          } else if (this.currentTabIndex === Index.TAB_ASSISTANTS) {
            this.ExpandedAssistantsTab()
          } else if (this.currentTabIndex === Index.TAB_KNOWLEDGE) {
            this.ExpandedKnowledgeTab()
          } else {
            this.ExpandedSettingsTab()
          }
        }
        .layoutWeight(1)
      .height('100%')
      .backgroundColor(this.themeBackground)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }

  @Builder
  ExpandedNavigationRail() {
    Column({ space: 6 }) {
      Column()
        .width('100%')
        .height(this.px2vp(this.topAvoidHeight))

      this.RailTabButton(Index.TAB_ASSISTANTS, $r('sys.symbol.person_fill'), $r('sys.symbol.person'),
        $r('app.string.tab_assistants'))
      this.RailTabButton(Index.TAB_CHAT, $r('sys.symbol.message_fill'), $r('sys.symbol.message'), $r('app.string.tab_chat'))
      this.RailTabButton(Index.TAB_KNOWLEDGE, $r('sys.symbol.externaldrive_fill'), $r('sys.symbol.externaldrive'),
        $r('app.string.tab_knowledge'))
      this.RailTabButton(Index.TAB_SETTINGS, $r('sys.symbol.gearshape_fill'), $r('sys.symbol.gearshape'), $r('app.string.tab_settings'))

      Blank()
    }
    .width(88)
    .height('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 12 })
    .backgroundColor(this.themeSurface)
    .border({
      width: { right: 1 },
      color: $r('app.color.divider')
    })
  }

  @Builder
  ExpandedSettingsTab() {
    Column() {
      this.SettingsTab()
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(this.themeBackground)
    .borderRadius(24)
    .clip(true)
    .border({
      width: 1,
      color: $r('app.color.divider')
    })
    .padding({
      left: this.getExpandedPageHorizontalPadding(),
      right: this.getExpandedPageHorizontalPadding()
    })
  }

  @Builder
  RailTabButton(index: number, activeIcon: Resource, inactiveIcon: Resource, label: Resource, badgeCount: number = 0) {
    Column() {
      IndexBottomTabItem({
        active: this.isTabActive(index),
        activeIcon: activeIcon,
        inactiveIcon: inactiveIcon,
        label: label,
        manuscriptLabel: this.getManuscriptTabLabel(index),
        badgeCount: badgeCount
      })
    }
    .width('100%')
    .height(64)
    .borderRadius(18)
    .backgroundColor(this.isTabActive(index) ? this.themePrimaryLight : Color.Transparent)
    .onClick(() => {
      this.switchToTab(index)
    })
  }

  @Builder
  SharePreviewBuilder() {
    SharePreviewSheet({
      messages: this.shareMessages,
      onClose: () => {
        this.showSharePreview = false
      }
    })
  }

  @Builder
  BalanceSheetBuilder() {
    ProviderBalanceSheet({
      state: this.balanceSheetState,
      onRefresh: () => {
        this.refreshBalanceResults()
      },
      onClose: () => {
        this.showBalanceSheet = false
      }
    })
  }

  // px 转 vp
  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  private normalizeSessionAssistantId(assistantId: string): string {
    return assistantId !== '' ? assistantId : DEFAULT_ASSISTANT_ID
  }

  private getAssistantScopedSessions(): ChatSession[] {
    const scopedSessions: ChatSession[] = []
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.normalizeSessionAssistantId(this.sessions[i].assistantId) === this.currentAssistantId) {
        scopedSessions.push(this.sessions[i])
      }
    }
    return scopedSessions
  }

  private findAssistantById(assistantId: string): Assistant | null {
    for (let i = 0; i < this.assistants.length; i++) {
      if (this.assistants[i].id === assistantId) {
        return this.assistants[i]
      }
    }
    return null
  }

  private getCurrentAssistant(): Assistant | null {
    const assistant = this.findAssistantById(this.currentAssistantId)
    if (assistant !== null) {
      return assistant
    }
    return this.assistants.length > 0 ? this.assistants[0] : null
  }

  private getWorkspaceCurrentAssistant(): Assistant {
    const current = this.getCurrentAssistant()
    if (current !== null) {
      return current
    }
    return this.assistants[0]
  }

  private hasOtherAssistantsForWorkspace(): boolean {
    const currentId = this.getWorkspaceCurrentAssistant().id
    for (let i = 0; i < this.assistants.length; i++) {
      if (this.assistants[i].id !== currentId) {
        return true
      }
    }
    return false
  }

  private getOtherAssistantsForWorkspace(): Assistant[] {
    const result: Assistant[] = []
    const currentId = this.getWorkspaceCurrentAssistant().id
    for (let i = 0; i < this.assistants.length; i++) {
      if (this.assistants[i].id !== currentId) {
        result.push(this.assistants[i])
      }
    }
    return result
  }

  private getCurrentAssistantName(): string {
    return this.currentAssistantName
  }

  private getCurrentAssistantSymbol(): string {
    return this.currentAssistantAvatarSymbol
  }

  private getCurrentAssistantColor(): string {
    return this.currentAssistantColor !== '' ? this.currentAssistantColor : this.themePrimary
  }

  private normalizeAssistantAvatarSymbol(value: string): string {
    return normalizeAssistantAvatarValue(value)
  }

  private getAssistantRenderKey(assistant: Assistant): string {
    return `${assistant.id}:${assistant.name}:${assistant.avatarSymbol}:${assistant.color}:` +
      `${assistant.defaultProviderId}:${assistant.defaultModelId}:${assistant.defaultModelName}:` +
      `${assistant.systemPrompt}:${assistant.temperatureEnabled ? '1' : '0'}:${assistant.temperature}:` +
      `${assistant.isDefault ? '1' : '0'}:${assistant.sortOrder}:${this.assistantAvatarRenderTick}`
  }

  private getAssistantAvatarRenderKey(symbol: string, color: string, size: number, radius: number,
    fontSize: number, providerId: string = '', modelId: string = '', modelName: string = ''): string {
    return `${symbol}:${color}:${size}:${radius}:${fontSize}:${providerId}:${modelId}:${modelName}:` +
      `${this.assistantAvatarRenderTick}`
  }

  private getCurrentAssistantSwitchRenderKey(): string {
    return `${this.currentAssistantId}:${this.currentAssistantName}:${this.currentAssistantAvatarSymbol}:` +
      `${this.currentAssistantColor}:${this.assistantAvatarRenderTick}`
  }

  private getAssistantSwitchMaxWidth(): number {
    if (this.windowWidthVp <= 0) {
      return this.isManuscriptMode() ? 188 : 260
    }
    if (this.isManuscriptMode()) {
      const manuscriptActionWidth = this.isMultiSelectMode ? 44 : 132
      return Math.max(112, this.windowWidthVp - manuscriptActionWidth - 56)
    }
    return Math.max(140, this.windowWidthVp - 104)
  }

  private getAssistantSwitchNameMaxWidth(): number {
    return Math.max(72, this.getAssistantSwitchMaxWidth() - 82)
  }

  private isTabActive(index: number): boolean {
    return this.currentTabIndex === index
  }

  private isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  private getManuscriptTabLabel(index: number): Resource {
    switch (index) {
      case Index.TAB_ASSISTANTS:
        return $r('app.string.manuscript_tab_assistants')
      case Index.TAB_KNOWLEDGE:
        return $r('app.string.manuscript_tab_knowledge')
      case Index.TAB_SETTINGS:
        return $r('app.string.manuscript_tab_settings')
      case Index.TAB_CHAT:
      default:
        return $r('app.string.manuscript_tab_chat')
    }
  }

  private getCompactTabsBottomInset(): number {
    if (this.isManuscriptMode() && !this.shouldHideCompactTabsBar()) {
      return this.getManuscriptBottomBarHeight() + 44
    }
    return this.getCompactTabsHostBarHeight() + this.getCompactTabsFloatingBottomMargin()
  }

  private getManuscriptBottomSafeInset(): number {
    return Math.max(0, this.px2vp(this.bottomAvoidHeight))
  }

  private getManuscriptBottomBarHeight(): number {
    return Index.COMPACT_TABS_BAR_HEIGHT + this.getManuscriptBottomSafeInset()
  }

  private getCompactTabsFloatingBottomMargin(): number {
    if (this.shouldHideCompactTabsBar()) {
      return 0
    }
    if (this.isManuscriptMode()) {
      return 0
    }
    return this.px2vp(this.bottomAvoidHeight) > 0 ? 24 : 12
  }

  private shouldPlaceCompactMiniBarOnLeft(): boolean {
    if (!this.handAdaptiveEnabled || this.handAdaptiveUnsupported) {
      return false
    }
    return this.currentHoldingHand === motion.HoldingHandStatus.LEFT_HAND_HELD
  }

  private getCompactBottomTabBarWidth(): number {
    let preferredWidth = Index.COMPACT_TABS_WITH_ACTION_SMALL_WIDTH
    if (this.windowWidthVp >= 840) {
      preferredWidth = Index.COMPACT_TABS_WITH_ACTION_LARGE_WIDTH
    } else if (this.windowWidthVp >= 440) {
      preferredWidth = Index.COMPACT_TABS_WITH_ACTION_MEDIUM_WIDTH
    }
    const availableHostWidth = this.windowWidthVp > 0 ? this.windowWidthVp : this.compactBottomBarsWidthVp
    if (availableHostWidth <= 0) {
      return preferredWidth
    }
    const minimumGap = 8
    const maximumAvailableWidth = availableHostWidth -
      Index.COMPACT_TABS_FLOATING_SIDE_MARGIN -
      Index.COMPACT_TABS_FLOATING_TAB_OUTER_MARGIN -
      Index.COMPACT_MINI_BAR_WIDTH -
      minimumGap
    return Math.min(preferredWidth, Math.max(208, maximumAvailableWidth))
  }

  private getCompactBottomBarsWidth(): number {
    if (this.compactBottomBarsWidthVp > 0) {
      return this.compactBottomBarsWidthVp
    }
    return this.windowWidthVp
  }

  private getCompactMiniBarX(): number {
    if (this.shouldPlaceCompactMiniBarOnLeft()) {
      return Index.COMPACT_TABS_FLOATING_SIDE_MARGIN
    }
    return Math.max(Index.COMPACT_TABS_FLOATING_SIDE_MARGIN,
      this.getCompactBottomBarsWidth() - Index.COMPACT_TABS_FLOATING_SIDE_MARGIN - Index.COMPACT_MINI_BAR_WIDTH)
  }

  private getCompactTabBarX(): number {
    if (this.shouldPlaceCompactMiniBarOnLeft()) {
      return Math.max(Index.COMPACT_TABS_FLOATING_TAB_OUTER_MARGIN,
        this.getCompactBottomBarsWidth() - Index.COMPACT_TABS_FLOATING_TAB_OUTER_MARGIN -
          this.getCompactBottomTabBarWidth())
    }
    return Index.COMPACT_TABS_FLOATING_TAB_OUTER_MARGIN
  }

  private handleCompactBottomBarsAreaChange(area: Area): void {
    const width = Number(area.width)
    if (!Number.isFinite(width) || width <= 0) {
      return
    }
    if (Math.abs(width - this.compactBottomBarsWidthVp) < 0.5) {
      return
    }
    this.compactBottomBarsWidthVp = width
  }

  private handleCompactBottomMiniBarClick(): void {
    if (this.currentTabIndex === Index.TAB_ASSISTANTS) {
      this.openAssistantManageForNew()
      return
    }
    if (this.currentTabIndex === Index.TAB_KNOWLEDGE) {
      this.requestKnowledgeUpload()
      return
    }
    if (this.currentTabIndex !== Index.TAB_CHAT) {
      this.switchToTab(Index.TAB_CHAT)
    }
    this.openChatRoute({} as ChatPageRouteParams)
  }

  @Builder
  private CompactBottomBarsOverlay() {
    if (this.isManuscriptMode()) {
      Stack() {
        Row() {
          this.CompactBottomTabBarBuilder()
        }
        .width('100%')
        .height(this.getManuscriptBottomBarHeight())
        .alignItems(VerticalAlign.Top)
        .position({ x: 0, y: 0 })

        Row() {
          this.CompactBottomMiniBarBuilder()
        }
        .width(40)
        .height(40)
        .position({
          x: Math.max(12, this.getCompactBottomBarsWidth() - 52),
          y: -46
        })
      }
      .height(this.getManuscriptBottomBarHeight())
      .width('100%')
      .clip(false)
      .position({ x: 0, y: '100%' })
      .translate({
        x: 0,
        y: -this.getManuscriptBottomBarHeight()
      })
      .hitTestBehavior(HitTestMode.Default)
      .zIndex(10)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.handleCompactBottomBarsAreaChange(newArea)
      })
    } else {
      Stack() {
        Row() {
          this.CompactBottomTabBarBuilder()
        }
        .width(this.getCompactBottomTabBarWidth())
        .height(Index.COMPACT_TABS_BAR_HEIGHT)
        .position({ x: this.getCompactTabBarX(), y: 0 })
        .animation({ duration: 420, curve: curves.springMotion(0.75, 0.86) })

        Row() {
          this.CompactBottomMiniBarBuilder()
        }
        .width(Index.COMPACT_MINI_BAR_WIDTH)
        .height(Index.COMPACT_TABS_BAR_HEIGHT)
        .position({ x: this.getCompactMiniBarX(), y: 0 })
        .animation({ duration: 420, curve: curves.springMotion(0.75, 0.86) })
      }
      .width('100%')
      .height(Index.COMPACT_TABS_BAR_HEIGHT)
      .clip(false)
      .position({ x: 0, y: '100%' })
      .translate({
        x: 0,
        y: -(Index.COMPACT_TABS_BAR_HEIGHT + this.getCompactTabsFloatingBottomMargin())
      })
      .hitTestBehavior(HitTestMode.Default)
      .zIndex(10)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.handleCompactBottomBarsAreaChange(newArea)
      })
    }
  }

  @Builder
  private CompactBottomMiniBarBuilder() {
    if (this.isManuscriptMode()) {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(20)
          .fontColor([this.themePrimary])
      }
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .borderRadius(0)
      .border({ width: 0, color: Color.Transparent })
      .clip(false)
      .onClick(() => {
        this.handleCompactBottomMiniBarClick()
      })
    } else {
      ChatFloatingImmersiveButton({
        barWidth: Index.COMPACT_MINI_BAR_WIDTH,
        barHeight: Index.COMPACT_TABS_BAR_HEIGHT,
        iconResource: $r('sys.symbol.plus'),
        iconSize: 28,
        iconColor: [this.themePrimary],
        iconOffsetY: 0,
        responsePadding: 0,
        enableShadow: true,
        shadowRadius: 18,
        shadowColor: this.fabShadowColor,
        shadowOffsetY: 7,
        onButtonClick: (): void => {
          this.handleCompactBottomMiniBarClick()
        }
      }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(28)
            .fontColor([this.themePrimary])
        }
        .width(Index.COMPACT_MINI_BAR_WIDTH)
        .height(Index.COMPACT_TABS_BAR_HEIGHT)
      }
    }
  }

  @Builder
  private CompactBottomTabBarBuilder() {
    if (this.isManuscriptMode()) {
      Row() {
        this.CompactBottomTabBarContent()
      }
      .width('100%')
      .height(this.getManuscriptBottomBarHeight())
      .alignItems(VerticalAlign.Top)
      .backgroundColor(this.themeSurface)
      .borderRadius(0)
      .border({ width: { top: 1 }, color: this.themeDivider })
    } else {
      HdsTabs() {
        TabContent()
          .tabBar(this.CompactBottomTabBarContent())
      }
      .barHeight(Index.COMPACT_TABS_BAR_HEIGHT)
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .barBackgroundColor(Color.Transparent)
      .width(this.getCompactBottomTabBarWidth())
      .height(Index.COMPACT_TABS_BAR_HEIGHT)
      .backgroundColor(Color.Transparent)
      .borderRadius(Index.COMPACT_TABS_BAR_HEIGHT / 2)
      .clip(false)
      .barFloatingStyle({
        barBottomMargin: 0,
        barSideMargin: 0,
        barWidth: {
          smallWidth: this.getCompactBottomTabBarWidth(),
          mediumWidth: this.getCompactBottomTabBarWidth(),
          largeWidth: this.getCompactBottomTabBarWidth()
        },
        gradientMask: { maskColor: Color.Transparent },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
    }
  }

  @Builder
  private CompactBottomTabBarContent() {
    Stack({ alignContent: Alignment.Top }) {
      Row() {
        Row() {
          this.TabBarAssistants()
        }
        .layoutWeight(this.isManuscriptMode() ? 1 : 1.12)
        .height('100%')
        .onClick(() => {
          this.switchToTab(Index.TAB_ASSISTANTS)
        })

        Row() {
          this.TabBarChat()
        }
        .layoutWeight(this.isManuscriptMode() ? 1 : 0.76)
        .height('100%')
        .onClick(() => {
          this.switchToTab(Index.TAB_CHAT)
        })

        Row() {
          this.TabBarKnowledge()
        }
        .layoutWeight(this.isManuscriptMode() ? 1 : 1.12)
        .height('100%')
        .onClick(() => {
          this.switchToTab(Index.TAB_KNOWLEDGE)
        })

        Row() {
          this.TabBarSettings()
        }
        .layoutWeight(1)
        .height('100%')
        .onClick(() => {
          this.switchToTab(Index.TAB_SETTINGS)
        })
      }
      .width('100%')
      .height(Index.COMPACT_TABS_BAR_HEIGHT)
      .padding({ left: this.isManuscriptMode() ? 0 : 6, right: this.isManuscriptMode() ? 0 : 6 })
      .backgroundColor(Color.Transparent)
      .translate({ y: this.isManuscriptMode() ? 0 : -3 })
    }
    .width('100%')
    .height(Index.COMPACT_TABS_BAR_HEIGHT)
  }

  @Builder
  TabBarChat() {
    IndexBottomTabItem({
      active: this.isTabActive(Index.TAB_CHAT),
      activeIcon: $r('sys.symbol.ellipsis_message_fill'),
      inactiveIcon: $r('sys.symbol.ellipsis_message'),
      label: $r('app.string.tab_chat'),
      manuscriptLabel: $r('app.string.manuscript_tab_chat')
    })
  }

  @Builder
  TabBarAssistants() {
    IndexBottomTabItem({
      active: this.isTabActive(Index.TAB_ASSISTANTS),
      activeIcon: $r('sys.symbol.person_fill'),
      inactiveIcon: $r('sys.symbol.person'),
      label: $r('app.string.tab_assistants'),
      manuscriptLabel: $r('app.string.manuscript_tab_assistants')
    })
  }

  @Builder
  TabBarKnowledge() {
    IndexBottomTabItem({
      active: this.isTabActive(Index.TAB_KNOWLEDGE),
      activeIcon: $r('sys.symbol.externaldrive_fill'),
      inactiveIcon: $r('sys.symbol.externaldrive'),
      label: $r('app.string.tab_knowledge'),
      manuscriptLabel: $r('app.string.manuscript_tab_knowledge')
    })
  }

  @Builder
  TabBarSettings() {
    IndexBottomTabItem({
      active: this.isTabActive(Index.TAB_SETTINGS),
      activeIcon: $r('sys.symbol.gearshape_fill'),
      inactiveIcon: $r('sys.symbol.gearshape'),
      label: $r('app.string.tab_settings'),
      manuscriptLabel: $r('app.string.manuscript_tab_settings')
    })
  }

  private expandSearch(): void {
    if (this.isSearchExpanded) {
      this.scheduleSearchInputFocus(60)
      return
    }
    this.isSearchExpanded = true
    this.scheduleSearchInputFocus(120)
  }

  private scheduleSearchInputFocus(delayMs: number): void {
    setTimeout(() => {
      this.requestSearchInputFocusSafely()
    }, delayMs)
  }

  private requestSearchInputFocusSafely(): void {
    if (!this.isSearchExpanded) {
      return
    }
    try {
      this.getUIContext().getFocusController().requestFocus(this.searchInputFocusId)
    } catch (error) {
      console.warn('Index', `request search focus skipped: ${JSON.stringify(error)}`)
    }
  }

  private collapseSearch(): void {
    this.searchText = ''
    this.isSearchExpanded = false
    this.refreshSessionListProjection()
  }

  private resetSearchBeforeRouteChange(): void {
    if (!this.isSearchExpanded && this.searchText === '') {
      return
    }
    this.searchText = ''
    this.isSearchExpanded = false
    this.refreshSessionListProjection()
    try {
      this.getUIContext().getFocusController().clearFocus()
    } catch (error) {
    }
  }

  private collapseSearchBeforeRouteChange(onFinish: () => void): void {
    try {
      this.getUIContext().getFocusController().clearFocus()
    } catch (error) {
    }
    this.getUIContext().animateTo({
      duration: 180,
      curve: Curve.EaseOut
    }, () => {
      this.searchText = ''
      this.isSearchExpanded = false
      this.refreshSessionListProjection()
    })
    setTimeout(() => {
      onFinish()
    }, 190)
  }

  private isFavoriteFilterActive(): boolean {
    return this.currentSessionFilter === SessionFilterType.FAVORITE
  }

  private setSessionFilter(filterType: SessionFilterType): void {
    if (this.currentSessionFilter === filterType) {
      return
    }
    this.currentSessionFilter = filterType
    this.refreshSessionListProjection()
  }

  private toggleFavoriteFilter(): void {
    this.setSessionFilter(this.isFavoriteFilterActive() ? SessionFilterType.ALL : SessionFilterType.FAVORITE)
  }

  private openBalanceSheet(): void {
    this.showBalanceSheet = true
    this.refreshBalanceResults()
  }

  private async refreshBalanceResults(): Promise<void> {
    if (this.balanceSheetState.loading) {
      return
    }

    const querySeq = ++this.balanceQuerySeq
    this.balanceSheetState.loading = true
    try {
      const providers = await this.providerViewModel.loadAllProviders()
      const results = await this.providerBalanceService.queryAllEnabled(providers)
      if (querySeq !== this.balanceQuerySeq) {
        return
      }
      this.balanceSheetState.results = results
      this.balanceSheetState.revision += 1
    } catch (error) {
      if (querySeq !== this.balanceQuerySeq) {
        return
      }
      console.error('Index', `Failed to query provider balances: ${JSON.stringify(error)}`)
      this.balanceSheetState.results = []
      this.balanceSheetState.revision += 1
      this.showIndexSnack($r('app.string.balance_query_failed'), 2000, SnackBarTone.ERROR)
    } finally {
      if (querySeq === this.balanceQuerySeq) {
        this.balanceSheetState.loading = false
      }
    }
  }

  private buildCompactChatTitleBarMenuIcon(symbol: Resource, color: ResourceColor): SymbolGlyphModifier {
    const icon = new SymbolGlyphModifier(symbol)
    icon.fontSize(20)
    icon.fontColor([color])
    return icon
  }

  private getCompactChatTitleBarMenuItems(): Array<HdsNavigationMenuItemOptions> {
    if (this.isMultiSelectMode) {
      return [
        {
          content: {
            label: $r('app.string.delete'),
            icon: this.buildCompactChatTitleBarMenuIcon($r('sys.symbol.trash'),
              $r('app.color.status_error')),
            action: () => {
              this.handleDeleteSelectedSessions()
            }
          }
        }
      ]
    }

    const menus: Array<HdsNavigationMenuItemOptions> = [
      {
        content: {
          label: $r('app.string.balance_query'),
          icon: this.buildCompactChatTitleBarMenuIcon($r('sys.symbol.creditcard'),
            this.isManuscriptMode() ? this.themePrimary : $r('app.color.text_primary')),
          action: () => {
            this.openBalanceSheet()
          }
        }
      },
      {
        content: {
          label: $r('app.string.filter_favorite'),
          icon: this.buildCompactChatTitleBarMenuIcon(
            this.isFavoriteFilterActive() ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
            this.isFavoriteFilterActive() || this.isManuscriptMode() ? this.themePrimary :
              $r('app.color.text_primary')
          ),
          action: () => {
            this.toggleFavoriteFilter()
          }
        }
      },
      {
        content: {
          label: $r('app.string.search_sessions_placeholder'),
          icon: this.buildCompactChatTitleBarMenuIcon($r('sys.symbol.magnifyingglass'),
            this.isSearchExpanded || this.isManuscriptMode() ? this.themePrimary : $r('app.color.text_primary')),
          action: () => {
            if (this.isSearchExpanded) {
              this.collapseSearch()
            } else {
              this.expandSearch()
            }
          }
        }
      }
    ]
    return menus
  }

  @Builder
  ChatTab() {
    HdsNavigation(this.chatTabNavStack) {
      this.ChatListPanel()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
    .titleBar(this.getCompactChatTitleBarOptions())
    .bindToScrollable([this.sessionListScroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .systemBarStyle(
      { statusBarContentColor: getHdsStatusBarContentColor() },
      { statusBarContentColor: getHdsStatusBarContentColor() }
    )
    .hideBackButton(true)
    .hideToolBar(true)
    .mode(this.getChatNavigationMode())
    .navBarWidth(this.isChatSplitLayout() ? this.getExpandedChatListWidth() : this.windowWidthVp)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
  }

  private getCompactChatTitleBarOptions(): HdsNavigationTitleBarOptions {
    const options = new HdsTopNavigationBlurOptions()
    options.startPaddingVp = Index.TAB_TITLE_BAR_HORIZONTAL_PADDING
    options.endPaddingVp = Index.TAB_TITLE_BAR_HORIZONTAL_PADDING
    options.materialType = this.materialType
    options.materialLevel = this.materialLevel
    options.windowWidthVp = this.windowWidthVp
    options.windowHeightVp = this.windowHeightVp
    options.maskExtraHeightVp = this.getCompactChatTitleBarMaskExtraHeight()
    options.blurEffectiveEndOffsetVp = getHdsTopNavigationBlurEffectiveEndOffset(this.windowWidthVp,
      this.windowHeightVp)
    options.menuItems = this.isManuscriptMode() ? [] : this.getCompactChatTitleBarMenuItems()
    options.stackBuilder = (): void => this.CompactChatTitleStackBuilder()
    return buildHdsTopNavigationTitleBarOptions(options)
  }

  private getCompactChatTitleBarMaskExtraHeight(): number {
    return getHdsTopNavigationMaskExtraHeight(this.windowWidthVp, this.windowHeightVp)
  }

  private getFloatingSearchPanelTop(): number {
    return this.getCompactChatHeaderDefaultHeight() + 16
  }

  private getFloatingSearchPanelHeight(): number {
    return 52
  }

  private getFloatingSearchPanelWidth(): number {
    const availableWidth = this.isChatSplitLayout() ? this.getExpandedChatListWidth() : this.windowWidthVp
    if (availableWidth <= 0) {
      return 360
    }
    return Math.max(0, availableWidth - 24)
  }

  @Builder
  private CompactChatTitleStackBuilder() {
    Column() {
      this.ChatListHeaderMainRow()
    }
    .width('100%')
    .height(Index.TAB_TITLE_BAR_HEIGHT)
    .translate({ y: Index.TAB_TITLE_VERTICAL_OFFSET })
    .renderGroup(false)
  }

  private getAssistantSessionCount(assistantId: string): number {
    const normalizedId = this.normalizeSessionAssistantId(assistantId)
    let count = 0
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.normalizeSessionAssistantId(this.sessions[i].assistantId) === normalizedId) {
        count++
      }
    }
    return count
  }

  private getAssistantLastChatTimestamp(assistantId: string): number {
    const normalizedId = this.normalizeSessionAssistantId(assistantId)
    let timestamp = 0
    for (let i = 0; i < this.sessions.length; i++) {
      const session = this.sessions[i]
      if (this.normalizeSessionAssistantId(session.assistantId) === normalizedId && session.updatedAt > timestamp) {
        timestamp = session.updatedAt
      }
    }
    return timestamp
  }

  private getTotalAssistantSessionCount(): number {
    let count = 0
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.normalizeSessionAssistantId(this.sessions[i].assistantId) !== '') {
        count++
      }
    }
    return count
  }

  private getAssistantAccentColor(assistant: Assistant): string {
    return assistant.color !== '' && assistant.color !== TRANSPARENT_BG_COLOR ? assistant.color : this.themePrimary
  }

  private getAssistantAvatarColor(assistant: Assistant): string {
    return assistant.color !== '' ? assistant.color : this.themePrimary
  }

  private getAssistantPromptStateText(assistant: Assistant): ResourceStr {
    return assistant.systemPrompt.trim() !== '' ? $r('app.string.assistant_prompt_configured') :
      $r('app.string.assistant_prompt_empty')
  }

  private getAssistantPromptPreviewText(assistant: Assistant): ResourceStr {
    return assistant.systemPrompt.trim() !== '' ? assistant.systemPrompt.trim() : $r('app.string.assistant_prompt_empty')
  }

  private getAssistantTemperatureText(assistant: Assistant): ResourceStr {
    return assistant.temperatureEnabled ? assistant.temperature.toFixed(1) : $r('app.string.assistant_temperature_global')
  }

  private getRelativeDiff(timestamp: number): number {
    const now = Date.now()
    return now > timestamp ? now - timestamp : 0
  }

  private isJustNow(timestamp: number): boolean {
    return timestamp > 0 && this.getRelativeDiff(timestamp) < 60 * 1000
  }

  private isMinutesAgo(timestamp: number): boolean {
    const diff = this.getRelativeDiff(timestamp)
    return timestamp > 0 && diff >= 60 * 1000 && diff < 60 * 60 * 1000
  }

  private isHoursAgo(timestamp: number): boolean {
    const diff = this.getRelativeDiff(timestamp)
    return timestamp > 0 && diff >= 60 * 60 * 1000 && diff < 24 * 60 * 60 * 1000
  }

  private isDaysAgo(timestamp: number): boolean {
    const diff = this.getRelativeDiff(timestamp)
    return timestamp > 0 && diff >= 24 * 60 * 60 * 1000 && diff < 7 * 24 * 60 * 60 * 1000
  }

  private getMinutesAgoValue(timestamp: number): string {
    return `${Math.floor(this.getRelativeDiff(timestamp) / (60 * 1000))}`
  }

  private getHoursAgoValue(timestamp: number): string {
    return `${Math.floor(this.getRelativeDiff(timestamp) / (60 * 60 * 1000))}`
  }

  private getDaysAgoValue(timestamp: number): string {
    return `${Math.floor(this.getRelativeDiff(timestamp) / (24 * 60 * 60 * 1000))}`
  }

  private formatDateMMDD(timestamp: number): string {
    const date = new Date(timestamp)
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const dayNum = date.getDate().toString().padStart(2, '0')
    return `${month}-${dayNum}`
  }

  private getAssistantDefaultModelText(assistant: Assistant): ResourceStr {
    return assistant.defaultModelName !== '' ? assistant.defaultModelName : $r('app.string.assistant_model_follow_global')
  }

  private getAssistantTabBottomSpacerHeight(): number {
    return this.isExpandedLayout() ? 16 : this.getCompactTabsBottomInset() + 12
  }

  private getAssistantsListHorizontalPadding(): number {
    return Index.TAB_CONTENT_HORIZONTAL_PADDING
  }

  private openAssistantManageForNew(): void {
    this.openAssistantEditorForNew()
  }

  private async openAssistantSessions(assistant: Assistant): Promise<void> {
    if (this.openingAssistantId !== '') {
      return
    }
    this.getUIContext().animateTo({
      duration: 120,
      curve: Curve.EaseOut
    }, () => {
      this.openingAssistantId = assistant.id
    })
    setTimeout(async () => {
      try {
        await this.switchAssistant(assistant.id)
        this.getUIContext().animateTo({
          duration: 240,
          curve: Curve.EaseOut
        }, () => {
          this.switchToTab(Index.TAB_CHAT)
        })
      } finally {
        setTimeout(() => {
          this.openingAssistantId = ''
        }, 260)
      }
    }, 90)
  }

  private async openAssistantNewChat(assistant: Assistant): Promise<void> {
    await this.switchAssistant(assistant.id)
    this.openChatRoute({} as ChatPageRouteParams)
  }

  private resetAssistantEditorForm(): void {
    this.editingAssistantId = ''
    this.editingAssistantCreatedAt = 0
    this.editingAssistantSortOrder = 0
    this.editingAssistantIsDefault = false
    this.assistantFormName = ''
    this.assistantFormAvatarSymbol = 'AI'
    this.assistantFormColor = DEFAULT_PRIMARY_COLOR
    this.assistantFormSystemPrompt = ''
    this.assistantFormDefaultProviderId = ''
    this.assistantFormDefaultModelId = ''
    this.assistantFormDefaultModelName = ''
    this.assistantFormTemperatureEnabled = false
    this.assistantFormTemperature = 0.7
  }

  private fillAssistantEditorForm(assistant: Assistant): void {
    this.editingAssistantId = assistant.id
    this.editingAssistantCreatedAt = assistant.createdAt
    this.editingAssistantSortOrder = assistant.sortOrder
    this.editingAssistantIsDefault = assistant.id === DEFAULT_ASSISTANT_ID || assistant.isDefault
    this.assistantFormName = assistant.name
    this.assistantFormAvatarSymbol = this.normalizeAssistantAvatarSymbol(assistant.avatarSymbol)
    this.assistantFormColor = assistant.color !== '' ? assistant.color : DEFAULT_PRIMARY_COLOR
    this.assistantFormSystemPrompt = assistant.systemPrompt
    this.assistantFormDefaultProviderId = assistant.defaultProviderId
    this.assistantFormDefaultModelId = assistant.defaultModelId
    this.assistantFormDefaultModelName = assistant.defaultModelName
    this.assistantFormTemperatureEnabled = assistant.temperatureEnabled
    this.assistantFormTemperature = assistant.temperature
  }

  private setAssistantFormAvatarSymbol(value: string): void {
    this.assistantFormAvatarSymbol = this.normalizeAssistantAvatarSymbol(value)
    this.bumpAssistantAvatarRenderTick()
    refreshAssistantAvatarCache(this.assistantFormAvatarSymbol)
  }

  private setAssistantFormAvatarColor(value: string): void {
    this.assistantFormColor = value !== '' ? value : this.themePrimary
    this.bumpAssistantAvatarRenderTick()
  }

  private async openAssistantEditorForNew(): Promise<void> {
    this.resetAssistantEditorForm()
    this.showAssistantEditorSheet = true
    await this.loadAssistantProvidersIfNeeded()
  }

  private async openAssistantEditor(assistant: Assistant): Promise<void> {
    this.fillAssistantEditorForm(assistant)
    this.showAssistantEditorSheet = true
    await this.loadAssistantProvidersIfNeeded()
  }

  private getAssistantEditorTitle(): Resource {
    return this.editingAssistantId === '' ? $r('app.string.new_assistant') : $r('app.string.edit_assistant')
  }

  private getAssistantFormDefaultModelText(): ResourceStr {
    return this.assistantFormDefaultModelName !== '' ? this.assistantFormDefaultModelName :
      $r('app.string.assistant_model_follow_global')
  }

  private clearAssistantDefaultModel(): void {
    this.assistantFormDefaultProviderId = ''
    this.assistantFormDefaultModelId = ''
    this.assistantFormDefaultModelName = ''
    if (isModelAssistantAvatar(this.assistantFormAvatarSymbol)) {
      this.assistantFormAvatarSymbol = buildAssistantModelAvatarValue('', '')
      this.bumpAssistantAvatarRenderTick()
    }
  }

  private selectAssistantDefaultModel(providerId: string, modelId: string, modelName: string): void {
    this.assistantFormDefaultProviderId = providerId
    this.assistantFormDefaultModelId = modelId
    this.assistantFormDefaultModelName = modelName !== '' ? modelName : modelId
    if (isModelAssistantAvatar(this.assistantFormAvatarSymbol)) {
      this.assistantFormAvatarSymbol = buildAssistantModelAvatarValue(providerId, modelId)
      this.bumpAssistantAvatarRenderTick()
    }
    this.showAssistantModelSheet = false
  }

  private async saveAssistantEditor(): Promise<void> {
    const name = this.assistantFormName.trim()
    if (name === '') {
      this.showIndexSnack($r('app.string.assistant_name_required'), 2000, SnackBarTone.ERROR)
      return
    }

    const assistant = new Assistant(this.editingAssistantId, name)
    assistant.avatarSymbol = isModelAssistantAvatar(this.assistantFormAvatarSymbol) ?
      buildAssistantModelAvatarValue(this.assistantFormDefaultProviderId, this.assistantFormDefaultModelId) :
      this.normalizeAssistantAvatarSymbol(this.assistantFormAvatarSymbol)
    assistant.color = this.assistantFormColor
    assistant.systemPrompt = this.assistantFormSystemPrompt.trim()
    assistant.defaultProviderId = this.assistantFormDefaultProviderId
    assistant.defaultModelId = this.assistantFormDefaultModelId
    assistant.defaultModelName = this.assistantFormDefaultModelName
    assistant.temperatureEnabled = this.assistantFormTemperatureEnabled
    assistant.temperature = this.assistantFormTemperature
    assistant.createdAt = this.editingAssistantCreatedAt
    assistant.sortOrder = this.editingAssistantSortOrder
    assistant.isDefault = this.editingAssistantIsDefault

    if (assistant.id === '') {
      await this.assistantService.createAssistant(assistant)
    } else {
      await this.assistantService.saveAssistant(assistant)
    }
    this.assistantLoadSeq = this.assistantLoadSeq + 1
    this.patchAssistantInMemory(assistant)
    await this.loadAssistants()
    this.showAssistantEditorSheet = false
    this.showIndexSnack($r('app.string.assistant_saved'), 1500, SnackBarTone.SUCCESS)
  }

  private async deleteAssistantNow(assistant: Assistant): Promise<void> {
    const deleted = await this.assistantService.deleteAssistant(assistant.id)
    await this.loadAssistants()
    this.showIndexSnack(deleted ? $r('app.string.assistant_deleted') : $r('app.string.assistant_delete_failed'), 1800,
      deleted ? SnackBarTone.SUCCESS : SnackBarTone.ERROR)
  }

  private async deleteAssistantFromTab(assistant: Assistant): Promise<void> {
    if (assistant.id === DEFAULT_ASSISTANT_ID || assistant.isDefault) {
      return
    }
    if (this.getAssistantSessionCount(assistant.id) <= 0) {
      await this.deleteAssistantNow(assistant)
      return
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.assistant_delete_with_chats_title'),
      message: $r('app.string.assistant_delete_with_chats_message'),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: $r('app.color.status_error'),
        action: async () => {
          await this.deleteAssistantNow(assistant)
        }
      }
    })
  }

  private async moveAssistant(from: number, to: number): Promise<void> {
    if (from === to || from < 0 || to < 0 || from >= this.assistants.length || to >= this.assistants.length) {
      return
    }
    const reordered: Assistant[] = [...this.assistants]
    const moving = reordered[from]
    reordered.splice(from, 1)
    reordered.splice(to, 0, moving)
    for (let i = 0; i < reordered.length; i++) {
      reordered[i].sortOrder = i
    }
    this.assistants = reordered
    await this.assistantService.reorderAssistants(reordered)
  }

  private getAssistantsContentTopPadding(): number {
    const topAvoidHeightVp = this.isExpandedLayout() ? 0 : this.px2vp(this.topAvoidHeight)
    return getHdsTopNavigationContentTopPadding(topAvoidHeightVp, this.windowWidthVp, this.windowHeightVp,
      Index.TAB_TITLE_BAR_HEIGHT)
  }

  private getAssistantsTitleBarOptions(): HdsNavigationTitleBarOptions {
    const options = new HdsTopNavigationBlurOptions()
    options.startPaddingVp = Index.TAB_TITLE_BAR_HORIZONTAL_PADDING
    options.endPaddingVp = Index.TAB_TITLE_BAR_HORIZONTAL_PADDING
    options.materialType = this.materialType
    options.materialLevel = this.materialLevel
    options.windowWidthVp = this.windowWidthVp
    options.windowHeightVp = this.windowHeightVp
    options.maskExtraHeightVp = getHdsTopNavigationMaskExtraHeight(this.windowWidthVp, this.windowHeightVp)
    options.blurEffectiveEndOffsetVp = getHdsTopNavigationBlurEffectiveEndOffset(this.windowWidthVp,
      this.windowHeightVp)
    options.stackBuilder = (): void => this.AssistantsHeader()
    return buildHdsTopNavigationTitleBarOptions(options)
  }

  @Builder
  private AssistantsTabContent() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      HdsNavigation() {
        Column() {
          this.AssistantsList()
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themeBackground)
      .titleBar(this.getAssistantsTitleBarOptions())
      .bindToScrollable([this.assistantListScroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .systemBarStyle(
        { statusBarContentColor: getHdsStatusBarContentColor() },
        { statusBarContentColor: getHdsStatusBarContentColor() }
      )
      .hideBackButton(true)
      .hideToolBar(true)
      .mode(NavigationMode.Stack)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])

      if (this.isExpandedLayout()) {
        this.AssistantFloatingActionButton()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AssistantsTab() {
    this.AssistantsTabContent()
  }

  @Builder
  ExpandedAssistantsTab() {
    Row() {
      Column() {
        this.AssistantsTabContent()
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 720 })
      .backgroundColor(this.themeBackground)
      .borderRadius(24)
      .clip(true)
      .border({
        width: 1,
        color: $r('app.color.divider')
      })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({
      left: this.getExpandedPageHorizontalPadding(),
      right: this.getExpandedPageHorizontalPadding(),
      bottom: 12
    })
  }

  private getKnowledgeTabBottomSpacerHeight(): number {
    return this.isExpandedLayout()
      ? INDEX_NEW_CHAT_FAB_STACK_HEIGHT + INDEX_NEW_CHAT_FAB_BOTTOM_SPACING
      : this.getCompactTabsBottomInset() + 12
  }

  private requestKnowledgeUpload(): void {
    this.knowledgeUploadRequestTick += 1
  }

  private requestKnowledgeRefresh(): void {
    this.knowledgeRefreshRequestTick += 1
  }

  private showKnowledgeUsageInfo(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.tab_knowledge'),
      message: $r('app.string.knowledge_usage_message'),
      primaryButton: {
        value: $r('app.string.knowledge_usage_acknowledge'),
        action: () => {
        }
      }
    })
  }

  private openKnowledgeEmbeddingSelector(): void {
    this.showKnowledgeEmbeddingSheet = true
    this.loadKnowledgeEmbeddingOptions()
  }

  private refreshKnowledgeEmbeddingSelection(): void {
    this.performRefreshKnowledgeEmbeddingSelection().catch((error: Object): void => {
      console.warn('Index', `[refreshKnowledgeEmbeddingSelection] Failed: ${JSON.stringify(error)}`)
    })
  }

  private async performRefreshKnowledgeEmbeddingSelection(): Promise<void> {
    const embeddingService = getKnowledgeEmbeddingService()
    await embeddingService.initialize()
    this.knowledgeEmbeddingSelection = embeddingService.getSelection()
  }

  private loadKnowledgeEmbeddingOptions(): void {
    this.performLoadKnowledgeEmbeddingOptions().catch((error: Object): void => {
      console.error('Index', `[loadKnowledgeEmbeddingOptions] Failed: ${JSON.stringify(error)}`)
      this.knowledgeEmbeddingLoading = false
      this.showIndexSnack(
        pickLocalizedText('加载向量模型失败', 'Failed to load embedding models'),
        2400,
        SnackBarTone.ERROR
      )
    })
  }

  private async performLoadKnowledgeEmbeddingOptions(): Promise<void> {
    this.knowledgeEmbeddingLoading = true
    const embeddingService = getKnowledgeEmbeddingService()
    await embeddingService.initialize()
    this.knowledgeEmbeddingSelection = embeddingService.getSelection()
    const providers = await this.providerViewModel.loadProviders()
    this.knowledgeEmbeddingProviders = this.buildKnowledgeEmbeddingProviderProjection(providers)
    this.knowledgeEmbeddingLoading = false
  }

  private buildKnowledgeEmbeddingProviderProjection(providers: ModelProvider[]): ModelProvider[] {
    const projectedProviders: ModelProvider[] = []
    for (let index = 0; index < providers.length; index++) {
      const provider = providers[index]
      if (provider.apiStyle !== ApiStyle.OPENAI ||
        provider.type === ProviderType.AZURE ||
        provider.baseUrl.trim() === '') {
        continue
      }
      const likelyEmbeddingModels: ModelInfo[] = []
      const otherModels: ModelInfo[] = []
      for (let modelIndex = 0; modelIndex < provider.models.length; modelIndex++) {
        const model = provider.models[modelIndex]
        if (!model.isEnabled) {
          continue
        }
        if (model.modelType === ModelType.EMBEDDING || this.isLikelyEmbeddingModel(model)) {
          likelyEmbeddingModels.push(model)
        } else {
          otherModels.push(model)
        }
      }
      if (likelyEmbeddingModels.length === 0 && otherModels.length === 0) {
        continue
      }

      const projected = new ModelProvider(
        provider.id,
        provider.name,
        provider.type,
        provider.iconSymbol,
        provider.brandColor,
        provider.baseUrl,
        provider.apiStyle
      )
      this.providerViewModel.syncProviderProperties(projected, provider)
      projected.models = likelyEmbeddingModels.concat(otherModels)
      projectedProviders.push(projected)
    }
    return projectedProviders
  }

  private isLikelyEmbeddingModel(model: ModelInfo): boolean {
    const identity = `${model.id} ${model.name}`.toLowerCase()
    const markers: string[] = [
      'embedding',
      'embed',
      'bge',
      'm3e',
      'mxbai',
      'nomic',
      'jina',
      'gte-',
      '/gte',
      'e5-',
      '/e5'
    ]
    for (let index = 0; index < markers.length; index++) {
      if (identity.includes(markers[index])) {
        return true
      }
    }
    return false
  }

  // ===================== 重排序模型 =====================

  private openKnowledgeRerankSelector(): void {
    this.showKnowledgeRerankSheet = true
    this.loadKnowledgeRerankOptions()
  }

  private refreshKnowledgeRerankSelection(): void {
    this.performRefreshKnowledgeRerankSelection().catch((error: Object): void => {
      console.warn('Index', `[refreshKnowledgeRerankSelection] Failed: ${JSON.stringify(error)}`)
    })
  }

  private async performRefreshKnowledgeRerankSelection(): Promise<void> {
    const rerankService = getKnowledgeRerankService()
    await rerankService.initialize()
    this.knowledgeRerankSelection = rerankService.getSelection()
  }

  private loadKnowledgeRerankOptions(): void {
    this.performLoadKnowledgeRerankOptions().catch((error: Object): void => {
      console.error('Index', `[loadKnowledgeRerankOptions] Failed: ${JSON.stringify(error)}`)
      this.knowledgeRerankLoading = false
      this.showIndexSnack(
        pickLocalizedText('加载重排序模型失败', 'Failed to load rerank models'),
        2400,
        SnackBarTone.ERROR
      )
    })
  }

  private async performLoadKnowledgeRerankOptions(): Promise<void> {
    this.knowledgeRerankLoading = true
    const rerankService = getKnowledgeRerankService()
    await rerankService.initialize()
    this.knowledgeRerankSelection = rerankService.getSelection()
    const providers = await this.providerViewModel.loadProviders()
    this.knowledgeRerankProviders = this.buildKnowledgeRerankProviderProjection(providers)
    this.knowledgeRerankLoading = false
  }

  // 与向量模型选择器同样的投影方式：疑似 Rerank 的模型排在前面，
  // 其余模型仍然可选，避免服务商命名不规范时选不到。
  private buildKnowledgeRerankProviderProjection(providers: ModelProvider[]): ModelProvider[] {
    const projectedProviders: ModelProvider[] = []
    for (let index = 0; index < providers.length; index++) {
      const provider = providers[index]
      if (provider.apiStyle !== ApiStyle.OPENAI ||
        provider.type === ProviderType.AZURE ||
        provider.baseUrl.trim() === '') {
        continue
      }
      const likelyRerankModels: ModelInfo[] = []
      const otherModels: ModelInfo[] = []
      for (let modelIndex = 0; modelIndex < provider.models.length; modelIndex++) {
        const model = provider.models[modelIndex]
        if (!model.isEnabled) {
          continue
        }
        if (this.isLikelyRerankModel(model)) {
          likelyRerankModels.push(model)
        } else {
          otherModels.push(model)
        }
      }
      if (likelyRerankModels.length === 0 && otherModels.length === 0) {
        continue
      }

      const projected = new ModelProvider(
        provider.id,
        provider.name,
        provider.type,
        provider.iconSymbol,
        provider.brandColor,
        provider.baseUrl,
        provider.apiStyle
      )
      this.providerViewModel.syncProviderProperties(projected, provider)
      projected.models = likelyRerankModels.concat(otherModels)
      projectedProviders.push(projected)
    }
    return projectedProviders
  }

  private isLikelyRerankModel(model: ModelInfo): boolean {
    const identity = `${model.id} ${model.name}`.toLowerCase()
    const markers: string[] = [
      'rerank',
      're-rank',
      'reranker',
      'cross-encoder'
    ]
    for (let index = 0; index < markers.length; index++) {
      if (identity.includes(markers[index])) {
        return true
      }
    }
    return false
  }

  private selectApiKnowledgeRerank(providerId: string, modelId: string, modelName: string): void {
    let provider: ModelProvider | null = null
    for (let index = 0; index < this.knowledgeRerankProviders.length; index++) {
      if (this.knowledgeRerankProviders[index].id === providerId) {
        provider = this.knowledgeRerankProviders[index]
        break
      }
    }
    if (provider === null) {
      this.showIndexSnack(
        pickLocalizedText('未找到所选服务商', 'The selected provider was not found'),
        2400,
        SnackBarTone.ERROR
      )
      return
    }
    const selection = new KnowledgeRerankSelection(
      provider.id,
      provider.name,
      modelId,
      modelName,
      buildKnowledgeRerankEndpointFingerprint(
        provider.baseUrl,
        provider.apiPath,
        provider.customHeadersJson
      )
    )
    this.applyKnowledgeRerankSelection(selection)
  }

  private applyKnowledgeRerankSelection(selection: KnowledgeRerankSelection): void {
    if (this.knowledgeRerankApplying) {
      return
    }
    this.performApplyKnowledgeRerankSelection(selection).catch((error: Object): void => {
      const message: string = error instanceof Error && error.message.trim() !== ''
        ? error.message
        : pickLocalizedText('切换重排序模型失败', 'Failed to switch rerank model')
      console.error('Index', `[applyKnowledgeRerankSelection] Failed: ${JSON.stringify(error)}`)
      this.knowledgeRerankApplying = false
      this.showIndexSnack(message, 3600, SnackBarTone.ERROR)
    })
  }

  // 重排序只影响召回之后的排序，不涉及任何索引重建，因此切换后立即生效
  private async performApplyKnowledgeRerankSelection(
    selection: KnowledgeRerankSelection
  ): Promise<void> {
    this.knowledgeRerankApplying = true
    let changed = false
    try {
      changed = await getKnowledgeRerankService().applySelection(selection)
    } finally {
      this.knowledgeRerankSelection = getKnowledgeRerankService().getSelection()
      this.knowledgeRerankApplying = false
    }
    this.showKnowledgeRerankSheet = false

    if (!changed) {
      this.showIndexSnack(
        pickLocalizedText('重排序设置未变化', 'The rerank setting is unchanged'),
        2400,
        SnackBarTone.SUCCESS
      )
      return
    }
    this.showIndexSnack(
      selection.isEnabled()
        ? pickLocalizedText(
          `已启用重排序：${selection.displayName()}`,
          `Reranking enabled: ${selection.displayName()}`
        )
        : pickLocalizedText('已关闭重排序', 'Reranking disabled'),
      2800,
      SnackBarTone.SUCCESS
    )
  }

  // ===================== 向量模型 =====================

  private selectLocalKnowledgeEmbedding(): void {
    this.applyKnowledgeEmbeddingSelection(KnowledgeEmbeddingSelection.createLocal())
  }

  private selectApiKnowledgeEmbedding(providerId: string, modelId: string, modelName: string): void {
    let provider: ModelProvider | null = null
    for (let index = 0; index < this.knowledgeEmbeddingProviders.length; index++) {
      if (this.knowledgeEmbeddingProviders[index].id === providerId) {
        provider = this.knowledgeEmbeddingProviders[index]
        break
      }
    }
    if (provider === null) {
      this.showIndexSnack(
        pickLocalizedText('未找到所选服务商', 'The selected provider was not found'),
        2400,
        SnackBarTone.ERROR
      )
      return
    }
    const selection = new KnowledgeEmbeddingSelection(
      KnowledgeEmbeddingBackend.API,
      provider.id,
      provider.name,
      modelId,
      modelName,
      buildKnowledgeEmbeddingEndpointFingerprint(
        provider.baseUrl,
        provider.apiPath,
        provider.customHeadersJson
      )
    )
    this.applyKnowledgeEmbeddingSelection(selection)
  }

  private applyKnowledgeEmbeddingSelection(selection: KnowledgeEmbeddingSelection): void {
    if (this.knowledgeEmbeddingApplying) {
      return
    }
    this.performApplyKnowledgeEmbeddingSelection(selection).catch((error: Object): void => {
      const message: string = error instanceof Error && error.message.trim() !== ''
        ? error.message
        : pickLocalizedText('切换向量模型失败', 'Failed to switch embedding model')
      console.error('Index', `[applyKnowledgeEmbeddingSelection] Failed: ${JSON.stringify(error)}`)
      this.knowledgeEmbeddingApplying = false
      this.showIndexSnack(message, 3600, SnackBarTone.ERROR)
    })
  }

  private async performApplyKnowledgeEmbeddingSelection(
    selection: KnowledgeEmbeddingSelection
  ): Promise<void> {
    this.knowledgeEmbeddingApplying = true
    const result: KnowledgeEmbeddingMigrationResult =
      await ServiceRegistry.knowledgeDocuments().switchEmbeddingSelection(selection)
    this.knowledgeEmbeddingSelection = getKnowledgeEmbeddingService().getSelection()
    this.knowledgeEmbeddingApplying = false
    this.showKnowledgeEmbeddingSheet = false

    if (!result.changed && !result.repaired) {
      this.showIndexSnack(
        pickLocalizedText('当前向量模型和索引均已就绪', 'The current embedding model and indexes are ready'),
        2600,
        SnackBarTone.SUCCESS
      )
      return
    }
    if (result.cancelled) {
      this.showIndexSnack(
        pickLocalizedText('向量重建已被新的任务替代',
          'The vector rebuild was superseded by a newer task'),
        3200
      )
      return
    }
    if (result.failedDocuments > 0) {
      const failureDetail = result.lastVectorMessage.trim() === ''
        ? ''
        : `；${result.lastVectorMessage}`
      this.showIndexSnack(
        pickLocalizedText(
          `${result.repaired ? '向量修复' : '向量模型已切换'}：` +
            `知识索引 ${result.keywordReadyDocuments}/${result.totalDocuments}，` +
            `语义向量 ${result.vectorReadyDocuments}/${result.totalDocuments}${failureDetail}`,
          `${result.repaired ? 'Vector repair' : 'Embedding model switched'}: ` +
            `knowledge index ${result.keywordReadyDocuments}/${result.totalDocuments}, ` +
            `semantic vectors ${result.vectorReadyDocuments}/${result.totalDocuments}${failureDetail}`
        ),
        4200,
        SnackBarTone.DEFAULT
      )
      return
    }
    if (result.totalDocuments > 0 && result.vectorReadyDocuments < result.totalDocuments) {
      const vectorDetail = result.lastVectorMessage.trim() === ''
        ? pickLocalizedText('未完成的文件继续使用关键词检索',
          'Files without vectors continue to use keyword retrieval')
        : result.lastVectorMessage
      this.showIndexSnack(
        pickLocalizedText(
          `${result.repaired ? '向量修复' : '向量模型已切换'}：` +
            `知识索引 ${result.keywordReadyDocuments}/${result.totalDocuments}，` +
            `语义向量 ${result.vectorReadyDocuments}/${result.totalDocuments}；${vectorDetail}`,
          `${result.repaired ? 'Vector repair' : 'Embedding model switched'}: ` +
            `knowledge index ${result.keywordReadyDocuments}/${result.totalDocuments}, ` +
            `semantic vectors ${result.vectorReadyDocuments}/${result.totalDocuments}; ${vectorDetail}`
        ),
        4600,
        SnackBarTone.DEFAULT
      )
      return
    }
    const successMessage: string = result.totalDocuments > 0
      ? pickLocalizedText(
        result.repaired
          ? `已修复 ${result.vectorReadyDocuments} 个文件的知识索引与语义向量`
          : `已切换向量模型：${result.vectorReadyDocuments} 个文件的知识索引与语义向量均已就绪`,
        result.repaired
          ? `Repaired knowledge indexes and semantic vectors for ${result.vectorReadyDocuments} file(s)`
          : `Embedding model switched: knowledge indexes and semantic vectors are ready for ` +
            `${result.vectorReadyDocuments} file(s)`
      )
      : pickLocalizedText('已切换向量模型', 'Embedding model switched')
    this.showIndexSnack(successMessage, 3000, SnackBarTone.SUCCESS)
  }

  @Builder
  private KnowledgeEmbeddingSheetBuilder() {
    KnowledgeEmbeddingSelectSheetContent({
      providers: this.knowledgeEmbeddingProviders,
      currentSelection: this.knowledgeEmbeddingSelection,
      isLoading: this.knowledgeEmbeddingLoading,
      isApplying: this.knowledgeEmbeddingApplying,
      onSelectLocal: (): void => {
        this.selectLocalKnowledgeEmbedding()
      },
      onSelectApi: (providerId: string, modelId: string, modelName: string): void => {
        this.selectApiKnowledgeEmbedding(providerId, modelId, modelName)
      },
      onClose: (): void => {
        if (!this.knowledgeEmbeddingApplying) {
          this.showKnowledgeEmbeddingSheet = false
        }
      }
    })
  }

  @Builder
  private KnowledgeRerankSheetBuilder() {
    KnowledgeRerankSelectSheetContent({
      providers: this.knowledgeRerankProviders,
      currentSelection: this.knowledgeRerankSelection,
      isLoading: this.knowledgeRerankLoading,
      isApplying: this.knowledgeRerankApplying,
      onSelectNone: (): void => {
        this.applyKnowledgeRerankSelection(KnowledgeRerankSelection.createDisabled())
      },
      onSelectApi: (providerId: string, modelId: string, modelName: string): void => {
        this.selectApiKnowledgeRerank(providerId, modelId, modelName)
      },
      onClose: (): void => {
        if (!this.knowledgeRerankApplying) {
          this.showKnowledgeRerankSheet = false
        }
      }
    })
  }

  private getKnowledgeContentTopPadding(): number {
    const topAvoidHeightVp = this.isExpandedLayout() ? 0 : this.px2vp(this.topAvoidHeight)
    return getHdsTopNavigationContentTopPadding(topAvoidHeightVp, this.windowWidthVp, this.windowHeightVp,
      Index.TAB_TITLE_BAR_HEIGHT)
  }

  @Builder
  private ManuscriptKnowledgeHeaderActions() {
    Row({ space: 0 }) {
      ManuscriptTopArcButton({
        symbol: this.knowledgeEmbeddingSelection.isApi()
          ? $r('sys.symbol.square_stack_3d_fill') : $r('sys.symbol.square_stack_3d'),
        active: this.knowledgeEmbeddingSelection.isApi(),
        onTap: (): void => {
          this.openKnowledgeEmbeddingSelector()
        }
      })

      ManuscriptTopArcButton({
        symbol: this.knowledgeRerankSelection.isEnabled()
          ? $r('sys.symbol.ranking_fill') : $r('sys.symbol.ranking'),
        active: this.knowledgeRerankSelection.isEnabled(),
        onTap: (): void => {
          this.openKnowledgeRerankSelector()
        }
      })

      ManuscriptTopArcButton({
        symbol: $r('sys.symbol.doc_text_badge_leaf'),
        onTap: (): void => {
          this.requestKnowledgeRefresh()
        }
      })

      ManuscriptTopArcButton({
        symbol: $r('sys.symbol.info_circle'),
        onTap: (): void => {
          this.showKnowledgeUsageInfo()
        }
      })
    }
    .height(44)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private KnowledgeTitleStackBuilder() {
    if (this.isManuscriptMode()) {
      Row() {
        Blank()
        this.ManuscriptKnowledgeHeaderActions()
      }
        .width('100%')
        .height(Index.TAB_TITLE_BAR_HEIGHT)
        .padding({
          left: Index.TAB_TITLE_CONTENT_HORIZONTAL_PADDING,
          right: Index.TAB_TITLE_CONTENT_HORIZONTAL_PADDING
        })
        .alignItems(VerticalAlign.Center)
        .translate({ y: Index.TAB_TITLE_VERTICAL_OFFSET })
    } else {
      Row() {
        Text($r('app.string.tab_knowledge'))
          .fontSize(Index.TAB_TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(Index.TAB_TITLE_BAR_HEIGHT)
      .padding({
        left: Index.TAB_TITLE_CONTENT_HORIZONTAL_PADDING,
        right: Index.TAB_TITLE_CONTENT_HORIZONTAL_PADDING
      })
      .alignItems(VerticalAlign.Center)
      .translate({ y: Index.TAB_TITLE_VERTICAL_OFFSET })
      .renderGroup(false)
    }
  }

  private getKnowledgeTitleBarOptions(): HdsNavigationTitleBarOptions {
    const options = new HdsTopNavigationBlurOptions()
    options.startPaddingVp = Index.TAB_TITLE_BAR_HORIZONTAL_PADDING
    options.endPaddingVp = Index.TAB_TITLE_BAR_HORIZONTAL_PADDING
    options.materialType = this.materialType
    options.materialLevel = this.materialLevel
    options.windowWidthVp = this.windowWidthVp
    options.windowHeightVp = this.windowHeightVp
    options.maskExtraHeightVp = getHdsTopNavigationMaskExtraHeight(this.windowWidthVp, this.windowHeightVp)
    options.blurEffectiveEndOffsetVp = getHdsTopNavigationBlurEffectiveEndOffset(this.windowWidthVp,
      this.windowHeightVp)
    // 向量模型与重排序模型是一对配置入口，和更新/用量一起平铺展示，
    // 避免默认 maxCount=3 把已有的“更新知识库”折叠进“更多”
    options.menuMaxCount = 4
    if (!this.isManuscriptMode()) {
      options.menuItems = [
        {
          content: {
            label: pickLocalizedText('选择向量模型', 'Select embedding model'),
            icon: this.buildCompactChatTitleBarMenuIcon(
              this.knowledgeEmbeddingSelection.isApi()
                ? $r('sys.symbol.square_stack_3d_fill')
                : $r('sys.symbol.square_stack_3d'),
              this.knowledgeEmbeddingSelection.isApi()
                ? this.themePrimary
                : $r('app.color.text_primary')
            ),
            action: () => {
              this.openKnowledgeEmbeddingSelector()
            }
          }
        },
        {
          content: {
            label: pickLocalizedText('选择重排序模型', 'Select rerank model'),
            icon: this.buildCompactChatTitleBarMenuIcon(
              this.knowledgeRerankSelection.isEnabled()
                ? $r('sys.symbol.ranking_fill')
                : $r('sys.symbol.ranking'),
              this.knowledgeRerankSelection.isEnabled()
                ? this.themePrimary
                : $r('app.color.text_primary')
            ),
            action: () => {
              this.openKnowledgeRerankSelector()
            }
          }
        },
        {
          content: {
            label: pickLocalizedText('更新知识库', 'Update knowledge base'),
            icon: this.buildCompactChatTitleBarMenuIcon(
              $r('sys.symbol.doc_text_badge_leaf'),
              $r('app.color.text_primary')
            ),
            action: () => {
              this.requestKnowledgeRefresh()
            }
          }
        },
        {
          content: {
            label: $r('app.string.knowledge_usage_label'),
            icon: this.buildCompactChatTitleBarMenuIcon(
              $r('sys.symbol.info_circle'),
              $r('app.color.text_primary')
            ),
            action: () => {
              this.showKnowledgeUsageInfo()
            }
          }
        }
      ]
    }
    options.stackBuilder = (): void => this.KnowledgeTitleStackBuilder()
    return buildHdsTopNavigationTitleBarOptions(options)
  }

  @Builder
  private KnowledgeTabScrollableContent() {
    KnowledgeBasePanel({
      uploadRequestTick: this.knowledgeUploadRequestTick,
      refreshRequestTick: this.knowledgeRefreshRequestTick,
      listScroller: this.knowledgeScroller,
      topSpacerHeight: this.getKnowledgeContentTopPadding(),
      bottomSpacerHeight: this.getKnowledgeTabBottomSpacerHeight()
    })
  }

  @Builder
  KnowledgeTab() {
    HdsNavigation() {
      this.KnowledgeTabScrollableContent()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
    .titleBar(this.getKnowledgeTitleBarOptions())
    .bindToScrollable([this.knowledgeScroller])
    .titleMode(HdsNavigationTitleMode.MINI)
    .systemBarStyle(
      { statusBarContentColor: getHdsStatusBarContentColor() },
      { statusBarContentColor: getHdsStatusBarContentColor() }
    )
    .hideBackButton(true)
    .hideToolBar(true)
    .mode(NavigationMode.Stack)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
  }

  @Builder
  private KnowledgeUploadFloatingActionButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(24)
        .fontColor([Color.White])
    }
    .width(INDEX_NEW_CHAT_FAB_SIZE)
    .height(INDEX_NEW_CHAT_FAB_SIZE)
    .borderRadius(INDEX_NEW_CHAT_FAB_SIZE / 2)
    .backgroundColor(this.themePrimary)
    .type(ButtonType.Circle)
    .stateEffect(false)
    .padding(0)
    .clip(false)
    .position({ x: this.shouldPlaceFabOnLeft() ? 0 : '100%', y: '100%' })
    .translate({ x: this.getFabOffsetX(), y: this.getFabOffsetY() })
    .scale(getButtonScale(this.fabPressed))
    .animation({
      duration: 420,
      curve: curves.springMotion(0.75, 0.86)
    })
    .shadow({
      radius: this.fabPressed ? 20 : 14,
      color: this.fabShadowColor,
      offsetX: 0,
      offsetY: 8
    })
    .onTouch(createButtonTouchHandler((pressed: boolean) => {
      this.fabPressed = pressed
    }))
    .onClick(() => {
      this.fabPressed = false
      this.requestKnowledgeUpload()
    })
  }

  @Builder
  ExpandedKnowledgeTab() {
    Row() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          this.KnowledgeTab()
        }
        .width('100%')
        .height('100%')

        this.KnowledgeUploadFloatingActionButton()
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 720 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({
      left: this.getExpandedPageHorizontalPadding(),
      right: this.getExpandedPageHorizontalPadding(),
      bottom: 12
    })
  }

  @Builder
  private AssistantsHeader() {
    if (this.isManuscriptMode()) {
      Column()
        .width('100%')
        .height(Index.TAB_TITLE_BAR_HEIGHT)
    } else {
      Row() {
        Text($r('app.string.assistant_manage_title'))
          .fontSize(Index.TAB_TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Row({ space: 8 }) {
          this.AssistantHeaderPill(this.assistants.length.toString(), $r('app.string.assistant_total_label'))
          this.AssistantHeaderPill(this.getTotalAssistantSessionCount().toString(),
            $r('app.string.assistant_sessions_label'))
        }
      }
      .width('100%')
      .height(Index.TAB_TITLE_BAR_HEIGHT)
      .padding({
        left: Index.TAB_TITLE_CONTENT_HORIZONTAL_PADDING,
        right: Index.TAB_TITLE_CONTENT_HORIZONTAL_PADDING
      })
      .alignItems(VerticalAlign.Center)
      .translate({ y: Index.TAB_TITLE_VERTICAL_OFFSET })
      .renderGroup(false)
    }
  }

  @Builder
  private AssistantHeaderPill(value: string, label: ResourceStr) {
    Button({ type: this.isManuscriptMode() ? ButtonType.Normal : ButtonType.Capsule, stateEffect: false }) {
      Row({ space: 4 }) {
        Text(value)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)

        Text(label)
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width(this.getAssistantHeaderPillWidth(value))
    .height(this.getAssistantHeaderPillHeight())
    .padding({ left: 8, right: 8 })
    .backgroundColor(Color.Transparent)
    .borderRadius(this.isManuscriptMode() ? 0 : this.getAssistantHeaderPillHeight() / 2)
    .systemMaterial(this.isManuscriptMode() ? undefined : new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: false,
      lightEffect: { color: undefined }
    }))
  }

  private getAssistantHeaderPillHeight(): number {
    return 26
  }

  private getAssistantHeaderPillWidth(value: string): number {
    return Math.min(96, Math.max(66, 58 + value.length * 8))
  }

  @Builder
  private AssistantStatusBadge(label: ResourceStr, color: ResourceColor) {
    Row({ space: 5 }) {
      Circle()
        .width(6)
        .height(6)
        .fill(color)
      Text(label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(22)
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.themeBackground)
    .borderRadius(11)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private AssistantsList() {
    if (this.assistants.length === 0) {
      if (this.isManuscriptMode()) {
        List({ scroller: this.assistantListScroller }) {
          ListItem() {
            Column()
              .height(this.getAssistantsContentTopPadding())
          }
          .focusable(false)
          .selectable(false)

          ListItem() {
            ManuscriptPageTitle({
              title: $r('app.string.assistant_manage_title'),
              subtitle: pickLocalizedText('助手名录', 'ASSISTANT CATALOGUE')
            })
          }
          .focusable(false)
          .selectable(false)

          ListItem() {
            Column({ space: 10 }) {
              Text('❦')
                .fontFamily(MANUSCRIPT_HEADING_FONT)
                .fontSize(22)
                .fontColor(getAppUiState().isDarkMode ? '#C99A52' : '#B68235')

              Text($r('app.string.loading'))
                .fontFamily(MANUSCRIPT_BODY_FONT)
                .fontSize(13)
                .fontStyle(FontStyle.Italic)
                .fontColor(getAppUiState().themeTextSecondary)
            }
            .width('100%')
            .height(180)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .focusable(false)
          .selectable(false)

          ListItem() {
            Column()
              .height(this.getAssistantTabBottomSpacerHeight())
          }
          .focusable(false)
          .selectable(false)
        }
        .width('100%')
        .height(0)
        .layoutWeight(1)
        .padding({ left: 32, right: 32 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      } else {
        Column() {
          IndexEmptyStateCard({
            icon: $r('sys.symbol.person'),
            title: $r('app.string.assistant_manage_title'),
            description: $r('app.string.loading')
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
    } else {
      List({ space: this.isManuscriptMode() ? 0 : 8, scroller: this.assistantListScroller }) {
        ListItem() {
          Column()
            .height(this.getAssistantsContentTopPadding())
        }
        .focusable(false)
        .selectable(false)

        if (this.isManuscriptMode()) {
          ListItem() {
            ManuscriptPageTitle({
              title: $r('app.string.assistant_manage_title'),
              subtitle: pickLocalizedText('助手名录', 'ASSISTANT CATALOGUE')
            })
          }
          .focusable(false)
          .selectable(false)
        }

        ListItem() {
          this.AssistantSectionHeader($r('app.string.assistant_current_section'))
        }
        .focusable(false)
        .selectable(false)

        ForEach([this.getWorkspaceCurrentAssistant()], (assistant: Assistant) => {
          ListItem({ style: ListItemStyle.NONE }) {
            this.AssistantJumpCard(assistant, true)
          }
          .swipeAction({
            start: this.AssistantStartSwipePanel(assistant),
            end: this.AssistantEndSwipePanel(assistant)
          })
          .borderRadius(this.isManuscriptMode() ? 0 : 12)
          .clip(false)
        }, (assistant: Assistant) => this.getAssistantRenderKey(assistant))

        if (this.hasOtherAssistantsForWorkspace()) {
          ListItem() {
            this.AssistantSectionHeader($r('app.string.assistant_others_section'))
          }
          .focusable(false)
          .selectable(false)
        }

        ForEach(this.getOtherAssistantsForWorkspace(), (assistant: Assistant) => {
          ListItem({ style: ListItemStyle.NONE }) {
            this.AssistantJumpCard(assistant, false)
          }
          .swipeAction({
            start: this.AssistantStartSwipePanel(assistant),
            end: this.AssistantEndSwipePanel(assistant)
          })
          .borderRadius(this.isManuscriptMode() ? 0 : 12)
          .clip(false)
        }, (assistant: Assistant) => this.getAssistantRenderKey(assistant))

        if (this.isManuscriptMode()) {
          ListItem() {
            Text('❦')
              .fontFamily(MANUSCRIPT_HEADING_FONT)
              .fontSize(18)
              .fontColor(getAppUiState().isDarkMode ? '#C99A52' : '#B68235')
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 18, bottom: 12 })
          }
          .focusable(false)
          .selectable(false)
        }

        ListItem() {
          Column()
            .height(this.getAssistantTabBottomSpacerHeight())
        }
        .focusable(false)
        .selectable(false)
      }
      .width('100%')
      .height(0)
      .layoutWeight(1)
      .padding({
        left: this.isManuscriptMode() ? 32 : this.getAssistantsListHorizontalPadding(),
        right: this.isManuscriptMode() ? 32 : this.getAssistantsListHorizontalPadding(),
        top: this.isManuscriptMode() ? 0 : 2
      })
      .clip(false)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(4)
    }
  }

  @Builder
  private AssistantSectionHeader(title: ResourceStr) {
    Text(title)
      .fontFamily(this.isManuscriptMode() ? MANUSCRIPT_BODY_FONT : undefined)
      .fontSize(this.isManuscriptMode() ? 10 : 12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.isManuscriptMode() ? (getAppUiState().isDarkMode ? '#D9B274' : '#8A6228') :
        $r('app.color.text_tertiary'))
      .letterSpacing(this.isManuscriptMode() ? 1.4 : 0)
      .textCase(this.isManuscriptMode() ? TextCase.UpperCase : TextCase.Normal)
      .width('100%')
      .padding({
        left: 4,
        right: 4,
        top: this.isManuscriptMode() ? 14 : 8,
        bottom: this.isManuscriptMode() ? 5 : 2
      })
  }

  @Builder
  private AssistantStartSwipePanel(assistant: Assistant) {
    Row() {
      this.AssistantSwipeButton($r('sys.symbol.plus'), $r('app.string.new_chat'), this.themePrimary, 84, (): void => {
        this.assistantListScroller.closeAllSwipeActions()
        this.openAssistantNewChat(assistant)
      })
    }
    .height('100%')
    .borderRadius({ topLeft: 12, bottomLeft: 12 })
    .clip(true)
  }

  @Builder
  private AssistantEndSwipePanel(assistant: Assistant) {
    Row() {
      this.AssistantSwipeButton($r('sys.symbol.square_and_pencil'), $r('app.string.edit_assistant_short'),
        this.themePrimary, 72, (): void => {
          this.assistantListScroller.closeAllSwipeActions()
          this.openAssistantEditor(assistant)
        })

      if (assistant.id !== DEFAULT_ASSISTANT_ID && !assistant.isDefault) {
        this.AssistantSwipeButton($r('sys.symbol.trash'), $r('app.string.delete'), $r('app.color.status_error'),
          72, (): void => {
            this.assistantListScroller.closeAllSwipeActions()
            this.deleteAssistantFromTab(assistant)
          })
      }
    }
    .height('100%')
    .borderRadius({ topRight: 12, bottomRight: 12 })
    .clip(true)
  }

  @Builder
  private AssistantSwipeButton(symbol: Resource, label: ResourceStr, backgroundColor: ResourceColor, width: number,
    onTap: () => void) {
    Button() {
      Column() {
        SymbolGlyph(symbol)
          .fontSize(18)
          .fontColor([Color.White])

        Text(label)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .margin({ top: 2 })
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(width)
    .height('100%')
    .borderRadius(0)
    .backgroundColor(backgroundColor)
    .stateEffect(false)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: backgroundColor,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .onClick(() => {
      onTap()
    })
  }

  @Builder
  private AssistantFloatingActionButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(24)
        .fontColor([Color.White])
    }
    .width(INDEX_NEW_CHAT_FAB_SIZE)
    .height(INDEX_NEW_CHAT_FAB_SIZE)
    .borderRadius(INDEX_NEW_CHAT_FAB_SIZE / 2)
    .backgroundColor(this.themePrimary)
    .type(ButtonType.Circle)
    .stateEffect(false)
    .padding(0)
    .clip(false)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: this.themePrimary,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .position({ x: this.shouldPlaceFabOnLeft() ? 0 : '100%', y: '100%' })
    .translate({ x: this.getFabOffsetX(), y: this.getFabOffsetY() })
    .scale(getButtonScale(this.fabPressed))
    .animation({
      duration: 420,
      curve: curves.springMotion(0.75, 0.86)
    })
    .shadow({
      radius: this.fabPressed ? 20 : 14,
      color: this.fabShadowColor,
      offsetX: 0,
      offsetY: 8
    })
    .onTouch(createButtonTouchHandler((pressed: boolean) => {
      this.fabPressed = pressed
    }))
    .onClick(() => {
      this.fabPressed = false
      this.openAssistantManageForNew()
    })
  }

  private getAssistantOrdinal(assistant: Assistant): number {
    for (let index = 0; index < this.assistants.length; index++) {
      if (this.assistants[index].id === assistant.id) {
        return index + 1
      }
    }
    return 1
  }

  @Builder
  private ManuscriptAssistantAction(label: ResourceStr, primary: boolean, onTap: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Text(label)
        .fontFamily(MANUSCRIPT_BODY_FONT)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(primary ? (getAppUiState().isDarkMode ? '#D9B274' : '#8A6228') :
          getAppUiState().themeTextSecondary)
        .letterSpacing(1)
        .textCase(TextCase.UpperCase)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(28)
    .padding({ left: 2, right: 2 })
    .backgroundColor(Color.Transparent)
    .borderRadius(0)
    .border({
      width: { bottom: primary ? 1 : 0 },
      color: getAppUiState().isDarkMode ? '#C99A52' : '#B68235'
    })
    .onClick(() => {
      onTap()
    })
  }

  @Builder
  private ManuscriptAssistantActions(assistant: Assistant) {
    Row({ space: 20 }) {
      this.ManuscriptAssistantAction($r('app.string.new_chat'), true, (): void => {
        this.openAssistantNewChat(assistant)
      })

      this.ManuscriptAssistantAction($r('app.string.assistant_view_chats'), false, (): void => {
        this.openAssistantSessions(assistant)
      })

      Blank()

      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(16)
          .fontColor([getAppUiState().themeTextSecondary])
      }
      .width(36)
      .height(28)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .borderRadius(0)
      .bindMenu(this.AssistantCardMoreMenu(assistant), {
        placement: Placement.BottomRight,
        offset: { x: 0, y: 8 },
        backgroundColor: this.themeSurface,
        backgroundBlurStyle: BlurStyle.Regular
      })
    }
    .width('100%')
    .height(30)
    .padding({ left: 34 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ManuscriptAssistantRow(assistant: Assistant) {
    Column({ space: 5 }) {
      Row({ space: 8 }) {
        Text(toRomanNumeral(this.getAssistantOrdinal(assistant)))
          .width(26)
          .fontFamily(MANUSCRIPT_HEADING_FONT)
          .fontSize(15)
          .fontWeight(600)
          .fontColor(getAppUiState().isDarkMode ? '#D9B274' : '#8A6228')
          .fontFeature('tnum')

        Text(assistant.name)
          .fontFamily(MANUSCRIPT_HEADING_FONT)
          .fontSize(19)
          .fontWeight(600)
          .fontColor(getAppUiState().themeTextPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '55%' })

        Column()
          .height(1)
          .border({
            width: { top: 1 },
            color: getAppUiState().isDarkMode ? '#4A463F' : '#C9C4BB',
            style: BorderStyle.Dotted
          })
          .layoutWeight(1)
          .constraintSize({ minWidth: 18 })

        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.message'))
            .fontSize(11)
            .fontColor([getAppUiState().themeTextTertiary])

          Text(this.getAssistantSessionCount(assistant.id).toString())
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontSize(11.5)
            .fontColor(getAppUiState().themeTextTertiary)
            .fontFeature('tnum')
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text(this.getAssistantDefaultModelText(assistant))
          .fontFamily(MANUSCRIPT_BODY_FONT)
          .fontSize(12.5)
          .fontStyle(FontStyle.Italic)
          .fontColor(getAppUiState().themeTextSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (assistant.id === this.currentAssistantId) {
          Text($r('app.string.assistant_active_badge'))
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontSize(9.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(getAppUiState().isDarkMode ? '#D9B274' : '#8A6228')
            .letterSpacing(1)
            .textCase(TextCase.UpperCase)
        } else {
          this.AssistantRelativeTimeText(this.getAssistantLastChatTimestamp(assistant.id))
        }
      }
      .width('100%')
      .padding({ left: 34 })
      .alignItems(VerticalAlign.Center)

      this.ManuscriptAssistantActions(assistant)
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 12, bottom: 8 })
    .backgroundColor(this.openingAssistantId === assistant.id ?
      (getAppUiState().isDarkMode ? '#33291B' : '#F5EDE0') : Color.Transparent)
    .border({
      width: {
        bottom: 0.5,
        left: assistant.id === this.currentAssistantId ? 2 : 0
      },
      color: assistant.id === this.currentAssistantId ? this.themePrimary : getAppUiState().themeDivider
    })
    .opacity(this.openingAssistantId === assistant.id ? 0.92 : 1)
    .animation({ duration: 180, curve: Curve.EaseOut })
    .onClick(() => {
      this.openAssistantSessions(assistant)
    })
  }

  @Builder
  private AssistantJumpCard(assistant: Assistant, featured: boolean = false) {
    if (this.isManuscriptMode()) {
      this.ManuscriptAssistantRow(assistant)
    } else {
      Column() {
        this.AssistantJumpCardContent(assistant, featured)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: featured ? 14 : 12, bottom: featured ? 14 : 12 })
      .backgroundColor(Color.Transparent)
      .borderRadius(16)
      .border({
        width: assistant.id === this.currentAssistantId || this.openingAssistantId === assistant.id ? 1.5 : 1,
        color: assistant.id === this.currentAssistantId || this.openingAssistantId === assistant.id ?
          this.themePrimary : this.themePrimaryLight
      })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        materialColor: Color.Transparent,
        applyShadow: true,
        interactive: false,
        lightEffect: { color: undefined }
      }))
      .scale({
        x: this.openingAssistantId === assistant.id ? 0.985 : 1,
        y: this.openingAssistantId === assistant.id ? 0.985 : 1
      })
      .opacity(this.openingAssistantId === assistant.id ? 0.92 : 1)
      .animation({ duration: 180, curve: Curve.EaseOut })
      .onClick(() => {
        this.openAssistantSessions(assistant)
      })
    }
  }

  @Builder
  private AssistantJumpCardContent(assistant: Assistant, featured: boolean) {
    Column({ space: featured ? 12 : 10 }) {
      Row({ space: 12 }) {
        this.AssistantAvatarBadge(assistant.avatarSymbol, this.getAssistantAvatarColor(assistant), featured ? 48 : 44,
          featured ? 16 : 15, featured ? 25 : 23, assistant.defaultProviderId, assistant.defaultModelId,
          assistant.defaultModelName)

        Column({ space: 5 }) {
          Row({ space: 6 }) {
            Text(assistant.name)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            if (assistant.id === this.currentAssistantId) {
              this.AssistantStatusBadge($r('app.string.assistant_active_badge'), this.getAssistantAccentColor(assistant))
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.getAssistantDefaultModelText(assistant))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 5 }) {
          Row({ space: 3 }) {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(12)
              .fontColor([$r('app.color.text_tertiary')])
            Text(this.getAssistantSessionCount(assistant.id).toString())
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
          }
          .justifyContent(FlexAlign.End)

          this.AssistantRelativeTimeText(this.getAssistantLastChatTimestamp(assistant.id))
        }
        .width(74)
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        this.AssistantListMetaItem($r('app.string.assistant_prompt_label'), this.getAssistantPromptStateText(assistant))
        this.AssistantListMetaItem($r('app.string.assistant_temperature_override'), this.getAssistantTemperatureText(assistant))
      }
      .width('100%')

      Text(this.getAssistantPromptPreviewText(assistant))
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      this.AssistantCardActions(assistant)
    }
    .width('100%')
  }

  @Builder
  private AssistantCardActions(assistant: Assistant) {
    Row({ space: 8 }) {
      this.AssistantCardActionButton($r('sys.symbol.plus'), $r('app.string.new_chat'), true, (): void => {
        this.openAssistantNewChat(assistant)
      })

      this.AssistantCardActionButton($r('sys.symbol.message'), $r('app.string.assistant_view_chats'), false, (): void => {
        this.openAssistantSessions(assistant)
      })

      Button() {
        SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(40)
      .height(34)
      .borderRadius(17)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .stateEffect(false)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        materialColor: Color.Transparent,
        applyShadow: false,
        interactive: true,
        lightEffect: { color: undefined }
      }))
      .bindMenu(this.AssistantCardMoreMenu(assistant), {
        placement: Placement.BottomRight,
        offset: { x: 0, y: 8 },
        backgroundColor: this.themeSurface,
        backgroundBlurStyle: BlurStyle.Regular
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private AssistantCardActionButton(symbol: Resource, label: ResourceStr, primary: boolean, onTap: () => void) {
    Button() {
      Row({ space: 5 }) {
        SymbolGlyph(symbol)
          .fontSize(15)
          .fontColor([primary ? Color.White : this.themePrimary])

        Text(label)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(primary ? Color.White : this.themePrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width('100%')
    }
    .layoutWeight(1)
    .height(34)
    .borderRadius(17)
    .padding({ left: 10, right: 10 })
    .backgroundColor(primary ? this.themePrimary : this.themePrimaryLight)
    .stateEffect(false)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: primary ? this.themePrimary : this.themePrimaryLight,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .onClick(() => {
      onTap()
    })
  }

  @Builder
  private AssistantCardMoreMenu(assistant: Assistant) {
    Menu() {
      MenuItem({
        startIcon: $r('sys.symbol.square_and_pencil'),
        content: $r('app.string.edit_assistant_short')
      })
        .contentFont({ size: 14 })
        .onClick(() => {
          this.openAssistantEditor(assistant)
        })

      if (assistant.id !== DEFAULT_ASSISTANT_ID && !assistant.isDefault) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash'))
            .fontSize(16)
            .fontColor([$r('app.color.status_error')]),
          content: $r('app.string.delete')
        })
          .contentFont({ size: 14 })
          .contentFontColor($r('app.color.status_error'))
          .onClick(() => {
            this.deleteAssistantFromTab(assistant)
          })
      }
    }
  }

  @Builder
  private AssistantListMetaItem(label: ResourceStr, value: ResourceStr) {
    Row({ space: 4 }) {
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(value)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(28)
    .padding({ left: 10, right: 10 })
    .backgroundColor(Color.Transparent)
    .borderRadius(10)
    .border({ width: 0.5, color: this.themePrimaryLight })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: false
    }))
  }

  @Builder
  private AssistantRelativeTimeText(timestamp: number) {
    Row({ space: 0 }) {
      if (timestamp <= 0) {
        Text($r('app.string.assistant_no_chat_time'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else if (this.isJustNow(timestamp)) {
        Text($r('app.string.time_just_now'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else if (this.isMinutesAgo(timestamp)) {
        Text(this.getMinutesAgoValue(timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text($r('app.string.time_minutes_ago_suffix'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else if (this.isHoursAgo(timestamp)) {
        Text(this.getHoursAgoValue(timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text($r('app.string.time_hours_ago_suffix'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else if (this.isDaysAgo(timestamp)) {
        Text(this.getDaysAgoValue(timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text($r('app.string.time_days_ago_suffix'))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      } else {
        Text(this.formatDateMMDD(timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .justifyContent(FlexAlign.End)
  }

  @Builder
  private AssistantEditorSheetBuilder() {
    Column() {
      this.AssistantEditorHeader()

      Divider()
        .color($r('app.color.divider'))
        .margin({ left: 20, right: 20 })

      Scroll() {
        Row() {
          Column() {
            this.AssistantNameAvatarRow()

            Divider()
              .color($r('app.color.divider'))
              .margin({ left: 16, right: 16 })

            this.AssistantPromptEditor()

            Divider()
              .color($r('app.color.divider'))
              .margin({ left: 16, right: 16 })

            this.AssistantDefaultModelRow()

            Divider()
              .color($r('app.color.divider'))
              .margin({ left: 16, right: 16 })

            this.AssistantTemperatureRow()
          }
          .width('100%')
          .constraintSize({ maxWidth: 640 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ left: 16, right: 16, bottom: 28 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private AssistantEditorHeader() {
    ImmersiveSheetHeader({
      title: this.getAssistantEditorTitle(),
      showTrailing: true,
      trailingColor: this.themePrimary,
      onLeadingClick: (): void => {
        this.showAssistantEditorSheet = false
      },
      onTrailingClick: (): void => {
        this.saveAssistantEditor()
      }
    })
  }

  @Builder
  private AssistantAvatarBadge(symbol: string, color: string, size: number, radius: number, fontSize: number,
    modelProviderId: string = '', modelId: string = '', modelName: string = '', themedBorder: boolean = false) {
    Stack() {
      ForEach([this.getAssistantAvatarRenderKey(symbol, color, size, radius, fontSize, modelProviderId, modelId,
        modelName)], (_renderKey: string) => {
        AssistantAvatarView({
          value: symbol,
          color: color,
          avatarSize: size,
          radius: radius,
          fontSize: fontSize,
          cacheKey: this.assistantAvatarRenderTick,
          modelProviderId: modelProviderId,
          modelId: modelId,
          modelName: modelName
        })
      }, (renderKey: string) => renderKey)
    }
    .width(size)
    .height(size)
    .borderRadius(radius)
    .border({
      width: themedBorder ? 1 : 0,
      color: themedBorder ? this.themePrimaryLight : Color.Transparent
    })
  }

  @Builder
  private AssistantFormAvatarBadge(size: number, radius: number, fontSize: number) {
    Stack() {
      ForEach([this.getAssistantAvatarRenderKey(this.assistantFormAvatarSymbol, this.assistantFormColor, size, radius,
        fontSize, this.assistantFormDefaultProviderId, this.assistantFormDefaultModelId,
        this.assistantFormDefaultModelName)], (_renderKey: string) => {
        AssistantAvatarView({
          value: this.assistantFormAvatarSymbol,
          color: this.assistantFormColor,
          avatarSize: size,
          radius: radius,
          fontSize: fontSize,
          cacheKey: this.assistantAvatarRenderTick,
          modelProviderId: this.assistantFormDefaultProviderId,
          modelId: this.assistantFormDefaultModelId,
          modelName: this.assistantFormDefaultModelName
        })
      }, (renderKey: string) => renderKey)
    }
    .width(size)
    .height(size)
  }

  @Builder
  private AssistantNameAvatarRow() {
    Column({ space: 8 }) {
      Text($r('app.string.assistant_name'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Row({ space: 12 }) {
        TextInput({ text: this.assistantFormName, placeholder: $r('app.string.assistant_name_placeholder') })
          .layoutWeight(1)
          .height(52)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor(Color.Transparent)
          .borderRadius(16)
          .systemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
            materialColor: Color.Transparent,
            applyShadow: false
          }))
          .padding({ left: 14, right: 14 })
          .onChange((text: string) => {
            this.assistantFormName = text
          })

        Button() {
          this.AssistantFormAvatarBadge(60, 20, 34)
        }
        .width(60)
        .height(60)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(20)
        .stateEffect(false)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR,
          materialColor: Color.Transparent,
          applyShadow: false,
          interactive: true,
          lightEffect: { color: undefined }
        }))
        .onClick(() => {
          this.showAssistantAvatarEditorSheet = true
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
  }

  @Builder
  private AssistantAvatarEditorSheetBuilder() {
    AssistantAvatarEditorSheet({
      avatarValue: this.assistantFormAvatarSymbol,
      $avatarValue: (value: string): void => {
        this.setAssistantFormAvatarSymbol(value)
      },
      avatarColor: this.assistantFormColor !== '' ? this.assistantFormColor : this.themePrimary,
      $avatarColor: (value: string): void => {
        this.setAssistantFormAvatarColor(value)
      },
      defaultProviderId: this.assistantFormDefaultProviderId,
      defaultModelId: this.assistantFormDefaultModelId,
      defaultModelName: this.assistantFormDefaultModelName,
      onClose: (): void => {
        this.showAssistantAvatarEditorSheet = false
      }
    })
  }

  @Builder
  private AssistantPromptEditor() {
    Column({ space: 8 }) {
      Text($r('app.string.assistant_prompt'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      TextArea({ text: this.assistantFormSystemPrompt, placeholder: $r('app.string.assistant_prompt_placeholder') })
        .width('100%')
        .height(150)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: Color.Transparent,
          applyShadow: false
        }))
        .padding(14)
        .onChange((value: string) => {
          this.assistantFormSystemPrompt = value
        })
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
  }

  @Builder
  private AssistantDefaultModelRow() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text($r('app.string.assistant_default_model'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.getAssistantFormDefaultModelText())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.assistantFormDefaultModelId !== '') {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .backgroundColor(Color.Transparent)
        .stateEffect(false)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR,
          materialColor: Color.Transparent,
          applyShadow: false,
          interactive: true,
          lightEffect: { color: undefined }
        }))
        .onClick(() => {
          this.clearAssistantDefaultModel()
        })
      }

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 12, bottom: 12 })
    .backgroundColor(Color.Transparent)
    .borderRadius(16)
    .border({ width: 1, color: this.themePrimaryLight })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .margin({ top: 16, bottom: 16 })
    .onClick(() => {
      this.showAssistantModelSheet = true
      this.loadAssistantProvidersIfNeeded()
    })
  }

  @Builder
  private AssistantTemperatureRow() {
    Column({ space: 10 }) {
      Row() {
        Text($r('app.string.assistant_temperature_override'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.assistantFormTemperatureEnabled })
          .selectedColor(this.themePrimary)
          .systemMaterial(new uiMaterial.Material())
          .switchPointColor(Color.White)
          .onChange((value: boolean) => {
            this.assistantFormTemperatureEnabled = value
          })
      }
      .width('100%')

      if (this.assistantFormTemperatureEnabled) {
        Row({ space: 10 }) {
          Slider({ value: this.assistantFormTemperature, min: 0, max: 2, step: 0.1, style: SliderStyle.InSet })
            .layoutWeight(1)
            .systemMaterial(new uiMaterial.ImmersiveMaterial({
              style: uiMaterial.ImmersiveStyle.ULTRA_THIN
            }))
            .selectedColor(this.themePrimaryLight)
            .trackColor(Color.White)
            .blockColor(this.themePrimary)
            .blockBorderColor(this.themePrimary)
            .blockBorderWidth(1)
            .showSteps(false)
            .showTips(false)
            .onChange((value: number, _mode: SliderChangeMode) => {
              this.assistantFormTemperature = Math.round(value * 10) / 10
            })
          Text(this.assistantFormTemperature.toFixed(1))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width(34)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private AssistantModelSheetBuilder() {
    Column() {
      ImmersiveSheetHeader({
        title: $r('app.string.assistant_default_model'),
        onLeadingClick: (): void => {
          this.showAssistantModelSheet = false
        }
      })

      ModelSelectorContent({
        currentModelId: this.assistantFormDefaultModelId,
        currentProviderId: this.assistantFormDefaultProviderId,
        providers: this.assistantProviders,
        showEditEntry: false,
        showFavoriteActions: false,
        showFavoriteFilter: false,
        showClearSelectionOption: true,
        clearSelectionText: $r('app.string.assistant_model_follow_global'),
        emptyStateMode: 'settings',
        immersiveMaterial: true,
        narrowSearchBar: true,
        showImmersiveGroupBorder: true,
        onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
          this.selectAssistantDefaultModel(providerId, modelId, modelName)
        },
        onClearSelection: (): void => {
          this.clearAssistantDefaultModel()
          this.showAssistantModelSheet = false
        }
      })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private AssistantSwitchPill() {
    Stack() {
      ForEach([this.getCurrentAssistantSwitchRenderKey()], (_renderKey: string) => {
        Row({ space: 8 }) {
          Stack() {
            this.AssistantAvatarBadge(this.getCurrentAssistantSymbol(), this.getCurrentAssistantColor(), 36, 12, 20)
          }
          .width(36)
          .height(36)
          .borderRadius(12)
          .backgroundColor(Color.Transparent)
          .systemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
            materialColor: Color.Transparent,
            applyShadow: false,
            interactive: true,
            lightEffect: { color: undefined }
          }))

          Text(this.getCurrentAssistantName())
            .fontFamily(this.isManuscriptMode() ? MANUSCRIPT_HEADING_FONT : '')
            .fontSize(Index.TAB_TITLE_FONT_SIZE)
            .fontWeight(this.isManuscriptMode() ? 600 : FontWeight.Bold)
            .fontColor(this.isManuscriptMode() ? this.themePrimary : $r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: this.getAssistantSwitchNameMaxWidth() })

          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(13)
            .fontColor([this.isManuscriptMode() ? this.themePrimary : $r('app.color.text_secondary')])
        }
        .alignItems(VerticalAlign.Center)
      }, (renderKey: string) => renderKey)
    }
    .height(44)
    .padding({ left: 0, right: 10 })
    .constraintSize({ maxWidth: this.getAssistantSwitchMaxWidth() })
    .backgroundColor(Color.Transparent)
    .borderRadius(0)
    .border({ width: 0, color: Color.Transparent })
    .onClick(() => {
      this.showAssistantSwitchSheet = true
    })
    .transition(TransitionEffect.OPACITY.animation({
      duration: 200,
      curve: Curve.EaseOut
    }))
  }

  @Builder
  private AssistantSwitchSheetBuilder() {
    Column() {
      ImmersiveSheetHeader({
        title: $r('app.string.assistant_switch_title'),
        onLeadingClick: (): void => {
          this.showAssistantSwitchSheet = false
        }
      })

      if (this.assistants.length === 0) {
        Column() {
          IndexEmptyStateCard({
            icon: $r('sys.symbol.person'),
            title: $r('app.string.assistant_manage_title'),
            description: $r('app.string.loading')
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.assistants, (assistant: Assistant) => {
            ListItem({ style: ListItemStyle.NONE }) {
              this.AssistantSwitchSheetRow(assistant)
            }
          }, (assistant: Assistant) => this.getAssistantRenderKey(assistant))

          ListItem() {
            Column()
              .height(24)
          }
          .focusable(false)
          .selectable(false)
        }
        .width('100%')
        .height(0)
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 6 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(4)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private FloatingSearchPanel() {
    Row({ space: 8 }) {
      Search({ value: this.searchText, placeholder: $r('app.string.search_sessions_placeholder') })
        .id(this.searchInputFocusId)
        .layoutWeight(1)
        .height('100%')
        .backgroundColor(Color.Transparent)
        .borderRadius(this.isManuscriptMode() ? 0 : this.getFloatingSearchPanelHeight() / 2)
        .border({
          width: this.isManuscriptMode() ? { bottom: 1 } : 0,
          color: getAppUiState().themeTextSecondary
        })
        .searchIcon({ size: 0, color: Color.Transparent })
        .onChange((value: string) => {
          this.searchText = value
          this.refreshSessionListProjection()
        })
        .onSubmit((_value: string) => {
          try {
            this.getUIContext().getFocusController().clearFocus()
          } catch (error) {
          }
        })
        .onAppear(() => {
          this.scheduleSearchInputFocus(30)
        })

      Button({ type: this.isManuscriptMode() ? ButtonType.Normal : ButtonType.Circle,
        stateEffect: !this.isManuscriptMode() }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([this.themePrimary])
      }
      .width(36)
      .height(36)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .borderRadius(this.isManuscriptMode() ? 0 : 18)
      .border({ width: 0, color: Color.Transparent })
      .onClick(() => {
        try {
          this.getUIContext().getFocusController().clearFocus()
        } catch (error) {
        }
      })
    }
    .width(this.getFloatingSearchPanelWidth())
    .height(this.getFloatingSearchPanelHeight())
    .borderRadius(this.isManuscriptMode() ? 0 : this.getFloatingSearchPanelHeight() / 2)
    .clip(false)
    .padding({ left: 14, right: 10, top: 4, bottom: 4 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .systemMaterial(this.isManuscriptMode() ? undefined : new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: false,
      lightEffect: { color: undefined }
    }))
    .position({ x: '50%', y: this.getFloatingSearchPanelTop() })
    .translate({ x: '-50%' })
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -12 }))
        .animation({ duration: 180, curve: Curve.EaseOut }),
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 }))
        .animation({ duration: 120, curve: Curve.EaseIn })
    ))
    .zIndex(10)
  }

  @Builder
  private AssistantSwitchSheetRow(assistant: Assistant) {
    Row({ space: 12 }) {
      this.AssistantAvatarBadge(assistant.avatarSymbol, this.getAssistantAvatarColor(assistant), 42, 14, 22,
        assistant.defaultProviderId, assistant.defaultModelId, assistant.defaultModelName, true)

      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Text(assistant.name)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (assistant.id === this.currentAssistantId) {
            this.AssistantStatusBadge($r('app.string.assistant_active_badge'), this.getAssistantAccentColor(assistant))
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row({ space: 8 }) {
          Text(this.getAssistantDefaultModelText(assistant))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Row({ space: 3 }) {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(11)
              .fontColor([$r('app.color.text_tertiary')])
            Text(this.getAssistantSessionCount(assistant.id).toString())
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph(assistant.id === this.currentAssistantId ? $r('sys.symbol.checkmark_circle_fill') :
      $r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([assistant.id === this.currentAssistantId ? this.getAssistantAccentColor(assistant) :
        $r('app.color.text_tertiary')])
    }
    .width('100%')
    .constraintSize({ minHeight: 70 })
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(Color.Transparent)
    .borderRadius(16)
    .border({ width: 1, color: this.themePrimaryLight })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .onClick(() => {
      this.showAssistantSwitchSheet = false
      if (assistant.id !== this.currentAssistantId) {
        this.getUIContext().animateTo({
          duration: 180,
          curve: Curve.EaseOut
        }, () => {
          this.switchAssistant(assistant.id)
        })
      }
    })
  }

  @Builder
  private ManuscriptChatHeaderActions() {
    Row({ space: 0 }) {
      if (this.isMultiSelectMode) {
        ManuscriptTopArcButton({
          symbol: $r('sys.symbol.trash'),
          destructive: true,
          onTap: (): void => {
            this.handleDeleteSelectedSessions()
          }
        })
      } else {
        ManuscriptTopArcButton({
          symbol: $r('sys.symbol.creditcard'),
          onTap: (): void => {
            this.openBalanceSheet()
          }
        })

        ManuscriptTopArcButton({
          symbol: this.isFavoriteFilterActive() ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
          active: this.isFavoriteFilterActive(),
          onTap: (): void => {
            this.toggleFavoriteFilter()
          }
        })

        ManuscriptTopArcButton({
          symbol: $r('sys.symbol.magnifyingglass'),
          active: this.isSearchExpanded,
          onTap: (): void => {
            if (this.isSearchExpanded) {
              this.collapseSearch()
            } else {
              this.expandSearch()
            }
          }
        })
      }
    }
    .height(44)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ChatListHeaderMainRow() {
    if (!this.isMultiSelectMode) {
      Row() {
        this.AssistantSwitchPill()

        Blank()

        if (this.isManuscriptMode()) {
          this.ManuscriptChatHeaderActions()
        }
      }
      .width('100%')
      .height(Index.TAB_TITLE_BAR_HEIGHT)
      .padding({
        left: Index.TAB_TITLE_CONTENT_HORIZONTAL_PADDING,
        right: Index.TAB_TITLE_CONTENT_HORIZONTAL_PADDING
      })
      .alignItems(VerticalAlign.Center)
    } else {
      Row() {
        Text($r('app.string.select_conversations'))
          .fontSize(Index.TAB_TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Blank()

        if (this.isManuscriptMode()) {
          this.ManuscriptChatHeaderActions()
        }
      }
      .width('100%')
      .height(Index.TAB_TITLE_BAR_HEIGHT)
      .padding({
        left: Index.TAB_TITLE_CONTENT_HORIZONTAL_PADDING,
        right: Index.TAB_TITLE_CONTENT_HORIZONTAL_PADDING
      })
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  private ChatListPanelContent(topSpacerHeight: number = 0) {
    Column() {
      if (this.isLoading) {
        Column() {
          if (topSpacerHeight > 0) {
            Column()
              .width('100%')
              .height(topSpacerHeight)
          }

          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(this.themePrimary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.getAssistantScopedSessions().length === 0) {
        Column() {
          if (topSpacerHeight > 0) {
            Column()
              .width('100%')
              .height(topSpacerHeight)
          }

          IndexEmptyStateCard({
            icon: $r('sys.symbol.ellipsis_message'),
            title: $r('app.string.no_sessions'),
            description: $r('app.string.start_new_chat'),
            showButton: true,
            buttonText: $r('app.string.new_chat'),
            onButtonClick: (): void => {
              this.openChatRoute({} as ChatPageRouteParams)
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.filteredSessionCount === 0) {
        Column() {
          if (topSpacerHeight > 0) {
            Column()
              .width('100%')
              .height(topSpacerHeight)
          }

          if (this.searchText.trim() !== '') {
            IndexEmptyStateCard({
              icon: $r('sys.symbol.magnifyingglass'),
              title: $r('app.string.no_search_results'),
              description: $r('app.string.try_different_keyword')
            })
          } else {
            IndexEmptyStateCard({
              icon: $r('sys.symbol.heart'),
              title: $r('app.string.no_favorite_sessions'),
              description: $r('app.string.favorite_sessions_hint')
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Column() {
          IndexSessionListSection({
            horizontalPadding: Index.TAB_CONTENT_HORIZONTAL_PADDING,
            sessionGroups: this.sessionListGroups,
            sessionListScroller: this.sessionListScroller,
            isMultiSelectMode: this.isMultiSelectMode,
            topSpacerHeight: topSpacerHeight,
            bottomSpacerHeight: this.getSessionListBottomSpacerHeight(),
            showFavoriteFilterSummary: this.isFavoriteFilterActive(),
            favoriteFilterCountText: this.getFilterCountText(),
            onClearFavoriteFilter: (): void => {
              this.setSessionFilter(SessionFilterType.ALL)
            },
            onGetGroupTitle: (groupKey: string): Resource => {
              return this.getSessionGroupTitle(groupKey)
            },
            onToggleSelection: (sessionId: string): void => {
              this.handleSessionCardClick(sessionId)
            },
            onOpenSession: (session: ChatSession): void => {
              this.openChatRoute({
                sessionId: session.id,
                sessionTitle: session.title,
                modelId: session.modelId,
                providerId: session.providerId
              } as ChatPageRouteParams)
            },
            onDeleteSession: (sessionId: string): void => {
              this.deleteSession(sessionId)
            },
            onEnterMultiSelect: (sessionId: string): void => {
              this.handleEnterMultiSelectMode(sessionId)
            },
            onShareSession: (session: ChatSession): void => {
              this.handleShareSession(session)
            },
            onToggleFavorite: (session: ChatSession): void => {
              this.handleToggleFavoriteSession(session)
            }
          })
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(this.themeBackground)
  }

  @Builder
  private ChatListViewportContent() {
    Column() {
      this.ChatListPanelContent(this.getChatListTopSpacerHeight())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }

  @Builder
  private CompactChatListViewport() {
    Column() {
      this.ChatListViewportContent()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ChatListPanel() {
    if (this.isExpandedLayout()) {
      if (this.isMultiSelectMode) {
        Column() {
          this.ChatListViewportContent()
          MultiSelectToolbar({
            selectedCount: this.selectedSessionIds.length,
            totalCount: this.filteredSessionCount,
            onSelectAll: () => {
              this.handleSelectAllSessions()
            },
            onDelete: () => {
              this.handleDeleteSelectedSessions()
            },
            onShare: () => {
              this.handleShareSelectedSessions()
            },
            onCancel: () => {
              this.handleExitMultiSelectMode()
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.themeBackground)
      } else {
        Stack({ alignContent: Alignment.BottomEnd }) {
          this.ChatListViewportContent()
          if (this.isSearchExpanded) {
            this.FloatingSearchPanel()
          }
          this.FloatingActionButton()
        }
        .width('100%')
        .height('100%')
      }
    } else {
      if (this.isMultiSelectMode) {
        Stack({ alignContent: Alignment.Bottom }) {
          this.CompactChatListViewport()

          Column() {
            ChatMultiSelectToolbar({
              selectedCount: this.selectedSessionIds.length,
              totalCount: this.filteredSessionCount,
              onSelectAll: () => {
                this.handleSelectAllSessions()
              },
              onDelete: () => {
                this.handleDeleteSelectedSessions()
              },
              onShare: () => {
                this.handleShareSelectedSessions()
              },
              onCancel: () => {
                this.handleExitMultiSelectMode()
              }
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 12, right: 12, bottom: this.getCompactMultiSelectToolbarBottomInsetVp() })
          .position({ x: 0, y: '100%' })
          .translate({ y: '-100%', x: 0 })
          .hitTestBehavior(HitTestMode.Default)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.handleCompactMultiSelectToolbarAreaChange(newArea)
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.themeBackground)
      } else {
        Stack() {
          this.CompactChatListViewport()
          if (this.isSearchExpanded) {
            this.FloatingSearchPanel()
          }
        }
        .width('100%')
        .height('100%')
      }
    }
  }

  @Builder
  FloatingActionButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(24)
        .fontColor([Color.White])
    }
    .width(INDEX_NEW_CHAT_FAB_SIZE)
    .height(INDEX_NEW_CHAT_FAB_SIZE)
    .borderRadius(INDEX_NEW_CHAT_FAB_SIZE / 2)
    .backgroundColor(this.themePrimary)
    .type(ButtonType.Circle)
    .stateEffect(false)
    .padding(0)
    .clip(false)
    .position({ x: this.shouldPlaceFabOnLeft() ? 0 : '100%', y: '100%' })
    .translate({ x: this.getFabOffsetX(), y: this.getFabOffsetY() })
    .scale(getButtonScale(this.fabPressed))
    .animation({
      duration: 420,
      curve: curves.springMotion(0.75, 0.86)
    })
    .shadow({
      radius: this.fabPressed ? 20 : 14,
      color: this.fabShadowColor,
      offsetX: 0,
      offsetY: 8
    })
    .onTouch(createButtonTouchHandler((pressed: boolean) => {
      this.fabPressed = pressed
    }))
    .onClick(() => {
      this.fabPressed = false
      this.openChatRoute({} as ChatPageRouteParams)
    })
  }

  // 多选模式下点击防抖
  private isProcessingClick: boolean = false

  private handleSessionCardClick(sessionId: string): void {
    // 防止重复点击
    if (this.isProcessingClick) {
      return
    }
    this.isProcessingClick = true

    // 执行切换
    this.handleToggleSessionSelection(sessionId)

    // 100ms 后重置标志
    setTimeout(() => {
      this.isProcessingClick = false
    }, 100)
  }

  @Builder
  SettingsNavigationContent() {
    IndexSettingsPanel({
      sidebarMode: this.isSettingsSplitMode(),
      selectedRouteName: this.currentSettingsRouteName,
      highlightSelection: this.isSettingsSplitMode(),
      onOpenModelManage: (): void => {
        this.openSettingsDestination(SettingsRouteName.MODEL_MANAGE)
      },
      onOpenDefaultModel: (): void => {
        this.openSettingsDestination(SettingsRouteName.DEFAULT_MODEL)
      },
      onOpenToolsCenter: (): void => {
        this.openSettingsDestination(SettingsRouteName.TOOLS_CENTER)
      },
      onOpenSystemPrompt: (): void => {
        this.openSettingsDestination(SettingsRouteName.SYSTEM_PROMPT)
      },
      onOpenChatInput: (): void => {
        this.openSettingsPanelEntry(SettingsRouteName.CHAT_INPUT, SettingsSheetType.CHAT_INPUT)
      },
      onOpenTTS: (): void => {
        this.openSettingsDestination(SettingsRouteName.TTS)
      },
      onOpenHandAdaptive: (): void => {
        this.openSettingsPanelEntry(SettingsRouteName.HAND_ADAPTIVE, SettingsSheetType.HAND_ADAPTIVE)
      },
      onOpenTheme: (): void => {
        this.openSettingsDestination(SettingsRouteName.THEME_MODE)
      },
      onOpenLanguage: (): void => {
        this.openSettingsPanelEntry(SettingsRouteName.LANGUAGE, SettingsSheetType.LANGUAGE)
      },
      onOpenNotification: (): void => {
        this.openSettingsPanelEntry(SettingsRouteName.NOTIFICATION, SettingsSheetType.NOTIFICATION)
      },
      onOpenExportData: (): void => {
        this.openSettingsDestination(SettingsRouteName.EXPORT_DATA)
      },
      onOpenImportData: (): void => {
        this.openSettingsDestination(SettingsRouteName.IMPORT_DATA)
      },
      onOpenWebDAVSync: (): void => {
        this.openSettingsDestination(SettingsRouteName.WEBDAV_SYNC)
      },
      onOpenUsageStats: (): void => {
        this.openSettingsDestination(SettingsRouteName.USAGE_STATS)
      },
      onOpenAbout: (): void => {
        this.openSettingsDestination(SettingsRouteName.ABOUT)
      }
    })
  }

  @Builder
  private SettingsNavigationScrollableContent() {
    Scroll(this.settingsRootScroller) {
      Column() {
        Blank()
          .width('100%')
          .height(this.getSettingsListTopSpacerHeight())

        if (this.isManuscriptMode()) {
          ManuscriptPageTitle({
            title: $r('app.string.tab_settings'),
            subtitle: pickLocalizedText('偏好目录', 'INDEX OF PREFERENCES')
          })
        }

        this.SettingsNavigationContent()

        if (!this.isSettingsSplitMode()) {
          Blank()
            .width('100%')
            .height(this.getCompactTabsBottomInset() + 12)
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor(this.themeBackground)
  }

  @Builder
  private CompactSettingsTitleStackBuilder() {
    if (this.isManuscriptMode()) {
      Column()
        .width('100%')
        .height(Index.TAB_TITLE_BAR_HEIGHT)
    } else {
      Row() {
        Text($r('app.string.tab_settings'))
          .fontSize(Index.TAB_TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(Index.TAB_TITLE_BAR_HEIGHT)
      .padding({
        left: Index.TAB_TITLE_CONTENT_HORIZONTAL_PADDING,
        right: Index.TAB_TITLE_CONTENT_HORIZONTAL_PADDING
      })
      .alignItems(VerticalAlign.Center)
      .translate({ y: Index.TAB_TITLE_VERTICAL_OFFSET })
      .renderGroup(false)
    }
  }

  private getCompactSettingsTitleBarOptions(): HdsNavigationTitleBarOptions {
    const options = new HdsTopNavigationBlurOptions()
    options.startPaddingVp = Index.TAB_TITLE_BAR_HORIZONTAL_PADDING
    options.endPaddingVp = Index.TAB_TITLE_BAR_HORIZONTAL_PADDING
    options.materialType = this.materialType
    options.materialLevel = this.materialLevel
    options.windowWidthVp = this.windowWidthVp
    options.windowHeightVp = this.windowHeightVp
    options.maskExtraHeightVp = this.getCompactSettingsTitleBarMaskExtraHeight()
    options.blurEffectiveEndOffsetVp = getHdsTopNavigationBlurEffectiveEndOffset(this.windowWidthVp,
      this.windowHeightVp)
    options.stackBuilder = (): void => this.CompactSettingsTitleStackBuilder()
    return buildHdsTopNavigationTitleBarOptions(options)
  }

  @Builder
  private CompactSettingsRootContent() {
    Column() {
      Column() {
        this.SettingsNavigationScrollableContent()
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  private shouldIgnoreCompactSettingsTopSafeArea(): boolean {
    return true
  }

  private getCompactTabsBarHeight(): number {
    return Index.COMPACT_TABS_BAR_HEIGHT
  }

  @Builder
  SettingsTab() {
    if (this.isSettingsSplitMode()) {
      HdsNavigation(this.settingsNavPathStack) {
        this.SettingsNavigationScrollableContent()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themeBackground)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .titleBar(this.getCompactSettingsTitleBarOptions())
      .bindToScrollable([this.settingsRootScroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .systemBarStyle(
        { statusBarContentColor: getHdsStatusBarContentColor() },
        { statusBarContentColor: getHdsStatusBarContentColor() }
      )
      .mode(NavigationMode.Split)
      .navBarWidth(this.getExpandedSettingsListWidth())
      .hideBackButton(true)
      .hideToolBar(true)
      .onAppear(() => {
        this.ensureSettingsSplitLandingRoute()
      })
    } else {
      HdsNavigation(this.settingsNavPathStack) {
        this.CompactSettingsRootContent()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themeBackground)
      .titleBar(this.getCompactSettingsTitleBarOptions())
      .bindToScrollable([this.settingsRootScroller])
      .titleMode(HdsNavigationTitleMode.MINI)
      .systemBarStyle(
        { statusBarContentColor: getHdsStatusBarContentColor() },
        { statusBarContentColor: getHdsStatusBarContentColor() }
      )
      .ignoreLayoutSafeArea(
        [LayoutSafeAreaType.SYSTEM],
        this.shouldIgnoreCompactSettingsTopSafeArea() ? [LayoutSafeAreaEdge.TOP] : []
      )
      .mode(NavigationMode.Stack)
      .navBarWidth(this.windowWidthVp)
      .hideBackButton(true)
      .hideToolBar(true)
    }
  }

  private getActiveSettingsSheetHeight(): SheetSize {
    return SheetSize.FIT_CONTENT
  }

  @Builder
  SettingsSheetBuilder() {
    Column() {
      Column() {
        ImmersiveSheetHeader({
          title: getSettingsSheetTitleText(this.activeSettingsSheetType),
          leadingColor: this.themePrimary,
          onLeadingClick: (): void => {
            this.closeAllSettingsSheets()
          }
        })

        IndexSettingsSheetContent({
          settingsSheetType: this.activeSettingsSheetType,
          currentThemeMode: this.currentThemeMode,
          currentLanguage: this.currentLanguage,
          notifyEnabled: this.notifyEnabled,
          notifyOnComplete: this.notifyOnComplete,
          notifyOnFailed: this.notifyOnFailed,
          chatInputEnterKeySend: this.chatInputEnterKeySend,
          handAdaptiveEnabled: this.handAdaptiveEnabled,
          handAdaptiveNewChat: this.handAdaptiveNewChat,
          handAdaptiveUnsupported: this.handAdaptiveUnsupported,
          callbacks: this.buildSettingsSheetCallbacks()
        })
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .backgroundColor(Color.Transparent)
      .borderRadius({ topLeft: 28, topRight: 28, bottomLeft: 28, bottomRight: 28 })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  ThemeSheetBuilder() {
    IndexSettingsSheetContent({
      settingsSheetType: SettingsSheetType.THEME,
      currentThemeMode: this.currentThemeMode,
      currentLanguage: this.currentLanguage,
      notifyEnabled: this.notifyEnabled,
      notifyOnComplete: this.notifyOnComplete,
      notifyOnFailed: this.notifyOnFailed,
      chatInputEnterKeySend: this.chatInputEnterKeySend,
      handAdaptiveEnabled: this.handAdaptiveEnabled,
      handAdaptiveNewChat: this.handAdaptiveNewChat,
      handAdaptiveUnsupported: this.handAdaptiveUnsupported,
      callbacks: this.buildSettingsSheetCallbacks()
    })
  }

  @Builder
  NotificationSheetBuilder() {
    IndexSettingsSheetContent({
      settingsSheetType: SettingsSheetType.NOTIFICATION,
      currentThemeMode: this.currentThemeMode,
      currentLanguage: this.currentLanguage,
      notifyEnabled: this.notifyEnabled,
      notifyOnComplete: this.notifyOnComplete,
      notifyOnFailed: this.notifyOnFailed,
      chatInputEnterKeySend: this.chatInputEnterKeySend,
      handAdaptiveEnabled: this.handAdaptiveEnabled,
      handAdaptiveNewChat: this.handAdaptiveNewChat,
      handAdaptiveUnsupported: this.handAdaptiveUnsupported,
      callbacks: this.buildSettingsSheetCallbacks()
    })
  }

  @Builder
  HandAdaptiveSheetBuilder() {
    IndexSettingsSheetContent({
      settingsSheetType: SettingsSheetType.HAND_ADAPTIVE,
      currentThemeMode: this.currentThemeMode,
      currentLanguage: this.currentLanguage,
      notifyEnabled: this.notifyEnabled,
      notifyOnComplete: this.notifyOnComplete,
      notifyOnFailed: this.notifyOnFailed,
      chatInputEnterKeySend: this.chatInputEnterKeySend,
      handAdaptiveEnabled: this.handAdaptiveEnabled,
      handAdaptiveNewChat: this.handAdaptiveNewChat,
      handAdaptiveUnsupported: this.handAdaptiveUnsupported,
      callbacks: this.buildSettingsSheetCallbacks()
    })
  }

  private buildSettingsSheetCallbacks(): IndexSettingsSheetActionCallbacks {
    const callbacks = new IndexSettingsSheetActionCallbacks()
    callbacks.onSelectTheme = async (mode: ThemeMode): Promise<void> => {
      this.currentThemeMode = mode
      this.syncSettingsSummaryToStorage()
      this.closeAllSettingsSheets()
      try {
        await this.settingsManager.setThemeMode(mode)
      } catch (error) {
        console.error('Index', `Failed to set theme mode: ${JSON.stringify(error)}`)
        this.refreshSettingsState()
      }
    }
    callbacks.onSelectLanguage = async (language: AppLanguage): Promise<void> => {
      this.currentLanguage = language
      this.syncSettingsSummaryToStorage()
      this.closeAllSettingsSheets()
      try {
        await this.settingsManager.setLanguage(language)
      } catch (error) {
        console.error('Index', `Failed to set language: ${JSON.stringify(error)}`)
        this.refreshSettingsState()
      }
    }
    callbacks.onToggleHandAdaptiveEnabled = (value: boolean): void => {
      this.handleHandAdaptiveEnabledChanged(value)
    }
    callbacks.onToggleHandAdaptiveNewChat = (value: boolean): void => {
      this.handleHandAdaptiveNewChatChanged(value)
    }
    callbacks.onToggleNotifyEnabled = async (value: boolean): Promise<void> => {
      this.notifyEnabled = value
      this.syncSettingsSummaryToStorage()
      await this.settingsManager.setNotificationEnabled(value)
    }
    callbacks.onToggleNotifyOnComplete = async (value: boolean): Promise<void> => {
      this.notifyOnComplete = value
      this.syncSettingsSummaryToStorage()
      await this.settingsManager.setNotifyOnCompleteEnabled(value)
    }
    callbacks.onToggleNotifyOnFailed = async (value: boolean): Promise<void> => {
      this.notifyOnFailed = value
      this.syncSettingsSummaryToStorage()
      await this.settingsManager.setNotifyOnFailedEnabled(value)
    }
    callbacks.onToggleChatInputEnterKeySend = async (value: boolean): Promise<void> => {
      this.chatInputEnterKeySend = value
      this.syncSettingsSummaryToStorage()
      await this.settingsManager.setChatInputEnterKeySend(value)
    }
    callbacks.onOpenSystemNotificationSettings = (): void => {
      this.openSystemNotificationSettings()
    }
    return callbacks
  }

  // ========== 系统提示词 ==========

  private async openSystemPromptSheet(): Promise<void> {
    const saved = await this.preferencesService.getString(
      PreferenceKeys.CUSTOM_SYSTEM_PROMPT,
      SystemPromptTemplateDefaults.DEFAULT_TEMPLATE
    )
    this.customSystemPrompt = normalizeSystemPromptTemplate(saved)
    this.showSystemPromptSheet = true
  }

  private async saveSystemPrompt(): Promise<void> {
    const normalizedTemplate = normalizeSystemPromptTemplate(this.customSystemPrompt)
    this.customSystemPrompt = normalizedTemplate
    await this.preferencesService.setString(PreferenceKeys.CUSTOM_SYSTEM_PROMPT, normalizedTemplate)
    this.showIndexSnack($r('app.string.system_prompt_saved'), 2000, SnackBarTone.SUCCESS)
    this.showSystemPromptSheet = false
  }

  private resetSystemPrompt(): void {
    this.customSystemPrompt = SystemPromptTemplateDefaults.DEFAULT_TEMPLATE
  }

  @Builder
  SystemPromptSheetBuilder() {
    Column() {
      ImmersiveSheetHeader({
        title: $r('app.string.system_prompt_edit_title'),
        showTrailing: true,
        trailingColor: this.themePrimary,
        onLeadingClick: (): void => {
          this.showSystemPromptSheet = false
        },
        onTrailingClick: (): void => {
          this.saveSystemPrompt()
        }
      })

      Text($r('app.string.system_prompt_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 16, right: 16, bottom: 8 })
        .width('100%')

      Text($r('app.string.system_prompt_variables_hint'))
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .padding({ left: 16, right: 16, bottom: 12 })
        .width('100%')

      TextArea({ text: this.customSystemPrompt, placeholder: $r('app.string.system_prompt_placeholder') })
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor(Color.Transparent)
        .onChange((value: string) => {
          this.customSystemPrompt = value
        })

      Row() {
        Button($r('app.string.system_prompt_clear'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(this.themeSurface)
          .borderRadius(20)
          .height(40)
          .padding({ left: 18, right: 18 })
          .onClick(() => {
            this.resetSystemPrompt()
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 12, bottom: 12 + this.px2vp(this.bottomAvoidHeight) })
    }
    .width('100%')
    .height('100%')
  }

  // ========== 多选模式相关方法 ==========

  // 处理主题配色选择
  private async handleColorThemeSelected(theme: ColorTheme): Promise<void> {
    // 先本地更新，确保摘要先刷新，再持久化
    this.currentColorTheme = theme
    this.syncSettingsSummaryToStorage()
    this.closeAllSettingsSheets()
    try {
      await this.settingsManager.setColorTheme(theme)
      this.showIndexSnack($r('app.string.theme_switched'), 2000, SnackBarTone.SUCCESS)
    } catch (error) {
      console.error('Index', `Failed to set color theme: ${JSON.stringify(error)}`)
      this.refreshSettingsState()
    }
  }

  private async openSystemNotificationSettings(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await notificationManager.openNotificationSettings(context)
    } catch (error) {
      console.error('Index', `Failed to open notification settings: ${JSON.stringify(error)}`)
      this.showIndexSnack($r('app.string.notification_open_settings_failed'), 2000, SnackBarTone.ERROR)
    }
  }

  // 进入多选模式
  private handleEnterMultiSelectMode(sessionId: string): void {
    this.isMultiSelectMode = true
    this.selectedSessionIds = [sessionId]
    this.refreshSessionListProjection()
  }

  // 退出多选模式
  private handleExitMultiSelectMode(): void {
    this.isMultiSelectMode = false
    this.selectedSessionIds = []
    this.refreshSessionListProjection()
  }

  // 切换会话选中状态
  private handleToggleSessionSelection(sessionId: string): void {
    this.selectedSessionIds = toggleSelectionById(this.selectedSessionIds, sessionId)
    this.refreshSessionListProjection()
  }

  // 全选/取消全选
  private handleSelectAllSessions(): void {
    const filteredSessions = this.getFilteredSessions()
    if (filteredSessions.length === 0) {
      return
    }

    const filteredIds: string[] = []
    for (let i = 0; i < filteredSessions.length; i++) {
      filteredIds.push(filteredSessions[i].id)
    }
    const selectedFilteredCount = countSelectedIdsInCandidates(this.selectedSessionIds, filteredIds)

    if (selectedFilteredCount === filteredSessions.length) {
      this.selectedSessionIds = removeCandidateIds(this.selectedSessionIds, filteredIds)
    } else {
      this.selectedSessionIds = mergeSelectAllIds(this.selectedSessionIds, filteredIds)
    }
    this.refreshSessionListProjection()
  }

  private async handleToggleFavoriteSession(session: ChatSession): Promise<void> {
    const isFavorite = await this.chatViewModel.toggleSessionFavorite(session.id)
    session.isFavorite = isFavorite
    // 触发 sessions 的 @State 更新，确保 swipeAction 文案/图标立即按收藏状态重渲染
    this.sessions = [...this.sessions]
    this.refreshSessionListProjection()
    this.showIndexSnack(isFavorite ? $r('app.string.conversation_favorited') :
    $r('app.string.conversation_unfavorited'), 2000, SnackBarTone.SUCCESS)
    await this.loadSessions()
  }

  // 删除选中的会话
  private async handleDeleteSelectedSessions(): Promise<void> {
    if (this.selectedSessionIds.length === 0) {
      return
    }

    this.getUIContext().showAlertDialog({
      title: $r('app.string.delete_chat'),
      message: $r('app.string.delete_selected_conversations_confirm'),
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR
      }),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: '#FF3B30',
        action: async () => {
          // 批量删除
          for (let i = 0; i < this.selectedSessionIds.length; i++) {
            await this.chatViewModel.deleteSession(this.selectedSessionIds[i])
          }

          // 更新列表
          await this.loadSessions()

          // 退出多选模式
          this.handleExitMultiSelectMode()

          this.showIndexSnack($r('app.string.conversations_deleted'), 2000, SnackBarTone.SUCCESS)
        }
      }
    })
  }

  // 分享选中的会话
  private async handleShareSelectedSessions(): Promise<void> {
    if (this.selectedSessionIds.length === 0) {
      return
    }

    // 目前只支持单个会话分享，多个会话分享比较复杂
    if (this.selectedSessionIds.length > 1) {
      this.showIndexSnack($r('app.string.single_session_share_only'), 2000, SnackBarTone.ERROR)
      return
    }

    // 获取选中的会话
    const sessionId = this.selectedSessionIds[0]
    const session = this.sessions.find(s => s.id === sessionId)

    if (session === undefined) {
      return
    }

    // 加载会话消息
    const fullSession = await this.chatViewModel.loadSession(sessionId)
    if (fullSession === null || fullSession.messages.length === 0) {
      this.showIndexSnack($r('app.string.conversation_content_empty'), 2000, SnackBarTone.ERROR)
      return
    }

    // 设置分享消息并打开分享预览
    this.shareMessages = fullSession.messages
    this.showSharePreview = true
  }

  // 分享单个会话
  private async handleShareSession(session: ChatSession): Promise<void> {
    // 加载会话消息
    const fullSession = await this.chatViewModel.loadSession(session.id)
    if (fullSession === null || fullSession.messages.length === 0) {
      this.showIndexSnack($r('app.string.conversation_content_empty'), 2000, SnackBarTone.ERROR)
      return
    }

    // 设置分享消息并打开分享预览
    this.shareMessages = fullSession.messages
    this.showSharePreview = true
  }
}
