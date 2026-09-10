export interface AskUserQuestion {
  id: string
  question: string
  options: string[]
  selectionType: string
}

export interface AskUserQuestionParseResult {
  questions: AskUserQuestion[]
  status: string
}

// 只解析展示所需字段，不记录参数正文。兼容旧的顶层单问题与二次 JSON 编码。
export function parseAskUserQuestions(argumentsJson: string): AskUserQuestionParseResult {
  if (argumentsJson.trim() === '') {
    return { questions: [], status: 'empty' }
  }
  let decoded: Object | null = null
  try {
    decoded = JSON.parse(argumentsJson) as Object | null
    if (typeof decoded === 'string') {
      decoded = JSON.parse(decoded) as Object | null
    }
  } catch (_error) {
    return { questions: [], status: 'invalid_json' }
  }
  if (decoded === null || typeof decoded !== 'object' || Array.isArray(decoded)) {
    return { questions: [], status: 'invalid_schema' }
  }
  const args = decoded as Record<string, Object>
  const rawQuestions = args['questions']
  let items: Object[] = []
  if (Array.isArray(rawQuestions)) {
    items = rawQuestions as Object[]
  } else if (rawQuestions === undefined && typeof args['question'] === 'string') {
    items = [args]
  } else {
    return { questions: [], status: 'invalid_schema' }
  }
  const questions: AskUserQuestion[] = []
  const usedIds = new Set<string>()
  for (let i = 0; i < items.length; i++) {
    const raw = items[i]
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
      continue
    }
    const item = raw as Record<string, Object>
    if (typeof item['question'] !== 'string' || (item['question'] as string).trim() === '') {
      continue
    }
    const text = (item['question'] as string).trim()
    const suppliedId = typeof item['id'] === 'string' ? (item['id'] as string).trim() : ''
    const baseId = suppliedId !== '' ? suppliedId : `q_${i + 1}`
    let id = baseId
    let suffix = 2
    while (usedIds.has(id)) {
      id = `${baseId}_${suffix++}`
    }
    usedIds.add(id)
    const options: string[] = []
    if (Array.isArray(item['options'])) {
      const rawOptions = item['options'] as Object[]
      for (let j = 0; j < rawOptions.length; j++) {
        if (typeof rawOptions[j] === 'string') {
          const option = (rawOptions[j] as string).trim()
          if (option !== '' && !options.includes(option)) {
            options.push(option)
          }
        }
      }
    }
    const rawType = typeof item['selection_type'] === 'string'
      ? (item['selection_type'] as string).trim().toLowerCase() : ''
    const selectionType = rawType === 'single' || rawType === 'multi' || rawType === 'text'
      ? rawType : (options.length > 0 ? 'single' : 'text')
    questions.push({ id: id, question: text, options: options, selectionType: selectionType })
  }
  return { questions: questions, status: questions.length > 0 ? 'ready' : 'no_questions' }
}

// 相同 id 的参数内容更新时，ForEach 也必须重建展示；答案仍按 id 保存在卡片中。
export function askUserQuestionRenderKey(question: AskUserQuestion): string {
  return JSON.stringify([question.id, question.question, question.selectionType, question.options])
}
