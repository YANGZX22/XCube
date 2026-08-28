/**
 * 时间线条目（工具结果条 / 思考条 / 搜索结果条）共用的动效参数。
 * 这些条目现在合并进同一个块内、用分割线相隔展示，
 * 插入、移除、展开、收起都需要统一节奏，避免同一块里出现两种速度。
 */

export const TIMELINE_BAR_INSERT_DURATION: number = 220
export const TIMELINE_BAR_REMOVE_DURATION: number = 150
export const TIMELINE_BLOCK_INSERT_DURATION: number = 260
export const TIMELINE_BLOCK_REMOVE_DURATION: number = 160
export const TIMELINE_BAR_EXPAND_DURATION: number = 220
export const TIMELINE_BAR_COLLAPSE_DURATION: number = 150

// 块内单条的增删动效：新条目自上方压入并淡入，移除时就地淡出，
// 让"又多了一条"读起来像是接在上一条后面，而不是整块跳变。
export function buildTimelineBarTransition(): TransitionEffect {
  return TransitionEffect.asymmetric(
    TransitionEffect.OPACITY
      .animation({ duration: TIMELINE_BAR_INSERT_DURATION, curve: Curve.Friction })
      .combine(TransitionEffect.translate({ y: -10 })),
    TransitionEffect.OPACITY
      .animation({ duration: TIMELINE_BAR_REMOVE_DURATION, curve: Curve.Sharp })
  )
}

// 整块（合并后的条目块）的增删动效：块比单条更重，入场稍慢并带轻微缩放
export function buildTimelineBlockTransition(): TransitionEffect {
  return TransitionEffect.asymmetric(
    TransitionEffect.OPACITY
      .animation({ duration: TIMELINE_BLOCK_INSERT_DURATION, curve: Curve.Friction })
      .combine(TransitionEffect.scale({ x: 1, y: 0.94, centerX: '50%', centerY: '0%' })),
    TransitionEffect.OPACITY
      .animation({ duration: TIMELINE_BLOCK_REMOVE_DURATION, curve: Curve.Sharp })
  )
}

// 条目详情展开 / 收起动效
export function buildTimelineBarExpandTransition(): TransitionEffect {
  return TransitionEffect.asymmetric(
    TransitionEffect.OPACITY
      .animation({ duration: TIMELINE_BAR_EXPAND_DURATION, curve: Curve.Friction })
      .combine(TransitionEffect.translate({ y: -8 })),
    TransitionEffect.OPACITY
      .animation({ duration: TIMELINE_BAR_COLLAPSE_DURATION, curve: Curve.Sharp })
  )
}

// 展开 / 收起时块高度变化的动画参数：与详情过渡同拍，避免内容先于高度落位
export function getTimelineBarExpandAnimation(): AnimateParam {
  return { duration: TIMELINE_BAR_EXPAND_DURATION, curve: Curve.Friction }
}
