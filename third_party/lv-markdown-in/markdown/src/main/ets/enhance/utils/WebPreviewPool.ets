import { webview } from '@kit.ArkWeb'
import { BuilderNode, FrameNode, NodeController, UIContext } from '@kit.ArkUI'

const WEB_PREVIEW_BLANK_URL = 'about://blank'
const WEB_PREVIEW_IDLE_TRIM_DELAY_MS = 30000

class WebPreviewPoolNodeData {
  src: string = WEB_PREVIEW_BLANK_URL
  controller: webview.WebviewController = new webview.WebviewController()
  javaScriptAccess: boolean = false
  onProgressChange: (progress: number) => void = (_progress: number) => {}
  onPageEnd: () => void = () => {}
}

@Builder
function WebPreviewPoolBuilder(data: WebPreviewPoolNodeData) {
  Column() {
    Web({ src: data.src, controller: data.controller })
      .mixedMode(MixedMode.All)
      .domStorageAccess(true)
      .javaScriptAccess(data.javaScriptAccess)
      .fileAccess(true)
      .overviewModeAccess(false)
      .width('100%')
      .height('100%')
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_ONLY,
        scrollBackward: NestedScrollMode.SELF_ONLY
      })
      .onPageBegin(() => {
        try {
          data.controller.onActive()
        } catch (_err) {
        }
      })
      .onProgressChange((event) => {
        data.onProgressChange(event.newProgress)
      })
      .onPageEnd(() => {
        data.onPageEnd()
      })
  }
  .width('100%')
  .height('100%')
}

export class WebPreviewNodeController extends NodeController {
  private rootNode: BuilderNode<WebPreviewPoolNodeData[]> | null = null
  private root: FrameNode | null = null
  private slot: WebPreviewPoolSlot

  constructor(slot: WebPreviewPoolSlot) {
    super()
    this.slot = slot
  }

  isBuilt(): boolean {
    return this.rootNode !== null
  }

  ensureBuilt(uiContext: UIContext): void {
    if (this.rootNode !== null) {
      return
    }
    this.rootNode = new BuilderNode(uiContext)
    this.rootNode.build(wrapBuilder<WebPreviewPoolNodeData[]>(WebPreviewPoolBuilder), this.slot.getNodeData())
  }

  updateData(): void {
    if (this.rootNode === null) {
      return
    }
    try {
      this.rootNode.update(this.slot.getNodeData())
    } catch (_err) {
    }
  }

  makeNode(uiContext: UIContext): FrameNode | null {
    try {
      this.ensureBuilt(uiContext)
      const frameNode = this.rootNode?.getFrameNode()
      if (!frameNode) {
        return null
      }
      const parent = frameNode.getParent()
      if (parent) {
        parent.removeChild(frameNode)
        this.root = null
      }
      this.root = new FrameNode(uiContext)
      this.root.appendChild(frameNode)
      this.slot.onMounted()
      return this.root
    } catch (_err) {
      return null
    }
  }

  aboutToDisappear(): void {
    this.slot.onDetached()
  }

  dispose(): void {
    if (this.rootNode === null) {
      return
    }
    try {
      const frameNode = this.rootNode.getFrameNode()
      const parent = frameNode?.getParent()
      if (frameNode && parent) {
        parent.removeChild(frameNode)
      }
      this.rootNode.dispose()
    } catch (_err) {
    }
    this.rootNode = null
    this.root = null
  }
}

export class WebPreviewPoolRequest {
  ownerKey: string
  src: string
  javaScriptAccess: boolean
  uiContext: UIContext
  initialSize: number = 2
  maxSize: number = 4
  idleRetain: number = 2
  onProgressChange: (progress: number) => void = (_progress: number) => {}
  onPageEnd: () => void = () => {}
  onAcquired: (slot: WebPreviewPoolSlot) => void = (_slot: WebPreviewPoolSlot) => {}

  constructor(ownerKey: string, src: string, javaScriptAccess: boolean, uiContext: UIContext) {
    this.ownerKey = ownerKey
    this.src = src
    this.javaScriptAccess = javaScriptAccess
    this.uiContext = uiContext
  }
}

export class WebPreviewPoolSlot {
  readonly id: number
  readonly nodeController: WebPreviewNodeController
  private data: WebPreviewPoolNodeData = new WebPreviewPoolNodeData()
  private webController: webview.WebviewController = new webview.WebviewController()
  private ownerKey: string = ''
  private busy: boolean = false
  private lastUsedAt: number = 0
  private mounted: boolean = false
  private pendingLoad: boolean = false

  constructor(id: number) {
    this.id = id
    this.data.controller = this.webController
    this.nodeController = new WebPreviewNodeController(this)
  }

  getNodeData(): WebPreviewPoolNodeData {
    return this.data
  }

  isBusy(): boolean {
    return this.busy
  }

  getOwnerKey(): string {
    return this.ownerKey
  }

  getLastUsedAt(): number {
    return this.lastUsedAt
  }

  preload(uiContext: UIContext): void {
    this.data.src = WEB_PREVIEW_BLANK_URL
    this.pendingLoad = false
    this.nodeController.ensureBuilt(uiContext)
    this.nodeController.updateData()
  }

  assign(request: WebPreviewPoolRequest): void {
    this.ownerKey = request.ownerKey
    this.busy = true
    this.lastUsedAt = Date.now()
    this.data.src = request.src
    this.data.javaScriptAccess = request.javaScriptAccess
    this.data.onProgressChange = request.onProgressChange
    this.data.onPageEnd = request.onPageEnd
    this.nodeController.ensureBuilt(request.uiContext)
    this.nodeController.updateData()
    if (this.mounted) {
      this.pendingLoad = false
      this.loadUrl(request.src)
    } else {
      this.pendingLoad = true
    }
  }

  release(ownerKey: string): boolean {
    if (this.ownerKey !== ownerKey) {
      return false
    }
    this.ownerKey = ''
    this.busy = false
    this.lastUsedAt = Date.now()
    this.pendingLoad = false
    this.data.onProgressChange = (_progress: number) => {}
    this.data.onPageEnd = () => {}
    this.onDetached()
    return true
  }

  onMounted(): void {
    this.mounted = true
    try {
      this.webController.onActive()
    } catch (_err) {
    }
    if (this.pendingLoad && this.data.src.length > 0) {
      this.pendingLoad = false
      this.loadUrl(this.data.src)
    }
  }

  onDetached(): void {
    this.mounted = false
    try {
      this.webController.onInactive()
    } catch (_err) {
    }
  }

  dispose(): void {
    this.nodeController.dispose()
    this.ownerKey = ''
    this.busy = false
    this.lastUsedAt = 0
    this.mounted = false
    this.pendingLoad = false
  }

  private loadUrl(src: string): void {
    if (src.length === 0) {
      return
    }
    try {
      this.webController.loadUrl(src)
    } catch (_err) {
    }
  }
}

export class WebPreviewPool {
  private static instance: WebPreviewPool | null = null
  private slots: WebPreviewPoolSlot[] = []
  private waitingRequests: WebPreviewPoolRequest[] = []
  private nextSlotId: number = 1
  private initialSize: number = 2
  private maxSize: number = 4
  private idleRetain: number = 2
  private trimTimer: number = -1
  private webEngineInitialized: boolean = false

  static getInstance(): WebPreviewPool {
    if (WebPreviewPool.instance === null) {
      WebPreviewPool.instance = new WebPreviewPool()
    }
    return WebPreviewPool.instance
  }

  preload(uiContext: UIContext, initialSize: number, maxSize: number, idleRetain: number): void {
    this.configure(initialSize, maxSize, idleRetain)
    this.ensureWebEngineInitialized()
    this.prepareInitialSlots(uiContext)
    if (initialSize > idleRetain) {
      this.scheduleTrimTimer()
    }
  }

  request(request: WebPreviewPoolRequest): WebPreviewPoolSlot | null {
    this.configure(request.initialSize, request.maxSize, request.idleRetain)
    this.ensureWebEngineInitialized()
    this.cancelTrimTimer()
    this.removeWaitingRequest(request.ownerKey)
    this.prepareInitialSlots(request.uiContext)

    const ownerSlot = this.findOwnerSlot(request.ownerKey)
    if (ownerSlot !== null) {
      ownerSlot.assign(request)
      return ownerSlot
    }

    let slot = this.findIdleSlot()
    if (slot === null && this.slots.length < this.maxSize) {
      slot = this.createSlot()
      slot.preload(request.uiContext)
    }
    if (slot !== null) {
      slot.assign(request)
      return slot
    }

    this.waitingRequests.push(request)
    return null
  }

  release(ownerKey: string): void {
    this.removeWaitingRequest(ownerKey)
    const slot = this.findOwnerSlot(ownerKey)
    if (slot === null || !slot.release(ownerKey)) {
      return
    }
    if (!this.assignWaitingRequest(slot)) {
      this.scheduleTrimTimer()
    }
  }

  cancel(ownerKey: string): void {
    this.removeWaitingRequest(ownerKey)
  }

  private configure(initialSize: number, maxSize: number, idleRetain: number): void {
    const safeMaxSize = Math.max(1, Math.floor(maxSize))
    const safeInitialSize = Math.min(Math.max(0, Math.floor(initialSize)), safeMaxSize)
    const safeIdleRetain = Math.min(Math.max(0, Math.floor(idleRetain)), safeMaxSize)
    this.initialSize = safeInitialSize
    this.maxSize = safeMaxSize
    this.idleRetain = safeIdleRetain
  }

  private ensureWebEngineInitialized(): void {
    if (this.webEngineInitialized) {
      return
    }
    try {
      webview.WebviewController.initializeWebEngine()
    } catch (_err) {
    }
    this.webEngineInitialized = true
  }

  private prepareInitialSlots(uiContext: UIContext): void {
    while (this.slots.length < this.initialSize) {
      const slot = this.createSlot()
      slot.preload(uiContext)
    }
    for (let i = 0; i < this.initialSize && i < this.slots.length; i++) {
      if (!this.slots[i].nodeController.isBuilt()) {
        this.slots[i].preload(uiContext)
      }
    }
  }

  private createSlot(): WebPreviewPoolSlot {
    const slot = new WebPreviewPoolSlot(this.nextSlotId)
    this.nextSlotId++
    this.slots.push(slot)
    return slot
  }

  private findOwnerSlot(ownerKey: string): WebPreviewPoolSlot | null {
    for (let i = 0; i < this.slots.length; i++) {
      if (this.slots[i].isBusy() && this.slots[i].getOwnerKey() === ownerKey) {
        return this.slots[i]
      }
    }
    return null
  }

  private findIdleSlot(): WebPreviewPoolSlot | null {
    let candidate: WebPreviewPoolSlot | null = null
    for (let i = 0; i < this.slots.length; i++) {
      if (this.slots[i].isBusy()) {
        continue
      }
      if (candidate === null || this.slots[i].getLastUsedAt() < candidate.getLastUsedAt()) {
        candidate = this.slots[i]
      }
    }
    return candidate
  }

  private assignWaitingRequest(releasedSlot: WebPreviewPoolSlot): boolean {
    while (this.waitingRequests.length > 0) {
      const request = this.waitingRequests.shift()
      if (!request) {
        continue
      }
      this.configure(request.initialSize, request.maxSize, request.idleRetain)
      let slot: WebPreviewPoolSlot | null = releasedSlot.isBusy() ? null : releasedSlot
      if (slot === null) {
        slot = this.findIdleSlot()
      }
      if (slot === null && this.slots.length < this.maxSize) {
        slot = this.createSlot()
        slot.preload(request.uiContext)
      }
      if (slot === null) {
        this.waitingRequests.unshift(request)
        return false
      }
      slot.assign(request)
      request.onAcquired(slot)
      return true
    }
    return false
  }

  private removeWaitingRequest(ownerKey: string): void {
    for (let i = this.waitingRequests.length - 1; i >= 0; i--) {
      if (this.waitingRequests[i].ownerKey === ownerKey) {
        this.waitingRequests.splice(i, 1)
      }
    }
  }

  private cancelTrimTimer(): void {
    if (this.trimTimer === -1) {
      return
    }
    clearTimeout(this.trimTimer)
    this.trimTimer = -1
  }

  private scheduleTrimTimer(): void {
    this.cancelTrimTimer()
    this.trimTimer = setTimeout(() => {
      this.trimTimer = -1
      this.trimIdleSlots()
    }, WEB_PREVIEW_IDLE_TRIM_DELAY_MS)
  }

  private trimIdleSlots(): void {
    if (this.waitingRequests.length > 0) {
      return
    }
    let idleCount = 0
    for (let i = 0; i < this.slots.length; i++) {
      if (!this.slots[i].isBusy()) {
        idleCount++
      }
    }
    for (let i = this.slots.length - 1; i >= 0 && idleCount > this.idleRetain; i--) {
      if (this.slots[i].isBusy()) {
        continue
      }
      this.slots[i].dispose()
      this.slots.splice(i, 1)
      idleCount--
    }
  }
}
