import {
  ALL_THEMES,
  ColorTheme,
  getManuscriptColors,
  getThemeById,
  getThemeColors,
  normalizeVisualEffectsMode,
  resolveColorThemeId,
  ThemeColorConfig,
  ThemeInfo,
  VisualEffectsMode
} from '../models/ThemeColors'
import { getPreferencesService } from './PreferencesService'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { applyThemeToAppUiState, setAppUiStateValue } from '../state/AppUiState'
import { refreshAllThemeAwareForms } from '../utils/FormThemeSyncUtils'

// 主题变化回调接口
export interface ThemeColorChangeCallback {
  onColorThemeChanged: (theme: ColorTheme, colors: ThemeColorConfig) => void
}

// AppStorage 中的主题颜色键名
export class ThemeStorageKeys {
  static readonly COLOR_THEME: string = AppStorageKeys.COLOR_THEME
  static readonly THEME_PRIMARY: string = AppStorageKeys.THEME_PRIMARY
  static readonly THEME_PRIMARY_LIGHT: string = AppStorageKeys.THEME_PRIMARY_LIGHT
  static readonly THEME_BACKGROUND: string = AppStorageKeys.THEME_BACKGROUND
  static readonly THEME_SURFACE: string = AppStorageKeys.THEME_SURFACE
  static readonly THEME_DIVIDER: string = AppStorageKeys.THEME_DIVIDER
  static readonly THEME_USER_BUBBLE: string = AppStorageKeys.THEME_USER_BUBBLE
  static readonly THEME_USER_BUBBLE_TEXT: string = AppStorageKeys.THEME_USER_BUBBLE_TEXT
  static readonly THEME_AI_BUBBLE: string = AppStorageKeys.THEME_AI_BUBBLE
  static readonly THEME_TEXT_PRIMARY: string = AppStorageKeys.THEME_TEXT_PRIMARY
  static readonly THEME_TEXT_SECONDARY: string = AppStorageKeys.THEME_TEXT_SECONDARY
  static readonly THEME_TEXT_TERTIARY: string = AppStorageKeys.THEME_TEXT_TERTIARY
  static readonly THEME_MARKDOWN_TITLE: string = AppStorageKeys.THEME_MARKDOWN_TITLE
  static readonly THEME_MARKDOWN_TEXT: string = AppStorageKeys.THEME_MARKDOWN_TEXT
  static readonly THEME_MARKDOWN_LINK: string = AppStorageKeys.THEME_MARKDOWN_LINK
  static readonly THEME_MARKDOWN_LINK_BG: string = AppStorageKeys.THEME_MARKDOWN_LINK_BG
  static readonly THEME_MARKDOWN_CODE_BG: string = AppStorageKeys.THEME_MARKDOWN_CODE_BG
  static readonly THEME_MARKDOWN_CODE_TEXT: string = AppStorageKeys.THEME_MARKDOWN_CODE_TEXT
  static readonly THEME_MARKDOWN_QUOTE_BG: string = AppStorageKeys.THEME_MARKDOWN_QUOTE_BG
  static readonly THEME_MARKDOWN_TABLE_BG: string = AppStorageKeys.THEME_MARKDOWN_TABLE_BG
  static readonly THEME_MARKDOWN_TABLE_HEADER_BG: string = AppStorageKeys.THEME_MARKDOWN_TABLE_HEADER_BG
  static readonly THEME_MARKDOWN_TABLE_ALT_BG: string = AppStorageKeys.THEME_MARKDOWN_TABLE_ALT_BG
  static readonly THEME_MARKDOWN_TABLE_BORDER: string = AppStorageKeys.THEME_MARKDOWN_TABLE_BORDER
}

// 偏好设置键名
const PREF_KEY_COLOR_THEME = AppStorageKeys.COLOR_THEME
const PREF_KEY_VISUAL_EFFECTS_MODE = AppStorageKeys.VISUAL_EFFECTS_MODE

// 主题服务 - 单例模式
export class ThemeService {
  private static instance: ThemeService | null = null
  private currentTheme: ColorTheme = ColorTheme.LAVENDER
  private currentVisualEffectsMode: VisualEffectsMode = VisualEffectsMode.OFF
  private currentIsDarkMode: boolean = false
  private callbacks: ThemeColorChangeCallback[] = []
  private isInitialized: boolean = false

  private constructor() {
  }

  static getInstance(): ThemeService {
    if (ThemeService.instance === null) {
      ThemeService.instance = new ThemeService()
    }
    return ThemeService.instance
  }

  // 初始化主题服务
  async initialize(isDarkMode: boolean): Promise<void> {
    if (this.isInitialized) {
      // 如果已初始化，只更新深浅模式
      if (this.currentIsDarkMode !== isDarkMode) {
        this.currentIsDarkMode = isDarkMode
        this.applyThemeToStorage(true)
        this.notifyCallbacks()
      }
      return
    }

    this.currentIsDarkMode = isDarkMode

    // 从偏好设置加载保存的主题
    const savedTheme = await getPreferencesService().getString(PREF_KEY_COLOR_THEME, ColorTheme.LAVENDER)
    const savedVisualEffectsMode = await getPreferencesService().getString(
      PREF_KEY_VISUAL_EFFECTS_MODE,
      VisualEffectsMode.OFF
    )

    this.currentTheme = resolveColorThemeId(savedTheme)
    this.currentVisualEffectsMode = normalizeVisualEffectsMode(savedVisualEffectsMode)
    if ((this.currentTheme as string) !== savedTheme) {
      console.info('ThemeService', `Migrating theme '${savedTheme}' to '${this.currentTheme}'`)
      await getPreferencesService().setString(PREF_KEY_COLOR_THEME, this.currentTheme)
    }

    // 应用主题到 AppStorage
    this.applyThemeToStorage()

    this.isInitialized = true
    console.info('ThemeService', `Initialized with theme: ${this.currentTheme}, isDarkMode: ${isDarkMode}`)
  }

  // 获取当前主题
  getColorTheme(): ColorTheme {
    return this.currentTheme
  }

  getVisualEffectsMode(): VisualEffectsMode {
    return this.currentVisualEffectsMode
  }

  // 获取当前主题信息
  getThemeInfo(): ThemeInfo {
    return getThemeById(this.currentTheme)
  }

  // 获取所有主题列表
  getAllThemes(): ThemeInfo[] {
    return ALL_THEMES
  }

  // 获取当前颜色配置
  getCurrentColors(): ThemeColorConfig {
    if (this.currentVisualEffectsMode === VisualEffectsMode.MANUSCRIPT) {
      return getManuscriptColors(this.currentIsDarkMode)
    }
    return getThemeColors(this.currentTheme, this.currentIsDarkMode)
  }

  async setVisualEffectsMode(mode: VisualEffectsMode): Promise<void> {
    const normalizedMode = normalizeVisualEffectsMode(mode as string)
    if (this.currentVisualEffectsMode === normalizedMode) {
      return
    }
    this.currentVisualEffectsMode = normalizedMode
    await getPreferencesService().setString(PREF_KEY_VISUAL_EFFECTS_MODE, normalizedMode)
    this.applyThemeToStorage(true, 550)
    this.notifyCallbacks()
  }

  // 设置主题
  async setColorTheme(theme: ColorTheme): Promise<void> {
    if (this.currentTheme === theme) {
      return
    }

    this.currentTheme = theme

    // 保存到偏好设置
    await getPreferencesService().setString(PREF_KEY_COLOR_THEME, theme)

    // 应用主题到 AppStorage
    this.applyThemeToStorage(true)
    await this.refreshDesktopForms()

    // 通知回调
    this.notifyCallbacks()

    console.info('ThemeService', `Theme changed to: ${theme}`)
  }

  // 重新从偏好设置加载主题（导入后刷新用）
  async reloadTheme(): Promise<void> {
    const savedTheme = await getPreferencesService().getString(PREF_KEY_COLOR_THEME, ColorTheme.LAVENDER)
    const savedVisualEffectsMode = await getPreferencesService().getString(
      PREF_KEY_VISUAL_EFFECTS_MODE,
      VisualEffectsMode.OFF
    )

    this.currentTheme = resolveColorThemeId(savedTheme)
    this.currentVisualEffectsMode = normalizeVisualEffectsMode(savedVisualEffectsMode)
    if ((this.currentTheme as string) !== savedTheme) {
      console.info('ThemeService', `Reload migrated theme '${savedTheme}' to '${this.currentTheme}'`)
      await getPreferencesService().setString(PREF_KEY_COLOR_THEME, this.currentTheme)
    }

    // 强制刷新 AppStorage 和通知回调
    this.applyThemeToStorage(true)
    await this.refreshDesktopForms()
    this.notifyCallbacks()

    console.info('ThemeService', `Theme reloaded: ${this.currentTheme}`)
  }

  // 更新深浅模式（由系统或用户设置触发）
  updateDarkMode(isDarkMode: boolean): void {
    if (this.currentIsDarkMode === isDarkMode) {
      return
    }

    this.currentIsDarkMode = isDarkMode

    // 重新应用主题到 AppStorage
    this.applyThemeToStorage(true)
    void this.refreshDesktopForms()

    // 通知回调
    this.notifyCallbacks()

    console.info('ThemeService', `Dark mode updated: ${isDarkMode}`)
  }

  // 注册主题变化回调
  registerCallback(callback: ThemeColorChangeCallback): void {
    this.callbacks.push(callback)
  }

  // 取消注册回调
  unregisterCallback(callback: ThemeColorChangeCallback): void {
    const index = this.callbacks.indexOf(callback)
    if (index >= 0) {
      this.callbacks.splice(index, 1)
    }
  }

  // 应用主题颜色到 AppStorage
  private applyThemeToStorage(animated: boolean = false, duration: number = 450): void {
    const colors = this.getCurrentColors()
    if (animated) {
      animateTo({ duration: duration, curve: Curve.EaseInOut }, () => {
        setAppUiStateValue(AppStorageKeys.VISUAL_EFFECTS_MODE, this.currentVisualEffectsMode)
        applyThemeToAppUiState(this.currentTheme, colors)
      })
      return
    }
    setAppUiStateValue(AppStorageKeys.VISUAL_EFFECTS_MODE, this.currentVisualEffectsMode)
    applyThemeToAppUiState(this.currentTheme, colors)
  }

  private async refreshDesktopForms(): Promise<void> {
    await refreshAllThemeAwareForms(this.currentTheme)
  }

  // 通知所有回调
  private notifyCallbacks(): void {
    const colors = this.getCurrentColors()
    for (let i = 0; i < this.callbacks.length; i++) {
      this.callbacks[i].onColorThemeChanged(this.currentTheme, colors)
    }
  }
}

// 导出单例获取方法
export function getThemeService(): ThemeService {
  return ThemeService.getInstance()
}
