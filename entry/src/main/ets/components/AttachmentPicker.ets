import { SymbolGlyphModifier } from '@kit.ArkUI'
import { fileIo, picker } from '@kit.CoreFileKit'
import { camera, cameraPicker } from '@kit.CameraKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { MessageAttachment, AttachmentType } from '../models/ChatModels'
import { util } from '@kit.ArkTS'
import { getAttachmentStorageService } from '../services/AttachmentStorageService'
import { getAppUiState } from '../state/AppUiState'
import { ThinSelectModifier } from '../utils/WrappedMaterialSupport'

interface AttachmentMenuOption extends SelectOption {
  activate: () => Promise<void> | void
}

@ComponentV2
export struct AttachmentPicker {
  @Param isManuscript: boolean = false
  @Param pressedIconColor: ResourceColor = $r('app.color.text_secondary')
  @Event onSelectAttachments: (attachments: MessageAttachment[]) => void = () => {}
  @Event onVoiceInput: () => void = () => {}
  @Local pressed: boolean = false
  @Local selectedIndex: number = -1
  private picking: boolean = false
  private readonly options: AttachmentMenuOption[] = [
    {
      value: $r('app.string.chat_take_photo'),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.camera')),
      activate: (): Promise<void> => this.openCamera()
    },
    {
      value: $r('app.string.chat_pick_photos'),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.shutter_photo')),
      activate: (): Promise<void> => this.openPhotoPicker()
    },
    {
      value: $r('app.string.chat_upload_file'),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.paperclip')),
      activate: (): Promise<void> => this.openFilePicker()
    },
    {
      value: $r('app.string.voice_input'),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.mic')),
      activate: (): void => this.onVoiceInput()
    }
  ]

  private get buttonDiameter(): number {
    return this.isManuscript ? 44 : 40
  }

  private get iconColor(): ResourceColor {
    if (this.isManuscript) {
      return this.pressed ? this.pressedIconColor : getAppUiState().themeTextSecondary
    }
    return $r('app.color.text_secondary')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Select(this.options)
        .selected(this.selectedIndex!!)
        .value('')
        .font({ size: 0 })
        .arrowModifier(new SymbolGlyphModifier().fontColor([Color.Transparent]))
        .width('100%')
        .height('100%')
        .padding(0)
        .borderRadius(this.buttonDiameter / 2)
        .optionWidth(OptionWidthMode.FIT_CONTENT)
        .menuAlign(MenuAlignType.END)
        .attributeModifier(new ThinSelectModifier('plain'))
        .accessibilityText($r('app.string.chat_input_actions'))
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Down) this.pressed = true
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.pressed = false
        })
        .onSelect((index: number): void => {
          this.selectedIndex = -1
          this.activateOption(index)
        })

      // 加号独立居中，点击和键盘焦点交给下方的 Select。
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(this.isManuscript ? 18 : 20)
        .fontColor([this.iconColor])
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }
    .width(this.buttonDiameter)
    .height(this.buttonDiameter)
    .flexShrink(0)
    .borderRadius(this.buttonDiameter / 2)
    .clip(true)
  }

  private async activateOption(index: number): Promise<void> {
    const option = this.options[index]
    if (!option || this.picking) return
    this.picking = true
    try {
      await option.activate()
    } finally {
      this.picking = false
    }
  }

  // 打开相机拍照
  private async openCamera(): Promise<void> {
    try {
      // 使用 cameraPicker 拍照
      const pickerProfile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      }
      const context = this.getUIContext().getHostContext()
      if (context === undefined) {
        console.error('AttachmentPicker', 'Failed to get context')
        return
      }
      const pickerResult: cameraPicker.PickerResult = await cameraPicker.pick(
        context,
        [cameraPicker.PickerMediaType.PHOTO],
        pickerProfile
      )

      if (pickerResult.resultCode === 0 && pickerResult.resultUri !== '') {
        const attachment = await this.createAttachmentFromUri(pickerResult.resultUri, 'camera_photo.jpg')
        if (attachment !== null) {
          this.onSelectAttachments([attachment])
        }
      }
    } catch (error) {
      console.error('AttachmentPicker', `Failed to open camera: ${JSON.stringify(error)}`)
    }
  }

  // 打开照片选择器
  private async openPhotoPicker(): Promise<void> {
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      photoSelectOptions.maxSelectNumber = 5 // 最多选择5张图片

      const photoPicker = new photoAccessHelper.PhotoViewPicker()
      const photoSelectResult = await photoPicker.select(photoSelectOptions)

      if (photoSelectResult.photoUris.length > 0) {
        const attachments: MessageAttachment[] = []
        for (let i = 0; i < photoSelectResult.photoUris.length; i++) {
          const uri = photoSelectResult.photoUris[i]
          const fileName = `image_${i + 1}.jpg`
          const attachment = await this.createAttachmentFromUri(uri, fileName)
          if (attachment !== null) {
            attachments.push(attachment)
          }
        }
        if (attachments.length > 0) {
          this.onSelectAttachments(attachments)
        }
      }
    } catch (error) {
      console.error('AttachmentPicker', `Failed to open photo picker: ${JSON.stringify(error)}`)
    }
  }

  // 打开文件选择器
  private async openFilePicker(): Promise<void> {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions()
      documentSelectOptions.maxSelectNumber = 3
      documentSelectOptions.fileSuffixFilters = ['.pdf', '.doc', '.docx', '.xlsx', '.txt', '.md']

      const context = this.getUIContext().getHostContext()
      if (context === undefined) {
        console.error('AttachmentPicker', 'Failed to get context')
        return
      }
      const documentPicker = new picker.DocumentViewPicker(context)
      const documentSelectResult = await documentPicker.select(documentSelectOptions)

      if (documentSelectResult.length > 0) {
        const attachments: MessageAttachment[] = []
        for (let i = 0; i < documentSelectResult.length; i++) {
          const uri = documentSelectResult[i]
          const fileName = this.getFileNameFromUri(uri)
          const attachment = await this.createFileAttachment(uri, fileName)
          if (attachment !== null) {
            attachments.push(attachment)
          }
        }
        if (attachments.length > 0) {
          this.onSelectAttachments(attachments)
        }
      }
    } catch (error) {
      console.error('AttachmentPicker', `Failed to open file picker: ${JSON.stringify(error)}`)
    }
  }

  // 从 URI 创建图片附件（保存到应用目录）
  private async createAttachmentFromUri(uri: string, fileName: string): Promise<MessageAttachment | null> {
    try {
      console.info('AttachmentPicker', `Creating attachment from URI: ${uri}`)
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      fileIo.closeSync(file)
      console.info('AttachmentPicker', `Read file size: ${stat.size}`)

      // 转换为 Base64（用于发送 API 和保存文件）
      const base64Helper = new util.Base64Helper()
      const uint8Array = new Uint8Array(buffer)
      const base64Data = base64Helper.encodeToStringSync(uint8Array)
      console.info('AttachmentPicker', `Base64 data length: ${base64Data.length}`)

      // 创建附件对象
      const attachmentId = `img_${Date.now()}`
      const attachment = new MessageAttachment(
        attachmentId,
        AttachmentType.IMAGE,
        fileName,
        '', // filePath 稍后由存储服务设置
        'image/jpeg',
        stat.size
      )
      attachment.base64Data = base64Data

      // 保存到应用目录
      const storageService = getAttachmentStorageService()
      const filePath = await storageService.saveAttachment(attachment)
      console.info('AttachmentPicker', `Saved attachment to: ${filePath}`)
      attachment.filePath = filePath

      return attachment
    } catch (error) {
      console.error('AttachmentPicker', `Failed to create attachment: ${JSON.stringify(error)}`)
      return null
    }
  }

  // 从 URI 创建文件附件（保存到应用目录）
  private async createFileAttachment(uri: string, fileName: string): Promise<MessageAttachment | null> {
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(file.fd)
      const buffer = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buffer)
      fileIo.closeSync(file)

      // 转换为 Base64
      const base64Helper = new util.Base64Helper()
      const uint8Array = new Uint8Array(buffer)
      const base64Data = base64Helper.encodeToStringSync(uint8Array)

      const mimeType = this.getMimeType(fileName)
      const attachmentId = `file_${Date.now()}`
      const attachment = new MessageAttachment(
        attachmentId,
        AttachmentType.FILE,
        fileName,
        '', // filePath 稍后由存储服务设置
        mimeType,
        stat.size
      )
      attachment.base64Data = base64Data

      // 保存到应用目录
      const storageService = getAttachmentStorageService()
      const filePath = await storageService.saveAttachment(attachment)
      attachment.filePath = filePath

      return attachment
    } catch (error) {
      console.error('AttachmentPicker', `Failed to create file attachment: ${JSON.stringify(error)}`)
      return null
    }
  }

  // 从 URI 获取文件名
  private getFileNameFromUri(uri: string): string {
    const parts = uri.split('/')
    const encodedName = parts[parts.length - 1] || 'file'
    // 解码 URL 编码的中文文件名
    try {
      return decodeURIComponent(encodedName)
    } catch (e) {
      return encodedName
    }
  }

  // 根据文件扩展名获取 MIME 类型
  private getMimeType(fileName: string): string {
    const ext = fileName.split('.').pop()?.toLowerCase() || ''
    const mimeTypes: Record<string, string> = {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt': 'text/plain',
      'md': 'text/markdown',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp'
    }
    return mimeTypes[ext] || 'application/octet-stream'
  }
}
