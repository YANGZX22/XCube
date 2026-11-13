import { motion } from '@kit.MultimodalAwarenessKit'
import { HandAdaptiveFollowTarget } from '../../config/HandAdaptiveSettings'

export const INDEX_NEW_CHAT_FAB_SIZE = 58
export const INDEX_NEW_CHAT_FAB_STACK_WIDTH = 58
export const INDEX_NEW_CHAT_FAB_STACK_HEIGHT = 58
export const INDEX_NEW_CHAT_FAB_BOTTOM_SPACING = 20

export function isHandAdaptiveActiveForIndex(enabled: boolean): boolean {
  return enabled
}

export function shouldPlaceFabOnLeftForIndex(handAdaptiveEnabled: boolean, followTarget: HandAdaptiveFollowTarget,
  handAdaptiveUnsupported: boolean, currentHoldingHand: motion.HoldingHandStatus): boolean {
  if (!handAdaptiveEnabled || followTarget !== HandAdaptiveFollowTarget.PLUS || handAdaptiveUnsupported) {
    return false
  }
  return currentHoldingHand === motion.HoldingHandStatus.LEFT_HAND_HELD
}

export function shouldPlaceCompactPlusOnLeftForIndex(enabled: boolean, followTarget: HandAdaptiveFollowTarget,
  unsupported: boolean, holdingHand: motion.HoldingHandStatus): boolean {
  if (!enabled || unsupported) {
    return false
  }
  if (followTarget === HandAdaptiveFollowTarget.TASKBAR) {
    // 任务栏与加号位于相反两侧；右手握持时把任务栏放到右侧。
    return holdingHand === motion.HoldingHandStatus.RIGHT_HAND_HELD
  }
  return holdingHand === motion.HoldingHandStatus.LEFT_HAND_HELD
}

export function getFabOffsetXForIndex(placeOnLeft: boolean): number {
  if (placeOnLeft) {
    return 20
  }
  return -(INDEX_NEW_CHAT_FAB_SIZE + 20)
}

export function getFabOffsetYForIndex(bottomOverlayHeightVp: number): number {
  return -(INDEX_NEW_CHAT_FAB_STACK_HEIGHT + bottomOverlayHeightVp + INDEX_NEW_CHAT_FAB_BOTTOM_SPACING)
}
