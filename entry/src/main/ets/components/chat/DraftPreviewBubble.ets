import { AttachmentType, MessageAttachment } from '../../models/ChatModels'
import { getAppUiState } from '../../state/AppUiState'
import { VisualEffectsMode } from '../../models/ThemeColors'
import { ImmersiveMaterialAnchor } from '../ImmersiveMaterialBackdrop'

@ComponentV2
export struct DraftPreviewBubble {
  @Param inputText: string = ''
  @Param pendingAttachments: MessageAttachment[] = []
  @Local bubbleWidthVp: number = 0
  @Local bubbleHeightVp: number = 0
  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }
  private get themeUserBubble(): string {
    return getAppUiState().themeUserBubble
  }
  private get themeUserBubbleText(): string {
    return getAppUiState().themeUserBubbleText
  }
  @Param chatFontSize: number = 15
  @Param previewTimeText: string = ''
  draftPreviewImageMaxHeight: number = 120
  draftPreviewImageContainerWidth: number = 180
  draftPreviewImageGap: number = 6

  private getDraftImageAttachmentIndices(): number[] {
    const imageIndices: number[] = []
    for (let i = 0; i < this.pendingAttachments.length; i++) {
      if (this.pendingAttachments[i].type === AttachmentType.IMAGE) {
        imageIndices.push(i)
      }
    }
    return imageIndices
  }

  private buildDraftImageGridRows(imageCount: number): number[] {
    const rows: number[] = []
    if (imageCount <= 0) {
      return rows
    }
    const rowCount = Math.ceil(imageCount / 2)
    for (let i = 0; i < rowCount; i++) {
      rows.push(i)
    }
    return rows
  }

  @Builder
  private DraftPreviewSingleImage(attachment: MessageAttachment, bottomMargin: number) {
    if (attachment.filePath !== '') {
      Image('file://' + attachment.filePath)
        .width(this.draftPreviewImageContainerWidth)
        .height(this.draftPreviewImageMaxHeight)
        .objectFit(ImageFit.Contain)
        .borderRadius(12)
        .clip(true)
        .margin({ bottom: bottomMargin })
    } else if (attachment.base64Data !== '') {
      Image(`data:${attachment.mimeType};base64,${attachment.base64Data}`)
        .width(this.draftPreviewImageContainerWidth)
        .height(this.draftPreviewImageMaxHeight)
        .objectFit(ImageFit.Contain)
        .borderRadius(12)
        .clip(true)
        .margin({ bottom: bottomMargin })
    }
  }

  @Builder
  private DraftPreviewGridImage(attachment: MessageAttachment) {
    if (attachment.filePath !== '') {
      Image('file://' + attachment.filePath)
        .width('100%')
        .height(this.draftPreviewImageMaxHeight)
        .objectFit(ImageFit.Contain)
        .borderRadius(12)
        .clip(true)
        .layoutWeight(1)
    } else if (attachment.base64Data !== '') {
      Image(`data:${attachment.mimeType};base64,${attachment.base64Data}`)
        .width('100%')
        .height(this.draftPreviewImageMaxHeight)
        .objectFit(ImageFit.Contain)
        .borderRadius(12)
        .clip(true)
        .layoutWeight(1)
    }
  }

  @Builder
  private DraftPreviewImages(draftImageIndices: number[]) {
    if (draftImageIndices.length === 1) {
      this.DraftPreviewSingleImage(this.pendingAttachments[draftImageIndices[0]], this.inputText.trim().length > 0 ? 6 : 0)
    } else if (draftImageIndices.length > 1) {
      Column({ space: this.draftPreviewImageGap }) {
        ForEach(this.buildDraftImageGridRows(draftImageIndices.length), (rowIndex: number) => {
          Row({ space: this.draftPreviewImageGap }) {
            this.DraftPreviewGridImage(this.pendingAttachments[draftImageIndices[rowIndex * 2]])

            if (rowIndex * 2 + 1 < draftImageIndices.length) {
              this.DraftPreviewGridImage(this.pendingAttachments[draftImageIndices[rowIndex * 2 + 1]])
            } else {
              Blank()
                .layoutWeight(1)
            }
          }
          .width(this.draftPreviewImageContainerWidth)
        }, (rowIndex: number) => rowIndex.toString())
      }
      .margin({ bottom: this.inputText.trim().length > 0 ? 6 : 0 })
    }
  }

  build() {
    Column() {
      Row() {
        Blank()

        Stack({ alignContent: Alignment.TopStart }) {
          if (!this.isManuscriptMode) {
            ImmersiveMaterialAnchor({
              surfaceWidth: this.bubbleWidthVp,
              surfaceHeight: this.bubbleHeightVp,
              cornerRadius: { topLeft: 20, topRight: 20, bottomLeft: 20, bottomRight: 6 }
            })
          }

          Column() {
            if (this.pendingAttachments.length > 0) {
              this.DraftPreviewImages(this.getDraftImageAttachmentIndices())
            }

            if (this.inputText.trim().length > 0) {
              Text(this.inputText.trim())
                .fontSize(this.chatFontSize)
                .fontColor(this.isManuscriptMode ? this.themeUserBubbleText : $r('app.color.text_primary'))
                .lineHeight(this.chatFontSize + 7)
            } else {
              Text($r('app.string.input_placeholder'))
                .fontSize(this.chatFontSize)
                .fontColor(this.isManuscriptMode ? this.themeUserBubbleText : $r('app.color.text_primary'))
                .opacity(0.45)
                .lineHeight(this.chatFontSize + 7)
            }
          }
          .padding(this.pendingAttachments.length > 0 ?
            {
              left: 8,
              right: 8,
              top: 8,
              bottom: 8
            } :
            {
              left: 14,
              right: 14,
              top: 10,
              bottom: 10
            })
          .backgroundColor(this.isManuscriptMode ? this.themeUserBubble : Color.Transparent)
          .borderRadius({
            topLeft: 20,
            topRight: 20,
            bottomLeft: 20,
            bottomRight: 6
          })
          .clip(true)
          .opacity(0.55)
          .onSizeChange((_oldSize: SizeOptions, size: SizeOptions) => {
            if (this.isManuscriptMode) {
              return
            }
            const width = Number(size.width)
            const height = Number(size.height)
            if (Number.isFinite(width) && width > 0 && Math.abs(width - this.bubbleWidthVp) > 0.1) {
              this.bubbleWidthVp = width
            }
            if (Number.isFinite(height) && height > 0 && Math.abs(height - this.bubbleHeightVp) > 0.1) {
              this.bubbleHeightVp = height
            }
          })
        }
        .constraintSize({ maxWidth: '75%' })
        .clip(false)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .alignItems(HorizontalAlign.End)
  }
}
