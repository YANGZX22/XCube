/**
 * ChatCube 品牌 Loading 动效组件 — 围绕 app icon 卡通形象设计
 *
 * 四种变体 (export 名保留, 实现已重写):
 *   A) CubeSpinnerLight     - 看四周笑脸: 主题色圆角脸 + 双白点眼睛
 *                             眼睛同步左右扫视 (中→右→中→左) + 整体微呼吸
 *                             AI "在搜寻 / 思考" 的 loading 隐喻
 *                             适合: 标题旁小指示器、通用 loading (12 - 32vp)
 *
 *   B) CubeSpinnerBubble    - 立体气泡: TypingDots 气泡 + 后侧暗色厚度面 + 微 Y 轴摆动
 *                             视觉上像 icon 上的右前对话面在轻微转动
 *                             适合: 聊天里 AI 思考中
 *
 *   C) CubeSpinnerAssemble  - 像素扫描: 圆角方框 + 4×4 主题色格子从左上到右下逐格点亮
 *                             点亮是离散切换 (不插值) 以保留 8-bit / 生图 AI 逐步渲染感
 *                             适合: 生图占位 (≥ 56vp)
 *
 *   D) CubeSpinner3D        - 跑步小人: 完整 ChatCube 形象 (身子 + 双手 + 双腿 + 椭圆阴影)
 *                             两脚两手交替摆动, 整体上下跳, 阴影同步缩放
 *                             适合: 中大尺寸 (≥ 64vp), 加载等待场景
 *
 * 实现要点:
 *   - 仅用 Path / Column / Row 等基础组件, 无外部资源
 *   - 用 animateTo iterations: -1 走系统动画线程, 不挤占 JS 计时器
 *   - 动画启动必须挂在 .onAppear() (参考 ScrollToBottomLoadingButton.ets)
 *   - 老虎机停顿感用 cubicBezier(0, 0.7, 0.4, 1) 实现"快滚 → 慢停 → 重启"
 */

import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { TypingDots } from '../TypingDots'

// =============================================================================
// 变体 A: CubeSpinnerLight - 看四周笑脸 + 微呼吸
// =============================================================================
@ComponentV2
export struct CubeSpinnerLight {
  @Param sizeVp: number = 32
  @Param color: string = ''
  @Param motionScale: number = 1
  @Local private eyeOffsetX: number = 0
  @Local private breathScale: number = 1.0
  @Local private headTilt: number = -2
  private scanTimer: number = -1
  private scanPhase: number = 0
  private started: boolean = false

  private get faceColor(): string {
    return this.color !== '' ? this.color : getAppUiState().themePrimary
  }

  private get effectiveMotionScale(): number {
    return Math.max(0.5, this.motionScale)
  }

  aboutToDisappear(): void {
    if (this.scanTimer !== -1) {
      clearInterval(this.scanTimer)
      this.scanTimer = -1
    }
  }

  private startAnimations(): void {
    if (this.started) return
    this.started = true
    this.startBreath()
    this.startScanLoop()
  }

  private startBreath(): void {
    try {
      this.getUIContext().animateTo({
        duration: 1300,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate,
        expectedFrameRateRange: { min: 30, max: 120, expected: 60 }
      }, (): void => {
        this.breathScale = 1 + 0.055 * this.effectiveMotionScale
      })
    } catch (_error) {
    }
  }

  // 左右扫视: 中 → 右 → 中 → 左 → 中, 每阶段 700ms (整轮 2.8s)
  // 模拟 AI "环顾思考" 的动作, 比眨眼更能传达 loading 语义
  private startScanLoop(): void {
    if (this.scanTimer !== -1) return
    const scanAmt: number = this.sizeVp * 0.05 * this.effectiveMotionScale
    const tiltAmt: number = 2.5 * this.effectiveMotionScale
    const targets: number[] = [scanAmt, 0, -scanAmt, 0]
    const tilts: number[] = [tiltAmt, -tiltAmt * 0.55, -tiltAmt, tiltAmt * 0.55]
    this.scanTimer = setInterval((): void => {
      const target: number = targets[this.scanPhase]
      const tilt: number = tilts[this.scanPhase]
      this.scanPhase = (this.scanPhase + 1) % 4
      try {
        this.getUIContext().animateTo({
          duration: 460,
          curve: Curve.EaseInOut
        }, (): void => {
          this.eyeOffsetX = target
          this.headTilt = tilt
        })
      } catch (_error) {
        this.eyeOffsetX = target
        this.headTilt = tilt
      }
    }, 640)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 脸面背景
      Column()
        .width(this.sizeVp)
        .height(this.sizeVp * 0.92)
        .backgroundColor(this.faceColor)
        .borderRadius(this.sizeVp * 0.22)
      // 双眼 (Row 整体左右扫视 — 两眼同步)
      Row({ space: this.sizeVp * 0.20 }) {
        this.Eye()
        this.Eye()
      }
      .translate({ x: this.eyeOffsetX })
    }
    .width(this.sizeVp)
    .height(this.sizeVp)
    .scale({ x: this.breathScale, y: this.breathScale, centerX: '50%', centerY: '50%' })
    .rotate({ angle: this.headTilt, centerX: '50%', centerY: '50%' })
    .onAppear((): void => {
      this.startAnimations()
    })
  }

  @Builder
  private Eye() {
    Column()
      .width(this.sizeVp * 0.16)
      .height(this.sizeVp * 0.16)
      .borderRadius(this.sizeVp * 0.08)
      .backgroundColor('#FFFFFF')
  }
}

// =============================================================================
// 变体 B: CubeSpinnerBubble - 立体气泡 (TypingDots + 厚度面 + Y 轴微摆)
// =============================================================================
@ComponentV2
export struct CubeSpinnerBubble {
  @Param dotSize: number = 7
  @Param spacing: number = 5
  @Param bubbleColor: string = ''
  @Param dotColor: string = ''
  @Param useShadow: boolean = true
  @Local private bubbleScale: number = 0.96
  @Local private tiltY: number = -3
  private started: boolean = false

  private get bgColor(): string {
    if (this.bubbleColor !== '') {
      return this.bubbleColor
    }
    const uiState = getAppUiState()
    return uiState.isDarkMode ? withColorAlpha(uiState.themePrimary, '24') : uiState.themeAiBubble
  }

  // 后侧"厚度"色 (用主题色, 半透明)
  private get sideColor(): string {
    return getAppUiState().themePrimary
  }

  private get frontBorderColor(): string {
    const uiState = getAppUiState()
    return withColorAlpha(uiState.themePrimary, uiState.isDarkMode ? '80' : '26')
  }

  private get frontDotColor(): string {
    if (this.dotColor !== '') {
      return this.dotColor
    }
    const uiState = getAppUiState()
    return uiState.isDarkMode ? uiState.themeMarkdownLink : uiState.themePrimary
  }

  private get shadowColor(): string {
    return getAppUiState().isDarkMode ? withColorAlpha(getAppUiState().themePrimary, '33') : 'rgba(0, 0, 0, 0.05)'
  }

  private startAnimations(): void {
    if (this.started) return
    this.started = true
    try {
      this.getUIContext().animateTo({
        duration: 1000,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate,
        expectedFrameRateRange: { min: 30, max: 120, expected: 60 }
      }, (): void => {
        this.bubbleScale = 1.04
      })
      // 微小 Y 轴 3D 摆动 ±3°
      this.getUIContext().animateTo({
        duration: 1800,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate,
        expectedFrameRateRange: { min: 30, max: 120, expected: 60 }
      }, (): void => {
        this.tiltY = 3
      })
    } catch (_error) {
      this.bubbleScale = 1.0
      this.tiltY = 0
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 后面"厚度": 同尺寸气泡, 暗色 + 半透明 + 偏移
      // 用 opacity 0 的 TypingDots 撑出与前面气泡相同的尺寸
      Row() {
        TypingDots({ dotSize: this.dotSize, spacing: this.spacing, color: this.frontDotColor })
          .opacity(0)
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(this.sideColor)
      .borderRadius({ topLeft: 4, topRight: 18, bottomLeft: 18, bottomRight: 18 })
      .opacity(0.55)
      .translate({ x: 5, y: 5 })

      // 前面气泡
      Row() {
        TypingDots({ dotSize: this.dotSize, spacing: this.spacing, color: this.frontDotColor })
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(this.bgColor)
      .borderRadius({ topLeft: 4, topRight: 18, bottomLeft: 18, bottomRight: 18 })
      .border({ width: getAppUiState().isDarkMode ? 1 : 0.5, color: this.frontBorderColor })
      .clip(true)
      .shadow(this.useShadow ? {
        radius: getAppUiState().isDarkMode ? 12 : 8,
        color: this.shadowColor,
        offsetX: 0,
        offsetY: getAppUiState().isDarkMode ? 2 : 1
      } : { radius: 0, color: 'rgba(0,0,0,0)', offsetX: 0, offsetY: 0 })
    }
    .scale({ x: this.bubbleScale, y: this.bubbleScale, centerX: '50%', centerY: '50%' })
    .rotate({ x: 0, y: 1, z: 0, angle: this.tiltY, centerX: '50%', centerY: '50%' })
    .onAppear((): void => {
      this.startAnimations()
    })
  }
}

// =============================================================================
// 变体 C: CubeSpinnerAssemble - 像素扫描 (4×4 格子逐个点亮 → 停顿 → 清空 → 重来)
// =============================================================================
@ComponentV2
export struct CubeSpinnerAssemble {
  @Param sizeVp: number = 64
  @Param color: string = ''
  // litCount: 已点亮的格子数 (0 ~ 16)
  // cell.opacity 直接依赖该值, 离散切换 — 保留“像素咣一下亮”的质感, 所以不用 animateTo 插值
  @Local private litCount: number = 0
  private tick: number = -1
  private tickTimer: number = -1
  private started: boolean = false

  private get accentColor(): string {
    return this.color !== '' ? this.color : getAppUiState().themePrimary
  }

  // 单格尺寸: 4 格 + 3 gap + 2 padding 的水平布局
  // (0.18 × 4) + (0.025 × 3) + (0.1025 × 2) ≈ 1.0 × sizeVp
  private get cellSize(): number { return this.sizeVp * 0.18 }
  private get cellGap(): number { return this.sizeVp * 0.025 }

  aboutToDisappear(): void {
    if (this.tickTimer !== -1) {
      clearInterval(this.tickTimer)
      this.tickTimer = -1
    }
  }

  private startScan(): void {
    if (this.started) return
    this.started = true
    // 20 tick 一轮 × 80ms = 1600ms:
    //   tick  0~15: 依次点亮 cell 0~15
    //   tick 16~18: 全亮停顿 240ms
    //   tick   19: 一轮结束, 整体清空
    this.tickTimer = setInterval((): void => {
      this.tick = (this.tick + 1) % 20
      if (this.tick <= 15) {
        this.litCount = this.tick + 1
      } else if (this.tick === 19) {
        this.litCount = 0
      }
    }, 80)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 1. 底色 (主题色淺化, 图片占位背景)
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.accentColor)
        .opacity(0.10)

      // 2. 4×4 像素网格
      this.GridPanel()
    }
    .width(this.sizeVp)
    .height(this.sizeVp)
    .borderRadius(this.sizeVp * 0.22)
    .clip(true)
    .onAppear((): void => {
      this.startScan()
    })
  }

  @Builder
  private GridPanel() {
    Column({ space: this.cellGap }) {
      Row({ space: this.cellGap }) {
        this.Cell(0)
        this.Cell(1)
        this.Cell(2)
        this.Cell(3)
      }
      Row({ space: this.cellGap }) {
        this.Cell(4)
        this.Cell(5)
        this.Cell(6)
        this.Cell(7)
      }
      Row({ space: this.cellGap }) {
        this.Cell(8)
        this.Cell(9)
        this.Cell(10)
        this.Cell(11)
      }
      Row({ space: this.cellGap }) {
        this.Cell(12)
        this.Cell(13)
        this.Cell(14)
        this.Cell(15)
      }
    }
  }

  // 单个像素格: 未亮时 25% 主题色 (作为"骨架"), 点亮后 100% 主题色
  @Builder
  private Cell(index: number) {
    Column()
      .width(this.cellSize)
      .height(this.cellSize)
      .borderRadius(this.cellSize * 0.20)
      .backgroundColor(this.accentColor)
      .opacity(index < this.litCount ? 1.0 : 0.25)
  }
}

// =============================================================================
// 变体 D: CubeSpinner3D - 跑步小人 (身子 + 双手 + 双腿 + 椭圆阴影)
// =============================================================================
@ComponentV2
export struct CubeSpinner3D {
  @Param sizeVp: number = 80
  @Param color: string = ''
  @Param limbColor: string = '#2D3142'
  @Local private bodyY: number = 0
  @Local private shadowScaleX: number = 1.0
  @Local private leftLegAngle: number = -22
  @Local private rightLegAngle: number = 22
  @Local private leftArmAngle: number = 22
  @Local private rightArmAngle: number = -22
  private started: boolean = false

  private get bodyBg(): string {
    return this.color !== '' ? this.color : getAppUiState().themePrimary
  }

  private startAnimations(): void {
    if (this.started) return
    this.started = true
    try {
      // 身子上下跳 (320ms 半周期 -> 跑步频率 ~ 1.5 步/秒)
      this.getUIContext().animateTo({
        duration: 320,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate,
        expectedFrameRateRange: { min: 30, max: 120, expected: 60 }
      }, (): void => {
        this.bodyY = -this.sizeVp * 0.04
      })
      // 阴影同步缩放 (身子在空中时阴影最小)
      this.getUIContext().animateTo({
        duration: 320,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate,
        expectedFrameRateRange: { min: 30, max: 120, expected: 60 }
      }, (): void => {
        this.shadowScaleX = 0.72
      })
      // 双腿 + 双手反相摆动 (与跑步姿态: 左腿前 ↔ 右手前)
      this.getUIContext().animateTo({
        duration: 320,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate,
        expectedFrameRateRange: { min: 30, max: 120, expected: 60 }
      }, (): void => {
        this.leftLegAngle = 22
        this.rightLegAngle = -22
        this.leftArmAngle = -22
        this.rightArmAngle = 22
      })
    } catch (_error) {
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. 椭圆阴影 (位于底部, 不随 body 上下跳, 但同步缩放)
      Column()
        .width(this.sizeVp * 0.5)
        .height(this.sizeVp * 0.07)
        .borderRadius(this.sizeVp * 0.035)
        .backgroundColor('rgba(0, 0, 0, 0.18)')
        .position({ x: this.sizeVp * 0.25, y: this.sizeVp * 0.92 })
        .scale({ x: this.shadowScaleX, y: 1, centerX: '50%', centerY: '50%' })

      // 2. 整个小人 (身子 + 四肢一起上下跳, 但阴影留在原地)
      Stack() {
        // 2a. 左腿 (绕髋部旋转, 显示在身子下方)
        this.Leg(this.sizeVp * 0.40, this.sizeVp * 0.55, this.leftLegAngle)
        // 2b. 右腿
        this.Leg(this.sizeVp * 0.54, this.sizeVp * 0.55, this.rightLegAngle)
        // 2c. 左手 (绕肩旋转, 在身子两侧)
        // 注: Arm Column 实宽 = max(细条 0.04, 手圆 0.07) = 0.07, 视觉中心 = position.x + 0.035
        // 左右对称要求: rightX = 1 - leftX - columnWidth = 1 - 0.18 - 0.07 = 0.75
        this.Arm(this.sizeVp * 0.18, this.sizeVp * 0.25, this.leftArmAngle)
        // 2d. 右手
        this.Arm(this.sizeVp * 0.75, this.sizeVp * 0.25, this.rightArmAngle)
        // 2e. 身子: 圆角脸 + 双白眼 (放最后, 盖住四肢根部)
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(this.sizeVp * 0.55)
            .height(this.sizeVp * 0.50)
            .borderRadius(this.sizeVp * 0.14)
            .backgroundColor(this.bodyBg)
          Row({ space: this.sizeVp * 0.12 }) {
            Column()
              .width(this.sizeVp * 0.07)
              .height(this.sizeVp * 0.07)
              .borderRadius(this.sizeVp * 0.035)
              .backgroundColor('#FFFFFF')
            Column()
              .width(this.sizeVp * 0.07)
              .height(this.sizeVp * 0.07)
              .borderRadius(this.sizeVp * 0.035)
              .backgroundColor('#FFFFFF')
          }
        }
        .width(this.sizeVp * 0.55)
        .height(this.sizeVp * 0.50)
        .position({ x: this.sizeVp * 0.225, y: this.sizeVp * 0.10 })
      }
      .width(this.sizeVp)
      .height(this.sizeVp)
      .translate({ y: this.bodyY })
    }
    .width(this.sizeVp)
    .height(this.sizeVp)
    .onAppear((): void => {
      this.startAnimations()
    })
  }

  // 手臂: 一根细条 + 末端小圆 (手), 绕顶端旋转
  @Builder
  private Arm(x: number, y: number, angle: number) {
    Column() {
      Column()
        .width(this.sizeVp * 0.04)
        .height(this.sizeVp * 0.18)
        .borderRadius(this.sizeVp * 0.02)
        .backgroundColor(this.limbColor)
      Column()
        .width(this.sizeVp * 0.07)
        .height(this.sizeVp * 0.07)
        .borderRadius(this.sizeVp * 0.035)
        .backgroundColor(this.limbColor)
        .margin({ top: -this.sizeVp * 0.015 })
    }
    .position({ x, y })
    .rotate({ angle, centerX: this.sizeVp * 0.02, centerY: 0 })
  }

  // 腿: 一根细条 + 末端扁椭圆 (脚), 绕顶端旋转
  @Builder
  private Leg(x: number, y: number, angle: number) {
    Column() {
      Column()
        .width(this.sizeVp * 0.05)
        .height(this.sizeVp * 0.18)
        .borderRadius(this.sizeVp * 0.025)
        .backgroundColor(this.limbColor)
      Column()
        .width(this.sizeVp * 0.10)
        .height(this.sizeVp * 0.05)
        .borderRadius(this.sizeVp * 0.025)
        .backgroundColor(this.limbColor)
        .margin({ top: -this.sizeVp * 0.01, left: -this.sizeVp * 0.02 })
    }
    .position({ x, y })
    .rotate({ angle, centerX: this.sizeVp * 0.025, centerY: 0 })
  }
}
