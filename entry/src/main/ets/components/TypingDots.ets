import { curves } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'

@ComponentV2
struct StatusPulseDot {
  @Require @Param delayMs: number
  @Local private strength: number = 0.29
  private started: boolean = false

  private start(): void {
    if (this.started) return
    this.started = true
    this.getUIContext().keyframeAnimateTo({ delay: this.delayMs, iterations: -1 }, [
      { duration: 60, event: () => { this.strength = 0.29 } },
      { duration: 120, curve: curves.cubicBezierCurve(0.165, 0.84, 0.44, 1), event: () => { this.strength = 1 } },
      { duration: 120, event: () => { this.strength = 1 } },
      { duration: 480, curve: Curve.EaseOut, event: () => { this.strength = 0.29 } },
      { duration: 420, event: () => { this.strength = 0.29 } }
    ])
  }

  build() {
    Circle()
      .width(3)
      .height(3)
      .fill(getAppUiState().themePrimary)
      .opacity(this.strength)
      .onSizeChange((): void => { this.start() })
  }
}

@Builder
export function statusPulseDots(leftMargin: number = 0) {
  if (!getAppUiState().appInBackground) {
    Row({ space: 2 }) {
      ForEach([0, 180, 360], (delay: number) => {
        StatusPulseDot({ delayMs: delay })
      }, (delay: number) => delay.toString())
    }
    .margin({ left: leftMargin })
    .flexShrink(0)
    .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS)
    .accessibilityLevel('no-hide-descendants')
  }
}

@ComponentV2
export struct TypingDots {
  @Param dotSize: number = 7
  @Param spacing: number = 5
  @Param color: string = ''

  @Local private dot1Scale: number = 0.6
  @Local private dot2Scale: number = 0.6
  @Local private dot3Scale: number = 0.6
  private dotAnimationTimer: number = -1

  private get themePrimary(): string {
    return this.color !== '' ? this.color : getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    this.startAnimation()
  }

  aboutToDisappear(): void {
    this.stopAnimation()
  }

  private applyDotScaleState(activeDot: number): void {
    const updateState = (): void => {
      this.dot1Scale = 0.6
      this.dot2Scale = 0.6
      this.dot3Scale = 0.6

      if (activeDot === 0) {
        this.dot1Scale = 1.0
      } else if (activeDot === 1) {
        this.dot2Scale = 1.0
      } else {
        this.dot3Scale = 1.0
      }
    }

    try {
      this.getUIContext().animateTo({
        duration: 280,
        curve: Curve.EaseInOut
      }, () => {
        updateState()
      })
    } catch (_error) {
      updateState()
    }
  }

  private startAnimation(): void {
    if (this.dotAnimationTimer !== -1) {
      return
    }

    let step = 0
    this.applyDotScaleState(step)
    step = 1
    this.dotAnimationTimer = setInterval(() => {
      this.applyDotScaleState(step)
      step = (step + 1) % 3
    }, 320)
  }

  private stopAnimation(): void {
    if (this.dotAnimationTimer !== -1) {
      clearInterval(this.dotAnimationTimer)
      this.dotAnimationTimer = -1
    }
    this.dot1Scale = 0.6
    this.dot2Scale = 0.6
    this.dot3Scale = 0.6
  }

  build() {
    Row({ space: this.spacing }) {
      Column()
        .width(this.dotSize)
        .height(this.dotSize)
        .borderRadius(this.dotSize / 2)
        .backgroundColor(this.themePrimary)
        .scale({ x: this.dot1Scale, y: this.dot1Scale })
        .opacity(0.45 + this.dot1Scale * 0.55)

      Column()
        .width(this.dotSize)
        .height(this.dotSize)
        .borderRadius(this.dotSize / 2)
        .backgroundColor(this.themePrimary)
        .scale({ x: this.dot2Scale, y: this.dot2Scale })
        .opacity(0.45 + this.dot2Scale * 0.55)

      Column()
        .width(this.dotSize)
        .height(this.dotSize)
        .borderRadius(this.dotSize / 2)
        .backgroundColor(this.themePrimary)
        .scale({ x: this.dot3Scale, y: this.dot3Scale })
        .opacity(0.45 + this.dot3Scale * 0.55)
    }
  }
}
