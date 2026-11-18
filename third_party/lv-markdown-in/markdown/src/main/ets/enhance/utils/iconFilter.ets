import { drawing } from '@kit.ArkGraphics2D'

/**
 * 按主题 token（如 {@link AppTheme.menuBarIconTint}）生成图标着色滤镜，用于 `Image.colorFilter(...)`。
 * - tint 为非空颜色（`#RRGGBB`）：用 SRC_IN 把图标整片染成该色，保留原图 alpha 形状
 * - tint 为空串：返回 DST 恒等滤镜（结果取原图、忽略源色），等价于不加滤镜，
 *   这样调用方可以无条件地 `.colorFilter(iconColorFilter(...))`，不必处理 undefined
 */
export function iconColorFilter(tint: string): drawing.ColorFilter {
  const value: string = tint.trim()
  if (value.length > 0) {
    const hex: string = value.startsWith('#') ? value.substring(1) : value
    const toByte = (s: string): number => {
      const n: number = parseInt(s, 16)
      return Number.isNaN(n) ? 255 : n
    }
    const r: number = hex.length >= 6 ? toByte(hex.substring(0, 2)) : 255
    const g: number = hex.length >= 6 ? toByte(hex.substring(2, 4)) : 255
    const b: number = hex.length >= 6 ? toByte(hex.substring(4, 6)) : 255
    return drawing.ColorFilter.createBlendModeColorFilter({ alpha: 255, red: r, green: g, blue: b },
      drawing.BlendMode.SRC_IN)
  }
  return drawing.ColorFilter.createBlendModeColorFilter({ alpha: 0, red: 0, green: 0, blue: 0 }, drawing.BlendMode.DST)
}
