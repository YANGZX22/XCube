import { ChatMessage, MessageAttachment, ReasoningLevel } from '../../models/ChatModels'
import { ChatViewModel } from '../../viewmodels/ChatViewModel'
import { findMessageIndexById } from './ChatMessageActionHelper'

export interface ChatInlineEditFlowDependencies {
  chatViewModel: ChatViewModel
  getMessages: () => ChatMessage[]
  onValidateBeforeCommit: (
    content: string,
    attachments: MessageAttachment[],
    webSearchEnabled: boolean,
    selectedToolIds: string[],
    reasoningLevel: ReasoningLevel
  ) => boolean
  onSyncMessages: () => void
  // 把当前展示路径截断为指定的前缀消息（编辑时去掉被编辑消息及其后续，使新消息成为同级版本）
  onTruncateActivePath: (prefix: ChatMessage[]) => void
  onResetEditState: () => void
  onApplySavedDraft: (
    content: string,
    attachments: MessageAttachment[],
    webSearchEnabled: boolean,
    selectedToolIds: string[],
    reasoningLevel: ReasoningLevel
  ) => void
  onTriggerSend: (
    content: string,
    attachments: MessageAttachment[],
    webSearchEnabled: boolean,
    selectedToolIds: string[],
    reasoningLevel: ReasoningLevel
  ) => Promise<void>
  onShowToast: (message: string | Resource) => void
}

export class ChatInlineEditFlow {
  private deps: ChatInlineEditFlowDependencies

  constructor(deps: ChatInlineEditFlowDependencies) {
    this.deps = deps
  }

  async saveAndSendInline(
    editingMessageId: string,
    inputText: string,
    pendingAttachments: MessageAttachment[],
    editingWebSearchEnabled: boolean,
    editingSelectedToolIds: string[],
    editingReasoningLevel: ReasoningLevel
  ): Promise<void> {
    if (editingMessageId === '') {
      console.warn('ChatInlineEditFlow', '[saveAndSendInline] editingMessageId is empty')
      return
    }

    const messages = this.deps.getMessages()
    const messageIndex = findMessageIndexById(messages, editingMessageId)
    if (messageIndex < 0) {
      console.warn('ChatInlineEditFlow', '[saveAndSendInline] message not found:', editingMessageId)
      return
    }

    const hasContent = inputText.trim() !== ''
    const hasAttachments = pendingAttachments.length > 0
    if (!hasContent && !hasAttachments) {
      this.deps.onShowToast($r('app.string.message_content_empty'))
      return
    }

    try {
      const savedAttachments = this.deps.chatViewModel.cloneAttachmentsForNewMessage(pendingAttachments)
      const savedContent = inputText.trim()
      const savedWebSearchEnabled = editingWebSearchEnabled
      const savedToolIds = [...editingSelectedToolIds]
      const savedReasoningLevel = editingReasoningLevel

      // 在创建分支并发送之前，先复用正常发送链路做一次前置校验。
      // 失败时保留原消息和当前编辑态，避免“内容没了但也没发出去”的烂体验。
      const canCommit = this.deps.onValidateBeforeCommit(
        savedContent,
        savedAttachments,
        savedWebSearchEnabled,
        savedToolIds,
        savedReasoningLevel
      )
      if (!canCommit) {
        return
      }

      // 截断当前展示路径到被编辑消息之前：新消息将作为被编辑消息的同级版本，
      // 旧消息及其后续对话保留在对话树中，可通过 <n/n> 切回。
      const prefix = messages.slice(0, messageIndex)
      this.deps.onTruncateActivePath(prefix)
      this.deps.onSyncMessages()

      this.deps.onResetEditState()
      this.deps.onApplySavedDraft(
        savedContent,
        savedAttachments,
        savedWebSearchEnabled,
        savedToolIds,
        savedReasoningLevel
      )
      await this.deps.onTriggerSend(
        savedContent,
        savedAttachments,
        savedWebSearchEnabled,
        savedToolIds,
        savedReasoningLevel
      )
    } catch (error) {
      console.error('ChatInlineEditFlow', `[saveAndSendInline] Error: ${JSON.stringify(error)}`)
      this.deps.onShowToast($r('app.string.action_failed_retry'))
    }
  }
}
