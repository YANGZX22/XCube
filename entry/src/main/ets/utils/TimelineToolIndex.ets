import { ToolCall, ToolResult } from '../models/ChatModels'

class IndexedToolCall {
  call: ToolCall
  position: number

  constructor(call: ToolCall, position: number) {
    this.call = call
    this.position = position
  }
}

// 每次工具集合变化时建立一次索引。每个时间段只访问自己的调用，
// 避免工具分组、图表和地图各自扫描整条消息，变成 O(段数 × 调用数)。
export class TimelineToolIndex {
  private calls: ToolCall[]
  private callsById: Map<string, IndexedToolCall[]> = new Map()
  private resultsById: Map<string, ToolResult> = new Map()

  constructor(calls: ToolCall[], results: ToolResult[]) {
    this.calls = calls
    for (let i = 0; i < calls.length; i++) {
      const call = calls[i]
      let matches = this.callsById.get(call.id)
      if (matches === undefined) {
        matches = []
        this.callsById.set(call.id, matches)
      }
      matches.push(new IndexedToolCall(call, i))
    }
    for (let i = 0; i < results.length; i++) {
      const result = results[i]
      if (!this.resultsById.has(result.toolCallId)) {
        this.resultsById.set(result.toolCallId, result)
      }
    }
  }

  getCalls(ids: string[] = []): ToolCall[] {
    if (ids.length === 0) {
      return this.calls
    }
    const matches: IndexedToolCall[] = []
    const seen = new Set<string>()
    for (let i = 0; i < ids.length; i++) {
      if (seen.has(ids[i])) {
        continue
      }
      seen.add(ids[i])
      const entries = this.callsById.get(ids[i])
      if (entries !== undefined) {
        for (let j = 0; j < entries.length; j++) {
          matches.push(entries[j])
        }
      }
    }
    // 与原先按消息顺序过滤的行为一致，兼容交错的子智能体调用和乱序 ID。
    matches.sort((left: IndexedToolCall, right: IndexedToolCall): number => left.position - right.position)
    return matches.map((entry: IndexedToolCall): ToolCall => entry.call)
  }

  getResult(id: string): ToolResult | null {
    return this.resultsById.get(id) ?? null
  }
}
