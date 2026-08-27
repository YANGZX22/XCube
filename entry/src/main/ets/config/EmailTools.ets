import {
  ToolConfig,
  ToolDefinition,
  ToolFunction,
  ToolParameters,
  ToolPermissionLevel,
  ToolSourceType
} from '../models/ChatModels'
import { EmailListRequest, EmailSendRequest } from '../models/EmailModels'
import { ToolExecutor } from '../services/ToolRegistry'
import { getEmailService } from '../services/EmailService'

export const EMAIL_READ_TOOL_ID: string = 'email_read'
export const EMAIL_SEND_TOOL_ID: string = 'email_send'

interface EmailReadArgs {
  action?: string
  uid?: string | number
  query?: string
  from?: string
  unread_only?: boolean
  unreadOnly?: boolean
  since_days?: number | string
  sinceDays?: number | string
  limit?: number | string
}

interface EmailSendArgs {
  to?: string | string[]
  cc?: string | string[]
  bcc?: string | string[]
  subject?: string
  body?: string
  reply_to?: string
  replyTo?: string
}

export class EmailReadExecutor implements ToolExecutor {
  async execute(argsJson: string): Promise<string> {
    let args: EmailReadArgs = {}
    try {
      args = JSON.parse(argsJson || '{}') as EmailReadArgs
    } catch (_error) {
      return JSON.stringify({ error: '邮件读取参数不是有效 JSON' })
    }
    const request = new EmailListRequest()
    request.query = args.query || ''
    request.from = args.from || ''
    request.unreadOnly = args.unread_only === true || args.unreadOnly === true
    request.sinceDays = this.numberValue(args.since_days, args.sinceDays, 30, 0, 3650)
    request.limit = this.numberValue(args.limit, undefined, 20, 1, 100)
    const action = (args.action || 'list').trim().toLowerCase()
    const uid = args.uid === undefined ? '' : `${args.uid}`
    if ((action === 'view' || action === 'read') && uid.trim() === '') {
      return JSON.stringify({ error: '查看邮件时必须提供 uid' })
    }
    try {
      return await getEmailService().readForTool(action, request, uid)
    } catch (error) {
      return JSON.stringify({ error: this.errorMessage(error) })
    }
  }

  private numberValue(primary: number | string | undefined, secondary: number | string | undefined,
    fallback: number, min: number, max: number): number {
    const value = primary !== undefined ? primary : secondary
    if (value === undefined) {
      return fallback
    }
    const parsed = Number(value)
    if (Number.isNaN(parsed)) {
      return fallback
    }
    return Math.min(Math.max(Math.floor(parsed), min), max)
  }

  private errorMessage(error: Object): string {
    return error instanceof Error && error.message.trim() !== '' ? error.message : '读取邮件失败'
  }
}

export class EmailSendExecutor implements ToolExecutor {
  async execute(argsJson: string): Promise<string> {
    let args: EmailSendArgs = {}
    try {
      args = JSON.parse(argsJson || '{}') as EmailSendArgs
    } catch (_error) {
      return JSON.stringify({ error: '发信参数不是有效 JSON' })
    }
    const request = new EmailSendRequest()
    request.to = this.addressList(args.to)
    request.cc = this.addressList(args.cc)
    request.bcc = this.addressList(args.bcc)
    request.subject = args.subject || ''
    request.body = args.body || ''
    request.replyTo = args.reply_to || args.replyTo || ''
    try {
      const result = await getEmailService().sendMessage(request)
      return JSON.stringify({ ok: result.ok, message: result.message, recipients: request.to })
    } catch (error) {
      return JSON.stringify({ error: this.errorMessage(error) })
    }
  }

  private addressList(value: string | string[] | undefined): string[] {
    if (value === undefined) {
      return []
    }
    if (Array.isArray(value)) {
      return value
    }
    const values = value.split(/[;,]/)
    const result: string[] = []
    for (let i = 0; i < values.length; i++) {
      const normalized = values[i].trim()
      if (normalized !== '') {
        result.push(normalized)
      }
    }
    return result
  }

  private errorMessage(error: Object): string {
    return error instanceof Error && error.message.trim() !== '' ? error.message : '发送邮件失败'
  }
}

export function createEmailReadToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(`{
    "type": "object",
    "properties": {
      "action": {
        "type": "string",
        "enum": ["list", "view"],
        "description": "list 按条件列出邮件摘要；view 按 uid 查看一封邮件的正文、附件清单及受支持附件的解析内容。"
      },
      "uid": {
        "type": "string",
        "description": "action=view 时必填，使用 list 返回的 uid。"
      },
      "query": {
        "type": "string",
        "description": "可选，搜索主题、正文等邮件文本。"
      },
      "from": {
        "type": "string",
        "description": "可选，按发件人筛选。"
      },
      "unread_only": {
        "type": "boolean",
        "description": "是否只查看未读邮件，默认 false。"
      },
      "since_days": {
        "type": "number",
        "description": "查看最近多少天，默认 30；传 0 表示不限制日期。"
      },
      "limit": {
        "type": "number",
        "description": "list 最多返回多少封，默认 20，最大 100。"
      }
    }
  }`) as object)
  return new ToolDefinition(new ToolFunction(
    EMAIL_READ_TOOL_ID,
    '读取已授权邮箱中的邮件，支持按时间、发件人、未读状态和文本筛选，也可按 uid 查看正文、附件清单及受支持附件的文本或 OCR 解析内容。邮件涉及隐私，每次执行前客户端都会展示参数并要求用户明确批准；不得尝试获取或输出邮箱密码、授权码。',
    parameters
  ))
}

export function createEmailSendToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(`{
    "type": "object",
    "properties": {
      "to": {
        "type": "array",
        "items": { "type": "string" },
        "description": "收件人邮箱数组，至少一项。"
      },
      "cc": {
        "type": "array",
        "items": { "type": "string" },
        "description": "可选，抄送邮箱数组。"
      },
      "bcc": {
        "type": "array",
        "items": { "type": "string" },
        "description": "可选，密送邮箱数组。"
      },
      "subject": {
        "type": "string",
        "description": "邮件主题，必填。"
      },
      "body": {
        "type": "string",
        "description": "纯文本邮件正文，必填。"
      },
      "reply_to": {
        "type": "string",
        "description": "可选，回复地址。"
      }
    },
    "required": ["to", "subject", "body"]
  }`) as object)
  return new ToolDefinition(new ToolFunction(
    EMAIL_SEND_TOOL_ID,
    '通过已授权邮箱发送邮件。只有当用户明确要求发送邮件，且收件人、主题和正文均已确定时才使用；缺少关键内容时先用 ask_user 确认。模型只提出调用，客户端会在真正发送前展示关键参数并要求用户批准。',
    parameters
  ))
}

export function createEmailReadToolConfig(): ToolConfig {
  return new ToolConfig(
    EMAIL_READ_TOOL_ID,
    '读取邮件',
    '模型可经逐次确认后查看已授权邮箱中的邮件',
    null,
    true,
    true,
    ToolSourceType.BUILTIN,
    'builtin',
    EMAIL_READ_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.WRITE
  )
}

export function createEmailSendToolConfig(): ToolConfig {
  return new ToolConfig(
    EMAIL_SEND_TOOL_ID,
    '发送邮件',
    '模型可经逐次确认后向指定邮箱发送邮件',
    null,
    true,
    true,
    ToolSourceType.BUILTIN,
    'builtin',
    EMAIL_SEND_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.WRITE
  )
}
