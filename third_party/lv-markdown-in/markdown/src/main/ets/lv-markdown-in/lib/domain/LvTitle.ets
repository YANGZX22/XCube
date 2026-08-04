@Observed
class LvTitle {
  private level1Title: number | string = 30
  private level2Title: number | string = 28
  private level3Title: number | string = 24
  private level4Title: number | string = 20
  private level5Title: number | string = 16
  private level6Title: number | string = 12
  private levelTitleColor: string = "#181818"

  setLevel1Title(value: number | string) {
    this.level1Title = value
  }

  setLevel2Title(value: number | string) {
    this.level2Title = value
  }

  setLevel3Title(value: number | string) {
    this.level3Title = value
  }

  setLevel4Title(value: number | string) {
    this.level4Title = value
  }

  setLevel5Title(value: number | string) {
    this.level5Title = value
  }

  setLevel6Title(value: number | string) {
    this.level6Title = value
  }

  setLevelTitleColor(value: string) {
    this.levelTitleColor = value
  }

  getLevel1Title(): number | string {
    return this.level1Title
  }

  getLevel2Title(): number | string {
    return this.level2Title
  }

  getLevel3Title(): number | string {
    return this.level3Title
  }

  getLevel4Title(): number | string {
    return this.level4Title
  }

  getLevel5Title(): number | string {
    return this.level5Title
  }

  getLevel6Title(): number | string {
    return this.level6Title
  }

  getLevelTitleColor(): string {
    return this.levelTitleColor
  }
}

const lvTitle = new LvTitle()

export { lvTitle, LvTitle }