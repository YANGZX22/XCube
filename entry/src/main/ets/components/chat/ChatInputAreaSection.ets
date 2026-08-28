import { MessageAttachment, ReasoningLevel } from '../../models/ChatModels'
import { ChatToolbar } from '../ChatToolbar'
import { ChatInputBar } from '../ChatInputBar'
import { ScreenshotBanner } from '../ScreenshotBanner'
import { AttachmentPicker } from '../AttachmentPicker'
import { SlashCommandPanel } from './SlashCommandPanel'
import { ReasoningControlMode } from '../../services/ProviderCompatibilityRegistry'
import { matchSlashCommands, SlashCommandItem } from '../../utils/SlashCommandUtils'
import { getAppUiState } from '../../state/AppUiState'
import { VisualEffectsMode } from '../../models/ThemeColors'

@ComponentV2
export struct ChatInputAreaSection {
  @Param inputText: string = ''
  @Event onInputTextChange: (value: string) => void = (_value: string): void => {}
  @Param attachments: MessageAttachment[] = []
  @Event onAttachmentsChange: (value: MessageAttachment[]) => void = (_value: MessageAttachment[]): void => {}
  @Param isSending: boolean = false
  @Param isSendDispatching: boolean = false
  @Param inFlightSendMenuAvailable: boolean = false
  @Param queuedMessageCount: number = 0
  @Param isAwaitingResponse: boolean = false
  @Param currentModelId: string = ''
  @Param currentProviderId: string = ''
  @Param currentModelName: string = ''
  @Param currentConversationGoal: string = ''
  @Param currentProviderIconType: string = ''
  @Param currentProviderIconPath: string = ''
  @Param currentProviderTextIcon: string = ''
  @Param currentProviderTextIconBgColor: string = ''
  @Param currentProviderCustomImagePath: string = ''
  @Param currentProviderBrandColor: ResourceColor = ''
  @Param autoFocus: boolean = false
  @Param isEditing: boolean = false
  @Param toolSelectionAvailable: boolean = false
  @Param hasSelectedTools: boolean = false
  @Event onOpenTools: () => void = (): void => {}
  @Param reasoningAvailable: boolean = false
  @Param reasoningControlMode: ReasoningControlMode = ReasoningControlMode.NONE
  @Param reasoningXhighAvailable: boolean = false
  @Param reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  @Param reasoningPanelOpenRequestTick: number = 0
  @Event onReasoningLevelChange: (value: ReasoningLevel) => void =
    (_value: ReasoningLevel): void => {}
  @Param knowledgeEnabled: boolean = false
  @Param knowledgeAvailable: boolean = false
  @Event onKnowledgeToggle: (enabled: boolean) => void =
    (_enabled: boolean): void => {}
  @Param hasRecentScreenshot: boolean = false
  @Param bottomAvoidHeight: number = 0
  @Param contentMaxWidth: number = 99999
  @Event onCancelEdit: () => void = () => {}
  @Event onSend: () => void = () => {}
  @Event onStop: () => void = () => {}
  @Event onQueueSend: () => void = () => {}
  @Event onSteerSend: () => void = () => {}
  @Event onModelIconClick: () => void = () => {}
  @Param isAttachmentPanelOpen: boolean = false
  @Event onAttachmentClick: () => void = () => {}
  @Event onSelectAttachments: (attachments: MessageAttachment[]) => void =
    (_attachments: MessageAttachment[]): void => {}
  @Event onCloseAttachmentPicker: () => void = (): void => {}
  @Event onVoiceInput: () => void = (): void => {}
  @Event onInputFocus: () => void = () => {}
  @Event onInputBlur: () => void = () => {}
  @Event onComposerContentChanged: () => void = () => {}
  @Event onRecentPhotoDetected: (detected: boolean) => void = (_detected: boolean): void => {}
  @Event onSlashCommand: (commandId: string) => void = (_commandId: string): void => {}
  @Param showManuscriptScrollTop: boolean = false
  @Param showManuscriptScrollBottom: boolean = false
  @Param manuscriptScrollBottomLoading: boolean = false
  @Param showManuscriptHistory: boolean = false
  @Param showManuscriptCanvas: boolean = false
  @Param showManuscriptPlan: boolean = false
  @Event onManuscriptScrollTop: () => void = () => {}
  @Event onManuscriptScrollBottom: () => void = () => {}
  @Event onManuscriptHistory: () => void = () => {}
  @Event onManuscriptCanvas: () => void = () => {}
  @Event onOpenWorkspace: () => void = () => {}
  @Event onManuscriptPlan: () => void = () => {}

  private getEffectiveContentMaxWidth(): number {
    return this.contentMaxWidth > 0 ? this.contentMaxWidth : 99999
  }

  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  // 编辑既有消息时不接受斜杠命令：那次输入的目标是改写消息本身
  private getVisibleSlashCommands(): SlashCommandItem[] {
    if (this.isEditing) {
      return []
    }
    return matchSlashCommands(this.inputText)
  }

  private getBottomSpacerHeight(): number {
    return this.bottomAvoidHeight + 4
  }

  build() {
    Column() {
      Column() {
        Row() {
          ScreenshotBanner({
            attachments: this.attachments,
            hasRecentPhoto: this.hasRecentScreenshot,
            onAttachmentsChange: (value: MessageAttachment[]): void => {
              this.onAttachmentsChange(value)
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ bottom: 8 })

        if (this.getVisibleSlashCommands().length > 0) {
          SlashCommandPanel({
            commands: this.getVisibleSlashCommands(),
            currentModelId: this.currentModelId,
            currentProviderId: this.currentProviderId,
            currentModelName: this.currentModelName,
            currentConversationGoal: this.currentConversationGoal,
            onSelectCommand: (commandId: string): void => {
              this.onSlashCommand(commandId)
            }
          })
        }

        ChatToolbar({
          toolSelectionAvailable: this.toolSelectionAvailable,
          hasSelectedTools: this.hasSelectedTools,
          onOpenTools: (): void => {
            this.onOpenTools()
          },
          reasoningAvailable: this.reasoningAvailable,
          reasoningControlMode: this.reasoningControlMode,
          reasoningXhighAvailable: this.reasoningXhighAvailable,
          reasoningLevel: this.reasoningLevel,
          reasoningPanelOpenRequestTick: this.reasoningPanelOpenRequestTick,
          onReasoningLevelChange: (value: ReasoningLevel): void => {
            this.onReasoningLevelChange(value)
          },
          knowledgeEnabled: this.knowledgeEnabled,
          knowledgeAvailable: this.knowledgeAvailable,
          onKnowledgeToggle: (enabled: boolean): void => {
            this.onKnowledgeToggle(enabled)
          },
          showScrollTopAction: this.showManuscriptScrollTop,
          showScrollBottomAction: this.showManuscriptScrollBottom,
          scrollBottomActionLoading: this.manuscriptScrollBottomLoading,
          showHistoryAction: this.showManuscriptHistory,
          showCanvasAction: this.showManuscriptCanvas,
          showPlanAction: this.showManuscriptPlan,
          onScrollTopAction: (): void => {
            this.onManuscriptScrollTop()
          },
          onScrollBottomAction: (): void => {
            this.onManuscriptScrollBottom()
          },
          onHistoryAction: (): void => {
            this.onManuscriptHistory()
          },
          onCanvasAction: (): void => {
            this.onManuscriptCanvas()
          },
          onOpenWorkspace: (): void => {
            this.onOpenWorkspace()
          },
          onPlanAction: (): void => {
            this.onManuscriptPlan()
          }
        })

        ChatInputBar({
          isAttachmentPanelOpen: this.isAttachmentPanelOpen,
          inputText: this.inputText,
          onInputTextChange: (value: string): void => {
            this.onInputTextChange(value)
          },
          attachments: this.attachments,
          onAttachmentsChange: (value: MessageAttachment[]): void => {
            this.onAttachmentsChange(value)
          },
          isSending: this.isSending,
          isSendDispatching: this.isSendDispatching,
          inFlightSendMenuAvailable: this.inFlightSendMenuAvailable,
          queuedMessageCount: this.queuedMessageCount,
          isAwaitingResponse: this.isAwaitingResponse,
          currentModelId: this.currentModelId,
          currentProviderId: this.currentProviderId,
          currentModelName: this.currentModelName,
          currentProviderIconType: this.currentProviderIconType,
          currentProviderIconPath: this.currentProviderIconPath,
          currentProviderTextIcon: this.currentProviderTextIcon,
          currentProviderTextIconBgColor: this.currentProviderTextIconBgColor,
          currentProviderCustomImagePath: this.currentProviderCustomImagePath,
          currentProviderBrandColor: this.currentProviderBrandColor,
          autoFocus: this.autoFocus,
          isEditing: this.isEditing,
          onCancelEdit: (): void => {
            this.onCancelEdit()
          },
          onSend: (): void => {
            this.onSend()
          },
          onStop: (): void => {
            this.onStop()
          },
          onQueueSend: (): void => {
            this.onQueueSend()
          },
          onSteerSend: (): void => {
            this.onSteerSend()
          },
          onModelIconClick: (): void => {
            this.onModelIconClick()
          },
          onAttachmentClick: (): void => {
            this.onAttachmentClick()
          },
          onInputFocus: (): void => {
            this.onInputFocus()
          },
          onInputBlur: (): void => {
            this.onInputBlur()
          },
          onComposerContentChanged: (): void => {
            this.onComposerContentChanged()
          },
          onRecentPhotoDetected: (detected: boolean): void => {
            this.onRecentPhotoDetected(detected)
          },
          showManuscriptScrollTop: this.showManuscriptScrollTop,
          showManuscriptScrollBottom: this.showManuscriptScrollBottom,
          manuscriptScrollBottomLoading: this.manuscriptScrollBottomLoading,
          showManuscriptHistory: this.showManuscriptHistory,
          showManuscriptCanvas: this.showManuscriptCanvas,
          showManuscriptPlan: this.showManuscriptPlan,
          onManuscriptScrollTop: (): void => {
            this.onManuscriptScrollTop()
          },
          onManuscriptScrollBottom: (): void => {
            this.onManuscriptScrollBottom()
          },
          onManuscriptHistory: (): void => {
            this.onManuscriptHistory()
          },
          onManuscriptPlan: (): void => {
            this.onManuscriptPlan()
          },
          onManuscriptCanvas: (): void => {
            this.onManuscriptCanvas()
          }
        })

        Column() {
          AttachmentPicker({
            showDragBar: false,
            onSelectAttachments: (attachments: MessageAttachment[]): void => {
              this.onSelectAttachments(attachments)
            },
            onClose: (): void => {
              this.onCloseAttachmentPicker()
            },
            onVoiceInput: (): void => {
              this.onVoiceInput()
            }
          })
        }
        .width('100%')
        .height(this.isAttachmentPanelOpen ? 84 : 0)
        .opacity(this.isAttachmentPanelOpen ? 1 : 0)
        .clip(false)
        .enabled(this.isAttachmentPanelOpen)
        .animation({
          duration: this.isAttachmentPanelOpen ? 260 : 200,
          curve: Curve.FastOutSlowIn
        })

        Column()
          .width('100%')
          .height(this.getBottomSpacerHeight())
      }
      .width('100%')
      .constraintSize({ maxWidth: this.getEffectiveContentMaxWidth() })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(this.isManuscriptMode ? { left: 20, right: 20, top: 14 } : { left: 16, right: 16, top: 6 })
    .backgroundColor(this.isManuscriptMode ? getAppUiState().themeBackground : Color.Transparent)
    .border({
      width: this.isManuscriptMode ? { top: 1 } : 0,
      color: getAppUiState().themeDivider
    })
    .translate({ y: this.isManuscriptMode ? 20 : 0 })
  }
}
