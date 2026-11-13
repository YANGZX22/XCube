import { hdsEffect } from '@kit.UIDesignKit'
import uiEffect from '@ohos.graphics.uiEffect'

export const BROWSER_VIEWPORT_CORNER_RADIUS: number = 32
export const BROWSER_VIEWPORT_FLOW_WIDTH: number = 24
export const BROWSER_VIEWPORT_FLOW_DURATION: number = 6000

// Mount only while the model is using the browser. This layer draws light, never a backdrop:
// the toolbar's immersive material and the website remain visible through its center.
@ComponentV2
export struct BrowserEdgeFlowLight {
  @Param surfaceWidth: Length = '100%'
  @Param surfaceHeight: Length = '100%'
  @Param cornerRadius: number = 0
  // Distance over which the original glow fades inward, not a solid border or hard clip.
  // Zero retains the native effect used by toolbar buttons.
  @Param edgeWidth: number = 0
  @Param animationDuration: number = 4000
  private maskContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private maskReady: boolean = false
  private controller: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController()
  private effect: uiEffect.VisualEffect = new hdsEffect.HdsEffectBuilder()
    .shaderEffect({
      effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
      animation: { duration: this.animationDuration, iterations: -1, autoPlay: true },
      controller: this.controller,
      params: {
        firstEdgeFlowLight: { startPos: 0, endPos: 1.0, color: '#FF1AD0F1' },
        secondEdgeFlowLight: { startPos: 0.5, endPos: 1.5, color: '#FFFFA4E5' }
      }
    })
    .buildEffect()

  aboutToDisappear(): void {
    this.controller.stop()
  }

  private drawFadeMask(width: number, height: number): void {
    if (!this.maskReady || !Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return
    }
    // Canvas coordinates use vp. Redraw this static alpha mask only when its size changes.
    const context = this.maskContext
    const spread = Math.min(this.edgeWidth, width / 2, height / 2)
    const radius = Math.max(0, Math.min(this.cornerRadius, width / 2, height / 2))
    context.save()
    context.clearRect(0, 0, width, height)
    context.globalCompositeOperation = 'source-over'
    context.globalAlpha = 1
    context.fillStyle = '#FFFFFFFF'
    context.fillRect(0, 0, width, height)
    // Complete, nested contours keep the corner arcs tangent to the straight edges.
    // Avoid independently compositing rectangular gradient tiles at those tangent points.
    context.globalCompositeOperation = 'destination-out'
    const steps = Math.max(1, Math.ceil(spread * 2))
    let previousAlpha = 1
    for (let step = 1; step <= steps; step++) {
      const position = step / steps
      const inset = spread * position
      const alpha = 1 - position * position * (3 - 2 * position)
      // Account for earlier passes so the result follows the same smoothstep fade.
      context.globalAlpha = 1 - alpha / previousAlpha
      context.beginPath()
      context.roundRect(inset, inset, width - inset * 2, height - inset * 2, Math.max(0, radius - inset))
      context.fill()
      previousAlpha = alpha
    }
    context.restore()
  }

  build() {
    Stack() {
      Stack() {}
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .borderRadius(this.cornerRadius)
        .visualEffect(this.effect)
        .clip(true)
        .onAppear(() => this.controller.play())

      if (this.edgeWidth > 0) {
        Canvas(this.maskContext)
          .width('100%')
          .height('100%')
          // Composite the complete alpha mask, including its transparent center.
          // No blur filter or sharp inner clipping edge is applied to the original shader.
          .blendMode(BlendMode.DST_IN, BlendApplyType.OFFSCREEN)
          .onReady(() => {
            this.maskReady = true
            this.drawFadeMask(this.maskContext.width, this.maskContext.height)
          })
          .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
            this.drawFadeMask(Number(size.width), Number(size.height))
          })
      }
    }
    .width(this.surfaceWidth)
    .height(this.surfaceHeight)
    .borderRadius(this.cornerRadius)
    .clip(true)
    .blendMode(this.edgeWidth > 0 ? BlendMode.SRC_OVER : undefined, BlendApplyType.OFFSCREEN)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no')
  }
}
