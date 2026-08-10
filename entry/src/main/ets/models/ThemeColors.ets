// 主题类型枚举
export enum ColorTheme {
  ATELIER = 'atelier',      // Atelier 亚麻墨色
  LAVENDER = 'lavender',    // XCube 浅紫
  CLAUDE = 'claude',        // Claude 暖棕
  PORCELAIN = 'porcelain',  // 青瓷冷蓝
  HERBARIUM = 'herbarium',  // 压叶绿
  SALON = 'salon',          // 扑粉玫瑰
  GALLERY = 'gallery',      // 石墨单色
  NOCTURNE = 'nocturne'     // 破晓靛蓝
}

// 独立于配色主题的全局视觉模式。非 OFF 模式拥有最高的主题解析优先级。
export enum VisualEffectsMode {
  OFF = 'off',
  MANUSCRIPT = 'manuscript'
}

// 主题颜色配置接口
export interface ThemeColorConfig {
  // 主色调
  primary: string
  primaryLight: string
  // 背景色
  background: string
  // 表面色
  surface: string
  // 分隔线
  divider: string
  // 用户气泡
  userBubble: string
  userBubbleText: string
  // AI 气泡
  aiBubble: string
  // 文字颜色
  textPrimary: string
  textSecondary: string
  textTertiary: string
  // Markdown 相关
  markdownTitle: string
  markdownText: string
  markdownLink: string
  markdownLinkBg: string
  markdownCodeBg: string
  markdownCodeText: string
  markdownQuoteBg: string
  markdownTableBg: string
  markdownTableHeaderBg: string
  markdownTableAltBg: string
  markdownTableBorder: string
}

export interface ManuscriptColorConfig extends ThemeColorConfig {
  accent: string
  accentDeep: string
  dottedLeader: string
  pressTint: string
}

const MANUSCRIPT_LIGHT_COLORS: ManuscriptColorConfig = {
  primary: '#8A6228',
  primaryLight: '#F5EDE0',
  background: '#F3F2F2',
  surface: '#FBFAF8',
  divider: '#E4E1DB',
  userBubble: '#F3F2F2',
  userBubbleText: '#201F1D',
  aiBubble: '#FBFAF8',
  textPrimary: '#201F1D',
  textSecondary: '#6B675F',
  textTertiary: '#98938A',
  markdownTitle: '#201F1D',
  markdownText: '#201F1D',
  markdownLink: '#8A6228',
  markdownLinkBg: '#F3F2F2',
  markdownCodeBg: '#FBFAF8',
  markdownCodeText: '#201F1D',
  markdownQuoteBg: '#FBFAF8',
  markdownTableBg: '#FBFAF8',
  markdownTableHeaderBg: '#F3F2F2',
  markdownTableAltBg: '#F7F5F1',
  markdownTableBorder: '#E4E1DB',
  accent: '#B68235',
  accentDeep: '#8A6228',
  dottedLeader: '#C9C4BB',
  pressTint: '#F5EDE0'
}

const MANUSCRIPT_DARK_COLORS: ManuscriptColorConfig = {
  primary: '#D9B274',
  primaryLight: '#33291B',
  background: '#1B1A18',
  surface: '#242320',
  divider: '#34312B',
  userBubble: '#1B1A18',
  userBubbleText: '#ECEAE5',
  aiBubble: '#242320',
  textPrimary: '#ECEAE5',
  textSecondary: '#ADA89F',
  textTertiary: '#7B766D',
  markdownTitle: '#ECEAE5',
  markdownText: '#ECEAE5',
  markdownLink: '#D9B274',
  markdownLinkBg: '#1B1A18',
  markdownCodeBg: '#242320',
  markdownCodeText: '#ECEAE5',
  markdownQuoteBg: '#242320',
  markdownTableBg: '#242320',
  markdownTableHeaderBg: '#1B1A18',
  markdownTableAltBg: '#201F1C',
  markdownTableBorder: '#34312B',
  accent: '#C99A52',
  accentDeep: '#D9B274',
  dottedLeader: '#4A463F',
  pressTint: '#33291B'
}

export function normalizeVisualEffectsMode(mode: string): VisualEffectsMode {
  return mode === VisualEffectsMode.MANUSCRIPT ? VisualEffectsMode.MANUSCRIPT : VisualEffectsMode.OFF
}

export function getManuscriptColors(isDarkMode: boolean): ManuscriptColorConfig {
  return isDarkMode ? MANUSCRIPT_DARK_COLORS : MANUSCRIPT_LIGHT_COLORS
}

// 主题信息接口
export interface ThemeInfo {
  id: ColorTheme
  nameKey: string           // 字符串资源 key
  descriptionKey: string    // 描述字符串资源 key
  previewColors: string[]   // 预览色块（4 个颜色：背景、弱染色、主色、气泡）
  light: ThemeColorConfig
  dark: ThemeColorConfig
}

// Atelier 主题：亚麻纸底 + 靛墨点缀，聊天气泡默认衬线字体。
const ATELIER_THEME: ThemeInfo = {
  id: ColorTheme.ATELIER,
  nameKey: 'theme_color_atelier',
  descriptionKey: 'theme_color_atelier_desc',
  previewColors: ['#F7F1E6', '#DDE0EF', '#44518A', '#3D4877'],
  light: {
    primary: '#44518A',
    primaryLight: '#DDE0EF',
    background: '#F7F1E6',
    surface: '#FFFCF4',
    divider: '#EADFCB',
    userBubble: '#3D4877',
    userBubbleText: '#FFF6EE',
    aiBubble: '#FFFCF4',
    textPrimary: '#2A231A',
    textSecondary: '#6E6355',
    textTertiary: '#9C8F7E',
    markdownTitle: '#2A231A',
    markdownText: '#3F3729',
    markdownLink: '#44518A',
    markdownLinkBg: '#DDE0EF',
    markdownCodeBg: '#F3ECDD',
    markdownCodeText: '#3E4979',
    markdownQuoteBg: '#F3ECDD',
    markdownTableBg: '#FFFCF4',
    markdownTableHeaderBg: '#F3ECDD',
    markdownTableAltBg: '#FAF4E8',
    markdownTableBorder: '#DDE0EF'
  },
  dark: {
    primary: '#97A3D9',
    primaryLight: '#282D46',
    background: '#211B14',
    surface: '#2B241B',
    divider: '#282D46',
    userBubble: '#47528A',
    userBubbleText: '#FFF3EA',
    aiBubble: '#2B241B',
    textPrimary: '#F4ECDF',
    textSecondary: '#BCB09E',
    textTertiary: '#877B6A',
    markdownTitle: '#F4ECDF',
    markdownText: '#E8DFCE',
    markdownLink: '#A9B4E4',
    markdownLinkBg: '#282D46',
    markdownCodeBg: '#262019',
    markdownCodeText: '#C3CCF0',
    markdownQuoteBg: '#262019',
    markdownTableBg: '#2B241B',
    markdownTableHeaderBg: '#352D22',
    markdownTableAltBg: '#302921',
    markdownTableBorder: '#282D46'
  }
}

// XCube Lavender：更冷、更通透的品牌紫，呈现玻璃般的明亮质感。
const LAVENDER_THEME: ThemeInfo = {
  id: ColorTheme.LAVENDER,
  nameKey: 'theme_color_lavender',
  descriptionKey: 'theme_color_lavender_desc',
  previewColors: ['#F7F5FF', '#E6E1FD', '#7A68F0', '#6D5CE0'],
  light: {
    primary: '#7A68F0',
    primaryLight: '#E6E1FD',
    background: '#F7F5FF',
    surface: '#FDFCFF',
    divider: '#E6E1FD',
    userBubble: '#6D5CE0',
    userBubbleText: '#F7F4FF',
    aiBubble: '#FDFCFF',
    textPrimary: '#221E38',
    textSecondary: '#645E7C',
    textTertiary: '#948FA8',
    markdownTitle: '#221E38',
    markdownText: '#3B3554',
    markdownLink: '#7A68F0',
    markdownLinkBg: '#E6E1FD',
    markdownCodeBg: '#F0EDFD',
    markdownCodeText: '#5F50C7',
    markdownQuoteBg: '#F0EDFD',
    markdownTableBg: '#FDFCFF',
    markdownTableHeaderBg: '#F0EDFD',
    markdownTableAltBg: '#F8F6FF',
    markdownTableBorder: '#E6E1FD'
  },
  dark: {
    primary: '#A99DFF',
    primaryLight: '#332C52',
    background: '#171422',
    surface: '#211D31',
    divider: '#332C52',
    userBubble: '#6A5AD0',
    userBubbleText: '#F4F0FF',
    aiBubble: '#211D31',
    textPrimary: '#F1EDFF',
    textSecondary: '#B4ADCC',
    textTertiary: '#7E7794',
    markdownTitle: '#F1EDFF',
    markdownText: '#E3DEEF',
    markdownLink: '#B7ADFF',
    markdownLinkBg: '#332C52',
    markdownCodeBg: '#1D192B',
    markdownCodeText: '#C6BEFF',
    markdownQuoteBg: '#1D192B',
    markdownTableBg: '#211D31',
    markdownTableHeaderBg: '#2A253D',
    markdownTableAltBg: '#262238',
    markdownTableBorder: '#332C52'
  }
}

// Claude：更深的赤陶色与温暖纸面。
const CLAUDE_THEME: ThemeInfo = {
  id: ColorTheme.CLAUDE,
  nameKey: 'theme_color_claude',
  descriptionKey: 'theme_color_claude_desc',
  previewColors: ['#FAF6EF', '#F0E2D5', '#B15B33', '#9A5638'],
  light: {
    primary: '#B15B33',
    primaryLight: '#F0E2D5',
    background: '#FAF6EF',
    surface: '#FFFCF6',
    divider: '#F0E2D5',
    userBubble: '#9A5638',
    userBubbleText: '#FFF6EE',
    aiBubble: '#FFFCF6',
    textPrimary: '#28211A',
    textSecondary: '#6F6459',
    textTertiary: '#9C9082',
    markdownTitle: '#28211A',
    markdownText: '#40372F',
    markdownLink: '#B15B33',
    markdownLinkBg: '#F0E2D5',
    markdownCodeBg: '#F5EDE4',
    markdownCodeText: '#914A2C',
    markdownQuoteBg: '#F5EDE4',
    markdownTableBg: '#FFFCF6',
    markdownTableHeaderBg: '#F5EDE4',
    markdownTableAltBg: '#FBF5ED',
    markdownTableBorder: '#F0E2D5'
  },
  dark: {
    primary: '#D98A5F',
    primaryLight: '#40291D',
    background: '#221B15',
    surface: '#2C241C',
    divider: '#40291D',
    userBubble: '#87492F',
    userBubbleText: '#FFEFE4',
    aiBubble: '#2C241C',
    textPrimary: '#F5ECE1',
    textSecondary: '#BDAF9E',
    textTertiary: '#87796A',
    markdownTitle: '#F5ECE1',
    markdownText: '#E8DED2',
    markdownLink: '#E29A72',
    markdownLinkBg: '#40291D',
    markdownCodeBg: '#271F18',
    markdownCodeText: '#F0B18D',
    markdownQuoteBg: '#271F18',
    markdownTableBg: '#2C241C',
    markdownTableHeaderBg: '#382D22',
    markdownTableAltBg: '#32291F',
    markdownTableBorder: '#40291D'
  }
}

// Porcelain：带釉面质感的冷蓝灰，也是精选集合中唯一的冷色主题。
const PORCELAIN_THEME: ThemeInfo = {
  id: ColorTheme.PORCELAIN,
  nameKey: 'theme_color_porcelain',
  descriptionKey: 'theme_color_porcelain_desc',
  previewColors: ['#F4F7F9', '#DCE7EE', '#3E6E96', '#3A6285'],
  light: {
    primary: '#3E6E96',
    primaryLight: '#DCE7EE',
    background: '#F4F7F9',
    surface: '#FCFEFF',
    divider: '#DCE7EE',
    userBubble: '#3A6285',
    userBubbleText: '#F2F8FD',
    aiBubble: '#FCFEFF',
    textPrimary: '#1D242B',
    textSecondary: '#5F6C77',
    textTertiary: '#8C99A4',
    markdownTitle: '#1D242B',
    markdownText: '#34404A',
    markdownLink: '#3E6E96',
    markdownLinkBg: '#DCE7EE',
    markdownCodeBg: '#EAF1F5',
    markdownCodeText: '#355F82',
    markdownQuoteBg: '#EAF1F5',
    markdownTableBg: '#FCFEFF',
    markdownTableHeaderBg: '#EAF1F5',
    markdownTableAltBg: '#F5F8FA',
    markdownTableBorder: '#DCE7EE'
  },
  dark: {
    primary: '#85AECF',
    primaryLight: '#213648',
    background: '#151C22',
    surface: '#1E272F',
    divider: '#213648',
    userBubble: '#3D6484',
    userBubbleText: '#EFF7FE',
    aiBubble: '#1E272F',
    textPrimary: '#EAF2F9',
    textSecondary: '#A9B8C4',
    textTertiary: '#748492',
    markdownTitle: '#EAF2F9',
    markdownText: '#D8E3EC',
    markdownLink: '#9FC2DE',
    markdownLinkBg: '#213648',
    markdownCodeBg: '#192229',
    markdownCodeText: '#BDD3E3',
    markdownQuoteBg: '#192229',
    markdownTableBg: '#1E272F',
    markdownTableHeaderBg: '#28343D',
    markdownTableAltBg: '#232E36',
    markdownTableBorder: '#213648'
  }
}

// Herbarium：干燥压叶般的植物绿，安静而自然。
const HERBARIUM_THEME: ThemeInfo = {
  id: ColorTheme.HERBARIUM,
  nameKey: 'theme_color_herbarium',
  descriptionKey: 'theme_color_herbarium_desc',
  previewColors: ['#F4F8F2', '#DEEAE0', '#4E7A5A', '#486E55'],
  light: {
    primary: '#4E7A5A',
    primaryLight: '#DEEAE0',
    background: '#F4F8F2',
    surface: '#FBFEFA',
    divider: '#DEEAE0',
    userBubble: '#486E55',
    userBubbleText: '#F1FAF3',
    aiBubble: '#FBFEFA',
    textPrimary: '#1F271F',
    textSecondary: '#61705F',
    textTertiary: '#8C9A8A',
    markdownTitle: '#1F271F',
    markdownText: '#354238',
    markdownLink: '#4E7A5A',
    markdownLinkBg: '#DEEAE0',
    markdownCodeBg: '#EBF2EB',
    markdownCodeText: '#42684D',
    markdownQuoteBg: '#EBF2EB',
    markdownTableBg: '#FBFEFA',
    markdownTableHeaderBg: '#EBF2EB',
    markdownTableAltBg: '#F5F9F4',
    markdownTableBorder: '#DEEAE0'
  },
  dark: {
    primary: '#8CBB9A',
    primaryLight: '#24382A',
    background: '#161D17',
    surface: '#202A21',
    divider: '#24382A',
    userBubble: '#3F6A4E',
    userBubbleText: '#EDFAF0',
    aiBubble: '#202A21',
    textPrimary: '#ECF5EC',
    textSecondary: '#ABBCAB',
    textTertiary: '#77877A',
    markdownTitle: '#ECF5EC',
    markdownText: '#DCE8DC',
    markdownLink: '#A4CFAF',
    markdownLinkBg: '#24382A',
    markdownCodeBg: '#1B241C',
    markdownCodeText: '#B9D7C0',
    markdownQuoteBg: '#1B241C',
    markdownTableBg: '#202A21',
    markdownTableHeaderBg: '#2A352B',
    markdownTableAltBg: '#253026',
    markdownTableBorder: '#24382A'
  }
}

// Salon：温暖中性的灰粉玫瑰，柔和但不过分甜腻。
const SALON_THEME: ThemeInfo = {
  id: ColorTheme.SALON,
  nameKey: 'theme_color_salon',
  descriptionKey: 'theme_color_salon_desc',
  previewColors: ['#FAF4F3', '#F2DDE1', '#A44E5E', '#8F4A57'],
  light: {
    primary: '#A44E5E',
    primaryLight: '#F2DDE1',
    background: '#FAF4F3',
    surface: '#FFFBFA',
    divider: '#F2DDE1',
    userBubble: '#8F4A57',
    userBubbleText: '#FFF2F2',
    aiBubble: '#FFFBFA',
    textPrimary: '#2A2022',
    textSecondary: '#746165',
    textTertiary: '#A08D91',
    markdownTitle: '#2A2022',
    markdownText: '#453438',
    markdownLink: '#A44E5E',
    markdownLinkBg: '#F2DDE1',
    markdownCodeBg: '#F6E9EB',
    markdownCodeText: '#8A4351',
    markdownQuoteBg: '#F6E9EB',
    markdownTableBg: '#FFFBFA',
    markdownTableHeaderBg: '#F6E9EB',
    markdownTableAltBg: '#FBF5F4',
    markdownTableBorder: '#F2DDE1'
  },
  dark: {
    primary: '#D98D9C',
    primaryLight: '#402329',
    background: '#221718',
    surface: '#2C2022',
    divider: '#402329',
    userBubble: '#7E4250',
    userBubbleText: '#FFEDEF',
    aiBubble: '#2C2022',
    textPrimary: '#F6EAEC',
    textSecondary: '#C0AAAE',
    textTertiary: '#8A767A',
    markdownTitle: '#F6EAEC',
    markdownText: '#E8DADD',
    markdownLink: '#E9A5B2',
    markdownLinkBg: '#402329',
    markdownCodeBg: '#271B1D',
    markdownCodeText: '#F0B6C1',
    markdownQuoteBg: '#271B1D',
    markdownTableBg: '#2C2022',
    markdownTableHeaderBg: '#38282B',
    markdownTableAltBg: '#322427',
    markdownTableBorder: '#402329'
  }
}

// Gallery：博物馆白与暖石墨构成的无彩色主题。
const GALLERY_THEME: ThemeInfo = {
  id: ColorTheme.GALLERY,
  nameKey: 'theme_color_gallery',
  descriptionKey: 'theme_color_gallery_desc',
  previewColors: ['#F3F2F0', '#E4E1DB', '#3E3A34', '#33302B'],
  light: {
    primary: '#3E3A34',
    primaryLight: '#E4E1DB',
    background: '#F3F2F0',
    surface: '#FBFAF8',
    divider: '#E4E1DB',
    userBubble: '#33302B',
    userBubbleText: '#F4F2EE',
    aiBubble: '#FBFAF8',
    textPrimary: '#201F1D',
    textSecondary: '#6B675F',
    textTertiary: '#98938A',
    markdownTitle: '#201F1D',
    markdownText: '#3D3A35',
    markdownLink: '#3E3A34',
    markdownLinkBg: '#E4E1DB',
    markdownCodeBg: '#ECE9E4',
    markdownCodeText: '#4C4841',
    markdownQuoteBg: '#ECE9E4',
    markdownTableBg: '#FBFAF8',
    markdownTableHeaderBg: '#ECE9E4',
    markdownTableAltBg: '#F5F3F0',
    markdownTableBorder: '#E4E1DB'
  },
  dark: {
    primary: '#C9C3B8',
    primaryLight: '#34312B',
    background: '#191816',
    surface: '#232220',
    divider: '#34312B',
    userBubble: '#4A463F',
    userBubbleText: '#F2EFE9',
    aiBubble: '#232220',
    textPrimary: '#EFEDE8',
    textSecondary: '#ADA89F',
    textTertiary: '#7B766D',
    markdownTitle: '#EFEDE8',
    markdownText: '#DEDAD3',
    markdownLink: '#D5D0C7',
    markdownLinkBg: '#34312B',
    markdownCodeBg: '#1E1D1B',
    markdownCodeText: '#CEC8BD',
    markdownQuoteBg: '#1E1D1B',
    markdownTableBg: '#232220',
    markdownTableHeaderBg: '#2D2B27',
    markdownTableAltBg: '#282624',
    markdownTableBorder: '#34312B'
  }
}

// Nocturne：为夜间使用调校的深靛蓝，日间则呈现破晓前的浅蓝。
const NOCTURNE_THEME: ThemeInfo = {
  id: ColorTheme.NOCTURNE,
  nameKey: 'theme_color_nocturne',
  descriptionKey: 'theme_color_nocturne_desc',
  previewColors: ['#F3F4F9', '#DCE0F0', '#3F4C7E', '#3A4670'],
  light: {
    primary: '#3F4C7E',
    primaryLight: '#DCE0F0',
    background: '#F3F4F9',
    surface: '#FBFCFF',
    divider: '#DCE0F0',
    userBubble: '#3A4670',
    userBubbleText: '#EFF2FF',
    aiBubble: '#FBFCFF',
    textPrimary: '#1E2130',
    textSecondary: '#5F6478',
    textTertiary: '#8B90A4',
    markdownTitle: '#1E2130',
    markdownText: '#363B50',
    markdownLink: '#3F4C7E',
    markdownLinkBg: '#DCE0F0',
    markdownCodeBg: '#E9EBF5',
    markdownCodeText: '#394570',
    markdownQuoteBg: '#E9EBF5',
    markdownTableBg: '#FBFCFF',
    markdownTableHeaderBg: '#E9EBF5',
    markdownTableAltBg: '#F5F6FA',
    markdownTableBorder: '#DCE0F0'
  },
  dark: {
    primary: '#9AA6E0',
    primaryLight: '#262C4A',
    background: '#14151E',
    surface: '#1D1F2B',
    divider: '#262C4A',
    userBubble: '#39436E',
    userBubbleText: '#ECF0FF',
    aiBubble: '#1D1F2B',
    textPrimary: '#EBEEFA',
    textSecondary: '#A9AFC6',
    textTertiary: '#757B93',
    markdownTitle: '#EBEEFA',
    markdownText: '#D9DDEC',
    markdownLink: '#B0BAEC',
    markdownLinkBg: '#262C4A',
    markdownCodeBg: '#191A24',
    markdownCodeText: '#C3CAF2',
    markdownQuoteBg: '#191A24',
    markdownTableBg: '#1D1F2B',
    markdownTableHeaderBg: '#272A38',
    markdownTableAltBg: '#222430',
    markdownTableBorder: '#262C4A'
  }
}

// 精简后的可选主题列表
export const ALL_THEMES: ThemeInfo[] = [
  ATELIER_THEME,
  LAVENDER_THEME,
  CLAUDE_THEME,
  PORCELAIN_THEME,
  HERBARIUM_THEME,
  SALON_THEME,
  GALLERY_THEME,
  NOCTURNE_THEME
]

// 将持久化的旧主题 ID 归一化到当前精选集合。
export function resolveColorThemeId(themeId: string): ColorTheme {
  if (themeId === ColorTheme.ATELIER) {
    return ColorTheme.ATELIER
  }
  if (themeId === ColorTheme.LAVENDER) {
    return ColorTheme.LAVENDER
  }
  if (themeId === ColorTheme.CLAUDE) {
    return ColorTheme.CLAUDE
  }
  if (themeId === ColorTheme.PORCELAIN || themeId === 'chatgpt') {
    return ColorTheme.PORCELAIN
  }
  if (themeId === ColorTheme.HERBARIUM) {
    return ColorTheme.HERBARIUM
  }
  if (themeId === ColorTheme.SALON) {
    return ColorTheme.SALON
  }
  if (themeId === ColorTheme.GALLERY) {
    return ColorTheme.GALLERY
  }
  if (themeId === ColorTheme.NOCTURNE) {
    return ColorTheme.NOCTURNE
  }
  return ColorTheme.LAVENDER
}

// 根据主题 ID 获取主题信息
export function getThemeById(themeId: ColorTheme): ThemeInfo {
  const resolvedThemeId = resolveColorThemeId(themeId as string)
  for (let i = 0; i < ALL_THEMES.length; i++) {
    if (ALL_THEMES[i].id === resolvedThemeId) {
      return ALL_THEMES[i]
    }
  }
  return LAVENDER_THEME
}

// 根据主题 ID 和深浅模式获取颜色配置
export function getThemeColors(themeId: ColorTheme, isDarkMode: boolean): ThemeColorConfig {
  const theme = getThemeById(themeId)
  return isDarkMode ? theme.dark : theme.light
}
