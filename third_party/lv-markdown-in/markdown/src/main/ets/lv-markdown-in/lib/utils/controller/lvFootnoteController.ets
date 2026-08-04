@Observed
export class LvFootnoteController {
  footnoteList: string = ""

  setFootnoteList(item: string) {
    this.footnoteList = (item)
  }

  getFootnoteList() {
    return this.footnoteList
  }
}

export const lvFootnoteController = new LvFootnoteController()