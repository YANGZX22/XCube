export const TOOL_PROGRESS_WARNING: string =
  '连续相同的工具调用未取得新结果。请使用已有结果；只有存在明确缺口时才改用其他参数或方法，不要原样重试。'
export const TOOL_PROGRESS_STOP: string =
  '连续五次相同的工具调用返回相同结果，本轮已停止工具执行。请基于已有结果回答；若任务尚未完成，说明实际阻塞，不要声称完成。'

class ToolProgressState {
  requestId: string
  signature: string = ''
  result: string = ''
  repeats: number = 0

  constructor(requestId: string) {
    this.requestId = requestId
  }
}

// JSON 对象键顺序不代表调用或结果发生变化；数组顺序与字符串内容保留。
function canonicalValue(value: Object | null): string {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value)
  }
  if (Array.isArray(value)) {
    const parts: string[] = []
    const values = value as Object[]
    for (let i = 0; i < values.length; i++) {
      parts.push(canonicalValue(values[i]))
    }
    return `[${parts.join(',')}]`
  }
  const record = value as Record<string, Object>
  const keys = Object.keys(record).sort()
  const parts: string[] = []
  for (let i = 0; i < keys.length; i++) {
    parts.push(`${JSON.stringify(keys[i])}:${canonicalValue(record[keys[i]])}`)
  }
  return `{${parts.join(',')}}`
}

export function canonicalToolJson(text: string): string {
  try {
    return canonicalValue(JSON.parse(text) as Object | null)
  } catch (_error) {
    return text.trim()
  }
}

interface WaitArguments {
  wait?: boolean
}

function isBlockingInteraction(name: string, args: string): boolean {
  if (name === 'ask_user' || name === 'user_input' || name === 'ask') {
    return true
  }
  if (name === 'sub_agent_result') {
    try {
      const parsed = JSON.parse(args) as WaitArguments
      return parsed !== null && parsed.wait !== false
    } catch (_error) {
      return false
    }
  }
  return false
}

// 只跟踪活跃请求中每个智能体当前轮的连续调用，不限制有新结果的长任务。
export class ToolProgressGuard {
  private states: Map<string, ToolProgressState> = new Map()

  beginTurn(requestId: string, actorId: string): void {
    if (requestId !== '') {
      this.states.set(this.key(requestId, actorId), new ToolProgressState(requestId))
    }
  }

  endRequest(requestId: string): void {
    const keys: string[] = []
    this.states.forEach((state: ToolProgressState, key: string) => {
      if (state.requestId === requestId) {
        keys.push(key)
      }
    })
    for (let i = 0; i < keys.length; i++) {
      this.states.delete(keys[i])
    }
  }

  shouldStop(requestId: string, actorId: string): boolean {
    const state = this.states.get(this.key(requestId, actorId))
    return state !== undefined && state.repeats >= 5
  }

  observe(requestId: string, actorId: string, name: string, args: string, result: string): string {
    const state = this.states.get(this.key(requestId, actorId))
    // 已结束的请求可能仍有正在收尾的工具；不能由迟到结果重新创建状态。
    if (state === undefined) {
      return ''
    }
    if (isBlockingInteraction(name, args)) {
      state.signature = ''
      state.result = ''
      state.repeats = 0
      return ''
    }
    const signature = JSON.stringify([name, canonicalToolJson(args)])
    const canonicalResult = canonicalToolJson(result)
    state.repeats = state.signature === signature && state.result === canonicalResult ? state.repeats + 1 : 1
    state.signature = signature
    state.result = canonicalResult
    if (state.repeats >= 5) {
      return TOOL_PROGRESS_STOP
    }
    return state.repeats === 3 ? TOOL_PROGRESS_WARNING : ''
  }

  private key(requestId: string, actorId: string): string {
    return JSON.stringify([requestId, actorId])
  }
}
