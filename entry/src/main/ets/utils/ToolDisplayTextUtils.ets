import { pickLocalizedText } from './LocalizedTextUtils'
import { resolveLegacyToolId } from './ToolIdAliases'

function normalizeToolId(value: string): string {
  // 历史消息里的工具调用仍带 *_to_text，映射后才能显示当前的名字和说明。
  return resolveLegacyToolId(value.trim().toLowerCase().replace(/[\s\-]+/g, '_'))
}

function extractPythonSandboxAction(payload: string): string {
  const actionMatch = payload.match(/["']action["']\s*:\s*["']([A-Za-z0-9_-]+)["']/i)
  if (actionMatch !== null && actionMatch.length > 1) {
    return normalizeToolId(actionMatch[1])
  }
  return /["']code["']\s*:/.test(payload) ? 'run' : ''
}

export function resolvePythonSandboxAction(argumentsJson: string, resultContent: string = ''): string {
  const argumentAction = extractPythonSandboxAction(argumentsJson)
  return argumentAction !== '' ? argumentAction : extractPythonSandboxAction(resultContent)
}

export function getLocalizedPythonSandboxActionLabel(action: string): string {
  switch (normalizeToolId(action)) {
    case 'run':
      return pickLocalizedText('运行代码', 'Run Code')
    case 'write_file':
      return pickLocalizedText('写入文件', 'Write File')
    case 'append_file':
      return pickLocalizedText('追加文件', 'Append File')
    case 'replace_in_file':
      return pickLocalizedText('修改文件', 'Edit File')
    case 'read_file':
      return pickLocalizedText('读取文件', 'Read File')
    case 'list_files':
      return pickLocalizedText('列举文件', 'List Files')
    case 'delete_file':
      return pickLocalizedText('删除文件', 'Delete File')
    case 'run_files':
      return pickLocalizedText('运行文件', 'Run Files')
    default:
      return ''
  }
}

export function getLocalizedBuiltinToolName(toolId: string, fallback: string = ''): string {
  switch (normalizeToolId(toolId)) {
    case 'builtin_browser':
      return pickLocalizedText('浏览器', 'In-APP Browser')
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
    case 'pdf_toolkit':
      return pickLocalizedText('PDF 工具包', 'PDF Toolkit')
    case 'image_toolkit':
      return pickLocalizedText('图片工具包', 'Image Toolkit')
    case 'vision_read_image':
      return pickLocalizedText('视觉理解', 'Vision')
    case 'docx_toolkit':
      return pickLocalizedText('DOCX 工具包', 'DOCX Toolkit')
    case 'xlsx_toolkit':
      return pickLocalizedText('XLSX 工具包', 'XLSX Toolkit')
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
    case 'builtin_browser':
      return pickLocalizedText('浏览网页并完成页面操作。',
        'Browse and interact with web pages.')
    case 'web_search':
      return pickLocalizedText('搜索网页，查找所需信息。',
        'Search the web for information.')
    case 'ask_user':
      return pickLocalizedText('询问任务中需要补充的信息。',
        'Ask for missing task details.')
    case 'sub_agent':
      return pickLocalizedText('将任务分给多个助手同时处理。',
        'Split work among multiple assistants.')
    case 'sub_agent_result':
      return pickLocalizedText('查看子智能体的处理结果。',
        'View results from sub-agents.')
    case 'sub_agent_message':
      return pickLocalizedText('向子智能体补充任务要求。',
        'Send follow-up instructions to sub-agents.')
    case 'canvas_document':
      return pickLocalizedText('查看和编辑 Canvas 文档。',
        'View and edit Canvas documents.')
    case 'plan_mode':
    case 'plan':
      return pickLocalizedText('制定任务计划并记录进度。',
        'Plan tasks and track progress.')
    case 'pdf_toolkit':
      return pickLocalizedText('读取 PDF 文档内容。',
        'Read PDF documents.')
    case 'image_toolkit':
      return pickLocalizedText('识别图片中的文字。',
        'Read text in images.')
    case 'vision_read_image':
      return pickLocalizedText('识别图片中的内容。',
        'Understand image content.')
    case 'docx_toolkit':
      return pickLocalizedText('读取 Word 文档中的文字和表格。',
        'Read text and tables in Word documents.')
    case 'xlsx_toolkit':
      return pickLocalizedText('读取 Excel 表格中的数据。',
        'Read data from Excel spreadsheets.')
    case 'use_skill':
      return pickLocalizedText('使用你添加的技能处理任务。',
        'Handle tasks with your custom skills.')
    case 'python_sandbox':
      return pickLocalizedText('运行 Python 代码，处理数据和文件。',
        'Run Python code to work with data and files.')
    case 'math_chart':
      return pickLocalizedText('分析数据并绘制图表。',
        'Analyze data and create charts.')
    case 'read_schedule':
      return pickLocalizedText('查看日历中的日程。',
        'View events in your calendar.')
    case 'write_schedule':
      return pickLocalizedText('添加日程和提醒。',
        'Add calendar events and reminders.')
    case 'email_read':
      return pickLocalizedText('查看邮箱中的邮件。',
        'Read messages in your mailbox.')
    case 'email_send':
      return pickLocalizedText('撰写并发送邮件。',
        'Compose and send emails.')
    case 'map_search_route':
      return pickLocalizedText('查找地点并规划路线。',
        'Find places and plan routes.')
    case 'saved_places':
      return pickLocalizedText('按名称查找已保存的地点。',
        'Look up saved places by name.')
    case 'open_map_route':
      return pickLocalizedText('用花瓣地图查看路线并开始导航。',
        'View routes and start navigation in Petal Maps.')
    case 'knowledge_search':
      return pickLocalizedText('从知识库文件中查找相关内容。',
        'Find information in your knowledge base files.')
    case 'compact_context':
    case 'context_compaction':
    case 'compact':
      return pickLocalizedText('压缩较早的对话，保留重要信息。',
        'Summarize earlier messages to retain key information.')
    default:
      return fallback.trim() !== '' ? fallback : pickLocalizedText(
        '暂无说明。',
        'No description available.')
  }
}

export function getLocalizedToolSourceLabel(sourceLabel: string): string {
  const normalized = normalizeToolId(sourceLabel)
  if (sourceLabel.trim() === '内置工具' || normalized === 'builtin' || normalized === 'built_in') {
    return pickLocalizedText('内置工具', 'Built-in')
  }
  return sourceLabel
}
