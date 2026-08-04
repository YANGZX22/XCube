import { fileIo as fs } from '@kit.CoreFileKit'
import { webview } from '@kit.ArkWeb'
import { CodeDialogController } from '../controller/CodeDialogController'
import { MDBaseController } from '../controller/BaseController'
import { WebDialogController } from '../controller/WebDialogController'
import { CodeBlockImpl } from '../impl/CodeBlockImpl'
import { CodeBlockNode } from '../model/TreeNode'
import { buildHtmlPreviewDocument, buildHtmlPreviewMissingDocument } from '../utils/HtmlPreviewBuilder'
import { WebPreviewPool, WebPreviewPoolRequest, WebPreviewPoolSlot } from '../utils/WebPreviewPool'
import { CodeSourceBlockRender } from './CodeSourceBlockRender'
import { CodeSourceRender } from './CodeSourceRender'

type HtmlTab = "preview" | "code"

@Component
export struct HtmlRender {
  @Consume markdownUnion: string
  @Prop @Watch('handleBaseChange') base: CodeBlockNode | undefined = undefined
  @Prop @Watch('handleStreamingChange') streamingActive: boolean = false
  @State activeTab: HtmlTab = "preview"
  @State previewSrc: string = ""
  @State previewError: string = ""
  @State loading: boolean = false
  @State previewLoading: boolean = false
  @State poolRenderVersion: number = 0
  controller: WebviewController = new webview.WebviewController()
  private previewFilePath: string = ""
  private previewSignature: string = ""
  private componentAlive: boolean = false
  private previewVisible: boolean = false
  private poolOwnerKey: string =
    `lv_html_preview_${Date.now()}_${Math.floor(Math.random() * 100000)}`
  private poolSlot: WebPreviewPoolSlot | null = null
  private poolRequestedSrc: string = ""
  // previewSrc 就绪但暂时拿不到池 slot 时的兜底重试定时器(见 scheduleSlotAcquireRetry), 与 MermaidRender 同款。
  private slotRetryTimer: number = -1

  aboutToAppear(): void {
    this.componentAlive = true
    if (this.isPreviewSuppressed()) {
      return
    }
    this.preloadWebPreviewPool()
    this.handleBaseChange()
  }

  aboutToDisappear(): void {
    this.componentAlive = false
    this.releasePooledPreview()
    this.deletePreviewFile()
  }

  private deletePreviewFile() {
    if (this.previewFilePath.length == 0) {
      return
    }
    try {
      fs.unlinkSync(this.previewFilePath)
    } catch (_err) {
    }
    this.previewFilePath = ""
  }

  private isDarkTheme(): boolean {
    return MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockTheme() == "dark"
  }

  private getActiveTabBackgroundColor(): ResourceColor {
    return this.isDarkTheme() ? "#363A42" : "#ffffff"
  }

  private getTabTextColor(tab: HtmlTab): ResourceColor {
    if (this.activeTab == tab) {
      return this.isDarkTheme() ? "#F9FAFB" : "#111827"
    }
    return this.isDarkTheme() ? "#AEB4BC" : "#606366"
  }

  private getLoadingColor(): ResourceColor {
    return this.isDarkTheme() ? "#F9FAFB" : "#303133"
  }

  private getLanguageLabel(): string {
    const lang = (this.base?.lang || "html").trim()
    return lang.length > 0 ? lang : "html"
  }

  private getCodeTabWidth(): number {
    return Math.max(64, Math.min(108, this.getLanguageLabel().length * 8 + 42))
  }

  private shouldUseWebPreviewPool(): boolean {
    return MDBaseController.getMarkdownController(this.markdownUnion).getWebPreviewPoolEnable()
  }

  private preloadWebPreviewPool() {
    const markdownController = MDBaseController.getMarkdownController(this.markdownUnion)
    if (!markdownController.getWebPreviewPoolEnable()) {
      return
    }
    WebPreviewPool.getInstance().preload(this.getUIContext(), markdownController.getWebPreviewPoolInitialSize(),
      markdownController.getWebPreviewPoolMaxSize(), markdownController.getWebPreviewPoolIdleRetain())
  }

  private releasePooledPreview() {
    this.clearSlotAcquireRetry()
    WebPreviewPool.getInstance().release(this.poolOwnerKey)
    if (this.poolSlot !== null || this.poolRequestedSrc.length > 0) {
      this.poolSlot = null
      this.poolRequestedSrc = ""
      this.poolRenderVersion++
    }
  }

  private clearSlotAcquireRetry() {
    if (this.slotRetryTimer >= 0) {
      clearTimeout(this.slotRetryTimer)
      this.slotRetryTimer = -1
    }
  }

  // previewSrc 就绪但暂时没拿到池 slot(request 进等待队列、回填偶发丢失)时周期性重试申请,
  // 拿到 slot 或组件不再可见即停, 避免快速滑动后"一直转圈"(与 MermaidRender 同款兜底)。
  private scheduleSlotAcquireRetry() {
    if (this.slotRetryTimer >= 0) {
      return
    }
    this.slotRetryTimer = setTimeout(() => {
      this.slotRetryTimer = -1
      if (this.componentAlive && this.previewVisible && this.activeTab == "preview" &&
        this.previewSrc.length > 0 && this.poolSlot === null) {
        this.acquirePooledPreview()
      }
    }, 400)
  }

  private acquirePooledPreview() {
    if (this.isPreviewSuppressed() || !this.shouldUseWebPreviewPool() || !this.componentAlive || !this.previewVisible ||
      this.activeTab != "preview" || this.previewSrc.length == 0) {
      return
    }
    const markdownController = MDBaseController.getMarkdownController(this.markdownUnion)
    const request = new WebPreviewPoolRequest(this.poolOwnerKey, this.previewSrc,
      markdownController.getHtmlPreviewJavaScriptEnable(), this.getUIContext())
    request.initialSize = markdownController.getWebPreviewPoolInitialSize()
    request.maxSize = markdownController.getWebPreviewPoolMaxSize()
    request.idleRetain = markdownController.getWebPreviewPoolIdleRetain()
    request.onProgressChange = (progress: number) => {
      if (this.componentAlive && this.activeTab == "preview" && this.previewSrc == request.src && progress > 70) {
        animateTo({ duration: 200 }, () => {
          this.previewLoading = false
        })
      }
    }
    request.onPageEnd = () => {
      if (this.componentAlive && this.activeTab == "preview" && this.previewSrc == request.src) {
        this.previewLoading = false
      }
    }
    request.onAcquired = (slot: WebPreviewPoolSlot) => {
      if (!this.componentAlive || this.activeTab != "preview") {
        WebPreviewPool.getInstance().release(this.poolOwnerKey)
        return
      }
      if (this.previewSrc != request.src) {
        // 申请期间 previewSrc 已重建: 该 slot 不再匹配, 释放后按最新 previewSrc 重新申请, 不要留在无 slot 的转圈态。
        WebPreviewPool.getInstance().release(this.poolOwnerKey)
        this.acquirePooledPreview()
        return
      }
      this.clearSlotAcquireRetry()
      this.poolSlot = slot
      this.poolRequestedSrc = request.src
      this.poolRenderVersion++
    }

    this.previewLoading = true
    const slot = WebPreviewPool.getInstance().request(request)
    if (slot !== null) {
      this.clearSlotAcquireRetry()
      this.poolSlot = slot
      this.poolRequestedSrc = request.src
      this.poolRenderVersion++
      return
    }
    this.poolSlot = null
    this.poolRequestedSrc = request.src
    this.poolRenderVersion++
    // 没拿到 slot(进等待队列): 安排兜底重试, 防回填丢失导致永久转圈。
    this.scheduleSlotAcquireRetry()
  }

  private buildPreviewSignature(): string {
    const controller = MDBaseController.getMarkdownController(this.markdownUnion)
    return `${this.base?.text || ""}\n${controller.getCodeBlockTheme()}\n${controller.getHtmlPreviewJavaScriptEnable()}`
  }

  private handleBaseChange() {
    if (this.isPreviewSuppressed()) {
      return
    }
    const signature = this.buildPreviewSignature()
    if (signature == this.previewSignature && this.previewSrc.length > 0) {
      this.acquirePooledPreview()
      return
    }
    this.previewSignature = signature
    this.previewError = ""
    this.previewLoading = true
    this.releasePooledPreview()
    const controller = MDBaseController.getMarkdownController(this.markdownUnion)
    try {
      this.previewSrc = this.writeHtmlToCache(buildHtmlPreviewDocument(this.base?.text || "",
        controller.getCodeBlockTheme(), controller.getHtmlPreviewJavaScriptEnable()))
      if (this.previewSrc.length == 0) {
        this.previewError = "HTML 预览加载失败"
        this.previewLoading = false
      } else {
        this.acquirePooledPreview()
      }
    } catch (_err) {
      this.previewSrc = this.writeHtmlToCache(buildHtmlPreviewMissingDocument("HTML 预览加载失败",
        controller.getCodeBlockTheme()))
      this.acquirePooledPreview()
    }
  }

  handleStreamingChange() {
    if (this.isPreviewSuppressed()) {
      this.releasePooledPreview()
      return
    }
    this.preloadWebPreviewPool()
    this.handleBaseChange()
  }

  private isPreviewSuppressed(): boolean {
    return this.streamingActive
  }

  private writeHtmlToCache(html: string): string {
    try {
      if (this.previewFilePath.length == 0) {
        this.previewFilePath =
          `${getContext().cacheDir}/lv_markdown_html_preview_${Date.now()}_${Math.floor(Math.random() * 100000)}.html`
      }
      const file = fs.openSync(this.previewFilePath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      fs.writeSync(file.fd, html)
      fs.closeSync(file)
      return `file://${this.previewFilePath}`
    } catch (_err) {
      return ""
    }
  }

  private openCodeDialog() {
    CodeDialogController.getInstance().openBindSheet(this.markdownUnion, this.base?.lang || "html",
      this.base?.text || "")
  }

  private async openPreview() {
    if (this.loading) {
      return
    }
    this.loading = true
    const controller = MDBaseController.getMarkdownController(this.markdownUnion)
    try {
      const html = buildHtmlPreviewDocument(this.base?.text || "", controller.getCodeBlockTheme(),
        controller.getHtmlPreviewJavaScriptEnable())
      await WebDialogController.getInstance().openHtmlBindSheet("HTML", html,
        controller.getHtmlPreviewJavaScriptEnable())
    } catch (_err) {
      await WebDialogController.getInstance().openHtmlBindSheet("HTML",
        buildHtmlPreviewMissingDocument("HTML 预览加载失败", controller.getCodeBlockTheme()), false)
    }
    this.loading = false
  }

  private openActiveFullscreen() {
    if (this.activeTab == "code") {
      this.openCodeDialog()
      return
    }
    this.openPreview()
  }

  build() {
    if (this.isPreviewSuppressed()) {
      CodeSourceBlockRender({
        markdownUnion: this.markdownUnion,
        lang: this.base?.lang || "html",
        text: this.base?.text || "",
        autoCollapse: this.base?.closed !== false,
        selectable: false,
        lineNumberWidth: 34,
        contentBottomPadding: 12
      })
        .onVisibleAreaChange([0.01], (isVisible: boolean, currentRatio: number) => {
          this.previewVisible = isVisible || currentRatio > 0
        })
    } else {
      Column() {
        Row() {
          Row({ space: 8 }) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 4 }) {
                if (this.isDarkTheme()) {
                  Image($rawfile("imgs/eye_w.png"))
                    .width(14)
                    .height(14)
                    .interpolation(ImageInterpolation.Medium)
                } else {
                  Image($rawfile("imgs/eye_b.png"))
                    .width(14)
                    .height(14)
                    .interpolation(ImageInterpolation.Medium)
                }
                Text("预览")
                  .fontSize(13)
                  .fontColor(this.getTabTextColor("preview"))
                  .offset({ y: 1 })
              }
            }
            .backgroundColor(this.activeTab == "preview" ? this.getActiveTabBackgroundColor() : Color.Transparent)
            .height(30)
            .width(64)
            .borderRadius(8)
            .padding({ left: 10, right: 10 })
            .onClick(() => {
              this.activeTab = "preview"
              this.handleBaseChange()
              this.acquirePooledPreview()
            })

            Button({ type: ButtonType.Normal }) {
              Row({ space: 4 }) {
                if (this.isDarkTheme()) {
                  Image($rawfile("imgs/code_w.png"))
                    .width(14)
                    .height(14)
                    .interpolation(ImageInterpolation.Medium)
                } else {
                  Image($rawfile("imgs/code_b.png"))
                    .width(14)
                    .height(14)
                    .interpolation(ImageInterpolation.Medium)
                }
                Text(this.getLanguageLabel())
                  .fontSize(13)
                  .fontColor(this.getTabTextColor("code"))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .offset({ y: 1 })
              }
            }
            .backgroundColor(this.activeTab == "code" ? this.getActiveTabBackgroundColor() : Color.Transparent)
            .height(30)
            .width(this.getCodeTabWidth())
            .borderRadius(8)
            .padding({ left: 10, right: 10 })
            .onClick(() => {
              this.activeTab = "code"
              this.releasePooledPreview()
            })
          }

          Row({ space: 4 }) {
            Button() {
              if (this.isDarkTheme()) {
                Image($rawfile("imgs/plus_square_on_square_fill_w.png")).width(16.6)
                  .interpolation(ImageInterpolation.Medium)
              } else {
                Image($rawfile("imgs/plus_square_on_square_fill_b.png")).width(16.6)
                  .interpolation(ImageInterpolation.Medium)
              }
            }
            .backgroundColor(Color.Transparent)
            .width(30)
            .height(30)
            .borderRadius(8)
            .onClick(() => {
              CodeBlockImpl.copyText(this.markdownUnion, this.base?.text || "")
            })

            Button() {
              if (this.activeTab == "preview" && this.loading) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(this.getLoadingColor())
              } else if (this.isDarkTheme()) {
                Image($rawfile("imgs/arrow_up_left_and_arrow_down_right_w.png"))
                  .width(18)
                  .height(18)
                  .interpolation(ImageInterpolation.Medium)
              } else {
                Image($rawfile("imgs/arrow_up_left_and_arrow_down_right_b.png"))
                  .width(18)
                  .height(18)
                  .interpolation(ImageInterpolation.Medium)
              }
            }
            .backgroundColor(Color.Transparent)
            .width(30)
            .height(30)
            .borderRadius(8)
            .onClick(() => {
              this.openActiveFullscreen()
            })
          }
        }
        .width("100%")
        .padding({ left: 8, right: 10 })
        .height(44)
        .justifyContent(FlexAlign.SpaceBetween)
        .backgroundColor(this.isDarkTheme() ? "#24262B" : "#F3F4F6")

        if (this.activeTab == "preview") {
          Stack({ alignContent: Alignment.Center }) {
            if (this.previewSrc.length > 0) {
              if (this.shouldUseWebPreviewPool()) {
                if (this.poolRenderVersion >= 0 && this.poolSlot !== null && this.poolRequestedSrc == this.previewSrc) {
                  NodeContainer(this.poolSlot.nodeController)
                    .width("100%")
                    .height("100%")
                } else {
                  LoadingProgress()
                    .width(42)
                    .height(42)
                    .color(this.getLoadingColor())
                }
              } else {
                Web({ src: this.previewSrc, controller: this.controller })
                  .mixedMode(MixedMode.All)
                  .domStorageAccess(true)
                  .javaScriptAccess(MDBaseController.getMarkdownController(this.markdownUnion)
                    .getHtmlPreviewJavaScriptEnable())
                  .fileAccess(true)
                  .overviewModeAccess(false)
                  .width("100%")
                  .height("100%")
                  .nestedScroll({
                    scrollForward: NestedScrollMode.SELF_ONLY,
                    scrollBackward: NestedScrollMode.SELF_ONLY
                  })
                  .onProgressChange((e) => {
                    if (e.newProgress > 70) {
                      animateTo({ duration: 200 }, () => {
                        this.previewLoading = false
                      })
                    }
                  })
              }
            } else {
              Text(this.previewError || "HTML 预览加载失败")
                .fontSize(14)
                .fontColor(this.isDarkTheme() ? "#FFB4B4" : "#a8071a")
                .lineHeight(22)
                .padding(12)
            }
          }
          .width("100%")
          .height(300)
          .backgroundColor(this.isDarkTheme() ? "#181A1F" : "#ffffff")
        } else {
          Scroll() {
            CodeSourceRender({
              markdownUnion: this.markdownUnion,
              text: this.base?.text || "",
              lang: this.base?.lang || "html",
              autoCollapse: false,
              selectable: false,
              lineNumberWidth: 34,
              contentBottomPadding: 12
            })
          }
          .width("100%")
          .height(300)
          .scrollable(ScrollDirection.Vertical)
          .edgeEffect(EdgeEffect.Spring)
          .backgroundColor(CodeBlockImpl.handleBackgroundColor(MDBaseController.getMarkdownController(this.markdownUnion)
            .getCodeBlockTheme()))
          .align(Alignment.TopStart)
        }
      }
      .width("100%")
      .alignItems(HorizontalAlign.Start)
      .borderRadius(CodeBlockImpl.handleCodeBlockBorderRadius(this.markdownUnion))
      .border({
        width: 1,
        color: this.isDarkTheme() ? "#24262B" : "#F3F4F6"
      })
      .clip(true)
      .onVisibleAreaChange([0.01], (isVisible: boolean, currentRatio: number) => {
        this.previewVisible = isVisible || currentRatio > 0
        if (isVisible || currentRatio > 0) {
          this.acquirePooledPreview()
        } else {
          this.releasePooledPreview()
        }
      })
    }
  }
}
