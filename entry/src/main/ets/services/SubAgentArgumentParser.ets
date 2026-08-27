export interface SubAgentTaskArguments {
  name?: string
  prompt?: string
  expected_output?: string
}

export interface SubAgentDispatchArguments {
  main_thread_work?: string
  tasks?: SubAgentTaskArguments[]
}

interface RawSubAgentDispatchArguments {
  main_thread_work?: string
  mainThreadWork?: string
  tasks?: Object | string
  task?: Object | string
  sub_tasks?: Object | string
  subtasks?: Object | string
  task_1_name?: string
  task_1_prompt?: string
  task_1_expected_output?: string
  task_2_name?: string
  task_2_prompt?: string
  task_2_expected_output?: string
  task_3_name?: string
  task_3_prompt?: string
  task_3_expected_output?: string
}

interface RawSubAgentTaskArguments {
  name?: string
  prompt?: string
  instruction?: string
  instructions?: string
  content?: string
  task?: string
  description?: string
  expected_output?: string
  expectedOutput?: string
}

function stripJsonCodeFence(raw: string): string {
  const source = raw.trim()
  if (!source.startsWith('```')) {
    return source
  }
  const firstLineEnd = source.indexOf('\n')
  const closingFence = source.lastIndexOf('```')
  if (firstLineEnd < 0 || closingFence <= firstLineEnd) {
    return source
  }
  return source.substring(firstLineEnd + 1, closingFence).trim()
}

// 仅补齐已完整收到的值所缺少的尾部容器闭合符。字符串本身被截断时拒绝修复，
// 防止把半截 prompt 派发给子智能体。
export function repairTruncatedSubAgentToolArguments(raw: string): string {
  const source = raw.trim()
  if (!source.startsWith('{') && !source.startsWith('[')) {
    return ''
  }
  const stack: string[] = []
  let inString = false
  let escaped = false
  let rootClosed = false
  for (let i = 0; i < source.length; i++) {
    const character = source.charAt(i)
    if (inString) {
      if (escaped) {
        escaped = false
      } else if (character === '\\') {
        escaped = true
      } else if (character === '"') {
        inString = false
      }
      continue
    }
    if (character === '"') {
      inString = true
      continue
    }
    if (rootClosed) {
      if (character.trim() !== '') {
        return ''
      }
      continue
    }
    if (character === '{' || character === '[') {
      stack.push(character)
    } else if (character === '}' || character === ']') {
      if (stack.length === 0) {
        return ''
      }
      const expectedOpen = character === '}' ? '{' : '['
      if (stack[stack.length - 1] !== expectedOpen) {
        return ''
      }
      stack.pop()
      if (stack.length === 0) {
        rootClosed = true
      }
    }
  }
  if (inString || escaped || stack.length === 0) {
    return ''
  }
  const lastCharacter = source.charAt(source.length - 1)
  if (lastCharacter === ',' || lastCharacter === ':' || lastCharacter === '{' || lastCharacter === '[') {
    return ''
  }
  let repaired = source
  for (let i = stack.length - 1; i >= 0; i--) {
    repaired += stack[i] === '{' ? '}' : ']'
  }
  return repaired
}

function extractCompleteJsonValues(raw: string): string[] {
  const values: string[] = []
  const stack: string[] = []
  let start = -1
  let inString = false
  let escaped = false
  for (let i = 0; i < raw.length; i++) {
    const character = raw.charAt(i)
    if (inString) {
      if (escaped) {
        escaped = false
      } else if (character === '\\') {
        escaped = true
      } else if (character === '"') {
        inString = false
      }
      continue
    }
    if (character === '"') {
      inString = true
      continue
    }
    if (character === '{' || character === '[') {
      if (stack.length === 0) {
        start = i
      }
      stack.push(character)
      continue
    }
    if (character !== '}' && character !== ']') {
      continue
    }
    if (stack.length === 0) {
      start = -1
      continue
    }
    const expectedOpen = character === '}' ? '{' : '['
    if (stack[stack.length - 1] !== expectedOpen) {
      stack.length = 0
      start = -1
      continue
    }
    stack.pop()
    if (stack.length === 0 && start >= 0) {
      values.push(raw.substring(start, i + 1))
      start = -1
    }
  }
  return values
}

function hasTaskField(value: Object): boolean {
  if (Array.isArray(value)) {
    return value.length > 0
  }
  const args = value as RawSubAgentDispatchArguments
  return args.tasks !== undefined || args.task !== undefined || args.sub_tasks !== undefined ||
    args.subtasks !== undefined
}

function parseBestJsonValue(raw: string): Object | string {
  const source = stripJsonCodeFence(raw)
  try {
    return JSON.parse(source) as Object | string
  } catch (firstError) {
    const completeValues = extractCompleteJsonValues(source)
    let fallback: Object | string | null = null
    for (let i = completeValues.length - 1; i >= 0; i--) {
      try {
        const candidate = JSON.parse(completeValues[i]) as Object | string
        if (typeof candidate === 'object' && candidate !== null && hasTaskField(candidate)) {
          return candidate
        }
        if (fallback === null) {
          fallback = candidate
        }
      } catch (_error) {}
    }
    if (fallback !== null) {
      return fallback
    }
    const repaired = repairTruncatedSubAgentToolArguments(source)
    if (repaired !== '') {
      return JSON.parse(repaired) as Object | string
    }
    throw new Error(firstError instanceof Error ? firstError.message : JSON.stringify(firstError))
  }
}

function normalizeString(value: string | undefined): string {
  return value !== undefined ? value.trim() : ''
}

function normalizeTask(value: Object | string): SubAgentTaskArguments | null {
  if (typeof value === 'string') {
    const prompt = value.trim()
    return prompt !== '' ? { prompt: prompt } : null
  }
  if (value === null || Array.isArray(value)) {
    return null
  }
  const raw = value as RawSubAgentTaskArguments
  const promptCandidates: Array<string | undefined> = [
    raw.prompt,
    raw.instruction,
    raw.instructions,
    raw.content,
    raw.task,
    raw.description
  ]
  let prompt = ''
  for (let i = 0; i < promptCandidates.length; i++) {
    prompt = normalizeString(promptCandidates[i])
    if (prompt !== '') {
      break
    }
  }
  const task: SubAgentTaskArguments = {
    name: normalizeString(raw.name),
    prompt: prompt,
    expected_output: normalizeString(raw.expected_output !== undefined ? raw.expected_output : raw.expectedOutput)
  }
  return task
}

function normalizeTasks(rawValue: Object | string | undefined): SubAgentTaskArguments[] {
  if (rawValue === undefined || rawValue === null) {
    return []
  }
  let value: Object | string = rawValue
  for (let depth = 0; depth < 2 && typeof value === 'string'; depth++) {
    const source = stripJsonCodeFence(value)
    try {
      value = JSON.parse(source) as Object | string
    } catch (_error) {
      const plainTask = normalizeTask(source)
      return plainTask !== null ? [plainTask] : []
    }
  }
  const tasks: SubAgentTaskArguments[] = []
  if (Array.isArray(value)) {
    const values = value as Array<Object | string>
    for (let i = 0; i < values.length; i++) {
      const task = normalizeTask(values[i])
      if (task !== null) {
        tasks.push(task)
      }
    }
    return tasks
  }
  const singleTask = normalizeTask(value)
  if (singleTask !== null) {
    tasks.push(singleTask)
  }
  return tasks
}

function appendFlatTask(
  tasks: SubAgentTaskArguments[],
  name: string | undefined,
  prompt: string | undefined,
  expectedOutput: string | undefined
): void {
  const normalizedPrompt = normalizeString(prompt)
  if (normalizedPrompt === '') {
    return
  }
  tasks.push({
    name: normalizeString(name),
    prompt: normalizedPrompt,
    expected_output: normalizeString(expectedOutput)
  })
}

export function parseSubAgentToolArguments(raw: string): SubAgentDispatchArguments {
  let parsed = parseBestJsonValue(raw)
  // 兼容代理把完整 function.arguments 再 JSON 编码一到两层。
  for (let depth = 0; depth < 2 && typeof parsed === 'string'; depth++) {
    parsed = parseBestJsonValue(parsed)
  }
  if (typeof parsed === 'string' || parsed === null) {
    throw new Error('sub_agent 参数必须是 JSON 对象')
  }
  if (Array.isArray(parsed)) {
    return { tasks: normalizeTasks(parsed) }
  }
  const args = parsed as RawSubAgentDispatchArguments
  const mainThreadWork = normalizeString(args.main_thread_work !== undefined ?
    args.main_thread_work : args.mainThreadWork)
  const rawTasks = args.tasks !== undefined ? args.tasks :
    (args.task !== undefined ? args.task : (args.sub_tasks !== undefined ? args.sub_tasks : args.subtasks))
  const tasks = normalizeTasks(rawTasks)
  if (tasks.length === 0) {
    appendFlatTask(tasks, args.task_1_name, args.task_1_prompt, args.task_1_expected_output)
    appendFlatTask(tasks, args.task_2_name, args.task_2_prompt, args.task_2_expected_output)
    appendFlatTask(tasks, args.task_3_name, args.task_3_prompt, args.task_3_expected_output)
  }
  return {
    main_thread_work: mainThreadWork,
    tasks: tasks
  }
}
