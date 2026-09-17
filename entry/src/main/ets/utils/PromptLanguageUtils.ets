// 提示词语言跟随界面设置；回复语言仍由用户的要求决定。
export enum PromptLanguage {
  ZH_CN = 'zh-CN',
  EN_US = 'en-US'
}

export function resolvePromptLanguage(appLanguage: string, systemLanguage: string): PromptLanguage {
  const configured = appLanguage.replace(/_/g, '-').toLowerCase()
  const effective = configured === '' || configured === 'system' || configured === 'default'
    ? systemLanguage.replace(/_/g, '-').toLowerCase() : configured
  return effective.startsWith('zh') ? PromptLanguage.ZH_CN : PromptLanguage.EN_US
}

export function pickPromptText(language: PromptLanguage, chinese: string, english: string): string {
  return language === PromptLanguage.ZH_CN ? chinese : english
}
