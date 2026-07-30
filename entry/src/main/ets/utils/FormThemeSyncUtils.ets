import { Context, Want } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { formBindingData, formInfo, formProvider } from '@kit.FormKit'
import resourceManager from '@ohos.resourceManager'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { ColorTheme, ThemeColorConfig, getThemeColors } from '../models/ThemeColors'
import { getPreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { DEFAULT_PRIMARY_COLOR } from '../config/ThemeDefaults'

const FORM_IDS_PREF_KEY = 'entry_form_ids_json'
const PREFERENCES_NAME = 'chatbox_preferences'
const DEFAULT_THEME_PRIMARY = DEFAULT_PRIMARY_COLOR
const LIGHT_FORM_TEXT_COLOR = '#24211C'
const DARK_FORM_TEXT_COLOR = '#F3EFE6'

class NewChatFormData {
  title: string = '新对话'
  subtitle: string = '点击开始聊天'
  themePrimary: string = DEFAULT_THEME_PRIMARY
  surfaceColor: string = '#FEFDFF'
  textPrimary: string = '#24211C'
  textColor: string = ''
  glassBgColor: string = 'rgba(255,253,248,0.62)'
  shadowColor: string = 'rgba(78,58,35,0.08)'
  borderColor: string = 'rgba(255,255,255,0.76)'
}

function parseStoredFormIds(rawValue: string): string[] {
  try {
    const parsed = JSON.parse(rawValue) as Array<string>
    if (!Array.isArray(parsed)) {
      return []
    }
    const formIds: string[] = []
    for (let i = 0; i < parsed.length; i++) {
      const formId: string = parsed[i]
      if (formId !== '' && !formIds.includes(formId)) {
        formIds.push(formId)
      }
    }
    return formIds
  } catch (error) {
    console.error('FormThemeSyncUtils', `Failed to parse stored form ids: ${JSON.stringify(error)}`)
    return []
  }
}

async function getFormPreferences(context: Context): Promise<preferences.Preferences> {
  return await preferences.getPreferences(context, PREFERENCES_NAME)
}

async function readRegisteredFormIdsWithContext(context: Context): Promise<string[]> {
  const store = await getFormPreferences(context)
  const rawValue = await store.get(FORM_IDS_PREF_KEY, '[]') as string
  return parseStoredFormIds(rawValue)
}

async function writeRegisteredFormIds(context: Context, formIds: string[]): Promise<void> {
  const store = await getFormPreferences(context)
  await store.put(FORM_IDS_PREF_KEY, JSON.stringify(formIds))
  await store.flush()
}

export function readFormIdFromWant(want: Want): string {
  const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string | undefined
  return formId ?? ''
}

function resolveContextSystemDarkMode(context: Context): boolean {
  return context.resourceManager.getConfigurationSync().colorMode === resourceManager.ColorMode.DARK
}

export function createNewChatFormBindingData(colors: ThemeColorConfig, isSystemDarkMode?: boolean): formBindingData.FormBindingData {
  const formData = new NewChatFormData()
  formData.themePrimary = colors.primary
  formData.surfaceColor = colors.surface
  formData.textPrimary = colors.textPrimary
  // 玻璃色跟随系统深浅色，不跟随应用主题
  if (isSystemDarkMode === true) {
    formData.textColor = DARK_FORM_TEXT_COLOR
    // 深色模式使用暖灰玻璃，避免青色和应用主界面脱节。
    formData.glassBgColor = 'rgba(48,45,38,0.82)'
    formData.shadowColor = 'rgba(0,0,0,0.10)'
    formData.borderColor = 'rgba(243,239,230,0.14)'
  } else {
    formData.textColor = LIGHT_FORM_TEXT_COLOR
    // 浅色模式使用暖纸玻璃，保留通透但不发飘。
    formData.glassBgColor = 'rgba(255,253,248,0.62)'
    formData.shadowColor = 'rgba(78,58,35,0.08)'
    formData.borderColor = 'rgba(255,255,255,0.76)'
  }
  return formBindingData.createFormBindingData(formData)
}

export async function registerThemeAwareFormId(context: Context, formId: string): Promise<void> {
  if (formId === '') {
    return
  }
  const formIds = await readRegisteredFormIdsWithContext(context)
  if (formIds.includes(formId)) {
    return
  }
  formIds.push(formId)
  await writeRegisteredFormIds(context, formIds)
}

export async function unregisterThemeAwareFormId(context: Context, formId: string): Promise<void> {
  if (formId === '') {
    return
  }
  const formIds = await readRegisteredFormIdsWithContext(context)
  const nextFormIds: string[] = []
  for (let i = 0; i < formIds.length; i++) {
    if (formIds[i] !== formId) {
      nextFormIds.push(formIds[i])
    }
  }
  await writeRegisteredFormIds(context, nextFormIds)
}

async function resolveStoredSystemDarkMode(): Promise<boolean> {
  return await getPreferencesService().getBoolean(PreferenceKeys.SYSTEM_DARK_MODE, false)
}

async function loadStoredWidgetThemeId(): Promise<ColorTheme> {
  const themeId = await getPreferencesService().getString(AppStorageKeys.COLOR_THEME, ColorTheme.LAVENDER)
  return themeId as ColorTheme
}

export async function loadWidgetThemeColors(context: Context): Promise<ThemeColorConfig> {
  const store = await getFormPreferences(context)
  const themeId = await store.get(AppStorageKeys.COLOR_THEME, ColorTheme.LAVENDER) as string
  return getThemeColors(themeId as ColorTheme, resolveContextSystemDarkMode(context))
}

export async function refreshThemeAwareForm(formId: string, colors: ThemeColorConfig, isSystemDarkMode?: boolean): Promise<void> {
  if (formId === '') {
    return
  }
  await formProvider.updateForm(formId, createNewChatFormBindingData(colors, isSystemDarkMode))
}

export async function refreshThemeAwareFormWithStoredTheme(context: Context, formId: string): Promise<void> {
  const colors = await loadWidgetThemeColors(context)
  const isSystemDarkMode = resolveContextSystemDarkMode(context)
  await refreshThemeAwareForm(formId, colors, isSystemDarkMode)
}

export async function refreshAllThemeAwareForms(themeId?: ColorTheme): Promise<void> {
  const resolvedThemeId = themeId ?? await loadStoredWidgetThemeId()
  const isSystemDarkMode = await resolveStoredSystemDarkMode()
  const colors = getThemeColors(resolvedThemeId, isSystemDarkMode)
  const rawValue = await getPreferencesService().getString(FORM_IDS_PREF_KEY, '[]')
  const formIds = parseStoredFormIds(rawValue)
  for (let i = 0; i < formIds.length; i++) {
    try {
      await refreshThemeAwareForm(formIds[i], colors, isSystemDarkMode)
    } catch (error) {
      console.error('FormThemeSyncUtils', `Failed to refresh form ${formIds[i]}: ${JSON.stringify(error)}`)
    }
  }
}
