import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { fileIo, fileUri } from '@kit.CoreFileKit'
import { buffer } from '@kit.ArkTS'
import { common } from '@kit.AbilityKit'
import { showToast } from '../utils/ToastUtil'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { uiMaterial } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'

/**
 * 图片预览组件
 * 支持：全屏查看、双指缩放、双击缩放、Swiper 多图滑动切换、下拉关闭
 *
 * 架构：使用 Swiper 原生处理水平滑动切换，手势绑定在根 Stack 上处理缩放/拖拽/点击。
 * 不能在 bindContentCover 内使用（模态层会拦截连续手势），
 * 应作为条件渲染的全屏覆盖层直接嵌入页面 Stack 中。
 * 需在宿主页面的 onBackPress() 中拦截返回键。
 *
 * 手势架构（绑定在根 Stack 上，子组件按钮优先）：
 * .parallelGesture(PinchGesture)  → 双指缩放，始终可用，与其他手势并行
 * .gesture(Exclusive: PanGesture | TapGesture)  → 拖动和点击互斥
 *   PanGesture：放大时全向拖动，未放大时仅处理垂直下拉关闭
 *   TapGesture：单击关闭，双击缩放
 */

@ComponentV2
export struct ImagePreview {
  @Param images: Array<string> = []
  @Param currentIndex: number = 0
  @Param topSafeAreaVp: number = 0
  @Param bottomSafeAreaVp: number = 0
  @Event onClose: () => void = () => {}

  // 缩放状态
  @Local imageScale: number = 1
  @Local lastImageScale: number = 1

  // 位移状态
  @Local offsetX: number = 0
  @Local offsetY: number = 0
  @Local lastOffsetX: number = 0
  @Local lastOffsetY: number = 0

  // 当前显示图片索引
  @Local displayIndex: number = 0

  // 背景透明度（下拉退出时渐变）
  @Local backgroundOpacity: number = 1

  // 下拉关闭时的缩放（"抽离"效果）
  @Local dragScale: number = 1

  // 是否正在执行关闭动画（防止重复触发）
  @Local isDismissing: boolean = false

  // 保存状态
  @Local isSaving: boolean = false

  // 拖动方向锁定
  private panDirection: string = 'none'
  private readonly overlayHorizontalMarginVp: number = 16
  private readonly overlayBottomMarginVp: number = 20
  private readonly overlayTopMarginVp: number = 22
  private readonly saveButtonWidthVp: number = 104
  private readonly saveButtonHeightVp: number = 48

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }

  aboutToAppear(): void {
    this.displayIndex = this.currentIndex
  }

  /**
   * 统一关闭入口：淡出遮罩后关闭。
   * 状态栏由宿主 ChatPage 统一管理，本组件不介入。
   */
  private dismiss(): void {
    if (this.isDismissing) return
    this.isDismissing = true
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.backgroundOpacity = 0
    })
    setTimeout(() => this.onClose(), 210)
  }

  private showImageToast(message: string | Resource, duration: number = 2000): void {
    showToast(this.getUIContext(), message, duration)
  }

  private getOverlayControlMaterial(interactive: boolean): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: this.themePrimaryLight,
      interactive: interactive,
      lightEffect: { color: undefined }
    })
  }

  private getSaveButtonTranslateX(): number {
    return -(this.saveButtonWidthVp + this.overlayHorizontalMarginVp)
  }

  private getSaveButtonTranslateY(): number {
    return -(this.saveButtonHeightVp + this.overlayBottomMarginVp + this.bottomSafeAreaVp)
  }

  private getIndicatorTranslateY(): number {
    return -(this.saveButtonHeightVp + this.overlayBottomMarginVp + this.bottomSafeAreaVp + 28)
  }

  @Builder
  private SaveActionButtonBuilder() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 8 }) {
        if (this.isSaving) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.themePrimary)
        } else {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
              .fontSize(16)
              .fontColor([this.themePrimary])
          }
          .width(28)
          .height(28)
        }

        Text($r('app.string.save'))
          .fontSize(14)
          .fontColor(this.themePrimary)
          .fontWeight(FontWeight.Medium)
      }
      .width(this.saveButtonWidthVp)
      .height(this.saveButtonHeightVp)
      .padding({ left: 12, right: 14 })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width(this.saveButtonWidthVp)
    .height(this.saveButtonHeightVp)
    .padding(0)
    .backgroundColor(this.themePrimaryLight)
    .borderRadius(this.saveButtonHeightVp / 2)
    .systemMaterial(this.getOverlayControlMaterial(true))
    .onClick(() => {
      if (!this.isSaving) {
        this.saveCurrentImage()
      }
    })
  }

  @Builder
  private CloseActionButtonBuilder() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(20)
        .fontColor([this.themePrimary])
    }
    .width(40)
    .height(40)
    .padding(0)
    .backgroundColor(this.themePrimaryLight)
    .systemMaterial(this.getOverlayControlMaterial(true))
    .onClick(() => {
      this.dismiss()
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 黑色背景
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .opacity(this.backgroundOpacity)

      // Swiper 多图切换
      Swiper() {
        ForEach(this.images, (image: string, index: number) => {
          Image(image)
            .objectFit(ImageFit.Contain)
            .width('100%')
            .height('100%')
            .draggable(false)
        }, (image: string, index: number): string => index.toString())
      }
      .index(this.displayIndex)
      .loop(false)
      .disableSwipe(this.imageScale > 1)
      .indicator(false)
      .duration(300)
      .curve(Curve.EaseOut)
      .onChange((index: number) => {
        this.displayIndex = index
        this.resetGestureState()
      })
      .width('100%')
      .height('100%')
      .scale({ x: this.imageScale * this.dragScale, y: this.imageScale * this.dragScale })
      .translate({ x: this.offsetX, y: this.offsetY })

      // 底部圆点指示器
      if (this.images.length > 1) {
        Row({ space: 6 }) {
          ForEach(this.images, (item: string, index: number) => {
            Column()
              .width(index === this.displayIndex ? 16 : 6)
              .height(6)
              .borderRadius(3)
              .backgroundColor(index === this.displayIndex ? '#FFFFFF' : 'rgba(255, 255, 255, 0.5)')
              .animation({ duration: 200, curve: Curve.EaseOut })
          }, (item: string, index: number): string => index.toString())
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .position({ x: 0, y: '100%' })
        .translate({ y: this.getIndicatorTranslateY() })
      }

      // 右下角保存按钮
      Stack() {
        this.SaveActionButtonBuilder()
      }
        .position({ x: '100%', y: '100%' })
        .translate({ x: this.getSaveButtonTranslateX(), y: this.getSaveButtonTranslateY() })

      // 顶部关闭按钮 + 页码
      Row() {
        this.CloseActionButtonBuilder()

        Blank()

        if (this.images.length > 1) {
          Text(`${this.displayIndex + 1} / ${this.images.length}`)
            .fontSize(16)
            .fontColor(this.themePrimary)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(this.themePrimaryLight)
            .borderRadius(999)
            .systemMaterial(this.getOverlayControlMaterial(false))
        }
      }
      .width('100%')
      .padding({
        left: this.overlayHorizontalMarginVp,
        right: this.overlayHorizontalMarginVp,
        top: this.topSafeAreaVp + this.overlayTopMarginVp
      })
      .position({ x: 0, y: 0 })
    }
    .width('100%')
    .height('100%')
    // 双指缩放：parallelGesture 使其与其他手势并行，互不干扰
    .parallelGesture(
      PinchGesture({ fingers: 2 })
        .onActionStart(() => {
          this.lastImageScale = this.imageScale
        })
        .onActionUpdate((event: GestureEvent) => {
          let newScale = this.lastImageScale * event.scale
          if (newScale < 0.5) {
            newScale = 0.5
          } else if (newScale > 4) {
            newScale = 4
          }
          this.imageScale = newScale
        })
        .onActionEnd(() => {
          if (this.imageScale < 1) {
            this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
              this.imageScale = 1
              this.lastImageScale = 1
              this.offsetX = 0
              this.offsetY = 0
            })
          }
          this.lastImageScale = this.imageScale
        })
    )
    // 拖动和点击互斥：手指动了就是拖动，没动就是点击，不会同时触发
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        // PanGesture 在前：手指移动超过阈值时胜出，TapGesture 被取消
        PanGesture({ fingers: 1, distance: 12 })
          .onActionStart(() => {
            this.lastOffsetX = this.offsetX
            this.lastOffsetY = this.offsetY
            this.panDirection = 'none'
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.imageScale > 1) {
              this.offsetX = this.lastOffsetX + event.offsetX
              this.offsetY = this.lastOffsetY + event.offsetY
            } else {
              // 方向锁定
              if (this.panDirection === 'none') {
                if (Math.abs(event.offsetX) > 10 || Math.abs(event.offsetY) > 10) {
                  if (Math.abs(event.offsetX) > Math.abs(event.offsetY)) {
                    this.panDirection = 'horizontal'
                  } else {
                    this.panDirection = 'vertical'
                  }
                }
              }

              if (this.panDirection === 'vertical' && event.offsetY > 0) {
                const rawY = event.offsetY
                // 橡皮筋阻尼：阻力随距离递增，自然减速
                this.offsetY = rawY * 0.55 / (1 + rawY / 500)
                // 同步缩小图片，营造"抽离"效果
                this.dragScale = 1 - Math.min(rawY / 600, 0.2)
                // 背景同步淡出
                this.backgroundOpacity = Math.max(0.15, 1 - rawY / 450)
              }
            }
          })
          .onActionEnd((event: GestureEvent) => {
            if (this.imageScale > 1) {
              // 放大状态：保持当前拖动位置，不回弹
              this.lastOffsetX = this.offsetX
              this.lastOffsetY = this.offsetY
              return
            }

            // 未放大：下拉关闭
            if (this.panDirection === 'vertical' && this.offsetY > 70) {
              this.isDismissing = true
              this.getUIContext().animateTo({ duration: 280, curve: Curve.FastOutLinearIn }, () => {
                this.offsetY = 2000
                this.dragScale = 0.6
                this.backgroundOpacity = 0
              })
              setTimeout(() => this.onClose(), 300)
              return
            }

            // 回弹归位
            this.getUIContext().animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
              this.offsetX = 0
              this.offsetY = 0
              this.dragScale = 1
              this.backgroundOpacity = 1
            })
          }),
        // TapGesture 组：手指没移动时才会触发（PanGesture 未识别）
        GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 2 })
            .onAction(() => {
              this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
                if (this.imageScale > 1) {
                  this.imageScale = 1
                  this.lastImageScale = 1
                  this.offsetX = 0
                  this.offsetY = 0
                } else {
                  this.imageScale = 2
                  this.lastImageScale = 2
                }
              })
            }),
          TapGesture({ count: 1 })
            .onAction(() => {
              if (this.imageScale <= 1) {
                this.dismiss()
              }
            })
        )
      )
    )
  }

  private async saveCurrentImage(): Promise<void> {
    if (this.isSaving) {
      return
    }

    const imageUri = this.images[this.displayIndex]
    if (!imageUri) {
      this.showImageToast($r('app.string.image_not_found'))
      return
    }

    this.isSaving = true
    try {
      if (imageUri.startsWith('data:')) {
        await this.saveFromBase64(imageUri)
      } else {
        await this.saveFromFileUri(imageUri)
      }
      this.showImageToast($r('app.string.image_saved_to_album'))
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err)
      hilog.error(0x0000, 'ImagePreview', 'Save image failed: %{public}s', errorMessage)
      this.showImageToast($r('app.string.image_save_failed'))
    } finally {
      this.isSaving = false
    }
  }

  private async saveFromFileUri(imageUri: string): Promise<void> {
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      throw new Error('UI context is unavailable')
    }
    const context = hostContext as common.UIAbilityContext
    try {
      // 将 file:// URI 转换为规范格式
      let filePath = imageUri
      if (filePath.startsWith('file://')) {
        filePath = filePath.replace('file://', '')
      }
      const srcUri = fileUri.getUriFromPath(filePath)

      const ext = this.getExtensionFromUri(imageUri)
      const config: photoAccessHelper.PhotoCreationConfig = {
        title: `IMG_${Date.now()}`,
        fileNameExtension: ext,
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      }

      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context)
      const desFileUris = await phAccessHelper.showAssetsCreationDialog([srcUri], [config])
      if (desFileUris.length === 0) {
        throw new Error('No target file uri selected')
      }

      const srcFile = fileIo.openSync(srcUri, fileIo.OpenMode.READ_ONLY)
      const desFile = fileIo.openSync(desFileUris[0], fileIo.OpenMode.WRITE_ONLY)
      fileIo.copyFileSync(srcFile.fd, desFile.fd)
      fileIo.closeSync(srcFile)
      fileIo.closeSync(desFile)
    } catch (error) {
      throw new Error(`Save from file uri failed: ${JSON.stringify(error)}`)
    }
  }

  private async saveFromBase64(dataUri: string): Promise<void> {
    const hostContext = this.getUIContext().getHostContext()
    if (!hostContext) {
      throw new Error('UI context is unavailable')
    }
    const context = hostContext as common.UIAbilityContext

    // 解析 data URI: data:image/png;base64,xxxxx
    const commaIndex = dataUri.indexOf(',')
    const base64Data = dataUri.substring(commaIndex + 1)
    const mimeSection = dataUri.substring(0, commaIndex)

    let ext = 'png'
    if (mimeSection.includes('jpeg') || mimeSection.includes('jpg')) {
      ext = 'jpg'
    } else if (mimeSection.includes('gif')) {
      ext = 'gif'
    } else if (mimeSection.includes('webp')) {
      ext = 'webp'
    }

    // 解码 base64 并写入临时文件
    const decodedBuffer = buffer.from(base64Data, 'base64')
    const tempFileName = `temp_save_${Date.now()}.${ext}`
    const tempFilePath = `${context.cacheDir}/${tempFileName}`
    try {
      const tempFile = fileIo.openSync(tempFilePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY)
      fileIo.writeSync(tempFile.fd, decodedBuffer.buffer)
      fileIo.closeSync(tempFile)

      const tempFileUriStr = fileUri.getUriFromPath(tempFilePath)
      await this.saveFromFileUri(tempFileUriStr)
    } catch (error) {
      throw new Error(`Save from base64 failed: ${JSON.stringify(error)}`)
    } finally {
      // 清理临时文件
      try {
        fileIo.unlinkSync(tempFilePath)
      } catch (cleanupError) {
        hilog.error(0x0000, 'ImagePreview', 'Cleanup temp file failed: %{public}s', JSON.stringify(cleanupError))
      }
    }
  }

  private getExtensionFromUri(uri: string): string {
    const dotIndex = uri.lastIndexOf('.')
    if (dotIndex >= 0) {
      let ext = uri.substring(dotIndex + 1).toLowerCase()
      const queryIndex = ext.indexOf('?')
      if (queryIndex >= 0) {
        ext = ext.substring(0, queryIndex)
      }
      return ext
    }
    return 'jpg'
  }

  private resetGestureState(): void {
    this.imageScale = 1
    this.lastImageScale = 1
    this.offsetX = 0
    this.offsetY = 0
    this.lastOffsetX = 0
    this.lastOffsetY = 0
    this.backgroundOpacity = 1
    this.dragScale = 1
    this.panDirection = 'none'
  }
}
