export const INDEX_TAB_ASSISTANTS: number = 0
export const INDEX_TAB_CHAT: number = 1
export const INDEX_TAB_KNOWLEDGE: number = 2
export const INDEX_TAB_SETTINGS: number = 3

export function shouldHideCompactTabsBarForIndex(currentTabIndex: number, currentSettingsRouteName: string,
  chatTabShowingChatPage: boolean): boolean {
  if (currentTabIndex === INDEX_TAB_SETTINGS && currentSettingsRouteName !== '') {
    return true
  }
  if (currentTabIndex === INDEX_TAB_CHAT && chatTabShowingChatPage) {
    return true
  }
  return false
}

export function shouldHideCompactTabsHostForIndex(currentTabIndex: number, isMultiSelectMode: boolean): boolean {
  if (currentTabIndex === INDEX_TAB_CHAT && isMultiSelectMode) {
    return true
  }
  return false
}
