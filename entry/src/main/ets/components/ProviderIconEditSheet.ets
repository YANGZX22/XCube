import { fileIo, fileUri } from '@kit.CoreFileKit'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { ModelProvider, ProviderIconType } from '../models/ChatModels'
import { ProviderIcon } from './ProviderIcon'
import {
  generateSoftColor,
  generateSoftColorFromString,
  getAllSoftColors,
  TRANSPARENT_BG_COLOR,
  extractInitials
} from '../utils/IconGeneratorUtils'
import { showToast } from '../utils/ToastUtil'
import { getAppUiState } from '../state/AppUiState'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'

const ICON_EDIT_MODE_TEXT: string = 'text'
const ICON_EDIT_MODE_GALLERY: string = 'gallery'
const ICON_EDIT_MODE_LINK: string = 'link'

const PROVIDER_ICON_DIR: string = 'provider_icons'

export interface ProviderIconEditConfig {
  iconType: string
  textIcon: string
  textIconBgColor: string
  customImagePath: string
}

function deriveInitialEditMode(iconType: string, customImagePath: string): string {
  if (iconType !== ProviderIconType.IMAGE || customImagePath === '') {
    return ICON_EDIT_MODE_TEXT
  }
  const lower = customImagePath.toLowerCase()
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return ICON_EDIT_MODE_LINK
  }
  return ICON_EDIT_MODE_GALLERY
}

@ComponentV2
export struct ProviderIconEditSheet {
  @Param provider: ModelProvider | null = null
  @Param initialIconType: string = ProviderIconType.TEXT
  @Param initialTextIcon: string = ''
  @Param initialTextIconBgColor: string = ''
  @Param initialCustomImagePath: string = ''
  @Event onSave: (config: ProviderIconEditConfig) => void = (_config: ProviderIconEditConfig) => {}
  @Event onResetToPreset: () => void = () => {}
  @Event onClose: () => void = () => {}

  @Local editMode: string = ICON_EDIT_MODE_TEXT
  @Local textValue: string = ''
  @Local bgColor: string = ''
  @Local galleryValue: string = ''
  @Local linkValue: string = ''
  @Local showColorPicker: boolean = false
  @Local isPickingImage: boolean = false

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    const fallbackName = this.provider !== null ? this.provider.name : ''
    this.editMode = deriveInitialEditMode(this.initialIconType, this.initialCustomImagePath)
    this.textValue = this.initialTextIcon !== '' ? this.initialTextIcon : extractInitials(fallbackName)
    this.bgColor = this.initialTextIconBgColor !== ''
      ? this.initialTextIconBgColor
      : generateSoftColorFromString(fallbackName)
    if (this.editMode === ICON_EDIT_MODE_GALLERY) {
      this.galleryValue = this.initialCustomImagePath
      this.linkValue = ''
    } else if (this.editMode === ICON_EDIT_MODE_LINK) {
      this.linkValue = this.initialCustomImagePath
      this.galleryValue = ''
    } else {
      this.galleryValue = ''
      this.linkValue = ''
    }
  }

  private showSheetToast(message: string | Resource, duration: number = 2000): void {
    showToast(this.getUIContext(), message, duration)
  }

  private hasPresetIconToReset(): boolean {
    // 预设服务商总是可以重置回默认图标（远程 logo 或预设文字）
    return this.provider !== null && this.provider.isPreset
  }

  private getPreviewIconType(): string {
    return this.editMode === ICON_EDIT_MODE_TEXT ? ProviderIconType.TEXT : ProviderIconType.IMAGE
  }

  private getPreviewCustomImagePath(): string {
    if (this.editMode === ICON_EDIT_MODE_GALLERY) {
      return this.galleryValue
    }
    if (this.editMode === ICON_EDIT_MODE_LINK) {
      return this.linkValue.trim()
    }
    return ''
  }

  private getFileExtension(uri: string): string {
    const cleanUri = uri.split('?')[0].toLowerCase()
    const dotIndex = cleanUri.lastIndexOf('.')
    if (dotIndex >= 0) {
      const ext = cleanUri.substring(dotIndex)
      if (ext === '.jpg' || ext === '.jpeg' || ext === '.png' || ext === '.webp' || ext === '.gif'
        || ext === '.bmp') {
        return ext
      }
    }
    return '.jpg'
  }

  private ensureProviderIconDirectory(baseDir: string): string {
    const dir = `${baseDir}/${PROVIDER_ICON_DIR}`
    try {
      fileIo.mkdirSync(dir, true)
    } catch (error) {
      console.error('ProviderIconEditSheet', `Failed to create icon dir: ${JSON.stringify(error)}`)
    }
    return dir
  }

  private async copyPickedImageToSandbox(uri: string): Promise<string> {
    const context = this.getUIContext().getHostContext()
    if (context === undefined) {
      return ''
    }
    const dir = this.ensureProviderIconDirectory(context.filesDir)
    const targetPath = `${dir}/icon_${Date.now()}_${Math.random().toString(36).substring(2, 8)}${this.getFileExtension(uri)}`
    try {
      const srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      try {
        const destFile = fileIo.openSync(targetPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        try {
          await fileIo.copyFile(srcFile.fd, destFile.fd)
        } finally {
          fileIo.closeSync(destFile)
        }
      } finally {
        fileIo.closeSync(srcFile)
      }
      return fileUri.getUriFromPath(targetPath)
    } catch (error) {
      console.error('ProviderIconEditSheet', `Failed to copy picked image: ${JSON.stringify(error)}`)
      return ''
    }
  }

  private async pickGalleryImage(): Promise<void> {
    if (this.isPickingImage) {
      return
    }
    this.isPickingImage = true
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions()
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      photoSelectOptions.maxSelectNumber = 1
      const photoPicker = new photoAccessHelper.PhotoViewPicker()
      const photoSelectResult = await photoPicker.select(photoSelectOptions)
      if (photoSelectResult.photoUris.length <= 0) {
        return
      }
      const imageUri = await this.copyPickedImageToSandbox(photoSelectResult.photoUris[0])
      if (imageUri !== '') {
        this.editMode = ICON_EDIT_MODE_GALLERY
        this.galleryValue = imageUri
      } else {
        this.showSheetToast($r('app.string.icon_gallery_pick_failed'))
      }
    } catch (error) {
      console.error('ProviderIconEditSheet', `Failed to pick gallery image: ${JSON.stringify(error)}`)
      this.showSheetToast($r('app.string.icon_gallery_pick_failed'))
    } finally {
      this.isPickingImage = false
    }
  }

  private resolveSaveConfig(): ProviderIconEditConfig {
    const fallbackName = this.provider !== null ? this.provider.name : ''
    if (this.editMode === ICON_EDIT_MODE_GALLERY && this.galleryValue !== '') {
      return {
        iconType: ProviderIconType.IMAGE,
        textIcon: this.textValue,
        textIconBgColor: this.bgColor,
        customImagePath: this.galleryValue
      }
    }
    if (this.editMode === ICON_EDIT_MODE_LINK && this.linkValue.trim() !== '') {
      return {
        iconType: ProviderIconType.IMAGE,
        textIcon: this.textValue,
        textIconBgColor: this.bgColor,
        customImagePath: this.linkValue.trim()
      }
    }
    const finalText = this.textValue !== '' ? this.textValue : extractInitials(fallbackName)
    return {
      iconType: ProviderIconType.TEXT,
      textIcon: finalText,
      textIconBgColor: this.bgColor,
      customImagePath: ''
    }
  }

  private confirmSave(): void {
    const config = this.resolveSaveConfig()
    this.onSave(config)
    this.onClose()
  }

  build() {
    Column() {
      ImmersiveSheetHeader({
        title: $r('app.string.icon_edit_title'),
        showTrailing: true,
        trailingColor: this.themePrimary,
        onLeadingClick: (): void => {
          this.onClose()
        },
        onTrailingClick: (): void => {
          this.confirmSave()
        }
      })

      Column({ space: 16 }) {
        ProviderIcon({
        iconType: this.getPreviewIconType(),
        iconPath: '',
        textIcon: this.textValue,
        textIconBgColor: this.bgColor,
        customImagePath: this.getPreviewCustomImagePath(),
        iconSize: 88,
        radius: 28,
        bgColor: getAppUiState().themeSurface,
        fallbackSymbol: $r('sys.symbol.cloud'),
        fallbackColor: $r('app.color.text_tertiary')
      })
        .alignSelf(ItemAlign.Center)
        .bindSheet($$this.showColorPicker, this.ColorPickerSheet(), {
          height: 400,
          showClose: false,
          onDisappear: () => {
            this.showColorPicker = false
          }
        })

      Row({ space: 8 }) {
        this.SourceButton(ICON_EDIT_MODE_TEXT, $r('app.string.icon_source_text'))
        this.SourceButton(ICON_EDIT_MODE_GALLERY, $r('app.string.icon_source_gallery'))
        this.SourceButton(ICON_EDIT_MODE_LINK, $r('app.string.icon_source_link'))
      }
      .width('100%')

      if (this.editMode === ICON_EDIT_MODE_TEXT) {
        this.TextModeContent()
      } else if (this.editMode === ICON_EDIT_MODE_GALLERY) {
        this.GalleryModeContent()
      } else {
        this.LinkModeContent()
      }

      if (this.hasPresetIconToReset()) {
        Button($r('app.string.icon_reset_button'))
          .width('100%')
          .height(44)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor(getAppUiState().themeSurface)
          .borderRadius(16)
          .onClick(() => {
            this.onResetToPreset()
          })
      }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 28 })
    }
    .width('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  @Builder
  private SourceButton(mode: string, label: ResourceStr) {
    Button(label)
      .layoutWeight(1)
      .height(38)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.editMode === mode ? Color.White : $r('app.color.text_secondary'))
      .backgroundColor(this.editMode === mode ? this.themePrimary : getAppUiState().themeSurface)
      .borderRadius(19)
      .border({
        width: this.editMode === mode ? 0 : 1,
        color: $r('app.color.divider')
      })
      .onClick(() => {
        if (this.editMode === mode) {
          return
        }
        this.editMode = mode
        if (mode === ICON_EDIT_MODE_TEXT && this.textValue === '') {
          const fallbackName = this.provider !== null ? this.provider.name : ''
          this.textValue = extractInitials(fallbackName)
        }
      })
  }

  @Builder
  private TextModeContent() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Text($r('app.string.icon_text_input_label'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        TextInput({ text: this.textValue })
          .width('100%')
          .height(46)
          .maxLength(2)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor(getAppUiState().themeSurface)
          .borderRadius(16)
          .padding({ left: 14, right: 14 })
          .onChange((text: string) => {
            this.textValue = text
          })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      this.BackgroundColorRow()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private GalleryModeContent() {
    Column({ space: 10 }) {
      Text($r('app.string.icon_gallery_hint'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Button(this.isPickingImage ? $r('app.string.loading') : $r('app.string.icon_pick_gallery'))
        .width('100%')
        .height(46)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor(this.themePrimary)
        .borderRadius(18)
        .enabled(!this.isPickingImage)
        .onClick(() => {
          this.pickGalleryImage()
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private LinkModeContent() {
    Column({ space: 10 }) {
      Text($r('app.string.icon_link_hint'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Text($r('app.string.icon_link_label'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ text: this.linkValue, placeholder: $r('app.string.icon_link_placeholder') })
        .width('100%')
        .height(46)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor(getAppUiState().themeSurface)
        .borderRadius(16)
        .padding({ left: 14, right: 14 })
        .onChange((text: string) => {
          this.linkValue = text
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private BackgroundColorRow() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.icon_background_color'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Button($r('app.string.icon_random_generate'))
          .fontSize(12)
          .type(ButtonType.Normal)
          .borderRadius(8)
          .backgroundColor(getAppUiState().themeSurface)
          .fontColor($r('app.color.text_primary'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .onClick(() => {
            this.bgColor = generateSoftColor()
          })
      }
      .width('100%')

      Row({ space: 12 }) {
        if (this.bgColor === TRANSPARENT_BG_COLOR) {
          Column() {
            Text($r('app.string.icon_none'))
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width(40)
          .height(40)
          .borderRadius(10)
          .border({ width: 1, color: $r('app.color.divider') })
          .justifyContent(FlexAlign.Center)
        } else {
          Column()
            .width(40)
            .height(40)
            .backgroundColor(this.bgColor)
            .borderRadius(10)
            .border({ width: 1, color: $r('app.color.divider') })
        }

        Text(this.bgColor === TRANSPARENT_BG_COLOR ? $r('app.string.icon_transparent_hint') : this.bgColor)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)

        Button($r('app.string.icon_select_color'))
          .fontSize(12)
          .type(ButtonType.Normal)
          .borderRadius(8)
          .backgroundColor(getAppUiState().themeSurface)
          .fontColor($r('app.color.text_primary'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .onClick(() => {
            this.showColorPicker = true
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private ColorPickerSheet() {
    Column() {
      ImmersiveSheetHeader({
        title: $r('app.string.icon_color_picker_title'),
        onLeadingClick: (): void => {
          this.showColorPicker = false
        }
      })

      Column({ space: 16 }) {

      Row() {
        Column() {
          Text($r('app.string.icon_none'))
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width(50)
        .height(50)
        .borderRadius(10)
        .border({
          width: this.bgColor === TRANSPARENT_BG_COLOR ? 3 : 1,
          color: this.bgColor === TRANSPARENT_BG_COLOR ? this.themePrimary : $r('app.color.divider')
        })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.bgColor = TRANSPARENT_BG_COLOR
          this.showColorPicker = false
        })

        Text($r('app.string.icon_transparent_hint'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 12 })
      }
      .width('100%')
      .padding({ bottom: 8 })

      Divider().color($r('app.color.divider'))

      Scroll() {
        Grid() {
          ForEach(getAllSoftColors(), (color: string) => {
            GridItem() {
              Column()
                .width(50)
                .height(50)
                .backgroundColor(color)
                .borderRadius(10)
                .border({
                  width: this.bgColor === color ? 3 : 1,
                  color: this.bgColor === color ? this.themePrimary : $r('app.color.divider')
                })
                .onClick(() => {
                  this.bgColor = color
                  this.showColorPicker = false
                })
            }
          })
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(12)
        .columnsGap(12)
        .width('100%')
      }
      .width('100%')
      .height(250)
      .scrollBar(BarState.Off)
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 20 })
    }
    .width('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }
}
