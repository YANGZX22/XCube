import { webview } from '@kit.ArkWeb'
import { BrowserExecution, BuiltinBrowserService } from './BuiltinBrowserService'
import { BrowserRequest, isBrowserPageUrl } from './BuiltinBrowserPolicy'
import { getPreferencesService, PreferenceKeys } from './PreferencesService'

export interface BrowserPreferenceStore {
  getString(key: string, fallback: string): Promise<string>
  setString(key: string, value: string, throwOnError?: boolean): Promise<void>
  getBoolean(key: string, fallback: boolean): Promise<boolean>
  setBoolean(key: string, value: boolean, throwOnError?: boolean): Promise<void>
}

export interface BrowserDataStore {
  save(): Promise<void>
  clearSaved(): Promise<void>
  clearAllData(): Promise<void>
}

class ArkWebBrowserDataStore implements BrowserDataStore {
  async save(): Promise<void> {
    await webview.WebCookieManager.saveCookieAsync()
  }

  async clearSaved(): Promise<void> {
    await webview.WebCookieManager.clearAllCookies()
    await webview.WebCookieManager.saveCookieAsync()
  }

  async clearAllData(): Promise<void> {
    const failures: string[] = []
    try {
      await this.clearSaved()
    } catch (_error) {
      failures.push('Cookie')
    }
    try {
      webview.WebCookieManager.clearAllCookiesSync(true)
    } catch (_error) {
      failures.push('隐私 Cookie')
    }
    for (const incognito of [false, true]) {
      try {
        webview.WebStorage.deleteAllData(incognito)
      } catch (_error) {
        failures.push(incognito ? '隐私网页存储' : '网页存储')
      }
    }
    try {
      // Static API also clears disk/private caches when no browser page is mounted.
      webview.WebviewController.removeAllCache(true)
    } catch (_error) {
      failures.push('网页缓存')
    }
    if (failures.length > 0) throw new Error(`未能清空：${failures.join('、')}`)
  }
}

class SavedBrowserPage {
  sessionId: string
  url: string
  pageMode: string

  constructor(sessionId: string, url: string, pageMode: string = 'mobile') {
    this.sessionId = sessionId
    this.url = url
    this.pageMode = pageMode
  }
}

@ObservedV2
export class BuiltinBrowserManagerState {
  @Trace sessions: BuiltinBrowserService[] = []
  @Trace saveCookies: boolean = false
  @Trace changingCookies: boolean = false
  @Trace clearingData: boolean = false
  @Trace initialized: boolean = false
}

export class BuiltinBrowserManager {
  readonly state: BuiltinBrowserManagerState = new BuiltinBrowserManagerState()
  private sessions: Map<string, BuiltinBrowserService> = new Map()
  private savedPages: Map<string, SavedBrowserPage> = new Map()
  private preferences: BrowserPreferenceStore
  private browserData: BrowserDataStore
  private initialization: Promise<void> | null = null
  private writeChain: Promise<void> = Promise.resolve()
  private foreground: boolean = true
  private activeSessionId: string = ''

  constructor(preferences: BrowserPreferenceStore = getPreferencesService(),
    browserData: BrowserDataStore = new ArkWebBrowserDataStore()) {
    this.preferences = preferences
    this.browserData = browserData
  }

  async initialize(): Promise<void> {
    if (this.initialization === null) {
      this.initialization = this.loadPreferences()
    }
    await this.initialization
  }

  private async loadPreferences(): Promise<void> {
    this.state.saveCookies = await this.preferences.getBoolean(PreferenceKeys.BROWSER_SAVE_COOKIES, false)
    const raw = await this.preferences.getString(PreferenceKeys.BROWSER_OPEN_PAGES_JSON, '[]')
    try {
      const pages = JSON.parse(raw) as SavedBrowserPage[]
      if (Array.isArray(pages)) {
        for (const page of pages) {
          if (page !== null && typeof page.sessionId === 'string' && page.sessionId.trim() !== '' &&
            typeof page.url === 'string' && isBrowserPageUrl(page.url)) {
            this.savedPages.set(page.sessionId,
              new SavedBrowserPage(page.sessionId, page.url, page.pageMode === 'desktop' ? 'desktop' : 'mobile'))
          }
        }
      }
    } catch (_error) {
      console.warn('BuiltinBrowserManager', 'Ignored invalid saved browser pages')
    }
    this.state.initialized = true
    // A chat can bind its empty state while application services are still loading.
    this.sessions.forEach((browser: BuiltinBrowserService, sessionId: string): void => {
      this.configureSession(sessionId, browser)
    })
  }

  private configureSession(sessionId: string, browser: BuiltinBrowserService): void {
    const saved = this.savedPages.get(sessionId)
    browser.configure((): void => this.recordPage(sessionId, browser),
      (): boolean => this.presentSession(sessionId), this.state.saveCookies,
      saved === undefined ? 'about:blank' : saved.url, saved === undefined ? 'mobile' : saved.pageMode)
    browser.setForeground(this.foreground)
  }

  getSession(sessionId: string): BuiltinBrowserService {
    if (sessionId.trim() === '') throw new Error('请先打开一个会话')
    const existing = this.sessions.get(sessionId)
    if (existing !== undefined) return existing
    const browser = new BuiltinBrowserService()
    this.configureSession(sessionId, browser)
    this.sessions.set(sessionId, browser)
    this.state.sessions = [...this.state.sessions, browser]
    return browser
  }

  setActiveSession(sessionId: string): void {
    this.activeSessionId = sessionId
    this.sessions.forEach((browser: BuiltinBrowserService, id: string): void => {
      if (id !== sessionId && browser.state.visible) browser.hide()
    })
  }

  leaveSession(sessionId: string): void {
    if (this.activeSessionId === sessionId) this.setActiveSession('')
  }

  private presentSession(sessionId: string): boolean {
    if (this.activeSessionId !== sessionId) return false
    this.sessions.forEach((browser: BuiltinBrowserService, id: string): void => {
      if (id !== sessionId && browser.state.visible) browser.hide()
    })
    return true
  }

  async showForUser(sessionId: string): Promise<void> {
    await this.initialize()
    if (this.state.clearingData) throw new Error('正在清空浏览器数据，请稍后再试')
    this.setActiveSession(sessionId)
    this.getSession(sessionId).showForUser(sessionId)
  }

  requiresLaunchApproval(request: BrowserRequest, sessionId: string): boolean {
    const browser = this.sessions.get(sessionId)
    return browser === undefined ? request.action === 'open' : browser.requiresLaunchApproval(request)
  }

  async execute(request: BrowserRequest, sessionId: string, requestId: string,
    cancelled: () => boolean): Promise<BrowserExecution> {
    await this.initialize()
    if (this.state.clearingData) throw new Error('正在清空浏览器数据，请稍后再试')
    if (this.state.changingCookies) throw new Error('浏览器正在切换 Cookie 设置，请稍后再试')
    return this.getSession(sessionId).execute(request, sessionId, requestId, cancelled)
  }

  dismissOnBack(): boolean {
    for (const browser of this.state.sessions) {
      if (browser.dismissOnBack()) return true
    }
    return false
  }

  setForeground(foreground: boolean): void {
    this.foreground = foreground
    this.sessions.forEach((browser: BuiltinBrowserService): void => browser.setForeground(foreground))
    if (!foreground) this.flush().catch((): void => {
      console.warn('BuiltinBrowserManager', 'Could not finish saving browser state')
    })
  }

  endRequest(requestId: string): void {
    this.sessions.forEach((browser: BuiltinBrowserService): void => browser.endRequest(requestId))
  }

  async forgetSession(sessionId: string): Promise<void> {
    await this.initialize()
    const browser = this.sessions.get(sessionId)
    browser?.closeSession(sessionId)
    this.savedPages.delete(sessionId)
    this.sessions.delete(sessionId)
    this.state.sessions = this.state.sessions.filter((item: BuiltinBrowserService): boolean => item !== browser)
    if (this.activeSessionId === sessionId) this.activeSessionId = ''
    await this.persistPages()
  }

  private recordPage(sessionId: string, browser: BuiltinBrowserService): void {
    if (!this.state.initialized || this.state.clearingData) return
    const previous = this.savedPages.get(sessionId)
    const url = browser.state.rememberedUrl
    if (url === '') {
      if (previous === undefined) return
      this.savedPages.delete(sessionId)
    } else {
      if (previous !== undefined && previous.url === url && previous.pageMode === browser.state.pageMode) return
      this.savedPages.set(sessionId, new SavedBrowserPage(sessionId, url, browser.state.pageMode))
    }
    this.persistPages().catch((): void => {
      console.warn('BuiltinBrowserManager', 'Could not save browser page addresses')
    })
  }

  private persistPages(): Promise<void> {
    this.writeChain = this.writeChain.catch((): void => {}).then(async (): Promise<void> => {
      const pages: SavedBrowserPage[] = []
      this.savedPages.forEach((page: SavedBrowserPage): void => { pages.push(page) })
      await this.preferences.setString(PreferenceKeys.BROWSER_OPEN_PAGES_JSON, JSON.stringify(pages), true)
    })
    return this.writeChain
  }

  async setSaveCookies(enabled: boolean): Promise<void> {
    await this.initialize()
    if (this.state.clearingData) throw new Error('正在清空浏览器数据，请稍后再试')
    if (this.state.changingCookies || this.state.saveCookies === enabled) return
    if (this.state.sessions.some((browser: BuiltinBrowserService): boolean => browser.state.busy)) {
      throw new Error('浏览器正在操作，请稍后再切换')
    }
    this.state.changingCookies = true
    try {
      await this.preferences.setBoolean(PreferenceKeys.BROWSER_SAVE_COOKIES, enabled, true)
      this.state.saveCookies = enabled
      this.sessions.forEach((browser: BuiltinBrowserService): void => browser.changeCookieMode(enabled))
      if (!enabled) await this.browserData.clearSaved()
      await this.persistPages()
      if (enabled) await this.browserData.save()
    } finally {
      this.state.changingCookies = false
    }
  }

  async clearAllData(): Promise<void> {
    await this.initialize()
    if (this.state.clearingData || this.state.changingCookies) {
      throw new Error('浏览器设置正在更新，请稍后再试')
    }
    this.state.clearingData = true
    const failures: string[] = []
    try {
      this.savedPages.clear()
      // Cancel operations and destroy every live Web before deleting shared storage.
      // Keep the state objects bound to ChatPage so their active indicators update immediately.
      this.sessions.forEach((browser: BuiltinBrowserService, sessionId: string): void => {
        try {
          browser.closeSession(sessionId)
        } catch (_error) {
          failures.push('网页')
        }
        this.configureSession(sessionId, browser)
      })
      try {
        await this.persistPages()
      } catch (_error) {
        failures.push('网址')
      }
      try {
        await this.browserData.clearAllData()
      } catch (_error) {
        failures.push('网页缓存和 Cookie')
      }
      if (failures.length > 0) throw new Error(`部分浏览器数据未能清空：${failures.join('、')}`)
    } finally {
      this.state.clearingData = false
    }
  }

  async flush(): Promise<void> {
    // Lifecycle callbacks may arrive before PreferencesService has initialized.
    if (this.initialization === null) return
    await this.initialization
    await this.persistPages()
    if (this.state.saveCookies && !this.state.clearingData) await this.browserData.save()
  }
}

const browserManager: BuiltinBrowserManager = new BuiltinBrowserManager()

export function getBuiltinBrowserManager(): BuiltinBrowserManager {
  return browserManager
}
