/**
 * 工具 ID 的历史别名。
 * PDF/图片/DOCX/XLSX 读取工具早期叫 *_to_text，只能把文件转成文本；它们现在也会把原文件
 * 直接交给有原生视觉/文档能力的模型，因此改名为 *_toolkit。旧 ID 仍会出现在三个地方：
 * 已保存的工具选择、历史消息里的工具调用记录，以及沿用旧名字的模型输出。这些入口必须
 * 继续解析到新工具，否则升级后用户的勾选会静默失效，旧会话的工具卡片也会失去名字和图标。
 */

const LEGACY_TOOL_ID_MAP: Record<string, string> = {
  'pdf_to_text': 'pdf_toolkit',
  'image_to_text': 'image_toolkit',
  'docx_to_text': 'docx_toolkit',
  'xlsx_to_text': 'xlsx_toolkit'
}

// 入参必须已经过 trim + 小写 + 分隔符归一，与各调用方自己的归一化保持一致。
export function resolveLegacyToolId(normalizedToolId: string): string {
  return LEGACY_TOOL_ID_MAP[normalizedToolId] ?? normalizedToolId
}

export function normalizeAliasedToolId(value: string): string {
  return resolveLegacyToolId(value.trim().toLowerCase().replace(/[\s\-]+/g, '_'))
}
