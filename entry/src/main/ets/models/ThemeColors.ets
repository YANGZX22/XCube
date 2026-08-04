// 主题类型枚举
export enum ColorTheme {
  ATELIER = 'atelier',      // Atelier 亚麻墨色
  LAVENDER = 'lavender',    // XCube 浅紫
  CLAUDE = 'claude',        // Claude 暖棕
  PORCELAIN = 'porcelain'   // 青瓷冷蓝
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

// 精简后的可选主题列表
export const ALL_THEMES: ThemeInfo[] = [
  ATELIER_THEME,
  LAVENDER_THEME,
  CLAUDE_THEME,
  PORCELAIN_THEME
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
