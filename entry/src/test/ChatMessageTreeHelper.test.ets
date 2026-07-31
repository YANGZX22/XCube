import { describe, it, expect } from '@ohos/hypium'
import { ChatMessage, MessageRole } from '../main/ets/models/ChatModels'
import {
  buildLegacyChain,
  computeActivePath,
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
  })
}
