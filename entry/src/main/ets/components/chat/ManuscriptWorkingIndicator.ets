import { getAppUiState } from '../../state/AppUiState'
import { MANUSCRIPT_BODY_FONT } from '../../utils/ManuscriptVisualUtils'

const actionVerbs: string[] = [
  'Cubing', 'Accomplishing', 'Actioning', 'Actualizing', 'Baking', 'Brewing', 'Calculating', 'Cerebrating',
  'Churning', 'Coalescing', 'Cogitating', 'Computing', 'Conjuring', 'Considering', 'Cooking', 'Crafting',
  'Creating', 'Crunching', 'Deliberating', 'Determining', 'Doing', 'Effecting', 'Finagling', 'Forging',
  'Forming', 'Generating', 'Hatching', 'Herding', 'Honking', 'Hustling', 'Ideating', 'Inferring',
  'Manifesting', 'Marinating', 'Moseying', 'Mulling', 'Mustering', 'Musing', 'Noodling', 'Percolating',
  'Pondering', 'Processing', 'Puttering', 'Reticulating', 'Ruminating', 'Schlepping', 'Shucking', 'Simmering',
  'Smooshing', 'Spinning', 'Stewing', 'Synthesizing', 'Thinking', 'Transmuting', 'Vibing', 'Working'
]

@ComponentV2
export struct ManuscriptWorkingIndicator {
  @Local private displayedText: string = ''
  @Local private textOpacity: number = 1

  private currentVerbIndex: number = -1
  private characterIndex: number = 0
  private animationTimerId: number = -1
  private animationActive: boolean = false

  aboutToAppear(): void {
    this.animationActive = true
    this.selectNextVerb()
    this.schedule((): void => {
      this.typeNextCharacter()
    }, 140)
  }

  aboutToDisappear(): void {
    this.animationActive = false
    this.clearAnimationTimer()
  }

  private get accentColor(): string {
    return getAppUiState().isDarkMode ? '#C99A52' : '#B68235'
  }

  private clearAnimationTimer(): void {
    if (this.animationTimerId === -1) {
      return
    }
    clearTimeout(this.animationTimerId)
    this.animationTimerId = -1
  }

  private schedule(callback: () => void, delayMs: number): void {
    this.clearAnimationTimer()
    this.animationTimerId = setTimeout((): void => {
      this.animationTimerId = -1
      if (this.animationActive) {
        callback()
      }
    }, delayMs)
  }

  private selectNextVerb(): void {
    if (actionVerbs.length === 0) {
      this.currentVerbIndex = -1
      return
    }
    if (actionVerbs.length === 1) {
      this.currentVerbIndex = 0
    } else if (this.currentVerbIndex < 0) {
      this.currentVerbIndex = Math.floor(Math.random() * actionVerbs.length)
    } else {
      const candidate = Math.floor(Math.random() * (actionVerbs.length - 1))
      this.currentVerbIndex = candidate >= this.currentVerbIndex ? candidate + 1 : candidate
    }
    this.characterIndex = 0
    this.displayedText = ''
    this.textOpacity = 1
  }

  private typeNextCharacter(): void {
    if (this.currentVerbIndex < 0 || this.currentVerbIndex >= actionVerbs.length) {
      return
    }
    const verb = `${actionVerbs[this.currentVerbIndex]}...`
    if (this.characterIndex < verb.length) {
      this.characterIndex += 1
      this.displayedText = verb.substring(0, this.characterIndex)
      this.schedule((): void => {
        this.typeNextCharacter()
      }, 72)
      return
    }
    this.schedule((): void => {
      this.fadeToNextVerb()
    }, 960)
  }

  private fadeToNextVerb(): void {
    const fadeOut = (): void => {
      this.textOpacity = 0
    }
    try {
      this.getUIContext().animateTo({ duration: 140, curve: Curve.EaseOut }, () => {
        fadeOut()
      })
    } catch (_error) {
      fadeOut()
    }
    this.schedule((): void => {
      this.selectNextVerb()
      this.schedule((): void => {
        this.typeNextCharacter()
      }, 120)
    }, 150)
  }

  build() {
    Text(this.displayedText)
      .fontFamily(MANUSCRIPT_BODY_FONT)
      .fontSize(11)
      .fontStyle(FontStyle.Italic)
      .fontColor(this.accentColor)
      .letterSpacing(0.2)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Clip })
      .opacity(this.textOpacity)
      .textAlign(TextAlign.Start)
  }
}
