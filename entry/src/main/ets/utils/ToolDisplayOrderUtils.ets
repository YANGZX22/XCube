import { ToolConfig, ToolSourceType } from '../models/ChatModels'
import { pickLocalizedText } from './LocalizedTextUtils'

export enum BuiltinToolCategory {
  WEB = 'web',
  EMAIL = 'email',
  MAPS = 'maps',
  CALENDAR = 'calendar',
  DOCUMENTS = 'documents',
  COMPUTING = 'computing',
  ASSISTANT = 'assistant',
  SKILLS = 'skills',
  OTHER = 'other'
}

class BuiltinToolCategoryDefinition {
  key: BuiltinToolCategory
  chineseTitle: string
  englishTitle: string
  toolIds: string[]

  constructor(key: BuiltinToolCategory, chineseTitle: string, englishTitle: string, toolIds: string[]) {
    this.key = key
    this.chineseTitle = chineseTitle
    this.englishTitle = englishTitle
    this.toolIds = toolIds
  }
}

// 工具中心与聊天选择器共用分类、分类顺序和组内顺序；专用设置项仍由工具中心单独渲染。
const BUILTIN_TOOL_CATEGORIES: BuiltinToolCategoryDefinition[] = [
  new BuiltinToolCategoryDefinition(BuiltinToolCategory.WEB, '联网与检索', 'Web & Search',
    ['web_search', 'builtin_browser']),
  new BuiltinToolCategoryDefinition(BuiltinToolCategory.EMAIL, '邮件', 'Email',
    ['email_read', 'email_send']),
  new BuiltinToolCategoryDefinition(BuiltinToolCategory.MAPS, '地图与地点', 'Maps & Places',
    ['map_search_route', 'open_map_route', 'saved_places']),
  new BuiltinToolCategoryDefinition(BuiltinToolCategory.CALENDAR, '日程', 'Calendar',
    ['read_schedule', 'write_schedule']),
  new BuiltinToolCategoryDefinition(BuiltinToolCategory.DOCUMENTS, '文档与图像', 'Documents & Images',
    ['pdf_toolkit', 'image_toolkit', 'vision_read_image', 'docx_toolkit', 'xlsx_toolkit', 'canvas_document']),
  new BuiltinToolCategoryDefinition(BuiltinToolCategory.COMPUTING, '计算与绘图', 'Computation & Charts',
    ['python_sandbox', 'math_chart']),
  new BuiltinToolCategoryDefinition(BuiltinToolCategory.ASSISTANT, '对话与协作', 'Conversation & Collaboration',
    ['compact', 'ask_user', 'sub_agent', 'plan_mode']),
  new BuiltinToolCategoryDefinition(BuiltinToolCategory.SKILLS, 'Skill', 'Skill', ['use_skill']),
  new BuiltinToolCategoryDefinition(BuiltinToolCategory.OTHER, '其他工具', 'Other Tools', [])
]

export class BuiltinToolDisplayGroup {
  key: BuiltinToolCategory
  title: string
  tools: ToolConfig[]

  constructor(key: BuiltinToolCategory, title: string, tools: ToolConfig[]) {
    this.key = key
    this.title = title
    this.tools = tools
  }
}

export function getBuiltinToolCategory(toolId: string): BuiltinToolCategory {
  for (const category of BUILTIN_TOOL_CATEGORIES) {
    if (category.toolIds.includes(toolId)) {
      return category.key
    }
  }
  return BuiltinToolCategory.OTHER
}

export function getBuiltinToolCategoryTitle(key: BuiltinToolCategory): string {
  for (const category of BUILTIN_TOOL_CATEGORIES) {
    if (category.key === key) {
      return pickLocalizedText(category.chineseTitle, category.englishTitle)
    }
  }
  return pickLocalizedText('其他工具', 'Other Tools')
}

function getToolDisplayIndex(tool: ToolConfig): number {
  const isMcp = tool.sourceType === ToolSourceType.MCP && tool.sourceId.trim() !== ''
  let offset = 0
  for (const category of BUILTIN_TOOL_CATEGORIES) {
    const index = category.toolIds.indexOf(tool.id)
    if (!isMcp && index >= 0) {
      return offset + index
    }
    offset += category.toolIds.length
  }
  // 未分类工具排在内置分类末尾，MCP 服务保留原有相对顺序并放在最后。
  return offset + (isMcp ? 1 : 0)
}

export function sortToolsForDisplay(tools: ToolConfig[]): ToolConfig[] {
  return [...tools].sort((left: ToolConfig, right: ToolConfig): number =>
    getToolDisplayIndex(left) - getToolDisplayIndex(right))
}

export function getBuiltinToolDisplayGroups(tools: ToolConfig[]): BuiltinToolDisplayGroup[] {
  const sortedTools = sortToolsForDisplay(tools)
  const groups: BuiltinToolDisplayGroup[] = []
  for (const category of BUILTIN_TOOL_CATEGORIES) {
    const categoryTools = sortedTools.filter((tool: ToolConfig): boolean =>
      getBuiltinToolCategory(tool.id) === category.key)
    if (categoryTools.length > 0) {
      groups.push(new BuiltinToolDisplayGroup(category.key,
        getBuiltinToolCategoryTitle(category.key), categoryTools))
    }
  }
  return groups
}
