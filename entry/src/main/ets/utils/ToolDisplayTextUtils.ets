import { pickLocalizedText } from './LocalizedTextUtils'

function normalizeToolId(value: string): string {
  return value.trim().toLowerCase().replace(/[\s\-]+/g, '_')
}

export function getLocalizedBuiltinToolName(toolId: string, fallback: string = ''): string {
  switch (normalizeToolId(toolId)) {
    case 'web_search':
    case 'exa_search':
    case 'websearch':
    case 'search_web':
    case 'internet_search':
    case 'web_search_exa':
      return pickLocalizedText('联网搜索', 'Web Search')
    case 'ask_user':
    case 'user_input':
    case 'ask':
      return pickLocalizedText('向用户提问', 'Ask User')
    case 'sub_agent':
      return pickLocalizedText('子智能体', 'Sub-agent')
    case 'sub_agent_result':
      return pickLocalizedText('收取子智能体结果', 'Collect Sub-agent Results')
    case 'canvas_document':
      return pickLocalizedText('Canvas 文档', 'Canvas Document')
    case 'pdf_to_text':
      return pickLocalizedText('PDF 转文本', 'PDF to Text')
    case 'image_to_text':
      return pickLocalizedText('图片转文本', 'Image to Text')
    case 'docx_to_text':
      return pickLocalizedText('DOCX 转文本', 'DOCX to Text')
    case 'xlsx_to_text':
      return pickLocalizedText('XLSX 转文本', 'XLSX to Text')
    case 'use_skill':
      return 'Skill'
    case 'python_sandbox':
      return 'Python'
    case 'math_chart':
      return pickLocalizedText('数学绘图', 'Math & Charts')
    case 'read_schedule':
      return pickLocalizedText('读取日程', 'Read Calendar')
    case 'write_schedule':
      return pickLocalizedText('写入日程', 'Write Calendar')
    case 'knowledge_search':
      return pickLocalizedText('知识库检索', 'Knowledge Search')
    case 'compact_context':
    case 'context_compaction':
    case 'compact':
      return pickLocalizedText('上下文压缩', 'Context Compaction')
    default:
      return fallback.trim() !== '' ? fallback : pickLocalizedText('未知工具', 'Unknown Tool')
  }
}

export function getLocalizedBuiltinToolDescription(toolId: string, fallback: string = ''): string {
  switch (normalizeToolId(toolId)) {
    case 'web_search':
      return pickLocalizedText('模型可搜索互联网获取最新信息',
        'Search the web for current information.')
    case 'ask_user':
      return pickLocalizedText('需要澄清时向用户提问，再根据答复继续',
        'Ask clarifying questions and continue with the answers.')
    case 'sub_agent':
      return pickLocalizedText('派出并行子智能体处理独立子任务',
        'Dispatch parallel sub-agents for independent tasks.')
    case 'sub_agent_result':
      return pickLocalizedText('取回已派出子智能体的最终报告',
        'Collect final reports from dispatched sub-agents.')
    case 'canvas_document':
      return pickLocalizedText('读取或修改与用户共享的 Canvas 文档',
        'Read or edit the Canvas document shared with the user.')
    case 'pdf_to_text':
      return pickLocalizedText('读取 PDF 文本，扫描件可自动使用 OCR',
        'Extract text from PDFs, with OCR fallback for scans.')
    case 'image_to_text':
      return pickLocalizedText('使用本地 OCR 读取图片中的文字',
        'Extract text from images with local OCR.')
    case 'docx_to_text':
      return pickLocalizedText('在本地读取 DOCX 中的标题、段落、列表和表格',
        'Extract headings, paragraphs, lists, and tables from DOCX files locally.')
    case 'xlsx_to_text':
      return pickLocalizedText('在本地读取 XLSX 工作表和单元格内容',
        'Extract worksheets and cell content from XLSX files locally.')
    case 'use_skill':
      return pickLocalizedText('读取用户已启用的技能说明',
        'Read instructions from enabled user skills.')
    case 'python_sandbox':
      return pickLocalizedText('在本地沙箱中运行 Pyodide/CPython',
        'Run Pyodide/CPython in a local sandbox.')
    case 'math_chart':
      return pickLocalizedText('在本地分析数据并生成多种图表',
        'Analyze data locally and generate charts.')
    case 'read_schedule':
      return pickLocalizedText('经用户确认后读取系统日历事件',
        'Read calendar events after user approval.')
    case 'write_schedule':
      return pickLocalizedText('经用户确认后写入系统日历事件',
        'Create calendar events after user approval.')
    case 'knowledge_search':
      return pickLocalizedText('按需检索知识库中已上传的文件',
        'Search files uploaded to the knowledge base.')
    case 'compact_context':
    case 'context_compaction':
    case 'compact':
      return pickLocalizedText('将较早对话压缩为摘要以节省上下文',
        'Summarize earlier turns to save context space.')
    default:
      return fallback.trim() !== '' ? fallback : pickLocalizedText(
        '应用内原生能力，可在当前聊天中按需调用。',
        'Built-in app capability available to the current chat.')
  }
}

export function getLocalizedToolSourceLabel(sourceLabel: string): string {
  const normalized = normalizeToolId(sourceLabel)
  if (sourceLabel.trim() === '内置工具' || normalized === 'builtin' || normalized === 'built_in') {
    return pickLocalizedText('内置工具', 'Built-in')
  }
  return sourceLabel
}
