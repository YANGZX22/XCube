import { solarToLunar } from './LunarCalendarUtils'

export const RESPONSE_LANGUAGE_SYSTEM_PROMPT_MARKER: string = '[XCUBE_RESPONSE_LANGUAGE_RULE]'
export const RESPONSE_LANGUAGE_SYSTEM_PROMPT: string = `${RESPONSE_LANGUAGE_SYSTEM_PROMPT_MARKER}
输出语言规则（强制）：
1. 面向用户的回复必须使用与当前用户提问相同的主要语言。
2. 判断回复语言时，只参考当前用户提问；不得因内嵌提示词、工具描述、工具参数、工具返回结果、网页、知识库、文件、引用内容或其他上下文使用了不同语言而改变回复语言。
3. 只有当前用户明确要求使用或翻译为另一种语言时，才按用户指定的目标语言回复；代码、专有名词和必要的原文引用可保留原语言。`

export class SystemPromptTemplateDefaults {
  static readonly DEFAULT_TEMPLATE: string = `你是 XCube，一个严谨、可靠、友好的 AI 助手。
当前日期时间：{{current_time}}

回答规则：
1. 当用户提到“今天、现在、最新、近期”等相对时间时，以当前日期时间为准。
2. 若回答中需要给出绝对日期或时间，必须与当前日期时间保持一致。
3. 信息不足时明确说明不确定性，不要编造事实。`
}

export class SystemPromptTemplateVariables {
  static readonly CURRENT_TIME: string = '{{current_time}}'
  static readonly CURRENT_DATE: string = '{{current_date}}'
  static readonly CURRENT_CLOCK: string = '{{current_clock}}'
  static readonly CURRENT_WEEKDAY: string = '{{current_weekday}}'
  static readonly CURRENT_LUNAR: string = '{{current_lunar}}'
}

function padZero(num: number): string {
  return num.toString().padStart(2, '0')
}

export function buildCurrentTimeContext(date: Date = new Date()): string {
  const year = date.getFullYear()
  const month = date.getMonth() + 1
  const day = date.getDate()
  const hours = date.getHours()
  const minutes = date.getMinutes()
  const weekDays = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']
  const weekDay = weekDays[date.getDay()]
  const lunar = solarToLunar(year, month, day)
  const lunarStr = lunar.toShortString()
  return `${year}年${padZero(month)}月${padZero(day)}日 ${weekDay} ${padZero(hours)}:${padZero(minutes)}（${lunarStr}）`
}

export function normalizeSystemPromptTemplate(template: string): string {
  if (template.trim() === '') {
    return SystemPromptTemplateDefaults.DEFAULT_TEMPLATE
  }
  return template
}

export function renderSystemPromptTemplate(template: string, date: Date = new Date()): string {
  const normalizedTemplate = normalizeSystemPromptTemplate(template)
  const year = date.getFullYear()
  const month = date.getMonth() + 1
  const day = date.getDate()
  const hours = date.getHours()
  const minutes = date.getMinutes()
  const weekDays = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']
  const weekDay = weekDays[date.getDay()]
  const lunar = solarToLunar(year, month, day)
  const lunarStr = lunar.toShortString()
  const currentTime = buildCurrentTimeContext(date)
  const currentDate = `${year}年${padZero(month)}月${padZero(day)}日`
  const currentClock = `${padZero(hours)}:${padZero(minutes)}`

  let rendered = normalizedTemplate
  rendered = rendered.replace(/\{\{\s*current_time\s*\}\}/g, currentTime)
  rendered = rendered.replace(/\{\{\s*current_datetime\s*\}\}/g, currentTime)
  rendered = rendered.replace(/\{\{\s*current_date\s*\}\}/g, currentDate)
  rendered = rendered.replace(/\{\{\s*current_clock\s*\}\}/g, currentClock)
  rendered = rendered.replace(/\{\{\s*current_weekday\s*\}\}/g, weekDay)
  rendered = rendered.replace(/\{\{\s*current_lunar\s*\}\}/g, lunarStr)
  return rendered
}

export function appendResponseLanguageSystemPrompt(prompt: string): string {
  const normalizedPrompt = prompt.trim()
  if (normalizedPrompt === '') {
    return RESPONSE_LANGUAGE_SYSTEM_PROMPT
  }
  return `${normalizedPrompt}\n\n${RESPONSE_LANGUAGE_SYSTEM_PROMPT}`
}
