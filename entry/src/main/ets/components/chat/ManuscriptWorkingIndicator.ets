import { getAppUiState } from '../../state/AppUiState'
import { MANUSCRIPT_BODY_FONT } from '../../utils/ManuscriptVisualUtils'

const actionVerbs: string[] = [
  'Accomplishing', 'Actioning', 'Actualizing', 'Architecting', 'Baking', 'Beaming', "Beboppin'", 'Befuddling',
  'Billowing', 'Blanching', 'Bloviating', 'Boogieing', 'Boondoggling', 'Booping', 'Bootstrapping', 'Brewing',
  'Bunning', 'Burrowing', 'Calculating', 'Canoodling', 'Caramelizing', 'Cascading', 'Catapulting', 'Cerebrating',
  'Channeling', 'Channelling', 'Choreographing', 'Churning', 'Coalescing', 'Cogitating',
  'Combobulating', 'Composing', 'Computing', 'Concocting', 'Considering', 'Contemplating', 'Cooking', 'Crafting',
  'Creating', 'Crunching', 'Crystallizing', 'Cultivating', 'Deciphering', 'Deliberating', 'Determining',
  'Dilly-dallying', 'Discombobulating', 'Doing', 'Doodling', 'Drizzling', 'Ebbing', 'Effecting', 'Elucidating',
  'Embellishing', 'Enchanting', 'Envisioning', 'Evaporating', 'Fermenting', 'Fiddle-faddling', 'Finagling',
  'Flambéing', 'Flibbertigibbeting', 'Flowing', 'Flummoxing', 'Fluttering', 'Forging', 'Forming', 'Frolicking',
  'Frosting', 'Gallivanting', 'Galloping', 'Garnishing', 'Generating', 'Gesticulating', 'Germinating', 'Gitifying',
  'Grooving', 'Gusting', 'Harmonizing', 'Hashing', 'Hatching', 'Herding', 'Honking', 'Hullaballooing',
  'Hyperspacing', 'Ideating', 'Imagining', 'Improvising', 'Incubating', 'Inferring', 'Infusing', 'Ionizing',
  'Jitterbugging', 'Julienning', 'Kneading', 'Leavening', 'Levitating', 'Lollygagging', 'Manifesting',
  'Marinating', 'Meandering', 'Metamorphosing', 'Misting', 'Moonwalking', 'Moseying', 'Mulling', 'Mustering',
  'Musing', 'Nebulizing', 'Nesting', 'Newspapering', 'Noodling', 'Nucleating', 'Orbiting', 'Orchestrating',
  'Osmosing', 'Perambulating', 'Percolating', 'Perusing', 'Philosophising', 'Photosynthesizing', 'Pollinating',
  'Pondering', 'Pontificating', 'Pouncing', 'Precipitating', 'Prestidigitating', 'Processing', 'Proofing',
  'Propagating', 'Puttering', 'Puzzling', 'Quantumizing', 'Razzle-dazzling', 'Razzmatazzing', 'Recombobulating',
  'Reticulating', 'Roosting', 'Ruminating', 'Sautéing', 'Scampering', 'Schlepping', 'Scurrying', 'Seasoning',
  'Shenaniganing', 'Shimmying', 'Simmering', 'Skedaddling', 'Sketching', 'Slithering', 'Smooshing',
  'Sock-hopping', 'Spelunking', 'Spinning', 'Sprouting', 'Stewing', 'Sublimating', 'Swirling', 'Swooping',
  'Symbioting', 'Synthesizing', 'Tempering', 'Thinking', 'Thundering', 'Tinkering', 'Tomfoolering',
  'Topsy-turvying', 'Transfiguring', 'Transmuting', 'Twisting', 'Undulating', 'Unfurling', 'Unravelling',
  'Vibing', 'Waddling', 'Wandering', 'Warping', 'Whatchamacalliting', 'Whirlpooling', 'Whirring', 'Whisking',
  'Wibbling', 'Working', 'Wrangling', 'XCubing', 'Zesting', 'Zigzagging'
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
