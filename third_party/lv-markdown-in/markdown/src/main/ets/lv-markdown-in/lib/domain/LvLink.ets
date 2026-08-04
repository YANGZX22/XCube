@Observed
class LvLink {
  private textSize: number | string = 15
  private textColor: string = "#0664EC"
  private textUnderline: boolean = false
  private linkUrl: string = ""

  setTextSize(value: number | string) {
    this.textSize = value
  }

  setTextColor(value: string) {
    this.textColor = value
  }

  setTextUnderline(value: boolean) {
    this.textUnderline = value
  }

  setLinkUrl(value: string) {
    this.linkUrl = value
  }

  getTextSize(): number | string {
    return this.textSize
  }

  getTextColor(): string {
    return this.textColor
  }

  getTextUnderline(): boolean {
    return this.textUnderline
  }

  getLinkUrl(): string {
    return this.linkUrl
  }
}

const lvLink = new LvLink()

export { lvLink, LvLink }