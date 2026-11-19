import { pickPromptText, PromptLanguage } from './PromptLanguageUtils'

export const SLASH_COMMAND_COMPACT: string = 'compact'
export const SLASH_COMMAND_MODELS: string = 'models'
export const SLASH_COMMAND_REASONING: string = 'reasoning'
export const SLASH_COMMAND_CANVAS: string = 'canvas'
export const SLASH_COMMAND_GOAL: string = 'goal'
export const SLASH_COMMAND_PLAN: string = 'plan'

export class SlashCommandItem {
  readonly id: string
  readonly name: string
  readonly skillId: string
  readonly skillName: string
  readonly description: string

  constructor(id: string, name: string = '/' + id, skillId: string = '', skillName: string = '', description: string = '') {
    this.id = id
    this.name = name
    this.skillId = skillId
    this.skillName = skillName
    this.description = description
  }
}

export interface SlashSkillInfo {
  id: string
  name: string
  description: string
}

const SKILL_PREFIX = '/skill:'

const SLASH_COMMANDS: SlashCommandItem[] = [
  new SlashCommandItem(SLASH_COMMAND_MODELS),
  new SlashCommandItem(SLASH_COMMAND_REASONING),
  new SlashCommandItem(SLASH_COMMAND_CANVAS),
  new SlashCommandItem(SLASH_COMMAND_PLAN),
  new SlashCommandItem(SLASH_COMMAND_GOAL),
  new SlashCommandItem(SLASH_COMMAND_COMPACT)
]

export function getSlashCommands(): SlashCommandItem[] {
  return SLASH_COMMANDS
}

export function buildSkillSlashCommands(skills: SlashSkillInfo[]): SlashCommandItem[] {
  const aliases = skills.map((skill: SlashSkillInfo): string =>
    skill.name.trim().replace(/[\s/#:\\\x00-\x1f\x7f]+/g, '-').replace(/^-+|-+$/g, ''))
  const counts = new Map<string, number>()
  for (const alias of aliases) {
    const key = alias.toLowerCase()
    counts.set(key, (counts.get(key) ?? 0) + 1)
  }
  return skills.map((skill: SlashSkillInfo, index: number): SlashCommandItem => {
    const alias = aliases[index]
    // 同名条目用持久化 ID 区分；用户仍能按原始名称搜索。
    const token = alias && counts.get(alias.toLowerCase()) === 1 ? alias : '#' + encodeURIComponent(skill.id)
    return new SlashCommandItem('skill:' + skill.id, SKILL_PREFIX + token, skill.id, skill.name, skill.description)
  })
}

// 只有整段输入是一个以 "/" 开头的单词时才算在输入命令；
// 正文里出现的斜杠（路径、日期、分数）不应该弹出命令面板。
export function isSlashCommandQuery(input: string): boolean {
  return /^\/[^\s/]*$/.test(input)
}

export function matchSlashCommands(input: string, skillCommands: SlashCommandItem[] = []): SlashCommandItem[] {
  if (!isSlashCommandQuery(input)) {
    return []
  }
  const prefix = input.toLowerCase()
  const builtins = SLASH_COMMANDS.filter((command: SlashCommandItem): boolean => command.name.startsWith(prefix))
  const query = prefix.startsWith(SKILL_PREFIX) ? prefix.slice(SKILL_PREFIX.length) : prefix.slice(1)
  const skills = skillCommands.filter((command: SlashCommandItem): boolean =>
    command.name.toLowerCase().startsWith(prefix) || command.skillName.toLowerCase().startsWith(query) ||
    command.name.slice(SKILL_PREFIX.length).toLowerCase().startsWith(query))
  return builtins.concat(skills)
}

// undefined 是普通消息，空串是已失效的显式 Skill 命令。仅解析消息开头的完整命令词。
export function resolveSlashSkillId(input: string, skills: SlashCommandItem[]): string | undefined {
  const token = input.trimStart().match(/^\/[^\s/]*(?=\s|$)/)?.[0]
  if (!token) return undefined
  const lower = token.toLowerCase()
  if (lower.startsWith(SKILL_PREFIX)) {
    if (token.charAt(SKILL_PREFIX.length) === '#') {
      const id = token.slice(SKILL_PREFIX.length + 1)
      return skills.find((skill: SlashCommandItem): boolean => encodeURIComponent(skill.skillId) === id)?.skillId ?? ''
    }
    return skills.find((skill: SlashCommandItem): boolean => skill.name.toLowerCase() === lower)?.skillId ?? ''
  }
  if (resolveSlashCommandId(token) !== '') return undefined
  return skills.find((skill: SlashCommandItem): boolean =>
    skill.name.slice(SKILL_PREFIX.length).toLowerCase() === lower.slice(1))?.skillId
}

export function buildRequiredSkillPrompt(id: string, language: PromptLanguage): string {
  if (!id) return ''
  const args = JSON.stringify({ skill_id: id, path: 'SKILL.md' })
  return pickPromptText(language,
    `用户为本轮明确指定了技能。回答前必须调用 use_skill，参数为 ${args}。按返回的技能说明完成任务，按需读取引用文件。如果读取失败，向用户说明原因。`,
    `The user explicitly selected a skill for this turn. Before answering, you must call use_skill with ${args}. Apply the returned instructions to the task and read referenced files as needed. If the skill cannot be read, tell the user why.`)
}

// 直接发送一个完整命令时按命令执行，而不是把命令原文当成消息发出去。
// 返回空串表示这段输入不是命令。
export function resolveSlashCommandId(input: string): string {
  const normalized = input.trim().toLowerCase()
  for (let i = 0; i < SLASH_COMMANDS.length; i++) {
    if (SLASH_COMMANDS[i].name === normalized) {
      return SLASH_COMMANDS[i].id
    }
  }
  return ''
}

// /goal 后允许跟随空格、换行和多行目标正文；/goalkeeper 等普通文本不能误判为命令。
export function isGoalSlashCommandInput(input: string): boolean {
  const normalized = input.trim()
  if (normalized.length < 5 || normalized.substring(0, 5).toLowerCase() !== '/goal') {
    return false
  }
  return normalized.length === 5 || /^\s$/.test(normalized.substring(5, 6))
}

export function resolveGoalSlashCommandText(input: string): string {
  if (!isGoalSlashCommandInput(input)) {
    return ''
  }
  return input.trim().substring(5).trim()
}

// 空的 /goal 有两种含义，取决于当前会话有没有目标：
// 已有目标时是"取消目标"，没有目标时只是把命令填回输入框等待用户写正文。
export const GOAL_COMMAND_ACTION_NONE: string = ''
export const GOAL_COMMAND_ACTION_SET: string = 'set'
export const GOAL_COMMAND_ACTION_CLEAR: string = 'clear'
export const GOAL_COMMAND_ACTION_PROMPT: string = 'prompt'

export function resolveGoalSlashCommandAction(input: string, currentGoal: string): string {
  if (!isGoalSlashCommandInput(input)) {
    return GOAL_COMMAND_ACTION_NONE
  }
  if (resolveGoalSlashCommandText(input) !== '') {
    return GOAL_COMMAND_ACTION_SET
  }
  return currentGoal.trim() !== '' ? GOAL_COMMAND_ACTION_CLEAR : GOAL_COMMAND_ACTION_PROMPT
}
