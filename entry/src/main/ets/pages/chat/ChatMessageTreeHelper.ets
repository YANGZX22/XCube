import { ChatMessage } from '../../models/ChatModels'

/**
 * 会话内对话树工具
 *
 * 数据模型：
 * - 每条消息用 parentId 指向其在对话链中的前驱消息（根消息 parentId 为空）。
 * - 同一 parentId 的多条消息互为"版本"（兄弟）。
 * - 会话用 activeLeafId 记录当前路径的叶子，从叶子沿 parentId 回溯得到当前展示路径。
 *
 * 所有函数都是纯函数，不修改入参。
 */

// 单条消息的版本信息（在其兄弟中的位置）
export interface MessageVersionInfo {
  index: number  // 0-based，在兄弟列表中的序号
  count: number  // 兄弟总数
}

// 旧数据线性建链的修复项
export interface LegacyChainFix {
  messageId: string
  parentId: string
}

export interface LegacyChainResult {
  fixes: LegacyChainFix[]
  leafId: string
}

function buildMessageMap(allMessages: ChatMessage[]): Map<string, ChatMessage> {
  const map = new Map<string, ChatMessage>()
  for (let i = 0; i < allMessages.length; i++) {
    map.set(allMessages[i].id, allMessages[i])
  }
  return map
}

// 按 timestamp 升序排序（同毫秒用 id 兜底，保证稳定确定性）
function sortByTimestampAsc(messages: ChatMessage[]): ChatMessage[] {
  const sorted = messages.slice()
  sorted.sort((a: ChatMessage, b: ChatMessage): number => {
    if (a.timestamp !== b.timestamp) {
      return a.timestamp - b.timestamp
    }
    if (a.id < b.id) {
      return -1
    }
    if (a.id > b.id) {
      return 1
    }
    return 0
  })
  return sorted
}

// 获取某节点的直接子消息（即 parentId === node.id 的消息），按 timestamp 升序
export function getChildren(allMessages: ChatMessage[], nodeId: string): ChatMessage[] {
  const children: ChatMessage[] = []
  for (let i = 0; i < allMessages.length; i++) {
    if (allMessages[i].parentId === nodeId) {
      children.push(allMessages[i])
    }
  }
  return sortByTimestampAsc(children)
}

// 获取某消息的兄弟列表（含自身，相同 parentId），按 timestamp 升序
export function getSiblings(allMessages: ChatMessage[], message: ChatMessage): ChatMessage[] {
  return getChildren(allMessages, message.parentId)
}

// 计算某消息在其兄弟中的版本信息
export function getVersionInfo(allMessages: ChatMessage[], message: ChatMessage): MessageVersionInfo {
  const siblings = getSiblings(allMessages, message)
  let index = 0
  for (let i = 0; i < siblings.length; i++) {
    if (siblings[i].id === message.id) {
      index = i
      break
    }
  }
  return { index, count: siblings.length }
}

// 从某节点沿"最新 child"一路向下走到叶子
export function resolveLeafOfSubtree(allMessages: ChatMessage[], node: ChatMessage): ChatMessage {
  let current = node
  const visited = new Set<string>()
  while (!visited.has(current.id)) {
    visited.add(current.id)
    const children = getChildren(allMessages, current.id)
    if (children.length === 0) {
      break
    }
    // 取 timestamp 最大（最新）的 child
    current = children[children.length - 1]
  }
  return current
}

// 收集某节点及其全部后代的消息 id（用于删除整条子树）
export function collectSubtreeIds(allMessages: ChatMessage[], node: ChatMessage): string[] {
  const ids: string[] = []
  const stack: string[] = [node.id]
  const visited = new Set<string>()
  while (stack.length > 0) {
    const id = stack.pop() as string
    if (visited.has(id)) {
      continue
    }
    visited.add(id)
    ids.push(id)
    const children = getChildren(allMessages, id)
    for (let i = 0; i < children.length; i++) {
      stack.push(children[i].id)
    }
  }
  return ids
}

/**
 * 计算当前活跃路径：从 activeLeafId 沿 parentId 回溯到根，再反转。
 * - activeLeafId 为空或找不到对应消息时，回退为按 timestamp 升序的线性序列（兼容旧数据）。
 */
export function computeActivePath(allMessages: ChatMessage[], activeLeafId: string): ChatMessage[] {
  if (allMessages.length === 0) {
    return []
  }
  const map = buildMessageMap(allMessages)
  const leaf = activeLeafId !== '' ? map.get(activeLeafId) : undefined
  if (leaf === undefined) {
    // 回退：旧数据没有树结构，直接按时间线性返回全部消息
    const linear = sortByTimestampAsc(allMessages)
    stampVersionInfo(allMessages, linear)
    return linear
  }
  const reversed: ChatMessage[] = []
  let current: ChatMessage | undefined = leaf
  const visited = new Set<string>()
  while (current !== undefined && !visited.has(current.id)) {
    visited.add(current.id)
    reversed.push(current)
    if (current.parentId === '') {
      break
    }
    current = map.get(current.parentId)
  }
  reversed.reverse()
  stampVersionInfo(allMessages, reversed)
  return reversed
}

// 给路径上的每条消息写入运行时版本信息（versionIndex / versionCount）
function stampVersionInfo(allMessages: ChatMessage[], path: ChatMessage[]): void {
  for (let i = 0; i < path.length; i++) {
    const info = getVersionInfo(allMessages, path[i])
    path[i].versionIndex = info.index
    path[i].versionCount = info.count
  }
}

/**
 * 旧数据惰性建链：当会话没有 activeLeafId（树结构未初始化）时，
 * 按 timestamp 升序把所有消息串成单链，返回需要回写的 parentId 修复项与叶子 id。
 * 已经具备 parentId / activeLeafId 的会话不应调用此函数。
 */
export function buildLegacyChain(allMessages: ChatMessage[]): LegacyChainResult {
  const ordered = sortByTimestampAsc(allMessages)
  const fixes: LegacyChainFix[] = []
  let prevId = ''
  for (let i = 0; i < ordered.length; i++) {
    const msg = ordered[i]
    if (msg.parentId !== prevId) {
      fixes.push({ messageId: msg.id, parentId: prevId })
    }
    prevId = msg.id
  }
  return { fixes, leafId: ordered.length > 0 ? ordered[ordered.length - 1].id : '' }
}
