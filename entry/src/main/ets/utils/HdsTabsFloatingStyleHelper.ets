import { HdsTabsFloatingStyle, HdsBarWidthRangeOptions } from '@kit.UIDesignKit'
import { getHdsSystemMaterialEffect, getHdsMaterialLightColor } from './HdsMaterialSupport'

const DEFAULT_BAR_WIDTH: HdsBarWidthRangeOptions = {
  smallWidth: 248,
  mediumWidth: 278,
  largeWidth: 312
}

export class CompactTabsFloatingStyleOptions {
  materialType: number = 100
  materialLevel: number = 10
  lightColorMode: string = 'default'
  themePrimary: string = ''
  barSideMargin: number = 16
  barBottomMargin: number = 0
  barWidth: HdsBarWidthRangeOptions = DEFAULT_BAR_WIDTH
}

export function buildCompactTabsFloatingStyle(opts: CompactTabsFloatingStyleOptions): HdsTabsFloatingStyle {
  return {
    barWidth: opts.barWidth,
    barSideMargin: opts.barSideMargin,
    barBottomMargin: opts.barBottomMargin,
    systemMaterialEffect: getHdsSystemMaterialEffect(opts.materialType, opts.materialLevel),
    lightColor: opts.lightColorMode === 'theme' ? getHdsMaterialLightColor(opts.themePrimary) : undefined
  }
}
