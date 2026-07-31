/**
 * 带 Loading 圆环旋转动效的底部居中"回到底部"按钮
 * 仅在 AI 流式生成中且用户不在底部时显示
 */

import { getAppUiState } from '../state/AppUiState'
import { uiMaterial } from '@kit.ArkUI'

@ComponentV2
export struct ScrollToBottomLoadingButton {
  @Param isVisible: boolean = false
  @Param isInputBarVisible: boolean = true
  @Param bottomAvoidHeight: number = 0
  @Event onScrollToBottom: () => void = () => {}

  @Local private loadingAngle: number = 0
  @Local private isPointerActive: boolean = false
  private rotationStarted: boolean = false
  private pointerReleaseTimer: number = -1
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    this.startLoadingRotation()
  }

  aboutToDisappear(): void {
    this.stopLoadingRotation()
  }

  private shouldKeepButtonActive(): boolean {
    return this.isVisible || this.isPointerActive
  }

  private startLoadingRotation(): void {
    if (this.rotationStarted) {
      return
    }
    this.rotationStarted = true
    this.loadingAngle = 0
    setTimeout(() => {
      if (!this.rotationStarted) {
        return
      }
      this.getUIContext().animateTo({
        duration: 1200,
        curve: Curve.Linear,
        iterations: -1,
        playMode: PlayMode.Normal,
        expectedFrameRateRange: { min: 30, max: 120, expected: 60 }
      }, () => {
        this.loadingAngle = 360
      })
    }, 0)
  }

  private stopLoadingRotation(): void {
    this.rotationStarted = false
    if (this.pointerReleaseTimer !== -1) {
      clearTimeout(this.pointerReleaseTimer)
      this.pointerReleaseTimer = -1
    }
    this.isPointerActive = false
    this.loadingAngle = 0
  }

  private schedulePointerRelease(): void {
    if (this.pointerReleaseTimer !== -1) {
      clearTimeout(this.pointerReleaseTimer)
    }
    this.pointerReleaseTimer = setTimeout(() => {
      this.isPointerActive = false
      this.pointerReleaseTimer = -1
    }, 0)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(20)
          .fontColor([this.themePrimary])
      }
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .enabled(this.shouldKeepButtonActive())
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        materialColor: Color.Transparent,
        applyShadow: false,
        interactive: true,
        lightEffect: { color: undefined }
      }))
      .responseRegion({
        x: -4,
        y: -4,
        width: 48,
        height: 48
      })
      .zIndex(2)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.isPointerActive = true
        } else if (event.type === TouchType.Up) {
          this.schedulePointerRelease()
        } else if (event.type === TouchType.Cancel) {
          this.isPointerActive = false
        }
      })
      .onClick(() => {
        this.onScrollToBottom()
      })

      // 外围 loading 圆环只参与绘制，不参与触摸命中。
      Progress({ value: 25, total: 100, type: ProgressType.Ring })
        .width(48)
        .height(48)
        .color(this.themePrimary)
        .backgroundColor('transparent')
        .style({ strokeWidth: 2.5 })
        .rotate({ angle: this.loadingAngle })
        .hitTestBehavior(HitTestMode.None)
        .zIndex(3)
    }
    .width(48)
    .height(48)
    .opacity(this.shouldKeepButtonActive() ? 1 : 0)
    .scale({
      x: this.shouldKeepButtonActive() ? 1 : 0.8,
      y: this.shouldKeepButtonActive() ? 1 : 0.8
    })
    .enabled(this.shouldKeepButtonActive())
    .hitTestBehavior(this.shouldKeepButtonActive() ? HitTestMode.Default : HitTestMode.None)
    .position({ x: '50%', y: '100%' })
    .translate({
      x: '-50%',
      y: this.isInputBarVisible
        ? (-160 - this.bottomAvoidHeight)
        : (-92 - this.bottomAvoidHeight)
    })
    .animation({ duration: 200, curve: Curve.EaseOut })
    .zIndex(20)
  }
}
