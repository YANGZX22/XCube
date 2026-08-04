@Observed
class LvImage {
  private imgWidth: number | string = "200"
  private imgHeight: number | string | null = null
  private confGlobal: boolean = false
  private imgUrl: string = ""

  setImgWidth(value: string) {
    this.imgWidth = value
  }

  setImgHeight(value: string) {
    this.imgHeight = value
  }

  setConfGlobal(value: boolean) {
    this.confGlobal = value
  }

  setImgUrl(value: string) {
    this.imgUrl = value
  }

  getImgWidth(): number | string {
    return this.imgWidth
  }

  getImgHeight(): number | string | null {
    return this.imgHeight
  }

  getConfGlobal(): boolean {
    return this.confGlobal
  }

  getImgUrl(): string {
    return this.imgUrl
  }
}

const lvImage = new LvImage()

export { lvImage, LvImage }