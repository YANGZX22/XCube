import { CodeBlockNode, InlineCodeNode, InlineHtmlFontNode, LinkNode, TextNode, TreeNode } from '../model/TreeNode'
import { TextSelectionSegment } from '../model/TextSelectionInfo'

function pushTextSegment(list: TextSelectionSegment[], text: string) {
  if (!text) {
    return
  }
  const last = list.length > 0 ? list[list.length - 1] : undefined
  if (last && last.renderedLength == last.copyText.length) {
    last.copyText += text
    last.renderedLength += text.length
    return
  }
  list.push(new TextSelectionSegment(text.length, text))
}

function buildInlineSegments(nodes: TreeNode[] | undefined, list: TextSelectionSegment[]) {
  if (!nodes || nodes.length == 0) {
    return
  }
  for (let i = 0; i < nodes.length; i++) {
    const item = nodes[i]
    if (item.type == 'text') {
      pushTextSegment(list, (item as TextNode).text || '')
      continue
    }
    if (item.type == 'inlineCode') {
      pushTextSegment(list, ` ${(item as InlineCodeNode).text || ''} `)
      continue
    }
    if (item.type == 'inlineHtmlFont') {
      pushTextSegment(list, (item as InlineHtmlFontNode).text || '')
      continue
    }
    if (item.type == 'footnoteRef') {
      pushTextSegment(list, `[${item.id}]`)
      continue
    }
    if (item.type == 'latex') {
      list.push(new TextSelectionSegment(1, item.text || ''))
      continue
    }
    if (item.type == 'plugin') {
      if (item.display == 'inline' && item.selectable !== false) {
        list.push(new TextSelectionSegment(1, item.copyText || item.raw || ''))
      }
      continue
    }
    if (item.type == 'image') {
      const alt = item.alt || ''
      const label = alt ? `![${alt}](${item.url})` : (item.url || '')
      list.push(new TextSelectionSegment(1, label))
      continue
    }
    if (item.type == 'link') {
      buildInlineSegments((item as LinkNode).children, list)
      continue
    }
    if (item.children && item.children.length > 0) {
      buildInlineSegments(item.children as TreeNode[], list)
    }
  }
}

export function buildSelectionSegmentsFromBlock(node: TreeNode | undefined): TextSelectionSegment[] {
  const segments: TextSelectionSegment[] = []
  if (!node) {
    return segments
  }
  if (node.type == 'paragraph' || node.type == 'heading') {
    buildInlineSegments(node.children as TreeNode[], segments)
    return segments
  }
  if (node.type == 'text') {
    pushTextSegment(segments, node.text || '')
    return segments
  }
  if (node.type == 'inlineCode') {
    pushTextSegment(segments, ` ${node.text || ''} `)
    return segments
  }
  if (node.type == 'inlineHtmlFont') {
    pushTextSegment(segments, (node as InlineHtmlFontNode).text || '')
    return segments
  }
  if (node.type == 'codeBlock') {
    const code = (node as CodeBlockNode).text || ''
    pushTextSegment(segments, code)
    return segments
  }
  if (node.children && node.children.length > 0) {
    buildInlineSegments(node.children as TreeNode[], segments)
  }
  return segments
}
