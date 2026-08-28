export const DEEPSEEK_WEB_SEARCH_DEFAULT_BASE_URL: string = 'https://api.deepseek.com/anthropic/v1'
export const DEEPSEEK_WEB_SEARCH_DEFAULT_MODEL: string = 'deepseek-v4-flash'
export const DEEPSEEK_WEB_SEARCH_MAX_TOKENS: number = 4096
export const DEEPSEEK_WEB_SEARCH_MAX_USES: number = 5
export const DEEPSEEK_WEB_SEARCH_TIMEOUT_MS: number = 60000

export class DeepSeekWebSearchSource {
  title: string = ''
  url: string = ''
  snippet: string = ''

  constructor(title: string, url: string, snippet: string) {
    this.title = title
    this.url = url
    this.snippet = snippet
  }
}

export class DeepSeekWebSearchParseResult {
  hasResultBlock: boolean = false
  sources: DeepSeekWebSearchSource[] = []
}

export class DeepSeekProviderCredential {
  providerId: string
  providerType: string
  baseUrl: string
  apiKey: string
  isEnabled: boolean

  constructor(providerId: string, providerType: string, baseUrl: string, apiKey: string, isEnabled: boolean) {
    this.providerId = providerId
    this.providerType = providerType
    this.baseUrl = baseUrl
    this.apiKey = apiKey
    this.isEnabled = isEnabled
  }
}

function readString(value: Record<string, Object>, key: string): string {
  const field = value[key]
  return typeof field === 'string' ? field : ''
}

function asRecord(value: Object | null | undefined): Record<string, Object> | null {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
    return null
  }
  return value as Record<string, Object>
}

function appendPublishedAt(snippet: string, publishedAt: string): string {
  if (publishedAt === '') {
    return snippet
  }
  return snippet === '' ? publishedAt : `${snippet} (${publishedAt})`
}

/**
 * Parses the structured Anthropic-compatible DeepSeek web-search blocks.
 * Ordinary model prose is ignored; snippets are joined from citations by URL.
 */
export function parseDeepSeekWebSearchResponse(json: string, maxCount: number): DeepSeekWebSearchParseResult {
  const result = new DeepSeekWebSearchParseResult()
  if (json.trim() === '' || maxCount <= 0) {
    return result
  }

  try {
    const root = JSON.parse(json) as Record<string, Object>
    const contentValue = root['content']
    if (!Array.isArray(contentValue)) {
      return result
    }
    const blocks = contentValue as Object[]
    const snippets = new Map<string, string>()

    for (let i = 0; i < blocks.length; i++) {
      const block = asRecord(blocks[i])
      if (block === null || readString(block, 'type') !== 'text') {
        continue
      }
      const citationsValue = block['citations']
      if (!Array.isArray(citationsValue)) {
        continue
      }
      const citations = citationsValue as Object[]
      for (let j = 0; j < citations.length; j++) {
        const citation = asRecord(citations[j])
        if (citation === null) {
          continue
        }
        const url = readString(citation, 'url').trim()
        const citedText = readString(citation, 'cited_text').trim()
        if (url !== '' && citedText !== '' && !snippets.has(url)) {
          snippets.set(url, citedText)
        }
      }
    }

    const seenUrls = new Set<string>()
    for (let i = 0; i < blocks.length && result.sources.length < maxCount; i++) {
      const block = asRecord(blocks[i])
      if (block === null || readString(block, 'type') !== 'web_search_tool_result') {
        continue
      }
      result.hasResultBlock = true
      const blockContentValue = block['content']
      if (!Array.isArray(blockContentValue)) {
        continue
      }
      const items = blockContentValue as Object[]
      for (let j = 0; j < items.length && result.sources.length < maxCount; j++) {
        const item = asRecord(items[j])
        if (item === null || readString(item, 'type') !== 'web_search_result') {
          continue
        }
        const url = readString(item, 'url').trim()
        if (url === '' || seenUrls.has(url)) {
          continue
        }
        seenUrls.add(url)
        const rawTitle = readString(item, 'title').trim()
        const title = rawTitle !== '' ? rawTitle : url
        const publishedAt = readString(item, 'page_age').trim()
        const snippet = appendPublishedAt(snippets.get(url) ?? '', publishedAt)
        result.sources.push(new DeepSeekWebSearchSource(title, url, snippet))
      }
    }
  } catch (_error) {
    return new DeepSeekWebSearchParseResult()
  }
  return result
}

/** Extracts the best available provider error without exposing request credentials. */
export function extractDeepSeekWebSearchError(json: string): string {
  if (json.trim() === '') {
    return ''
  }
  try {
    const root = JSON.parse(json) as Record<string, Object>
    const errorValue = root['error']
    if (typeof errorValue === 'string') {
      return errorValue
    }
    const errorObject = asRecord(errorValue)
    if (errorObject !== null) {
      const message = readString(errorObject, 'message').trim()
      if (message !== '') {
        return message
      }
    }
    return readString(root, 'message').trim()
  } catch (_error) {
    return ''
  }
}

export function buildDeepSeekWebSearchEndpoint(baseUrl: string): string {
  let normalized = baseUrl.trim()
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1)
  }
  if (normalized === '') {
    normalized = DEEPSEEK_WEB_SEARCH_DEFAULT_BASE_URL
  }
  if (normalized.endsWith('/messages')) {
    return normalized
  }
  if (normalized.endsWith('/anthropic')) {
    return `${normalized}/v1/messages`
  }
  return `${normalized}/messages`
}

export function isDeepSeekProvider(providerId: string, providerType: string, baseUrl: string): boolean {
  if (providerType.trim().toLowerCase() === 'deepseek' || providerId.trim().toLowerCase() === 'deepseek') {
    return true
  }
  return isOfficialDeepSeekBaseUrl(baseUrl)
}

export function isOfficialDeepSeekBaseUrl(baseUrl: string): boolean {
  let normalizedBaseUrl = baseUrl.trim().toLowerCase()
  while (normalizedBaseUrl.endsWith('/')) {
    normalizedBaseUrl = normalizedBaseUrl.substring(0, normalizedBaseUrl.length - 1)
  }
  return normalizedBaseUrl === 'https://api.deepseek.com' ||
    normalizedBaseUrl.startsWith('https://api.deepseek.com/')
}

/**
 * Resolves an already configured DeepSeek credential without copying it into search settings.
 * The selected provider wins; otherwise the built-in DeepSeek provider and then other enabled
 * DeepSeek providers are considered. This keeps session restoration from depending on a stale
 * global provider preference.
 */
export function resolveConfiguredDeepSeekApiKey(
  currentProviderId: string,
  providers: DeepSeekProviderCredential[]
): string {
  const normalizedCurrentId = currentProviderId.trim()
  if (normalizedCurrentId !== '') {
    for (let i = 0; i < providers.length; i++) {
      const provider = providers[i]
      if (provider.providerId === normalizedCurrentId) {
        const key = resolveDeepSeekCredentialKey(provider)
        if (key !== '') {
          return key
        }
        break
      }
    }
  }

  for (let i = 0; i < providers.length; i++) {
    const provider = providers[i]
    if (provider.providerId.trim().toLowerCase() === 'deepseek') {
      const key = resolveDeepSeekCredentialKey(provider)
      if (key !== '') {
        return key
      }
    }
  }

  for (let i = 0; i < providers.length; i++) {
    const key = resolveDeepSeekCredentialKey(providers[i])
    if (key !== '') {
      return key
    }
  }
  return ''
}

function resolveDeepSeekCredentialKey(provider: DeepSeekProviderCredential): string {
  // 自动模式固定请求 DeepSeek 官方端点，不能把第三方代理的 Key 转发给官方域名。
  if (!provider.isEnabled || !isOfficialDeepSeekBaseUrl(provider.baseUrl)) {
    return ''
  }
  return provider.apiKey.trim()
}
