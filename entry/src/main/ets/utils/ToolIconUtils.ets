/**
 * 工具图标的统一映射。
 * 工具中心、工具选择面板与聊天里的工具结果条共用同一套图标，
 * 避免同一个工具在不同入口长得不一样。
 */

export function normalizeToolIconId(value: string): string {
  const normalized = value.trim().toLowerCase().replace(/[\s\-]+/g, '_')
  if (normalized === 'exa_search' || normalized === 'websearch' || normalized === 'search_web' ||
    normalized === 'internet_search' || normalized === 'web_search_exa') {
    return 'web_search'
  }
  if (normalized === 'user_input' || normalized === 'ask') {
    return 'ask_user'
  }
  if (normalized === 'sub_agent_message' || normalized === 'sub_agent_result') {
    return 'sub_agent'
  }
  if (normalized === 'plan') {
    return 'plan_mode'
  }
  if (normalized === 'compact' || normalized === 'context_compaction') {
    return 'compact_context'
  }
  return normalized
}

// 少数工具用位图图标（Symbol 里没有对应字形），调用方据此改走 Image 渲染
export const TOOL_ICON_IMAGE_DOCX: string = 'docx'
export const TOOL_ICON_IMAGE_XLSX: string = 'xlsx'

export function resolveToolIconImageKind(toolId: string): string {
  const normalized = normalizeToolIconId(toolId)
  if (normalized === 'docx_to_text') {
    return TOOL_ICON_IMAGE_DOCX
  }
  if (normalized === 'xlsx_to_text') {
    return TOOL_ICON_IMAGE_XLSX
  }
  return ''
}

export function resolveToolSymbolResource(toolId: string): Resource {
  switch (normalizeToolIconId(toolId)) {
    case 'web_search':
      return $r('sys.symbol.worldclock_fill_2')
    case 'ask_user':
      return $r('sys.symbol.ellipsis_message')
    case 'sub_agent':
      return $r('sys.symbol.protein')
    case 'python_sandbox':
      return $r('sys.symbol.doc_text')
    case 'canvas_document':
      return $r('sys.symbol.paintbrush_pointed_waveform')
    case 'pdf_to_text':
      return $r('sys.symbol.pdf_doc')
    case 'image_to_text':
      return $r('sys.symbol.picture')
    case 'vision_read_image':
      return $r('sys.symbol.hi_vison')
    case 'use_skill':
      return $r('sys.symbol.more')
    case 'math_chart':
      return $r('sys.symbol.histogram')
    case 'read_schedule':
      return $r('sys.symbol.calendar')
    case 'write_schedule':
      return $r('sys.symbol.calendar_badge_plus')
    case 'map_search_route':
      return $r('sys.symbol.map')
    case 'saved_places':
      return $r('sys.symbol.location_north_up_right')
    case 'open_map_route':
      return $r('sys.symbol.navigation')
    case 'email_send':
      return $r('sys.symbol.envelope_badge_arrowshape_turn_up_right')
    case 'email_read':
      return $r('sys.symbol.envelope_on_envelope_badge_arrow_left')
    case 'plan_mode':
      return $r('sys.symbol.list_checkmark')
    case 'compact_context':
      return $r('sys.symbol.doc_zipper')
    case 'knowledge_search':
      return $r('sys.symbol.doc_text_badge_magnifyingglass')
    default:
      return $r('sys.symbol.wrench_and_screwdriver')
  }
}
