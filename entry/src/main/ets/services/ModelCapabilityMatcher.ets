import { http } from '@kit.NetworkKit'
import { ModelInfo, InputMode, OutputMode } from '../models/ChatModels'
import { PreferenceKeys, getPreferencesService, DEFAULT_MODELS_DEV_BASE_URL } from './PreferencesService'

// models.dev 单个模型的数据结构
interface ModelsDevModalities {
  input: string[]
  output: string[]
}

interface ModelsDevLimit {
  context: number
  output: number
}

interface ModelsDevEntry {
  id: string
  name: string
  family: string
  reasoning: boolean
  tool_call: boolean
  modalities: ModelsDevModalities
  limit: ModelsDevLimit
}

// models.dev 供应商结构
interface ModelsDevProvider {
  id: string
  models: Record<string, ModelsDevEntry>
}

// models.dev 顶层结构：供应商 ID → 供应商对象
type ModelsDevData = Record<string, ModelsDevProvider>

// 模型能力匹配服务（单例）
export class ModelCapabilityMatcher {
  private static instance: ModelCapabilityMatcher | null = null
  // 扁平化缓存：模型 ID → 模型条目
  private cache: Map<string, ModelsDevEntry> = new Map()
  // 小写索引：模型 ID 小写 → 原始模型 ID（用于大小写不敏感回退匹配）
  private lowerCaseIndex: Map<string, string> = new Map()
  private cacheTimestamp: number = 0
  private readonly CACHE_TTL: number = 24 * 60 * 60 * 1000 // 24h
  private fetchPromise: Promise<boolean> | null = null

  private constructor() {
  }

  static getInstance(): ModelCapabilityMatcher {
    if (ModelCapabilityMatcher.instance === null) {
      ModelCapabilityMatcher.instance = new ModelCapabilityMatcher()
    }
    return ModelCapabilityMatcher.instance
  }

  // 批量匹配并填充模型能力，返回成功匹配数量
  async applyCapabilitiesBatch(models: ModelInfo[]): Promise<number> {
    let matched = 0
    const fallbackMatchedIndexes: Set<number> = new Set()
    for (let i = 0; i < models.length; i++) {
      if (this.applyKnownCapabilityFallback(models[i])) {
        fallbackMatchedIndexes.add(i)
        matched++
      }
    }

    const prefs = getPreferencesService()
    const enabled = await prefs.getBoolean(PreferenceKeys.MODELS_DEV_ENABLED, true)
    if (!enabled) {
      return matched
    }

    const loaded = await this.ensureCache()
    if (!loaded) {
      return matched
    }

    for (let i = 0; i < models.length; i++) {
      const model = models[i]
      const entry = this.findEntry(model.id)
      if (entry !== null) {
        this.applyEntry(model, entry)
        if (!fallbackMatchedIndexes.has(i)) {
          matched++
        }
      }
    }
    return matched
  }

  // 确保缓存已加载
  private async ensureCache(): Promise<boolean> {
    if (this.cache.size > 0 && (Date.now() - this.cacheTimestamp) < this.CACHE_TTL) {
      return true
    }
    // 避免并发重复请求
    if (this.fetchPromise !== null) {
      return await this.fetchPromise
    }
    this.fetchPromise = this.fetchAndBuildCache()
    const result = await this.fetchPromise
    this.fetchPromise = null
    return result
  }

  // 从 models.dev 拉取数据并构建扁平化缓存
  private async fetchAndBuildCache(): Promise<boolean> {
    try {
      const prefs = getPreferencesService()
      const baseUrl = await prefs.getString(PreferenceKeys.MODELS_DEV_BASE_URL, DEFAULT_MODELS_DEV_BASE_URL)
      const url = `${baseUrl}/api.json`

      const httpRequest = http.createHttp()
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 30000
      })
      httpRequest.destroy()

      if (response.responseCode !== 200) {
        console.warn('ModelCapabilityMatcher', `HTTP ${response.responseCode}`)
        return false
      }

      const raw = response.result as string
      const data: ModelsDevData = JSON.parse(raw) as ModelsDevData
      this.cache.clear()
      this.lowerCaseIndex.clear()

      // 扁平化各供应商的模型数据；图标匹配由 LobeIconResolver 独立负责。
      const providerKeys = Object.keys(data)
      for (let i = 0; i < providerKeys.length; i++) {
        const providerKey = providerKeys[i]
        const provider = data[providerKey]
        if (provider.models === undefined || provider.models === null) {
          continue
        }
        const modelKeys = Object.keys(provider.models)
        for (let j = 0; j < modelKeys.length; j++) {
          const entry = provider.models[modelKeys[j]]
          // 构建模型缓存：优先保留有 family 信息的条目
          const existing = this.cache.get(entry.id)
          if (existing === undefined ||
            (existing.family === undefined || existing.family === '') &&
            (entry.family !== undefined && entry.family !== '')) {
            this.cache.set(entry.id, entry)
            this.lowerCaseIndex.set(entry.id.toLowerCase(), entry.id)
          } else if (this.lowerCaseIndex.get(entry.id.toLowerCase()) === undefined) {
            this.lowerCaseIndex.set(entry.id.toLowerCase(), entry.id)
          }
        }
      }

      this.cacheTimestamp = Date.now()
      console.info('ModelCapabilityMatcher', `Cache built: ${this.cache.size} models`)
      return true
    } catch (error) {
      console.warn('ModelCapabilityMatcher', `Fetch failed: ${JSON.stringify(error)}`)
      return false
    }
  }

  // 通过小写索引查找缓存条目（大小写不敏感回退）
  private getCaseInsensitive(key: string): ModelsDevEntry | null {
    const originalId = this.lowerCaseIndex.get(key.toLowerCase())
    if (originalId !== undefined) {
      const entry = this.cache.get(originalId)
      if (entry !== undefined) {
        return entry
      }
    }
    return null
  }

  // 按优先级查找匹配的模型条目
  private findEntry(modelId: string): ModelsDevEntry | null {
    // 1. 精确匹配
    const exact = this.cache.get(modelId)
    if (exact !== undefined) {
      return exact
    }

    // 2. 去供应商前缀：取最后一个 / 后的内容，兼容聚合商多层路径
    //    如 deepseek-ai/deepseek-v3.2 → deepseek-v3.2
    const slashIndex = modelId.lastIndexOf('/')
    if (slashIndex >= 0) {
      const stripped = modelId.substring(slashIndex + 1)
      const found = this.cache.get(stripped)
      if (found !== undefined) {
        return found
      }
    }

    // 3. 去日期后缀：gpt-4o-2024-08-06 → gpt-4o
    const baseId = slashIndex >= 0 ? modelId.substring(slashIndex + 1) : modelId
    const datePattern = new RegExp('-\\d{4}[-]?\\d{0,2}[-]?\\d{0,2}$')
    const dateMatch = baseId.match(datePattern)
    if (dateMatch !== null) {
      const withoutDate = baseId.substring(0, dateMatch.index!)
      if (withoutDate.length > 0) {
        const found = this.cache.get(withoutDate)
        if (found !== undefined) {
          return found
        }
      }
    }

    // 4. 大小写不敏感回退：minimax-m2.1 → MiniMax-M2.1
    const ci1 = this.getCaseInsensitive(modelId)
    if (ci1 !== null) {
      return ci1
    }
    if (slashIndex >= 0) {
      const stripped = modelId.substring(slashIndex + 1)
      const ci2 = this.getCaseInsensitive(stripped)
      if (ci2 !== null) {
        return ci2
      }
    }
    if (dateMatch !== null) {
      const withoutDate = baseId.substring(0, dateMatch.index!)
      if (withoutDate.length > 0) {
        const ci3 = this.getCaseInsensitive(withoutDate)
        if (ci3 !== null) {
          return ci3
        }
      }
    }

    // 5. 最长前缀匹配：逐步去除末尾 -suffix 段，兼容中转站/聚合商附加后缀
    //    如 GPT-5.1-Xhigh → GPT-5.1, deepseek-r1-free → deepseek-r1
    let prefixCandidate = baseId
    let dashIdx = prefixCandidate.lastIndexOf('-')
    while (dashIdx > 0) {
      prefixCandidate = prefixCandidate.substring(0, dashIdx)
      const found = this.cache.get(prefixCandidate)
      if (found !== undefined) {
        return found
      }
      const ci = this.getCaseInsensitive(prefixCandidate)
      if (ci !== null) {
        return ci
      }
      dashIdx = prefixCandidate.lastIndexOf('-')
    }

    return null
  }

  // 将 models.dev 条目的能力映射到 ModelInfo
  private applyEntry(model: ModelInfo, entry: ModelsDevEntry): void {
    // tool_call → supportsTools
    if (entry.tool_call) {
      model.capabilities.supportsTools = true
    }
    // reasoning → supportsReasoning
    if (entry.reasoning) {
      model.capabilities.supportsReasoning = true
    }
    // modalities.input 含 "image" → supportsVision + inputMode
    if (entry.modalities !== undefined && entry.modalities !== null &&
      entry.modalities.input !== undefined && entry.modalities.input !== null) {
      for (let i = 0; i < entry.modalities.input.length; i++) {
        if (entry.modalities.input[i] === 'image') {
          model.capabilities.supportsVision = true
          model.inputMode = InputMode.VISION
          break
        }
      }
    }
    // modalities.output 含 "image" → outputMode = IMAGE
    if (entry.modalities !== undefined && entry.modalities !== null &&
      entry.modalities.output !== undefined && entry.modalities.output !== null) {
      for (let i = 0; i < entry.modalities.output.length; i++) {
        if (entry.modalities.output[i] === 'image') {
          model.outputMode = OutputMode.IMAGE
          break
        }
      }
    }
    // limit.context → contextLength
    if (entry.limit !== undefined && entry.limit !== null &&
      entry.limit.context > 0) {
      model.contextLength = entry.limit.context
    }
    // limit.output → 最大输出预算；上下文安全输入预算会据此预留空间。
    if (entry.limit !== undefined && entry.limit !== null && entry.limit.output > 0) {
      model.parameters.maxTokens = entry.limit.output
    }
  }

  private applyKnownCapabilityFallback(model: ModelInfo): boolean {
    const id = model.id.trim().toLowerCase()
    const slashIndex = id.lastIndexOf('/')
    const routedId = slashIndex >= 0 ? id.substring(slashIndex + 1) : id
    let changed = false

    if (routedId.startsWith('gpt-5') || routedId.startsWith('o1') ||
      routedId.startsWith('o3') || routedId.startsWith('o4')) {
      if (!model.capabilities.supportsReasoning) {
        model.capabilities.supportsReasoning = true
        changed = true
      }
    }

    if (id.startsWith('qwen3') ||
      id.startsWith('qwq') ||
      id.startsWith('qvq') ||
      id.includes('/qwen3') ||
      id.includes('/qwq') ||
      id.includes('/qvq')) {
      if (!model.capabilities.supportsReasoning) {
        model.capabilities.supportsReasoning = true
        changed = true
      }
    }

    if (id.startsWith('minimax-m2') || id.includes('/minimax-m2')) {
      if (!model.capabilities.supportsReasoning) {
        model.capabilities.supportsReasoning = true
        changed = true
      }
    }

    if (id.includes('kimi-k2-thinking') || id.includes('kimi-k2.5')) {
      if (!model.capabilities.supportsReasoning) {
        model.capabilities.supportsReasoning = true
        changed = true
      }
    }

    if (id.includes('deepseek-v4')) {
      if (!model.capabilities.supportsTools) {
        model.capabilities.supportsTools = true
        changed = true
      }
      if (!model.capabilities.supportsReasoning) {
        model.capabilities.supportsReasoning = true
        changed = true
      }
    }

    if (id.includes('claude-opus-4-7')) {
      if (!model.capabilities.supportsTools) {
        model.capabilities.supportsTools = true
        changed = true
      }
      if (!model.capabilities.supportsReasoning) {
        model.capabilities.supportsReasoning = true
        changed = true
      }
      if (!model.capabilities.supportsVision) {
        model.capabilities.supportsVision = true
        model.inputMode = InputMode.VISION
        changed = true
      }
    }

    return changed
  }

  // 主动加载缓存（供外部调用）
  async loadCache(): Promise<boolean> {
    return await this.ensureCache()
  }

  // 判断缓存是否已加载
  isCacheLoaded(): boolean {
    return this.cache.size > 0 && (Date.now() - this.cacheTimestamp) < this.CACHE_TTL
  }
}
