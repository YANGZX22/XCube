/**
 * 简易 JSON 路径解析工具
 * 支持点路径与数组下标，如：data.total_balance、balance_infos[0].currency、list[2]
 * 找不到或类型不符时返回 null，调用方需自行兜底。
 */

// 将一段路径拆成 key 序列，数组下标也拆成独立 key
// 例：'data.list[0].amount' -> ['data', 'list', '0', 'amount']
function splitPath(path: string): string[] {
  const result: string[] = []
  const segments = path.split('.')
  for (let i = 0; i < segments.length; i++) {
    const seg = segments[i].trim()
    if (seg === '') {
      continue
    }
    // 处理形如 list[0] 或 list[0][1]
    let buffer = ''
    let j = 0
    while (j < seg.length) {
      const ch = seg.charAt(j)
      if (ch === '[') {
        if (buffer !== '') {
          result.push(buffer)
          buffer = ''
        }
        // 读取直到 ]
        let idx = ''
        j++
        while (j < seg.length && seg.charAt(j) !== ']') {
          idx += seg.charAt(j)
          j++
        }
        result.push(idx.trim())
      } else if (ch === ']') {
        // 跳过多余的 ]
      } else {
        buffer += ch
      }
      j++
    }
    if (buffer !== '') {
      result.push(buffer)
    }
  }
  return result
}

// 在已解析的对象上按路径取值，返回原始值（可能是 string/number/boolean/object）
export function resolveJsonValue(root: Object | null, path: string): Object | null {
  if (root === null || path.trim() === '') {
    return null
  }
  const keys = splitPath(path)
  let current: Object | null = root
  for (let i = 0; i < keys.length; i++) {
    if (current === null) {
      return null
    }
    const key = keys[i]
    if (Array.isArray(current)) {
      const arr = current as Object[]
      const index = Number.parseInt(key, 10)
      if (Number.isNaN(index) || index < 0 || index >= arr.length) {
        return null
      }
      current = arr[index] as Object
    } else if (typeof current === 'object') {
      const record = current as Record<string, Object>
      const next: Object | undefined = record[key]
      if (next === undefined || next === null) {
        return null
      }
      current = next
    } else {
      // 已经是标量，但路径还没走完
      return null
    }
  }
  return current
}

// 取字符串结果（数字会转成字符串），失败返回空串
export function resolveJsonString(root: Object | null, path: string): string {
  const value = resolveJsonValue(root, path)
  if (value === null) {
    return ''
  }
  if (typeof value === 'string') {
    return value as string
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return `${value}`
  }
  return ''
}

// 安全解析 JSON 字符串为对象，失败返回 null
export function safeParseJson(text: string): Object | null {
  if (text === '') {
    return null
  }
  try {
    return JSON.parse(text) as Object
  } catch (e) {
    return null
  }
}
