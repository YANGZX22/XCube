import { HdsMiniBarButton } from 'hds_button'

@Entry
@ComponentV2
struct Index {
  build() {
    Column({ space: 20 }) {
      // 基础用法 - 默认加号按钮
      Text('基础用法')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      HdsMiniBarButton({
        onButtonClick: () => {
          this.getUIContext().getPromptAction().showToast({
            message: '点击了加号按钮'
          })
        }
      })

      // 自定义图标
      Text('自定义图标')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      HdsMiniBarButton({
        iconResource: $r('sys.symbol.play_fill'),
        iconColor: [Color.White],
        onButtonClick: () => {
          this.getUIContext().getPromptAction().showToast({
            message: '点击了自定义的播放按钮'
          })
        }
      })

      // 自定义尺寸
      Text('自定义尺寸')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      HdsMiniBarButton({
        barWidth: 60,
        barHeight: 60,
        contentPadding: 10,
      })

      // 完全自定义内容 (尾随闭包)
      Text('自定义内容')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      HdsMiniBarButton({
        onButtonClick: () => {
        }
      }) {
        Text('GO')
          .fontSize(18)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
      }
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Gray)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
