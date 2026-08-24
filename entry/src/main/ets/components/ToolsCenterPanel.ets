import { uiMaterial } from '@kit.ArkUI'
import { ToolConfig, SearchEngine, ToolSourceType } from '../models/ChatModels'
import { McpAuthType, McpServerConfig } from '../models/McpModels'
import { ToolRegistry } from '../services/ToolRegistry'
import { McpService } from '../services/McpService'
import { SkillConfig, SkillService } from '../services/SkillService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import {
  COMPACT_TOOL_ID,
  KNOWLEDGE_SEARCH_TOOL_ID,
  MODLENS_READ_IMAGE_TOOL_ID,
  registerBuiltinTools,
  SUB_AGENT_MESSAGE_TOOL_ID,
  SUB_AGENT_RESULT_TOOL_ID,
  USE_SKILL_TOOL_ID
} from '../config/BuiltinTools'
import { MODLENS_DEFAULT_GATEWAY_URL } from '../services/ModLensVisionService'
import { ContextCompactionService } from '../services/ContextCompactionService'
import {
  COMPACT_THRESHOLD_PERCENT_STEP,
  CONTEXT_LIMIT_TOKENS_STEP,
  DEFAULT_COMPACT_THRESHOLD_PERCENT,
  DEFAULT_CONTEXT_LIMIT_TOKENS,
  MAX_COMPACT_THRESHOLD_PERCENT,
  MAX_CONTEXT_LIMIT_TOKENS,
  MIN_COMPACT_THRESHOLD_PERCENT,
  MIN_CONTEXT_LIMIT_TOKENS,
  formatTokenCount
} from '../utils/ContextWindowUtils'
import { getPreferencesService, PreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { getAppUiState } from '../state/AppUiState'
import { formatLocalizedCount, pickLocalizedText } from '../utils/LocalizedTextUtils'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { ChatFloatingImmersiveButton } from './ChatFloatingImmersiveButton'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'
import { getLocalizedBuiltinToolDescription, getLocalizedBuiltinToolName } from '../utils/ToolDisplayTextUtils'
import {
  buildCustomHeadersJson,
  isSensitiveCustomHeaderName,
  normalizeCustomHeaderName,
  parseCustomHeaderEntries,
  validateCustomHeaderEntries
} from '../utils/CustomHeaderUtils'

@ObservedV2
class McpHeaderEntry {
  @Trace id: string = ''
  @Trace name: string = ''
  @Trace value: string = ''

  constructor(id: string = '', name: string = '', value: string = '') {
    this.id = id
    this.name = name
    this.value = value
  }
}

function createToolServiceCardMaterial(interactive: boolean = false): uiMaterial.Material {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
    materialColor: Color.Transparent,
    applyShadow: true,
    interactive: interactive,
    lightEffect: { color: undefined }
  })
}

@ComponentV2
export struct ToolsCenterPanel {
  @Param showHeader: boolean = true
  @Param contentBottomPadding: number = 24
  @Param contentTopPadding: number = 0
  @Param contentScroller: Scroller = new Scroller()
  @Local builtinTools: ToolConfig[] = []
  @Local searchServiceEnabled: boolean = false
  @Local searchEngine: SearchEngine = SearchEngine.BING
  @Local searchEngineSelectedIndex: number = 0
  @Local searchEngineDisplayValue: string = 'Bing(local)'
  @Local searchBraveApiKey: string = ''
  @Local searchTavilyApiKey: string = ''
  @Local searchTavilyBaseUrl: string = 'https://api.tavily.com'
  @Local searchExaApiKey: string = ''
  @Local searchExaBaseUrl: string = 'https://api.exa.ai'
  @Local searchBochaApiKey: string = ''
  @Local searchBochaBaseUrl: string = 'https://api.bochaai.com'
  @Local searchQueryOptimizationEnabled: boolean = false
  @Local isLoading: boolean = false
  @Local isRefreshingMcpServers: boolean = false
  @Local showSearchConfigSheet: boolean = false
  @Local showModLensConfigSheet: boolean = false
  @Local modLensGatewayUrl: string = ''
  @Local modLensGatewayToken: string = ''
  @Local modLensConnectionMessage: string = ''
  @Local modLensConnectionOk: boolean = false
  @Local isTestingModLens: boolean = false
  @Local isSavingModLens: boolean = false
  @Local enableModLensAfterSave: boolean = false
  @Local contextCompactEnabled: boolean = true
  @Local contextCompactThresholdPercent: number = DEFAULT_COMPACT_THRESHOLD_PERCENT
  @Local contextCompactMaxTokens: number = DEFAULT_CONTEXT_LIMIT_TOKENS
  @Local skillToolEnabled: boolean = false
  @Local skills: SkillConfig[] = []
  @Local showSkillConfigSheet: boolean = false
  @Local skillFormId: string = ''
  @Local skillFormName: string = ''
  @Local skillFormDescription: string = ''
  @Local skillFormContent: string = ''
  @Local skillFormEnabled: boolean = true
  @Local skillFormCreatedAt: number = 0
  @Local isSavingSkill: boolean = false
  @Local mcpServers: McpServerConfig[] = []
  @Local showMcpServerSheet: boolean = false
  @Local editingMcpServerId: string = ''
  @Local mcpFormName: string = ''
  @Local mcpFormBaseUrl: string = ''
  @Local mcpFormAuthToken: string = ''
  @Local mcpFormCustomHeadersJson: string = ''
  @Local mcpFormCustomHeaderEntries: McpHeaderEntry[] = []
  @Local showMcpCustomHeadersEditor: boolean = false
  @Local mcpFormEnabled: boolean = true
  @Local mcpFormAuthType: string = McpAuthType.NONE
  @Local mcpAuthTypeSelectedIndex: number = 0
  @Local isSavingMcpServer: boolean = false
  @Local selectedToolIds: string[] = []

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private toolRegistry: ToolRegistry = ServiceRegistry.toolRegistry()
  private mcpService: McpService = ServiceRegistry.mcp()
  private skillService: SkillService = ServiceRegistry.skill()
  private preferencesService: PreferencesService = getPreferencesService()
  private readonly searchToolId: string = 'web_search'
  private readonly searchEngineOptions: Array<SelectOption> = [
    { value: 'Bing(local)' },
    { value: 'Brave Search' },
    { value: 'Tavily' },
    { value: 'Exa' },
    { value: '博查(Bocha)' }
  ]
  private readonly mcpAuthTypeOptions: Array<SelectOption> = [
    { value: 'None' },
    { value: 'Bearer' }
  ]
  private readonly reservedMcpHeaderNames: string[] = [
    'content-type',
    'accept',
    'mcp-protocol-version',
    'mcp-session-id',
    'authorization'
  ]
  private originalSearchEngine: SearchEngine = SearchEngine.BING
  private originalSearchBraveApiKey: string = ''
  private originalSearchTavilyApiKey: string = ''
  private originalSearchTavilyBaseUrl: string = 'https://api.tavily.com'
  private originalSearchExaApiKey: string = ''
  private originalSearchExaBaseUrl: string = 'https://api.exa.ai'
  private originalSearchBochaApiKey: string = ''
  private originalSearchBochaBaseUrl: string = 'https://api.bochaai.com'
  private originalSearchQueryOptimizationEnabled: boolean = false

  private showToolsSnack(message: string | Resource, duration: number = 2000,
    tone: SnackBarTone = SnackBarTone.DEFAULT): void {
    const options: SnackBarDisplayOptions = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  aboutToAppear(): void {
    this.loadData()
  }

  private syncBuiltinToolsFromRegistry(): void {
    const allTools = this.toolRegistry.getAllToolConfigs()
    const builtin: ToolConfig[] = []
    for (let i = 0; i < allTools.length; i++) {
      // 联网搜索、Skill、上下文压缩各有独立卡片；知识库只在知识库页管理；
      // sub_agent_result/sub_agent_message 随 sub_agent 一起曝光，不单独开关
      if (allTools[i].sourceType === ToolSourceType.BUILTIN && allTools[i].id !== this.searchToolId &&
        allTools[i].id !== USE_SKILL_TOOL_ID && allTools[i].id !== KNOWLEDGE_SEARCH_TOOL_ID &&
        allTools[i].id !== COMPACT_TOOL_ID && allTools[i].id !== SUB_AGENT_RESULT_TOOL_ID &&
        allTools[i].id !== SUB_AGENT_MESSAGE_TOOL_ID) {
        builtin.push(allTools[i])
      }
    }
    this.builtinTools = builtin
  }

  private async loadSelectedToolIds(): Promise<void> {
    this.selectedToolIds = [...await this.mcpService.loadSelectedToolIds()]
  }

  private isToolSelected(toolId: string): boolean {
    return this.selectedToolIds.includes(toolId)
  }

  private handleToolSelectionChanged(toolId: string, enabled: boolean): void {
    const previousToolIds = [...this.selectedToolIds]
    const nextToolIds = [...this.selectedToolIds]
    const index = nextToolIds.indexOf(toolId)
    if (enabled && index < 0) {
      nextToolIds.push(toolId)
    }
    if (!enabled && index >= 0) {
      nextToolIds.splice(index, 1)
    }
    this.selectedToolIds = nextToolIds
    this.mcpService.saveSelectedToolIds(nextToolIds)
      .then((savedToolIds: string[]): void => {
        this.selectedToolIds = [...savedToolIds]
      })
      .catch((error: Object): void => {
        this.selectedToolIds = previousToolIds
        console.error('ToolsCenterPanel', `Failed to save selected tools: ${JSON.stringify(error)}`)
        this.showToolsSnack(pickLocalizedText('工具选择保存失败', 'Failed to save tool selection'),
          2000, SnackBarTone.ERROR)
      })
  }

  private handleBuiltinToolSelectionChanged(toolId: string, enabled: boolean): void {
    if (toolId === MODLENS_READ_IMAGE_TOOL_ID && enabled && this.modLensGatewayUrl.trim() === '') {
      this.enableModLensAfterSave = true
      this.modLensConnectionMessage = ''
      this.showModLensConfigSheet = true
      return
    }
    this.handleToolSelectionChanged(toolId, enabled)
  }

  private openModLensConfig(): void {
    this.enableModLensAfterSave = false
    this.modLensConnectionMessage = ''
    this.showModLensConfigSheet = true
  }

  private async loadModLensConfig(): Promise<void> {
    const config = await ServiceRegistry.modLensVision().loadConfig()
    this.modLensGatewayUrl = config.endpoint
    this.modLensGatewayToken = config.token
  }

  private handleTestModLensConnection(): void {
    if (this.isTestingModLens) {
      return
    }
    this.isTestingModLens = true
    this.modLensConnectionMessage = ''
    ServiceRegistry.modLensVision().testConnection(this.modLensGatewayUrl, this.modLensGatewayToken)
      .then((result): void => {
        this.modLensConnectionOk = result.ok
        this.modLensConnectionMessage = result.message
      })
      .catch((error: Object): void => {
        this.modLensConnectionOk = false
        this.modLensConnectionMessage = `连接失败: ${JSON.stringify(error)}`
      })
      .finally((): void => {
        this.isTestingModLens = false
      })
  }

  private handleSaveModLensConfig(): void {
    if (this.isSavingModLens) {
      return
    }
    this.isSavingModLens = true
    ServiceRegistry.modLensVision().saveConfig(this.modLensGatewayUrl, this.modLensGatewayToken)
      .then((config): void => {
        this.modLensGatewayUrl = config.endpoint
        this.modLensGatewayToken = config.token
        if (this.enableModLensAfterSave) {
          this.handleToolSelectionChanged(MODLENS_READ_IMAGE_TOOL_ID, true)
        }
        this.enableModLensAfterSave = false
        this.showModLensConfigSheet = false
        this.showToolsSnack(pickLocalizedText('ModLens 配置已保存', 'ModLens configuration saved'),
          2000, SnackBarTone.SUCCESS)
      })
      .catch((error: Object): void => {
        this.showToolsSnack(`${error}`, 2200, SnackBarTone.ERROR)
      })
      .finally((): void => {
        this.isSavingModLens = false
      })
  }

  private async loadContextCompactSettings(): Promise<void> {
    const compactionService = ContextCompactionService.getInstance()
    await compactionService.loadPreferences()
    this.contextCompactEnabled = compactionService.isEnabled()
    this.contextCompactThresholdPercent = compactionService.getThresholdPercent()
    this.contextCompactMaxTokens = compactionService.getMaxContextTokens()
  }

  private handleContextCompactEnabledChanged(enabled: boolean): void {
    this.contextCompactEnabled = enabled
    const compactTool = this.toolRegistry.getTool(COMPACT_TOOL_ID)
    if (compactTool !== undefined) {
      compactTool.config.enabled = enabled
    }
    this.handleToolSelectionChanged(COMPACT_TOOL_ID, enabled)
    ContextCompactionService.getInstance().setEnabled(enabled)
      .catch((error: Object): void => {
        console.error('ToolsCenterPanel', `Failed to save compact enabled state: ${JSON.stringify(error)}`)
        this.showToolsSnack(pickLocalizedText('保存失败，请重试', 'Failed to save, please try again'))
      })
  }

  private handleContextCompactThresholdChanged(percent: number): void {
    this.contextCompactThresholdPercent = percent
    ContextCompactionService.getInstance().setThresholdPercent(percent)
      .then((): void => {
        this.contextCompactThresholdPercent = ContextCompactionService.getInstance().getThresholdPercent()
      })
      .catch((error: Object): void => {
        console.error('ToolsCenterPanel', `Failed to save compact threshold: ${JSON.stringify(error)}`)
        this.showToolsSnack(pickLocalizedText('保存失败，请重试', 'Failed to save, please try again'))
      })
  }

  private handleContextCompactMaxTokensChanged(tokens: number): void {
    this.contextCompactMaxTokens = tokens
    ContextCompactionService.getInstance().setMaxContextTokens(tokens)
      .then((): void => {
        this.contextCompactMaxTokens = ContextCompactionService.getInstance().getMaxContextTokens()
      })
      .catch((error: Object): void => {
        console.error('ToolsCenterPanel', `Failed to save compact max tokens: ${JSON.stringify(error)}`)
        this.showToolsSnack(pickLocalizedText('保存失败，请重试', 'Failed to save, please try again'))
      })
  }

  private async loadData(): Promise<void> {
    this.isLoading = true

    registerBuiltinTools()
    this.syncBuiltinToolsFromRegistry()
    try {
      await this.loadToolEnabledStates()
      await this.loadSelectedToolIds()
      await this.loadModLensConfig()
      await this.loadSearchSettings()
      await this.loadContextCompactSettings()
      await this.loadSkills()
      await this.loadMcpServers()
      this.syncBuiltinToolsFromRegistry()
    } finally {
      this.isLoading = false
    }
    this.refreshMcpServersInBackground(false)
  }

  private async loadMcpServers(): Promise<void> {
    const configs = await this.mcpService.loadServerConfigs()
    this.applyMcpServerConfigsToLocal(configs)
  }

  private syncMcpServerProperties(target: McpServerConfig, source: McpServerConfig): void {
    target.name = source.name
    target.baseUrl = source.baseUrl
    target.enabled = source.enabled
    target.authType = source.authType
    target.authToken = source.authToken
    target.customHeadersJson = source.customHeadersJson
  }

  private applyMcpServerConfigsToLocal(configs: McpServerConfig[]): void {
    if (this.mcpServers.length === 0) {
      this.mcpServers = [...configs]
      return
    }

    const configMap = new Map<string, McpServerConfig>()
    for (let i = 0; i < configs.length; i++) {
      configMap.set(configs[i].id, configs[i])
    }

    for (let i = 0; i < this.mcpServers.length; i++) {
      const existing = this.mcpServers[i]
      const updated = configMap.get(existing.id)
      if (updated !== undefined && updated !== existing) {
        this.syncMcpServerProperties(existing, updated)
      }
    }

    let needsRebuild = configs.length !== this.mcpServers.length
    if (!needsRebuild) {
      for (let i = 0; i < configs.length; i++) {
        if (configs[i].id !== this.mcpServers[i].id) {
          needsRebuild = true
          break
        }
      }
    }

    if (needsRebuild) {
      this.mcpServers = [...configs]
      return
    }

    this.mcpServers = [...this.mcpServers]
  }

  private findLocalMcpServerById(serverId: string): McpServerConfig | null {
    for (let i = 0; i < this.mcpServers.length; i++) {
      if (this.mcpServers[i].id === serverId) {
        return this.mcpServers[i]
      }
    }
    return null
  }

  private updateLocalMcpServerEnabledState(serverId: string, enabled: boolean): void {
    const server = this.findLocalMcpServerById(serverId)
    if (server === null) {
      return
    }
    server.enabled = enabled
    this.mcpServers = [...this.mcpServers]
  }

  private refreshMcpServersInBackground(showErrorSnack: boolean): void {
    if (this.isRefreshingMcpServers) {
      return
    }
    this.isRefreshingMcpServers = true
    this.performRefreshAllMcpServers(showErrorSnack).finally(() => {
      this.isRefreshingMcpServers = false
    })
  }

  private async performRefreshAllMcpServers(showErrorSnack: boolean): Promise<void> {
    try {
      await this.mcpService.refreshAllServers()
      await this.loadMcpServers()
    } catch (error) {
      console.warn('ToolsCenterPanel', `MCP refresh failed during load: ${JSON.stringify(error)}`)
      if (showErrorSnack) {
        this.showToolsSnack(this.getMcpRefreshFailedMessage(error), 2500, SnackBarTone.ERROR)
      }
    } finally {
      this.syncBuiltinToolsFromRegistry()
    }
  }

  private getEnabledMcpServerCount(): number {
    let count = 0
    for (let i = 0; i < this.mcpServers.length; i++) {
      if (this.mcpServers[i].enabled) {
        count += 1
      }
    }
    return count
  }

  private getDiscoveredMcpToolCount(): number {
    let total = 0
    for (let i = 0; i < this.mcpServers.length; i++) {
      total += this.getServerTools(this.mcpServers[i].id).length
    }
    return total
  }

  private parseSearchEngine(raw: string): SearchEngine {
    if (raw === SearchEngine.BRAVE) {
      return SearchEngine.BRAVE
    }
    if (raw === SearchEngine.TAVILY) {
      return SearchEngine.TAVILY
    }
    if (raw === SearchEngine.EXA) {
      return SearchEngine.EXA
    }
    if (raw === SearchEngine.BOCHA) {
      return SearchEngine.BOCHA
    }
    return SearchEngine.BING
  }

  private getSearchEngineLabel(engine: SearchEngine): string {
    if (engine === SearchEngine.BRAVE) {
      return 'Brave Search'
    }
    if (engine === SearchEngine.TAVILY) {
      return 'Tavily'
    }
    if (engine === SearchEngine.EXA) {
      return 'Exa'
    }
    if (engine === SearchEngine.BOCHA) {
      return '博查(Bocha)'
    }
    return 'Bing(local)'
  }

  private getSearchEngineByIndex(index: number): SearchEngine {
    if (index === 1) {
      return SearchEngine.BRAVE
    }
    if (index === 2) {
      return SearchEngine.TAVILY
    }
    if (index === 3) {
      return SearchEngine.EXA
    }
    if (index === 4) {
      return SearchEngine.BOCHA
    }
    return SearchEngine.BING
  }

  private getSearchEngineSelectedIndex(engine: SearchEngine): number {
    if (engine === SearchEngine.BRAVE) {
      return 1
    }
    if (engine === SearchEngine.TAVILY) {
      return 2
    }
    if (engine === SearchEngine.EXA) {
      return 3
    }
    if (engine === SearchEngine.BOCHA) {
      return 4
    }
    return 0
  }

  private applySearchServiceEnabledState(enabled: boolean): void {
    this.searchServiceEnabled = enabled
    const registeredTool = this.toolRegistry.getTool(this.searchToolId)
    if (registeredTool !== undefined) {
      registeredTool.config.enabled = enabled
    }
  }

  private async loadToolEnabledStates(): Promise<void> {
    const webSearchEnabled = await this.preferencesService.getBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, false)
    this.applySearchServiceEnabledState(webSearchEnabled)
    const skillEnabled = await this.skillService.isToolEnabled()
    this.applySkillToolEnabledState(skillEnabled)
  }

  private handleSearchServiceEnabledChanged(enabled: boolean): void {
    this.applySearchServiceEnabledState(enabled)
    this.preferencesService.setBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, enabled)
    this.preferencesService.setBoolean(PreferenceKeys.SEARCH_CONVERSATION_ENABLED, enabled)
    this.handleToolSelectionChanged(this.searchToolId, enabled)
  }

  private applySkillToolEnabledState(enabled: boolean): void {
    this.skillToolEnabled = enabled
    const registeredTool = this.toolRegistry.getTool(USE_SKILL_TOOL_ID)
    if (registeredTool !== undefined) {
      registeredTool.config.enabled = enabled
    }
  }

  private async loadSkills(): Promise<void> {
    this.skills = [...await this.skillService.loadSkills()]
  }

  private getEnabledSkillCount(): number {
    let count = 0
    for (let i = 0; i < this.skills.length; i++) {
      if (this.skills[i].enabled) {
        count += 1
      }
    }
    return count
  }

  private handleSkillToolEnabledChanged(enabled: boolean): void {
    this.applySkillToolEnabledState(enabled)
    this.skillService.setToolEnabled(enabled).catch((error: Object): void => {
      console.error('ToolsCenterPanel', `Failed to save skill tool state: ${JSON.stringify(error)}`)
      this.applySkillToolEnabledState(!enabled)
      this.showToolsSnack(pickLocalizedText('保存 Skill 工具状态失败', 'Failed to save Skill tool state'),
        2000, SnackBarTone.ERROR)
    })
    this.handleToolSelectionChanged(USE_SKILL_TOOL_ID, enabled)
  }

  private resetSkillForm(): void {
    this.skillFormId = ''
    this.skillFormName = ''
    this.skillFormDescription = ''
    this.skillFormContent = ''
    this.skillFormEnabled = true
    this.skillFormCreatedAt = 0
    this.isSavingSkill = false
  }

  private openCreateSkill(): void {
    this.resetSkillForm()
    this.showSkillConfigSheet = true
  }

  private openEditSkill(skill: SkillConfig): void {
    this.skillFormId = skill.id
    this.skillFormName = skill.name
    this.skillFormDescription = skill.description
    this.skillFormContent = skill.content
    this.skillFormEnabled = skill.enabled
    this.skillFormCreatedAt = skill.createdAt
    this.showSkillConfigSheet = true
  }

  private isEditingSkill(): boolean {
    return this.skillFormId.trim() !== ''
  }

  private getSkillFormTitle(): string {
    return this.isEditingSkill()
      ? pickLocalizedText('编辑 Skill', 'Edit Skill')
      : pickLocalizedText('新增 Skill', 'Add Skill')
  }

  private getSkillFormHeroTitle(): string {
    const name = this.skillFormName.trim()
    return name !== '' ? name : pickLocalizedText('未命名 Skill', 'Untitled Skill')
  }

  private buildSkillIdFromName(name: string): string {
    return this.skillService.buildNewSkillId(name)
  }

  private findSkillIndex(skills: SkillConfig[], skillId: string): number {
    for (let i = 0; i < skills.length; i++) {
      if (skills[i].id === skillId) {
        return i
      }
    }
    return -1
  }

  private async handleSaveSkill(): Promise<void> {
    if (this.isSavingSkill) {
      return
    }
    const name = this.skillFormName.trim()
    const content = this.skillFormContent
    if (name === '') {
      this.showToolsSnack(pickLocalizedText('Skill 名称不能为空', 'Skill name is required'),
        2000, SnackBarTone.ERROR)
      return
    }
    if (content.trim() === '') {
      this.showToolsSnack(pickLocalizedText('SKILL.md 正文不能为空', 'SKILL.md content is required'),
        2000, SnackBarTone.ERROR)
      return
    }
    this.isSavingSkill = true
    try {
      const now = Date.now()
      const skills = await this.skillService.loadSkills()
      const targetId = this.isEditingSkill() ? this.skillFormId : this.buildSkillIdFromName(name)
      const index = this.findSkillIndex(skills, targetId)
      const createdAt = this.skillFormCreatedAt > 0 ? this.skillFormCreatedAt : now
      const nextSkill = new SkillConfig(
        targetId,
        name,
        this.skillFormDescription.trim(),
        content,
        this.skillFormEnabled,
        createdAt,
        now
      )
      if (index >= 0) {
        skills[index] = nextSkill
      } else {
        skills.push(nextSkill)
      }
      await this.skillService.saveSkills(skills)
      this.skills = [...skills]
      this.showSkillConfigSheet = false
      this.showToolsSnack(pickLocalizedText('Skill 已保存', 'Skill saved'), 2000, SnackBarTone.SUCCESS)
    } catch (error) {
      console.error('ToolsCenterPanel', `Failed to save skill: ${JSON.stringify(error)}`)
      this.showToolsSnack(pickLocalizedText('保存 Skill 失败', 'Failed to save Skill'),
        2000, SnackBarTone.ERROR)
    } finally {
      this.isSavingSkill = false
    }
  }

  private updateSkillEnabled(skillId: string, enabled: boolean): void {
    this.performUpdateSkillEnabled(skillId, enabled).catch((error: Object): void => {
      console.error('ToolsCenterPanel', `Failed to update skill state: ${JSON.stringify(error)}`)
      this.showToolsSnack(pickLocalizedText('更新 Skill 状态失败', 'Failed to update Skill state'),
        2000, SnackBarTone.ERROR)
    })
  }

  private async performUpdateSkillEnabled(skillId: string, enabled: boolean): Promise<void> {
    const skills = await this.skillService.loadSkills()
    const index = this.findSkillIndex(skills, skillId)
    if (index < 0) {
      return
    }
    skills[index].enabled = enabled
    skills[index].updatedAt = Date.now()
    await this.skillService.saveSkills(skills)
    this.skills = [...skills]
  }

  private handleDeleteSkill(skillId: string): void {
    this.getUIContext().showAlertDialog({
      title: pickLocalizedText('删除 Skill', 'Delete Skill'),
      message: pickLocalizedText('删除后模型将无法再读取该 Skill。', 'The model will no longer be able to read it.'),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: Color.Red,
        action: () => {
          this.deleteSkill(skillId)
        }
      }
    })
  }

  private deleteSkill(skillId: string): void {
    this.performDeleteSkill(skillId).catch((error: Object): void => {
      console.error('ToolsCenterPanel', `Failed to delete skill: ${JSON.stringify(error)}`)
      this.showToolsSnack(pickLocalizedText('删除 Skill 失败', 'Failed to delete Skill'),
        2000, SnackBarTone.ERROR)
    })
  }

  private async performDeleteSkill(skillId: string): Promise<void> {
    const skills = await this.skillService.loadSkills()
    const nextSkills: SkillConfig[] = []
    for (let i = 0; i < skills.length; i++) {
      if (skills[i].id !== skillId) {
        nextSkills.push(skills[i])
      }
    }
    await this.skillService.saveSkills(nextSkills)
    this.skills = [...nextSkills]
    this.showToolsSnack(pickLocalizedText('Skill 已删除', 'Skill deleted'), 2000, SnackBarTone.SUCCESS)
  }

  private async loadSearchSettings(): Promise<void> {
    const searchServiceEnabled = await this.preferencesService.getBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, false)
    const engineRaw = await this.preferencesService.getString(PreferenceKeys.SEARCH_ENGINE, SearchEngine.BING)
    const braveApiKey = await this.preferencesService.getString(PreferenceKeys.SEARCH_BRAVE_API_KEY, '')
    const tavilyApiKey = await this.preferencesService.getString(PreferenceKeys.SEARCH_TAVILY_API_KEY, '')
    const tavilyBaseUrl =
      await this.preferencesService.getString(PreferenceKeys.SEARCH_TAVILY_BASE_URL, 'https://api.tavily.com')
    const exaApiKey = await this.preferencesService.getString(PreferenceKeys.SEARCH_EXA_API_KEY, '')
    const exaBaseUrl = await this.preferencesService.getString(PreferenceKeys.SEARCH_EXA_BASE_URL, 'https://api.exa.ai')
    const bochaApiKey = await this.preferencesService.getString(PreferenceKeys.SEARCH_BOCHA_API_KEY, '')
    const bochaBaseUrl =
      await this.preferencesService.getString(PreferenceKeys.SEARCH_BOCHA_BASE_URL, 'https://api.bochaai.com')
    const optimizationEnabled = await this.preferencesService.getBoolean(
      PreferenceKeys.SEARCH_QUERY_OPTIMIZATION_ENABLED,
      false
    )

    this.searchServiceEnabled = searchServiceEnabled
    this.searchEngine = this.parseSearchEngine(engineRaw)
    this.searchEngineSelectedIndex = this.getSearchEngineSelectedIndex(this.searchEngine)
    this.searchEngineDisplayValue = this.getSearchEngineLabel(this.searchEngine)
    this.searchBraveApiKey = braveApiKey.trim()
    this.searchTavilyApiKey = tavilyApiKey.trim()
    this.searchTavilyBaseUrl = this.normalizeSearchBaseUrl(tavilyBaseUrl, 'https://api.tavily.com')
    this.searchExaApiKey = exaApiKey
    this.searchExaBaseUrl = this.normalizeSearchBaseUrl(exaBaseUrl, 'https://api.exa.ai')
    this.searchBochaApiKey = bochaApiKey
    this.searchBochaBaseUrl = this.normalizeSearchBaseUrl(bochaBaseUrl, 'https://api.bochaai.com')
    this.searchQueryOptimizationEnabled = optimizationEnabled
    this.syncOriginalSearchSettings()
  }

  private normalizeSearchBaseUrl(raw: string, fallback: string): string {
    const trimmed = raw.trim()
    if (trimmed === '') {
      return fallback
    }
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1)
    }
    return trimmed
  }

  private syncOriginalSearchSettings(): void {
    this.originalSearchEngine = this.searchEngine
    this.originalSearchBraveApiKey = this.searchBraveApiKey.trim()
    this.originalSearchTavilyApiKey = this.searchTavilyApiKey.trim()
    this.originalSearchTavilyBaseUrl =
      this.normalizeSearchBaseUrl(this.searchTavilyBaseUrl, 'https://api.tavily.com')
    this.originalSearchExaApiKey = this.searchExaApiKey.trim()
    this.originalSearchExaBaseUrl = this.normalizeSearchBaseUrl(this.searchExaBaseUrl, 'https://api.exa.ai')
    this.originalSearchBochaApiKey = this.searchBochaApiKey.trim()
    this.originalSearchBochaBaseUrl = this.normalizeSearchBaseUrl(this.searchBochaBaseUrl, 'https://api.bochaai.com')
    this.originalSearchQueryOptimizationEnabled = this.searchQueryOptimizationEnabled
  }

  private hasPendingSearchConfigChanges(): boolean {
    if (this.searchEngine !== this.originalSearchEngine) {
      return true
    }
    if (this.searchBraveApiKey.trim() !== this.originalSearchBraveApiKey) {
      return true
    }
    if (this.searchTavilyApiKey.trim() !== this.originalSearchTavilyApiKey) {
      return true
    }
    if (this.normalizeSearchBaseUrl(this.searchTavilyBaseUrl, 'https://api.tavily.com') !==
      this.originalSearchTavilyBaseUrl) {
      return true
    }
    if (this.searchExaApiKey.trim() !== this.originalSearchExaApiKey) {
      return true
    }
    if (this.normalizeSearchBaseUrl(this.searchExaBaseUrl, 'https://api.exa.ai') !== this.originalSearchExaBaseUrl) {
      return true
    }
    if (this.searchBochaApiKey.trim() !== this.originalSearchBochaApiKey) {
      return true
    }
    if (this.normalizeSearchBaseUrl(this.searchBochaBaseUrl, 'https://api.bochaai.com') !==
      this.originalSearchBochaBaseUrl) {
      return true
    }
    if (this.searchQueryOptimizationEnabled !== this.originalSearchQueryOptimizationEnabled) {
      return true
    }
    return false
  }

  private performCloseSearchConfigSheet(sheetDismiss?: SheetDismiss): void {
    if (sheetDismiss !== undefined) {
      sheetDismiss.dismiss()
      return
    }
    this.showSearchConfigSheet = false
  }

  private requestCloseSearchConfigSheet(sheetDismiss?: SheetDismiss): void {
    if (!this.hasPendingSearchConfigChanges()) {
      this.performCloseSearchConfigSheet(sheetDismiss)
      return
    }

    this.getUIContext().showAlertDialog({
      title: $r('app.string.search_discard_changes_title'),
      message: $r('app.string.search_discard_changes_message'),
      primaryButton: {
        value: $r('app.string.search_continue_editing'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.search_discard_changes'),
        fontColor: Color.Red,
        action: () => {
          this.performCloseSearchConfigSheet(sheetDismiss)
        }
      }
    })
  }

  private async handleSaveSearchSettings(): Promise<boolean> {
    const braveKey = this.searchBraveApiKey.trim()
    const tavilyKey = this.searchTavilyApiKey.trim()
    const exaKey = this.searchExaApiKey.trim()
    const bochaKey = this.searchBochaApiKey.trim()
    const tavilyBaseUrl = this.normalizeSearchBaseUrl(this.searchTavilyBaseUrl, 'https://api.tavily.com')
    const exaBaseUrl = this.normalizeSearchBaseUrl(this.searchExaBaseUrl, 'https://api.exa.ai')
    const bochaBaseUrl = this.normalizeSearchBaseUrl(this.searchBochaBaseUrl, 'https://api.bochaai.com')
    if (this.searchEngine === SearchEngine.BRAVE && braveKey === '') {
      this.showToolsSnack(pickLocalizedText(
        '请选择 Brave Search 时先填写 API Key',
        'Enter the API key before selecting Brave Search'
      ), 2000, SnackBarTone.ERROR)
      return false
    }
    if (this.searchEngine === SearchEngine.TAVILY && tavilyKey === '') {
      this.showToolsSnack(pickLocalizedText(
        '请选择 Tavily 时先填写 API Key',
        'Enter the API key before selecting Tavily'
      ), 2000, SnackBarTone.ERROR)
      return false
    }
    if (this.searchEngine === SearchEngine.EXA && exaKey === '') {
      this.showToolsSnack($r('app.string.search_exa_key_required'), 2000, SnackBarTone.ERROR)
      return false
    }
    if (this.searchEngine === SearchEngine.BOCHA && bochaKey === '') {
      this.showToolsSnack(pickLocalizedText(
        '请选择 博查(Bocha) 时先填写 API Key',
        'Enter the API key before selecting Bocha'
      ), 2000, SnackBarTone.ERROR)
      return false
    }

    const shouldValidateTavilyBaseUrl = this.searchEngine === SearchEngine.TAVILY
    if (shouldValidateTavilyBaseUrl && !tavilyBaseUrl.startsWith('http://') && !tavilyBaseUrl.startsWith('https://')) {
      this.showToolsSnack($r('app.string.search_base_url_invalid'), 2000, SnackBarTone.ERROR)
      return false
    }
    const shouldValidateExaBaseUrl = this.searchEngine === SearchEngine.EXA
    if (shouldValidateExaBaseUrl && !exaBaseUrl.startsWith('http://') && !exaBaseUrl.startsWith('https://')) {
      this.showToolsSnack($r('app.string.search_base_url_invalid'), 2000, SnackBarTone.ERROR)
      return false
    }
    const shouldValidateBochaBaseUrl = this.searchEngine === SearchEngine.BOCHA
    if (shouldValidateBochaBaseUrl && !bochaBaseUrl.startsWith('http://') && !bochaBaseUrl.startsWith('https://')) {
      this.showToolsSnack($r('app.string.search_base_url_invalid'), 2000, SnackBarTone.ERROR)
      return false
    }

    await this.preferencesService.setString(PreferenceKeys.SEARCH_ENGINE, this.searchEngine)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_BRAVE_API_KEY, braveKey)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_TAVILY_API_KEY, tavilyKey)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_TAVILY_BASE_URL, tavilyBaseUrl)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_EXA_API_KEY, exaKey)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_EXA_BASE_URL, exaBaseUrl)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_BOCHA_API_KEY, bochaKey)
    await this.preferencesService.setString(PreferenceKeys.SEARCH_BOCHA_BASE_URL, bochaBaseUrl)
    await this.preferencesService.setBoolean(
      PreferenceKeys.SEARCH_QUERY_OPTIMIZATION_ENABLED,
      this.searchQueryOptimizationEnabled
    )
    this.searchBraveApiKey = braveKey
    this.searchTavilyApiKey = tavilyKey
    this.searchTavilyBaseUrl = tavilyBaseUrl
    this.searchExaApiKey = exaKey
    this.searchExaBaseUrl = exaBaseUrl
    this.searchBochaApiKey = bochaKey
    this.searchBochaBaseUrl = bochaBaseUrl
    this.syncOriginalSearchSettings()

    this.showToolsSnack($r('app.string.search_config_saved'), 2000, SnackBarTone.SUCCESS)
    return true
  }

  private handleSaveAndCloseSearchSettings(): void {
    this.handleSaveSearchSettings().then((saved: boolean) => {
      if (saved) {
        this.showSearchConfigSheet = false
      }
    })
  }

  private handleSearchEngineSelect(index: number, value: string): void {
    this.searchEngineSelectedIndex = index
    const nextEngine = this.getSearchEngineByIndex(index)
    const displayValue = value.trim() === '' ? this.getSearchEngineLabel(nextEngine) : value
    this.searchEngineDisplayValue = displayValue
    this.searchEngine = nextEngine
  }

  private resetMcpServerForm(): void {
    this.editingMcpServerId = ''
    this.mcpFormName = ''
    this.mcpFormBaseUrl = ''
    this.mcpFormAuthToken = ''
    this.mcpFormCustomHeadersJson = ''
    this.mcpFormCustomHeaderEntries = []
    this.showMcpCustomHeadersEditor = false
    this.mcpFormEnabled = true
    this.mcpFormAuthType = McpAuthType.NONE
    this.mcpAuthTypeSelectedIndex = 0
    this.isSavingMcpServer = false
  }

  private openCreateMcpServer(): void {
    this.resetMcpServerForm()
    this.showMcpServerSheet = true
  }

  private openEditMcpServer(server: McpServerConfig): void {
    this.editingMcpServerId = server.id
    this.mcpFormName = server.name
    this.mcpFormBaseUrl = server.baseUrl
    this.mcpFormAuthToken = server.authToken
    this.mcpFormCustomHeadersJson = server.customHeadersJson
    this.mcpFormCustomHeaderEntries = this.parseMcpHeaderEntries(server.customHeadersJson)
    this.showMcpCustomHeadersEditor = this.mcpFormCustomHeaderEntries.length > 0
    this.mcpFormEnabled = server.enabled
    this.mcpFormAuthType = server.authType
    this.mcpAuthTypeSelectedIndex = server.authType === McpAuthType.BEARER ? 1 : 0
    this.showMcpServerSheet = true
  }

  private handleMcpAuthTypeSelect(index: number): void {
    this.mcpAuthTypeSelectedIndex = index
    this.mcpFormAuthType = index === 1 ? McpAuthType.BEARER : McpAuthType.NONE
  }

  private isEditingMcpServer(): boolean {
    return this.editingMcpServerId !== ''
  }

  private getMcpFormTitle(): string {
    return this.isEditingMcpServer()
      ? pickLocalizedText('编辑 MCP Server', 'Edit MCP Server')
      : pickLocalizedText('新增 MCP Server', 'Add MCP Server')
  }

  private getMcpFormModeTag(): string {
    return this.isEditingMcpServer()
      ? pickLocalizedText('编辑', 'Editing')
      : pickLocalizedText('新服务', 'New')
  }

  private getMcpFormHeroTitle(): string {
    const name = this.mcpFormName.trim()
    if (name !== '') {
      return name
    }
    return this.isEditingMcpServer()
      ? pickLocalizedText('未命名服务', 'Unnamed Server')
      : pickLocalizedText('新建 MCP Server', 'New MCP Server')
  }

  private getMcpFormHeroDescription(): string {
    if (this.isEditingMcpServer()) {
      return pickLocalizedText('管理连接、认证和请求头。', 'Manage connection, auth, and headers.')
    }
    return pickLocalizedText('添加一个新的 MCP 服务。', 'Add a new MCP service.')
  }

  private getMcpFormTargetHint(): string {
    const baseUrl = this.normalizeMcpBaseUrl(this.mcpFormBaseUrl)
    if (baseUrl !== '') {
      return baseUrl
    }
    return ''
  }

  private getMcpFormAuthLabel(): string {
    return this.mcpFormAuthType === McpAuthType.BEARER ? 'Bearer' : pickLocalizedText('无认证', 'No auth')
  }

  private getMcpFormEnableLabel(): string {
    return this.mcpFormEnabled ? pickLocalizedText('自动启用', 'Auto enable') : pickLocalizedText('暂不启用', 'Save disabled')
  }

  private getServerCustomHeaderCount(server: McpServerConfig): number {
    return this.parseMcpHeaderEntries(server.customHeadersJson).length
  }

  private getMcpServerAuthLabel(server: McpServerConfig): string {
    return server.authType === McpAuthType.BEARER ? 'Bearer' : 'None'
  }

  private buildNewMcpServerId(): string {
    return `mcp_${Date.now()}`
  }

  private buildNewMcpHeaderEntryId(): string {
    return `mcp_header_${Date.now()}_${Math.floor(Math.random() * 100000)}`
  }

  private createMcpHeaderEntry(name: string = '', value: string = ''): McpHeaderEntry {
    return new McpHeaderEntry(this.buildNewMcpHeaderEntryId(), name, value)
  }

  private normalizeMcpHeaderName(name: string): string {
    return normalizeCustomHeaderName(name)
  }

  private isReservedMcpHeaderName(name: string): boolean {
    return this.reservedMcpHeaderNames.includes(this.normalizeMcpHeaderName(name))
  }

  private isSensitiveMcpHeaderName(name: string): boolean {
    return isSensitiveCustomHeaderName(name)
  }

  private parseMcpHeaderEntries(raw: string): McpHeaderEntry[] {
    const parsedEntries = parseCustomHeaderEntries(raw)
    const entries: McpHeaderEntry[] = []
    for (let i = 0; i < parsedEntries.length; i++) {
      entries.push(this.createMcpHeaderEntry(parsedEntries[i].name, parsedEntries[i].value))
    }
    return entries
  }

  private syncMcpCustomHeadersJsonFromEntries(): void {
    this.mcpFormCustomHeadersJson = this.buildMcpCustomHeadersJson()
  }

  private buildMcpCustomHeadersJson(): string {
    return buildCustomHeadersJson(this.mcpFormCustomHeaderEntries)
  }

  private validateMcpHeaderEntries(): string {
    return validateCustomHeaderEntries(this.mcpFormCustomHeaderEntries, this.reservedMcpHeaderNames, {
      emptyEntryMessage: pickLocalizedText(
        '自定义请求头的名称和值都不能为空',
        'Custom header name and value are both required'
      ),
      reservedHeaderMessage: (name: string): string => pickLocalizedText(
        `请求头 ${name} 由系统管理，请勿手动填写`,
        `Header ${name} is managed by the system and should not be set manually`
      ),
      duplicateHeaderMessage: (name: string): string => pickLocalizedText(
        `请求头 ${name} 重复，请保留一项`,
        `Header ${name} is duplicated; keep only one entry`
      )
    })
  }

  private getMcpRefreshFailedMessage(error: Object): string {
    return pickLocalizedText(`MCP 刷新失败: ${error}`, `MCP refresh failed: ${error}`)
  }

  private getDuplicateMcpServerMessage(serverName: string): string {
    return pickLocalizedText(
      `相同的 MCP 配置已存在：${serverName}`,
      `An identical MCP configuration already exists: ${serverName}`
    )
  }

  private getSavedMcpServerMessage(): string {
    return pickLocalizedText('MCP Server 已保存', 'MCP server saved')
  }

  private getSavedMcpServerRefreshFailedMessage(error: Object): string {
    return pickLocalizedText(
      `MCP Server 已保存，但刷新失败: ${error}`,
      `MCP server saved, but refresh failed: ${error}`
    )
  }

  private getSavedMcpServerSyncFailedMessage(error: Object): string {
    return pickLocalizedText(
      `MCP Server 已保存，但同步失败: ${error}`,
      `MCP server saved, but sync failed: ${error}`
    )
  }

  private getSaveMcpServerFailedMessage(error: Object): string {
    return pickLocalizedText(`保存 MCP Server 失败: ${error}`, `Failed to save MCP server: ${error}`)
  }

  private getMcpServerConnectedCountText(): string {
    return formatLocalizedCount(this.mcpServers.length, '个服务', 'connected service', 'connected services')
  }

  private addMcpHeaderEntry(): void {
    this.showMcpCustomHeadersEditor = true
    this.mcpFormCustomHeaderEntries = [...this.mcpFormCustomHeaderEntries, this.createMcpHeaderEntry()]
    this.syncMcpCustomHeadersJsonFromEntries()
  }

  private removeMcpHeaderEntry(entryId: string): void {
    const nextEntries: McpHeaderEntry[] = []
    for (let i = 0; i < this.mcpFormCustomHeaderEntries.length; i++) {
      if (this.mcpFormCustomHeaderEntries[i].id !== entryId) {
        nextEntries.push(this.mcpFormCustomHeaderEntries[i])
      }
    }
    this.mcpFormCustomHeaderEntries = nextEntries
    if (this.mcpFormCustomHeaderEntries.length === 0) {
      this.showMcpCustomHeadersEditor = false
    }
    this.syncMcpCustomHeadersJsonFromEntries()
  }

  private updateMcpHeaderEntryName(entryId: string, value: string): void {
    for (let i = 0; i < this.mcpFormCustomHeaderEntries.length; i++) {
      if (this.mcpFormCustomHeaderEntries[i].id === entryId) {
        this.mcpFormCustomHeaderEntries[i].name = value
        break
      }
    }
    this.mcpFormCustomHeaderEntries = [...this.mcpFormCustomHeaderEntries]
    this.syncMcpCustomHeadersJsonFromEntries()
  }

  private updateMcpHeaderEntryValue(entryId: string, value: string): void {
    for (let i = 0; i < this.mcpFormCustomHeaderEntries.length; i++) {
      if (this.mcpFormCustomHeaderEntries[i].id === entryId) {
        this.mcpFormCustomHeaderEntries[i].value = value
        break
      }
    }
    this.mcpFormCustomHeaderEntries = [...this.mcpFormCustomHeaderEntries]
    this.syncMcpCustomHeadersJsonFromEntries()
  }

  private normalizeMcpBaseUrl(raw: string): string {
    const trimmed = raw.trim()
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1)
    }
    return trimmed
  }

  private buildMcpServerSignature(
    baseUrl: string,
    authType: string,
    authToken: string,
    customHeadersJson: string
  ): string {
    return JSON.stringify({
      baseUrl: this.normalizeMcpBaseUrl(baseUrl),
      authType: authType,
      authToken: authToken.trim(),
      customHeadersJson: customHeadersJson.trim()
    })
  }

  private findDuplicateMcpServer(
    configs: McpServerConfig[],
    baseUrl: string,
    authType: string,
    authToken: string,
    customHeadersJson: string,
    ignoreServerId: string
  ): McpServerConfig | null {
    const targetSignature = this.buildMcpServerSignature(baseUrl, authType, authToken, customHeadersJson)
    for (let i = 0; i < configs.length; i++) {
      if (configs[i].id === ignoreServerId) {
        continue
      }
      const configSignature = this.buildMcpServerSignature(
        configs[i].baseUrl,
        configs[i].authType,
        configs[i].authToken,
        configs[i].customHeadersJson
      )
      if (configSignature === targetSignature) {
        return configs[i]
      }
    }
    return null
  }

  private getServerTools(serverId: string): ToolConfig[] {
    const configs: ToolConfig[] = []
    const tools = this.toolRegistry.getToolsBySource(ToolSourceType.MCP, serverId)
    for (let i = 0; i < tools.length; i++) {
      configs.push(tools[i].config)
    }
    return configs
  }

  private async handleSaveMcpServer(): Promise<void> {
    if (this.isSavingMcpServer) {
      return
    }
    const name = this.mcpFormName.trim()
    const baseUrl = this.normalizeMcpBaseUrl(this.mcpFormBaseUrl)
    const customHeadersError = this.validateMcpHeaderEntries()
    if (name === '') {
      this.showToolsSnack(pickLocalizedText('MCP Server 名称不能为空', 'MCP server name is required'),
        2000, SnackBarTone.ERROR)
      return
    }
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      this.showToolsSnack(
        pickLocalizedText('MCP Server 地址必须是 http/https', 'MCP server URL must use http or https'),
        2000,
        SnackBarTone.ERROR
      )
      return
    }
    if (customHeadersError !== '') {
      this.showToolsSnack(customHeadersError, 2500, SnackBarTone.ERROR)
      return
    }
    const customHeadersJson = this.buildMcpCustomHeadersJson()
    this.isSavingMcpServer = true
    let configSaved = false
    try {
      const configs = await this.mcpService.loadServerConfigs()
      const duplicateServer = this.findDuplicateMcpServer(
        configs,
        baseUrl,
        this.mcpFormAuthType,
        this.mcpFormAuthToken,
        customHeadersJson,
        this.editingMcpServerId
      )
      if (duplicateServer !== null) {
        const duplicateName = duplicateServer.name.trim() !== ''
          ? duplicateServer.name.trim()
          : pickLocalizedText('未命名服务', 'Unnamed Server')
        this.showToolsSnack(this.getDuplicateMcpServerMessage(duplicateName), 2500, SnackBarTone.ERROR)
        return
      }

      let targetServer: McpServerConfig | null = null
      for (let i = 0; i < configs.length; i++) {
        if (configs[i].id === this.editingMcpServerId) {
          targetServer = configs[i]
          break
        }
      }
      if (targetServer === null) {
        targetServer = new McpServerConfig(this.buildNewMcpServerId())
        configs.push(targetServer)
      }

      targetServer.name = name
      targetServer.baseUrl = baseUrl
      targetServer.enabled = this.mcpFormEnabled
      targetServer.authType = this.mcpFormAuthType
      targetServer.authToken = this.mcpFormAuthToken.trim()
      targetServer.customHeadersJson = customHeadersJson
      this.mcpFormBaseUrl = baseUrl
      this.mcpFormAuthToken = targetServer.authToken
      this.mcpFormCustomHeadersJson = customHeadersJson

      await this.mcpService.saveServerConfigs(configs)
      configSaved = true
      this.applyMcpServerConfigsToLocal(configs)
      this.showMcpServerSheet = false

      if (targetServer.enabled) {
        try {
          await this.mcpService.refreshServer(targetServer.id, configs)
          await this.loadMcpServers()
          this.showToolsSnack(this.getSavedMcpServerMessage(), 2000, SnackBarTone.SUCCESS)
        } catch (error) {
          await this.loadMcpServers()
          this.showToolsSnack(this.getSavedMcpServerRefreshFailedMessage(error), 3000, SnackBarTone.ERROR)
        }
      } else {
        await this.mcpService.refreshAllServers()
        await this.loadMcpServers()
        this.showToolsSnack(this.getSavedMcpServerMessage(), 2000, SnackBarTone.SUCCESS)
      }
    } catch (error) {
      console.error('ToolsCenterPanel', `Failed to save MCP server: ${JSON.stringify(error)}`)
      if (configSaved) {
        this.showToolsSnack(this.getSavedMcpServerSyncFailedMessage(error), 3000, SnackBarTone.ERROR)
      } else {
        this.showToolsSnack(this.getSaveMcpServerFailedMessage(error), 3000, SnackBarTone.ERROR)
      }
    } finally {
      this.isSavingMcpServer = false
    }
  }

  private handleDeleteMcpServer(serverId: string): void {
    this.getUIContext().showAlertDialog({
      title: pickLocalizedText('删除 MCP Server', 'Delete MCP Server'),
      message: pickLocalizedText(
        '删除后会同时卸载该 Server 发现的所有工具。',
        'Deleting it also removes every tool discovered from this server.'
      ),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: Color.Red,
        action: () => {
          this.deleteMcpServer(serverId)
        }
      }
    })
  }

  private deleteMcpServer(serverId: string): void {
    this.performDeleteMcpServer(serverId).catch((error: Object) => {
      console.error('ToolsCenterPanel', `Failed to delete MCP server: ${JSON.stringify(error)}`)
      this.showToolsSnack(pickLocalizedText('删除 MCP Server 失败', 'Failed to delete MCP server'),
        2000, SnackBarTone.ERROR)
    })
  }

  private async performDeleteMcpServer(serverId: string): Promise<void> {
    const configs = await this.mcpService.loadServerConfigs()
    const nextConfigs: McpServerConfig[] = []
    for (let i = 0; i < configs.length; i++) {
      if (configs[i].id !== serverId) {
        nextConfigs.push(configs[i])
      }
    }
    await this.mcpService.saveServerConfigs(nextConfigs)
    this.applyMcpServerConfigsToLocal(nextConfigs)
    await this.mcpService.terminateServerSession(serverId)
    await this.mcpService.refreshAllServers()
    await this.loadMcpServers()
    this.showToolsSnack(pickLocalizedText('MCP Server 已删除', 'MCP server deleted'), 2000, SnackBarTone.SUCCESS)
  }

  private handleMcpServerEnabledChanged(serverId: string, enabled: boolean): void {
    this.updateMcpServerEnabled(serverId, enabled).catch((error: Object) => {
      console.error('ToolsCenterPanel', `Failed to update MCP server enabled state: ${JSON.stringify(error)}`)
      this.showToolsSnack(pickLocalizedText('更新 MCP Server 状态失败', 'Failed to update MCP server state'),
        2000, SnackBarTone.ERROR)
    })
  }

  private async updateMcpServerEnabled(serverId: string, enabled: boolean): Promise<void> {
    const localServer = this.findLocalMcpServerById(serverId)
    const previousEnabled = localServer !== null ? localServer.enabled : !enabled
    this.updateLocalMcpServerEnabledState(serverId, enabled)
    const configs = await this.mcpService.loadServerConfigs()
    for (let i = 0; i < configs.length; i++) {
      if (configs[i].id === serverId) {
        configs[i].enabled = enabled
        break
      }
    }
    try {
      await this.mcpService.saveServerConfigs(configs)
    } catch (error) {
      this.updateLocalMcpServerEnabledState(serverId, previousEnabled)
      throw new Error(`${error}`)
    }
    this.applyMcpServerConfigsToLocal(configs)
    try {
      await this.mcpService.refreshAllServers()
    } finally {
      await this.loadMcpServers()
    }
  }

  private refreshMcpServer(serverId: string): void {
    this.performRefreshMcpServer(serverId).catch((error: Object) => {
      console.error('ToolsCenterPanel', `Failed to refresh MCP server: ${JSON.stringify(error)}`)
      this.showToolsSnack(this.getMcpRefreshFailedMessage(error), 2500, SnackBarTone.ERROR)
    })
  }

  private async performRefreshMcpServer(serverId: string): Promise<void> {
    await this.mcpService.refreshServer(serverId)
    await this.loadMcpServers()
    this.showToolsSnack(pickLocalizedText('MCP 工具已刷新', 'MCP tools refreshed'), 2000, SnackBarTone.SUCCESS)
  }

  @Builder
  ModLensConfigSheetBuilder() {
    Column() {
      ImmersiveSheetHeader({
        title: pickLocalizedText('ModLens 视觉理解', 'ModLens Vision'),
        showTrailing: true,
        trailingColor: this.themePrimary,
        onLeadingClick: (): void => {
          this.enableModLensAfterSave = false
          this.showModLensConfigSheet = false
        },
        onTrailingClick: (): void => {
          this.handleSaveModLensConfig()
        }
      })

      Scroll() {
        Column({ space: 16 }) {
          Text(pickLocalizedText(
            'ModLens 为未开启视觉能力的模型生成 OCR、布局、语义与视觉线索。需先在电脑或服务器运行项目内 tools/modlens-gateway。',
            'ModLens produces OCR, layout, semantic, and visual evidence for models without native vision. Run tools/modlens-gateway on a computer or server first.'
          ))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')

          Column({ space: 8 }) {
            Text(pickLocalizedText('网关地址', 'Gateway URL'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            TextInput({
              text: this.modLensGatewayUrl,
              placeholder: MODLENS_DEFAULT_GATEWAY_URL
            })
              .onChange((value: string) => {
                this.modLensGatewayUrl = value
                this.modLensConnectionMessage = ''
              })
              .fontSize(13)
              .width('100%')
              .height(42)
              .borderRadius(10)
              .backgroundColor(getAppUiState().themeBackground)
              .padding({ left: 12, right: 12 })

            Text(pickLocalizedText(
              '真机请填写运行网关的电脑局域网地址，例如 http://192.168.1.10:8787。',
              'For a physical device, use the LAN address of the computer running the gateway, for example http://192.168.1.10:8787.'
            ))
              .fontSize(11)
              .lineHeight(16)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
          }
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
          .backgroundColor(Color.Transparent)
          .systemMaterial(createToolServiceCardMaterial(false))

          Column({ space: 8 }) {
            Text(pickLocalizedText('Bearer 令牌（推荐）', 'Bearer token (recommended)'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            TextInput({
              text: this.modLensGatewayToken,
              placeholder: pickLocalizedText('与网关环境变量中的令牌一致', 'Same value as the gateway environment token')
            })
              .onChange((value: string) => {
                this.modLensGatewayToken = value
                this.modLensConnectionMessage = ''
              })
              .type(InputType.Password)
              .enableAutoFill(false)
              .fontSize(13)
              .width('100%')
              .height(42)
              .borderRadius(10)
              .backgroundColor(getAppUiState().themeBackground)
              .padding({ left: 12, right: 12 })
          }
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
          .backgroundColor(Color.Transparent)
          .systemMaterial(createToolServiceCardMaterial(false))

          Text(pickLocalizedText(
            '隐私提示：启用后，当前会话中由模型选择读取的图片会发送到该网关，并继续发送给 ModLens 配置的视觉 provider。原有“图片转文本”工具仍只在设备本地执行 OCR。',
            'Privacy: once enabled, images the model chooses to read are sent to this gateway and then to the vision provider configured in ModLens. The existing Image to Text tool continues to run OCR only on device.'
          ))
            .fontSize(11)
            .lineHeight(17)
            .fontColor('#D98400')
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor(withColorAlpha('#D98400', '1A'))

          Button(this.isTestingModLens
            ? pickLocalizedText('正在测试…', 'Testing…')
            : pickLocalizedText('测试连接', 'Test connection'))
            .width('100%')
            .height(42)
            .type(ButtonType.Capsule)
            .stateEffect(false)
            .enabled(!this.isTestingModLens && !this.isSavingModLens)
            .backgroundColor(this.themePrimary)
            .fontColor(Color.White)
            .onClick(() => {
              this.handleTestModLensConnection()
            })

          if (this.modLensConnectionMessage !== '') {
            Text(this.modLensConnectionMessage)
              .fontSize(12)
              .lineHeight(18)
              .fontColor(this.modLensConnectionOk ? this.themePrimary : '#D9485F')
              .width('100%')
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  @Builder
  SearchConfigSheetBuilder() {
    Column() {
      ImmersiveSheetHeader({
        title: $r('app.string.search_service_config'),
        showTrailing: true,
        trailingColor: this.themePrimary,
        onLeadingClick: (): void => {
          this.requestCloseSearchConfigSheet()
        },
        onTrailingClick: (): void => {
          this.handleSaveAndCloseSearchSettings()
        }
      })

      Scroll() {
        Column() {
          Text($r('app.string.search_service_config_desc'))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .margin({ bottom: 10 })

          Column() {
            Text($r('app.string.search_engine'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ bottom: 6 })

            Select(this.searchEngineOptions)
              .selected(this.searchEngineSelectedIndex)
              .value(this.searchEngineDisplayValue)
              .onSelect((index: number, value: string) => {
                this.handleSearchEngineSelect(index, value)
              })
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .height(40)
              .backgroundColor(getAppUiState().themeBackground)
              .borderRadius(10)
              .padding({ left: 8, right: 8 })

            if (this.searchEngine === SearchEngine.BRAVE) {
              TextInput({ text: this.searchBraveApiKey, placeholder: 'Brave Search API Key' })
                .onChange((value: string) => {
                  this.searchBraveApiKey = value
                })
                .type(InputType.Password)
                .enableAutoFill(false)
                .fontSize(13)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor(getAppUiState().themeBackground)
                .padding({ left: 12, right: 12 })
                .margin({ top: 8 })
            }

            if (this.searchEngine === SearchEngine.TAVILY) {
              TextInput({ text: this.searchTavilyApiKey, placeholder: 'Tavily API Key' })
                .onChange((value: string) => {
                  this.searchTavilyApiKey = value
                })
                .type(InputType.Password)
                .enableAutoFill(false)
                .fontSize(13)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor(getAppUiState().themeBackground)
                .padding({ left: 12, right: 12 })
                .margin({ top: 8 })

              TextInput({ text: this.searchTavilyBaseUrl, placeholder: $r('app.string.search_tavily_base_url') })
                .onChange((value: string) => {
                  this.searchTavilyBaseUrl = value
                })
                .fontSize(13)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor(getAppUiState().themeBackground)
                .padding({ left: 12, right: 12 })
                .margin({ top: 8 })

              Text($r('app.string.search_tavily_base_url_hint'))
                .fontSize(11)
                .lineHeight(16)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .margin({ top: 6 })
            }

            if (this.searchEngine === SearchEngine.EXA) {
              TextInput({ text: this.searchExaApiKey, placeholder: $r('app.string.search_exa_api_key') })
                .onChange((value: string) => {
                  this.searchExaApiKey = value
                })
                .type(InputType.Password)
                .enableAutoFill(false)
                .fontSize(13)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor(getAppUiState().themeBackground)
                .padding({ left: 12, right: 12 })
                .margin({ top: 8 })

              TextInput({ text: this.searchExaBaseUrl, placeholder: $r('app.string.search_exa_base_url') })
                .onChange((value: string) => {
                  this.searchExaBaseUrl = value
                })
                .fontSize(13)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor(getAppUiState().themeBackground)
                .padding({ left: 12, right: 12 })
                .margin({ top: 8 })
            }

            if (this.searchEngine === SearchEngine.BOCHA) {
              TextInput({ text: this.searchBochaApiKey, placeholder: '博查(Bocha) API Key' })
                .onChange((value: string) => {
                  this.searchBochaApiKey = value
                })
                .type(InputType.Password)
                .enableAutoFill(false)
                .fontSize(13)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor(getAppUiState().themeBackground)
                .padding({ left: 12, right: 12 })
                .margin({ top: 8 })

              TextInput({ text: this.searchBochaBaseUrl, placeholder: 'https://api.bochaai.com' })
                .onChange((value: string) => {
                  this.searchBochaBaseUrl = value
                })
                .fontSize(13)
                .width('100%')
                .height(40)
                .borderRadius(10)
                .backgroundColor(getAppUiState().themeBackground)
                .padding({ left: 12, right: 12 })
                .margin({ top: 8 })

              Text(pickLocalizedText(
                '博查是国内中文搜索 API，需在 open.bochaai.com 获取 API Key（付费）。',
                'Bocha is a Chinese search API; get an API key at open.bochaai.com (paid).'
              ))
                .fontSize(11)
                .lineHeight(16)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .margin({ top: 6 })
            }

            Text($r('app.string.search_engine_runtime_hint'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
              .margin({ top: 8 })

            if (this.searchEngine === SearchEngine.BING) {
              Row() {
                Column() {
                  Text($r('app.string.search_query_optimization'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')

                  Text($r('app.string.search_query_optimization_hint'))
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                    .width('100%')
                    .margin({ top: 2, right: 8 })
                }
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.searchQueryOptimizationEnabled })
                  .selectedColor(this.themePrimary)
                  .systemMaterial(new uiMaterial.Material())
                  .switchPointColor(Color.White)
                  .onChange((value: boolean) => {
                    this.searchQueryOptimizationEnabled = value
                  })
              }
              .width('100%')
              .margin({ top: 10 })
            }
          }
          .width('100%')
          .padding(12)
          .borderRadius(16)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
          .systemMaterial(createToolServiceCardMaterial(false))
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  @Builder
  McpServerSheetBuilder() {
    Column() {
      ImmersiveSheetHeader({
        title: this.getMcpFormTitle(),
        showTrailing: true,
        trailingButtonEnabled: !this.isSavingMcpServer,
        trailingLoading: this.isSavingMcpServer,
        trailingColor: this.themePrimary,
        onLeadingClick: (): void => {
          this.showMcpServerSheet = false
        },
        onTrailingClick: (): void => {
          this.handleSaveMcpServer()
        }
      })

      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 12 }) {
            Row({ space: 12 }) {
              Column() {
                SymbolGlyph($r('sys.symbol.cloud'))
                  .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                  .fontSize(22)
                  .fontColor([this.themePrimary])
              }
              .width(46)
              .height(46)
              .borderRadius(16)
              .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '26' : '12'))
              .justifyContent(FlexAlign.Center)

              Column({ space: 4 }) {
                Row({ space: 8 }) {
                  Text(this.getMcpFormHeroTitle())
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(this.getMcpFormModeTag())
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.themePrimary)
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .borderRadius(999)
                    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '20' : '10'))
                }
                .width('100%')

                Text(this.getMcpFormHeroDescription())
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')

                if (this.getMcpFormTargetHint() !== '') {
                  Text(this.getMcpFormTargetHint())
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                    .width('100%')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')

            Row({ space: 8 }) {
              Text(this.getMcpFormAuthLabel())
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(999)
                .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '20' : '10'))

              Text(this.getMcpFormEnableLabel())
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(999)
                .backgroundColor(getAppUiState().themeBackground)
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
          .systemMaterial(createToolServiceCardMaterial(false))

          Column({ space: 12 }) {
            Column({ space: 4 }) {
              Text(pickLocalizedText('连接信息', 'Connection'))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))

              Text(pickLocalizedText('填写名称和服务地址。', 'Set the display name and service URL.'))
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column({ space: 6 }) {
              Text(pickLocalizedText('显示名称', 'Display Name'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')

              TextInput({ text: this.mcpFormName, placeholder: pickLocalizedText(
                '例如 GitHub MCP / Timebook MCP',
                'e.g. GitHub MCP / Timebook MCP'
              ) })
                .onChange((value: string) => {
                  this.mcpFormName = value
                })
                .fontSize(14)
                .width('100%')
                .height(46)
                .borderRadius(14)
                .backgroundColor(getAppUiState().themeBackground)
                .border({ width: 1, color: $r('app.color.divider') })
                .padding({ left: 14, right: 14 })
            }
            .width('100%')

            Column({ space: 6 }) {
              Text(pickLocalizedText('服务地址', 'Service URL'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')

              TextInput({ text: this.mcpFormBaseUrl, placeholder: 'https://your-mcp.example.com/mcp' })
                .onChange((value: string) => {
                  this.mcpFormBaseUrl = value
                })
                .fontSize(14)
                .width('100%')
                .height(46)
                .borderRadius(14)
                .backgroundColor(getAppUiState().themeBackground)
                .border({ width: 1, color: $r('app.color.divider') })
                .padding({ left: 14, right: 14 })

              Text(pickLocalizedText('请输入完整的 HTTP/HTTPS 地址。', 'Enter the full HTTP or HTTPS URL.'))
                .fontSize(11)
                .lineHeight(16)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
          .systemMaterial(createToolServiceCardMaterial(false))

          Column({ space: 12 }) {
            Column({ space: 4 }) {
              Text(pickLocalizedText('认证策略', 'Authentication'))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))

              Text(pickLocalizedText('按服务要求选择认证方式。', 'Choose the auth method required by the server.'))
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column({ space: 6 }) {
              Text(pickLocalizedText('认证类型', 'Auth Type'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')

              Select(this.mcpAuthTypeOptions)
                .selected(this.mcpAuthTypeSelectedIndex)
                .value(this.mcpAuthTypeSelectedIndex === 1 ? 'Bearer' : 'None')
                .onSelect((index: number, _value: string) => {
                  this.handleMcpAuthTypeSelect(index)
                })
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .height(46)
                .backgroundColor(getAppUiState().themeBackground)
                .borderRadius(14)
                .border({ width: 1, color: $r('app.color.divider') })
                .padding({ left: 10, right: 10 })
            }
            .width('100%')

            if (this.mcpFormAuthType === McpAuthType.BEARER) {
              Column({ space: 6 }) {
                Text('Bearer Token')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')

                TextInput({ text: this.mcpFormAuthToken, placeholder: pickLocalizedText(
                  '输入 Bearer Token',
                  'Enter bearer token'
                ) })
                  .onChange((value: string) => {
                    this.mcpFormAuthToken = value
                  })
                  .type(InputType.Password)
                  .enableAutoFill(false)
                  .fontSize(14)
                  .width('100%')
                  .height(46)
                  .borderRadius(14)
                  .backgroundColor(getAppUiState().themeBackground)
                  .border({ width: 1, color: $r('app.color.divider') })
                  .padding({ left: 14, right: 14 })

                Text(pickLocalizedText(
                  '系统会自动附加 Authorization。',
                  'Authorization is added automatically.'
                ))
                  .fontSize(11)
                  .lineHeight(16)
                  .fontColor($r('app.color.text_tertiary'))
                  .width('100%')
              }
              .width('100%')
            } else {
              Row({ space: 10 }) {
                Column() {
                  SymbolGlyph($r('sys.symbol.checkmark_circle'))
                    .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                    .fontSize(16)
                    .fontColor([this.themePrimary])
                }
                .width(28)
                .height(28)
                .borderRadius(14)
                .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '20' : '10'))
                .justifyContent(FlexAlign.Center)

                Column({ space: 3 }) {
                  Text(pickLocalizedText('未设置额外认证', 'No extra authentication'))
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))

                  Text(pickLocalizedText(
                    '当前服务将直接使用基础连接信息。',
                    'This server uses the base connection settings directly.'
                  ))
                    .fontSize(11)
                    .lineHeight(16)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(12)
              .borderRadius(14)
              .backgroundColor(getAppUiState().themeBackground)
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
          .systemMaterial(createToolServiceCardMaterial(false))

          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Text(pickLocalizedText('自定义请求头', 'Custom Headers'))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Toggle({ type: ToggleType.Switch, isOn: this.showMcpCustomHeadersEditor })
                .selectedColor(this.themePrimary)
                .systemMaterial(new uiMaterial.Material())
                .switchPointColor(Color.White)
                .onChange((isOn: boolean) => {
                  this.showMcpCustomHeadersEditor = isOn
                })
            }
            .width('100%')

            if (this.showMcpCustomHeadersEditor) {
              Row() {
                Button() {
                  Row({ space: 4 }) {
                    SymbolGlyph($r('sys.symbol.plus'))
                      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                      .fontSize(13)
                      .fontColor([Color.White])
                    Text(pickLocalizedText('新增请求头', 'Add header'))
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Color.White)
                  }
                }
                .height(32)
                .padding({ left: 14, right: 14 })
                .type(ButtonType.Capsule)
                .stateEffect(false)
                .backgroundColor(this.themePrimary)
                .onClick(() => {
                  this.addMcpHeaderEntry()
                })
                Blank()
              }
              .width('100%')
            }

            if (this.showMcpCustomHeadersEditor) {
              ForEach(this.mcpFormCustomHeaderEntries, (entry: McpHeaderEntry, index: number) => {
                Column({ space: 10 }) {
                  Row() {
                    Text(pickLocalizedText(`请求头 ${index + 1}`, `Header ${index + 1}`))
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)

                    if (this.isSensitiveMcpHeaderName(entry.name)) {
                      Text(pickLocalizedText('敏感', 'Sensitive'))
                        .fontSize(10)
                        .fontWeight(FontWeight.Medium)
                        .fontColor('#D97757')
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .borderRadius(999)
                        .backgroundColor(this.isDarkMode ? '#4A2D1A' : '#FFF1E8')
                        .margin({ right: 8 })
                    }

                    Button($r('app.string.delete'))
                      .height(28)
                      .fontSize(11)
                      .type(ButtonType.Capsule)
                      .stateEffect(false)
                      .backgroundColor(getAppUiState().themeSurface)
                      .border({ width: 1, color: this.isDarkMode ? '#6A3139' : '#F2CBD2' })
                      .fontColor('#D9485F')
                      .onClick(() => {
                        this.removeMcpHeaderEntry(entry.id)
                      })
                  }
                  .width('100%')

                  Column({ space: 6 }) {
                    Text(pickLocalizedText('名称', 'Name'))
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                      .width('100%')

                    TextInput({ text: entry.name, placeholder: pickLocalizedText(
                      '例如 timebook-mcp-token',
                      'e.g. timebook-mcp-token'
                    ) })
                      .onChange((value: string) => {
                        this.updateMcpHeaderEntryName(entry.id, value)
                      })
                      .fontSize(14)
                      .width('100%')
                      .height(44)
                      .borderRadius(14)
                      .backgroundColor(getAppUiState().themeBackground)
                      .border({ width: 1, color: $r('app.color.divider') })
                      .padding({ left: 14, right: 14 })
                  }
                  .width('100%')

                  Column({ space: 6 }) {
                    Text(pickLocalizedText('值', 'Value'))
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                      .width('100%')

                    if (this.isSensitiveMcpHeaderName(entry.name)) {
                      TextInput({ text: entry.value, placeholder: pickLocalizedText(
                        '输入 Header Value',
                        'Enter header value'
                      ) })
                        .onChange((value: string) => {
                          this.updateMcpHeaderEntryValue(entry.id, value)
                        })
                        .type(InputType.Password)
                        .enableAutoFill(false)
                        .fontSize(14)
                        .width('100%')
                        .height(44)
                        .borderRadius(14)
                        .backgroundColor(getAppUiState().themeBackground)
                        .border({ width: 1, color: $r('app.color.divider') })
                        .padding({ left: 14, right: 14 })
                    } else {
                      TextInput({ text: entry.value, placeholder: pickLocalizedText(
                        '输入 Header Value',
                        'Enter header value'
                      ) })
                        .onChange((value: string) => {
                          this.updateMcpHeaderEntryValue(entry.id, value)
                        })
                        .fontSize(14)
                        .width('100%')
                        .height(44)
                        .borderRadius(14)
                        .backgroundColor(getAppUiState().themeBackground)
                        .border({ width: 1, color: $r('app.color.divider') })
                        .padding({ left: 14, right: 14 })
                    }
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(14)
                .borderRadius(18)
                .backgroundColor(getAppUiState().themeBackground)
                .border({ width: 1, color: $r('app.color.divider') })
              }, (entry: McpHeaderEntry) => entry.id)
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
          .systemMaterial(createToolServiceCardMaterial(false))

          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text(pickLocalizedText('启用该 Server', 'Enable This Server'))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')

              Text(this.mcpFormEnabled
                ? pickLocalizedText('保存后立即连接并发现工具。', 'Connect and discover tools right after saving.')
                : pickLocalizedText('仅保存当前配置。', 'Only save the current configuration.'))
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.mcpFormEnabled })
              .selectedColor(this.themePrimary)
              .systemMaterial(new uiMaterial.Material())
              .switchPointColor(Color.White)
              .onChange((value: boolean) => {
                this.mcpFormEnabled = value
              })
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
          .systemMaterial(createToolServiceCardMaterial(false))
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  @Builder
  SkillConfigSheetBuilder() {
    Column() {
      ImmersiveSheetHeader({
        title: this.getSkillFormTitle(),
        showTrailing: true,
        trailingButtonEnabled: !this.isSavingSkill,
        trailingLoading: this.isSavingSkill,
        trailingColor: this.themePrimary,
        onLeadingClick: (): void => {
          this.showSkillConfigSheet = false
        },
        onTrailingClick: (): void => {
          this.handleSaveSkill()
        }
      })

      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 12 }) {
            Row({ space: 12 }) {
              Column() {
                SymbolGlyph($r('sys.symbol.doc_text_badge_magnifyingglass'))
                  .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                  .fontSize(22)
                  .fontColor([this.themePrimary])
              }
              .width(46)
              .height(46)
              .borderRadius(16)
              .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '26' : '12'))
              .justifyContent(FlexAlign.Center)

              Column({ space: 4 }) {
                Text(this.getSkillFormHeroTitle())
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(pickLocalizedText(
                  '模型只会读取已启用 Skill 的 SKILL.md 正文。',
                  'The model can only read enabled Skill content.'
                ))
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')

            Row({ space: 12 }) {
              Blank()

              Toggle({ type: ToggleType.Switch, isOn: this.skillFormEnabled })
                .selectedColor(this.themePrimary)
                .systemMaterial(new uiMaterial.Material())
                .switchPointColor(Color.White)
                .onChange((value: boolean) => {
                  this.skillFormEnabled = value
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
          .systemMaterial(createToolServiceCardMaterial(false))

          Column({ space: 12 }) {
            Column({ space: 6 }) {
              Text(pickLocalizedText('名称', 'Name'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')

              TextInput({ text: this.skillFormName, placeholder: 'app-help' })
                .onChange((value: string) => {
                  this.skillFormName = value
                })
                .fontSize(14)
                .width('100%')
                .height(46)
                .borderRadius(14)
                .backgroundColor(getAppUiState().themeBackground)
                .border({ width: 1, color: $r('app.color.divider') })
                .padding({ left: 14, right: 14 })
            }
            .width('100%')

            Column({ space: 6 }) {
              Text(pickLocalizedText('描述', 'Description'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')

              TextInput({ text: this.skillFormDescription, placeholder: pickLocalizedText(
                '一句话说明这个 Skill 适合回答什么问题',
                'Describe when this Skill should be used'
              ) })
                .onChange((value: string) => {
                  this.skillFormDescription = value
                })
                .fontSize(14)
                .width('100%')
                .height(46)
                .borderRadius(14)
                .backgroundColor(getAppUiState().themeBackground)
                .border({ width: 1, color: $r('app.color.divider') })
                .padding({ left: 14, right: 14 })
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
          .systemMaterial(createToolServiceCardMaterial(false))

          Column({ space: 8 }) {
            Text('SKILL.md')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%')

            TextArea({ text: this.skillFormContent, placeholder: pickLocalizedText(
              '# 使用说明\\n\\n写下模型需要遵守的能力说明、入口和限制。',
              '# Instructions\\n\\nWrite the capability guidance, entry points, and limits.'
            ) })
              .fontSize(14)
              .lineHeight(20)
              .fontColor($r('app.color.text_primary'))
              .placeholderColor($r('app.color.text_tertiary'))
              .backgroundColor(getAppUiState().themeBackground)
              .borderRadius(14)
              .border({ width: 1, color: $r('app.color.divider') })
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .width('100%')
              .height(260)
              .onChange((value: string) => {
                this.skillFormContent = value
              })
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Color.Transparent)
          .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
          .systemMaterial(createToolServiceCardMaterial(false))
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  build() {
    Column() {
      Column() {
        if (this.showHeader) {
          Row() {
            Text($r('app.string.tools_center_title'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))

            Blank()

            Button($r('app.string.tools_center_refresh'))
              .height(30)
              .fontSize(12)
              .type(ButtonType.Capsule)
              .stateEffect(false)
              .backgroundColor(this.themePrimary)
              .fontColor(Color.White)
              .onClick(() => {
                this.refreshMcpServersInBackground(true)
              })
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)
        }

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(42)
              .height(42)
              .color(this.themePrimary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ top: this.contentTopPadding })
        } else {
          Scroll(this.contentScroller) {
            Column({ space: 20 }) {
              if (this.contentTopPadding > 0) {
                Blank()
                  .width('100%')
                  .height(this.contentTopPadding)
              }

              SearchServiceCardItem({
                searchEnabled: this.searchServiceEnabled,
                searchEngineDisplayValue: this.searchEngineDisplayValue,
                onToggle: (enabled: boolean) => {
                  this.handleSearchServiceEnabledChanged(enabled)
                },
                onOpenConfig: () => {
                  this.showSearchConfigSheet = true
                }
              })

              ContextCompactCardItem({
                compactEnabled: this.contextCompactEnabled,
                thresholdPercent: this.contextCompactThresholdPercent,
                maxContextTokens: this.contextCompactMaxTokens,
                onToggle: (enabled: boolean) => {
                  this.handleContextCompactEnabledChanged(enabled)
                },
                onThresholdChange: (percent: number) => {
                  this.handleContextCompactThresholdChanged(percent)
                },
                onMaxContextTokensChange: (tokens: number) => {
                  this.handleContextCompactMaxTokensChanged(tokens)
                }
              })

              SkillServiceCardItem({
                skillEnabled: this.skillToolEnabled,
                totalSkillCount: this.skills.length,
                enabledSkillCount: this.getEnabledSkillCount(),
                skills: this.skills,
                onToggle: (enabled: boolean) => {
                  this.handleSkillToolEnabledChanged(enabled)
                },
                onCreateSkill: () => {
                  this.openCreateSkill()
                },
                onToggleSkillEnabled: (skillId: string, enabled: boolean) => {
                  this.updateSkillEnabled(skillId, enabled)
                },
                onEditSkill: (skill: SkillConfig) => {
                  this.openEditSkill(skill)
                },
                onDeleteSkill: (skillId: string) => {
                  this.handleDeleteSkill(skillId)
                }
              })

              if (this.builtinTools.length > 0) {
                ForEach(this.builtinTools, (tool: ToolConfig) => {
                  BuiltinToolCardItem({
                    tool: tool,
                    selected: this.isToolSelected(tool.id),
                    configurable: tool.id === MODLENS_READ_IMAGE_TOOL_ID,
                    onToggle: (enabled: boolean): void => {
                      this.handleBuiltinToolSelectionChanged(tool.id, enabled)
                    },
                    onConfigure: (): void => {
                      this.openModLensConfig()
                    }
                  })
                }, (tool: ToolConfig) => tool.id)
              }

              Column({ space: 10 }) {
                Row() {
                  Text(pickLocalizedText('MCP 服务', 'MCP Services'))
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)

                  if (this.isRefreshingMcpServers) {
                    LoadingProgress()
                      .width(18)
                      .height(18)
                      .color(this.themePrimary)
                      .margin({ right: 8 })
                  }

                  Button() {
                    Row({ space: 4 }) {
                      SymbolGlyph($r('sys.symbol.plus'))
                        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                        .fontSize(13)
                        .fontColor([Color.White])
                      Text(pickLocalizedText('新增', 'Add'))
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Color.White)
                    }
                  }
                  .height(32)
                  .padding({ left: 14, right: 14 })
                  .type(ButtonType.Capsule)
                  .stateEffect(false)
                  .backgroundColor(this.themePrimary)
                  .onClick(() => {
                    this.openCreateMcpServer()
                  })
                }
                .width('100%')

                if (this.mcpServers.length > 0) {
                  Text(this.getMcpServerConnectedCountText())
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }
              }
              .width('100%')

              if (this.mcpServers.length === 0) {
                Row({ space: 12 }) {
                  ChatFloatingImmersiveButton({
                    barWidth: 42,
                    barHeight: 42,
                    iconResource: $r('sys.symbol.puzzle'),
                    iconSize: 22,
                    iconColor: [this.themePrimary],
                    responsePadding: 0,
                    onButtonClick: (): void => {
                      this.openCreateMcpServer()
                    }
                  }) {
                    Stack({ alignContent: Alignment.Center }) {
                      SymbolGlyph($r('sys.symbol.puzzle'))
                        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                        .fontSize(22)
                        .fontColor([this.themePrimary])
                    }
                    .width(42)
                    .height(42)
                  }

                  Column({ space: 4 }) {
                    Text(pickLocalizedText('还没有 MCP Server', 'No MCP server yet'))
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))

                    Text(pickLocalizedText('点击右上角新增。', 'Tap Add in the top right to create one.'))
                      .fontSize(12)
                      .lineHeight(18)
                      .fontColor($r('app.color.text_secondary'))
                      .width('100%')
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding(18)
                .borderRadius(16)
                .backgroundColor(Color.Transparent)
                .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
                .systemMaterial(createToolServiceCardMaterial(false))
              } else {
                ForEach(this.mcpServers, (server: McpServerConfig) => {
                  McpServerCardItem({
                    serverName: server.name,
                    serverBaseUrl: server.baseUrl,
                    serverEnabled: server.enabled,
                    tools: this.getServerTools(server.id),
                    authLabel: this.getMcpServerAuthLabel(server),
                    customHeaderCount: this.getServerCustomHeaderCount(server),
                    onToggleEnabled: (value: boolean) => {
                      this.handleMcpServerEnabledChanged(server.id, value)
                    },
                    onRefresh: () => {
                      this.refreshMcpServer(server.id)
                    },
                    onEdit: () => {
                      this.openEditMcpServer(server)
                    },
                    onDelete: () => {
                      this.handleDeleteMcpServer(server.id)
                    }
                  })
                }, (server: McpServerConfig) => server.id)
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: this.contentBottomPadding })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(getAppUiState().themeBackground)

      // bindSheet 宿主分离：布尔状态模式下不要把多个 sheet 链到同一个组件上
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showSearchConfigSheet, this.SearchConfigSheetBuilder(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          showClose: false,
          dragBar: true,
          blurStyle: BlurStyle.Regular,
          onWillAppear: () => {
            this.loadSearchSettings()
          },
          shouldDismiss: (dismissAction: SheetDismiss) => {
            this.requestCloseSearchConfigSheet(dismissAction)
          },
          onDisappear: () => {
            this.showSearchConfigSheet = false
            this.loadSearchSettings()
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showModLensConfigSheet, this.ModLensConfigSheetBuilder(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          showClose: false,
          dragBar: true,
          blurStyle: BlurStyle.Regular,
          onWillAppear: () => {
            this.loadModLensConfig()
          },
          onDisappear: () => {
            this.showModLensConfigSheet = false
            this.enableModLensAfterSave = false
            this.loadModLensConfig()
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showSkillConfigSheet, this.SkillConfigSheetBuilder(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          showClose: false,
          dragBar: true,
          blurStyle: BlurStyle.Regular,
          onDisappear: () => {
            this.showSkillConfigSheet = false
            this.loadSkills()
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showMcpServerSheet, this.McpServerSheetBuilder(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          showClose: false,
          dragBar: true,
          blurStyle: BlurStyle.Regular,
          onDisappear: () => {
            this.showMcpServerSheet = false
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }
}

@ComponentV2
struct SearchServiceCardItem {
  @Param searchEnabled: boolean = false
  @Param searchEngineDisplayValue: string = ''
  @Event onToggle: (enabled: boolean) => void = (enabled: boolean) => {}
  @Event onOpenConfig: () => void = () => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private getDisabledText(): string {
    return pickLocalizedText('未启用', 'Disabled')
  }

  private getConfigureText(): string {
    return pickLocalizedText('配置', 'Configure')
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        ChatFloatingImmersiveButton({
          barWidth: 44,
          barHeight: 44,
          iconResource: $r('sys.symbol.worldclock_fill_2'),
          iconSize: 20,
          iconColor: [this.themePrimary],
          responsePadding: 0,
          onButtonClick: (): void => {
            this.onOpenConfig()
          }
        }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.worldclock_fill_2'))
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
              .fontSize(20)
              .fontColor([this.themePrimary])
          }
          .width(44)
          .height(44)
        }

        Column({ space: 6 }) {
          Text($r('app.string.search_service_card_title'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Text(this.searchEnabled ? this.searchEngineDisplayValue : this.getDisabledText())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.searchEnabled })
          .selectedColor(this.themePrimary)
          .systemMaterial(new uiMaterial.Material())
          .switchPointColor(Color.White)
          .onChange((value: boolean) => {
            this.onToggle(value)
          })
      }
      .width('100%')

      Row({ space: 4 }) {
        Blank()

        Text(this.getConfigureText())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .fontSize(12)
          .fontColor([this.themePrimary])
      }
      .width('100%')
      .onClick(() => {
        this.onOpenConfig()
      })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Color.Transparent)
    .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
    .systemMaterial(createToolServiceCardMaterial(false))
    .onClick(() => {
      this.onOpenConfig()
    })
  }
}

// 上下文压缩（compact）设置卡片：控制是否在超过阈值时提醒模型压缩，以及触发阈值
@ComponentV2
struct ContextCompactCardItem {
  @Param compactEnabled: boolean = true
  @Param thresholdPercent: number = DEFAULT_COMPACT_THRESHOLD_PERCENT
  @Param maxContextTokens: number = DEFAULT_CONTEXT_LIMIT_TOKENS
  @Event onToggle: (enabled: boolean) => void = (_enabled: boolean): void => {}
  @Event onThresholdChange: (percent: number) => void = (_percent: number): void => {}
  @Event onMaxContextTokensChange: (tokens: number) => void = (_tokens: number): void => {}

  // 拖动过程中的实时值，抬手（Moving/End）后才写入偏好
  @Local draggingThresholdPercent: number = -1
  @Local draggingMaxContextTokens: number = -1

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private getDisplayThresholdPercent(): number {
    return this.draggingThresholdPercent >= 0 ? this.draggingThresholdPercent : this.thresholdPercent
  }

  private getDisplayMaxContextTokens(): number {
    return this.draggingMaxContextTokens >= 0 ? this.draggingMaxContextTokens : this.maxContextTokens
  }

  private getStatusText(): string {
    if (!this.compactEnabled) {
      return pickLocalizedText('未启用', 'Disabled')
    }
    return pickLocalizedText(
      `上限 ${formatTokenCount(this.getDisplayMaxContextTokens())} · 超过 ${this.getDisplayThresholdPercent()}% 时提醒压缩`,
      `Cap ${formatTokenCount(this.getDisplayMaxContextTokens())} · remind above ${this.getDisplayThresholdPercent()}%`
    )
  }

  // 拖动中只更新显示，抬手或点击轨道时才落盘
  private isSliderCommitted(mode: SliderChangeMode): boolean {
    return mode === SliderChangeMode.End || mode === SliderChangeMode.Click
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        ChatFloatingImmersiveButton({
          barWidth: 44,
          barHeight: 44,
          iconResource: $r('sys.symbol.wrench_and_screwdriver'),
          iconSize: 20,
          iconColor: [this.themePrimary],
          responsePadding: 0,
          onButtonClick: (): void => {}
        }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
              .fontSize(20)
              .fontColor([this.themePrimary])
          }
          .width(44)
          .height(44)
        }

        Column({ space: 6 }) {
          Text(pickLocalizedText('上下文压缩', 'Context Compaction'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Text(this.getStatusText())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.compactEnabled })
          .selectedColor(this.themePrimary)
          .systemMaterial(new uiMaterial.Material())
          .switchPointColor(Color.White)
          .onChange((value: boolean) => {
            this.onToggle(value)
          })
      }
      .width('100%')

      Text(pickLocalizedText(
        '对话上下文超过所选比例时，应用会在下一次请求中提醒模型先调用 compact 工具，把更早的历史压缩成摘要。' +
          '只影响发送给模型的内容，不会删除聊天记录。仅支持工具调用的模型可用。',
        'When the conversation exceeds the selected share of the model context window, the next request reminds ' +
          'the model to call the compact tool first. Only the request is shortened; your chat history is kept. ' +
          'Requires a model that supports tools.'
      ))
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      if (this.compactEnabled) {
        Column({ space: 4 }) {
          Row() {
            Text(pickLocalizedText('上下文长度上限', 'Context length cap'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)

            Text(formatTokenCount(this.getDisplayMaxContextTokens()))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)
          }
          .width('100%')

          Slider({
            value: this.getDisplayMaxContextTokens(),
            min: MIN_CONTEXT_LIMIT_TOKENS,
            max: MAX_CONTEXT_LIMIT_TOKENS,
            step: CONTEXT_LIMIT_TOKENS_STEP,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .selectedColor(this.themePrimary)
            .trackColor(getAppUiState().themeBackground)
            .blockColor(Color.White)
            .onChange((value: number, mode: SliderChangeMode) => {
              this.draggingMaxContextTokens = value
              if (this.isSliderCommitted(mode)) {
                this.draggingMaxContextTokens = -1
                this.onMaxContextTokensChange(value)
              }
            })

          Text(pickLocalizedText(
            `模型窗口大于该值时按该值计算用量，可选 ${formatTokenCount(MIN_CONTEXT_LIMIT_TOKENS)} ~ ` +
              `${formatTokenCount(MAX_CONTEXT_LIMIT_TOKENS)}；窗口较小的模型不受影响。`,
            `Models with a larger window are measured against this cap ` +
              `(${formatTokenCount(MIN_CONTEXT_LIMIT_TOKENS)}–${formatTokenCount(MAX_CONTEXT_LIMIT_TOKENS)}). ` +
              `Smaller models are unaffected.`
          ))
            .fontSize(11)
            .lineHeight(16)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        .width('100%')

        Column({ space: 4 }) {
          Row() {
            Text(pickLocalizedText('触发阈值', 'Trigger threshold'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)

            Text(`${this.getDisplayThresholdPercent()}%`)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)
          }
          .width('100%')

          Slider({
            value: this.getDisplayThresholdPercent(),
            min: MIN_COMPACT_THRESHOLD_PERCENT,
            max: MAX_COMPACT_THRESHOLD_PERCENT,
            step: COMPACT_THRESHOLD_PERCENT_STEP,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .selectedColor(this.themePrimary)
            .trackColor(getAppUiState().themeBackground)
            .blockColor(Color.White)
            .onChange((value: number, mode: SliderChangeMode) => {
              this.draggingThresholdPercent = value
              if (this.isSliderCommitted(mode)) {
                this.draggingThresholdPercent = -1
                this.onThresholdChange(value)
              }
            })

          Text(pickLocalizedText(
            `可选 ${MIN_COMPACT_THRESHOLD_PERCENT}% ~ ${MAX_COMPACT_THRESHOLD_PERCENT}%，默认 ${DEFAULT_COMPACT_THRESHOLD_PERCENT}%。`,
            `Range ${MIN_COMPACT_THRESHOLD_PERCENT}%–${MAX_COMPACT_THRESHOLD_PERCENT}%, default ${DEFAULT_COMPACT_THRESHOLD_PERCENT}%.`
          ))
            .fontSize(11)
            .lineHeight(16)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Color.Transparent)
    .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
    .systemMaterial(createToolServiceCardMaterial(false))
  }
}

@ComponentV2
struct SkillServiceCardItem {
  @Param skillEnabled: boolean = false
  @Param totalSkillCount: number = 0
  @Param enabledSkillCount: number = 0
  @Param skills: SkillConfig[] = []
  @Event onToggle: (enabled: boolean) => void = (_enabled: boolean) => {}
  @Event onCreateSkill: () => void = () => {}
  @Event onToggleSkillEnabled: (skillId: string, enabled: boolean) => void =
    (_skillId: string, _enabled: boolean) => {}
  @Event onEditSkill: (skill: SkillConfig) => void = (_skill: SkillConfig) => {}
  @Event onDeleteSkill: (skillId: string) => void = (_skillId: string) => {}
  @Local isSkillsExpanded: boolean = false

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private getStatusText(): string {
    if (!this.skillEnabled) {
      return pickLocalizedText('未启用', 'Disabled')
    }
    return formatLocalizedCount(this.enabledSkillCount, '个启用 Skill', 'enabled Skill', 'enabled Skills')
  }

  private getManageText(): string {
    return this.isSkillsExpanded ? pickLocalizedText('收起', 'Collapse') : pickLocalizedText('展开', 'Expand')
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        ChatFloatingImmersiveButton({
          barWidth: 44,
          barHeight: 44,
          iconResource: $r('sys.symbol.more'),
          iconSize: 20,
          iconColor: [this.themePrimary],
          responsePadding: 0,
          onButtonClick: (): void => {
            this.isSkillsExpanded = !this.isSkillsExpanded
          }
        }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.more'))
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
              .fontSize(20)
              .fontColor([this.themePrimary])
          }
          .width(44)
          .height(44)
        }

        Column({ space: 6 }) {
          Text('Skill')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Text(this.totalSkillCount > 0
            ? this.getStatusText()
            : pickLocalizedText('添加可被模型读取的技能说明', 'Add instructions the model can read'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.skillEnabled })
          .selectedColor(this.themePrimary)
          .systemMaterial(new uiMaterial.Material())
          .switchPointColor(Color.White)
          .onChange((value: boolean) => {
            this.onToggle(value)
          })
      }
      .width('100%')

      Row({ space: 10 }) {
        Button() {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
              .fontSize(13)
              .fontColor([Color.White])
            Text(pickLocalizedText('新增 Skill', 'Add Skill'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
          }
        }
        .height(32)
        .padding({ left: 14, right: 14 })
        .type(ButtonType.Capsule)
        .stateEffect(false)
        .backgroundColor(this.themePrimary)
        .onClick(() => {
          this.onCreateSkill()
        })

        Blank()

        Row({ space: 4 }) {
          Text(this.getManageText())
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)

          SymbolGlyph($r('sys.symbol.chevron_down'))
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .fontSize(12)
            .fontColor([this.themePrimary])
            .rotate({ angle: this.isSkillsExpanded ? 180 : 0 })
            .animation({ duration: 180, curve: Curve.EaseOut })
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .borderRadius(999)
        .backgroundColor(getAppUiState().themeBackground)
        .onClick(() => {
          this.isSkillsExpanded = !this.isSkillsExpanded
        })
      }
      .width('100%')

      if (this.isSkillsExpanded) {
        if (this.skills.length === 0) {
          Row({ space: 10 }) {
            Column() {
              SymbolGlyph($r('sys.symbol.doc_text_badge_magnifyingglass'))
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontSize(16)
                .fontColor([this.themePrimary])
            }
            .width(32)
            .height(32)
            .borderRadius(12)
            .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '24' : '12'))
            .justifyContent(FlexAlign.Center)

            Text(pickLocalizedText('还没有 Skill，点击新增创建。', 'No Skill yet. Tap Add to create one.'))
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
          }
          .width('100%')
          .padding(12)
          .borderRadius(16)
          .backgroundColor(getAppUiState().themeBackground)
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 }))
              .animation({ duration: 180, curve: Curve.EaseOut }),
            TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -6 }))
              .animation({ duration: 120, curve: Curve.EaseIn })
          ))
        } else {
          Column({ space: 10 }) {
            ForEach(this.skills, (skill: SkillConfig) => {
              SkillListCardItem({
                skill: skill,
                onToggleEnabled: (enabled: boolean) => {
                  this.onToggleSkillEnabled(skill.id, enabled)
                },
                onEdit: () => {
                  this.onEditSkill(skill)
                },
                onDelete: () => {
                  this.onDeleteSkill(skill.id)
                }
              })
            }, (skill: SkillConfig) => `${skill.id}_${skill.name}_${skill.description}_${skill.enabled ? '1' : '0'}_${skill.updatedAt}`)
          }
          .width('100%')
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 }))
              .animation({ duration: 180, curve: Curve.EaseOut }),
            TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -6 }))
              .animation({ duration: 120, curve: Curve.EaseIn })
          ))
        }
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Color.Transparent)
    .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
    .systemMaterial(createToolServiceCardMaterial(false))
    .animation({ duration: 220, curve: Curve.EaseInOut })
  }
}

@ComponentV2
struct SkillListCardItem {
  @Param skill: SkillConfig = new SkillConfig()
  @Event onToggleEnabled: (enabled: boolean) => void = (_enabled: boolean) => {}
  @Event onEdit: () => void = () => {}
  @Event onDelete: () => void = () => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private getDescription(): string {
    const description = this.skill.description.trim()
    if (description !== '') {
      return description
    }
    return pickLocalizedText('无描述', 'No description')
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.doc_text_badge_magnifyingglass'))
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .fontSize(18)
            .fontColor([this.themePrimary])
        }
        .width(38)
        .height(38)
        .borderRadius(14)
        .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '24' : '12'))
        .justifyContent(FlexAlign.Center)

        Column({ space: 5 }) {
          Text(this.skill.name)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.getDescription())
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.skill.enabled })
          .selectedColor(this.themePrimary)
          .systemMaterial(new uiMaterial.Material())
          .switchPointColor(Color.White)
          .onChange((value: boolean) => {
            this.onToggleEnabled(value)
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Blank()

        Button(pickLocalizedText('编辑', 'Edit'))
          .height(30)
          .fontSize(11)
          .type(ButtonType.Capsule)
          .stateEffect(false)
          .fontColor(this.themePrimary)
          .backgroundColor(getAppUiState().themeBackground)
          .onClick(() => {
            this.onEdit()
          })

        Button($r('app.string.delete'))
          .height(30)
          .fontSize(11)
          .type(ButtonType.Capsule)
          .stateEffect(false)
          .fontColor('#D9485F')
          .backgroundColor(getAppUiState().themeBackground)
          .onClick(() => {
            this.onDelete()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor(Color.Transparent)
    .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
    .systemMaterial(createToolServiceCardMaterial(false))
  }
}

@ComponentV2
struct BuiltinToolCardItem {
  @Param tool: ToolConfig = new ToolConfig()
  @Param selected: boolean = false
  @Param configurable: boolean = false
  @Event onToggle: (enabled: boolean) => void = (_enabled: boolean): void => {}
  @Event onConfigure: () => void = (): void => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get backgroundHex(): string {
    return getAppUiState().themeBackground
  }

  private isWriteTool(): boolean {
    return this.tool.permissionLevel === 'write'
  }

  private getPermissionText(): string {
    return this.isWriteTool() ? pickLocalizedText('需确认', 'Approval') : pickLocalizedText('只读', 'Read only')
  }

  private getPermissionTextColor(): string {
    return this.isWriteTool() ? '#D9485F' : this.themePrimary
  }

  private getPermissionBackgroundColor(): string {
    if (this.isWriteTool()) {
      return this.isDarkMode ? '#4B1D24' : '#FDECEF'
    }
    return this.backgroundHex
  }

  private getToolSymbolResource(toolId: string): Resource {
    if (toolId === 'web_search') {
      return $r('sys.symbol.worldclock_fill_2')
    }
    if (toolId === 'ask_user') {
      return $r('sys.symbol.ellipsis_message')
    }
    if (toolId === 'sub_agent') {
      return $r('sys.symbol.protein')
    }
    if (toolId === 'python_sandbox') {
      return $r('sys.symbol.doc_text')
    }
    if (toolId === 'canvas_document') {
      return $r('sys.symbol.paintbrush_pointed_waveform')
    }
    if (toolId === 'pdf_to_text') {
      return $r('sys.symbol.pdf_doc')
    }
    if (toolId === 'image_to_text') {
      return $r('sys.symbol.picture')
    }
    if (toolId === 'vision_read_image') {
      return $r('sys.symbol.picture')
    }
    if (toolId === 'use_skill') {
      return $r('sys.symbol.more')
    }
    if (toolId === 'math_chart') {
      return $r('sys.symbol.histogram')
    }
    if (toolId === 'read_schedule') {
      return $r('sys.symbol.calendar')
    }
    if (toolId === 'write_schedule') {
      return $r('sys.symbol.calendar_badge_plus')
    }
    return $r('sys.symbol.wrench_and_screwdriver')
  }

  @Builder
  private ToolIcon(toolId: string, size: number) {
    if (toolId === 'docx_to_text') {
      Image($r('app.media.doc_docx'))
        .width(size)
        .height(size)
        .fillColor(this.themePrimary)
    } else if (toolId === 'xlsx_to_text') {
      Image($r('app.media.doc_xlsx'))
        .width(size)
        .height(size)
        .fillColor(this.themePrimary)
    } else {
      SymbolGlyph(this.getToolSymbolResource(toolId))
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontSize(size)
        .fontColor([this.themePrimary])
    }
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        ChatFloatingImmersiveButton({
          barWidth: 44,
          barHeight: 44,
          iconResource: this.getToolSymbolResource(this.tool.id),
          iconSize: 20,
          iconColor: [this.themePrimary],
          responsePadding: 0
        }) {
          Stack({ alignContent: Alignment.Center }) {
            this.ToolIcon(this.tool.id, 20)
          }
          .width(44)
          .height(44)
        }

        Column({ space: 6 }) {
          Text(getLocalizedBuiltinToolName(this.tool.id, this.tool.name))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(getLocalizedBuiltinToolDescription(this.tool.id, this.tool.description))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.selected })
          .selectedColor(this.themePrimary)
          .systemMaterial(new uiMaterial.Material())
          .switchPointColor(Color.White)
          .onChange((value: boolean) => {
            this.onToggle(value)
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        Text(this.tool.id)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(999)
          .backgroundColor(this.themePrimaryLight)

        Text(this.getPermissionText())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getPermissionTextColor())
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(999)
          .backgroundColor(this.getPermissionBackgroundColor())
          .border({ width: this.isWriteTool() ? 0 : 1, color: this.themePrimary })

        Blank()

        if (this.configurable) {
          Button(pickLocalizedText('配置', 'Configure'))
            .height(28)
            .fontSize(11)
            .type(ButtonType.Capsule)
            .stateEffect(false)
            .fontColor(this.themePrimary)
            .backgroundColor(this.themePrimaryLight)
            .onClick(() => {
              this.onConfigure()
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Color.Transparent)
    .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
    .systemMaterial(createToolServiceCardMaterial(false))
  }
}

@ComponentV2
struct McpServerCardItem {
  @Param serverName: string = ''
  @Param serverBaseUrl: string = ''
  @Param serverEnabled: boolean = false
  @Param tools: ToolConfig[] = []
  @Param authLabel: string = 'None'
  @Param customHeaderCount: number = 0
  @Event onToggleEnabled: (enabled: boolean) => void = (_enabled: boolean) => {}
  @Event onRefresh: () => void = () => {}
  @Event onEdit: () => void = () => {}
  @Event onDelete: () => void = () => {}
  @Local isToolsExpanded: boolean = false

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get backgroundHex(): string {
    return getAppUiState().themeBackground
  }

  private get dividerHex(): string {
    return getAppUiState().themeDivider
  }

  private getWriteToolCount(): number {
    let count = 0
    for (let i = 0; i < this.tools.length; i++) {
      if (this.tools[i].permissionLevel === 'write') {
        count += 1
      }
    }
    return count
  }

  private getToolPreviewText(): string {
    if (this.tools.length === 0) {
      return pickLocalizedText('暂未发现工具。', 'No tools discovered yet.')
    }
    const names: string[] = []
    const maxVisible = Math.min(this.tools.length, 5)
    for (let i = 0; i < maxVisible; i++) {
      names.push(this.tools[i].name)
    }
    const suffix = this.tools.length > maxVisible
      ? pickLocalizedText(` 等 ${this.tools.length} 个`, ` and ${this.tools.length} total`)
      : ''
    return `${names.join(' · ')}${suffix}`
  }

  private getToolToggleText(): string {
    return this.isToolsExpanded ? pickLocalizedText('收起工具', 'Collapse') : pickLocalizedText('展开工具', 'Expand')
  }

  private getToolCountText(): string {
    return this.tools.length > 0
      ? formatLocalizedCount(this.tools.length, '个工具', 'tool', 'tools')
      : pickLocalizedText('尚未发现工具', 'No tools discovered')
  }

  private getCustomHeaderCountText(): string {
    return formatLocalizedCount(this.customHeaderCount, '个请求头', 'header', 'headers')
  }

  private getWriteToolCountText(): string {
    return formatLocalizedCount(this.getWriteToolCount(), '个需确认', 'tool needs approval', 'tools need approval')
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        ChatFloatingImmersiveButton({
          barWidth: 46,
          barHeight: 46,
          iconResource: $r('sys.symbol.cloud'),
          iconSize: 22,
          iconColor: [this.themePrimary],
          responsePadding: 0,
          onButtonClick: (): void => {
            this.onEdit()
          }
        }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.cloud'))
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
              .fontSize(22)
              .fontColor([this.themePrimary])
          }
          .width(46)
          .height(46)
        }

        Column({ space: 6 }) {
          Text(this.serverName)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.serverBaseUrl)
            .fontSize(11)
            .lineHeight(16)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.serverEnabled })
          .selectedColor(this.themePrimary)
          .systemMaterial(new uiMaterial.Material())
          .switchPointColor(Color.White)
          .onChange((value: boolean) => {
            this.onToggleEnabled(value)
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Text(this.getToolCountText())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(999)
          .backgroundColor(getAppUiState().themeBackground)

        if (this.authLabel !== 'None') {
          Text(this.authLabel)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(999)
            .backgroundColor(this.backgroundHex)
            .border({ width: 1, color: this.themePrimary })
        }

        if (this.customHeaderCount > 0) {
          Text(this.getCustomHeaderCountText())
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(999)
            .backgroundColor(getAppUiState().themeBackground)
        }

        if (this.getWriteToolCount() > 0) {
          Text(this.getWriteToolCountText())
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor('#D9485F')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(999)
            .backgroundColor(this.isDarkMode ? '#4B1D24' : '#FDECEF')
        }
      }
      .width('100%')

      Column({ space: 10 }) {
        Row() {
          Text(this.tools.length > 0 ? this.getToolPreviewText() : pickLocalizedText('暂未发现工具', 'No tools discovered'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .maxLines(this.isToolsExpanded ? 10 : 3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.tools.length > 0) {
            Row({ space: 4 }) {
              Text(this.getToolToggleText())
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)

              SymbolGlyph($r('sys.symbol.chevron_down'))
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontSize(12)
                .fontColor([this.themePrimary])
                .rotate({ angle: this.isToolsExpanded ? 180 : 0 })
                .animation({ duration: 180, curve: Curve.EaseOut })
            }
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(999)
            .backgroundColor(this.backgroundHex)
            .border({ width: 1, color: this.themePrimary })
            .onClick(() => {
              this.isToolsExpanded = !this.isToolsExpanded
            })
          }
        }
        .width('100%')

        if (this.isToolsExpanded && this.tools.length > 0) {
          Column({ space: 8 }) {
            ForEach(this.tools, (tool: ToolConfig) => {
              Row({ space: 8 }) {
                Column({ space: 3 }) {
                  Text(tool.name)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))

                  Text(tool.description.length > 0 ? tool.description : tool.id)
                    .fontSize(11)
                    .lineHeight(16)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                if (tool.permissionLevel === 'write') {
                  Text(pickLocalizedText('需确认', 'Approval'))
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#D9485F')
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .borderRadius(999)
                    .backgroundColor(this.isDarkMode ? '#4B1D24' : '#FDECEF')
                }
              }
              .width('100%')
              .padding(12)
              .borderRadius(14)
              .backgroundColor(this.isDarkMode ? '#23262D' : Color.White)
              .border({ width: 1, color: this.isDarkMode ? '#2E323A' : '#EEF2F6' })
            }, (tool: ToolConfig) => tool.id)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(14)
      .borderRadius(18)
      .backgroundColor(this.backgroundHex)
      .border({ width: 1, color: this.dividerHex })

      Row({ space: 8 }) {
        Button(pickLocalizedText('刷新', 'Refresh'))
          .height(32)
          .fontSize(12)
          .type(ButtonType.Capsule)
          .stateEffect(false)
          .backgroundColor(this.backgroundHex)
          .border({ width: 1, color: this.themePrimary })
          .fontColor(this.themePrimary)
          .onClick(() => {
            this.onRefresh()
          })

        Button(pickLocalizedText('编辑', 'Edit'))
          .height(32)
          .fontSize(12)
          .type(ButtonType.Capsule)
          .stateEffect(false)
          .backgroundColor(this.backgroundHex)
          .border({ width: 1, color: this.dividerHex })
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.onEdit()
          })

        Blank()

        Button($r('app.string.delete'))
          .height(32)
          .fontSize(12)
          .type(ButtonType.Capsule)
          .stateEffect(false)
          .backgroundColor(this.backgroundHex)
          .border({ width: 1, color: this.isDarkMode ? '#6A3139' : '#F2CBD2' })
          .fontColor('#D9485F')
          .onClick(() => {
            this.onDelete()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Color.Transparent)
    .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
    .systemMaterial(createToolServiceCardMaterial(false))
  }
}
