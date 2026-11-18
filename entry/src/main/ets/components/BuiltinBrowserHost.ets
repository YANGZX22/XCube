import { ImmersiveInputSurface } from './ImmersiveInputSurface'
import { WRAPPED_MATERIAL_REGULAR } from '../utils/WrappedMaterialSupport'
import { BuilderNode, componentUtils, FrameNode, NodeController, UIContext } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { image } from '@kit.ImageKit'
import { util } from '@kit.ArkTS'
import { inputMethod } from '@kit.IMEKit'
import { IntentionCode, KeyCode } from '@kit.InputKit'
import { systemDateTime } from '@kit.BasicServicesKit'
import { AppUiState, getAppUiState } from '../state/AppUiState'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { getLocalizedBuiltinToolName } from '../utils/ToolDisplayTextUtils'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { InteractiveMaterialButton } from './InteractiveMaterialButton'
import { InteractiveMaterialRow } from './InteractiveMaterialRow'
import {
  BROWSER_VIEWPORT_CORNER_RADIUS, BROWSER_VIEWPORT_FLOW_WIDTH, BROWSER_VIEWPORT_FLOW_DURATION, BrowserEdgeFlowLight
} from './BrowserEdgeFlowLight'
import { assertBrowserPoint, buildBrowserUserAgent, isBrowserUrlAllowed } from '../services/BuiltinBrowserPolicy'
import { BROWSER_FOCUSED_EDITOR_SCRIPT, buildBrowserInsertTextScript, parseBrowserInputStatus } from '../services/BuiltinBrowserInput'
import { BrowserPageText, buildBrowserPageTextScript, buildBrowserFragmentScript, parseBrowserPageText } from '../services/BuiltinBrowserPage'
import {
  browserDelay, BrowserCapture, BrowserTypingResult, BuiltinBrowserHostAdapter, BuiltinBrowserService, BuiltinBrowserState
} from '../services/BuiltinBrowserService'
import { BuiltinBrowserManagerState } from '../services/BuiltinBrowserManager'

const MODEL_POINTER_ID: number = 787
const BROWSER_PRESENT_DURATION: number = 320
const BROWSER_DISMISS_DURATION: number = 260
const BROWSER_TOOLBAR_CONTROL_SIZE: number = 32
const BROWSER_HISTORY_BUTTON_WIDTH: number = 38
const BROWSER_ADDRESS_RADIUS: number = BROWSER_TOOLBAR_CONTROL_SIZE / 2

class BrowserBuilderParams {
  node: BrowserNodeController
  constructor(node: BrowserNodeController) {
    this.node = node
  }
}

@Builder
function BrowserWebBuilder(params: BrowserBuilderParams) {
  // Canvas rendering includes the Web content in component snapshots (not a separate surface).
  Web({ src: params.node.initialUrl, controller: params.node.web, renderMode: RenderMode.SYNC_RENDER,
    incognitoMode: !params.node.browser.state.saveCookies })
    .id(params.node.componentId)
    .width('100%')
    .height('100%')
    .javaScriptAccess(true)
    .domStorageAccess(true)
    .fileAccess(false)
    .geolocationAccess(false)
    .mixedMode(MixedMode.None)
    .multiWindowAccess(false)
    .onControllerAttached(() => params.node.attach())
    .onPageBegin((event) => params.node.pageChanged(event.url, true))
    .onPageEnd((event) => params.node.pageChanged(event.url, false))
    .onLoadFinished((event) => params.node.pageChanged(event.url, false))
    .onNavigationEntryCommitted((event) => params.node.navigationCommitted(event))
    .onRefreshAccessedHistory(() => params.node.syncHistoryAvailability())
    .onSearchResultReceive((event) => params.node.searchResult(event))
    .onProgressChange((event) => {
      if (params.node.isCurrent()) {
        params.node.browser.state.progress = event.newProgress
      }
    })
    .onTitleReceive((event) => {
      if (params.node.isCurrent()) {
        params.node.browser.state.title = event.title
      }
    })
    .onScroll(() => params.node.changed())
    .onAreaChange(() => params.node.changed())
    .onLoadIntercept((event) => !isBrowserUrlAllowed(event.data.getRequestUrl()) &&
      !(!event.data.isMainFrame() && event.data.getRequestUrl() === 'about:srcdoc'))
    .onPermissionRequest((event) => event.request.deny())
    .onErrorReceive((event) => {
      if (event.request.isMainFrame()) {
        params.node.failed(event.error.getErrorInfo())
      }
    })
    .onRenderExited(() => params.node.renderExited())
    .onInterceptKeyboardAttach((info): WebKeyboardOptions => params.node.keyboardAttached(info))
    // Only the model's scoped Enter dispatch bypasses the physical-keyboard takeover guard.
    .onKeyPreIme((event: KeyEvent): boolean => params.node.blockHardwareKey(event))
    .onBlur(() => params.node.handleBlur())
}

class BrowserNodeController extends NodeController implements BuiltinBrowserHostAdapter {
  browser: BuiltinBrowserService = new BuiltinBrowserService()
  readonly web: webview.WebviewController = new webview.WebviewController()
  componentId: string = ''
  generation: number = 0
  initialUrl: string = 'about:blank'
  private root: BuilderNode<[BrowserBuilderParams]> | null = null
  private ui: UIContext | null = null
  private keyboard: WebKeyboardController | null = null
  private modelKeyboardBuilder: (() => void) | null = null
  private defaultUserAgent: string = ''
  private dispatchingModelEnter: boolean = false
  private lastInputTimestamp: number = 0
  private navigationRevision: number = 0
  private initialNavigationPending: boolean = true
  private initialDocumentFinished: boolean = false
  private pendingNavigation: string = ''
  private navigationTarget: string = ''

  setModelKeyboardBuilder(builder: () => void): void {
    this.modelKeyboardBuilder = builder
  }

  makeNode(uiContext: UIContext): FrameNode | null {
    this.ui = uiContext
    this.componentId = `builtin-browser-web-${this.browser.instanceId}-${this.generation}`
    this.initialUrl = this.browser.state.initialUrl
    this.root = new BuilderNode<[BrowserBuilderParams]>(uiContext)
    this.root.build(wrapBuilder(BrowserWebBuilder), new BrowserBuilderParams(this))
    return this.root.getFrameNode()
  }

  isCurrent(): boolean {
    return this.browser.isCurrent(this.generation)
  }

  attach(): void {
    if (!this.isCurrent()) {
      return
    }
    try {
      this.setPageMode(this.browser.state.pageMode)
      this.browser.attach(this.generation, this)
      this.syncHistoryAvailability()
    } catch (error) {
      this.failed(`浏览器页面模式初始化失败，请关闭浏览器后重新打开：${error instanceof Error ? error.message : String(error)}`)
      this.browser.pause('page_mode_initialization_failed')
    }
  }

  setActive(active: boolean): void {
    if (this.browser.state.owner === 'model') {
      // Activating a background tab must not pop up the keyboard over the chat or another app.
      this.web.setSoftKeyboardBehaviorMode(webview.WebSoftKeyboardBehaviorMode.DISABLE_AUTO_KEYBOARD_ON_ACTIVE)
    } else {
      this.web.setSoftKeyboardBehaviorMode(webview.WebSoftKeyboardBehaviorMode.DEFAULT)
    }
    if (active) {
      this.web.onActive()
    } else {
      this.web.onInactive()
    }
  }

  handleBlur(): void {
    // Window/UI focus can move to chat while the DOM input stays focused. Keep the callback controller
    // for model typing; navigation and explicit handoff still reset it.
    if (this.browser.state.owner !== 'model') {
      this.resetKeyboard()
    }
  }

  destroy(): void {
    // Release the owning ArkUI component before closing native callbacks or disposing the Web subtree.
    this.modelKeyboardBuilder = null
    this.browser.detach(this.generation)
    this.resetKeyboard()
    this.root?.dispose()
    this.root = null
    this.ui = null
  }

  changed(): void {
    if (this.isCurrent()) {
      this.browser.invalidate()
    }
  }

  pageChanged(url: string, loading: boolean): void {
    if (!this.isCurrent()) {
      return
    }
    const state = this.browser.state
    if (!loading && url === this.initialUrl) {
      this.initialDocumentFinished = true
      if (this.pendingNavigation !== '') {
        const pending = this.pendingNavigation
        this.pendingNavigation = ''
        this.navigate(pending)
        return
      }
    }
    // A late bootstrap callback must not overwrite a requested HTTP navigation with about:blank.
    if (url === 'about:blank' && this.navigationTarget !== '' && this.navigationTarget !== 'about:blank') return
    // Completion callbacks may arrive after an editor has already focused. Do not discard its controller.
    if (loading || state.url !== url) {
      this.navigationRevision++
      this.resetKeyboard()
      state.findQuery = ''
      state.findDone = true
      state.findMatches = 0
    }
    state.url = url
    state.loading = loading
    if (loading) {
      state.error = ''
    }
    this.changed()
  }

  navigationCommitted(event: LoadCommittedDetails): void {
    if (!this.isCurrent() || !event.isMainFrame) return
    this.syncHistoryAvailability()
    if (event.isSameDocument) {
      const state = this.browser.state
      state.url = event.url
      state.loading = false
      this.changed()
    } else {
      this.pageChanged(event.url, true)
    }
  }

  syncHistoryAvailability(): void {
    if (!this.isCurrent()) return
    const state = this.browser.state
    try {
      state.canGoBack = this.web.accessBackward()
      state.canGoForward = this.web.accessForward()
    } catch (_error) {
      state.canGoBack = false
      state.canGoForward = false
    }
  }

  searchResult(event: OnSearchResultReceiveEvent): void {
    if (!this.isCurrent()) return
    const state = this.browser.state
    state.findMatches = event.numberOfMatches
    state.findDone = event.isDoneCounting
    this.changed()
  }

  failed(message: string): void {
    if (this.isCurrent()) {
      this.browser.state.error = message
      this.browser.state.loading = false
      this.changed()
    }
  }

  renderExited(): void {
    this.failed('网页渲染进程已退出，请关闭浏览器后重新打开')
    if (this.isCurrent()) {
      this.browser.pause('render_exited')
      this.browser.detach(this.generation)
    }
  }

  keyboardAttached(info: WebKeyboardCallbackInfo): WebKeyboardOptions {
    const controller = info.controller
    if (this.isCurrent() && this.modelKeyboardBuilder !== null) {
      this.keyboard = controller
      if (this.browser.state.owner === 'user') {
        return { useSystemKeyboard: true }
      }
    }
    return {
      useSystemKeyboard: false,
      customKeyboard: (): void => {
        // ArkWeb calls this later without a receiver. Use the tab-bound builder, never an unbound
        // global @Builder or this NodeController (neither supplies the owning ArkUI component).
        if (this.isCurrent() && this.browser.state.owner === 'model' &&
          this.keyboard === controller) {
          this.modelKeyboardBuilder?.()
        }
      }
    }
  }

  resetKeyboard(): void {
    const keyboard = this.keyboard
    this.keyboard = null
    try {
      keyboard?.close()
    } catch (_error) {}
  }

  navigate(url: string): void {
    if (!isBrowserUrlAllowed(url)) {
      throw new Error('浏览器仅支持 HTTP/HTTPS 网页')
    }
    this.navigationTarget = url
    this.pendingNavigation = ''
    const state = this.browser.state
    const current = this.web.getUrl()
    if (this.initialNavigationPending) {
      this.initialNavigationPending = false
      // The first model URL is Web.src itself. Do not race it with a second loadUrl/blank navigation.
      if (url === this.initialUrl) return
    }
    // A user may open the empty browser and immediately navigate. Keep only the latest request
    // until the bootstrap document finishes, instead of racing its initial Web.src.
    if (url !== 'about:blank' && this.initialUrl === 'about:blank' && current === 'about:blank' && !this.initialDocumentFinished) {
      this.pendingNavigation = url
      state.loading = true
      this.changed()
      return
    }
    if (url.includes('#') && current.split('#')[0] === url.split('#')[0]) {
      const revision = ++this.navigationRevision
      state.loading = true
      state.error = ''
      this.changed()
      this.web.runJavaScript(buildBrowserFragmentScript(url, Date.now() + 2000)).then((raw: string): void => {
        if (!this.isCurrent() || this.navigationRevision !== revision) return
        const status = raw.startsWith('"') ? JSON.parse(raw) as string : raw
        state.url = this.web.getUrl()
        state.loading = false
        if (status !== 'moved') {
          state.error = '片段地址已请求，但未确认锚点位置；不要猜测锚点或反复 open，可用 find 按章节标题定位。'
        }
        this.changed()
      }).catch((_error: Error): void => {
        if (!this.isCurrent() || this.navigationRevision !== revision) return
        this.failed('页内锚点跳转未确认，请用 find 按章节标题定位，不要反复重新加载页面')
      })
      return
    }
    state.loading = true
    state.title = ''
    state.error = ''
    state.progress = 0
    this.changed()
    this.web.loadUrl(url)
  }

  find(text: string): void {
    const state = this.browser.state
    state.error = ''
    if (state.findQuery === text && state.findDone && state.findMatches > 0) {
      this.web.searchNext(true)
    } else {
      state.findQuery = text
      state.findMatches = 0
      state.findDone = false
      this.web.searchAllAsync(text)
    }
  }

  async readPage(start: number, maxChars: number): Promise<BrowserPageText> {
    let timer: number = -1
    try {
      const timeout = new Promise<string>((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error('网页正文读取超时')), 4000)
      })
      const raw = await Promise.race([this.web.runJavaScript(buildBrowserPageTextScript(start, maxChars, Date.now() + 2000)), timeout])
      return parseBrowserPageText(raw, start, maxChars)
    } finally {
      if (timer !== -1) clearTimeout(timer)
    }
  }

  back(): void {
    if (!this.web.accessBackward()) {
      throw new Error('没有可后退的页面')
    }
    this.web.backward()
  }

  forward(): void {
    if (!this.web.accessForward()) {
      throw new Error('没有可前进的页面')
    }
    this.web.forward()
  }

  reload(): void {
    this.web.refresh()
  }

  setPageMode(pageMode: string): void {
    if (this.defaultUserAgent === '') {
      this.defaultUserAgent = this.web.getUserAgent()
    }
    this.resetKeyboard()
    const agent = buildBrowserUserAgent(this.defaultUserAgent, pageMode)
    const metadata = new webview.UserAgentMetadata()
    metadata.setMobile(pageMode === 'mobile')
    metadata.setFormFactors([pageMode === 'mobile' ? webview.UserAgentFormFactor.MOBILE :
      webview.UserAgentFormFactor.DESKTOP])
    this.web.setUserAgentMetadata(agent, metadata)
    // Only this tab changes. ArkWeb uses the Mobile token for meta-viewport handling.
    // The service reloads the current URL, or navigates once when used with open.
    this.web.setCustomUserAgent(agent)
  }

  private inputTimestamp(): number {
    // ArkUI can discard successive input events with the same timestamp.
    this.lastInputTimestamp = Math.max(this.lastInputTimestamp + 1000,
      systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE, true))
    return this.lastInputTimestamp
  }

  private touchEvent(rect: componentUtils.ComponentInfo, type: TouchType, x: number, y: number): TouchEvent {
    const windowX = rect.windowOffset.x + x
    const windowY = rect.windowOffset.y + y
    // Web is the BuilderNode root with no local offset. postTouchEvent consumes its local physical px,
    // independent of ancestor slide animations, window placement and front/background presentation.
    const point: TouchObject = {
      type: type, id: MODEL_POINTER_ID, x: x, y: y,
      windowX: windowX, windowY: windowY, screenX: windowX, screenY: windowY,
      displayX: rect.screenOffset.x + x, displayY: rect.screenOffset.y + y
    }
    return {
      type: type, touches: [point], changedTouches: [point],
      // Native input timestamps use monotonic uptime, not the wall-clock epoch.
      timestamp: this.inputTimestamp(),
      source: SourceType.TouchScreen, sourceTool: SourceTool.Finger,
      pressure: type === TouchType.Down || type === TouchType.Move ? 1 : 0, tiltX: 0, tiltY: 0,
      target: { area: { width: rect.size.width, height: rect.size.height,
        position: { x: 0, y: 0 }, globalPosition: { x: rect.windowOffset.x, y: rect.windowOffset.y } } },
      stopPropagation: (): void => {}, preventDefault: (): void => {},
      getHistoricalPoints: (): HistoricalPoint[] => []
    }
  }

  async click(x: number, y: number, shouldStop: () => boolean): Promise<void> {
    const ui = this.ui
    const root = this.root
    if (ui === null || root === null) {
      throw new Error('浏览器未挂载')
    }
    // Clicking the already-focused input need not attach the keyboard again. Keep the real controller;
    // type/capture probe the focused editor instead of treating a cached keyboard as proof of focus.
    const rect = ui.getComponentUtils().getRectangleById(this.componentId)
    assertBrowserPoint(x, y, rect.size.width, rect.size.height)
    const check = (): void => {
      if (shouldStop() || this.root !== root || this.ui !== ui) {
        throw new Error('点击已中止；操作可能已发生，恢复后请先重新截图')
      }
      const current = ui.getComponentUtils().getRectangleById(this.componentId)
      if (current.size.width !== rect.size.width || current.size.height !== rect.size.height) {
        throw new Error('点击期间视口发生变化，已中止；请重新截图')
      }
    }
    let started = false
    let completed = false
    try {
      check()
      started = true
      if (!root.postTouchEvent(this.touchEvent(rect, TouchType.Down, x, y))) {
        throw new Error('网页原生触摸派发失败（DOWN），不能据此判断是页面空白或浮层遮挡；请先 snapshot 确认，不要反复点击旧坐标')
      }
      // Give ArkWeb a frame to process the press before releasing it (including button/input focus).
      await browserDelay(50)
      check()
      if (!root.postTouchEvent(this.touchEvent(ui.getComponentUtils().getRectangleById(this.componentId), TouchType.Up, x, y))) {
        throw new Error('原生点击结束失败；操作可能已发生，请重新截图确认页面状态')
      }
      completed = true
    } finally {
      if (started && !completed) {
        // Do not turn a cancelled/failed press into a confirmation click.
        try {
          root.postTouchEvent(this.touchEvent(rect, TouchType.Cancel, x, y))
        } catch (_error) {}
      }
    }
  }

  async scroll(x: number, y: number, deltaX: number, deltaY: number, shouldStop: () => boolean): Promise<void> {
    const ui = this.ui
    const root = this.root
    if (ui === null || root === null) {
      throw new Error('浏览器未挂载')
    }
    const rect = ui.getComponentUtils().getRectangleById(this.componentId)
    assertBrowserPoint(x, y, rect.size.width, rect.size.height)
    const margin = Math.max(1, ui.vp2px(2))
    // A native gesture is hit-tested at its origin, so the inner scroller/iframe receives it.
    // Finger travel is opposite to content scrolling. Keep a single gesture inside the viewport;
    // do not repeat it blindly after the nested container reaches its boundary.
    let fraction = 1
    if (deltaX > 0) fraction = Math.min(fraction, (x - margin) / deltaX)
    if (deltaX < 0) fraction = Math.min(fraction, (rect.size.width - margin - x) / -deltaX)
    if (deltaY > 0) fraction = Math.min(fraction, (y - margin) / deltaY)
    if (deltaY < 0) fraction = Math.min(fraction, (rect.size.height - margin - y) / -deltaY)
    fraction = Math.max(0, fraction)
    const travelX = -deltaX * fraction
    const travelY = -deltaY * fraction
    const distance = Math.hypot(travelX, travelY)
    if (!Number.isFinite(distance) || distance < ui.vp2px(16)) {
      throw new Error('滚动距离太小或起点靠近视口边缘；请在目标滚动区域中部选取 x/y 并增大距离')
    }
    const check = (): void => {
      if (shouldStop() || this.root !== root || this.ui !== ui) {
        throw new Error('滚动已中止；部分滑动可能已发生，恢复后请先重新截图')
      }
      const current = ui.getComponentUtils().getRectangleById(this.componentId)
      if (current.size.width !== rect.size.width || current.size.height !== rect.size.height) {
        throw new Error('滚动期间视口发生变化，已中止；请重新截图')
      }
    }
    const steps = Math.max(8, Math.min(24, Math.ceil(distance / ui.vp2px(24))))
    let lastX = x
    let lastY = y
    let started = false
    let completed = false
    try {
      check()
      started = true
      if (!root.postTouchEvent(this.touchEvent(rect, TouchType.Down, x, y))) {
        throw new Error('网页原生滚动派发失败（DOWN），不代表页面没有可滚动元素；请先 snapshot 确认')
      }
      for (let step = 1; step <= steps; step++) {
        await browserDelay(16)
        check()
        lastX = x + travelX * step / steps
        lastY = y + travelY * step / steps
        if (!root.postTouchEvent(this.touchEvent(ui.getComponentUtils().getRectangleById(this.componentId), TouchType.Move, lastX, lastY))) {
          throw new Error('原生滚动派发失败，部分滑动可能已发生；请重新截图')
        }
      }
      // Pause at the endpoint to limit fling before capturing the result.
      await browserDelay(80)
      check()
      if (!root.postTouchEvent(this.touchEvent(ui.getComponentUtils().getRectangleById(this.componentId), TouchType.Up, lastX, lastY))) {
        throw new Error('原生滚动结束失败，请重新截图确认页面状态')
      }
      completed = true
    } finally {
      if (started && !completed) {
        // Release the pointer without clicking after cancellation, takeover or dispatch failure.
        try {
          root.postTouchEvent(this.touchEvent(rect, TouchType.Cancel, lastX, lastY))
        } catch (_error) {}
      }
    }
  }

  private async runInputScript(script: string): Promise<string> {
    let timer: number = -1
    try {
      const timeout = new Promise<string>((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error('网页输入响应超时，操作可能已发生；请先截图确认，不要重复输入')), 2500)
      })
      return parseBrowserInputStatus(await Promise.race([this.web.runJavaScript(script), timeout]))
    } finally {
      if (timer !== -1) clearTimeout(timer)
    }
  }

  private async focusedEditor(): Promise<string> {
    try {
      return await this.runInputScript(BROWSER_FOCUSED_EDITOR_SCRIPT)
    } catch (_error) {
      return 'opaque'
    }
  }

  blockHardwareKey(event: KeyEvent): boolean {
    if (this.browser.state.owner === 'user') return false
    return !(this.dispatchingModelEnter && event.keyCode === KeyCode.KEYCODE_ENTER &&
      (event.type === KeyType.Down || event.type === KeyType.Up))
  }

  private enterEvent(type: KeyType): KeyEvent {
    return {
      type: type, keyCode: KeyCode.KEYCODE_ENTER, keyText: 'Enter', keySource: KeySource.Keyboard,
      deviceId: -1, metaKey: 0, timestamp: this.inputTimestamp(),
      intentionCode: IntentionCode.INTENTION_UNKNOWN, stopPropagation: (): void => {}
    }
  }

  private dispatchEnter(): void {
    const ui = this.ui
    if (ui === null || this.root === null || this.componentId === '') {
      throw new Error('浏览器未挂载')
    }
    // Target only this Web node, even while hidden. No global key injection or focus stealing.
    // The return value is consumption, not submission success; never replay an unconsumed Enter.
    this.dispatchingModelEnter = true
    try {
      try {
        ui.dispatchKeyEvent(this.componentId, this.enterEvent(KeyType.Down))
      } finally {
        ui.dispatchKeyEvent(this.componentId, this.enterEvent(KeyType.Up))
      }
    } finally {
      this.dispatchingModelEnter = false
    }
  }

  async type(text: string, submit: boolean, shouldStop: () => boolean): Promise<BrowserTypingResult> {
    if (shouldStop()) throw new Error('浏览器输入已取消')
    const focus = await this.focusedEditor()
    if (shouldStop()) throw new Error('浏览器输入已取消')
    if (focus === 'none' && text !== '') {
      throw new Error('当前没有可编辑输入框获得焦点；请根据新截图 click 输入框')
    }
    const result = new BrowserTypingResult()
    // Enter alone also works on a focused button, without sending it to a stale text controller.
    const keyboard = focus === 'none' ? null : this.keyboard
    const ui = this.ui
    const root = this.root
    const navigationRevision = this.navigationRevision
    if (keyboard !== null) {
      result.inputMethod = 'native_keyboard'
      if (text !== '') {
        keyboard.insertText(text)
        result.textInserted = true
      }
      // Never retry through a second input channel after a native insert: that can duplicate text.
    } else {
      result.inputMethod = 'focused_element'
      if (text !== '') {
        if (focus !== 'editable') {
          throw new Error('无法访问当前输入框，且原生键盘通道未就绪（可能位于跨域 iframe 或封闭组件）；请重新点击输入框或等待用户接管')
        }
        // Desktop/background editors may be focused without ever asking the OS for a keyboard.
        // Only insert into that focused editor, with a short expiry for delayed WebView execution.
        const status = await this.runInputScript(buildBrowserInsertTextScript(text, Date.now() + 2000))
        if (status !== 'inserted') {
          throw new Error(`网页未确认输入（${status}），请先截图确认内容和焦点，不要直接重复输入`)
        }
        result.textInserted = true
      }
    }
    if (submit) {
      // Let the page consume the input event before it handles Enter.
      if (result.textInserted) await browserDelay(50)
      if (shouldStop()) throw new Error('浏览器输入已取消；文字可能已输入，未发送 Enter，请勿重复输入')
      if (this.ui !== ui || this.root !== root || this.navigationRevision !== navigationRevision ||
        (keyboard !== null && this.keyboard !== keyboard)) {
        result.message = '输入期间页面或输入框已切换，未发送 Enter；请根据新截图确认，不要重复输入。'
        return result
      }
      try {
        if (keyboard !== null) {
          // UNSPECIFIED is not a submit action. DONE matches ArkWeb's native IME return key.
          keyboard.sendFunctionKey(inputMethod.EnterKeyType.DONE)
        } else {
          this.dispatchEnter()
        }
        result.submitSent = true
      } catch (error) {
        // Preserve successful text insertion, but never auto-retry a possibly delivered submission.
        const reason = error instanceof Error ? error.message : String(error)
        result.message = `Enter 派发异常（${reason}），操作可能已发生；请先按新截图确认结果，不要重复输入或盲目重试提交。`
      }
    }
    return result
  }

  async capture(): Promise<BrowserCapture> {
    const ui = this.ui
    if (ui === null) {
      throw new Error('浏览器未挂载')
    }
    const rect = ui.getComponentUtils().getRectangleById(this.componentId)
    if (rect.size.width <= 0 || rect.size.height <= 0) {
      throw new Error('浏览器视口为空')
    }
    let pixels: image.PixelMap | null = null
    let packer: image.ImagePacker | null = null
    try {
      const scale = Math.min(1, 1600 / Math.max(rect.size.width, rect.size.height))
      pixels = await ui.getComponentSnapshot().get(this.componentId, { scale: scale, waitUntilRenderFinished: true })
      const info = await pixels.getImageInfo()
      packer = image.createImagePacker()
      const bytes = await packer.packToData(pixels, { format: 'image/jpeg', quality: 80 })
      if (bytes.byteLength > 4 * 1024 * 1024) {
        throw new Error('网页截图过大，请缩小浏览器窗口后重试')
      }
      const result = new BrowserCapture()
      result.base64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes))
      result.bytes = bytes.byteLength
      result.width = info.size.width
      result.height = info.size.height
      result.viewportWidth = rect.size.width
      result.viewportHeight = rect.size.height
      result.url = this.web.getUrl()
      result.title = this.web.getTitle()
      const focus = await this.focusedEditor()
      result.focusedEditable = focus === 'editable' || (focus === 'opaque' && this.keyboard !== null)
      return result
    } finally {
      try {
        if (packer !== null) {
          await packer.release()
        }
      } finally {
        if (pixels !== null) {
          await pixels.release()
        }
      }
    }
  }
}

@ComponentV2
struct BuiltinBrowserTab {
  @Param browser: BuiltinBrowserService = new BuiltinBrowserService()
  @Param generation: number = 0
  private node: BrowserNodeController = new BrowserNodeController()

  aboutToAppear(): void {
    this.node.browser = this.browser
    this.node.generation = this.generation
    this.node.setModelKeyboardBuilder(this.ModelKeyboard.bind(this))
  }

  aboutToDisappear(): void {
    this.node.destroy()
  }

  @Builder
  private ModelKeyboard() {
    Row().width('100%').height(1)
  }

  build() {
    NodeContainer(this.node).width('100%').height('100%')
  }
}

@ComponentV2
export struct BuiltinBrowserHost {
  @Param browser: BuiltinBrowserService = new BuiltinBrowserService()
  @Param state: BuiltinBrowserState = new BuiltinBrowserState()
  @Local appState: AppUiState = getAppUiState()
  @Local address: string = ''
  @Local addressEditing: boolean = false
  @Local presentationOffset: string = '0%'
  @Local presentationOnTop: boolean = false
  private presentationTimer: number = -1
  private presentationSequence: number = 0

  aboutToAppear(): void {
    this.syncPresentation()
  }

  aboutToDisappear(): void {
    this.stopPresentation()
  }

  @Monitor('state.visible', 'state.generation')
  onPresentationChanged(): void {
    this.syncPresentation()
  }

  private cancelPresentationCallbacks(): void {
    this.presentationSequence++
    if (this.presentationTimer !== -1) {
      clearTimeout(this.presentationTimer)
      this.presentationTimer = -1
    }
  }

  private stopPresentation(): void {
    this.cancelPresentationCallbacks()
    // Return the same Web to its normal position behind the chat for background model operations.
    this.presentationOnTop = false
    try {
      this.getUIContext().animateTo({ duration: 0 }, (): void => {
        this.presentationOffset = '0%'
      })
    } catch (_error) {
      this.presentationOffset = '0%'
    }
  }

  private syncPresentation(): void {
    this.cancelPresentationCallbacks()
    if (this.state.sessionId === '' || (!this.state.visible && !this.presentationOnTop)) {
      this.stopPresentation()
      return
    }
    const sequence = this.presentationSequence
    if (!this.state.visible) {
      // Only the visual layer remains on top during dismissal. Service visibility changes immediately;
      // the existing Web, model ownership, execution and screenshot flow are untouched.
      this.presentationTimer = setTimeout((): void => this.finishDismissal(sequence), BROWSER_DISMISS_DURATION + 64)
      this.animatePresentation(sequence, false)
      return
    }
    if (this.presentationOnTop) {
      // Reopening midway through dismissal reverses from the current rendered position.
      this.animatePresentation(sequence, true)
      return
    }
    this.presentationOnTop = true
    this.presentationOffset = '100%'
    // Commit the below-screen position before starting the render-thread animation.
    this.presentationTimer = setTimeout((): void => {
      this.presentationTimer = -1
      this.animatePresentation(sequence, true)
    }, 16)
  }

  private finishDismissal(sequence: number): void {
    if (sequence === this.presentationSequence && !this.state.visible) {
      this.stopPresentation()
    }
  }

  private animatePresentation(sequence: number, showing: boolean): void {
    if (sequence !== this.presentationSequence || this.state.visible !== showing || this.state.sessionId === '') return
    try {
      this.getUIContext().animateTo({
        duration: showing ? BROWSER_PRESENT_DURATION : BROWSER_DISMISS_DURATION,
        curve: showing ? Curve.EaseOut : Curve.EaseIn,
        onFinish: (): void => {
          if (!showing) this.finishDismissal(sequence)
        }
      }, (): void => {
        this.presentationOffset = showing ? '0%' : '100%'
      })
    } catch (_error) {
      this.stopPresentation()
      this.presentationOnTop = this.state.visible && this.state.sessionId !== ''
    }
  }

  @Monitor('state.url')
  onUrlChanged(): void {
    if (!this.addressEditing) {
      this.address = this.state.url === 'about:blank' ? '' : this.state.url
    }
  }

  private navigate(): void {
    const value = this.address.trim()
    if (value === '') {
      return
    }
    this.addressEditing = false
    this.perform(() => this.browser.userNavigate(
      /^[a-z][a-z0-9+.-]*:/i.test(value) ? value : `https://${value}`))
  }

  private perform(action: () => void): void {
    try {
      action()
    } catch (error) {
      this.state.error = error instanceof Error ? error.message : String(error)
    }
  }

  private canUseHistory(direction: 'back' | 'forward'): boolean {
    return this.state.owner === 'user' && (direction === 'back' ? this.state.canGoBack : this.state.canGoForward)
  }

  @Builder
  private HistoryButton(direction: 'back' | 'forward') {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      SymbolGlyph(direction === 'back' ? $r('sys.symbol.chevron_left') : $r('sys.symbol.chevron_right'))
        .fontSize(18).fontColor([this.appState.themeTextPrimary])
    }
    .width(BROWSER_HISTORY_BUTTON_WIDTH).height(BROWSER_TOOLBAR_CONTROL_SIZE)
    .borderRadius(direction === 'back' ? { topLeft: BROWSER_ADDRESS_RADIUS, bottomLeft: BROWSER_ADDRESS_RADIUS } :
      { topRight: BROWSER_ADDRESS_RADIUS, bottomRight: BROWSER_ADDRESS_RADIUS })
    .padding(0).backgroundColor(Color.Transparent)
    .enabled(this.canUseHistory(direction))
    .opacity(this.canUseHistory(direction) ? 1 : 0.35)
    .accessibilityText(direction === 'back' ? pickLocalizedText('后退', 'Back') : pickLocalizedText('前进', 'Forward'))
    .onClick(() => this.perform(() => this.browser.userNavigateHistory(direction)))
  }

  private getHeaderActionWidth(label: string, icon: Resource | null): number {
    if (icon !== null) {
      return BROWSER_TOOLBAR_CONTROL_SIZE
    }
    const uiContext = this.getUIContext()
    const size = uiContext.getMeasureUtils().measureTextSize({
      textContent: label, fontSize: 13, fontWeight: FontWeight.Medium
    })
    return Math.max(BROWSER_TOOLBAR_CONTROL_SIZE, Math.ceil(uiContext.px2vp(Number(size.width))) + 20)
  }

  @Builder
  private HeaderActionButton(getLabel: () => string, icon: Resource | null, color: string,
    foreground: ResourceColor, action: () => void) {
    Stack({ alignContent: Alignment.TopStart }) {
      // Material and touch handling belong to the same native Button, as on the send button.
      InteractiveMaterialButton({
        // Read the live label inside ArkUI's render callbacks so the mounted button tracks control changes.
        surfaceWidth: this.getHeaderActionWidth(getLabel(), icon),
        surfaceHeight: BROWSER_TOOLBAR_CONTROL_SIZE,
        buttonType: icon === null ? ButtonType.Capsule : ButtonType.Circle,
        materialColor: withColorAlpha(color, '40'),
        interactive: true,
        accessibilityLabel: getLabel(),
        onActivate: () => this.perform(action)
      }) {
        if (icon !== null) {
          SymbolGlyph(icon).fontSize(19).fontColor([foreground])
        } else {
          Text(getLabel()).fontSize(13).fontWeight(FontWeight.Medium).fontColor(foreground).maxLines(1)
        }
      }
    }
    .height(BROWSER_TOOLBAR_CONTROL_SIZE)
    .flexShrink(0)
    .clip(false)
  }

  private controlLabel(): string {
    if (this.state.owner === 'user') {
      return pickLocalizedText('用户接管中', 'You are in control')
    }
    if (this.state.owner === 'model') {
      return pickLocalizedText('模型控制', 'Model control')
    }
    if (this.state.owner === 'paused') {
      return this.state.pauseReason === 'awaiting_user'
        ? pickLocalizedText('等待用户操作', 'Waiting for you')
        : pickLocalizedText('已暂停', 'Paused')
    }
    return pickLocalizedText('就绪', 'Ready')
  }

  build() {
    Column() {
      if (this.state.sessionId !== '') {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(getLocalizedBuiltinToolName('builtin_browser')).fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor(this.appState.themeTextPrimary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.controlLabel())
              .fontSize(12).fontColor(this.appState.themeTextSecondary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          if (this.state.owner === 'paused') {
            this.HeaderActionButton(() => pickLocalizedText('继续模型', 'Resume'), null,
              this.appState.themePrimary, this.appState.themePrimary, () => this.browser.resume())
          }
          Row({ space: 8 }) {
            this.HeaderActionButton(() => pickLocalizedText('关闭浏览器', 'Close browser'), $r('sys.symbol.xmark'),
              '#EF4444', $r('app.color.status_error'),
              () => this.browser.closeSession(this.state.sessionId))
            this.HeaderActionButton(() => pickLocalizedText('隐藏浏览器', 'Hide browser'), $r('sys.symbol.chevron_down'),
              '#F5C542', '#F5C542', () => this.browser.hide())
            this.HeaderActionButton(() => this.state.owner === 'user' ? pickLocalizedText('交给模型', 'Give control') :
              pickLocalizedText('接管页面', 'Take over'), null, this.appState.themePrimary, this.appState.themePrimary, () => {
                if (this.state.owner === 'user') {
                  this.browser.resume()
                } else {
                  this.browser.takeOver()
                }
              })
          }.flexShrink(0)
        }.width('100%').padding({ left: 8, right: 8, top: 6, bottom: 6 })

        Row({ space: 6 }) {
          InteractiveMaterialRow({
            surfaceWidth: BROWSER_HISTORY_BUTTON_WIDTH * 2 + 1,
            surfaceHeight: BROWSER_TOOLBAR_CONTROL_SIZE,
            spacing: 0,
            horizontalPadding: 0
          }) {
            this.HistoryButton('back')
            Divider().vertical(true).width(1).strokeWidth(1).height(20)
              .color(this.appState.themeTextPrimary).opacity(0.16)
              .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
            this.HistoryButton('forward')
          }
          ImmersiveInputSurface({
            minSurfaceHeight: BROWSER_TOOLBAR_CONTROL_SIZE,
            maxSurfaceHeight: BROWSER_TOOLBAR_CONTROL_SIZE,
            cornerRadius: BROWSER_ADDRESS_RADIUS,
            materialStyle: WRAPPED_MATERIAL_REGULAR,
            applyShadow: true,
            layoutWeightValue: 1
          }) {
            TextInput({ text: this.address, placeholder: pickLocalizedText('输入网址', 'Enter URL') })
              .width('100%')
              .backgroundColor(Color.Transparent)
              .borderRadius(BROWSER_ADDRESS_RADIUS)
              .height(BROWSER_TOOLBAR_CONTROL_SIZE)
              .fontSize(14)
              .enterKeyType(EnterKeyType.Go)
              .enabled(this.state.owner === 'user')
              .onFocus(() => {
                this.addressEditing = true
              })
              .onChange((value: string) => { this.address = value })
              .onSubmit(() => this.navigate())
              .onBlur(() => { this.addressEditing = false })
          }
          InteractiveMaterialButton({
            surfaceWidth: BROWSER_TOOLBAR_CONTROL_SIZE,
            surfaceHeight: BROWSER_TOOLBAR_CONTROL_SIZE,
            buttonType: ButtonType.Circle,
            applyShadow: true,
            isEnabled: this.state.owner === 'user',
            accessibilityLabel: pickLocalizedText('刷新', 'Reload'),
            onActivate: () => this.perform(() => this.browser.userNavigateHistory('reload'))
          }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(19).fontColor([this.appState.themeTextPrimary])
          }
          InteractiveMaterialButton({
            surfaceWidth: BROWSER_TOOLBAR_CONTROL_SIZE,
            surfaceHeight: BROWSER_TOOLBAR_CONTROL_SIZE,
            buttonType: ButtonType.Circle,
            applyShadow: true,
            isEnabled: this.state.owner === 'user',
            accessibilityLabel: this.state.pageMode === 'desktop' ? pickLocalizedText('切换为手机版', 'Switch to mobile') :
              pickLocalizedText('切换为电脑版', 'Switch to desktop'),
            onActivate: () => this.perform(() => this.browser.userSetPageMode(
              this.state.pageMode === 'desktop' ? 'mobile' : 'desktop'))
          }) {
            SymbolGlyph(this.state.pageMode === 'desktop' ? $r('sys.symbol.computer') : $r('sys.symbol.phone_1'))
              .fontSize(19).fontColor([this.appState.themePrimary])
          }
        }.width('100%').padding({ left: 8, right: 8, bottom: 6 })

        Progress({ value: this.state.progress, total: 100, type: ProgressType.Linear })
          .width('100%').height(2).color(this.appState.themePrimary)
          .opacity(this.state.loading ? 1 : 0)
        if (this.state.error !== '') {
          Text(this.state.error).fontSize(12).fontColor(this.appState.themeTextSecondary)
            .width('100%').padding(8).maxLines(2)
        }
        if (this.state.waitingForUser) {
          Text(pickLocalizedText('点击“接管页面”操作，完成后交给模型', 'Tap Take over to interact, then Give control'))
            .fontSize(12).fontColor(this.appState.themePrimary).padding(8)
        }
        Stack() {
          ForEach([this.state.generation], (generation: number) => {
            BuiltinBrowserTab({ browser: this.browser, generation: generation })
          }, (generation: number): string => generation.toString())
          // This sibling blocks physical pointer/scroll input until explicit takeover.
          // Model events target the Web's BuilderNode directly, so they never hit this surface.
          if (this.state.owner !== 'user') {
            Column().width('100%').height('100%').backgroundColor(Color.Transparent)
              .hitTestBehavior(HitTestMode.Block)
          }
          // A sibling overlay never enters Web-only screenshots or intercepts model/user input.
          // Keep the glow through dismissal; destroy it once hidden, paused or handed over.
          if (this.presentationOnTop && this.state.modelRequestActive && this.state.owner === 'model') {
            BrowserEdgeFlowLight({
              cornerRadius: BROWSER_VIEWPORT_CORNER_RADIUS,
              edgeWidth: BROWSER_VIEWPORT_FLOW_WIDTH,
              animationDuration: BROWSER_VIEWPORT_FLOW_DURATION
            })
          }
        }
        .width('100%').layoutWeight(1)
        .borderRadius(BROWSER_VIEWPORT_CORNER_RADIUS)
        .clip(true)
      }
    }
    .width('100%').height('100%')
    // The full-screen root already reaches the navigation indicator. A second bottom inset
    // leaves an empty strip below Web; let the viewport fill the remaining height instead.
    .padding({ top: this.getUIContext().px2vp(this.appState.topAvoidHeight) })
    .backgroundColor(this.appState.themeBackground)
    .translate({ y: this.presentationOnTop ? this.presentationOffset : '0%' })
    // Keep a real, laid-out Web viewport behind the opaque main UI. Visibility.Hidden/opacity(0)
    // would stop painting or blank the component snapshot. Moving this same node preserves tab state.
    .visibility(this.state.sessionId !== '' ? Visibility.Visible : Visibility.Hidden)
    .hitTestBehavior(this.state.visible ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(this.state.visible ? 'auto' : 'no-hide-descendants')
    .zIndex(this.presentationOnTop ? 100 : -1)
  }
}

@Builder
export function BuiltinBrowserHosts(state: BuiltinBrowserManagerState) {
  ForEach(state.sessions, (browser: BuiltinBrowserService) => {
    BuiltinBrowserHost({ browser: browser, state: browser.state })
  }, (browser: BuiltinBrowserService): string => `${browser.instanceId}`)
}
