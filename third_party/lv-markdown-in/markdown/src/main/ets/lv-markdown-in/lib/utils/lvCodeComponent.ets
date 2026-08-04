import { codeStyle } from './codeColorOn'
import handleCodeLib from './handle/handleCodeLib'
import { lvCode, LvCode } from '../domain/LvCode'

let reg = /(\.\w+\()/g

@Component
export struct lvCodeComponent {
  @State text: string = ""
  @State nCode: LvCode = lvCode
  @State rowLimit: number = 11
  @State idxWidth: number = 10

  calcRow() {
    let len = this.text.split("\n").slice(1, -2).length
    if (len >= 10) {
      this.idxWidth = 20
    }
    if (len >= 100) {
      this.idxWidth = 30
    }
    return len
  }

  showMore() {
    this.rowLimit = -2
  }

  build() {
    Stack({
      alignContent: Alignment.TopEnd
    }) {
      // Column() {
      //   if (this.nCode.getTheme() == "dark") {
      //     Image($rawfile("imgs/copy_w1.png")).width(18).height(18)
      //       .interpolation(ImageInterpolation.Medium)
      //   } else {
      //     Image($rawfile("imgs/copy_g1.png")).width(18).height(18)
      //       .interpolation(ImageInterpolation.Medium)
      //   }
      //
      //   // Text('复制').fontColor(this.nCode.getTheme() == "dark" ? "#fff" : "rgba(84, 84, 84, 0.70)").fontSize(13)
      // }
      // .margin({
      //   top: 10, right: 10
      // })
      // .padding({
      //   top: 4,
      //   bottom: 4,
      //   left: 8,
      //   right: 8
      // })
      // .borderRadius(6)
      // .backgroundColor(this.nCode.getTheme() == "dark" ? "rgba(0,0,0,0.7)" : "rgba(0, 0, 0, 0.03)")
      // .zIndex(2)
      // .onClick(() => {
      //   copyContent(this.text)
      // })

      // 不可滚动了
      Stack({ alignContent: Alignment.Bottom }) {
        List() {
          ListItem() {
            Column() {
              // 分行
              ForEach(this.calcRow() >= 10 ? this.text.split("\n").slice(1, this.rowLimit) :
                this.text.split("\n").slice(1, -2),
                (rowText: string, ri: number) => {
                  Stack({ alignContent: Alignment.Start }) {
                    // 索引
                    Row() {
                      Text(ri + 1 + "")
                        .width(this.idxWidth)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .fontSize(13)
                        .fontColor(this.nCode.getTheme() == "dark" ? "#80f1f1f1" : "#6d666666")
                        .textAlign(TextAlign.End)

                      Row()
                        .margin({ left: 8, right: 8 })
                        .width(1)
                        .height(23)
                        .backgroundColor(this.nCode.getTheme() == "dark" ? "#51f1f1f1" : "#77888888")
                    }

                    Row() {
                      Text() {
                        // 按行处理样式
                        if (rowText.trim().slice(0, 2) == "//") {
                          Span(rowText)
                            .fontColor(this.nCode.getTheme() == "dark" ? "#80f1f1f1" : "#8b666666")
                            .fontSize(14)
                        } else {
                          ForEach(rowText.split(/(\w+|\.\w+\()/g), (item: string) => {
                            if (reg.test(item)) {
                              Span(item.slice(0, -1))
                                .fontColor(this.nCode.getTheme() == "dark" ? "#4FC1FF" : "#ff108edd")
                                .fontSize(14)
                              Span("(")
                                .fontColor(codeStyle["("])
                                .fontSize(14)
                            } else {
                              // Text(item)
                              ForEach(handleCodeLib(item), (item: string) => {
                                Span(item)
                                  .fontColor(codeStyle[item] ||
                                    (this.nCode.getTheme() == "dark" ? "#ffd9d9d9" : "#ff676767"))
                                  .fontSize(14)
                              })
                            }
                          })
                        }
                      }
                    }
                    .margin({ left: this.idxWidth + 16 })
                  }
                  .constraintSize({ minWidth: "100%" })
                  .height(23)
                })
            }
            .alignItems(HorizontalAlign.Start)
          }.padding({
            top: 15,
            bottom: 15,
            left: 10,
            right: 10
          })
        }
        .width('100%')
        .listDirection(Axis.Horizontal)
        .backgroundColor(this.nCode.getTheme() == "dark" ? "#282C35" : "#FAFAFA")
        .borderRadius(6)
        .scrollBar(BarState.Off)

        if (this.calcRow() >= 10 && this.rowLimit != -2) {
          Row() {
            Image($rawfile("imgs/down_b.png")).width(20).height(20)
          }
          .justifyContent(FlexAlign.Center)
          .width(60)
          .height(25)
          .borderRadius(99)
          .backgroundColor("#5cffffff")
          .margin({ bottom: 7 })
          .onClick(() => {
            this.showMore()
          })
        }
      }
    }.width('100%')
  }
}