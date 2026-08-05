import { ColorTheme } from '../../models/ThemeColors'
import { SettingsSheetType } from './IndexPageTypes'

export function getSettingsSheetTitleText(sheetType: SettingsSheetType): Resource {
  if (sheetType === SettingsSheetType.THEME) {
    return $r('app.string.settings_appearance')
  }
  if (sheetType === SettingsSheetType.LANGUAGE) {
    return $r('app.string.settings_language')
  }
  if (sheetType === SettingsSheetType.HAND_ADAPTIVE) {
    return $r('app.string.hand_adaptive_title')
  }
  if (sheetType === SettingsSheetType.NOTIFICATION) {
    return $r('app.string.settings_notifications')
  }
  if (sheetType === SettingsSheetType.CHAT_INPUT) {
    return $r('app.string.settings_chat_input')
  }
  return $r('app.string.tab_settings')
}

export function getColorThemeDisplayTextForIndex(theme: ColorTheme): Resource {
  if (theme === ColorTheme.ATELIER) {
    return $r('app.string.theme_color_atelier')
  }
  if (theme === ColorTheme.LAVENDER) {
    return $r('app.string.theme_color_lavender')
  }
  if (theme === ColorTheme.CLAUDE) {
    return $r('app.string.theme_color_claude')
  }
  if (theme === ColorTheme.PORCELAIN) {
    return $r('app.string.theme_color_porcelain')
  }
  if (theme === ColorTheme.HERBARIUM) {
    return $r('app.string.theme_color_herbarium')
  }
  if (theme === ColorTheme.SALON) {
    return $r('app.string.theme_color_salon')
  }
  if (theme === ColorTheme.GALLERY) {
    return $r('app.string.theme_color_gallery')
  }
  if (theme === ColorTheme.NOCTURNE) {
    return $r('app.string.theme_color_nocturne')
  }
  return $r('app.string.theme_color_lavender')
}

export function getNotificationSummaryTextForIndex(notifyEnabled: boolean, notifyOnComplete: boolean,
  notifyOnFailed: boolean): Resource {
  if (!notifyEnabled) {
    return $r('app.string.notification_disabled')
  }
  if (notifyOnComplete && notifyOnFailed) {
    return $r('app.string.notification_summary_all')
  }
  if (notifyOnComplete) {
    return $r('app.string.notification_summary_complete')
  }
  if (notifyOnFailed) {
    return $r('app.string.notification_summary_failed')
  }
  return $r('app.string.notification_summary_none')
}
