import { ChatSession } from '../../models/ChatModels'
import { SessionCard } from '../SessionCard'
import { SessionListItemData } from '../../pages/index/IndexSessionListDataSource'
import { getAppUiState } from '../../state/AppUiState'
import { VisualEffectsMode } from '../../models/ThemeColors'
import { getSessionDisplayPreviewText } from '../../utils/ChatSessionDisplayHelper'
import {
  ensureManuscriptFonts,
  MANUSCRIPT_BODY_FONT,
  MANUSCRIPT_HEADING_FONT,
  toRomanNumeral
} from '../../utils/ManuscriptVisualUtils'

@ComponentV2
export struct IndexSessionListItem {
  @Param item: SessionListItemData = new SessionListItemData(new ChatSession('', '', ''), false, false)
  @Param isMultiSelectMode: boolean = false
  @Local pressed: boolean = false
  @Event onToggleSelection: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onOpenSession: (session: ChatSession) => void = (_session: ChatSession): void => {}
  @Event onDeleteSession: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onEnterMultiSelect: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onShareSession: (session: ChatSession) => void = (_session: ChatSession): void => {}
  @Event onToggleFavorite: (session: ChatSession) => void = (_session: ChatSession): void => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  aboutToAppear(): void {
    ensureManuscriptFonts()
  }

  private getTimeText(): string {
    const date = new Date(this.item.session.updatedAt)
    const now = new Date()
    const elapsedDays = Math.floor((now.getTime() - date.getTime()) / 86400000)
    if (elapsedDays >= 0 && elapsedDays < 7) {
      const weekdays: string[] = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
      return weekdays[date.getDay()]
    }
    const months: string[] = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    return `${months[date.getMonth()]} ${date.getDate().toString()}`
  }

  private getExcerpt(): string | Resource {
    const preview = getSessionDisplayPreviewText(this.item.session)
    return preview !== '' ? preview : $r('app.string.session_no_preview')
  }

  @Builder
  private ManuscriptSessionRow() {
    Column({ space: 5 }) {
      Row({ space: 8 }) {
        Text(toRomanNumeral(this.item.ordinal))
          .width(26)
          .fontFamily(MANUSCRIPT_HEADING_FONT)
          .fontSize(15)
          .fontWeight(600)
          .fontColor(getAppUiState().isDarkMode ? '#D9B274' : '#8A6228')
          .fontFeature('tnum')

        Text(this.item.session.title)
          .fontFamily(MANUSCRIPT_HEADING_FONT)
          .fontSize(19)
          .fontWeight(600)
          .fontColor(getAppUiState().themeTextPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '55%' })

        Column()
          .height(1)
          .border({
            width: { top: 1 },
            color: getAppUiState().isDarkMode ? '#4A463F' : '#C9C4BB',
            style: BorderStyle.Dotted
          })
          .layoutWeight(1)
          .constraintSize({ minWidth: 18 })

        Text(this.getTimeText())
          .fontFamily(MANUSCRIPT_BODY_FONT)
          .fontSize(11.5)
          .fontColor(getAppUiState().themeTextTertiary)
          .fontFeature('tnum')
          .maxLines(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.getExcerpt())
        .width('100%')
        .fontFamily(MANUSCRIPT_BODY_FONT)
        .fontSize(12.5)
        .fontStyle(FontStyle.Italic)
        .fontColor(getAppUiState().themeTextSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 34 })
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 14, bottom: 12 })
    .backgroundColor(this.pressed ? (getAppUiState().isDarkMode ? '#33291B' : '#F5EDE0') : Color.Transparent)
    .border({
      width: { bottom: 0.5, left: this.item.isSelected || this.item.isActive ? 2 : 0 },
      color: this.item.isSelected || this.item.isActive ? this.themePrimary : getAppUiState().themeDivider
    })
    .onTouch((event: TouchEvent) => {
      this.pressed = event.type === TouchType.Down
    })
    .onClick(() => {
      this.handleTap()
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          if (!this.isMultiSelectMode) {
            this.onEnterMultiSelect(this.item.session.id)
          }
        })
    )
  }

  private handleTap(): void {
    if (this.isMultiSelectMode) {
      this.onToggleSelection(this.item.session.id)
      return
    }
    this.onOpenSession(this.item.session)
  }

  build() {
    if (this.isManuscriptMode) {
      this.ManuscriptSessionRow()
    } else {
      SessionCard({
      session: this.item.session,
      enableAnimation: false,
      enableContextMenu: !this.isMultiSelectMode,
      onTap: (): void => {
        this.handleTap()
      },
      onDelete: (): void => {
        this.onDeleteSession(this.item.session.id)
      },
      onMultiSelect: (): void => {
        this.onEnterMultiSelect(this.item.session.id)
      },
      onShare: (): void => {
        this.onShareSession(this.item.session)
      },
      onToggleFavorite: (): void => {
        this.onToggleFavorite(this.item.session)
      }
    })
      .borderRadius(12)
      .clip(false)
      .border({
        width: 2,
        color: this.item.isSelected || this.item.isActive ? this.themePrimary : Color.Transparent
      })
      .opacity(this.isMultiSelectMode && !this.item.isSelected ? 0.5 : 1)
      .animation({ duration: 200 })
    }
  }
}
