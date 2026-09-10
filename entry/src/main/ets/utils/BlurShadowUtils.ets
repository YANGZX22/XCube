import { getAppUiState } from '../state/AppUiState'

// Keep the glass surface transparent: only draw a faint shadow below its outline.
export function getBlurBottomShadow(enabled: boolean = true): ShadowOptions {
  return {
    radius: enabled ? 8 : 0,
    color: enabled ? (getAppUiState().isDarkMode ? '#33000000' : '#1F000000') : Color.Transparent,
    offsetX: 0,
    offsetY: enabled ? 3 : 0,
    fill: false
  }
}

// 透明模糊下的悬浮加号只保留轻微轮廓阴影，避免沿用材质模式的高不透明度阴影。
export function getBlurFloatingActionShadow(): ShadowOptions {
  return {
    radius: 8,
    color: getAppUiState().isDarkMode ? '#26000000' : '#14000000',
    offsetX: 0,
    offsetY: 2,
    fill: false
  }
}
