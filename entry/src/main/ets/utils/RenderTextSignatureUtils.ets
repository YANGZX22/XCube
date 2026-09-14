// 刷新标识只用于当前进程内的失效判断，不需要携带正文或工具结果全文。
// 每个对象的每个字段只保留最新文本；WeakMap 不阻止已离开会话的消息被回收。
class RenderTextSnapshot {
  text: string
  signature: string

  constructor(text: string, signature: string) {
    this.text = text
    this.signature = signature
  }
}

const snapshots: WeakMap<Object, Map<string, RenderTextSnapshot>> = new WeakMap()
let nextRevision: number = 0

export function encodeRenderText(owner: Object, field: string, text: string): string {
  let fields = snapshots.get(owner)
  if (text.length <= 256) {
    // 回滚/清空后及时释放上一份长文本。
    if (fields !== undefined) {
      fields.delete(field)
    }
    return `${text.length}:${text};`
  }
  if (fields === undefined) {
    fields = new Map<string, RenderTextSnapshot>()
    snapshots.set(owner, fields)
  }
  const previous = fields.get(field)
  if (previous !== undefined && previous.text === text) {
    return previous.signature
  }
  // 精确比较，不用长度或首尾采样，等长的中间编辑也必须触发刷新。
  // 追加时长度不同即可判定；未变化的历史文本复用同一个字符串。
  nextRevision++
  const signature = `r${nextRevision};`
  fields.set(field, new RenderTextSnapshot(text, signature))
  return signature
}
