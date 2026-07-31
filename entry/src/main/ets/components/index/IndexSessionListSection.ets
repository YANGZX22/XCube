import { uiMaterial } from '@kit.ArkUI'
import { ChatSession } from '../../models/ChatModels'
import { SessionListGroupViewModel, SessionListItemData } from '../../pages/index/IndexSessionListDataSource'
import { IndexSessionListItem } from './IndexSessionListItem'
import { getAppUiState } from '../../state/AppUiState'

@ComponentV2
export struct IndexSessionListSection {
  @Param horizontalPadding: number = 16
  @Param sessionGroups: SessionListGroupViewModel[] = []
  @Param sessionListScroller: ListScroller = new ListScroller()
  @Param isMultiSelectMode: boolean = false
  @Param topSpacerHeight: number = 0
  @Param bottomSpacerHeight: number = 100
  @Param showFavoriteFilterSummary: boolean = false
  @Param favoriteFilterCountText: string = '0'
  @Event onClearFavoriteFilter: () => void = (): void => {}
  @Event onGetGroupTitle: (groupKey: string) => Resource = (_groupKey: string): Resource => $r('app.string.group_older')
  @Event onToggleSelection: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onOpenSession: (session: ChatSession) => void = (_session: ChatSession): void => {}
  @Event onDeleteSession: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onEnterMultiSelect: (sessionId: string) => void = (_sessionId: string): void => {}
  @Event onShareSession: (session: ChatSession) => void = (_session: ChatSession): void => {}
  @Event onToggleFavorite: (session: ChatSession) => void = (_session: ChatSession): void => {}

  private getFavoriteSwipeColor(session: ChatSession): ResourceColor {
    if (session.isFavorite) {
      return $r('app.color.status_error')
    }
    return getAppUiState().themePrimary
  }

  private getSwipeButtonHeight(): number {
    return 56
  }

  @Builder
  private SessionGroupHeader(groupKey: string, count: number) {
    Row() {
      Text(this.onGetGroupTitle(groupKey))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))

      Text(count.toString())
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({ left: this.horizontalPadding, right: this.horizontalPadding, top: 6, bottom: 2 })
  }

  @Builder
  private FavoriteSwipeContent(session: ChatSession) {
    Column() {
      SymbolGlyph(session.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
        .fontSize(18)
        .fontColor([this.getFavoriteSwipeColor(session)])

      Text(session.isFavorite ? $r('app.string.cancel') : $r('app.string.menu_favorite'))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getFavoriteSwipeColor(session))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .margin({ top: 2 })
    }
    .width('100%')
    .height(this.getSwipeButtonHeight())
    .padding({ left: 4, right: 4 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private FavoriteSwipeButton(session: ChatSession) {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        this.FavoriteSwipeContent(session)
      }
      .width(this.getSwipeButtonHeight())
      .height(this.getSwipeButtonHeight())
      .backgroundColor(Color.Transparent)
      .padding(0)
      .onClick(() => {
        this.sessionListScroller.closeAllSwipeActions()
        this.onToggleFavorite(session)
      })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true,
        lightEffect: { color: undefined }
      }))
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .clip(false)
  }

  @Builder
  private DeleteSwipeContent() {
    Column() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(18)
        .fontColor([$r('app.color.status_error')])

      Text($r('app.string.delete'))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.status_error'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .margin({ top: 2 })
    }
    .width('100%')
    .height(this.getSwipeButtonHeight())
    .padding({ left: 4, right: 4 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private DeleteSwipePanel(sessionId: string) {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        this.DeleteSwipeContent()
      }
      .width(this.getSwipeButtonHeight())
      .height(this.getSwipeButtonHeight())
      .backgroundColor(Color.Transparent)
      .padding(0)
      .onClick(() => {
        this.sessionListScroller.closeAllSwipeActions()
        this.onDeleteSession(sessionId)
      })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true,
        lightEffect: { color: undefined }
      }))
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .clip(false)
  }

  @Builder
  private FavoriteFilterSummaryRow() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.heart_fill'))
          .fontSize(14)
          .fontColor([getAppUiState().themePrimary])

        Text($r('app.string.favorite_filter_active'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 6 })

        Text(` · ${this.favoriteFilterCountText}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(VerticalAlign.Center)

      Blank()

      Text($r('app.string.filter_clear'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(getAppUiState().themePrimary)
        .onClick(() => {
          this.onClearFavoriteFilter()
        })
    }
    .width('100%')
    .height(32)
    .padding({ left: this.horizontalPadding, right: this.horizontalPadding })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private SessionGroup(group: SessionListGroupViewModel) {
    ListItemGroup({
      header: this.SessionGroupHeader(group.key, group.count)
    }) {
      LazyForEach(group.dataSource, (item: SessionListItemData, index: number) => {
        ListItem({ style: ListItemStyle.NONE }) {
          Column() {
            IndexSessionListItem({
              item: item,
              isMultiSelectMode: this.isMultiSelectMode,
              onToggleSelection: (sessionId: string): void => {
                this.onToggleSelection(sessionId)
              },
              onOpenSession: (session: ChatSession): void => {
                this.onOpenSession(session)
              },
              onDeleteSession: (sessionId: string): void => {
                this.onDeleteSession(sessionId)
              },
              onEnterMultiSelect: (sessionId: string): void => {
                this.onEnterMultiSelect(sessionId)
              },
              onShareSession: (session: ChatSession): void => {
                this.onShareSession(session)
              },
              onToggleFavorite: (session: ChatSession): void => {
                this.onToggleFavorite(session)
              }
            })
          }
          .width('100%')
          .padding({ left: this.horizontalPadding, right: this.horizontalPadding })
        }
        .margin({
          top: index === 0 ? 4 : 0,
          bottom: 6
        })
        .swipeAction(this.isMultiSelectMode ? undefined : {
          start: this.FavoriteSwipeButton(item.session),
          end: this.DeleteSwipePanel(item.session.id)
        })
        .borderRadius(12)
        .clip(false)
      }, (item: SessionListItemData): string => item.key)
    }
    .divider(null)
  }

  build() {
    List({ scroller: this.sessionListScroller }) {
      if (this.topSpacerHeight > 0) {
        ListItem() {
          Column()
            .height(this.topSpacerHeight)
        }
        .focusable(false)
        .selectable(false)
      }

      if (this.showFavoriteFilterSummary && !this.isMultiSelectMode) {
        ListItem() {
          this.FavoriteFilterSummaryRow()
        }
        .focusable(false)
        .selectable(false)
      }

      ForEach(this.sessionGroups, (group: SessionListGroupViewModel) => {
        this.SessionGroup(group)
      }, (group: SessionListGroupViewModel): string => group.key)

      ListItem() {
        Column()
          .height(this.bottomSpacerHeight)
      }
      .focusable(false)
      .selectable(false)
    }
    .sticky(StickyStyle.None)
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .cachedCount(4)
  }
}
