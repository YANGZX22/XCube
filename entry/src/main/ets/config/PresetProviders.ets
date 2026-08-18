/**
 * 预设供应商配置
 * 定义内置的模型供应商，这些供应商不可删除
 */

import { ProviderType, ApiStyle, OpenAITransport, ProviderIconType, ModelProvider } from '../models/ChatModels'
import { DEFAULT_PRIMARY_COLOR } from './ThemeDefaults'
import { buildLobeIconUrl } from '../utils/LobeIconResolver'

// 预设供应商配置接口
export interface PresetProviderConfig {
  id: string
  name: string
  type: ProviderType
  apiStyle: ApiStyle
  openaiTransport?: OpenAITransport
  baseUrl: string
  autoInitialize?: boolean // 是否在服务商管理中默认创建；默认为 true
  requiresApiKey?: boolean
  iconPath: string      // SVG 图标路径（已弃用，置空）
  brandColorHex: string // 品牌色（十六进制）
  presetApiKey?: string // 预设 API Key（可选，用户不填时使用）
  textIcon: string      // 文字图标内容（也作为远程 logo 加载失败的兜底显示）
  textIconBgColor: string // 文字图标背景色
  // @lobehub/icons-static-svg 中的文件名（不含 .svg）。留空时显示文字图标。
  lobeIconFileName?: string
}

// 预设供应商列表（主流厂商，不可删除）
const PRESET_PROVIDERS: PresetProviderConfig[] = [
  {
    id: 'openai',
    name: 'OpenAI',
    type: ProviderType.OPENAI,
    apiStyle: ApiStyle.OPENAI,
    openaiTransport: OpenAITransport.CHAT_COMPLETIONS,
    baseUrl: 'https://api.openai.com/v1',
    iconPath: '',
    brandColorHex: '#202123',
    textIcon: 'AI',
    textIconBgColor: '#202123',
    lobeIconFileName: 'openai'
  },
  {
    id: 'anthropic',
    name: 'Claude',
    type: ProviderType.ANTHROPIC,
    apiStyle: ApiStyle.ANTHROPIC,
    openaiTransport: OpenAITransport.CHAT_COMPLETIONS,
    baseUrl: 'https://api.anthropic.com',
    iconPath: '',
    brandColorHex: '#C45C3A',
    textIcon: 'C',
    textIconBgColor: '#C45C3A',
    lobeIconFileName: 'anthropic'
  },
  {
    id: 'deepseek',
    name: 'DeepSeek',
    type: ProviderType.DEEPSEEK,
    apiStyle: ApiStyle.OPENAI,
    openaiTransport: OpenAITransport.CHAT_COMPLETIONS,
    baseUrl: 'https://api.deepseek.com/v1',
    iconPath: '',
    brandColorHex: '#4D6BFE',
    textIcon: 'DS',
    textIconBgColor: '#4D6BFE',
    lobeIconFileName: 'deepseek-color'
  },
  {
    id: 'gemini',
    name: 'Gemini',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.GOOGLE,
    openaiTransport: OpenAITransport.CHAT_COMPLETIONS,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    iconPath: '',
    brandColorHex: '#4285F4',
    textIcon: 'G',
    textIconBgColor: '#4285F4',
    lobeIconFileName: 'gemini-color'
  },
  {
    id: 'openrouter',
    name: 'OpenRouter',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://openrouter.ai/api/v1',
    iconPath: '',
    brandColorHex: '#6366F1',
    textIcon: 'OR',
    textIconBgColor: '#6366F1',
    lobeIconFileName: 'openrouter-color'
  },
  {
    id: 'groq',
    name: 'Groq',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    openaiTransport: OpenAITransport.CHAT_COMPLETIONS,
    baseUrl: 'https://api.groq.com/openai/v1',
    iconPath: '',
    brandColorHex: '#F55036',
    textIcon: 'GQ',
    textIconBgColor: '#F55036',
    lobeIconFileName: 'groq'
  },
  {
    id: 'together',
    name: 'Together AI',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    openaiTransport: OpenAITransport.CHAT_COMPLETIONS,
    baseUrl: 'https://api.together.ai/v1',
    iconPath: '',
    brandColorHex: '#111827',
    textIcon: 'TA',
    textIconBgColor: '#111827',
    lobeIconFileName: 'together-color'
  },
  {
    id: 'nvidia',
    name: 'NVIDIA NIM',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    openaiTransport: OpenAITransport.CHAT_COMPLETIONS,
    baseUrl: 'https://integrate.api.nvidia.com/v1',
    iconPath: '',
    brandColorHex: '#76B900',
    textIcon: 'NV',
    textIconBgColor: '#76B900',
    lobeIconFileName: 'nvidia-color'
  },
  {
    id: 'siliconflow',
    name: '硅基流动',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://api.siliconflow.cn/v1',
    iconPath: '',
    brandColorHex: '#7C3AED',
    textIcon: 'SF',
    textIconBgColor: '#7C3AED',
    lobeIconFileName: 'siliconcloud-color'
  },
  {
    id: 'qwen',
    name: '阿里云百炼',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    iconPath: '',
    brandColorHex: '#615CED',
    textIcon: 'Q',
    textIconBgColor: '#615CED',
    lobeIconFileName: 'qwen-color'
  },
  {
    id: 'kimi',
    name: 'Kimi',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://api.moonshot.cn/v1',
    iconPath: '',
    brandColorHex: '#0F172A',
    textIcon: 'K',
    textIconBgColor: '#0F172A',
    lobeIconFileName: 'kimi-color'
  },
  {
    id: 'zhipu',
    name: '智谱 AI',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    iconPath: '',
    brandColorHex: '#3B82F6',
    textIcon: 'Z',
    textIconBgColor: '#3B82F6',
    lobeIconFileName: 'zhipu-color'
  },
  {
    id: 'doubao',
    name: '火山引擎',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    iconPath: '',
    brandColorHex: '#3370FF',
    textIcon: 'D',
    textIconBgColor: '#3370FF',
    lobeIconFileName: 'volcengine-color'
  },
  {
    id: 'minimax',
    name: 'MiniMax',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://api.minimaxi.com/v1',
    iconPath: '',
    brandColorHex: '#00A876',
    textIcon: 'M',
    textIconBgColor: '#00A876',
    lobeIconFileName: 'minimax-color'
  },
  {
    id: 'aihubmix',
    name: 'AiHubMix',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://aihubmix.com/v1',
    iconPath: '',
    brandColorHex: '#D97706',
    textIcon: 'AH',
    textIconBgColor: '#D97706',
    lobeIconFileName: 'aihubmix-color'
  },
  {
    id: 'grok',
    name: 'Grok',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://api.x.ai/v1',
    iconPath: '',
    brandColorHex: '#000000',
    textIcon: 'G',
    textIconBgColor: '#000000',
    lobeIconFileName: 'xai'
  },
  {
    id: 'aiping',
    name: 'AIPing',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://aiping.cn/api/v1',
    autoInitialize: false,
    iconPath: '',
    brandColorHex: '#6C5CE7',
    textIcon: 'AP',
    textIconBgColor: '#6C5CE7'
  },
  {
    id: 'mimo',
    name: 'MiMo',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    openaiTransport: OpenAITransport.CHAT_COMPLETIONS,
    baseUrl: 'https://api.xiaomimimo.com/v1',
    iconPath: '',
    brandColorHex: '#FF6900',
    textIcon: 'Mi',
    textIconBgColor: '#FF6900',
    lobeIconFileName: 'xiaomimimo'
  },
  {
    id: 'ollama',
    name: 'Ollama',
    type: ProviderType.OLLAMA,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'http://localhost:11434/v1',
    requiresApiKey: false,
    iconPath: '',
    brandColorHex: '#FFFFFF',
    textIcon: '🦙',
    textIconBgColor: '',
    lobeIconFileName: 'ollama'
  }
]

// 预设供应商 ID 集合（用于快速判断）
const PRESET_PROVIDER_IDS: Set<string> = new Set(PRESET_PROVIDERS.map(p => p.id))

/**
 * 获取所有预设供应商配置
 */
export function getPresetProviders(): PresetProviderConfig[] {
  return PRESET_PROVIDERS
}

/**
 * 获取应自动初始化到服务商管理页的预设服务商。
 */
export function getAutoInitializedPresetProviders(): PresetProviderConfig[] {
  const result: PresetProviderConfig[] = []
  for (let i = 0; i < PRESET_PROVIDERS.length; i++) {
    if (PRESET_PROVIDERS[i].autoInitialize !== false) {
      result.push(PRESET_PROVIDERS[i])
    }
  }
  return result
}

/**
 * 根据 ID 获取预设供应商配置
 */
export function getPresetProviderById(id: string): PresetProviderConfig | null {
  for (let i = 0; i < PRESET_PROVIDERS.length; i++) {
    if (PRESET_PROVIDERS[i].id === id) {
      return PRESET_PROVIDERS[i]
    }
  }
  return null
}

/**
 * 判断是否为预设供应商
 */
export function isPresetProvider(providerId: string): boolean {
  return PRESET_PROVIDER_IDS.has(providerId)
}

/**
 * 获取供应商图标路径
 * @param providerId 供应商 ID
 * @returns 图标文件路径，如果不是预设供应商则返回空字符串
 */
export function getPresetProviderIconPath(providerId: string): string {
  const preset = getPresetProviderById(providerId)
  if (preset !== null) {
    return preset.iconPath
  }
  return ''
}

/**
 * 获取供应商品牌色
 * @param providerId 供应商 ID
 * @returns 品牌色十六进制值，如果不是预设供应商则返回默认色
 */
export function getPresetProviderBrandColor(providerId: string): string {
  const preset = getPresetProviderById(providerId)
  if (preset !== null) {
    return preset.brandColorHex
  }
  return DEFAULT_PRIMARY_COLOR
}

/**
 * 获取供应商的有效 API Key
 * 如果用户配置了 API Key 则使用用户的，否则使用预设的
 * @param providerId 供应商 ID
 * @param userApiKey 用户配置的 API Key
 * @returns 有效的 API Key
 */
export function getEffectiveApiKey(providerId: string, userApiKey: string): string {
  // 如果用户配置了 API Key，优先使用
  if (userApiKey !== '') {
    return userApiKey
  }
  // 否则尝试使用预设的 API Key
  const preset = getPresetProviderById(providerId)
  if (preset !== null && preset.presetApiKey !== undefined) {
    return preset.presetApiKey
  }
  return ''
}

export function isPresetProviderApiKeyRequired(providerId: string): boolean {
  const preset = getPresetProviderById(providerId)
  if (preset !== null && preset.requiresApiKey !== undefined) {
    return preset.requiresApiKey
  }
  return true
}

/**
 * 由 lobeIconFileName 拼接固定版本的 @lobehub/icons-static-svg CDN URL。
 * 没有 lobeIconFileName 返回空字符串。
 */
export function getPresetProviderLogoUrl(providerId: string): string {
  const preset = getPresetProviderById(providerId)
  if (preset === null || preset.lobeIconFileName === undefined || preset.lobeIconFileName === '') {
    return ''
  }
  return buildLobeIconUrl(preset.lobeIconFileName)
}

/**
 * 把预设服务商的默认图标配置写入 ModelProvider：
 * 有远程 logo 用 IMAGE+URL，否则用 TEXT；textIcon/bg 总是写入预设值作为兜底。
 * 返回 true 表示已应用，false 表示 providerId 不是预设服务商。
 */
export function applyPresetIconDefaults(provider: ModelProvider, providerId: string): boolean {
  const preset = getPresetProviderById(providerId)
  if (preset === null) {
    return false
  }
  provider.iconPath = ''
  provider.textIcon = preset.textIcon
  provider.textIconBgColor = preset.textIconBgColor
  const logoUrl = getPresetProviderLogoUrl(providerId)
  if (logoUrl !== '') {
    provider.iconType = ProviderIconType.IMAGE
    provider.customImagePath = logoUrl
  } else {
    provider.iconType = ProviderIconType.TEXT
    provider.customImagePath = ''
  }
  return true
}

/**
 * 获取未配置的预置服务商列表
 * @param configuredIds 已配置的服务商 ID 列表
 * @returns 未配置的预置服务商配置列表
 */
export function getUnconfiguredPresetProviders(configuredIds: string[]): PresetProviderConfig[] {
  const configuredSet = new Set<string>(configuredIds)
  const result: PresetProviderConfig[] = []
  for (let i = 0; i < PRESET_PROVIDERS.length; i++) {
    const preset = PRESET_PROVIDERS[i]
    if (!configuredSet.has(preset.id)) {
      result.push(preset)
    }
  }
  return result
}
