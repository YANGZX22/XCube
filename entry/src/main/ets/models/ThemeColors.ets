// 主题类型枚举
export enum ColorTheme {
  LAVENDER = 'lavender',    // XCube 浅紫
  DEFAULT = 'default',      // 默认暖纸
  CLAUDE = 'claude',        // Claude 暖棕
  CHATGPT = 'chatgpt',      // 清爽蓝
  VIOLET = 'violet',        // 雾紫
  MINT = 'mint',            // 松雾绿
  NOTION = 'notion'         // Notion 极简
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

// XCube 浅紫主题：以品牌紫为强调色，整体保持轻盈、通透和低饱和。
const LAVENDER_THEME: ThemeInfo = {
  id: ColorTheme.LAVENDER,
  nameKey: 'theme_color_lavender',
  descriptionKey: 'theme_color_lavender_desc',
  previewColors: ['#F8F7FF', '#E9E6FF', '#8576FF', '#7568DF'],
  light: {
    primary: '#8576FF',
    primaryLight: '#E9E6FF',
    background: '#F8F7FF',
    surface: '#FEFDFF',
    divider: '#E5E5E5',
    userBubble: '#7568DF',
    userBubbleText: '#FFFFFF',
    aiBubble: '#FEFDFF',
    textPrimary: '#252238',
    textSecondary: '#686279',
    textTertiary: '#958FA5',
    markdownTitle: '#252238',
    markdownText: '#3E394F',
    markdownLink: '#7568DF',
    markdownLinkBg: '#E9E6FF',
    markdownCodeBg: '#F0EEFF',
    markdownCodeText: '#6559C7',
    markdownQuoteBg: '#F0EEFF',
    markdownTableBg: '#FEFDFF',
    markdownTableHeaderBg: '#F0EEFF',
    markdownTableAltBg: '#F8F7FF',
    markdownTableBorder: '#E9E6FF'
  },
  dark: {
    primary: '#A99FFF',
    primaryLight: '#373251',
    background: '#191725',
    surface: '#242132',
    divider: '#4A4A4A',
    userBubble: '#7468D7',
    userBubbleText: '#FFFFFF',
    aiBubble: '#242132',
    textPrimary: '#F3F0FF',
    textSecondary: '#B9B3C9',
    textTertiary: '#847E94',
    markdownTitle: '#F3F0FF',
    markdownText: '#E5E0F2',
    markdownLink: '#B8AFFF',
    markdownLinkBg: '#373251',
    markdownCodeBg: '#211E2D',
    markdownCodeText: '#C8C0FF',
    markdownQuoteBg: '#211E2D',
    markdownTableBg: '#242132',
    markdownTableHeaderBg: '#2F2B40',
    markdownTableAltBg: '#292638',
    markdownTableBorder: '#373251'
  }
}

// 默认暖纸主题：中性色底盘，蓝灰只做小面积强调。
const DEFAULT_THEME: ThemeInfo = {
  id: ColorTheme.DEFAULT,
  nameKey: 'theme_color_default',
  descriptionKey: 'theme_color_default_desc',
  previewColors: ['#FAF8F3', '#D8E2EE', '#4E6F9E', '#52688A'],
  light: {
    primary: '#4E6F9E',
    primaryLight: '#D8E2EE',
    background: '#FAF8F3',
    surface: '#FFFDF8',
    divider: '#D8E2EE',
    userBubble: '#52688A',
    userBubbleText: '#FFFFFF',
    aiBubble: '#FFFDF8',
    textPrimary: '#24211C',
    textSecondary: '#6F6A60',
    textTertiary: '#8A8178',
    markdownTitle: '#24211C',
    markdownText: '#3D3830',
    markdownLink: '#4E6F9E',
    markdownLinkBg: '#D8E2EE',
    markdownCodeBg: '#F3EFE8',
    markdownCodeText: '#8F5E45',
    markdownQuoteBg: '#F3EFE8',
    markdownTableBg: '#FFFDF8',
    markdownTableHeaderBg: '#F3EFE8',
    markdownTableAltBg: '#FAF7F0',
    markdownTableBorder: '#D8E2EE'
  },
  dark: {
    primary: '#7FA2CC',
    primaryLight: '#273646',
    background: '#1F1E1A',
    surface: '#292722',
    divider: '#273646',
    userBubble: '#4F6886',
    userBubbleText: '#F7FAFD',
    aiBubble: '#292722',
    textPrimary: '#F3EFE6',
    textSecondary: '#B8B0A3',
    textTertiary: '#837B70',
    markdownTitle: '#F3EFE6',
    markdownText: '#E7E0D4',
    markdownLink: '#9CBFE8',
    markdownLinkBg: '#273646',
    markdownCodeBg: '#24221E',
    markdownCodeText: '#D7C4A9',
    markdownQuoteBg: '#24221E',
    markdownTableBg: '#292722',
    markdownTableHeaderBg: '#332F28',
    markdownTableAltBg: '#2E2B25',
    markdownTableBorder: '#273646'
  }
}

// Claude 暖棕主题：参考暖纸面和锈棕点缀，避免大面积橙色。
const CLAUDE_THEME: ThemeInfo = {
  id: ColorTheme.CLAUDE,
  nameKey: 'theme_color_claude',
  descriptionKey: 'theme_color_claude_desc',
  previewColors: ['#FAF7F0', '#F1E8E0', '#A65F3B', '#8F5E45'],
  light: {
    primary: '#A65F3B',
    primaryLight: '#F1E8E0',
    background: '#FAF7F0',
    surface: '#FFFDF8',
    divider: '#F1E8E0',
    userBubble: '#8F5E45',
    userBubbleText: '#FFFFFF',
    aiBubble: '#FFFDF8',
    textPrimary: '#26211C',
    textSecondary: '#6F665C',
    textTertiary: '#9C9287',
    markdownTitle: '#26211C',
    markdownText: '#3F372F',
    markdownLink: '#A65F3B',
    markdownLinkBg: '#F1E8E0',
    markdownCodeBg: '#F3EDE5',
    markdownCodeText: '#8F5E45',
    markdownQuoteBg: '#F3EDE5',
    markdownTableBg: '#FFFDF8',
    markdownTableHeaderBg: '#F3EDE5',
    markdownTableAltBg: '#FAF4EC',
    markdownTableBorder: '#F1E8E0'
  },
  dark: {
    primary: '#C87552',
    primaryLight: '#3A2C25',
    background: '#251F1A',
    surface: '#292722',
    divider: '#3A2C25',
    userBubble: '#7A4E3D',
    userBubbleText: '#FFF8F2',
    aiBubble: '#292722',
    textPrimary: '#F3EFE6',
    textSecondary: '#B8B0A3',
    textTertiary: '#837B70',
    markdownTitle: '#F3EFE6',
    markdownText: '#E7E0D4',
    markdownLink: '#D48B68',
    markdownLinkBg: '#3A2C25',
    markdownCodeBg: '#24221E',
    markdownCodeText: '#E0AA8A',
    markdownQuoteBg: '#24221E',
    markdownTableBg: '#292722',
    markdownTableHeaderBg: '#332F28',
    markdownTableAltBg: '#2E2B25',
    markdownTableBorder: '#3A2C25'
  }
}

// 清爽蓝主题：保留冷静科技感，但降低蓝色饱和和面积。
const CHATGPT_THEME: ThemeInfo = {
  id: ColorTheme.CHATGPT,
  nameKey: 'theme_color_chatgpt',
  descriptionKey: 'theme_color_chatgpt_desc',
  previewColors: ['#F7FAFC', '#E4EDF6', '#416FAD', '#4D719C'],
  light: {
    primary: '#416FAD',
    primaryLight: '#E4EDF6',
    background: '#F7FAFC',
    surface: '#FCFEFF',
    divider: '#E4EDF6',
    userBubble: '#4D719C',
    userBubbleText: '#FFFFFF',
    aiBubble: '#FCFEFF',
    textPrimary: '#1F252B',
    textSecondary: '#64707A',
    textTertiary: '#8F9AA4',
    markdownTitle: '#1F252B',
    markdownText: '#34404A',
    markdownLink: '#416FAD',
    markdownLinkBg: '#E4EDF6',
    markdownCodeBg: '#EDF3F7',
    markdownCodeText: '#47627F',
    markdownQuoteBg: '#EDF3F7',
    markdownTableBg: '#FCFEFF',
    markdownTableHeaderBg: '#EDF3F7',
    markdownTableAltBg: '#F4F8FA',
    markdownTableBorder: '#E4EDF6'
  },
  dark: {
    primary: '#82A9D4',
    primaryLight: '#24374A',
    background: '#182027',
    surface: '#202932',
    divider: '#24374A',
    userBubble: '#4D6F91',
    userBubbleText: '#F6FAFF',
    aiBubble: '#202932',
    textPrimary: '#EEF4FA',
    textSecondary: '#B1BCC7',
    textTertiary: '#7E8A96',
    markdownTitle: '#EEF4FA',
    markdownText: '#DDE6EE',
    markdownLink: '#9CBFE5',
    markdownLinkBg: '#24374A',
    markdownCodeBg: '#1B242C',
    markdownCodeText: '#C2CEDA',
    markdownQuoteBg: '#1B242C',
    markdownTableBg: '#202932',
    markdownTableHeaderBg: '#2A3540',
    markdownTableAltBg: '#242E38',
    markdownTableBorder: '#24374A'
  }
}

// 雾紫主题：紫色只做灰紫点缀，避免大面积高饱和紫。
const VIOLET_THEME: ThemeInfo = {
  id: ColorTheme.VIOLET,
  nameKey: 'theme_color_violet',
  descriptionKey: 'theme_color_violet_desc',
  previewColors: ['#FAF8FC', '#ECE8F2', '#7E5F92', '#675F82'],
  light: {
    primary: '#7E5F92',
    primaryLight: '#ECE8F2',
    background: '#FAF8FC',
    surface: '#FFFDFF',
    divider: '#ECE8F2',
    userBubble: '#675F82',
    userBubbleText: '#FFFFFF',
    aiBubble: '#FFFDFF',
    textPrimary: '#27232C',
    textSecondary: '#6B6474',
    textTertiary: '#9B93A3',
    markdownTitle: '#27232C',
    markdownText: '#3F3948',
    markdownLink: '#71658F',
    markdownLinkBg: '#ECE8F2',
    markdownCodeBg: '#F1EDF5',
    markdownCodeText: '#6E5D86',
    markdownQuoteBg: '#F1EDF5',
    markdownTableBg: '#FFFDFF',
    markdownTableHeaderBg: '#F1EDF5',
    markdownTableAltBg: '#FAF6FC',
    markdownTableBorder: '#ECE8F2'
  },
  dark: {
    primary: '#A897C5',
    primaryLight: '#342D42',
    background: '#1F1D24',
    surface: '#2A2630',
    divider: '#342D42',
    userBubble: '#5F5476',
    userBubbleText: '#FBF8FF',
    aiBubble: '#2A2630',
    textPrimary: '#F1ECF7',
    textSecondary: '#B8AEC4',
    textTertiary: '#83778F',
    markdownTitle: '#F1ECF7',
    markdownText: '#E3DBEC',
    markdownLink: '#BEAFDA',
    markdownLinkBg: '#342D42',
    markdownCodeBg: '#25222B',
    markdownCodeText: '#D0C1E5',
    markdownQuoteBg: '#25222B',
    markdownTableBg: '#2A2630',
    markdownTableHeaderBg: '#352F3D',
    markdownTableAltBg: '#302B37',
    markdownTableBorder: '#342D42'
  }
}

// 松雾绿主题：偏自然的低饱和松绿色，避免荧光薄荷感。
const MINT_THEME: ThemeInfo = {
  id: ColorTheme.MINT,
  nameKey: 'theme_color_mint',
  descriptionKey: 'theme_color_mint_desc',
  previewColors: ['#F7FAF6', '#E5EFE9', '#4D8069', '#587A68'],
  light: {
    primary: '#4D8069',
    primaryLight: '#E5EFE9',
    background: '#F7FAF6',
    surface: '#FEFFFC',
    divider: '#E5EFE9',
    userBubble: '#587A68',
    userBubbleText: '#FFFFFF',
    aiBubble: '#FEFFFC',
    textPrimary: '#202820',
    textSecondary: '#627064',
    textTertiary: '#8C9A8E',
    markdownTitle: '#202820',
    markdownText: '#354238',
    markdownLink: '#4D8069',
    markdownLinkBg: '#E5EFE9',
    markdownCodeBg: '#EEF4EF',
    markdownCodeText: '#4D705E',
    markdownQuoteBg: '#EEF4EF',
    markdownTableBg: '#FEFFFC',
    markdownTableHeaderBg: '#EEF4EF',
    markdownTableAltBg: '#F5F9F5',
    markdownTableBorder: '#E5EFE9'
  },
  dark: {
    primary: '#79A88F',
    primaryLight: '#25372D',
    background: '#1B211D',
    surface: '#242C26',
    divider: '#25372D',
    userBubble: '#4E6F5C',
    userBubbleText: '#F6FFF9',
    aiBubble: '#242C26',
    textPrimary: '#EEF5EE',
    textSecondary: '#AFBBAF',
    textTertiary: '#7D8B80',
    markdownTitle: '#EEF5EE',
    markdownText: '#DDE8DE',
    markdownLink: '#91BAA3',
    markdownLinkBg: '#25372D',
    markdownCodeBg: '#202722',
    markdownCodeText: '#B9D1C2',
    markdownQuoteBg: '#202722',
    markdownTableBg: '#242C26',
    markdownTableHeaderBg: '#2E3730',
    markdownTableAltBg: '#29322B',
    markdownTableBorder: '#25372D'
  }
}

// Notion 极简主题：纯白/深灰底，蓝色强调；浅色 surface/aiBubble 用 Notion 标志性的米白做"块"层次。
const NOTION_THEME: ThemeInfo = {
  id: ColorTheme.NOTION,
  nameKey: 'theme_color_notion',
  descriptionKey: 'theme_color_notion_desc',
  previewColors: ['#FFFFFF', '#E3E8EF', '#2E7AC2', '#1F6AB3'],
  light: {
    primary: '#2E7AC2',
    primaryLight: '#E3E8EF',
    background: '#FFFFFF',
    surface: '#FBFBFA',
    divider: '#E3E8EF',
    userBubble: '#1F6AB3',
    userBubbleText: '#FFFFFF',
    aiBubble: '#F7F6F3',
    textPrimary: '#37352F',
    textSecondary: '#787774',
    textTertiary: '#9B9A97',
    markdownTitle: '#37352F',
    markdownText: '#37352F',
    markdownLink: '#2E7AC2',
    markdownLinkBg: '#E3E8EF',
    markdownCodeBg: '#F7F6F3',
    markdownCodeText: '#EB5757',
    markdownQuoteBg: '#F7F6F3',
    markdownTableBg: '#FBFBFA',
    markdownTableHeaderBg: '#F7F6F3',
    markdownTableAltBg: '#FAFAF8',
    markdownTableBorder: '#E3E8EF'
  },
  dark: {
    primary: '#5B9DD9',
    primaryLight: '#2C3E50',
    background: '#191919',
    surface: '#202020',
    divider: '#2C3E50',
    userBubble: '#3D6A99',
    userBubbleText: '#FFFFFF',
    aiBubble: '#202020',
    textPrimary: '#FFFFFF',
    textSecondary: '#9B9A97',
    textTertiary: '#6F6E69',
    markdownTitle: '#FFFFFF',
    markdownText: '#E3E2E0',
    markdownLink: '#71A7D9',
    markdownLinkBg: '#2C3E50',
    markdownCodeBg: '#2F2F2F',
    markdownCodeText: '#FF6B6B',
    markdownQuoteBg: '#2F2F2F',
    markdownTableBg: '#202020',
    markdownTableHeaderBg: '#2A2A2A',
    markdownTableAltBg: '#252525',
    markdownTableBorder: '#2C3E50'
  }
}

// 精简后的可选主题列表
export const ALL_THEMES: ThemeInfo[] = [
  LAVENDER_THEME,
  DEFAULT_THEME,
  CLAUDE_THEME,
  CHATGPT_THEME,
  MINT_THEME,
  VIOLET_THEME,
  NOTION_THEME
]

// 根据主题 ID 获取主题信息
export function getThemeById(themeId: ColorTheme): ThemeInfo {
  for (let i = 0; i < ALL_THEMES.length; i++) {
    if (ALL_THEMES[i].id === themeId) {
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
