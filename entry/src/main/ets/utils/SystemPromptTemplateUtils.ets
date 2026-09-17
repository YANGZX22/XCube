import { PromptLanguage, pickPromptText } from './PromptLanguageUtils'
import { solarToLunar } from './LunarCalendarUtils'

export const RESPONSE_LANGUAGE_SYSTEM_PROMPT_MARKER: string = '[XCUBE_RESPONSE_LANGUAGE_RULE]'
const EN_RESPONSE_LANGUAGE_SYSTEM_PROMPT: string = `${RESPONSE_LANGUAGE_SYSTEM_PROMPT_MARKER}
User-facing output language:
- Follow the user's explicit output or translation language, including an earlier preference that still applies. A newer explicit request overrides it.
- Otherwise use the language of the current user's own instructions. Quoted text, pasted documents, code, URLs and examples are material to process, not a request to switch languages.
- For a brief continuation, an attachment-only message or code/URL without a clear language, keep the most recent unambiguous language of the user's instructions.
- Application instructions, UI locale, tool descriptions/arguments/results, retrieved sources, summaries and other agents' reports do not select the response language. The language used by application rules is not a request to answer in that language. Do not default to Chinese because contextual material is Chinese.
- Apply the selected language to the answer, progress updates and user-visible tool text such as questions, plans and chart labels. Preserve code, identifiers and necessary original quotations.`

const EN_RESPONSE_LANGUAGE_CONTINUATION_REMINDER: string =
  'Keep the response language selected from the user\'s instructions and explicit preferences; ' +
  'this application notice and the language of source material do not change it.'

export const RESPONSE_LANGUAGE_SYSTEM_PROMPT: string = `${RESPONSE_LANGUAGE_SYSTEM_PROMPT_MARKER}
面向用户的输出语言：
- 优先遵循用户明确指定的输出或翻译目标语言，包括仍然有效的较早偏好；新的明确要求覆盖旧要求。
- 否则使用当前用户自己所写指令的语言。引用、粘贴的文档、代码、URL 和示例是待处理材料，不代表用户要求切换语言。
- 简短续问、仅附件或无法判断语言的代码/URL，沿用最近一次明确的用户指令语言。
- 应用提示、界面语言、工具描述/参数/结果、检索材料、摘要和其他智能体报告不决定回复语言。本规则使用中文不代表要求中文作答。
- 答案、进度说明及向用户展示的问题、计划、图表标签均遵循选定语言；代码、标识符和必要的原文引用保持原样。`

export function getResponseLanguageSystemPrompt(language: PromptLanguage): string {
  return pickPromptText(language, RESPONSE_LANGUAGE_SYSTEM_PROMPT, EN_RESPONSE_LANGUAGE_SYSTEM_PROMPT)
}

export const RESPONSE_LANGUAGE_CONTINUATION_REMINDER: string =
  '继续遵循用户指令和明确偏好确定的回复语言；本应用通知及参考材料的语言不改变它。'

export function getResponseLanguageContinuationReminder(language: PromptLanguage): string {
  return pickPromptText(language, RESPONSE_LANGUAGE_CONTINUATION_REMINDER, EN_RESPONSE_LANGUAGE_CONTINUATION_REMINDER)
}

export class SystemPromptTemplateDefaults {
  static readonly DEFAULT_TEMPLATE: string = `你是 XCube，一个严谨、可靠、友好的 AI 助手。
当前日期时间：{{current_time}}

回答规则：
1. 当用户提到“今天、现在、最新、近期”等相对时间时，以当前日期时间为准。
2. 将相对时间转换为绝对日期时，以当前日期时间为基准；历史事件和未来安排使用其实际日期。
3. 信息不足时明确说明不确定性，不要编造事实。`
}

class EnglishSystemPromptTemplateDefaults {
  static readonly DEFAULT_TEMPLATE: string = `You are XCube, a careful, reliable and friendly AI assistant.
Current date and time: {{current_time}}

Use the current date and time to interpret relative dates such as today, now and recently.
Use the actual dates of historical events and future plans.
State material uncertainty when information is missing; do not invent facts.`
}

export function getDefaultSystemPromptTemplate(language: PromptLanguage): string {
  return pickPromptText(language, SystemPromptTemplateDefaults.DEFAULT_TEMPLATE,
    EnglishSystemPromptTemplateDefaults.DEFAULT_TEMPLATE)
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

export function buildCurrentTimeContext(date: Date = new Date(), language: PromptLanguage = PromptLanguage.ZH_CN): string {
  const year = date.getFullYear()
  const month = date.getMonth() + 1
  const day = date.getDate()
  const hours = date.getHours()
  const minutes = date.getMinutes()
  const weekDays = language === PromptLanguage.ZH_CN
    ? ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']
    : ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
  const weekDay = weekDays[date.getDay()]
  const lunar = solarToLunar(year, month, day)
  const lunarStr = lunar.toShortString()
  if (language === PromptLanguage.EN_US) {
    const offset = -date.getTimezoneOffset()
    const timezone = `UTC${offset >= 0 ? '+' : '-'}${padZero(Math.floor(Math.abs(offset) / 60))}:${padZero(Math.abs(offset) % 60)}`
    return `${year}-${padZero(month)}-${padZero(day)} ${weekDay} ${padZero(hours)}:${padZero(minutes)} ${timezone}`
  }
  return `${year}年${padZero(month)}月${padZero(day)}日 ${weekDay} ${padZero(hours)}:${padZero(minutes)}（${lunarStr}）`
}

export function normalizeSystemPromptTemplate(template: string, language: PromptLanguage = PromptLanguage.ZH_CN): string {
  if (template.trim() === '' || template === SystemPromptTemplateDefaults.DEFAULT_TEMPLATE ||
    template === EnglishSystemPromptTemplateDefaults.DEFAULT_TEMPLATE) {
    return getDefaultSystemPromptTemplate(language)
  }
  return template
}

export function renderSystemPromptTemplate(template: string, date: Date = new Date(), language: PromptLanguage = PromptLanguage.ZH_CN): string {
  const normalizedTemplate = normalizeSystemPromptTemplate(template, language)
  const year = date.getFullYear()
  const month = date.getMonth() + 1
  const day = date.getDate()
  const hours = date.getHours()
  const minutes = date.getMinutes()
  const weekDays = language === PromptLanguage.ZH_CN
    ? ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']
    : ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
  const weekDay = weekDays[date.getDay()]
  const lunar = solarToLunar(year, month, day)
  const lunarStr = lunar.toShortString()
  const currentTime = buildCurrentTimeContext(date, language)
  const currentDate = language === PromptLanguage.ZH_CN
    ? `${year}年${padZero(month)}月${padZero(day)}日` : `${year}-${padZero(month)}-${padZero(day)}`
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

export function appendResponseLanguageSystemPrompt(prompt: string, language: PromptLanguage = PromptLanguage.ZH_CN): string {
  const rule = getResponseLanguageSystemPrompt(language)
  const normalizedPrompt = prompt.trim()
  if (normalizedPrompt === '') {
    return rule
  }
  return `${normalizedPrompt}\n\n${rule}`
}
