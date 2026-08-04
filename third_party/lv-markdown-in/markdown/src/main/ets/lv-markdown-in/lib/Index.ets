import { LV_MD_CONTENT_TYPE, LV_MD_DATA_TYPE } from './utils/constant'
import { WebControl } from './webControl'
import { ImgControl } from './imgControl'
import { determineTitle } from './utils/determine/detTitle'
import { determineImg } from './utils/determine/detImg'
import { determineQuote } from './utils/determine/detQuote'
import { determineLine } from './utils/determine/detLine'
import { determineTable } from './utils/determine/detTable'
import { determineCode } from './utils/determine/detCode'
import { determineCheckbox } from './utils/determine/detCheckbox'
import { determineTabulate } from './utils/determine/detTabulate'
import { determineHTMLFONT, determineHTMLIMG } from './utils/determine/detHTMLEL'

import { lvTitleComponent } from './utils/lvTitleComponent'
import { lvCompositeComponent } from './utils/lvCompositeComponent'
import { lvTableComponent } from './utils/lvTableComponent'
import { lvCodeComponent } from './utils/lvCodeComponent'
import { lvImgComponent } from './utils/lvImgComponent'
import lvLineBuilder from './utils/lvLineBuilder'
import { lvQuoteComponent } from './utils/lvQuoteComponent'
import { lvCheckboxComponent } from './utils/lvCheckboxComponent'
import { lvTabulateComponent } from './utils/lvTabulateComponent'
import { lvHTMLImgComponent } from './utils/lvHTMLImgComponent'
import { lvHTMLFontComponent } from './utils/lvHTMLFontComponent'

import { buffer } from '@kit.ArkTS'
import { fileIo as fs, ReadTextOptions } from '@kit.CoreFileKit'
import { lvFootnoteView } from './utils/lvFootnoteComponent'
import { LvFootnoteController } from './utils/controller/lvFootnoteController'
import { html2md } from '@luvi/html2md'

// import { html2View } from 'html2View'

export interface LMICallBack {
  success?: Function,
  fail?: Function,
  code?: string,
  message?: string
}

/**
 * @deprecated LvMarkdownIn() 组件已弃用，你可以使用导出的 Markdown() 组件
 * @instruction 新版本使用说明：https://ohpm.openharmony.cn/#/cn/detail/@luvi%2Flv-markdown-in
 */
@Component
export default struct lvMarkdownIn {
  /** 纯文本数据，mode：text */
  @Prop @Watch("textChange") text: string;
  /** 加载模式：
   * text：纯文本模式
   * rawfile：rawfile资源文件模式
   * sandbox：本地沙箱路径文件模式
   */
  @Prop loadMode: "text" | "rawfile" | "sandbox" = "text";
  /**
   * 资源文件path
   */
  @Prop rawfilePath: string
  /**
   * 沙箱文件path
   */
  @Prop sandboxPath: string
  /**
   * 应用上下文
   */
  @State context: Context | null = null
  /**
   * 事件回调
   */
  loadCallBack: LMICallBack = {
    success(msg?: string) {
    },
    fail(msg?: string) {
    }
  }
  @State cge: number = new Date().getTime()
  @State private resultData: string[][] = []
  @State footnoteController: LvFootnoteController = new LvFootnoteController()
  startTime: number = new Date().getTime()
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: WebControl(),
    alignment: DialogAlignment.Bottom,
    customStyle: true
  })
  private imgController: CustomDialogController = new CustomDialogController({
    builder: ImgControl(),
    customStyle: true
  })

  textChange() {
    if (this.loadMode == "text") {
      this._readText()
    }
  }

  cBack(type: "success" | "fail", code: string, message: string) {
    if (type == "success") {
      if (this.loadCallBack.success) {
        this.loadCallBack?.success({ code, message })
      }
    }
    if (type == "fail") {
      if (this.loadCallBack.fail) {
        this.loadCallBack?.fail({ code, message })
      }
    }
  }

  aboutToAppear() {
    this.startTime = new Date().getTime();
    if (this.loadMode == "text") {
      this._readText()
    }
    if (this.loadMode == "rawfile") {
      this._loadRawfile()
    }
    if (this.loadMode == "sandbox") {
      this._loadSandbox()
    }
  }

  // 1
  _loadRawfile() {
    if (!this.rawfilePath && this.loadCallBack.fail) {
      this.cBack("fail", "50011", "The rawfile resource file is incorrect.")
      return
    }
    if (!this.context) {
      this.cBack("fail", "50030", "The context is incorrect.")
      return
    }
    try {
      let uint8Array: Uint8Array = this.context?.resourceManager.getRawFileContentSync(this.rawfilePath);
      let bf = buffer.from(uint8Array).buffer;
      let bf2 = new buffer.Blob([bf]);
      let pro = bf2.text();
      pro.then((str: string) => {
        this._readText(str)
      });
    } catch (error) {
      this.cBack("fail", "50012", "The resourceManager getRawFileContentSync is error, " +
      JSON.stringify(error))
    }
  }

  // 2
  _loadSandbox() {
    if (!this.sandboxPath) {
      this.cBack("fail", "50021", "The sandbox file is incorrect.")
      return
    }
    try {
      let readTextOptions: ReadTextOptions = {
        offset: 0,
        length: 0,
        encoding: 'utf-8'
      };
      let stat = fs.statSync(this.sandboxPath);
      readTextOptions.length = stat.size;
      let str = fs.readTextSync(this.sandboxPath, readTextOptions);
      this._readText(str)
    } catch (error) {
      this.cBack("fail", "50022", "The fileIo readText is error, " +
      JSON.stringify(error))
    }
  }

  _readText(text: string = this.text) {
    const html2mdRes = html2md(text)
    // const html2mdRes = text
    // console.log("luvi > " + html2mdRes)
    let code_flag = -1
    let fIdx = html2mdRes.split('\n').map((item: string) => {
      if (code_flag < 0) {
        if (determineCode(item)) {
          ++code_flag
          return LV_MD_CONTENT_TYPE.CODE
        }
        if (determineTable(item)) {
          return LV_MD_CONTENT_TYPE.TABLE
        }
        return LV_MD_CONTENT_TYPE.TEXT
      } else {
        if (determineCode(item)) {
          code_flag = -1
          return LV_MD_CONTENT_TYPE.TEXT
        } else {
          return LV_MD_CONTENT_TYPE.CODE
        }
      }
    })

    let resultData: string[][] = []
    let montageText: string = ""
    let montageTableText: string = ""
    html2mdRes.split('\n').forEach((item: string, i: number) => {
      if (fIdx[i] == LV_MD_CONTENT_TYPE.TEXT) {
        if (montageText != "") {
          montageText += item + '\n'
          resultData.push([LV_MD_CONTENT_TYPE.CODE, montageText])
          montageText = ""
        } else if (montageTableText != "") {
          montageTableText += item + '\n'
          resultData.push([LV_MD_CONTENT_TYPE.TABLE, montageTableText])
          montageTableText = ""
        } else {
          if (determineTitle(item)) {
            return resultData.push([LV_MD_CONTENT_TYPE.TITLE, item.trim()])
          } else if (determineImg(item)) {
            return resultData.push([LV_MD_CONTENT_TYPE.IMG, item.trim()])
          } else if (determineQuote(item)) {
            return resultData.push([LV_MD_CONTENT_TYPE.QUOTE, item.trim()])
          } else if (determineLine(item)) {
            return resultData.push([LV_MD_CONTENT_TYPE.LINE, item.trim()])
          } else if (determineCheckbox(item)) {
            return resultData.push([LV_MD_CONTENT_TYPE.CHECKBOX, item.trim()])
          } else if (i > 0 && determineTabulate(item, html2mdRes.split('\n')[i-1], html2mdRes.split('\n')[i+1])) {
            return resultData.push([LV_MD_CONTENT_TYPE.TABULATE, item])
          } else if (determineHTMLIMG(item)) {
            return resultData.push([LV_MD_CONTENT_TYPE.HTMLIMG, item])
          } else if (determineHTMLFONT(item)) {
            return resultData.push([LV_MD_CONTENT_TYPE.HTMLFONT, item])
          } else {
            return resultData.push([LV_MD_CONTENT_TYPE.TEXT, item.trim()])
          }
        }
      } else if (fIdx[i] == LV_MD_CONTENT_TYPE.TABLE) {
        montageTableText += item + '\n'
      } else {
        montageText += item + '\n'
      }
      return item
    })
    this.resultData = resultData
    this.cBack("success", "20000", "Component Load Success.")
    const endTime = new Date().getTime();
    const elapsedTime = endTime - this.startTime;
    // console.log(`lv-markdown-in execution time is: ${elapsedTime} ms`);
  }

  build() {
    Column() {
      List() {
        ListItem() {
          Column() {
            ForEach(this.resultData, (item: string[]) => {
              Row() {
                if (item[LV_MD_DATA_TYPE.FLAG] === LV_MD_CONTENT_TYPE.TEXT) {
                  lvCompositeComponent({
                    text: item[LV_MD_DATA_TYPE.MSG],
                    dialogController: this.dialogController,
                    footnoteController: this.footnoteController
                  })
                }
                if (item[LV_MD_DATA_TYPE.FLAG] === LV_MD_CONTENT_TYPE.TITLE) {
                  lvTitleComponent({ text: item[LV_MD_DATA_TYPE.MSG], dialogController: this.dialogController })
                }
                if (item[LV_MD_DATA_TYPE.FLAG] === LV_MD_CONTENT_TYPE.CODE) {
                  lvCodeComponent({ text: item[LV_MD_DATA_TYPE.MSG] })
                }
                if (item[LV_MD_DATA_TYPE.FLAG] === LV_MD_CONTENT_TYPE.IMG) {
                  lvImgComponent({ text: item[LV_MD_DATA_TYPE.MSG], dialogController: this.imgController })
                }
                if (item[LV_MD_DATA_TYPE.FLAG] === LV_MD_CONTENT_TYPE.HTMLIMG) {
                  lvHTMLImgComponent({ text: item[LV_MD_DATA_TYPE.MSG], dialogController: this.imgController })
                }
                if (item[LV_MD_DATA_TYPE.FLAG] === LV_MD_CONTENT_TYPE.HTMLFONT) {
                  lvHTMLFontComponent({ text: item[LV_MD_DATA_TYPE.MSG] })
                }
                if (item[LV_MD_DATA_TYPE.FLAG] === LV_MD_CONTENT_TYPE.QUOTE) {
                  lvQuoteComponent({
                    text: item[LV_MD_DATA_TYPE.MSG],
                    dialogController: this.dialogController,
                  })
                }
                if (item[LV_MD_DATA_TYPE.FLAG] === LV_MD_CONTENT_TYPE.LINE) {
                  lvLineBuilder()
                }
                if (item[LV_MD_DATA_TYPE.FLAG] === LV_MD_CONTENT_TYPE.TABLE) {
                  lvTableComponent({
                    text: item[LV_MD_DATA_TYPE.MSG],
                    dialogController: this.dialogController,
                  })
                }
                if (item[LV_MD_DATA_TYPE.FLAG] === LV_MD_CONTENT_TYPE.CHECKBOX) {
                  lvCheckboxComponent({
                    text: item[LV_MD_DATA_TYPE.MSG],
                    dialogController: this.dialogController,
                  })
                }
                if (item[LV_MD_DATA_TYPE.FLAG] === LV_MD_CONTENT_TYPE.TABULATE) {
                  lvTabulateComponent({
                    text: item[LV_MD_DATA_TYPE.MSG],
                    dialogController: this.dialogController,
                  })
                }
              }.margin({ top: !item[1] ? 10 : 5 })
            })

            lvFootnoteView({ dialogController: this.dialogController })
          }.alignItems(HorizontalAlign.Start).width('100%')
        }
      }.edgeEffect(EdgeEffect.None).scrollBar(BarState.Off)
    }
  }
}