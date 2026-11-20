import { getAppUiState } from '../../state/AppUiState'
import { ReplySpeedTier } from '../../utils/ReplyStatistics'

function animalIcon(tier: ReplySpeedTier): Resource {
  if (tier === ReplySpeedTier.RABBIT) return $r('app.media.lucide_rabbit')
  if (tier === ReplySpeedTier.TURTLE) return $r('app.media.lucide_turtle')
  return $r('app.media.lucide_snail')
}

@ComponentV2
struct AnimalGait {
  @Require @Param tier: ReplySpeedTier
  @Require @Param iterations: number
  @Local private x: number = 0
  @Local private y: number = 0
  @Local private tilt: number = 0
  @Local private stretch: number = 1
  private started: boolean = false

  private pose(duration: number, x: number = 0, y: number = 0, tilt: number = 0, stretch: number = 1): KeyframeState {
    return { duration, curve: Curve.EaseInOut, event: (): void => {
      this.x = x
      this.y = y
      this.tilt = tilt
      this.stretch = stretch
    } }
  }

  private frames(): KeyframeState[] {
    if (this.tier === ReplySpeedTier.SNAIL) {
      return [this.pose(650, 1.4, 0, 0, 1.12), this.pose(430, 0.6, 0, 0, 0.95), this.pose(360)]
    }
    if (this.tier === ReplySpeedTier.TURTLE) {
      return [this.pose(240, 0.6, -0.6, -4), this.pose(230, 1.4, 0, 3),
        this.pose(240, 0.6, -0.6, -3), this.pose(230)]
    }
    return [this.pose(110, -0.6, 0.4, 3, 1.08), this.pose(200, 1.4, -3.2, -7, 0.96),
      this.pose(150, 2.1, 0, 2, 1.06), this.pose(220)]
  }

  build() {
    Image(animalIcon(this.tier))
      .id('reply-speed-' + this.tier)
      .width(20)
      .height(20)
      .supportSvg2(true)
      .colorFilter(getAppUiState().themePrimary)
      .draggable(false)
      .scale({ x: this.stretch, y: 1 / this.stretch, centerY: '100%' })
      .rotate({ angle: this.tilt, centerY: '85%' })
      .translate({ x: this.x, y: this.y })
      .onSizeChange((): void => {
        if (this.started || this.iterations === 0) return
        this.started = true
        this.getUIContext().keyframeAnimateTo({ iterations: this.iterations }, this.frames())
      })
  }
}

@ComponentV2
export struct ReplySpeedIcon {
  @Require @Param tier: ReplySpeedTier
  @Require @Param isGenerating: boolean
  @Require @Param modelRoundActive: boolean
  @Local private visible: boolean = false
  private openedDuringGeneration: boolean = false

  aboutToAppear(): void {
    this.openedDuringGeneration = this.isGenerating
  }

  private get iterations(): number {
    if (!this.visible || getAppUiState().appInBackground) return 0
    if (this.isGenerating) return this.modelRoundActive ? -1 : 0
    return this.openedDuringGeneration ? 0 : 1
  }

  build() {
    Stack() {
      if (this.tier === ReplySpeedTier.UNKNOWN) {
        SymbolGlyph($r('sys.symbol.bolt'))
          .fontSize(20)
          .fontColor([getAppUiState().themePrimary])
      } else {
        // 换档、停止或离开可见区域时，旧节点和它的原生动画一起释放。
        ForEach([`${this.tier}:${this.iterations}`], (_key: string) => {
          AnimalGait({ tier: this.tier, iterations: this.iterations })
        }, (key: string): string => key)
      }
    }
    .width(20)
    .height(26)
    .flexShrink(0)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
    .onVisibleAreaChange([0.01], (visible: boolean): void => { this.visible = visible })
  }
}
