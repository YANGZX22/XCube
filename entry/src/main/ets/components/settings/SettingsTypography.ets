import { VisualEffectsMode } from '../../models/ThemeColors'
import { getAppUiState } from '../../state/AppUiState'
import { ensureManuscriptFonts, MANUSCRIPT_BODY_FONT, MANUSCRIPT_HEADING_FONT } from '../../utils/ManuscriptVisualUtils'

export const SETTINGS_SUBTITLE_LINE_HEIGHT: string = '18fp'
export const SETTINGS_HEADING_CONTENT_GAP: number = 12

export interface SettingsFont extends Font {
  size: number
  weight: FontWeight
  family?: string
}

export class SettingsTypography {
  readonly pageTitle: SettingsFont
  readonly sectionTitle: SettingsFont
  readonly itemTitle: SettingsFont
  readonly fieldLabel: SettingsFont
  readonly subtitle: SettingsFont

  constructor(headingFamily?: string, bodyFamily?: string) {
    this.pageTitle = { size: 18, weight: FontWeight.Bold, family: headingFamily }
    this.sectionTitle = { size: 16, weight: FontWeight.Bold, family: headingFamily }
    this.itemTitle = { size: 15, weight: FontWeight.Medium, family: headingFamily }
    this.fieldLabel = { size: 13, weight: FontWeight.Medium, family: bodyFamily }
    this.subtitle = { size: 12, weight: FontWeight.Regular, family: bodyFamily }
  }
}

const systemTypography = new SettingsTypography()
const manuscriptTypography = new SettingsTypography(MANUSCRIPT_HEADING_FONT, MANUSCRIPT_BODY_FONT)

export function getSettingsTypography(): SettingsTypography {
  if (getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT) {
    ensureManuscriptFonts()
    return manuscriptTypography
  }
  return systemTypography
}
