@Observed
class LvText {
  private textSize: number | string = 15
  private textColor: string = "#1A1A1C"
  private textMarkBackground: string = "#ffffd3b8"
  private textLineHeight: string | number = 24

  setTextSize(value: number | string) {
    this.textSize = value
  }

  setTextColor(value: string) {
    this.textColor = value
  }

  setTextMarkBackground(value: string) {
    this.textMarkBackground = value
  }

  setTextLineHeight(value: string) {
    this.textLineHeight = value
  }

  getTextSize(): number | string {
    return this.textSize
  }

  getTextColor(): string {
    return this.textColor
  }

  getTextMarkBackground(): string {
    return this.textMarkBackground
  }

  getTextLineHeight(): string | number {
    return this.textLineHeight
  }
}

const lvText = new LvText()

export { lvText, LvText }