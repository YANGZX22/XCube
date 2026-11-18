// 默认模型配置服务
import { getPreferencesService, PreferencesService, PreferenceKeys } from './PreferencesService'
import { DefaultModelConfig, ModelRole } from '../models/ChatModels'
import { DefaultPrompts } from '../config/DefaultPrompts'

// 默认模型服务 - 单例模式
export class DefaultModelService {
  private static instance: DefaultModelService | null = null
  private preferencesService: PreferencesService
  private isInitialized: boolean = false

  // 缓存模型配置
  private chatModel: DefaultModelConfig = new DefaultModelConfig()
  private titleModel: DefaultModelConfig = new DefaultModelConfig()
  private searchOptimizationModel: DefaultModelConfig = new DefaultModelConfig()

  // 缓存 Prompt 配置
  private titlePrompt: string = ''

  private constructor() {
    this.preferencesService = getPreferencesService()
  }

  static getInstance(): DefaultModelService {
    if (DefaultModelService.instance === null) {
      DefaultModelService.instance = new DefaultModelService()
    }
    return DefaultModelService.instance
  }

  // 初始化加载配置
  async initialize(): Promise<void> {
    if (this.isInitialized) {
      return
    }
    await this.loadConfig()
    this.isInitialized = true
  }

  // 加载所有配置
  async loadConfig(): Promise<void> {
    // 加载聊天模型配置
    const chatModelId = await this.preferencesService.getString(PreferenceKeys.DEFAULT_CHAT_MODEL_ID, '')
    const chatProviderId = await this.preferencesService.getString(PreferenceKeys.DEFAULT_CHAT_PROVIDER_ID, '')
    const chatModelName = await this.preferencesService.getString(PreferenceKeys.DEFAULT_CHAT_MODEL_NAME, '')
    const chatProviderName = await this.preferencesService.getString(PreferenceKeys.DEFAULT_CHAT_PROVIDER_NAME, '')
    this.chatModel = new DefaultModelConfig(chatModelId, chatProviderId, chatModelName, chatProviderName)

    // 加载标题模型配置（默认使用硅基流动免费模型）
    const titleModelId = await this.preferencesService.getString(
      PreferenceKeys.DEFAULT_TITLE_MODEL_ID,
      DefaultPrompts.SILICONFLOW_TITLE_MODEL
    )
    const titleProviderId = await this.preferencesService.getString(
      PreferenceKeys.DEFAULT_TITLE_PROVIDER_ID,
      DefaultPrompts.SILICONFLOW_PROVIDER_ID
    )
    const titleModelName = await this.preferencesService.getString(
      PreferenceKeys.DEFAULT_TITLE_MODEL_NAME,
      DefaultPrompts.SILICONFLOW_TITLE_MODEL
    )
    const titleProviderName = await this.preferencesService.getString(
      PreferenceKeys.DEFAULT_TITLE_PROVIDER_NAME,
      '硅基流动'
    )
    this.titleModel = new DefaultModelConfig(titleModelId, titleProviderId, titleModelName, titleProviderName)

    // 加载搜索优化模型配置（默认使用硅基流动快速模型）
    const searchOptModelId = await this.preferencesService.getString(
      PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_MODEL_ID,
      DefaultPrompts.SILICONFLOW_SEARCH_OPTIMIZATION_MODEL
    )
    const searchOptProviderId = await this.preferencesService.getString(
      PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_PROVIDER_ID,
      DefaultPrompts.SILICONFLOW_PROVIDER_ID
    )
    const searchOptModelName = await this.preferencesService.getString(
      PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_MODEL_NAME,
      DefaultPrompts.SILICONFLOW_SEARCH_OPTIMIZATION_MODEL
    )
    const searchOptProviderName = await this.preferencesService.getString(
      PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_PROVIDER_NAME,
      '硅基流动'
    )
    this.searchOptimizationModel = new DefaultModelConfig(searchOptModelId, searchOptProviderId, searchOptModelName, searchOptProviderName)

    // 加载 Prompt 配置
    this.titlePrompt = await this.preferencesService.getString(
      PreferenceKeys.TITLE_PROMPT_TEMPLATE,
      DefaultPrompts.TITLE_PROMPT
    )
  }

  // 获取指定角色的模型配置
  getModel(role: ModelRole): DefaultModelConfig {
    if (role === ModelRole.CHAT) {
      return this.chatModel
    } else if (role === ModelRole.TITLE) {
      return this.titleModel
    } else if (role === ModelRole.SEARCH_OPTIMIZATION) {
      return this.searchOptimizationModel
    }
    return new DefaultModelConfig()
  }

  // 设置模型配置
  async setModel(role: ModelRole, config: DefaultModelConfig): Promise<void> {
    if (role === ModelRole.CHAT) {
      this.chatModel = config
      await this.preferencesService.setString(PreferenceKeys.DEFAULT_CHAT_MODEL_ID, config.modelId)
      await this.preferencesService.setString(PreferenceKeys.DEFAULT_CHAT_PROVIDER_ID, config.providerId)
      await this.preferencesService.setString(PreferenceKeys.DEFAULT_CHAT_MODEL_NAME, config.modelName)
      await this.preferencesService.setString(PreferenceKeys.DEFAULT_CHAT_PROVIDER_NAME, config.providerName)
    } else if (role === ModelRole.TITLE) {
      this.titleModel = config
      await this.preferencesService.setString(PreferenceKeys.DEFAULT_TITLE_MODEL_ID, config.modelId)
      await this.preferencesService.setString(PreferenceKeys.DEFAULT_TITLE_PROVIDER_ID, config.providerId)
      await this.preferencesService.setString(PreferenceKeys.DEFAULT_TITLE_MODEL_NAME, config.modelName)
      await this.preferencesService.setString(PreferenceKeys.DEFAULT_TITLE_PROVIDER_NAME, config.providerName)
    } else if (role === ModelRole.SEARCH_OPTIMIZATION) {
      this.searchOptimizationModel = config
      await this.preferencesService.setString(PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_MODEL_ID, config.modelId)
      await this.preferencesService.setString(PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_PROVIDER_ID, config.providerId)
      await this.preferencesService.setString(PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_MODEL_NAME, config.modelName)
      await this.preferencesService.setString(PreferenceKeys.DEFAULT_SEARCH_OPTIMIZATION_PROVIDER_NAME, config.providerName)
    }
  }

  // 获取格式化的标题生成 System Prompt
  getTitleSystemPrompt(locale: string): string {
    return DefaultPrompts.TITLE_SYSTEM_PROMPT.replace(/\{locale\}/g, () => locale)
  }

  // 获取格式化的标题生成 User Prompt
  getTitleUserPrompt(content: string): string {
    return DefaultPrompts.TITLE_USER_PROMPT.replace(/\{content\}/g, () => content)
  }

  // 一次替换模板中的所有变量，传入的原文保持字面值。
  getTitlePrompt(content: string, locale: string): string {
    return this.titlePrompt.replace(/\{(?:content|locale)\}/g, (token: string) => token === '{content}' ? content : locale)
  }

  // 获取标题 Prompt 模板
  getTitlePromptTemplate(): string {
    return this.titlePrompt
  }

  // 设置标题 Prompt 模板
  async setTitlePromptTemplate(prompt: string): Promise<void> {
    this.titlePrompt = prompt
    await this.preferencesService.setString(PreferenceKeys.TITLE_PROMPT_TEMPLATE, prompt)
  }

  // 重置标题 Prompt 为默认值
  async resetTitlePrompt(): Promise<void> {
    this.titlePrompt = DefaultPrompts.TITLE_PROMPT
    await this.preferencesService.setString(PreferenceKeys.TITLE_PROMPT_TEMPLATE, DefaultPrompts.TITLE_PROMPT)
  }

  // 检查是否使用默认标题 Prompt
  isDefaultTitlePrompt(): boolean {
    return this.titlePrompt === DefaultPrompts.TITLE_PROMPT
  }
}

// 导出单例实例获取方法
export function getDefaultModelService(): DefaultModelService {
  return DefaultModelService.getInstance()
}
