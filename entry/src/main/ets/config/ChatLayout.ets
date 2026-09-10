export const CHAT_NAVIGATION_BAR_DEFAULT_HEIGHT: number = 44
export const CHAT_NAVIGATION_BAR_MIN_HEIGHT: number = 44
// 提示优先占用输入栏原有底部留白；不足时仅补齐差额，避免进入键盘/附件按钮区域。
export const CHAT_AI_NOTICE_MIN_HEIGHT_VP: number = 28

export function getChatAiNoticeExtraInsetVp(bottomAvoidHeightVp: number): number {
  return Math.max(0, CHAT_AI_NOTICE_MIN_HEIGHT_VP - (bottomAvoidHeightVp + 4))
}
