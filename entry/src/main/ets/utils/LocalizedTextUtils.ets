import { i18n } from '@kit.LocalizationKit'
import { AppLanguage, normalizeAppLanguageValue } from '../services/PreferencesService'
import { getSettingsManager } from '../viewmodels/SettingsManager'
import { PromptLanguage, resolvePromptLanguage } from './PromptLanguageUtils'
import { buildAnnotatedRequest, formatAnnotatedMessage, ReplyAnnotation } from '../models/ReplyAnnotation'

export function getAnnotatedDisplayText(text: string, annotationCount: number): string {
  return annotationCount > 0 ? formatAnnotatedMessage(text, annotationCount, getAppPromptLanguage()) : text
}

export function getAnnotatedRequestText(text: string, annotations: ReplyAnnotation[]): string {
  return annotations.length > 0 ? buildAnnotatedRequest(text, annotations, getAppPromptLanguage()) : text
}

export function getAppPromptLanguage(): PromptLanguage {
  return resolvePromptLanguage(getSettingsManager().getLanguage(), i18n.System.getSystemLanguage())
}

export function resolveCurrentAppLanguage(): AppLanguage {
  const storedLanguage = getSettingsManager().getLanguage()
  if (storedLanguage !== AppLanguage.SYSTEM) {
    return storedLanguage
  }
  return normalizeAppLanguageValue(i18n.System.getSystemLanguage())
}

export function isChineseAppLanguage(): boolean {
  return resolveCurrentAppLanguage() === AppLanguage.ZH_CN
}

export function pickLocalizedText(chineseText: string, englishText: string): string {
  return isChineseAppLanguage() ? chineseText : englishText
}

export function formatLocalizedCount(
  count: number,
  chineseUnit: string,
  englishSingular: string,
  englishPlural: string
): string {
  if (isChineseAppLanguage()) {
    return `${count} ${chineseUnit}`
  }
  return `${count} ${count === 1 ? englishSingular : englishPlural}`
}
