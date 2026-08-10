import { MessageAttachment, AttachmentType } from '../models/ChatModels'
import { BaseItemInfo, PhotoSource, RecentPhotoComponent, RecentPhotoOptions, photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { uiMaterial } from '@kit.ArkUI'
import { getAttachmentStorageService } from '../services/AttachmentStorageService'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { getAppUiState } from '../state/AppUiState'
import { VisualEffectsMode } from '../models/ThemeColors'

@ComponentV2
export struct ScreenshotBanner {
  @Param attachments: MessageAttachment[] = []
  @Event onAttachmentsChange: (value: MessageAttachment[]) => void = (_value: MessageAttachment[]): void => {}
  @Param hasRecentPhoto: boolean = false
  @Local dismissed: boolean = false
  @Local bannerHeight: number = 0
  private recentPhotoOptions: RecentPhotoOptions = new RecentPhotoOptions()
  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    this.recentPhotoOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
    this.recentPhotoOptions.period = 60
    this.recentPhotoOptions.photoSource = PhotoSource.SCREENSHOT

    // 检查是否在检测周期内已忽略过截图
    const dismissedTs = AppStorage.get<number>(AppStorageKeys.SCREENSHOT_DISMISSED_TS)
    const now = Date.now()
    if (dismissedTs !== undefined && (now - dismissedTs) < 60 * 1000) {
      this.dismissed = true
    }
  }

  build() {
    if (this.hasRecentPhoto && !this.dismissed) {
      Column() {
        Row() {
          Text($r('app.string.screenshot_banner_title'))
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)
          Blank()
          Button({ type: ButtonType.Circle, stateEffect: this.isManuscriptMode }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(9)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width(this.isManuscriptMode ? 44 : 20)
          .height(this.isManuscriptMode ? 44 : 20)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .borderRadius(this.isManuscriptMode ? 0 : 10)
          .border({ width: 0, color: Color.Transparent })
          .systemMaterial(this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
            materialColor: Color.Transparent,
            applyShadow: false,
            interactive: true,
            lightEffect: { color: undefined }
          }))
          .onClick(() => {
            this.dismiss()
          })
        }
        .width('100%')

        RecentPhotoComponent({
          recentPhotoOptions: this.recentPhotoOptions,
          onRecentPhotoClick: (info: BaseItemInfo): boolean => {
            if (info && info.uri) {
              this.addScreenshotByUri(info.uri)
            }
            return true
          },
          onRecentPhotoCheckResult: (_exists: boolean): void => {}
        })
          .width(48)
          .height(48)
          .borderRadius(12)
          .clip(true)
          .margin({ top: 8 })

        Text($r('app.string.screenshot_banner_subtitle'))
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 6 })
      }
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .width(140)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(Color.Transparent)
      .borderRadius(this.isManuscriptMode ? 0 : 14)
      .border({
        width: this.isManuscriptMode ? { top: 1, bottom: 1 } : 0,
        color: this.isManuscriptMode ? getAppUiState().themeDivider : this.themePrimary
      })
      .clip(false)
      .systemMaterial(this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        materialColor: Color.Transparent,
        applyShadow: false,
        interactive: false,
        lightEffect: { color: undefined }
      }))
      .shadow({
        radius: this.isManuscriptMode ? 0 : 20,
        color: this.isManuscriptMode ? Color.Transparent : 'rgba(0, 0, 0, 0.12)',
        offsetX: 0,
        offsetY: 6
      })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        let h = newArea.height
        if (typeof h === 'number') {
          this.bannerHeight = h
        }
      })
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.85, y: 0.85 }))
          .animation({ duration: 250, curve: Curve.EaseOut }),
        TransitionEffect.OPACITY.animation({ duration: 150 })
      ))
    }
  }

  private dismiss(): void {
    this.dismissed = true
    AppStorage.setOrCreate<number>(AppStorageKeys.SCREENSHOT_DISMISSED_TS, Date.now())
  }

  private async addScreenshotByUri(uri: string): Promise<void> {
    if (!uri) {
      return
    }
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      fileIo.closeSync(file)

      const base64Helper = new util.Base64Helper()
      const uint8Array = new Uint8Array(buffer)
      const base64Data = base64Helper.encodeToStringSync(uint8Array)

      const attachmentId = `img_${Date.now()}`
      const attachment = new MessageAttachment(
        attachmentId,
        AttachmentType.IMAGE,
        `screenshot_${Date.now()}.jpg`,
        '',
        'image/jpeg',
        stat.size
      )
      attachment.base64Data = base64Data

      const storageService = getAttachmentStorageService()
      const filePath = await storageService.saveAttachment(attachment)
      attachment.filePath = filePath

      this.onAttachmentsChange([...this.attachments, attachment])
      this.dismiss()
    } catch (error) {
      console.error('ScreenshotBanner', `Failed to add screenshot: ${JSON.stringify(error)}`)
    }
  }
}
