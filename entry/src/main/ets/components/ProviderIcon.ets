/**
 * 供应商图标组件
 * 统一处理供应商和模型图标的显示
 * 支持三种图标类型：SVG、文字、自定义图片
 */

import { buildIconResourcePath } from '../utils/ProviderIconUtils'
import { TRANSPARENT_BG_COLOR } from '../utils/IconGeneratorUtils'
import { IconDownloadCache } from '../services/IconDownloadCache'

export enum ProviderTextIconDisplayMode {
  BRAND = 'brand',
  DISABLED_NEUTRAL = 'disabledNeutral'
}

export function resolveProviderTextIconDisplayMode(isEnabled: boolean): ProviderTextIconDisplayMode {
  return isEnabled ? ProviderTextIconDisplayMode.BRAND : ProviderTextIconDisplayMode.DISABLED_NEUTRAL
}

// 网络 URL、file URI 和沙箱绝对路径都由 ArkUI Image 直接读取。
export function resolveProviderCustomImageSource(customImagePath: string): string {
  if (customImagePath === '') {
    return ''
  }
  const lower = customImagePath.toLowerCase()
  if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('file://')
    || lower.startsWith('data:')) {
    return customImagePath
  }
  return customImagePath
}

export function isRemoteSvgImagePath(customImagePath: string): boolean {
  const lower = customImagePath.trim().toLowerCase()
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return false
  }
  const fragmentIndex = lower.indexOf('#')
  const withoutFragment = fragmentIndex >= 0 ? lower.substring(0, fragmentIndex) : lower
  const queryIndex = withoutFragment.indexOf('?')
  const cleanPath = queryIndex >= 0 ? withoutFragment.substring(0, queryIndex) : withoutFragment
  return cleanPath.endsWith('.svg')
}

function isRemoteImagePath(customImagePath: string): boolean {
  const lower = customImagePath.trim().toLowerCase()
  return lower.startsWith('http://') || lower.startsWith('https://')
}

@ComponentV2
export struct ProviderIcon {
  @Param iconPath: string = ''
  @Param iconSize: number = 40
  @Param bgColor: ResourceColor = Color.Transparent
  @Param radius: number = 10
  @Param fallbackSymbol: Resource = $r('sys.symbol.message')
  @Param fallbackColor: ResourceColor = Color.White
  @Param iconType: string = 'svg'
  @Param textIcon: string = ''
  @Param textIconBgColor: string = ''
  @Param customImagePath: string = ''
  @Param brandColor: ResourceColor = ''
  @Param isDarkMode: boolean = false
  @Param textIconDisplayMode: ProviderTextIconDisplayMode = ProviderTextIconDisplayMode.BRAND
  @Local hasImageLoadError: boolean = false
  @Local resolvedCustomImageSource: string = ''
  @Local hasAttemptedImageCache: boolean = false

  aboutToAppear(): void {
    this.refreshCustomImageSource()
  }

  @Monitor('customImagePath', 'iconType')
  onImageSourceChange(): void {
    this.refreshCustomImageSource()
  }

  private refreshCustomImageSource(): void {
    this.hasImageLoadError = false
    this.hasAttemptedImageCache = false
    const source = this.customImagePath.trim()
    if (this.iconType !== 'image' || source === '') {
      this.resolvedCustomImageSource = ''
      return
    }
    // 与预设供应商保持一致：优先直接渲染数据库中保存的原始 URL。
    this.resolvedCustomImageSource = resolveProviderCustomImageSource(source)
  }

  private async prepareRemoteImage(source: string): Promise<void> {
    const cachedPath = await IconDownloadCache.getInstance().downloadAndCache(source)
    if (this.iconType !== 'image' || this.customImagePath.trim() !== source) {
      return
    }
    if (cachedPath === '') {
      this.hasImageLoadError = true
      return
    }
    this.resolvedCustomImageSource = resolveProviderCustomImageSource(cachedPath)
    this.hasImageLoadError = false
  }

  private handleCustomImageLoadError(): void {
    const source = this.customImagePath.trim()
    this.hasImageLoadError = true
    // 兼容 URL 中没有 .svg 后缀、但服务端实际返回 SVG 的链接。
    if (!isRemoteImagePath(source) || this.hasAttemptedImageCache) {
      return
    }
    this.hasAttemptedImageCache = true
    void this.prepareRemoteImage(source)
  }

  private shouldFallbackToText(): boolean {
    return this.iconType === 'image' && this.hasImageLoadError && this.textIcon !== ''
  }

  private getCustomImageFit(): ImageFit {
    return isRemoteSvgImagePath(this.customImagePath) ? ImageFit.Contain : ImageFit.Cover
  }

  private isDisabledNeutralMode(): boolean {
    if (this.iconType === 'text' || this.shouldFallbackToText()) {
      return this.textIconDisplayMode === ProviderTextIconDisplayMode.DISABLED_NEUTRAL
    }
    return false
  }

  // 判断是否为透明背景
  private isTransparentBg(): boolean {
    return this.textIconBgColor === TRANSPARENT_BG_COLOR || this.textIconBgColor === ''
  }

  private shouldUseTransparentTextLayout(): boolean {
    return !this.isDisabledNeutralMode() && this.isTransparentBg()
  }

  // 获取背景色
  private getBackgroundColor(): ResourceColor {
    if (this.iconType === 'text' || this.shouldFallbackToText()) {
      if (this.isDisabledNeutralMode()) {
        return $r('app.color.divider')
      }
      if (this.shouldUseTransparentTextLayout()) {
        return Color.Transparent
      }
      return this.textIconBgColor
    }
    if (this.iconType === 'svg' || this.iconType === 'image') {
      return Color.Transparent
    }
    return this.bgColor
  }

  // 获取文字颜色（透明背景时使用深色文字）
  private getTextColor(): ResourceColor {
    if (this.isDisabledNeutralMode()) {
      return $r('app.color.text_secondary')
    }
    if (this.shouldUseTransparentTextLayout()) {
      return $r('app.color.text_primary')
    }
    return Color.White
  }

  private getTextFontSize(): number {
    return this.shouldUseTransparentTextLayout() ? this.iconSize * 0.7 : this.iconSize * 0.45
  }

  build() {
    Column() {
      // SVG 图标
      if (this.iconType === 'svg' && this.iconPath !== '') {
        Image($rawfile(buildIconResourcePath(this.iconPath)))
          .width(this.iconSize)
          .height(this.iconSize)
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.High)
          .borderRadius(this.radius)
          .clip(true)
      }
      else if (this.iconType === 'image' && this.resolvedCustomImageSource !== '' && !this.hasImageLoadError) {
        Image(this.resolvedCustomImageSource)
          .width(this.iconSize)
          .height(this.iconSize)
          .objectFit(this.getCustomImageFit())
          .interpolation(ImageInterpolation.High)
          .borderRadius(this.radius)
          .clip(true)
          .onError(() => {
            this.handleCustomImageLoadError()
          })
      }
      else if ((this.iconType === 'text' || this.shouldFallbackToText()) && this.textIcon !== '') {
        Text(this.textIcon)
          .fontSize(this.getTextFontSize())
          .fontColor(this.getTextColor())
          .fontWeight(FontWeight.Bold)
      }
      else {
        SymbolGlyph(this.fallbackSymbol)
          .fontSize(this.iconSize * 0.55)
          .fontColor([this.fallbackColor])
      }
    }
    .width(this.iconSize)
    .height(this.iconSize)
    .borderRadius(this.radius)
    .backgroundColor(this.getBackgroundColor())
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

@ComponentV2
export struct ProviderIconSmall {
  @Param iconPath: string = ''
  @Param iconSize: number = 24
  @Param iconType: string = 'svg'
  @Param textIcon: string = ''
  @Param textIconBgColor: string = ''
  @Param customImagePath: string = ''
  @Param brandColor: ResourceColor = ''
  @Param isDarkMode: boolean = false
  @Param textIconDisplayMode: ProviderTextIconDisplayMode = ProviderTextIconDisplayMode.BRAND
  @Local hasImageLoadError: boolean = false
  @Local resolvedCustomImageSource: string = ''
  @Local hasAttemptedImageCache: boolean = false

  aboutToAppear(): void {
    this.refreshCustomImageSource()
  }

  @Monitor('customImagePath', 'iconType')
  onImageSourceChange(): void {
    this.refreshCustomImageSource()
  }

  private refreshCustomImageSource(): void {
    this.hasImageLoadError = false
    this.hasAttemptedImageCache = false
    const source = this.customImagePath.trim()
    if (this.iconType !== 'image' || source === '') {
      this.resolvedCustomImageSource = ''
      return
    }
    this.resolvedCustomImageSource = resolveProviderCustomImageSource(source)
  }

  private async prepareRemoteImage(source: string): Promise<void> {
    const cachedPath = await IconDownloadCache.getInstance().downloadAndCache(source)
    if (this.iconType !== 'image' || this.customImagePath.trim() !== source) {
      return
    }
    if (cachedPath === '') {
      this.hasImageLoadError = true
      return
    }
    this.resolvedCustomImageSource = resolveProviderCustomImageSource(cachedPath)
    this.hasImageLoadError = false
  }

  private handleCustomImageLoadError(): void {
    const source = this.customImagePath.trim()
    this.hasImageLoadError = true
    if (!isRemoteImagePath(source) || this.hasAttemptedImageCache) {
      return
    }
    this.hasAttemptedImageCache = true
    void this.prepareRemoteImage(source)
  }

  private shouldFallbackToText(): boolean {
    return this.iconType === 'image' && this.hasImageLoadError && this.textIcon !== ''
  }

  private getCustomImageFit(): ImageFit {
    return isRemoteSvgImagePath(this.customImagePath) ? ImageFit.Contain : ImageFit.Cover
  }

  private isDisabledNeutralMode(): boolean {
    if (this.iconType === 'text' || this.shouldFallbackToText()) {
      return this.textIconDisplayMode === ProviderTextIconDisplayMode.DISABLED_NEUTRAL
    }
    return false
  }

  // 判断是否显示品牌色边框
  private shouldShowBrandBorder(): boolean {
    return this.iconType === 'svg' && this.brandColor !== ''
  }

  // 判断是否为透明背景
  private isTransparentBg(): boolean {
    return this.textIconBgColor === TRANSPARENT_BG_COLOR || this.textIconBgColor === ''
  }

  private shouldUseTransparentTextLayout(): boolean {
    return !this.isDisabledNeutralMode() && this.isTransparentBg()
  }

  build() {
    // SVG 图标
    if (this.iconType === 'svg' && this.iconPath !== '') {
      Image($rawfile(buildIconResourcePath(this.iconPath)))
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.High)
        .border(this.shouldShowBrandBorder() ? {
          width: 1.5,
          color: this.brandColor
        } : undefined)
        .borderRadius(this.iconSize * 0.25)
    }
    else if (this.iconType === 'image' && this.resolvedCustomImageSource !== '' && !this.hasImageLoadError) {
      Image(this.resolvedCustomImageSource)
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(this.getCustomImageFit())
        .interpolation(ImageInterpolation.High)
        .borderRadius(this.iconSize * 0.25)
        .backgroundColor(Color.Transparent)
        .onError(() => {
          this.handleCustomImageLoadError()
        })
    }
    else if ((this.iconType === 'text' || this.shouldFallbackToText()) && this.textIcon !== '') {
      if (this.shouldUseTransparentTextLayout()) {
        // 透明背景：直接显示文字/emoji
        Text(this.textIcon)
          .fontSize(this.iconSize * 0.85)
          .fontWeight(FontWeight.Bold)
      } else {
        // 有背景色：显示彩色背景 + 白色文字
        Column() {
          Text(this.textIcon)
            .fontSize(this.iconSize * 0.45)
            .fontColor(this.isDisabledNeutralMode() ? $r('app.color.text_secondary') : Color.White)
            .fontWeight(FontWeight.Bold)
        }
        .width(this.iconSize)
        .height(this.iconSize)
        .borderRadius(this.iconSize * 0.25)
        .backgroundColor(this.isDisabledNeutralMode() ? $r('app.color.divider') : this.textIconBgColor)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    // 默认 fallback
    else {
      SymbolGlyph($r('sys.symbol.message'))
        .fontSize(this.iconSize)
        .fontColor([$r('app.color.text_tertiary')])
    }
  }
}
