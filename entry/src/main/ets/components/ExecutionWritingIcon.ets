const ICON_SIZE: number = 14
const GLYPH_SIZE: number = 12

@Extend(Image)
function writingGlyph(tint: ResourceColor) {
  .width(GLYPH_SIZE)
  .height(GLYPH_SIZE)
  .supportSvg2(true)
  .colorFilter(tint)
  .draggable(false)
}

@ComponentV2
struct WritingStrokes {
  @Require @Param tint: ResourceColor
  @Local private offsetX: number = -1.3
  @Local private offsetY: number = 0
  @Local private tilt: number = 0
  @Local private featherOpacity: number = 1
  private started: boolean = false

  private moveTip(x: number, y: number, angle: number): void {
    this.offsetX = x
    this.offsetY = y
    this.tilt = angle
  }

  private strokeFrames(nextIsFeather: boolean): KeyframeState[] {
    return [
      { duration: 160, curve: Curve.EaseOut, event: (): void => { this.moveTip(-0.6, 0.9, -8) } },
      { duration: 140, curve: Curve.EaseInOut, event: (): void => { this.moveTip(0.4, -0.4, 3) } },
      { duration: 180, curve: Curve.EaseOut, event: (): void => { this.moveTip(1.7, 0.7, -5) } },
      { duration: 170, curve: Curve.EaseOut, event: (): void => { this.moveTip(0.6, -0.75, 5) } },
      // 抬笔时换笔，再回到下一笔的起点。
      { duration: 210, curve: Curve.EaseInOut, event: (): void => {
        this.featherOpacity = nextIsFeather ? 1 : 0
        this.moveTip(-1.3, -1.1, 5)
      } },
      { duration: 150, curve: Curve.EaseIn, event: (): void => { this.moveTip(-1.3, 0, 0) } }
    ]
  }

  private start(): void {
    if (!this.started) {
      this.started = true
      this.getUIContext().keyframeAnimateTo({ iterations: -1 },
        this.strokeFrames(false).concat(this.strokeFrames(true)))
    }
  }

  build() {
    Stack() {
      Image($r('app.media.lucide_pencil'))
        .writingGlyph(this.tint)
        .opacity(1 - this.featherOpacity)
      Image($r('app.media.lucide_feather'))
        .writingGlyph(this.tint)
        .opacity(this.featherOpacity)
    }
    .width(ICON_SIZE)
    .height(ICON_SIZE)
    // 两枚 Lucide 图标的笔尖都靠近 (2, 22)，居中缩放后以笔尖为轴。
    .rotate({ angle: this.tilt, centerX: 2, centerY: ICON_SIZE - 2 })
    .translate({ x: this.offsetX, y: this.offsetY })
    .onSizeChange((): void => { this.start() })
  }
}

@ComponentV2
export struct ExecutionWritingIcon {
  @Require @Param isActive: boolean
  @Require @Param tint: ResourceColor
  @Local private visible: boolean = false

  build() {
    Stack() {
      if (this.isActive && this.visible) {
        WritingStrokes({ tint: this.tint })
      } else {
        Image($r('app.media.lucide_feather'))
          .writingGlyph(this.tint)
      }
    }
    .width(ICON_SIZE)
    .height(ICON_SIZE)
    .flexShrink(0)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
    .onVisibleAreaChange([0.01], (visible: boolean): void => { this.visible = visible })
  }
}
