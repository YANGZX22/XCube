import {
  ToolDefinition,
  ToolConfig,
  ToolParameters,
  ToolFunction,
  ToolParameterProperty,
  ToolPermissionLevel,
  ToolSourceType
} from '../models/ChatModels'
import { util } from '@kit.ArkTS'
import { ToolExecutor, RegisteredTool, getToolRegistry } from '../services/ToolRegistry'
import { getWebSearchService, SearchResult, WebSearchResult } from '../services/WebSearchService'
import { cleanSearchQuery } from '../utils/SearchQueryUtils'
import { getCalendarWriteService, ReadScheduleRequest, WriteScheduleRequest } from '../services/CalendarWriteService'
import { getPythonSandboxService, PythonSandboxRequest } from '../services/PythonSandboxService'
import { getPyodideRuntimeService } from '../services/PyodideRuntimeService'
import { CanvasDocumentMutationResult, CanvasDocumentState, getCanvasDocumentService } from '../services/CanvasDocumentService'
import { getPdfTextExtractionService, PdfTextExtractionRequest } from '../services/PdfTextExtractionService'
import { getImageTextRecognitionService, ImageTextRecognitionRequest } from '../services/ImageTextRecognitionService'
import { getSkillService } from '../services/SkillService'
import { getSubAgentService, SUB_AGENT_MAX_TASKS, SUB_AGENT_TOOL_ID } from '../services/SubAgentService'
import {
  createKnowledgeSearchToolConfig,
  createKnowledgeSearchToolDefinition,
  KNOWLEDGE_SEARCH_TOOL_ID,
  KnowledgeSearchExecutor
} from './KnowledgeSearchTool'

export { KNOWLEDGE_SEARCH_TOOL_ID } from './KnowledgeSearchTool'
export { SUB_AGENT_TOOL_ID } from '../services/SubAgentService'

export const ASK_USER_TOOL_ID: string = 'ask_user'
export const READ_SCHEDULE_TOOL_ID: string = 'read_schedule'
export const WRITE_SCHEDULE_TOOL_ID: string = 'write_schedule'
export const MATH_CHART_TOOL_ID: string = 'math_chart'
export const PYTHON_SANDBOX_TOOL_ID: string = 'python_sandbox'
export const CANVAS_DOCUMENT_TOOL_ID: string = 'canvas_document'
export const PDF_TO_TEXT_TOOL_ID: string = 'pdf_to_text'
export const IMAGE_TO_TEXT_TOOL_ID: string = 'image_to_text'
export const USE_SKILL_TOOL_ID: string = 'use_skill'

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

interface MathChartSeriesArgs {
  name?: string
  values?: number[]
  color?: string
}

interface MathChartLinkArgs {
  source?: string
  target?: string
  value?: number | string
}

interface MathChartArgs {
  chart_type?: string
  title?: string
  x_label?: string
  y_label?: string
  labels?: string[]
  values?: number[]
  x_values?: number[]
  y_values?: number[]
  sizes?: number[]
  colors?: string[]
  words?: string[]
  sources?: string[]
  targets?: string[]
  links?: MathChartLinkArgs[]
  series?: MathChartSeriesArgs[]
  width?: number
  height?: number
  show_points?: boolean
}

interface CanvasDocumentArgs {
  operation?: string
  content?: string
  text?: string
  document?: string
  value?: string
  title?: string
  target?: string
  old_text?: string
  oldText?: string
  replacement?: string
  new_text?: string
  newText?: string
}

interface PdfToTextArgs {
  attachmentId?: string
  attachment_id?: string
  id?: string
  maxChars?: number | string
  max_chars?: number | string
  useOcr?: boolean | string
  use_ocr?: boolean | string
  ocr?: boolean | string
}

interface ImageToTextArgs {
  attachmentId?: string
  attachment_id?: string
  id?: string
  maxChars?: number | string
  max_chars?: number | string
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

class MathChartSeriesStats {
  name: string = ''
  count: number = 0
  min: number = 0
  max: number = 0
  sum: number = 0
  mean: number = 0
  median: number = 0
  stddev: number = 0
  slope: number = 0
  intercept: number = 0

  constructor(
    name: string,
    count: number,
    min: number,
    max: number,
    sum: number,
    mean: number,
    median: number,
    stddev: number,
    slope: number,
    intercept: number
  ) {
    this.name = name
    this.count = count
    this.min = min
    this.max = max
    this.sum = sum
    this.mean = mean
    this.median = median
    this.stddev = stddev
    this.slope = slope
    this.intercept = intercept
  }
}

class MathChartOutput {
  ok: boolean = true
  chartType: string = ''
  summary: string = ''
  stats: MathChartSeriesStats[] = []
  // VChart spec 的 JSON 字符串，由消息侧的 VChartCard 解析并实时渲染
  chart_spec: string = ''

  constructor(chartType: string, summary: string, stats: MathChartSeriesStats[], chartSpec: string) {
    this.chartType = chartType
    this.summary = summary
    this.stats = stats
    this.chart_spec = chartSpec
  }
}

class AskUserExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    return JSON.stringify(new ErrorOutput('ask_user should be resolved by the user, not executed directly'))
  }
}

class SubAgentExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    return await getSubAgentService().executeSubAgentToolCall(args)
  }
}

class SkillExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    return await getSkillService().readForTool(args)
  }
}

class CanvasDocumentOutput {
  ok: boolean = true
  operation: string = ''
  message: string = ''
  title: string = ''
  content: string = ''
  revision: number = 0
  updatedAt: number = 0
  updatedBy: string = ''
  activated: boolean = false

  constructor(ok: boolean, operation: string, message: string, document: CanvasDocumentState) {
    this.ok = ok
    this.operation = operation
    this.message = message
    this.title = document.title
    this.content = document.content
    this.revision = document.revision
    this.updatedAt = document.updatedAt
    this.updatedBy = document.updatedBy
    this.activated = document.activated
  }
}

class CanvasDocumentExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as CanvasDocumentArgs
      const operation = this.normalizeOperation(params)
      const service = getCanvasDocumentService()
      const activatedDocument = await service.activateDocument('assistant')
      if (operation === 'read') {
        return JSON.stringify(new CanvasDocumentOutput(true, operation, '已读取 canvas 文档', activatedDocument))
      }
      if (operation === 'replace') {
        const content = this.resolveContent(params)
        const document = await service.saveDocument(content, this.resolveString(params.title), 'assistant')
        return JSON.stringify(new CanvasDocumentOutput(true, operation, '已替换 canvas 文档全文', document))
      }
      if (operation === 'append') {
        const content = this.resolveRequiredContent(this.resolveContent(params))
        const document = await service.appendContent(content, 'assistant')
        return JSON.stringify(new CanvasDocumentOutput(true, operation, '已追加到 canvas 文档末尾', document))
      }
      if (operation === 'prepend') {
        const content = this.resolveRequiredContent(this.resolveContent(params))
        const document = await service.prependContent(content, 'assistant')
        return JSON.stringify(new CanvasDocumentOutput(true, operation, '已追加到 canvas 文档开头', document))
      }
      if (operation === 'patch') {
        const result = await service.replaceFirst(
          this.resolvePatchTarget(params),
          this.resolvePatchReplacement(params),
          'assistant'
        )
        return JSON.stringify(this.fromMutationResult(operation, result))
      }
      if (operation === 'clear') {
        const document = await service.clearDocument('assistant')
        return JSON.stringify(new CanvasDocumentOutput(true, operation, '已清空 canvas 文档', document))
      }
      return JSON.stringify(new CanvasDocumentOutput(false, operation, '不支持的 operation', activatedDocument))
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`Canvas 文档操作失败: ${this.stringifyError(error)}`))
    }
  }

  private fromMutationResult(operation: string, result: CanvasDocumentMutationResult): CanvasDocumentOutput {
    return new CanvasDocumentOutput(result.ok, operation, result.message, result.document)
  }

  private normalizeOperation(params: CanvasDocumentArgs): string {
    const normalized = this.resolveString(params.operation).trim().toLowerCase().replace(/[\s\-]+/g, '_')
    if (normalized === '' && this.resolveContent(params).trim() !== '') {
      return 'replace'
    }
    if (normalized === '') {
      return 'read'
    }
    if (normalized === 'write' || normalized === 'update' || normalized === 'set' || normalized === 'rewrite' ||
      normalized === 'overwrite') {
      return 'replace'
    }
    if (normalized === 'add' || normalized === 'insert' || normalized === 'insert_after') {
      return 'append'
    }
    if (normalized === 'insert_before') {
      return 'prepend'
    }
    if (normalized === 'edit' || normalized === 'modify' || normalized === 'replace_first') {
      if (this.resolvePatchTarget(params) !== '') {
        return 'patch'
      }
      return 'replace'
    }
    if (normalized === 'delete' || normalized === 'remove' || normalized === 'reset') {
      return 'clear'
    }
    return normalized
  }

  private resolveContent(params: CanvasDocumentArgs): string {
    if (params.content !== undefined) {
      return this.resolveString(params.content)
    }
    if (params.text !== undefined) {
      return this.resolveString(params.text)
    }
    if (params.document !== undefined) {
      return this.resolveString(params.document)
    }
    if (params.value !== undefined) {
      return this.resolveString(params.value)
    }
    return ''
  }

  private resolvePatchTarget(params: CanvasDocumentArgs): string {
    return this.resolveString(params.target, this.resolveString(params.old_text, this.resolveString(params.oldText)))
  }

  private resolvePatchReplacement(params: CanvasDocumentArgs): string {
    return this.resolveString(params.replacement, this.resolveString(params.new_text, this.resolveString(params.newText)))
  }

  private resolveRequiredContent(value: string): string {
    const content = value
    if (content.trim() === '') {
      throw new Error('content 不能为空')
    }
    return content
  }

  private resolveString(value: string | undefined, fallback: string = ''): string {
    if (value === undefined || value === null) {
      return fallback
    }
    return `${value}`
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message
    }
    return JSON.stringify(error)
  }
}

class PdfToTextExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as PdfToTextArgs
      const request = new PdfTextExtractionRequest()
      request.attachmentId = this.resolveAttachmentId(params)
      request.maxChars = this.resolveNumber(params.maxChars, this.resolveNumber(params.max_chars, 12000))
      request.useOcr = this.resolveBoolean(params.useOcr, this.resolveBoolean(params.use_ocr,
        this.resolveBoolean(params.ocr, false)))
      if (request.attachmentId === '') {
        return JSON.stringify(new ErrorOutput('attachmentId 不能为空。请使用用户上传 PDF 附件的 id。'))
      }
      const service = getPdfTextExtractionService()
      let result = await service.extractForCurrentSession(request)
      // A scan usually has no PDF text layer. Keep that implementation detail
      // inside the tool instead of relying on the model to notice the empty
      // result and issue a second call with a different argument.
      if (!request.useOcr && !result.ok && result.fileName !== '') {
        request.useOcr = true
        result = await service.extractForCurrentSession(request)
      }
      return JSON.stringify(result)
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`PDF 转文本失败: ${this.stringifyError(error)}`))
    }
  }

  private resolveAttachmentId(params: PdfToTextArgs): string {
    if (params.attachmentId !== undefined) {
      return `${params.attachmentId}`.trim()
    }
    if (params.attachment_id !== undefined) {
      return `${params.attachment_id}`.trim()
    }
    if (params.id !== undefined) {
      return `${params.id}`.trim()
    }
    return ''
  }

  private resolveNumber(value: number | string | undefined, fallback: number): number {
    if (value === undefined || value === null) {
      return fallback
    }
    if (typeof value === 'number') {
      return Number.isFinite(value) ? value : fallback
    }
    const parsed = Number.parseInt(value, 10)
    return Number.isNaN(parsed) ? fallback : parsed
  }

  private resolveBoolean(value: boolean | string | undefined, fallback: boolean): boolean {
    if (value === undefined || value === null) {
      return fallback
    }
    if (typeof value === 'boolean') {
      return value
    }
    const normalized = value.trim().toLowerCase()
    if (normalized === 'true' || normalized === '1' || normalized === 'yes' || normalized === 'y') {
      return true
    }
    if (normalized === 'false' || normalized === '0' || normalized === 'no' || normalized === 'n') {
      return false
    }
    return fallback
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message
    }
    return JSON.stringify(error)
  }
}

class ImageToTextExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as ImageToTextArgs
      const request = new ImageTextRecognitionRequest()
      request.attachmentId = this.resolveAttachmentId(params)
      request.maxChars = this.resolveNumber(params.maxChars, this.resolveNumber(params.max_chars, 12000))
      if (request.attachmentId === '') {
        return JSON.stringify(new ErrorOutput('attachmentId 不能为空。请使用用户上传图片附件的 id。'))
      }
      const result = await getImageTextRecognitionService().recognizeForCurrentSession(request)
      return JSON.stringify(result)
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`图片转文本失败: ${this.stringifyError(error)}`))
    }
  }

  private resolveAttachmentId(params: ImageToTextArgs): string {
    if (params.attachmentId !== undefined) {
      return `${params.attachmentId}`.trim()
    }
    if (params.attachment_id !== undefined) {
      return `${params.attachment_id}`.trim()
    }
    if (params.id !== undefined) {
      return `${params.id}`.trim()
    }
    return ''
  }

  private resolveNumber(value: number | string | undefined, fallback: number): number {
    if (value === undefined || value === null) {
      return fallback
    }
    if (typeof value === 'number') {
      return Number.isFinite(value) ? value : fallback
    }
    const parsed = Number.parseInt(value, 10)
    return Number.isNaN(parsed) ? fallback : parsed
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message
    }
    return JSON.stringify(error)
  }
}

class PythonSandboxExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as PythonSandboxRequest
      const code = params.code ?? ''
      // 优先走 Pyodide（真正的 CPython 运行时）
      const pyResult = await getPyodideRuntimeService().run(code, params.variables)
      if (!pyResult.fallback) {
        return JSON.stringify(pyResult)
      }
      // 运行时未就绪/加载失败/超时：降级到本地受限解释器
      const fallback = getPythonSandboxService().run(params)
      fallback.warnings.unshift(`Python 运行时未就绪（${pyResult.error}），已用受限子集执行；完整能力请确保联网后重试。`)
      return JSON.stringify(fallback)
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`Python 执行失败: ${this.stringifyError(error)}`))
    }
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message
    }
    return JSON.stringify(error)
  }
}

class MathChartSeriesRuntime {
  name: string = ''
  values: number[] = []
  color: string = ''

  constructor(name: string, values: number[], color: string) {
    this.name = name
    this.values = values
    this.color = color
  }
}

class MathChartDataPoint {
  category: string = ''
  series: string = ''
  value: number = 0

  constructor(category: string, series: string, value: number) {
    this.category = category
    this.series = series
    this.value = value
  }
}

class MathChartScatterPoint {
  x: number = 0
  y: number = 0
  size: number = 8
  series: string = ''
  category: string = ''

  constructor(x: number, y: number, size: number, series: string, category: string) {
    this.x = x
    this.y = y
    this.size = size
    this.series = series
    this.category = category
  }
}

class MathChartFlowPoint {
  source: string = ''
  target: string = ''
  value: number = 0

  constructor(source: string, target: string, value: number) {
    this.source = source
    this.target = target
    this.value = value
  }
}

class MathChartSankeyNode {
  name: string = ''

  constructor(name: string) {
    this.name = name
  }
}

class MathChartSankeyGraph {
  nodes: MathChartSankeyNode[] = []
  links: MathChartFlowPoint[] = []

  constructor(nodes: MathChartSankeyNode[], links: MathChartFlowPoint[]) {
    this.nodes = nodes
    this.links = links
  }
}

class MathChartVChartData {
  values: Object[] = []

  constructor(values: Object[]) {
    this.values = values
  }
}

class MathChartVChartTitle {
  visible: boolean = true
  text: string = ''

  constructor(text: string) {
    this.text = text
  }
}

class MathChartVChartLegend {
  visible: boolean = false
  position: string = 'middle'
  orient: string = 'bottom'
  padding: MathChartVChartPadding = new MathChartVChartPadding(8, 0, 0, 0)

  constructor(visible: boolean) {
    this.visible = visible
  }
}

class MathChartVChartPadding {
  top: number = 0
  right: number = 0
  bottom: number = 0
  left: number = 0

  constructor(top: number, right: number, bottom: number, left: number) {
    this.top = top
    this.right = right
    this.bottom = bottom
    this.left = left
  }
}

class MathChartVChartAxisTitleStyle {
  fontSize: number = 11
  lineHeight: number = 15
}

class MathChartVChartAxisTitle {
  visible: boolean = false
  text: string = ''
  space: number = 24
  style: MathChartVChartAxisTitleStyle = new MathChartVChartAxisTitleStyle()

  constructor(text: string) {
    this.visible = text !== ''
    this.text = text
  }
}

class MathChartVChartBottomAxisLabelStyle {
  fontSize: number = 10
  lineHeight: number = 13
  maxLineWidth: number = 88
}

class MathChartVChartSideAxisLabelStyle {
  fontSize: number = 10
  lineHeight: number = 13
}

class MathChartVChartAxisLabel {
  visible: boolean = true
  autoHide: boolean = true
  autoLimit: boolean = true
  autoRotate: boolean = false
  autoWrap: boolean = false
  space: number = 6
  style: Object = new MathChartVChartSideAxisLabelStyle()

  constructor(isBottomAxis: boolean) {
    if (isBottomAxis) {
      this.autoHide = false
      this.autoLimit = false
      this.autoWrap = true
      this.space = 8
      this.style = new MathChartVChartBottomAxisLabelStyle()
    }
  }
}

class MathChartVChartAxis {
  orient: string = ''
  title: MathChartVChartAxisTitle = new MathChartVChartAxisTitle('')
  label: MathChartVChartAxisLabel = new MathChartVChartAxisLabel(false)
  sampling: boolean = true
  labelFlush: boolean = false

  constructor(orient: string, title: string) {
    this.orient = orient
    this.title = new MathChartVChartAxisTitle(title)
    this.label = new MathChartVChartAxisLabel(orient === 'bottom')
    this.labelFlush = orient === 'bottom'
  }
}

class MathChartVChartPoint {
  visible: boolean = true

  constructor(visible: boolean) {
    this.visible = visible
  }
}

class MathChartVChartTooltip {
  visible: boolean = true
}

class MathChartCommonSeriesSpec {
  type: string = ''
  xField: string = 'category'
  yField: string = 'value'
  seriesField: string = 'series'

  constructor(type: string) {
    this.type = type
  }
}

class MathChartVChartSpec {
  type: string = 'line'
  width: number = 720
  height: number = 440
  data: MathChartVChartData = new MathChartVChartData([])
  xField: string | string[] = 'category'
  yField: string = 'value'
  seriesField: string = 'series'
  color: string[] = []
  padding: MathChartVChartPadding = new MathChartVChartPadding(26, 14, 40, 14)
  title: MathChartVChartTitle = new MathChartVChartTitle('')
  legends: MathChartVChartLegend = new MathChartVChartLegend(false)
  axes: MathChartVChartAxis[] = []
  point: MathChartVChartPoint = new MathChartVChartPoint(true)
  tooltip: MathChartVChartTooltip = new MathChartVChartTooltip()

  constructor(
    type: string,
    width: number,
    height: number,
    data: MathChartVChartData,
    xField: string | string[],
    color: string[],
    title: MathChartVChartTitle,
    legends: MathChartVChartLegend,
    axes: MathChartVChartAxis[],
    point: MathChartVChartPoint
  ) {
    this.type = type
    this.width = width
    this.height = height
    this.data = data
    this.xField = xField
    this.color = color
    this.title = title
    this.legends = legends
    this.axes = axes
    this.point = point
  }
}

class MathChartExecutor implements ToolExecutor {
  private readonly palette: string[] = ['#2563EB', '#E11D48', '#059669', '#D97706', '#7C3AED', '#0891B2']

  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as MathChartArgs
      const chartType = this.normalizeChartType(params.chart_type)
      const series = this.resolveSeries(params)
      if (series.length === 0 || series[0].values.length === 0) {
        return JSON.stringify(new ErrorOutput('缺少可分析的数值数据。请传入 values 或 series[].values。'))
      }
      const labels = this.resolveLabels(params.labels, series[0].values.length)
      const title = this.resolveString(params.title, this.getDefaultTitle(chartType))
      const stats = this.buildStats(series)
      const summary = this.buildSummary(chartType, stats)
      const width = this.clampInteger(params.width, 720, 360, 1200)
      const height = this.clampInteger(params.height, 440, 260, 900)
      const spec = this.buildVChartSpec(chartType, title, this.resolveString(params.x_label),
        this.resolveString(params.y_label), labels, series, width, height, params.show_points !== false, params)
      return JSON.stringify(new MathChartOutput(chartType, summary, stats, JSON.stringify(spec)))
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`数学分析/绘图失败: ${this.stringifyError(error)}`))
    }
  }

  private normalizeChartType(value: string | undefined): string {
    const normalized = (value ?? 'line').trim().toLowerCase()
    if (normalized === 'bar' || normalized === 'column' || normalized === '柱状图' || normalized === '条形图') {
      return 'bar'
    }
    if (normalized === 'area' || normalized === 'area_chart' || normalized === '面积图') {
      return 'area'
    }
    if (normalized === 'scatter' || normalized === 'bubble' || normalized === '散点图' || normalized === '气泡图') {
      return 'scatter'
    }
    if (normalized === 'pie' || normalized === '饼图') {
      return 'pie'
    }
    if (normalized === 'donut' || normalized === 'doughnut' || normalized === '环形图') {
      return 'donut'
    }
    if (normalized === 'rose' || normalized === '玫瑰图' || normalized === '南丁格尔玫瑰图') {
      return 'rose'
    }
    if (normalized === 'funnel' || normalized === '漏斗图') {
      return 'funnel'
    }
    if (normalized === 'wordcloud' || normalized === 'word_cloud' || normalized === '词云图' || normalized === '词云') {
      return 'wordCloud'
    }
    if (normalized === 'sankey' || normalized === '桑基图') {
      return 'sankey'
    }
    if (normalized === 'dualaxis' || normalized === 'dual_axis' || normalized === 'combo' || normalized === '双轴图' || normalized === '组合图') {
      return 'dualAxis'
    }
    return 'line'
  }

  private resolveSeries(params: MathChartArgs): MathChartSeriesRuntime[] {
    const result: MathChartSeriesRuntime[] = []
    if (params.series !== undefined && Array.isArray(params.series)) {
      for (let i = 0; i < params.series.length; i++) {
        const item = params.series[i]
        const values = this.normalizeValues(item.values)
        if (values.length > 0) {
          result.push(new MathChartSeriesRuntime(
            this.resolveString(item.name, `系列 ${i + 1}`),
            values,
            this.resolveColor(item.color, i)
          ))
        }
      }
    }
    const singleValues = this.normalizeValues(params.values)
    if (result.length === 0 && singleValues.length > 0) {
      result.push(new MathChartSeriesRuntime('数据', singleValues, this.palette[0]))
    }
    const yValues = this.normalizeValues(params.y_values)
    if (result.length === 0 && yValues.length > 0) {
      result.push(new MathChartSeriesRuntime('数据', yValues, this.palette[0]))
    }
    const linkValues = this.normalizeLinkValues(params.links)
    if (result.length === 0 && linkValues.length > 0) {
      result.push(new MathChartSeriesRuntime('流量', linkValues, this.palette[0]))
    }
    return result
  }

  private normalizeLinkValues(links: MathChartLinkArgs[] | undefined): number[] {
    const result: number[] = []
    if (links === undefined || !Array.isArray(links)) {
      return result
    }
    for (let i = 0; i < links.length; i++) {
      const value = Number(links[i].value)
      if (Number.isFinite(value)) {
        result.push(value)
      }
    }
    return result
  }

  private normalizeValues(values: number[] | undefined): number[] {
    const result: number[] = []
    if (values === undefined || !Array.isArray(values)) {
      return result
    }
    for (let i = 0; i < values.length; i++) {
      const value = Number(values[i])
      if (Number.isFinite(value)) {
        result.push(value)
      }
    }
    return result
  }

  private resolveLabels(labels: string[] | undefined, count: number): string[] {
    const result: string[] = []
    if (labels !== undefined && Array.isArray(labels)) {
      for (let i = 0; i < labels.length && i < count; i++) {
        result.push(`${labels[i]}`)
      }
    }
    while (result.length < count) {
      result.push(`${result.length + 1}`)
    }
    return result
  }

  private buildVChartSpec(
    chartType: string,
    title: string,
    xLabel: string,
    yLabel: string,
    labels: string[],
    series: MathChartSeriesRuntime[],
    width: number,
    height: number,
    showPoints: boolean,
    params: MathChartArgs
  ): Record<string, Object> {
    const values: MathChartDataPoint[] = []
    const count = labels.length
    const colors: string[] = []
    for (let i = 0; i < series.length; i++) {
      colors.push(series[i].color)
      for (let j = 0; j < series[i].values.length && j < count; j++) {
        values.push(new MathChartDataPoint(labels[j], series[i].name, series[i].values[j]))
      }
    }

    if (chartType === 'scatter') {
      return this.buildScatterSpec(title, xLabel, yLabel, labels, series, width, height, colors, params)
    }
    if (chartType === 'pie' || chartType === 'donut' || chartType === 'rose' || chartType === 'funnel' ||
      chartType === 'wordCloud') {
      return this.buildCategoryValueSpec(chartType, title, labels, series, width, height, colors, params)
    }
    if (chartType === 'sankey') {
      return this.buildSankeySpec(title, series, width, height, colors, params)
    }
    if (chartType === 'dualAxis') {
      return this.buildDualAxisSpec(title, xLabel, yLabel, labels, series, width, height, colors)
    }

    const axes: MathChartVChartAxis[] = [
      new MathChartVChartAxis('bottom', xLabel),
      new MathChartVChartAxis('left', yLabel)
    ]
    const xField: string | string[] = chartType === 'bar' && series.length > 1 ? ['category', 'series'] : 'category'
    const spec = this.createBaseSpec(chartType, width, height, title, colors)
    spec['padding'] = this.buildCartesianPadding(labels, xLabel, yLabel, series.length > 1)
    spec['data'] = new MathChartVChartData(values)
    spec['xField'] = xField
    spec['yField'] = 'value'
    spec['seriesField'] = 'series'
    spec['legends'] = new MathChartVChartLegend(series.length > 1)
    spec['axes'] = axes
    spec['point'] = new MathChartVChartPoint(chartType === 'line' && showPoints)
    if (chartType === 'area' && series.length > 1) {
      spec['stack'] = true
    }
    return spec
  }

  private buildScatterSpec(
    title: string,
    xLabel: string,
    yLabel: string,
    labels: string[],
    series: MathChartSeriesRuntime[],
    width: number,
    height: number,
    colors: string[],
    params: MathChartArgs
  ): Record<string, Object> {
    const points: Object[] = []
    const xValues = this.normalizeValues(params.x_values)
    const sizes = this.normalizeValues(params.sizes)
    const count = series[0].values.length
    for (let i = 0; i < count; i++) {
      points.push(new MathChartScatterPoint(
        i < xValues.length ? xValues[i] : i + 1,
        series[0].values[i],
        i < sizes.length ? sizes[i] : 8,
        series[0].name,
        i < labels.length ? labels[i] : `${i + 1}`
      ))
    }
    const spec = this.createBaseSpec('scatter', width, height, title, colors)
    spec['padding'] = this.buildCartesianPadding(labels, xLabel, yLabel, series.length > 1)
    spec['data'] = new MathChartVChartData(points)
    spec['xField'] = 'x'
    spec['yField'] = 'y'
    spec['sizeField'] = 'size'
    spec['seriesField'] = 'series'
    spec['legends'] = new MathChartVChartLegend(series.length > 1)
    spec['axes'] = [
      new MathChartVChartAxis('bottom', xLabel),
      new MathChartVChartAxis('left', yLabel)
    ]
    return spec
  }

  private buildCategoryValueSpec(
    chartType: string,
    title: string,
    labels: string[],
    series: MathChartSeriesRuntime[],
    width: number,
    height: number,
    colors: string[],
    params: MathChartArgs
  ): Record<string, Object> {
    const values: Object[] = []
    const words = params.words !== undefined && Array.isArray(params.words) ? params.words : []
    const count = series[0].values.length
    for (let i = 0; i < count; i++) {
      const label = chartType === 'wordCloud' && i < words.length ? `${words[i]}` : (i < labels.length ? labels[i] : `${i + 1}`)
      values.push(new MathChartDataPoint(label, series[0].name, series[0].values[i]))
    }
    const specType = chartType === 'donut' ? 'pie' : chartType
    const spec = this.createBaseSpec(specType, width, height, title,
      this.buildCategoryPalette(values.length, params.colors, colors))
    spec['data'] = new MathChartVChartData(values)
    spec['categoryField'] = 'category'
    spec['valueField'] = 'value'
    spec['nameField'] = 'category'
    this.applyCategoryColorEncoding(spec)
    spec['legends'] = new MathChartVChartLegend(chartType !== 'wordCloud')
    if (chartType === 'donut') {
      spec['innerRadius'] = 0.58
      spec['outerRadius'] = 0.82
    }
    if (chartType === 'pie') {
      spec['outerRadius'] = 0.82
    }
    if (chartType === 'rose') {
      spec['outerRadius'] = 0.82
    }
    return spec
  }

  private buildSankeySpec(
    title: string,
    series: MathChartSeriesRuntime[],
    width: number,
    height: number,
    colors: string[],
    params: MathChartArgs
  ): Record<string, Object> {
    const links: MathChartFlowPoint[] = []
    if (params.links !== undefined && Array.isArray(params.links)) {
      for (let i = 0; i < params.links.length; i++) {
        const source = this.resolveString(params.links[i].source)
        const target = this.resolveString(params.links[i].target)
        const value = Number(params.links[i].value)
        if (source !== '' && target !== '' && Number.isFinite(value)) {
          links.push(new MathChartFlowPoint(source, target, value))
        }
      }
    }
    if (links.length === 0) {
      const sources = params.sources !== undefined && Array.isArray(params.sources) ? params.sources : []
      const targets = params.targets !== undefined && Array.isArray(params.targets) ? params.targets : []
      const count = Math.min(series[0].values.length, Math.min(sources.length, targets.length))
      for (let i = 0; i < count; i++) {
        links.push(new MathChartFlowPoint(`${sources[i]}`, `${targets[i]}`, series[0].values[i]))
      }
    }
    const nodes = this.buildSankeyNodes(links)
    const spec = this.createBaseSpec('sankey', width, height, title,
      this.buildCategoryPalette(Math.max(nodes.length, links.length, 1), params.colors, colors))
    spec['data'] = new MathChartVChartData([new MathChartSankeyGraph(nodes, links)])
    spec['nodeKey'] = 'name'
    spec['sourceField'] = 'source'
    spec['targetField'] = 'target'
    spec['valueField'] = 'value'
    spec['legends'] = new MathChartVChartLegend(false)
    return spec
  }

  private buildSankeyNodes(links: MathChartFlowPoint[]): MathChartSankeyNode[] {
    const names: string[] = []
    for (let i = 0; i < links.length; i++) {
      if (!names.includes(links[i].source)) {
        names.push(links[i].source)
      }
      if (!names.includes(links[i].target)) {
        names.push(links[i].target)
      }
    }
    const nodes: MathChartSankeyNode[] = []
    for (let i = 0; i < names.length; i++) {
      nodes.push(new MathChartSankeyNode(names[i]))
    }
    return nodes
  }

  private buildDualAxisSpec(
    title: string,
    xLabel: string,
    yLabel: string,
    labels: string[],
    series: MathChartSeriesRuntime[],
    width: number,
    height: number,
    colors: string[]
  ): Record<string, Object> {
    const values: MathChartDataPoint[] = []
    const count = labels.length
    for (let i = 0; i < series.length && i < 2; i++) {
      for (let j = 0; j < series[i].values.length && j < count; j++) {
        values.push(new MathChartDataPoint(labels[j], series[i].name, series[i].values[j]))
      }
    }
    const spec = this.createBaseSpec('common', width, height, title, colors)
    spec['padding'] = this.buildCartesianPadding(labels, xLabel, yLabel, true)
    spec['data'] = new MathChartVChartData(values)
    spec['seriesField'] = 'series'
    spec['axes'] = [
      new MathChartVChartAxis('bottom', xLabel),
      new MathChartVChartAxis('left', yLabel),
      new MathChartVChartAxis('right', '')
    ]
    spec['series'] = [
      new MathChartCommonSeriesSpec('bar'),
      new MathChartCommonSeriesSpec('line')
    ]
    spec['legends'] = new MathChartVChartLegend(true)
    return spec
  }

  private createBaseSpec(type: string, width: number, height: number, title: string, colors: string[]): Record<string, Object> {
    const spec = JSON.parse('{}') as Record<string, Object>
    spec['type'] = type
    spec['width'] = width
    spec['height'] = height
    spec['padding'] = new MathChartVChartPadding(26, 14, 40, 14)
    spec['title'] = new MathChartVChartTitle(title)
    spec['tooltip'] = new MathChartVChartTooltip()
    spec['color'] = colors
    return spec
  }

  private buildCartesianPadding(labels: string[], xLabel: string, yLabel: string, hasLegend: boolean): MathChartVChartPadding {
    let bottom = this.hasDenseAxisLabels(labels) ? 116 : (this.hasLongAxisLabels(labels) ? 102 : 82)
    if (xLabel !== '') {
      bottom += 10
    }
    if (hasLegend) {
      bottom += 16
    }
    return new MathChartVChartPadding(28, yLabel !== '' ? 62 : 52, Math.min(bottom, 136), yLabel !== '' ? 62 : 52)
  }

  private hasDenseAxisLabels(labels: string[]): boolean {
    return labels.length > 6
  }

  private hasLongAxisLabels(labels: string[]): boolean {
    if (labels.length > 5) {
      return true
    }
    for (let i = 0; i < labels.length; i++) {
      if (labels[i].length > 8 || labels[i].indexOf('\n') >= 0) {
        return true
      }
    }
    return false
  }

  private applyCategoryColorEncoding(spec: Record<string, Object>): void {
    spec['seriesField'] = 'category'
    spec['colorField'] = 'category'
  }

  private buildCategoryPalette(count: number, categoryColors: string[] | undefined, seriesColors: string[]): string[] {
    const explicitColors = this.normalizeColors(categoryColors)
    const result: string[] = []
    const source = explicitColors.length > 0 ? explicitColors : (seriesColors.length > 1 ? seriesColors : this.palette)
    for (let i = 0; i < count; i++) {
      result.push(source[i % source.length])
    }
    return result
  }

  private normalizeColors(values: string[] | undefined): string[] {
    const result: string[] = []
    if (values === undefined || !Array.isArray(values)) {
      return result
    }
    for (let i = 0; i < values.length; i++) {
      const color = this.resolveColor(values[i], i)
      if (color !== '') {
        result.push(color)
      }
    }
    return result
  }

  private getDefaultTitle(chartType: string): string {
    switch (chartType) {
      case 'bar':
        return '柱状图'
      case 'area':
        return '面积图'
      case 'scatter':
        return '散点图'
      case 'pie':
        return '饼图'
      case 'donut':
        return '环形图'
      case 'rose':
        return '玫瑰图'
      case 'funnel':
        return '漏斗图'
      case 'wordCloud':
        return '词云图'
      case 'sankey':
        return '桑基图'
      case 'dualAxis':
        return '双轴图'
      default:
        return '折线图'
    }
  }

  private buildLegacyVChartSpec(
    chartType: string,
    width: number,
    height: number,
    data: MathChartVChartData,
    xField: string | string[],
    color: string[],
    title: MathChartVChartTitle,
    legends: MathChartVChartLegend,
    axes: MathChartVChartAxis[],
    point: MathChartVChartPoint
  ): MathChartVChartSpec {
    return new MathChartVChartSpec(
      chartType,
      width,
      height,
      data,
      xField,
      color,
      title,
      legends,
      axes,
      point
    )
  }

  private buildStats(series: MathChartSeriesRuntime[]): MathChartSeriesStats[] {
    const result: MathChartSeriesStats[] = []
    for (let i = 0; i < series.length; i++) {
      const values = series[i].values.slice().sort((a, b) => a - b)
      const count = values.length
      const sum = series[i].values.reduce((acc, cur) => acc + cur, 0)
      const mean = count > 0 ? sum / count : 0
      const median = count === 0 ? 0 : (count % 2 === 1 ? values[Math.floor(count / 2)] : (values[count / 2 - 1] + values[count / 2]) / 2)
      let variance = 0
      for (let j = 0; j < series[i].values.length; j++) {
        variance += Math.pow(series[i].values[j] - mean, 2)
      }
      variance = count > 0 ? variance / count : 0
      const regression = this.linearRegression(series[i].values)
      result.push(new MathChartSeriesStats(
        series[i].name,
        count,
        count > 0 ? values[0] : 0,
        count > 0 ? values[count - 1] : 0,
        sum,
        mean,
        median,
        Math.sqrt(variance),
        regression[0],
        regression[1]
      ))
    }
    return result
  }

  private linearRegression(values: number[]): number[] {
    const n = values.length
    if (n <= 1) {
      return [0, n === 1 ? values[0] : 0]
    }
    let sumX = 0
    let sumY = 0
    let sumXY = 0
    let sumXX = 0
    for (let i = 0; i < n; i++) {
      const x = i + 1
      const y = values[i]
      sumX += x
      sumY += y
      sumXY += x * y
      sumXX += x * x
    }
    const denominator = n * sumXX - sumX * sumX
    const slope = denominator === 0 ? 0 : (n * sumXY - sumX * sumY) / denominator
    const intercept = (sumY - slope * sumX) / n
    return [slope, intercept]
  }

  private buildSummary(chartType: string, stats: MathChartSeriesStats[]): string {
    if (stats.length === 0) {
      return '没有可分析数据。'
    }
    const first = stats[0]
    const trend = first.slope > 0 ? '整体上升' : (first.slope < 0 ? '整体下降' : '整体基本持平')
    return `${this.getDefaultTitle(chartType)}已生成。${first.name} 共 ${first.count} 个数据点，最小值 ${this.formatNumber(first.min)}，最大值 ${this.formatNumber(first.max)}，均值 ${this.formatNumber(first.mean)}，趋势 ${trend}。`
  }

  private resolveMinMax(series: MathChartSeriesRuntime[]): number[] {
    let min = Number.POSITIVE_INFINITY
    let max = Number.NEGATIVE_INFINITY
    for (let i = 0; i < series.length; i++) {
      for (let j = 0; j < series[i].values.length; j++) {
        min = Math.min(min, series[i].values[j])
        max = Math.max(max, series[i].values[j])
      }
    }
    if (!Number.isFinite(min) || !Number.isFinite(max)) {
      return [0, 1]
    }
    if (min === max) {
      return [min - 1, max + 1]
    }
    const padding = (max - min) * 0.12
    return [Math.min(0, min - padding), max + padding]
  }

  private scaleY(value: number, minY: number, range: number, marginTop: number, plotH: number): number {
    return marginTop + plotH - (value - minY) / range * plotH
  }

  private encodeUtf8ToBase64(value: string): string {
    const bytes = new util.TextEncoder().encodeInto(value)
    const helper = new util.Base64Helper()
    return helper.encodeToStringSync(bytes)
  }

  private clampInteger(value: number | undefined, fallback: number, min: number, max: number): number {
    if (value === undefined || !Number.isFinite(value)) {
      return fallback
    }
    return Math.min(Math.max(Math.floor(value), min), max)
  }

  private resolveString(value: string | undefined, fallback: string = ''): string {
    if (value === undefined) {
      return fallback
    }
    return `${value}`.trim()
  }

  private resolveColor(value: string | undefined, index: number): string {
    const raw = this.resolveString(value)
    if (/^#[0-9a-fA-F]{6}$/.test(raw)) {
      return raw
    }
    return this.palette[index % this.palette.length]
  }

  private truncateLabel(value: string): string {
    return value.length > 12 ? `${value.substring(0, 12)}...` : value
  }

  private formatNumber(value: number): string {
    if (!Number.isFinite(value)) {
      return '0'
    }
    return `${Math.round(value * 1000) / 1000}`
  }

  private escapeXml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&apos;')
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message
    }
    return JSON.stringify(error)
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
    '模型可搜索互联网获取最新信息',
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
    '模型可在需要澄清时向用户发起提问，答复会作为工具结果回给模型继续生成',
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

function createSubAgentToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "tasks": {
        "type": "array",
        "description": "1 to ${SUB_AGENT_MAX_TASKS} independent sub-tasks to run in parallel. Each sub-agent works in an isolated context with the same tools exposed to this conversation except sub_agent itself. When the knowledge-base switch is on, this includes knowledge_search with one shared per-user-turn query budget across the main agent and all sub-agents. Sub-agent ask_user questions and generated charts appear in the main conversation; other sub-agent tool activity is visible to the user in a live preview panel.",
        "items": {
          "type": "object",
          "properties": {
            "name": {
              "type": "string",
              "description": "Short label for this sub-agent, e.g. 'price-research'."
            },
            "prompt": {
              "type": "string",
              "description": "Complete standalone instructions for the sub-agent. It cannot see this conversation, so include the goal, all necessary background, constraints, and what to return."
            },
            "expected_output": {
              "type": "string",
              "description": "Optional description of the desired output format of the final report."
            }
          },
          "required": ["prompt"]
        }
      }
    },
    "required": ["tasks"]
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)

  const func = new ToolFunction(
    SUB_AGENT_TOOL_ID,
    `Dispatch 1-${SUB_AGENT_MAX_TASKS} autonomous sub-agents to handle independent sub-tasks in parallel. Use this when a request splits into separate research or processing tracks (e.g. comparing multiple topics, gathering info from different sources). Each sub-agent runs its own tool-call loop and returns a final report. Do NOT use it for simple tasks you can answer directly, and write each prompt fully self-contained.`,
    parameters
  )

  return new ToolDefinition(func)
}

function createSubAgentToolConfig(): ToolConfig {
  return new ToolConfig(
    SUB_AGENT_TOOL_ID,
    '子智能体',
    '模型可派出最多 3 个并行子智能体独立完成子任务，结果汇总后继续回答',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    SUB_AGENT_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

function createCanvasDocumentToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "operation": {
        "type": "string",
        "enum": ["read", "replace", "append", "prepend", "patch", "clear", "write", "update", "set"],
        "description": "操作类型。read 读取当前文档；replace/write/update 用 content 替换全文；append/prepend 追加内容；patch 用 target/replacement 精确替换首个匹配片段；clear 清空文档。如果用户要求写入新文档，优先使用 replace。"
      },
      "content": {
        "type": "string",
        "description": "replace/write/update/append/prepend 使用的文本内容。可以是 Markdown。"
      },
      "text": {
        "type": "string",
        "description": "content 的别名。"
      },
      "document": {
        "type": "string",
        "description": "content 的别名。"
      },
      "value": {
        "type": "string",
        "description": "content 的别名。"
      },
      "title": {
        "type": "string",
        "description": "replace 时可选更新文档标题。"
      },
      "target": {
        "type": "string",
        "description": "patch 时必填，要被替换的精确原文片段。"
      },
      "old_text": {
        "type": "string",
        "description": "target 的别名。"
      },
      "replacement": {
        "type": "string",
        "description": "patch 时必填，用来替换 target 的新文本。"
      },
      "new_text": {
        "type": "string",
        "description": "replacement 的别名。"
      }
    },
    "required": []
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)

  const func = new ToolFunction(
    CANVAS_DOCUMENT_TOOL_ID,
    '读写右侧 Canvas 文档。适合和用户共同起草、改写、整理同一份 Markdown/纯文本文档。要把内容写入 Canvas 时，直接调用 operation="replace" 并传 content；小改动优先 patch，新增段落用 append/prepend。若省略 operation 但提供 content/text，会按 replace 写入。该工具只修改应用内当前 Canvas 文档，不写入系统日历、文件或外部服务。',
    parameters
  )

  return new ToolDefinition(func)
}

function createCanvasDocumentToolConfig(): ToolConfig {
  return new ToolConfig(
    CANVAS_DOCUMENT_TOOL_ID,
    'Canvas 文档',
    '模型可读取或修改一个和用户共享的文档',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    CANVAS_DOCUMENT_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

function createPdfToTextToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "attachmentId": {
        "type": "string",
        "description": "要读取的 PDF 附件 ID。用户上传 PDF 后，系统会在提示中列出可用 attachmentId。"
      },
      "attachment_id": {
        "type": "string",
        "description": "attachmentId 的别名。"
      },
      "id": {
        "type": "string",
        "description": "attachmentId 的别名。"
      },
      "maxChars": {
        "type": "number",
        "description": "最多返回多少字符，默认 12000。"
      },
      "max_chars": {
        "type": "number",
        "description": "maxChars 的别名。"
      },
      "useOcr": {
        "type": "boolean",
        "description": "是否跳过文本层并直接将 PDF 页面转为图片，再使用本地 CoreVisionKit OCR。默认 false；即使不传，文本层为空时工具也会自动回退 OCR。"
      },
      "use_ocr": {
        "type": "boolean",
        "description": "useOcr 的别名。"
      },
      "ocr": {
        "type": "boolean",
        "description": "useOcr 的别名。"
      }
    },
    "required": ["attachmentId"]
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)

  const func = new ToolFunction(
    PDF_TO_TEXT_TOOL_ID,
    '将用户上传的 PDF 附件转换为文本。仅能读取当前会话已登记的 PDF 附件；调用时传 attachmentId。工具默认先读取 PDF 文本层，文本层为空时会自动将页面转图片并通过本地 CoreVisionKit OCR 识别扫描件；useOcr=true 可跳过文本层并直接 OCR。',
    parameters
  )

  return new ToolDefinition(func)
}

function createPdfToTextToolConfig(): ToolConfig {
  return new ToolConfig(
    PDF_TO_TEXT_TOOL_ID,
    'PDF 转文本',
    '当模型不可直接读取 PDF 时读取其文本；扫描件会自动回退本地 OCR',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    PDF_TO_TEXT_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

function createImageToTextToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "attachmentId": {
        "type": "string",
        "description": "要读取的图片附件 ID。用户上传图片后，系统会在提示中列出可用 attachmentId。"
      },
      "attachment_id": {
        "type": "string",
        "description": "attachmentId 的别名。"
      },
      "id": {
        "type": "string",
        "description": "attachmentId 的别名。"
      },
      "maxChars": {
        "type": "number",
        "description": "最多返回多少字符，默认 12000。"
      },
      "max_chars": {
        "type": "number",
        "description": "maxChars 的别名。"
      }
    },
    "required": ["attachmentId"]
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)

  const func = new ToolFunction(
    IMAGE_TO_TEXT_TOOL_ID,
    '将用户上传的图片附件通过本地 CoreVisionKit OCR 转换为文本。仅能读取当前会话已登记的图片附件；调用时传 attachmentId。适合当前模型未开启视觉理解时读取图片中的文字。',
    parameters
  )

  return new ToolDefinition(func)
}

function createImageToTextToolConfig(): ToolConfig {
  return new ToolConfig(
    IMAGE_TO_TEXT_TOOL_ID,
    '图片转文本',
    '当模型不可直接读取图片时，可使用此工具读取将用户上传的图片转换为文本内容',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    IMAGE_TO_TEXT_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

function createUseSkillToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "skill_id": {
        "type": "string",
        "description": "要读取的 skill id。先空参调用可列出当前已启用的 skill。"
      },
      "skillId": {
        "type": "string",
        "description": "skill_id 的别名。"
      },
      "id": {
        "type": "string",
        "description": "skill_id 的别名。"
      },
      "name": {
        "type": "string",
        "description": "按 skill 名称读取。优先使用 skill_id；只有不知道 id 时再用 name。"
      },
      "path": {
        "type": "string",
        "description": "虚拟路径，如 app_help/SKILL.md。"
      },
      "maxChars": {
        "type": "number",
        "description": "最多返回多少字符，默认 16000。"
      },
      "max_chars": {
        "type": "number",
        "description": "maxChars 的别名。"
      }
    },
    "required": []
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)

  const func = new ToolFunction(
    USE_SKILL_TOOL_ID,
    '读取用户在应用设置中维护且已启用的 skill。空参调用会返回可用 skill 列表；回答需要某个技能说明时，使用 skill_id/name/path 读取对应 SKILL.md 正文，并严格以读取到的内容为准。只能读取已启用 skill，不要臆造未返回的能力、入口或限制。',
    parameters
  )

  return new ToolDefinition(func)
}

function createUseSkillToolConfig(): ToolConfig {
  return new ToolConfig(
    USE_SKILL_TOOL_ID,
    'Skill',
    '模型可读取用户启用的技能说明',
    null,
    false,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    USE_SKILL_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

function createPythonSandboxToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "code": {
        "type": "string",
        "description": "要执行的 Python 3 代码。支持完整 Python 3 语法（if/while/for、函数 def、类、字典、元组、f-string、列表推导式、切片、字符串方法等）与标准库（math、statistics、json、re、datetime、itertools、collections 等），以及随附的 numpy 等科学计算包（基于 Pyodide/CPython）。可用 print 输出，最后一个表达式的值会作为 result 返回。不支持文件系统读写、网络请求和系统命令。"
      },
      "variables": {
        "type": "object",
        "description": "可选。预置到全局命名空间的变量，只传 JSON 可序列化的数字、字符串、布尔值、数组和对象。"
      },
      "max_iterations": {
        "type": "number",
        "description": "可选。已废弃，保留向后兼容；仅在运行时未就绪降级到受限子集时生效。"
      }
    },
    "required": ["code"]
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)

  const func = new ToolFunction(
    PYTHON_SANDBOX_TOOL_ID,
    '模型可在本地运行真正的 Python 3（基于 Pyodide/CPython，在沙箱化的 WebAssembly 环境中执行），支持完整语法与标准库，用于数学计算、数据处理、统计分析、算法验证和中间推导。可使用 import 导入标准库与 numpy 等随附科学计算包，但不能访问文件系统、网络或系统命令。若需要画折线图/柱状图，优先使用 math_chart。',
    parameters
  )

  return new ToolDefinition(func)
}

function createPythonSandboxToolConfig(): ToolConfig {
  return new ToolConfig(
    PYTHON_SANDBOX_TOOL_ID,
    'Python',
    '模型可在本地运行 Pyodide/CPython',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    PYTHON_SANDBOX_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

function createMathChartToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "chart_type": {
        "type": "string",
        "enum": ["line", "bar", "area", "scatter", "pie", "donut", "rose", "funnel", "wordCloud", "sankey", "dualAxis"],
        "description": "图表类型。line 折线图，bar 柱状图，area 面积图，scatter 散点/气泡图，pie 饼图，donut 环形图，rose 玫瑰图，funnel 漏斗图，wordCloud 词云图，sankey 桑基图，dualAxis 双轴/柱线组合图。默认 line。"
      },
      "title": {
        "type": "string",
        "description": "图表标题。"
      },
      "x_label": {
        "type": "string",
        "description": "横轴名称，可选。"
      },
      "y_label": {
        "type": "string",
        "description": "纵轴名称，可选。"
      },
      "labels": {
        "type": "array",
        "description": "横轴标签，数量应与数据点对应。",
        "items": { "type": "string" }
      },
      "values": {
        "type": "array",
        "description": "单系列数值数据。折线/柱状/面积/饼图/环形/玫瑰/漏斗/词云使用该字段；桑基图中表示每条流量；只接受有限数字，不要传表达式字符串。",
        "items": { "type": "number" }
      },
      "x_values": {
        "type": "array",
        "description": "散点/气泡图的 X 轴数值；不传则自动使用 1..n。",
        "items": { "type": "number" }
      },
      "y_values": {
        "type": "array",
        "description": "散点/气泡图的 Y 轴数值；若没有 values，可用 y_values 作为主数值序列。",
        "items": { "type": "number" }
      },
      "sizes": {
        "type": "array",
        "description": "散点/气泡图的气泡大小，可选。",
        "items": { "type": "number" }
      },
      "colors": {
        "type": "array",
        "description": "分类图每个分类项的颜色，可选。用于饼图、环形图、玫瑰图、漏斗图、词云图、桑基图等；应按 labels/words/sources 顺序传多个颜色。不要只用 series.color 表示分类颜色；不传则自动按分类数量使用内置多色调色板。",
        "items": { "type": "string" }
      },
      "words": {
        "type": "array",
        "description": "词云图的词条；不传则使用 labels。",
        "items": { "type": "string" }
      },
      "sources": {
        "type": "array",
        "description": "桑基图每条流的源节点，数量应与 targets/values 对应。优先使用 links；只有无法构造 links 时再使用该字段。",
        "items": { "type": "string" }
      },
      "targets": {
        "type": "array",
        "description": "桑基图每条流的目标节点，数量应与 sources/values 对应。优先使用 links；只有无法构造 links 时再使用该字段。",
        "items": { "type": "string" }
      },
      "links": {
        "type": "array",
        "description": "桑基图推荐输入。每一项表示一条流向，包含 source、target、value。画桑基图时优先使用 chart_type='sankey' 与 links；不要只传 labels。",
        "items": {
          "type": "object",
          "properties": {
            "source": { "type": "string", "description": "源节点名称。" },
            "target": { "type": "string", "description": "目标节点名称。" },
            "value": { "type": "number", "description": "该流向的数值。" }
          },
          "required": ["source", "target", "value"]
        }
      },
      "series": {
        "type": "array",
        "description": "多系列数据。折线/柱状/面积/双轴图可使用多系列；dualAxis 通常提供两个系列，第一组用柱状，第二组用折线。",
        "items": {
          "type": "object",
          "properties": {
            "name": { "type": "string", "description": "系列名称。" },
            "values": {
              "type": "array",
              "description": "该系列数值。",
              "items": { "type": "number" }
            },
            "color": { "type": "string", "description": "可选，#RRGGBB 颜色。" }
          },
          "required": ["values"]
        }
      },
      "width": {
        "type": "number",
        "description": "图表渲染宽度，默认 720。"
      },
      "height": {
        "type": "number",
        "description": "图表渲染高度，默认 440。"
      },
      "show_points": {
        "type": "boolean",
        "description": "折线图是否显示数据点，默认 true。"
      }
    }
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)

  const func = new ToolFunction(
    MATH_CHART_TOOL_ID,
    '本地数学分析与图表绘制工具，在应用沙箱内根据结构化数据生成统计结果和 VChart 图表配置。支持折线图、柱状图、面积图、散点/气泡图、饼图、环形图、玫瑰图、漏斗图、词云图、桑基图、双轴/柱线组合图，以及基础统计和趋势分析。桑基图请使用 chart_type="sankey" 和 links:[{source,target,value}]。不要传任意 Python 代码；如用户要求用 Python 绘图，请将需求转换为结构化 labels/values/series/x_values/y_values/links/sources/targets 后调用本工具。',
    parameters
  )

  return new ToolDefinition(func)
}

function createMathChartToolConfig(): ToolConfig {
  return new ToolConfig(
    MATH_CHART_TOOL_ID,
    '数学绘图',
    '模型可在本地沙箱中分析数据并生成多类型图表',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    MATH_CHART_TOOL_ID,
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
    '模型可经用户确认后按指定范围读取系统日历事件进行分析',
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

  if (!registry.isToolRegistered(KNOWLEDGE_SEARCH_TOOL_ID)) {
    const knowledgeSearchTool = new RegisteredTool(
      KNOWLEDGE_SEARCH_TOOL_ID,
      createKnowledgeSearchToolConfig(),
      createKnowledgeSearchToolDefinition(),
      new KnowledgeSearchExecutor()
    )
    registry.registerTool(knowledgeSearchTool)
    registeredNow += 1
  }

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

  if (!registry.isToolRegistered(SUB_AGENT_TOOL_ID)) {
    const subAgentTool = new RegisteredTool(
      SUB_AGENT_TOOL_ID,
      createSubAgentToolConfig(),
      createSubAgentToolDefinition(),
      new SubAgentExecutor()
    )
    registry.registerTool(subAgentTool)
    registeredNow += 1
  }

  if (!registry.isToolRegistered(PYTHON_SANDBOX_TOOL_ID)) {
    const pythonSandboxTool = new RegisteredTool(
      PYTHON_SANDBOX_TOOL_ID,
      createPythonSandboxToolConfig(),
      createPythonSandboxToolDefinition(),
      new PythonSandboxExecutor()
    )
    registry.registerTool(pythonSandboxTool)
    registeredNow += 1
  }

  const pdfToTextWasRegistered = registry.isToolRegistered(PDF_TO_TEXT_TOOL_ID)
  const pdfToTextTool = new RegisteredTool(
    PDF_TO_TEXT_TOOL_ID,
    createPdfToTextToolConfig(),
    createPdfToTextToolDefinition(),
    new PdfToTextExecutor()
  )
  registry.registerTool(pdfToTextTool)
  if (!pdfToTextWasRegistered) {
    registeredNow += 1
  }

  const imageToTextWasRegistered = registry.isToolRegistered(IMAGE_TO_TEXT_TOOL_ID)
  const imageToTextTool = new RegisteredTool(
    IMAGE_TO_TEXT_TOOL_ID,
    createImageToTextToolConfig(),
    createImageToTextToolDefinition(),
    new ImageToTextExecutor()
  )
  registry.registerTool(imageToTextTool)
  if (!imageToTextWasRegistered) {
    registeredNow += 1
  }

  const useSkillWasRegistered = registry.isToolRegistered(USE_SKILL_TOOL_ID)
  const useSkillTool = new RegisteredTool(
    USE_SKILL_TOOL_ID,
    createUseSkillToolConfig(),
    createUseSkillToolDefinition(),
    new SkillExecutor()
  )
  registry.registerTool(useSkillTool)
  getSkillService().isToolEnabled()
    .then((enabled: boolean): void => {
      const registeredTool = registry.getTool(USE_SKILL_TOOL_ID)
      if (registeredTool !== undefined) {
        registeredTool.config.enabled = enabled
      }
    })
    .catch((error: Object): void => {
      console.warn('BuiltinTools', `Failed to load skill tool state: ${JSON.stringify(error)}`)
    })
  if (!useSkillWasRegistered) {
    registeredNow += 1
  }

  const canvasDocumentWasRegistered = registry.isToolRegistered(CANVAS_DOCUMENT_TOOL_ID)
  const canvasDocumentTool = new RegisteredTool(
    CANVAS_DOCUMENT_TOOL_ID,
    createCanvasDocumentToolConfig(),
    createCanvasDocumentToolDefinition(),
    new CanvasDocumentExecutor()
  )
  registry.registerTool(canvasDocumentTool)
  if (!canvasDocumentWasRegistered) {
    registeredNow += 1
  }

  if (!registry.isToolRegistered(MATH_CHART_TOOL_ID)) {
    const mathChartTool = new RegisteredTool(
      MATH_CHART_TOOL_ID,
      createMathChartToolConfig(),
      createMathChartToolDefinition(),
      new MathChartExecutor()
    )
    registry.registerTool(mathChartTool)
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
  return [
    KNOWLEDGE_SEARCH_TOOL_ID,
    'web_search',
    ASK_USER_TOOL_ID,
    SUB_AGENT_TOOL_ID,
    PYTHON_SANDBOX_TOOL_ID,
    PDF_TO_TEXT_TOOL_ID,
    IMAGE_TO_TEXT_TOOL_ID,
    USE_SKILL_TOOL_ID,
    CANVAS_DOCUMENT_TOOL_ID,
    MATH_CHART_TOOL_ID,
    READ_SCHEDULE_TOOL_ID,
    WRITE_SCHEDULE_TOOL_ID
  ]
}
