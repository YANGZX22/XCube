import { getAppUiState } from '../state/AppUiState'
import { resolveFileIconResourcePath } from '../utils/FileIconUtils'

// 工作区、消息附件和知识库共用相同映射。原始 SVG 配色用于区分文件类型。
@ComponentV2
export struct FileIcon {
  @Param fileName: string = ''
  @Param mimeType: string = ''
  @Param iconSize: number = 18
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
      .flexShrink(0)
      .draggable(false)
      .syncLoad(this.synchronousLoad)
      .accessibilityLevel('no')
  }
}
