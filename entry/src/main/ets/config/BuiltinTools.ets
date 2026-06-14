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
import { getCalendarWriteService, ReadScheduleRequest, WriteScheduleRequest } from '../services/CalendarWriteService'

export const ASK_USER_TOOL_ID: string = 'ask_user'
export const READ_SCHEDULE_TOOL_ID: string = 'read_schedule'
export const WRITE_SCHEDULE_TOOL_ID: string = 'write_schedule'

// web_search 工具参数接口
interface WebSearchArgs {
  query?: string
  q?: string
  keywords?: string
  url?: string
  page?: number | string
}

interface WriteScheduleArgs {
  target?: string
  title?: string
  start_time?: string
  startTime?: string
  end_time?: string
  endTime?: string
  all_day?: boolean
  allDay?: boolean
  description?: string
  location?: string
  reminder_minutes_before?: number | string
  reminderMinutesBefore?: number | string
}

interface ReadScheduleArgs {
  start_time?: string
  startTime?: string
  end_time?: string
  endTime?: string
  days_before?: number | string
  daysBefore?: number | string
  days_after?: number | string
  daysAfter?: number | string
  limit?: number | string
  include_description?: boolean
  includeDescription?: boolean
  include_location?: boolean
  includeLocation?: boolean
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

class ReadScheduleExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as ReadScheduleArgs
      const request = this.buildRequest(params)
      const result = await getCalendarWriteService().readSchedule(request)
      return JSON.stringify(result)
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`读取日程失败: ${this.stringifyError(error)}`))
    }
  }

  private buildRequest(params: ReadScheduleArgs): ReadScheduleRequest {
    return {
      startTime: this.resolveOptionalString(params.start_time, params.startTime),
      endTime: this.resolveOptionalString(params.end_time, params.endTime),
      daysBefore: this.resolveOptionalNumber(params.days_before, params.daysBefore),
      daysAfter: this.resolveOptionalNumber(params.days_after, params.daysAfter),
      limit: this.resolveOptionalNumber(params.limit),
      includeDescription: params.include_description === true || params.includeDescription === true,
      includeLocation: params.include_location !== false && params.includeLocation !== false
    }
  }

  private resolveOptionalString(primary: string | undefined, fallback?: string): string | undefined {
    if (primary !== undefined) {
      return primary
    }
    return fallback
  }

  private resolveOptionalNumber(
    primary: number | string | undefined,
    fallback?: number | string
  ): number | undefined {
    const value = primary !== undefined ? primary : fallback
    if (value === undefined) {
      return undefined
    }
    if (typeof value === 'number') {
      return value
    }
    const parsed = Number(value)
    if (Number.isNaN(parsed)) {
      return undefined
    }
    return parsed
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message
    }
    return JSON.stringify(error)
  }
}

class WriteScheduleExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as WriteScheduleArgs
      const request = this.buildRequest(params)
      const result = await getCalendarWriteService().writeSchedule(request)
      return JSON.stringify(result)
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`写入日程失败: ${this.stringifyError(error)}`))
    }
  }

  private buildRequest(params: WriteScheduleArgs): WriteScheduleRequest {
    return {
      target: this.resolveString(params.target, 'calendar'),
      title: this.resolveString(params.title),
      startTime: this.resolveString(params.start_time, this.resolveString(params.startTime)),
      endTime: this.resolveOptionalString(params.end_time, params.endTime),
      allDay: params.all_day === true || params.allDay === true,
      description: this.resolveOptionalString(params.description),
      location: this.resolveOptionalString(params.location),
      reminderMinutesBefore: this.resolveOptionalNumber(
        params.reminder_minutes_before,
        params.reminderMinutesBefore
      )
    }
  }

  private resolveString(value: string | undefined, fallback: string = ''): string {
    if (value === undefined) {
      return fallback
    }
    return value
  }

  private resolveOptionalString(primary: string | undefined, fallback?: string): string | undefined {
    if (primary !== undefined) {
      return primary
    }
    return fallback
  }

  private resolveOptionalNumber(
    primary: number | string | undefined,
    fallback?: number | string
  ): number | undefined {
    const value = primary !== undefined ? primary : fallback
    if (value === undefined) {
      return undefined
    }
    if (typeof value === 'number') {
      return value
    }
    const parsed = Number(value)
    if (Number.isNaN(parsed)) {
      return undefined
    }
    return parsed
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message
    }
    return JSON.stringify(error)
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

function createReadScheduleToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "days_before": {
        "type": "number",
        "description": "从今天往前读取多少天，可按用户请求或保守默认填写；执行前客户端会让用户通过专用 UI 确认或修改。"
      },
      "days_after": {
        "type": "number",
        "description": "从今天往后读取多少天，可按用户请求或保守默认填写；执行前客户端会让用户通过专用 UI 确认或修改。"
      },
      "start_time": {
        "type": "string",
        "description": "可选。读取范围开始时间，使用带时区 ISO-8601 字符串；若提供则必须同时提供 end_time。"
      },
      "end_time": {
        "type": "string",
        "description": "可选。读取范围结束时间，使用带时区 ISO-8601 字符串；若提供则必须同时提供 start_time。"
      },
      "limit": {
        "type": "number",
        "description": "最多返回多少条日程，默认 80，最大 300；执行前用户可在确认 UI 中修改。"
      },
      "include_description": {
        "type": "boolean",
        "description": "是否包含日程备注。备注可能含隐私，默认 false；执行前用户可在确认 UI 中修改。"
      },
      "include_location": {
        "type": "boolean",
        "description": "是否包含地点。默认 true；执行前用户可在确认 UI 中修改。"
      }
    }
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)

  const func = new ToolFunction(
    READ_SCHEDULE_TOOL_ID,
    '读取系统日历事件并提供给模型分析。读取日程涉及隐私，执行前客户端会弹出专用 UI，让用户确认或修改向前天数、向后天数、返回数量上限、是否包含备注/地点；最终以用户在 UI 中确认的范围为准。若用户没有明确读取范围，可传空对象或保守默认值，不要再使用 ask_user 询问读取范围。',
    parameters
  )

  return new ToolDefinition(func)
}

function createReadScheduleToolConfig(): ToolConfig {
  return new ToolConfig(
    READ_SCHEDULE_TOOL_ID,
    '读取日程',
    '经你确认后按指定范围读取系统日历事件供模型分析',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    READ_SCHEDULE_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.WRITE
  )
}

function createWriteScheduleToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "target": {
        "type": "string",
        "enum": ["calendar"],
        "description": "固定传 calendar。本工具只写入系统日历事件。"
      },
      "title": {
        "type": "string",
        "description": "日程标题，必填，简短明确。"
      },
      "start_time": {
        "type": "string",
        "description": "开始时间，必填。使用带时区的 ISO-8601 字符串，例如 2026-06-14T15:30:00+08:00；不要传相对时间。"
      },
      "end_time": {
        "type": "string",
        "description": "结束时间，可选。使用带时区的 ISO-8601 字符串；省略时非全天默认 1 小时，全天默认 1 天。"
      },
      "all_day": {
        "type": "boolean",
        "description": "是否全天事件。"
      },
      "description": {
        "type": "string",
        "description": "日程备注，可选。"
      },
      "location": {
        "type": "string",
        "description": "地点，可选，仅写入日历事件。"
      },
      "reminder_minutes_before": {
        "type": "number",
        "description": "日历事件提前多少分钟提醒，默认 15。"
      }
    },
    "required": ["title", "start_time"]
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)

  const func = new ToolFunction(
    WRITE_SCHEDULE_TOOL_ID,
    '只写入系统日历事件。仅当用户明确要求创建/写入日程、日历事件、日历提醒、安排事项、记到日历时使用；如果用户说“闹钟”“叫醒我”“设个闹钟”，不要调用工具，应直接说明当前不支持创建闹钟。如果日期、时间、标题或是否写入仍不明确，先使用 ask_user 向用户确认。时间必须转成带时区的具体 ISO 字符串。本工具会修改系统日历，执行前应用会要求用户审批。',
    parameters
  )

  return new ToolDefinition(func)
}

function createWriteScheduleToolConfig(): ToolConfig {
  return new ToolConfig(
    WRITE_SCHEDULE_TOOL_ID,
    '写入日程',
    '模型可经用户确认后写入系统日历事件',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    WRITE_SCHEDULE_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.WRITE
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

  if (!registry.isToolRegistered(READ_SCHEDULE_TOOL_ID)) {
    const readScheduleTool = new RegisteredTool(
      READ_SCHEDULE_TOOL_ID,
      createReadScheduleToolConfig(),
      createReadScheduleToolDefinition(),
      new ReadScheduleExecutor()
    )
    registry.registerTool(readScheduleTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(WRITE_SCHEDULE_TOOL_ID)) {
    const writeScheduleTool = new RegisteredTool(
      WRITE_SCHEDULE_TOOL_ID,
      createWriteScheduleToolConfig(),
      createWriteScheduleToolDefinition(),
      new WriteScheduleExecutor()
    )
    registry.registerTool(writeScheduleTool)
    registeredNow += 1
  }

  console.info(
    'BuiltinTools',
    `Builtin tools ready: total=${registry.getToolCount()}, newlyRegistered=${registeredNow}`
  )
}

// 获取所有内置工具 ID
export function getBuiltinToolIds(): string[] {
  return ['web_search', ASK_USER_TOOL_ID, READ_SCHEDULE_TOOL_ID, WRITE_SCHEDULE_TOOL_ID]
}
