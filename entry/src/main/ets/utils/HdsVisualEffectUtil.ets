import uiEffect from '@ohos.graphics.uiEffect'
import { LengthMetrics } from '@kit.ArkUI'
import {
  HdsNavigationTitleBarOptions,
  HdsNavigationMenuItemOptions,
  ScrollEffectType,
  hdsEffect,
  hdsMaterial
} from '@kit.UIDesignKit'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from './ColorAlphaUtils'

const STATUS_BAR_CONTENT_LIGHT: string = '#1F2329'
const STATUS_BAR_CONTENT_DARK: string = '#F5F7FA'
const TITLE_BAR_BLUR_EFFECTIVE_START_OFFSET: number = 1e5
const TITLE_BAR_BLUR_EFFECTIVE_END_OFFSET: number = 2e5

export function buildPointLightBorderEffect(sourceBright: boolean = false): uiEffect.VisualEffect {
  return new hdsEffect.HdsEffectBuilder()
    .pointLight({
      sourceType: sourceBright ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
    })
    .buildEffect()
}

export class HdsTopNavigationBlurOptions {
  startPaddingVp: number = 0
  endPaddingVp: number = 0
  materialType: number = 100
  materialLevel: number = 10
  windowWidthVp: number = 0
  windowHeightVp: number = 0
  maskExtraHeightVp: number = 20
  blurEffectiveEndOffsetVp: number = TITLE_BAR_BLUR_EFFECTIVE_END_OFFSET
  menuItems: Array<HdsNavigationMenuItemOptions> = []
  // HdsNavigation 默认最多展示 3 个菜单图标，超出的会折叠进“更多”。
  // 需要平铺更多入口时由调用方显式抬高。
  menuMaxCount: number = 3
  stackBuilder: () => void = (): void => {}
}

export function getHdsTopNavigationMaskExtraHeight(windowWidthVp: number, windowHeightVp: number,
  portraitHeightVp: number = 20, landscapeHeightVp: number = 16): number {
  return windowWidthVp > windowHeightVp ? landscapeHeightVp : portraitHeightVp
}

export function getHdsTopNavigationBlurEffectiveEndOffset(windowWidthVp: number, windowHeightVp: number): number {
  return TITLE_BAR_BLUR_EFFECTIVE_END_OFFSET
}

export function getHdsTopNavigationContentTopPadding(topAvoidHeightVp: number, windowWidthVp: number,
  windowHeightVp: number, titleHeightVp: number = 56): number {
  return topAvoidHeightVp + titleHeightVp + getHdsTopNavigationMaskExtraHeight(windowWidthVp, windowHeightVp)
}

export function getHdsTopNavigationScrollEffectType(materialType: number): ScrollEffectType {
  return ScrollEffectType.GRADIENT_BLUR
}

export function getHdsStatusBarContentColor(): string {
  return getAppUiState().isDarkMode ? STATUS_BAR_CONTENT_DARK : STATUS_BAR_CONTENT_LIGHT
}

export function getHdsTopNavigationInitialBlurRadius(materialType: number): number {
  return materialType === 0 ? 0 : 8
}

function getHdsTopNavigationOriginBackgroundColor(): string {
  return withColorAlpha(getAppUiState().themeBackground, '00')
}

function getHdsTopNavigationScrolledBackgroundColor(): string {
  return withColorAlpha(getAppUiState().themeBackground, 'E6')
}

export function getHdsTopNavigationBlurRadius(materialType: number, materialLevel: number,
  windowWidthVp: number, windowHeightVp: number): number {
  if (materialType === 0) {
    return 0
  }
  const isLandscape = windowWidthVp > windowHeightVp
  if (materialLevel === 0) {
    return isLandscape ? 20 : 26
  }
  if (materialLevel === 1) {
    return isLandscape ? 18 : 22
  }
  if (materialLevel === 2) {
    return isLandscape ? 14 : 18
  }
  return isLandscape ? 16 : 22
}

export function buildHdsTopNavigationTitleBarOptions(
  options: HdsTopNavigationBlurOptions): HdsNavigationTitleBarOptions {
  return {
    padding: {
      start: LengthMetrics.vp(options.startPaddingVp),
      end: LengthMetrics.vp(options.endPaddingVp)
    },
    content: {
      title: {
        mainTitle: ' '
      },
      menu: {
        value: options.menuItems,
        maxCount: options.menuMaxCount
      },
      stackBuilder: options.stackBuilder
    },
    style: {
      scrollEffectOpts: {
        enableScrollEffect: false,
        scrollEffectType: getHdsTopNavigationScrollEffectType(options.materialType),
        blurEffectiveStartOffset: LengthMetrics.vp(TITLE_BAR_BLUR_EFFECTIVE_START_OFFSET),
        blurEffectiveEndOffset: LengthMetrics.vp(options.blurEffectiveEndOffsetVp)
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      scrollEffectStyle: {
        backgroundStyle: {
          backgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
          maskExtraHeight: options.maskExtraHeightVp
        },
        contentStyle: {
          titleStyle: {
            mainTitleColor: $r('sys.color.font_primary')
          },
          menuStyle: {
            backgroundColor: $r('sys.color.comp_background_primary'),
            iconColor: $r('sys.color.icon_primary')
          },
          backIconStyle: {
            backgroundColor: $r('sys.color.comp_background_primary'),
            iconColor: $r('sys.color.icon_primary')
          }
        }
      },
      originalStyle: {
        backgroundStyle: {
          backgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
          maskExtraHeight: options.maskExtraHeightVp
        },
        contentStyle: {
          titleStyle: {
            mainTitleColor: Color.Black
          },
          menuStyle: {
            backgroundColor: $r('sys.color.comp_background_tertiary'),
            iconColor: $r('sys.color.icon_primary')
          }
        }
      }
    },
    avoidLayoutSafeArea: true,
    enableComponentSafeArea: false
  }
}

export function buildHdsTopNavigationTitleBarOptionsForPage(materialType: number, materialLevel: number,
  windowWidthVp: number, windowHeightVp: number, stackBuilder: () => void,
  menuItems: Array<HdsNavigationMenuItemOptions> = []): HdsNavigationTitleBarOptions {
  const options = new HdsTopNavigationBlurOptions()
  options.startPaddingVp = 16
  options.endPaddingVp = 16
  options.materialType = materialType
  options.materialLevel = materialLevel
  options.windowWidthVp = windowWidthVp
  options.windowHeightVp = windowHeightVp
  options.maskExtraHeightVp = getHdsTopNavigationMaskExtraHeight(windowWidthVp, windowHeightVp)
  options.blurEffectiveEndOffsetVp = getHdsTopNavigationBlurEffectiveEndOffset(windowWidthVp, windowHeightVp)
  options.stackBuilder = stackBuilder
  options.menuItems = menuItems
  return buildHdsTopNavigationTitleBarOptions(options)
}
