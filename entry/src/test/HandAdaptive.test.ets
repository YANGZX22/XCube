import { describe, expect, it } from '@ohos/hypium'
import { motion } from '@kit.MultimodalAwarenessKit'
import { HandAdaptiveFollowTarget, normalizeHandAdaptiveFollowTarget } from '../main/ets/config/HandAdaptiveSettings'
import {
  isHandAdaptiveActiveForIndex,
  shouldPlaceCompactPlusOnLeftForIndex,
  shouldPlaceFabOnLeftForIndex
} from '../main/ets/pages/index/IndexHandAdaptiveHelper'

export default function handAdaptiveTest() {
  describe('HandAdaptive', () => {
    it('keeps_plus_following_as_default_and_validates_saved_target', 0, () => {
      expect(normalizeHandAdaptiveFollowTarget('')).assertEqual(HandAdaptiveFollowTarget.PLUS)
      expect(normalizeHandAdaptiveFollowTarget('invalid')).assertEqual(HandAdaptiveFollowTarget.PLUS)
      expect(normalizeHandAdaptiveFollowTarget('plus')).assertEqual(HandAdaptiveFollowTarget.PLUS)
      expect(normalizeHandAdaptiveFollowTarget('taskbar')).assertEqual(HandAdaptiveFollowTarget.TASKBAR)
    })

    it('plus_follows_holding_hand', 0, () => {
      expect(shouldPlaceCompactPlusOnLeftForIndex(true, HandAdaptiveFollowTarget.PLUS, false,
        motion.HoldingHandStatus.LEFT_HAND_HELD)).assertTrue()
      expect(shouldPlaceCompactPlusOnLeftForIndex(true, HandAdaptiveFollowTarget.PLUS, false,
        motion.HoldingHandStatus.RIGHT_HAND_HELD)).assertFalse()
    })

    it('taskbar_follows_holding_hand_with_plus_on_opposite_side', 0, () => {
      expect(shouldPlaceCompactPlusOnLeftForIndex(true, HandAdaptiveFollowTarget.TASKBAR, false,
        motion.HoldingHandStatus.LEFT_HAND_HELD)).assertFalse()
      expect(shouldPlaceCompactPlusOnLeftForIndex(true, HandAdaptiveFollowTarget.TASKBAR, false,
        motion.HoldingHandStatus.RIGHT_HAND_HELD)).assertTrue()
    })

    it('disabled_unsupported_and_unknown_use_default_positions', 0, () => {
      const targets: HandAdaptiveFollowTarget[] = [HandAdaptiveFollowTarget.PLUS, HandAdaptiveFollowTarget.TASKBAR]
      const hands: motion.HoldingHandStatus[] = [motion.HoldingHandStatus.LEFT_HAND_HELD,
        motion.HoldingHandStatus.RIGHT_HAND_HELD, motion.HoldingHandStatus.UNKNOWN_STATUS]
      for (const target of targets) {
        expect(shouldPlaceCompactPlusOnLeftForIndex(true, target, false,
          motion.HoldingHandStatus.UNKNOWN_STATUS)).assertFalse()
        for (const hand of hands) {
          expect(shouldPlaceCompactPlusOnLeftForIndex(false, target, false, hand)).assertFalse()
          expect(shouldPlaceCompactPlusOnLeftForIndex(true, target, true, hand)).assertFalse()
        }
      }
    })

    it('standalone_fab_only_follows_when_plus_is_selected', 0, () => {
      expect(shouldPlaceFabOnLeftForIndex(true, HandAdaptiveFollowTarget.PLUS, false,
        motion.HoldingHandStatus.LEFT_HAND_HELD)).assertTrue()
      expect(shouldPlaceFabOnLeftForIndex(true, HandAdaptiveFollowTarget.TASKBAR, false,
        motion.HoldingHandStatus.LEFT_HAND_HELD)).assertFalse()
      expect(shouldPlaceFabOnLeftForIndex(true, HandAdaptiveFollowTarget.PLUS, false,
        motion.HoldingHandStatus.RIGHT_HAND_HELD)).assertFalse()
      expect(shouldPlaceFabOnLeftForIndex(true, HandAdaptiveFollowTarget.PLUS, true,
        motion.HoldingHandStatus.LEFT_HAND_HELD)).assertFalse()
      expect(shouldPlaceFabOnLeftForIndex(false, HandAdaptiveFollowTarget.PLUS, false,
        motion.HoldingHandStatus.LEFT_HAND_HELD)).assertFalse()
    })

    it('motion_subscription_depends_on_master_switch_not_target', 0, () => {
      expect(isHandAdaptiveActiveForIndex(true)).assertTrue()
      expect(isHandAdaptiveActiveForIndex(false)).assertFalse()
    })
  })
}
