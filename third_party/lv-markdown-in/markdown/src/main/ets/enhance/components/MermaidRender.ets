import { fileIo as fs } from '@kit.CoreFileKit'
import { webview } from '@kit.ArkWeb'
import { CodeTheme, markdownMermaidThemeChangeEventName } from '../constant/CodeTheme'
import { CodeDialogController } from '../controller/CodeDialogController'
import { MDBaseController } from '../controller/BaseController'
import { WebDialogController } from '../controller/WebDialogController'
import { CodeBlockImpl } from '../impl/CodeBlockImpl'
import { CodeBlockNode } from '../model/TreeNode'
import { buildMermaidHtml, buildMermaidMissingHtml, MermaidTheme } from '../utils/MermaidHtmlBuilder'
import { WebPreviewPool, WebPreviewPoolRequest, WebPreviewPoolSlot } from '../utils/WebPreviewPool'
import { CodeSourceBlockRender } from './CodeSourceBlockRender'
import { CodeSourceRender } from './CodeSourceRender'

type MermaidTab = "preview" | "code"
type MermaidPreviewTask = () => Promise<void>

class MermaidPreviewQueue {
  private static running: boolean = false
  private static tasks: MermaidPreviewTask[] = []

  static enqueue(task: MermaidPreviewTask) {
    MermaidPreviewQueue.tasks.push(task)
    MermaidPreviewQueue.runNext()
  }

  private static async runNext() {
    if (MermaidPreviewQueue.running) {
      return
    }
    const task = MermaidPreviewQueue.tasks.shift()
    if (!task) {
      return
    }
    MermaidPreviewQueue.running = true
    try {
      await task()
    } catch (_err) {
    }
    MermaidPreviewQueue.running = false
    MermaidPreviewQueue.runNext()
  }
}

@Component
export struct MermaidRender {
  @Consume markdownUnion: string
  @Prop @Watch('handleBaseChange') base: CodeBlockNode | undefined = undefined
  @Prop @Watch('handleStreamingChange') streamingActive: boolean = false
  @State loading: boolean = false
  @State activeTab: MermaidTab = "preview"
  // 仅用于 enqueueInlinePreview 的重入保护（await 期间防止重复入队），build 不读取，
  // 故无需 @State，降为普通字段以避免每次置位触发无效重渲染。
  private previewLoading: boolean = false
  @State previewSrc: string = ""
  @State previewError: string = ""
  @State themeVersion: number = 0
  @State poolRenderVersion: number = 0
  controller: WebviewController = new webview.WebviewController()
  private previewFilePath: string = ""
  private previewQueued: boolean = false
  private componentAlive: boolean = false
  private previewVisible: boolean = false
  private previewVersion: number = 0
  // previewSrc 就绪但暂时拿不到池 slot 时的兜底重试定时器(见 scheduleSlotAcquireRetry)。
  private slotRetryTimer: number = -1
  private previewSignature: string = ""
  private poolOwnerKey: string =
    `lv_mermaid_preview_${Date.now()}_${Math.floor(Math.random() * 100000)}`
  private poolSlot: WebPreviewPoolSlot | null = null
  private poolRequestedSrc: string = ""
  private mermaidThemeListener: (() => void) | null = null

  aboutToAppear(): void {
    this.componentAlive = true
    this.mermaidThemeChangeListener()
    if (this.isPreviewSuppressed()) {
      return
    }
    this.preloadWebPreviewPool()
    this.handleBaseChange()
  }

  aboutToDisappear(): void {
    this.componentAlive = false
    if (this.mermaidThemeListener) {
      getContext().eventHub.off(markdownMermaidThemeChangeEventName, this.mermaidThemeListener)
      this.mermaidThemeListener = null
    }
    this.releasePooledPreview()
    if (this.previewSrc.length == 0) {
      this.previewLoading = false
    }
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

  private mermaidThemeChangeListener() {
    if (this.mermaidThemeListener) {
      return
    }
    this.mermaidThemeListener = (): void => {
      if (this.isPreviewSuppressed()) {
        return
      }
      this.themeVersion++
      this.previewVersion++
      this.previewQueued = false
      this.previewLoading = false
      this.previewError = ""
      this.releasePooledPreview()
      this.previewSrc = ""
      this.enqueueInlinePreview()
    }
    getContext().eventHub.on(markdownMermaidThemeChangeEventName, this.mermaidThemeListener)
  }

  private buildPreviewSignature(): string {
    return `${this.base?.text || ""}\n${this.getRenderTheme()}\n${MDBaseController.getMarkdownController(this.markdownUnion)
      .getMermaidSecurityLevel()}`
  }

  private handleBaseChange() {
    if (this.isPreviewSuppressed()) {
      return
    }
    const signature = this.buildPreviewSignature()
    if (signature == this.previewSignature && this.previewSrc.length > 0) {
      return
    }
    this.previewSignature = signature
    this.previewVersion++
    this.previewQueued = false
    this.previewLoading = false
    this.previewError = ""
    this.releasePooledPreview()
    this.previewSrc = ""
    this.enqueueInlinePreview()
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

  private getRenderTheme(): CodeTheme {
    return MDBaseController.getMarkdownController(this.markdownUnion).getMermaidTheme()
  }

  private getCodeBlockTheme(): CodeTheme {
    return MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockTheme()
  }

  private isDarkTheme(): boolean {
    return this.getCodeBlockTheme() == "dark"
  }

  private getActiveTabBackgroundColor(): ResourceColor {
    return this.isDarkTheme() ? "#363A42" : "#ffffff"
  }

  private getTabTextColor(tab: MermaidTab): ResourceColor {
    if (this.activeTab == tab) {
      return this.isDarkTheme() ? "#F9FAFB" : "#111827"
    }
    return this.isDarkTheme() ? "#AEB4BC" : "#606366"
  }

  private getLoadingColor(): ResourceColor {
    return this.isDarkTheme() ? "#F9FAFB" : "#303133"
  }

  private getLanguageLabel(): string {
    const lang = (this.base?.lang || "mermaid").trim()
    return lang.length > 0 ? lang : "mermaid"
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
  // 拿到 slot 或组件不再可见即停, 避免快速滑动后"一直转圈"。
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
    const request = new WebPreviewPoolRequest(this.poolOwnerKey, this.previewSrc, true, this.getUIContext())
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
        // 申请期间 previewSrc 已重建: 该 slot 不再匹配, 释放后按最新 previewSrc 重新申请,
        // 不要直接 return 留在无 slot 的转圈态。
        WebPreviewPool.getInstance().release(this.poolOwnerKey)
        this.acquirePooledPreview()
        return
      }
      this.clearSlotAcquireRetry()
      this.poolSlot = slot
      this.poolRequestedSrc = request.src
      this.poolRenderVersion++
    }

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

  private resolveMermaidTheme(): MermaidTheme {
    return this.getRenderTheme() == "dark" ? "dark" : "default"
  }

  private enqueueInlinePreview() {
    if (this.isPreviewSuppressed() || !this.componentAlive || this.activeTab != "preview" || this.previewQueued ||
      this.previewLoading ||
      this.previewSrc.length > 0) {
      return
    }
    this.previewQueued = true
    this.previewLoading = true
    const version = this.previewVersion
    MermaidPreviewQueue.enqueue(async () => {
      this.previewQueued = false
      if (!this.componentAlive || this.activeTab != "preview") {
        this.previewLoading = false
        return
      }
      if (version != this.previewVersion) {
        this.previewLoading = false
        return
      }
      await this.loadInlinePreview(version)
    })
  }

  private async loadInlinePreview(version: number) {
    this.previewLoading = true
    this.previewError = ""
    this.previewSrc = ""
    let renderTheme = this.getRenderTheme()
    try {
      const controller = MDBaseController.getMarkdownController(this.markdownUnion)
      renderTheme = controller.getMermaidTheme()
      const html = await buildMermaidHtml(getContext(), this.base?.text || "", this.resolveMermaidTheme(),
        controller.getMermaidSecurityLevel(), renderTheme)
      if (!this.componentAlive || version != this.previewVersion) {
        return
      }
      this.previewSrc = this.writeHtmlToCache(html)
    } catch (_err) {
      if (!this.componentAlive || version != this.previewVersion) {
        return
      }
      this.previewSrc = this.writeHtmlToCache(buildMermaidMissingHtml(renderTheme))
    }
    if (this.previewSrc.length == 0) {
      this.previewError = "Mermaid 预览加载失败"
      this.previewLoading = false
      this.releasePooledPreview()
    } else {
      this.acquirePooledPreview()
    }
  }

  private writeHtmlToCache(html: string): string {
    try {
      if (this.previewFilePath.length == 0) {
        this.previewFilePath =
          `${getContext().cacheDir}/lv_markdown_mermaid_preview_${Date.now()}_${Math.floor(Math.random() *
            100000)}.html`
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
    CodeDialogController.getInstance().openBindSheet(this.markdownUnion, this.base?.lang || "mermaid",
      this.base?.text || "")
  }

  private async openPreview() {
    if (this.loading) {
      return
    }
    this.loading = true
    let renderTheme = this.getRenderTheme()
    try {
      const controller = MDBaseController.getMarkdownController(this.markdownUnion)
      renderTheme = controller.getMermaidTheme()
      const html = await buildMermaidHtml(getContext(), this.base?.text || "", this.resolveMermaidTheme(),
        controller.getMermaidSecurityLevel(), renderTheme)
      await WebDialogController.getInstance().openHtmlBindSheet("Mermaid", html)
    } catch (_err) {
      await WebDialogController.getInstance().openHtmlBindSheet("Mermaid", buildMermaidMissingHtml(renderTheme))
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
        lang: this.base?.lang || "mermaid",
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
              this.enqueueInlinePreview()
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
                  .javaScriptAccess(true)
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
            } else if (this.previewError.length > 0) {
              Text(this.previewError)
                .fontSize(14)
                .fontColor(this.isDarkTheme() ? "#FFB4B4" : "#a8071a")
                .lineHeight(22)
                .padding(12)
            } else {
              LoadingProgress()
                .width(42)
                .height(42)
                .color(this.getLoadingColor())
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
              lang: this.base?.lang || "mermaid",
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
          .backgroundColor(CodeBlockImpl.handleBackgroundColor(this.getCodeBlockTheme()))
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
      .backgroundColor(CodeBlockImpl.handleBackgroundColor(this.getCodeBlockTheme()))
      .onVisibleAreaChange([0.01], (isVisible: boolean, currentRatio: number) => {
        this.previewVisible = isVisible || currentRatio > 0
        if (isVisible || currentRatio > 0) {
          this.enqueueInlinePreview()
          this.acquirePooledPreview()
        } else {
          this.releasePooledPreview()
        }
      })
    }
  }
}
