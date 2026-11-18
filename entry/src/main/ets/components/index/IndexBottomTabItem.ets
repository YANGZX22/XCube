import { getAppUiState } from '../../state/AppUiState'
import { createButtonTouchHandler, getButtonAnimation, getButtonScale } from '../../utils/ButtonAnimationUtils'
import { VisualEffectsMode } from '../../models/ThemeColors'
import {
  ensureManuscriptFonts,
  getManuscriptAccent,
  MANUSCRIPT_BODY_FONT
} from '../../utils/ManuscriptVisualUtils'

@ComponentV2
export struct IndexBottomTabItem {
  @Param active: boolean = false
  @Param collapsed: boolean = false
  @Param bounceTrigger: number = -1
  @Param navigationTransitionId: string = ''
  @Param activeIcon: Resource = $r('sys.symbol.circle')
  @Param inactiveIcon: Resource = $r('sys.symbol.circle')
  @Param label: Resource = $r('app.string.tab_chat')
  @Param manuscriptLabel: string | Resource = ''
  @Param badgeCount: number = 0
  @Param disablePressScale: boolean = false
  @Local pressed: boolean = false
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  aboutToAppear(): void {
    ensureManuscriptFonts()
  }

  build() {
    if (this.isManuscriptMode && !this.collapsed) {
      // 书籍页脚导航：大写目录标签 + 选中项短鎏金书签线。
      Column({ space: 5 }) {
        Row({ space: 3 }) {
          Text(this.manuscriptLabel === '' ? this.label : this.manuscriptLabel)
            .geometryTransition(this.navigationTransitionId)
            .transition(this.navigationTransitionId ? TransitionEffect.OPACITY : undefined)
            .fontFamily(MANUSCRIPT_BODY_FONT)
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.active ? this.themePrimary : getAppUiState().themeTextSecondary)
            .letterSpacing(1.4)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.badgeCount > 0) {
            Text(this.badgeCount > 99 ? '99+' : this.badgeCount.toString())
              .fontFamily(MANUSCRIPT_BODY_FONT)
              .fontSize(8)
              .fontColor(this.themePrimary)
          }
        }

        Column()
          .width(this.active ? 34 : 0)
          .height(1)
          .backgroundColor(getManuscriptAccent(getAppUiState().isDarkMode))
          .opacity(this.active ? 1 : 0)
          .animation({ duration: 220, curve: Curve.EaseOut })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .scale(getButtonScale(this.pressed, {
        pressedScale: 0.96,
        animationDuration: 120,
        animationCurve: Curve.EaseOut
      }))
      .animation(getButtonAnimation({
        pressedScale: 0.96,
        animationDuration: 120,
        animationCurve: Curve.EaseOut
      }))
      .onTouch(createButtonTouchHandler((pressed: boolean) => {
        this.pressed = pressed
      }))
    } else {
      Column({ space: this.collapsed ? 0 : 1 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.active ? this.activeIcon : this.inactiveIcon)
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .fontSize(this.collapsed ? 24 : 22)
          .fontColor(this.active ? [this.themePrimary] : [$r('app.color.text_secondary')])
          .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE), this.bounceTrigger)
          .geometryTransition(this.navigationTransitionId)
          .transition(this.navigationTransitionId ? TransitionEffect.OPACITY : undefined)

        if (this.badgeCount > 0) {
          Row() {
            Text(this.badgeCount > 99 ? '99+' : this.badgeCount.toString())
              .fontSize(9)
              .fontColor($r('sys.color.comp_background_list_card'))
              .fontWeight(FontWeight.Medium)
          }
          .height(14)
          .padding({ left: 4, right: 4 })
          .borderRadius(7)
          .backgroundColor($r('app.color.status_error'))
          .position({ x: 16, y: -8 })
        }
      }
      .width(28)
      .height(24)

      Text(this.label)
        .width('100%')
        .height(this.collapsed ? 0 : undefined)
        .opacity(this.collapsed ? 0 : 1)
        .transition(this.navigationTransitionId ? TransitionEffect.OPACITY : undefined)
        .textAlign(TextAlign.Center)
        .fontSize(10)
        .minFontSize(9)
        .maxFontSize(10)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.active ? this.themePrimary : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .scale(getButtonScale(this.pressed && !this.disablePressScale, {
      pressedScale: 0.92,
      animationDuration: 120,
      animationCurve: Curve.EaseOut
    }))
    .animation(getButtonAnimation({
      pressedScale: 0.92,
      animationDuration: 120,
      animationCurve: Curve.EaseOut
    }))
      .onTouch(createButtonTouchHandler((pressed: boolean) => {
        this.pressed = pressed
      }))
    }
  }
}
