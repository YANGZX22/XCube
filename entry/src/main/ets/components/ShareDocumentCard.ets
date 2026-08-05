/**
 * Canvas 文稿分享卡片。
 * 用于分享预览和离屏长图渲染。
 */
import { ChatMarkdownHybridRenderer } from './ChatMarkdownHybridRenderer'
import { getAppUiState } from '../state/AppUiState'

@ComponentV2
export struct ShareDocumentCard {
  @Param title: string = 'Canvas'
  @Param content: string = ''
  @Param updatedAt: number = 0
  @Param appName: string = 'XCube'

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.app_icon'))
          .width(24)
          .height(24)
          .borderRadius(6)
          .syncLoad(true)

        Column({ space: 1 }) {
          Text(this.appName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          Text('Canvas')
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
        }
        .margin({ left: 8 })
        .alignItems(HorizontalAlign.Start)

        Blank()

        Text(this.formatDateTime(this.updatedAt > 0 ? this.updatedAt : Date.now()))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 12 })

      Divider()
        .color($r('app.color.divider'))
        .margin({ left: 16, right: 16 })

      Column({ space: 14 }) {
        Text(this.resolveTitle())
          .width('100%')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Start)

        if (this.content.trim() !== '') {
          ChatMarkdownHybridRenderer({
            content: this.content,
            isInputEnded: true,
            incrementalAnalysis: false,
            useCangjieComponent: true,
            chatFontSize: 14,
            themeRenderKey: `canvas-share-${this.updatedAt}`,
            showCodeFullScreen: false
          })
            .width('100%')
            .backgroundColor(Color.Transparent)
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 22 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .clip(true)
    .shadow({
      radius: 20,
      color: this.isDarkMode ? 'rgba(0, 0, 0, 0.3)' : 'rgba(0, 0, 0, 0.1)',
      offsetX: 0,
      offsetY: 4
    })
  }

  private resolveTitle(): string {
    const normalizedTitle = this.title.trim()
    return normalizedTitle !== '' ? normalizedTitle : 'Canvas'
  }

  private formatDateTime(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear()
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    const hours = date.getHours().toString().padStart(2, '0')
    const minutes = date.getMinutes().toString().padStart(2, '0')
    return `${year}/${month}/${day} ${hours}:${minutes}`
  }
}
