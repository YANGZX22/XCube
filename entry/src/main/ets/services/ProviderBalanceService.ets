/**
 * 服务商余额查询服务
 * 每个服务商可单独配置余额查询（URL/路径/结果JSON路径/币种/币种JSON路径），
 * 复用服务商自身 apiKey 作 Bearer 鉴权，固定 GET 请求。
 */
import { ModelProvider } from '../models/ChatModels'
import { getHttpService, HttpService, HttpResponse } from './HttpService'
import { resolveJsonString, safeParseJson } from '../utils/JsonPathUtils'

export const DEFAULT_BALANCE_API_PATH = '/user/balance'
export const DEFAULT_BALANCE_JSON_PATH = 'balance_infos[0].total_balance'
export const DEFAULT_BALANCE_CURRENCY_JSON_PATH = 'balance_infos[0].currency'

// 余额查询配置（持久化为 ModelProvider.balanceConfigJson）
export interface ProviderBalanceConfig {
  enabled: boolean         // 是否开启余额查询
  url: string              // 查询基址（留空则用服务商 baseUrl）
  apiPath: string          // API 路径，如 /user/balance
  balanceJsonPath: string  // 结果金额的 JSON 路径，如 data.total_balance
  currency: string         // 固定币种文本，当 currencyJsonPath 为空时用
  currencyJsonPath: string // 币种的 JSON 路径（优先于 currency）
}

// 单个服务商余额查询结果
export interface BalanceResult {
  providerId: string
  providerName: string
  success: boolean
  balance: string
  currency: string
  error: string
}

// 默认配置：查询基址留空使用服务商 Base URL，其余字段提供常见余额接口占位。
export function createDefaultBalanceConfig(): ProviderBalanceConfig {
  return {
    enabled: false,
    url: '',
    apiPath: DEFAULT_BALANCE_API_PATH,
    balanceJsonPath: DEFAULT_BALANCE_JSON_PATH,
    currency: '',
    currencyJsonPath: DEFAULT_BALANCE_CURRENCY_JSON_PATH
  }
}

export class ProviderBalanceService {
  private static instance: ProviderBalanceService | null = null
  private httpService: HttpService = getHttpService()

  private constructor() {}

  static getInstance(): ProviderBalanceService {
    if (ProviderBalanceService.instance === null) {
      ProviderBalanceService.instance = new ProviderBalanceService()
    }
    return ProviderBalanceService.instance
  }

  // 解析存储的配置 JSON，失败返回 null
  parseConfig(json: string): ProviderBalanceConfig | null {
    if (json === '') {
      return null
    }
    try {
      const obj = JSON.parse(json) as ProviderBalanceConfig
      const defaults = createDefaultBalanceConfig()
      const apiPath = obj.apiPath ?? ''
      const balanceJsonPath = obj.balanceJsonPath ?? ''
      const currencyJsonPath = obj.currencyJsonPath ?? ''
      return {
        enabled: obj.enabled === true,
        url: obj.url ?? '',
        apiPath: apiPath.trim() !== '' ? apiPath : defaults.apiPath,
        balanceJsonPath: balanceJsonPath.trim() !== '' ? balanceJsonPath : defaults.balanceJsonPath,
        currency: obj.currency ?? '',
        currencyJsonPath: currencyJsonPath.trim() !== '' ? currencyJsonPath : defaults.currencyJsonPath
      }
    } catch (e) {
      console.error('ProviderBalanceService', `parseConfig failed: ${JSON.stringify(e)}`)
      return null
    }
  }

  // 拼接完整请求 URL
  private buildUrl(provider: ModelProvider, config: ProviderBalanceConfig): string {
    let base = config.url.trim() !== '' ? config.url.trim() : provider.baseUrl.trim()
    const path = config.apiPath.trim()
    if (path === '') {
      return base
    }
    // 去掉 base 尾部斜杠 / 补 path 头部斜杠
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1)
    }
    if (path.startsWith('/')) {
      return base + path
    }
    return `${base}/${path}`
  }

  // 查询单个服务商余额
  async queryBalance(provider: ModelProvider): Promise<BalanceResult> {
    const result: BalanceResult = {
      providerId: provider.id,
      providerName: provider.name,
      success: false,
      balance: '',
      currency: '',
      error: ''
    }

    const config = this.parseConfig(provider.balanceConfigJson)
    if (config === null || !config.enabled) {
      result.error = '未开启'
      return result
    }

    const url = this.buildUrl(provider, config)
    if (url === '') {
      result.error = '未配置查询地址'
      return result
    }

    const headers: Record<string, string> = {
      'Accept': 'application/json'
    }
    if (provider.apiKey.trim() !== '') {
      headers['Authorization'] = `Bearer ${provider.apiKey.trim()}`
    }

    try {
      const response: HttpResponse = await this.httpService.get(url, headers, { timeout: 15000 })
      if (!response.success || response.statusCode < 200 || response.statusCode >= 300) {
        result.error = response.errorMessage !== '' ? response.errorMessage : `HTTP ${response.statusCode}`
        return result
      }

      const root = safeParseJson(response.data)
      if (root === null) {
        result.error = '返回非 JSON 数据'
        return result
      }

      const balance = resolveJsonString(root, config.balanceJsonPath)
      if (balance === '') {
        result.error = '未解析到余额（检查 JSON 路径）'
        return result
      }

      let currency = ''
      if (config.currencyJsonPath.trim() !== '') {
        currency = resolveJsonString(root, config.currencyJsonPath)
      }
      if (currency === '') {
        currency = config.currency
      }

      result.success = true
      result.balance = balance
      result.currency = currency
      return result
    } catch (e) {
      result.error = `查询失败: ${JSON.stringify(e)}`
      return result
    }
  }

  // 并发查询所有已开启余额查询的服务商
  async queryAllEnabled(providers: ModelProvider[]): Promise<BalanceResult[]> {
    const enabled: ModelProvider[] = []
    for (let i = 0; i < providers.length; i++) {
      const config = this.parseConfig(providers[i].balanceConfigJson)
      if (config !== null && config.enabled) {
        enabled.push(providers[i])
      }
    }

    const tasks: Promise<BalanceResult>[] = enabled.map((p: ModelProvider): Promise<BalanceResult> => {
      return this.queryBalance(p)
    })
    return await Promise.all(tasks)
  }

  // 是否存在已开启余额查询的服务商
  hasEnabledProvider(providers: ModelProvider[]): boolean {
    for (let i = 0; i < providers.length; i++) {
      const config = this.parseConfig(providers[i].balanceConfigJson)
      if (config !== null && config.enabled) {
        return true
      }
    }
    return false
  }
}

export function getProviderBalanceService(): ProviderBalanceService {
  return ProviderBalanceService.getInstance()
}
