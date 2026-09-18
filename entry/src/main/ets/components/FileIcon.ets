import { getAppUiState } from '../state/AppUiState'
import { resolveFileIconResourcePath } from '../utils/FileIconUtils'

// 共用文件类型映射；默认保留原始配色，知识库可指定所属类别的颜色。
@ComponentV2
export struct FileIcon {
  @Param fileName: string = ''
  @Param mimeType: string = ''
  @Param iconSize: number = 18
  @Param tintColor: ResourceColor | undefined = undefined
  @Param synchronousLoad: boolean = false

  @Computed
  private get iconPath(): string {
    return resolveFileIconResourcePath(this.fileName, this.mimeType, getAppUiState().isDarkMode)
  }

  build() {
    Image($rawfile(this.iconPath))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      // SVG2 保留 fill="none" 的透明区域，避免着色后遮住图案。
      .supportSvg2(this.tintColor !== undefined)
      .fillColor(this.tintColor ?? ColorContent.ORIGIN)
      .flexShrink(0)
      .draggable(false)
      .syncLoad(this.synchronousLoad)
      .accessibilityLevel('no')
  }
}
