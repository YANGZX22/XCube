import { ChatTaskStatus } from '../../models/ChatTaskModels'
import {
  parseInAppTaskAlertPayload,
  parseOpenSessionPayload
} from '../../utils/TaskAlertUtils'

export interface ChatTaskAlertFlowDependencies {
  getCurrentSessionId: () => string
  getLastHandledAlertTimestamp: () => number
  onSetLastHandledAlertTimestamp: (value: number) => void
  onNavigateToSession: (sessionId: string) => void
  onClearOpenSessionPayloadStorage: () => void
  onClearInAppTaskAlertPayloadStorage: () => void
  onShowTaskAlert: (message: string, failed: boolean, sessionId: string) => void
}

export class ChatTaskAlertFlow {
  private deps: ChatTaskAlertFlowDependencies

  constructor(deps: ChatTaskAlertFlowDependencies) {
    this.deps = deps
  }

  handleOpenSessionPayload(payloadText: string): void {
    if (payloadText === '') {
      return
    }

    const payload = parseOpenSessionPayload(payloadText)
    if (payload === null) {
      console.error('ChatTaskAlertFlow', 'Failed to parse openSession payload')
      return
    }

    const currentSessionId = this.deps.getCurrentSessionId()
    if (payload.sessionId === currentSessionId) {
      this.deps.onClearOpenSessionPayloadStorage()
      return
    }

    this.deps.onNavigateToSession(payload.sessionId)
    this.deps.onClearOpenSessionPayloadStorage()
  }

  handleInAppTaskAlertPayload(payloadText: string): void {
    if (payloadText === '') {
      return
    }

    const payload = parseInAppTaskAlertPayload(payloadText)
    if (payload === null) {
      console.error('ChatTaskAlertFlow', 'Failed to parse in-app alert payload')
      return
    }

    if (payload.timestamp <= this.deps.getLastHandledAlertTimestamp()) {
      return
    }

    const currentSessionId = this.deps.getCurrentSessionId()
    if (payload.sessionId === currentSessionId) {
      this.deps.onClearInAppTaskAlertPayloadStorage()
      return
    }

    this.deps.onSetLastHandledAlertTimestamp(payload.timestamp)

    this.deps.onShowTaskAlert(
      payload.message,
      payload.status === ChatTaskStatus.FAILED,
      payload.sessionId
    )
    this.deps.onClearInAppTaskAlertPayloadStorage()
  }
}
