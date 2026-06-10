import {
  ToolDefinition,
  ToolConfig,
  ToolParameters,
  ToolFunction,
  ToolParameterProperty,
  ToolPermissionLevel,
  ToolSourceType
} from '../models/ChatModels'
import { ToolExecutor, RegisteredTool, getToolRegistry } from '../services/ToolRegistry'
import { getWebSearchService, SearchResult, WebSearchResult } from '../services/WebSearchService'
import { cleanSearchQuery } from '../utils/SearchQueryUtils'

export const ASK_USER_TOOL_ID: string = 'ask_user'

// web_search 工具参数接口
interface WebSearchArgs {
  query?: string
  q?: string
  keywords?: string
  url?: string
  page?: number | string
}

// 搜索结果项接口（用于格式化输出）
class SearchResultItem {
  index: number = 0
  id: string = ''
  title: string = ''
  url: string = ''
  snippet: string = ''

  constructor(index: number, id: string, title: string, url: string, snippet: string) {
    this.index = index
    this.id = id
    this.title = title
    this.url = url
    this.snippet = snippet
  }
}


// 搜索结果输出接口
class SearchResultOutput {
  query: string = ''
  searchEngine: string = ''
  results: SearchResultItem[] = []
  summary: string = ''

  constructor(query: string, searchEngine: string, results: SearchResultItem[], summary: string) {
    this.query = query
    this.searchEngine = searchEngine
    this.results = results
    this.summary = summary
  }
}

// 错误输出接口
class ErrorOutput {
  error: string = ''

  constructor(error: string) {
    this.error = error
  }
}

class AskUserExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    return JSON.stringify(new ErrorOutput('ask_user should be resolved by the user, not executed directly'))
  }
}

// web_search 执行器
class WebSearchExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as WebSearchArgs
      const query = this.resolveQuery(params)
      if (query === '') {
        return JSON.stringify(new ErrorOutput('搜索关键词不能为空'))
      }

      const webSearchService = getWebSearchService()
      const extractedUrl = webSearchService.extractUrl(query)
      const isPureUrl = extractedUrl !== null && extractedUrl === query
      if (isPureUrl && extractedUrl !== null) {
        console.info('WebSearchExecutor', `Executing web extract: ${extractedUrl}`)
        const webResult = await webSearchService.fetchUrlContent(extractedUrl)
        return this.formatWebResult(webResult)
      }

      console.info('WebSearchExecutor', `Executing web search: ${query}`)
      const searchResult = await webSearchService.search(query, { page: this.resolvePage(params) })
      return this.formatResult(searchResult)
    } catch (error) {
      console.error('WebSearchExecutor', `Search error: ${JSON.stringify(error)}`)
      return JSON.stringify(new ErrorOutput(`搜索失败: ${JSON.stringify(error)}`))
    }
  }

  private resolveQuery(params: WebSearchArgs): string {
    const candidates: string[] = []
    if (params.url !== undefined) {
      candidates.push(params.url)
    }
    if (params.query !== undefined) {
      candidates.push(params.query)
    }
    if (params.q !== undefined) {
      candidates.push(params.q)
    }
    if (params.keywords !== undefined) {
      candidates.push(params.keywords)
    }

    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i].trim()
      if (candidate !== '') {
        const webSearchService = getWebSearchService()
        const extractedUrl = webSearchService.extractUrl(candidate)
        if (extractedUrl !== null && extractedUrl === candidate) {
          return candidate
        }
        return cleanSearchQuery(candidate)
      }
    }
    return ''
  }

  private resolvePage(params: WebSearchArgs): number | undefined {
    if (params.page === undefined) {
      return undefined
    }
    if (typeof params.page === 'number') {
      return params.page
    }
    const parsed = Number(params.page)
    if (Number.isNaN(parsed)) {
      return undefined
    }
    return parsed
  }

  private buildSnippet(content: string): string {
    const trimmed = content.replace(/\s+/g, ' ').trim()
    if (trimmed.length <= 200) {
      return trimmed
    }
    return trimmed.substring(0, 200) + '...'
  }

  private formatWebResult(result: WebSearchResult): string {
    if (!result.success) {
      return JSON.stringify(new ErrorOutput(result.errorMessage))
    }

    const output = new SearchResultOutput(
      result.url,
      result.sourceName !== '' ? result.sourceName : 'URL抓取',
      [new SearchResultItem(
        1,
        `ref_${Date.now()}`,
        result.title,
        result.url,
        this.buildSnippet(result.content)
      )],
      `标题: ${result.title}\n来源: ${result.url}\n\n${result.content}`
    )
    return JSON.stringify(output)
  }

  private formatResult(result: SearchResult): string {
    if (!result.success) {
      return JSON.stringify(new ErrorOutput(result.errorMessage))
    }

    // 翻页/去重后已无更多新结果：明确提示模型换关键词或停止，避免无意义地重复搜索同一 query
    if (result.exhausted && result.references.length === 0) {
      return JSON.stringify(new SearchResultOutput(
        result.query,
        result.searchEngine,
        [],
        `该关键词「${result.query}」没有拿到新的非重复结果。若仍需继续搜索，请主动更换 query 角度，不要重复该关键词；可尝试精确短语、site: 指定不同来源、-site: 排除已见来源、作者/机构/作品名/时间等更具体关键词。`
      ))
    }

    if (result.references.length === 0) {
      return JSON.stringify(new SearchResultOutput(
        result.query,
        result.searchEngine,
        [],
        `没有找到可用搜索结果。请换一组更具体的 web_search.query 再试，例如加入核心实体、官方来源、site: 限定、-site: 排除噪声来源、精确短语或具体日期；不要把这次空结果当作事实依据。`
      ))
    }

    // 返回结构化的搜索结果（包含 index 和 id）
    const formattedResults: SearchResultItem[] = []
    for (let i = 0; i < result.references.length; i++) {
      const ref = result.references[i]
      formattedResults.push(new SearchResultItem(
        result.startIndex + i,
        ref.id,
        ref.title,
        ref.url,
        ref.snippet
      ))
    }

    const output = new SearchResultOutput(
      result.query,
      result.searchEngine,
      formattedResults,
      result.contentForAI
    )
    return JSON.stringify(output)
  }
}

// 创建 web_search 工具定义
function createWebSearchToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.addProperty('query', new ToolParameterProperty(
    'string',
    '必填。搜索关键词或网页 URL。传入可直接检索的短关键词，不要传入整段推理；保留用户给出的实体、地点、日期、版本号和专有名词。读取网页时原样传入 URL。'
  ))
  parameters.addProperty('page', new ToolParameterProperty(
    'number',
    '可选。需要查看更多结果时传入页码，第一页为 1，第二页为 2。优先更换 query 角度；只有确实要看同一关键词下一页时才增加 page。'
  ))
  parameters.addRequired('query')

  const func = new ToolFunction(
    'web_search',
    '搜索互联网或读取网页 URL 获取外部信息。适合实时信息、新闻、天气、股票、最新事件、外部网页总结等。query 必须是简洁且可检索的关键词或原始 URL；多次搜索同一问题时要更换 query 角度获取不同来源，不要重复同一关键词。',
    parameters
  )

  return new ToolDefinition(func)
}

// 创建 web_search 工具配置
function createWebSearchToolConfig(): ToolConfig {
  return new ToolConfig(
    'web_search',
    '联网搜索',
    '搜索互联网获取最新信息',
    null,
    false,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    'web_search',
    '内置工具',
    ToolPermissionLevel.READ
  )
}

function createAskUserToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "questions": {
        "type": "array",
        "description": "1-3 clarification questions for the user. Each item must include id, question, selection_type, and options when selection_type is single or multi.",
        "minItems": 1,
        "maxItems": 3,
        "items": {
          "type": "object",
          "properties": {
            "id": {
              "type": "string",
              "description": "Unique answer key, such as q1, format, or target."
            },
            "question": {
              "type": "string",
              "description": "Concise question shown to the user."
            },
            "selection_type": {
              "type": "string",
              "enum": ["single", "multi", "text"],
              "description": "single means one option, multi means multiple options, text means free-form input."
            },
            "options": {
              "type": "array",
              "description": "Required for single or multi questions.",
              "items": { "type": "string" }
            }
          },
          "required": ["id", "question", "selection_type"]
        }
      }
    },
    "required": ["questions"]
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)

  const func = new ToolFunction(
    ASK_USER_TOOL_ID,
    'Ask the user clarifying questions before proceeding. Use this only when the request is genuinely ambiguous and choosing a default would likely cause rework. Batch 1-3 related questions in one call. The tool result will be a JSON object of user answers keyed by question id.',
    parameters
  )

  return new ToolDefinition(func)
}

function createAskUserToolConfig(): ToolConfig {
  return new ToolConfig(
    ASK_USER_TOOL_ID,
    '向用户提问',
    '模型需要澄清时向你发起提问，答复会作为工具结果回给模型继续生成',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    ASK_USER_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

// 注册所有内置工具
export function registerBuiltinTools(): void {
  const registry = getToolRegistry()
  let registeredNow = 0

  if (!registry.isToolRegistered('web_search')) {
    const webSearchTool = new RegisteredTool(
      'web_search',
      createWebSearchToolConfig(),
      createWebSearchToolDefinition(),
      new WebSearchExecutor()
    )
    registry.registerTool(webSearchTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(ASK_USER_TOOL_ID)) {
    const askUserTool = new RegisteredTool(
      ASK_USER_TOOL_ID,
      createAskUserToolConfig(),
      createAskUserToolDefinition(),
      new AskUserExecutor()
    )
    registry.registerTool(askUserTool)
    registeredNow += 1
  }

  console.info(
    'BuiltinTools',
    `Builtin tools ready: total=${registry.getToolCount()}, newlyRegistered=${registeredNow}`
  )
}

// 获取所有内置工具 ID
export function getBuiltinToolIds(): string[] {
  return ['web_search', ASK_USER_TOOL_ID]
}
