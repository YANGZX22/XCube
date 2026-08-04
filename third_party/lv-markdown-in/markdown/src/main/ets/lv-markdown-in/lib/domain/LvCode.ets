type Theme = "light" | "dark"

@Observed
class LvCode {
  private theme: Theme = "dark"
  private indexState: boolean = false

  setTheme(value: Theme) {
    this.theme = value
  }

  setIndexState(indexState: boolean) {
    this.indexState = indexState
  }

  getTheme(): string {
    return this.theme
  }

  getIndexState(): boolean {
    return this.indexState
  }
}

const lvCode = new LvCode()

export { lvCode, LvCode }