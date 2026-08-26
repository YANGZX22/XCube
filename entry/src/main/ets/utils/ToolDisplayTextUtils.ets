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
    case 'sub_agent_message':
      return pickLocalizedText('引导子智能体', 'Guide Sub-agent')
    case 'canvas_document':
      return pickLocalizedText('Canvas 文档', 'Canvas Document')
    case 'plan_mode':
    case 'plan':
      return pickLocalizedText('计划模式', 'Plan Mode')
    case 'pdf_to_text':
      return pickLocalizedText('PDF 转文本', 'PDF to Text')
    case 'image_to_text':
      return pickLocalizedText('图片转文本', 'Image to Text')
    case 'vision_read_image':
      return pickLocalizedText('ModLens 视觉理解', 'ModLens Vision')
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
    case 'email_read':
      return pickLocalizedText('读取邮件', 'Read Email')
    case 'email_send':
      return pickLocalizedText('发送邮件', 'Send Email')
    case 'map_search_route':
      return pickLocalizedText('地图', 'Map')
    case 'saved_places':
      return pickLocalizedText('常用地点', 'Saved Places')
    case 'open_map_route':
      return pickLocalizedText('花瓣导航', 'Petal Navigation')
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
      return pickLocalizedText('取回子智能体当前轮回复，会话可继续',
        'Collect the current replies from sub-agents.')
    case 'sub_agent_message':
      return pickLocalizedText('向已有子智能体续发指令并保留上下文',
        'Continue an existing sub-agent conversation.')
    case 'canvas_document':
      return pickLocalizedText('读取或修改与用户共享的 Canvas 文档',
        'Read or edit the Canvas document shared with the user.')
    case 'plan_mode':
    case 'plan':
      return pickLocalizedText('列出多步任务的计划，并在完成时逐条勾选',
        'Lay out a multi-step plan and tick each step off on completion.')
    case 'pdf_to_text':
      return pickLocalizedText('读取 PDF 文本，扫描件可自动使用 OCR',
        'Extract text from PDFs, with OCR fallback for scans.')
    case 'image_to_text':
      return pickLocalizedText('使用本地 OCR 读取图片中的文字',
        'Extract text from images with local OCR.')
    case 'vision_read_image':
      return pickLocalizedText('通过 ModLens 获取图片 OCR、布局与语义证据',
        'Get image OCR, layout, and semantic evidence through ModLens.')
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
    case 'email_read':
      return pickLocalizedText('经逐次确认后查看已授权邮箱中的邮件',
        'Read messages from the authorized mailbox after per-call approval.')
    case 'email_send':
      return pickLocalizedText('经逐次确认后向指定邮箱发送邮件',
        'Send email to specified recipients after per-call approval.')
    case 'map_search_route':
      return pickLocalizedText('推荐地点并规划驾车、步行或骑行路线',
        'Find places and plan driving, walking, or cycling routes.')
    case 'saved_places':
      return pickLocalizedText('标签对模型开放；读取对应地址和坐标前需用户确认',
        'Labels are available to the model; reading their addresses and coordinates requires approval.')
    case 'open_map_route':
      return pickLocalizedText('经用户确认后在花瓣地图中查看路线或发起导航',
        'Open a route or start navigation in Petal Maps after approval.')
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
