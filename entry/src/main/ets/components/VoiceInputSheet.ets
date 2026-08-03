/**
 * 语音输入录音浮层内容组件
 * 长按麦克风按钮录音，松手后本地识别（SenseVoice），结果通过 onRecognized 上抛。
 * 由 ChatPage 通过 bindSheet 承载显示。
 */
import abilityAccessCtrl, { Permissions, PermissionRequestResult } from '@ohos.abilityAccessCtrl'
import common from '@ohos.app.ability.common'
import { BusinessError } from '@kit.BasicServicesKit'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import {
  getSherpaAsrService,
  AsrResult,
  AsrResultCallback,
  AsrErrorCallback
} from '../services/SherpaAsrService'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'

// 录音浮层状态
enum VoiceState {
  IDLE = 'idle',           // 待机（按住说话）
  LOADING = 'loading',     // 首次加载模型
  LISTENING = 'listening', // 录音中
  RECOGNIZING = 'recognizing' // 松手后识别中
}

@ComponentV2
export struct VoiceInputSheet {
  // 识别出文本（追加到输入框）
  @Event onRecognized: (text: string) => void = (_text: string): void => {}
  // 关闭浮层
  @Event onClose: () => void = (): void => {}

  @Local state: VoiceState = VoiceState.IDLE
  @Local hintText: string = ''
  @Local pressed: boolean = false
  @Local rippleScale: number = 1
  @Local rippleOpacity: number = 0
  // 麦克风权限是否已授予（进入浮层时申请）
  @Local micGranted: boolean = false

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeUserBubble(): string {
    return getAppUiState().themeUserBubble
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  aboutToAppear(): void {
    this.hintText = ''
    // 进入浮层即申请麦克风权限 + 预热模型加载（不阻塞 UI）
    this.prepare()
  }

  private async prepare(): Promise<void> {
    // 1. 申请麦克风权限
    this.micGranted = await this.requestMicPermission()
    if (!this.micGranted) {
      this.hintText = '麦克风权限被拒绝'
    }
    // 2. 预热模型（即便权限没给也先加载，避免后续等待）
    await this.ensureAsrInit()
  }

  aboutToDisappear(): void {
    // 浮层关闭时若仍在录音，强制停止
    const svc = getSherpaAsrService()
    if (svc.isRecording()) {
      svc.stop()
    }
  }

  private getContext(): common.UIAbilityContext | undefined {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  private async ensureAsrInit(): Promise<void> {
    const svc = getSherpaAsrService()
    if (svc.isReady()) {
      return
    }
    const ctx = this.getContext()
    if (!ctx) {
      return
    }
    try {
      await svc.init(ctx)
    } catch (e) {
      console.error('[VoiceInputSheet] ASR init failed: ' + JSON.stringify(e))
    }
  }

  // 请求麦克风权限，返回是否已授权
  private requestMicPermission(): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
      const ctx = this.getContext()
      if (!ctx) {
        resolve(false)
        return
      }
      const permissions: Permissions[] = ['ohos.permission.MICROPHONE']
      atManager.requestPermissionsFromUser(
        ctx,
        permissions,
        (err: BusinessError, data: PermissionRequestResult) => {
          if (err) {
            console.error('[VoiceInputSheet] requestPermissionsFromUser error: ' + JSON.stringify(err))
            resolve(false)
            return
          }
          const authResults: number[] = data.authResults
          const granted: boolean = authResults.length > 0 && authResults[0] === 0
          resolve(granted)
        }
      )
    })
  }

  private async onPressStart(): Promise<void> {
    console.info('[VoiceInputSheet] onPressStart, micGranted=' + this.micGranted)
    if (this.state === VoiceState.LISTENING || this.state === VoiceState.RECOGNIZING) {
      return
    }

    // 权限检查（已在 aboutToAppear 申请）
    if (!this.micGranted) {
      // 再尝试申请一次（用户可能首次拒绝后又想用）
      this.micGranted = await this.requestMicPermission()
      if (!this.micGranted) {
        this.hintText = '麦克风权限被拒绝'
        return
      }
    }

    // 确保模型就绪
    const svc = getSherpaAsrService()
    if (!svc.isReady()) {
      this.state = VoiceState.LOADING
      this.hintText = ''
      await this.ensureAsrInit()
      if (!svc.isReady()) {
        this.state = VoiceState.IDLE
        this.hintText = '语音模型加载失败'
        return
      }
    }

    // 用户可能在等待期间已松手
    if (!this.pressed) {
      return
    }

    this.startRipple()
    this.state = VoiceState.LISTENING

    const onResult: AsrResultCallback = (res: AsrResult): void => {
      if (res.isFinal) {
        this.stopRipple()
        const text = res.text.trim()
        if (text.length > 0) {
          this.onRecognized(text)
        }
        this.state = VoiceState.IDLE
        // 识别完成后关闭浮层
        this.onClose()
      }
    }
    const onError: AsrErrorCallback = (msg: string): void => {
      console.error('[VoiceInputSheet] ASR error: ' + msg)
      this.stopRipple()
      this.state = VoiceState.IDLE
      this.hintText = msg
    }

    svc.start(onResult, onError)
  }

  private onPressEnd(): void {
    if (this.state === VoiceState.LISTENING) {
      this.state = VoiceState.RECOGNIZING
      const svc = getSherpaAsrService()
      svc.stop()
    }
  }

  private startRipple(): void {
    this.getUIContext().animateTo({
      duration: 1000,
      curve: Curve.EaseOut,
      iterations: -1,
      playMode: PlayMode.Normal
    }, () => {
      this.rippleScale = 1.8
      this.rippleOpacity = 0
    })
    this.rippleOpacity = 0.35
  }

  private stopRipple(): void {
    this.getUIContext().animateTo({ duration: 200 }, () => {
      this.rippleScale = 1
      this.rippleOpacity = 0
    })
  }

  private getStatusText(): string {
    switch (this.state) {
      case VoiceState.LOADING:
        return '正在加载语音模型…'
      case VoiceState.LISTENING:
        return '正在聆听…松开结束'
      case VoiceState.RECOGNIZING:
        return '正在识别…'
      default:
        return this.hintText !== '' ? this.hintText : '按住说话'
    }
  }

  private isBusy(): boolean {
    return this.state === VoiceState.LISTENING || this.state === VoiceState.RECOGNIZING
  }

  build() {
    Column() {
      ImmersiveSheetHeader({
        title: $r('app.string.voice_input'),
        onLeadingClick: (): void => {
          this.onClose()
        }
      })

      // 状态提示
      Text(this.getStatusText())
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 12, bottom: 28 })

      // 麦克风按钮 + 波纹
      Stack({ alignContent: Alignment.Center }) {
        // 波纹
        Circle()
          .width(96)
          .height(96)
          .fill(this.themePrimary)
          .opacity(this.rippleOpacity)
          .scale({ x: this.rippleScale, y: this.rippleScale })

        Column() {
          SymbolGlyph($r('sys.symbol.mic'))
            .fontSize(40)
            .fontColor([this.isDarkMode ? Color.White : this.themePrimary])
        }
        .width(96)
        .height(96)
        .borderRadius(48)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.isBusy()
          ? withColorAlpha(this.themePrimary, '66')
          : withColorAlpha(this.themeUserBubble, '40'))
        .scale({ x: this.pressed ? 1.08 : 1, y: this.pressed ? 1.08 : 1 })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.pressed = true
            void this.onPressStart()
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.pressed = false
            this.onPressEnd()
          }
        })
      }
      .width(150)
      .height(150)

      Text('按住麦克风说话，松开自动识别')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 28, bottom: 16 })
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}
