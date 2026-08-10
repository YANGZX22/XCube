import { getAppUiState } from '../../state/AppUiState'

@ComponentV2
export struct ManuscriptTopArcButton {
  @Param symbol: Resource = $r('sys.symbol.circle')
  @Param active: boolean = false
  @Param destructive: boolean = false
  @Local pressed: boolean = false
  @Event onTap: () => void = (): void => {}

  private getArcColor(): ResourceColor {
    if (this.destructive) {
      return $r('app.color.status_error')
    }
    return this.active || this.pressed
      ? (getAppUiState().isDarkMode ? '#D9B274' : '#8A6228')
      : (getAppUiState().isDarkMode ? '#C99A52' : '#B68235')
  }

  private getIconColor(): ResourceColor {
    if (this.destructive) {
      return $r('app.color.status_error')
    }
    if (this.active || this.pressed) {
      return getAppUiState().isDarkMode ? '#D9B274' : '#8A6228'
    }
    return getAppUiState().themeTextSecondary
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph(this.symbol)
          .fontSize(18)
          .fontColor([this.getIconColor()])
          .hitTestBehavior(HitTestMode.None)
      }
      .width(44)
      .height(44)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .borderRadius(0)
      .border({ width: 0, color: Color.Transparent })
      .onTouch((event: TouchEvent) => {
        this.pressed = event.type === TouchType.Down
      })
      .onClick(() => {
        this.pressed = false
        this.onTap()
      })
    }
    .width(44)
    .height(44)
    .backgroundColor(Color.Transparent)
    .borderRadius(22)
    .border({
      width: { bottom: this.pressed ? 1.5 : 1 },
      color: this.getArcColor()
    })
  }
}
