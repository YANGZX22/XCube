import { ChatMessage, MessageRole } from '../models/ChatModels'

// 每条助手回复都有独立的用时和用量，包括相邻的同模型回复。
export function shouldShowMessageHeader(message: ChatMessage): boolean {
  return message.role === MessageRole.ASSISTANT
}
