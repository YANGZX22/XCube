export class QuoteController {
  private backgroundColor: string = "#dbf2f3f5"
  private borderColor: string = "#0A58F6"

  setBackgroundColor(value: string) {
    this.backgroundColor = value
  }

  setBorderColor(value: string) {
    this.borderColor = value
  }

  getBackgroundColor(): string {
    return this.backgroundColor
  }

  getBorderColor(): string {
    return this.borderColor
  }
}