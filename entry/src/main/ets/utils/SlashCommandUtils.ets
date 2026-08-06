// 输入框斜杠命令：在聊天输入框顶格输入 "/" 时弹出命令面板，点选后立即执行。
// 这里只放纯匹配逻辑，命令的实际执行由 ChatPage 负责。

export const SLASH_COMMAND_COMPACT: string = 'compact'

export class SlashCommandItem {
  id: string = ''
  // 展示与输入用的完整命令名，例如 "/compact"
  name: string = ''

  constructor(id: string) {
    this.id = id
    this.name = `/${id}`
  }
}

const SLASH_COMMANDS: SlashCommandItem[] = [
  new SlashCommandItem(SLASH_COMMAND_COMPACT)
]

export function getSlashCommands(): SlashCommandItem[] {
  return SLASH_COMMANDS
}

// 只有整段输入是一个以 "/" 开头的单词时才算在输入命令；
// 正文里出现的斜杠（路径、日期、分数）不应该弹出命令面板。
export function isSlashCommandQuery(input: string): boolean {
  return /^\/[a-zA-Z0-9_-]*$/.test(input)
}

export function matchSlashCommands(input: string): SlashCommandItem[] {
  if (!isSlashCommandQuery(input)) {
    return []
  }
  const prefix = input.toLowerCase()
  const matched: SlashCommandItem[] = []
  for (let i = 0; i < SLASH_COMMANDS.length; i++) {
    if (SLASH_COMMANDS[i].name.startsWith(prefix)) {
      matched.push(SLASH_COMMANDS[i])
    }
  }
  return matched
}

// 直接发送 "/compact" 时按命令执行，而不是把命令原文当成消息发出去。
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
