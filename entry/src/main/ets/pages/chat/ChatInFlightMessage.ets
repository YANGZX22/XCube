import { MessageAttachment } from '../../models/ChatModels'
import { ReplyAnnotation } from '../../models/ReplyAnnotation'

export enum InFlightMessageDelivery {
  STEER = 'steer',
  QUEUE = 'queue'
}

export class ChatInFlightMessage {
  content: string
  attachments: MessageAttachment[]
  replyAnnotations: ReplyAnnotation[]
  delivery: InFlightMessageDelivery
  sessionId: string
  requiredSkillId: string = ''

  constructor(
    content: string,
    attachments: MessageAttachment[] = [],
    delivery: InFlightMessageDelivery = InFlightMessageDelivery.QUEUE,
    sessionId: string = '',
    replyAnnotations: ReplyAnnotation[] = []
  ) {
    this.content = content.trim()
    this.attachments = attachments.slice()
    this.replyAnnotations = replyAnnotations.slice()
    this.delivery = delivery
    this.sessionId = sessionId
  }

  hasPayload(): boolean {
    return this.content !== '' || this.attachments.length > 0 || this.replyAnnotations.length > 0
  }
}

export function buildSteeringTimelineText(content: string, attachments: MessageAttachment[]): string {
  const normalized = content.trim()
  if (attachments.length === 0) {
    return normalized
  }
  const names: string[] = []
  for (let i = 0; i < attachments.length; i++) {
    names.push(attachments[i].name)
  }
  const attachmentLine = `Attachments: ${names.join(', ')}`
  return normalized === '' ? attachmentLine : `${normalized}\n${attachmentLine}`
}

export function buildSteeringRequestContent(content: string): string {
  const normalized = content.trim()
  return `[User guidance received while this answer was in progress]\n${normalized}\n\n` +
    'Continue the current task with this guidance. Do not repeat completed work or explain the delivery mechanism.'
}
