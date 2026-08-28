import { AssistantResponseSegment, ToolCall } from '../models/ChatModels'
import { ToolCallCardEntry } from './ToolCallCard'

// 工具调用渲染分组：同一工具（同名 + 同来源）的多次调用合并成一张卡片
export class ToolCallRenderGroup {
  key: string = ''
  isAskUser: boolean = false
  askUserCalls: ToolCall[] = []
  entries: ToolCallCardEntry[] = []
  anyExecuting: boolean = false
}

export class MessageVChartPayload {
  id: string = ''
  specJson: string = ''
  summary: string = ''
  chartType: string = ''

  constructor(id: string, specJson: string, summary: string, chartType: string) {
    this.id = id
    this.specJson = specJson
    this.summary = summary
    this.chartType = chartType
  }
}

export class MessageMapPayload {
  id: string = ''
  resultContent: string = ''

  constructor(id: string, resultContent: string) {
    this.id = id
    this.resultContent = resultContent
  }
}

// AI 消息正文之前的展示单元。相邻的"条"会被并进同一个 BARS 块，
// 其余富卡片（追问、图表、地图、附件）各自成块，并把前面的条收口。
export enum TimelineBlockKind {
  BARS = 'bars',
  ASK_USER = 'ask_user',
  VCHART = 'vchart',
  MAP = 'map',
  ATTACHMENTS = 'attachments',
  COMPACTION = 'compaction',
  GUIDANCE = 'guidance',
  CONTENT = 'content'
}

// 能并进同一个块的三种"条"
export enum TimelineBarKind {
  REASONING = 'reasoning',
  LEGACY_REASONING = 'legacy_reasoning',
  TOOL = 'tool',
  SEARCH = 'search'
}

// 两份块列表：正文前（旧版顺序）与有序时间线，各自的 key 空间互不影响
export const TIMELINE_BLOCK_LIST_PRE_CONTENT: string = 'pre'
export const TIMELINE_BLOCK_LIST_ORDERED: string = 'timeline'

// 块字段用不到时给一个共享空对象，省掉 null 判断，也避免每次重算都新建实例
const EMPTY_SEGMENT: AssistantResponseSegment = new AssistantResponseSegment()
const EMPTY_TOOL_GROUP: ToolCallRenderGroup = new ToolCallRenderGroup()
const EMPTY_VCHART_PAYLOAD: MessageVChartPayload = new MessageVChartPayload('', '', '', '')
const EMPTY_MAP_PAYLOAD: MessageMapPayload = new MessageMapPayload('', '')

export class TimelineBar {
  // identity 只描述"这是哪一条"，块内位置变了才需要重画分割线，所以位置也编进 key
  identity: string = ''
  key: string = ''
  // 内容签名。分组入参是每次重算新建的普通对象、不可观察，
  // 签名变了才重建条目内容——身份不变就不会重播出入场动效。
  contentKey: string = ''
  listId: string = ''
  kind: TimelineBarKind = TimelineBarKind.TOOL
  isFirst: boolean = false
  segment: AssistantResponseSegment = EMPTY_SEGMENT
  toolGroup: ToolCallRenderGroup = EMPTY_TOOL_GROUP

  constructor(kind: TimelineBarKind, identity: string, contentKey: string) {
    this.kind = kind
    this.identity = identity
    this.contentKey = contentKey
  }

  // 思考条的正文挂在可观察的 segment 上，签名保持不变即可随流式刷新
  static reasoning(segment: AssistantResponseSegment): TimelineBar {
    const identity = 'reasoning_' + segment.id
    const bar = new TimelineBar(TimelineBarKind.REASONING, identity, identity)
    bar.segment = segment
    return bar
  }

  static legacyReasoning(messageId: string): TimelineBar {
    const identity = 'legacy_reasoning_' + messageId
    return new TimelineBar(TimelineBarKind.LEGACY_REASONING, identity, identity)
  }

  static tool(group: ToolCallRenderGroup, identity: string, signature: string): TimelineBar {
    const bar = new TimelineBar(TimelineBarKind.TOOL, identity, identity + '_' + signature)
    bar.toolGroup = group
    return bar
  }

  static search(identity: string, signature: string): TimelineBar {
    return new TimelineBar(TimelineBarKind.SEARCH, identity, identity + '_' + signature)
  }
}

export class TimelineBlock {
  key: string = ''
  listId: string = ''
  kind: TimelineBlockKind = TimelineBlockKind.BARS
  // 非 BARS 块把自身内容签名编进 key，内容一变就重建；BARS 块留空以保持稳定
  contentKey: string = ''
  bars: TimelineBar[] = []
  segment: AssistantResponseSegment = EMPTY_SEGMENT
  askUserCalls: ToolCall[] = []
  vchart: MessageVChartPayload = EMPTY_VCHART_PAYLOAD
  map: MessageMapPayload = EMPTY_MAP_PAYLOAD

  constructor(kind: TimelineBlockKind, contentKey: string = '') {
    this.kind = kind
    this.contentKey = contentKey
  }
}

// 往块列表里追加一条：能接在末尾的 BARS 块上就接，否则新开一块
export function appendTimelineBar(blocks: TimelineBlock[], bar: TimelineBar): void {
  const last = blocks.length > 0 ? blocks[blocks.length - 1] : null
  if (last !== null && last.kind === TimelineBlockKind.BARS) {
    last.bars.push(bar)
    return
  }
  const block = new TimelineBlock(TimelineBlockKind.BARS)
  block.bars.push(bar)
  blocks.push(block)
}

/**
 * 定稿：写入列表归属、块 key 与块内位置。
 * BARS 块的 key 只由位置决定，流式追加新条时块不会重建，
 * 条目自己的 ForEach 会重新求值，于是只有新条播放入场动效。
 */
export function finalizeTimelineBlocks(blocks: TimelineBlock[], listId: string): TimelineBlock[] {
  for (let i = 0; i < blocks.length; i++) {
    const block = blocks[i]
    block.listId = listId
    block.key = listId + '_' + block.kind + '_' + i.toString() +
      (block.contentKey === '' ? '' : '_' + block.contentKey)
    for (let j = 0; j < block.bars.length; j++) {
      const bar = block.bars[j]
      bar.listId = listId
      bar.isFirst = j === 0
      bar.key = (j === 0 ? 'f_' : 'n_') + bar.identity
    }
  }
  return blocks
}
