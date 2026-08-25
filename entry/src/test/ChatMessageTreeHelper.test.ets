import { describe, it, expect } from '@ohos/hypium'
import { ChatMessage, MessageRole } from '../main/ets/models/ChatModels'
import {
  buildLegacyChain,
  computeActivePath,
  resolveDisplayLeafId,
  shouldBuildLegacyChain
} from '../main/ets/pages/chat/ChatMessageTreeHelper'

function createTreeMessage(
  id: string,
  role: MessageRole,
  parentId: string,
  timestamp: number
): ChatMessage {
  const message = new ChatMessage(id, role, id)
  message.parentId = parentId
  message.timestamp = timestamp
  return message
}

export default function chatMessageTreeHelperTest() {
  describe('chatMessageTreeHelperTest', () => {
    it('preserves_root_message_versions_after_reload', 0, () => {
      const originalUser = createTreeMessage('user-1', MessageRole.USER, '', 1)
      const originalAssistant = createTreeMessage('assistant-1', MessageRole.ASSISTANT, 'user-1', 2)
      const editedUser = createTreeMessage('user-2', MessageRole.USER, '', 3)
      const editedAssistant = createTreeMessage('assistant-2', MessageRole.ASSISTANT, 'user-2', 4)
      const allMessages = [originalUser, originalAssistant, editedUser, editedAssistant]

      expect(shouldBuildLegacyChain(allMessages, editedAssistant.id)).assertEqual(false)

      const activePath = computeActivePath(allMessages, editedAssistant.id)
      expect(activePath.length).assertEqual(2)
      expect(activePath[0].id).assertEqual(editedUser.id)
      expect(activePath[1].id).assertEqual(editedAssistant.id)
      expect(activePath[0].versionIndex).assertEqual(1)
      expect(activePath[0].versionCount).assertEqual(2)
      expect(editedUser.parentId).assertEqual('')
    })

    it('builds_a_linear_chain_only_for_uninitialized_legacy_sessions', 0, () => {
      const user = createTreeMessage('legacy-user', MessageRole.USER, '', 1)
      const assistant = createTreeMessage('legacy-assistant', MessageRole.ASSISTANT, '', 2)
      const legacyMessages = [user, assistant]

      expect(shouldBuildLegacyChain(legacyMessages, '')).assertEqual(true)
      expect(shouldBuildLegacyChain(legacyMessages, 'missing-leaf')).assertEqual(false)

      const migration = buildLegacyChain(legacyMessages)
      expect(migration.leafId).assertEqual(assistant.id)
      expect(migration.fixes.length).assertEqual(1)
      expect(migration.fixes[0].messageId).assertEqual(assistant.id)
      expect(migration.fixes[0].parentId).assertEqual(user.id)
    })

    it('keeps_streaming_reply_on_the_active_path_after_returning_to_the_page', 0, () => {
      // 生成途中离开页面：用户消息已落库（activeLeafId 停在它上面），AI 回答还在流式生成
      const user = createTreeMessage('user-1', MessageRole.USER, '', 1)
      const streaming = createTreeMessage('assistant-1', MessageRole.ASSISTANT, 'user-1', 2)
      const allMessages = [user, streaming]

      expect(computeActivePath(allMessages, user.id).length).assertEqual(1)

      const displayLeafId = resolveDisplayLeafId(allMessages, user.id, [streaming.id])
      expect(displayLeafId).assertEqual(streaming.id)

      const activePath = computeActivePath(allMessages, displayLeafId)
      expect(activePath.length).assertEqual(2)
      expect(activePath[1].id).assertEqual(streaming.id)
    })

    it('ignores_pending_messages_that_hang_off_another_branch', 0, () => {
      const user = createTreeMessage('user-1', MessageRole.USER, '', 1)
      const otherUser = createTreeMessage('user-2', MessageRole.USER, '', 3)
      const otherStreaming = createTreeMessage('assistant-2', MessageRole.ASSISTANT, 'user-2', 4)
      const allMessages = [user, otherUser, otherStreaming]

      expect(resolveDisplayLeafId(allMessages, user.id, [otherStreaming.id])).assertEqual(user.id)
      expect(resolveDisplayLeafId(allMessages, user.id, ['missing-id'])).assertEqual(user.id)
      expect(resolveDisplayLeafId(allMessages, '', [otherStreaming.id])).assertEqual('')
    })

    it('picks_the_newest_pending_descendant_of_the_current_leaf', 0, () => {
      const user = createTreeMessage('user-1', MessageRole.USER, '', 1)
      const earlier = createTreeMessage('assistant-1', MessageRole.ASSISTANT, 'user-1', 2)
      const later = createTreeMessage('assistant-2', MessageRole.ASSISTANT, 'user-1', 5)
      const allMessages = [user, earlier, later]

      expect(resolveDisplayLeafId(allMessages, user.id, [earlier.id, later.id])).assertEqual(later.id)
      expect(resolveDisplayLeafId(allMessages, user.id, [later.id, earlier.id])).assertEqual(later.id)
    })
  })
}
