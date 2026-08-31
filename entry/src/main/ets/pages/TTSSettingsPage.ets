import { curves, uiMaterial } from '@kit.ArkUI'
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { getPreferencesService, PreferenceKeys } from '../services/PreferencesService'
import {
  DEFAULT_ELEVENLABS_BASE_URL,
  DEFAULT_ELEVENLABS_MODEL_ID,
  DEFAULT_ELEVENLABS_SIMILARITY_BOOST,
  DEFAULT_ELEVENLABS_SPEED,
  DEFAULT_ELEVENLABS_STABILITY,
  ElevenLabsVoiceInfo,
  getTTSService,
  TTSEngineType,
  TTSService
} from '../services/TTSService'
import { getAppUiState, setAppUiStateValue } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'
import {
  getSettingsPageCompactTabsTotalInset,
  getSettingsPageContentMaxWidth
} from '../utils/SettingsPageLayoutHelper'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'

let ttsSettingsPathStack: NavPathStack | null = null

function createTtsSettingsCardMaterial(): uiMaterial.Material {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
    materialColor: Color.Transparent,
    applyShadow: true,
    interactive: false,
    lightEffect: { color: undefined }
  })
}

@Entry
@ComponentV2
struct TTSSettingsPage {
  @Local ttsEnabled: boolean = true
  @Local engine: TTSEngineType = TTSEngineType.LOCAL
  @Local elevenLabsBaseUrl: string = DEFAULT_ELEVENLABS_BASE_URL
  @Local elevenLabsApiKey: string = ''
  @Local elevenLabsVoiceId: string = ''
  @Local elevenLabsModelId: string = DEFAULT_ELEVENLABS_MODEL_ID
  @Local stability: number = DEFAULT_ELEVENLABS_STABILITY
  @Local similarityBoost: number = DEFAULT_ELEVENLABS_SIMILARITY_BOOST
  @Local speed: number = DEFAULT_ELEVENLABS_SPEED
  @Local isTesting: boolean = false
  @Local isLoadingVoices: boolean = false
  @Local voiceOptions: SelectOption[] = []
  @Local voiceIds: string[] = []

  private readonly modelOptions: SelectOption[] = [
    { value: 'eleven_multilingual_v2' },
    { value: 'eleven_flash_v2_5' },
    { value: 'eleven_v3' }
  ]
  private preferences = getPreferencesService()
  private previewService: TTSService = getTTSService()
  private compactScroller: Scroller = new Scroller()
  private settingsLoadGeneration: number = 0
  private voiceLoadGeneration: number = 0

  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }

  private get bottomAvoidHeight(): number {
    return getAppUiState().bottomAvoidHeight
  }

  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }

  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }

  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }

  private get settingsDetailPresentationMode(): string {
    return getAppUiState().settingsDetailPresentationMode
  }

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }

  private get materialType(): number {
    return getAppUiState().materialType
  }

  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }

  aboutToAppear(): void {
    const loadGeneration = this.settingsLoadGeneration + 1
    this.settingsLoadGeneration = loadGeneration
    this.loadSettings(loadGeneration)
  }

  aboutToDisappear(): void {
    // 返回动画期间不调用 TextReader.stop / HttpRequest.destroy，也不修改 @Local。
    // 共享 TTS 服务会在下一次朗读时接管当前任务，这里只让离页后的异步结果失效。
    this.settingsLoadGeneration += 1
    this.voiceLoadGeneration += 1
  }

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) *
      160
  }

  private async loadSettings(loadGeneration: number): Promise<void> {
    const ttsEnabled = await this.preferences.getBoolean(PreferenceKeys.TTS_ENABLED, true)
    const savedEngine = await this.preferences.getString(PreferenceKeys.TTS_ENGINE, TTSEngineType.LOCAL)
    const engine = savedEngine === TTSEngineType.ELEVENLABS ? TTSEngineType.ELEVENLABS : TTSEngineType.LOCAL
    const elevenLabsBaseUrl = await this.preferences.getString(
      PreferenceKeys.ELEVENLABS_BASE_URL,
      DEFAULT_ELEVENLABS_BASE_URL
    )
    const elevenLabsApiKey = await this.preferences.getString(PreferenceKeys.ELEVENLABS_API_KEY, '')
    const elevenLabsVoiceId = await this.preferences.getString(PreferenceKeys.ELEVENLABS_VOICE_ID, '')
    const elevenLabsModelId = await this.preferences.getString(
      PreferenceKeys.ELEVENLABS_MODEL_ID,
      DEFAULT_ELEVENLABS_MODEL_ID
    )
    const stability = await this.preferences.getNumber(
      PreferenceKeys.ELEVENLABS_STABILITY,
      DEFAULT_ELEVENLABS_STABILITY
    )
    const similarityBoost = await this.preferences.getNumber(
      PreferenceKeys.ELEVENLABS_SIMILARITY_BOOST,
      DEFAULT_ELEVENLABS_SIMILARITY_BOOST
    )
    const speed = await this.preferences.getNumber(PreferenceKeys.ELEVENLABS_SPEED, DEFAULT_ELEVENLABS_SPEED)
    if (loadGeneration !== this.settingsLoadGeneration) {
      return
    }

    this.ttsEnabled = ttsEnabled
    this.engine = engine
    this.elevenLabsBaseUrl = elevenLabsBaseUrl
    this.elevenLabsApiKey = elevenLabsApiKey
    this.elevenLabsVoiceId = elevenLabsVoiceId
    this.elevenLabsModelId = elevenLabsModelId
    this.stability = stability
    this.similarityBoost = similarityBoost
    this.speed = speed
    if (elevenLabsVoiceId !== '') {
      this.voiceOptions = [{ value: elevenLabsVoiceId }]
      this.voiceIds = [elevenLabsVoiceId]
    } else {
      this.voiceOptions = []
      this.voiceIds = []
    }
  }

  private async loadVoices(showSuccess: boolean = true): Promise<void> {
    if (this.elevenLabsApiKey.trim() === '') {
      this.showMessage($r('app.string.tts_voice_api_key_required'), SnackBarTone.ERROR)
      return
    }

    const loadGeneration = this.voiceLoadGeneration + 1
    this.voiceLoadGeneration = loadGeneration
    this.isLoadingVoices = true
    try {
      const voices = await this.previewService.listElevenLabsVoices(
        this.elevenLabsBaseUrl,
        this.elevenLabsApiKey
      )
      if (loadGeneration !== this.voiceLoadGeneration) {
        return
      }
      this.applyVoiceOptions(voices)
      if (showSuccess) {
        this.showMessage(
          voices.length > 0 ? $r('app.string.tts_voices_loaded') : $r('app.string.tts_voices_empty'),
          voices.length > 0 ? SnackBarTone.SUCCESS : SnackBarTone.DEFAULT
        )
      }
    } catch (error) {
      if (loadGeneration !== this.voiceLoadGeneration) {
        return
      }
      const message = error instanceof Error ? error.message : JSON.stringify(error)
      if (showSuccess) {
        this.showMessage(message, SnackBarTone.ERROR)
      }
    } finally {
      if (loadGeneration === this.voiceLoadGeneration) {
        this.isLoadingVoices = false
      }
    }
  }

  private cancelVoiceLoading(): void {
    this.voiceLoadGeneration += 1
    this.previewService.cancelVoiceListRequest()
    this.isLoadingVoices = false
  }

  private applyVoiceOptions(voices: ElevenLabsVoiceInfo[]): void {
    const options: SelectOption[] = []
    const ids: string[] = []
    for (let index = 0; index < voices.length; index++) {
      const voice = voices[index]
      options.push({ value: `${voice.name} · ${voice.voiceId}` })
      ids.push(voice.voiceId)
    }

    if (this.elevenLabsVoiceId !== '' && !ids.includes(this.elevenLabsVoiceId)) {
      options.unshift({ value: this.elevenLabsVoiceId })
      ids.unshift(this.elevenLabsVoiceId)
    }
    if (this.elevenLabsVoiceId === '' && ids.length > 0) {
      this.elevenLabsVoiceId = ids[0]
    }
    this.voiceOptions = options
    this.voiceIds = ids
  }

  private async setEnabled(value: boolean): Promise<void> {
    this.ttsEnabled = value
    setAppUiStateValue(AppStorageKeys.TTS_ENABLED, value)
    await this.preferences.setBoolean(PreferenceKeys.TTS_ENABLED, value)
    if (!value && this.isTesting) {
      this.previewService.stop()
      this.isTesting = false
    }
  }

  private selectEngine(engine: TTSEngineType): void {
    if (this.engine === engine) {
      return
    }
    if (this.isTesting) {
      this.previewService.stop()
      this.isTesting = false
    }
    this.engine = engine
  }

  private async saveSettings(showSuccess: boolean = true): Promise<void> {
    const normalizedBaseUrl = this.elevenLabsBaseUrl.trim() === '' ?
      DEFAULT_ELEVENLABS_BASE_URL : this.elevenLabsBaseUrl.trim()
    this.elevenLabsBaseUrl = normalizedBaseUrl

    await this.preferences.setBoolean(PreferenceKeys.TTS_ENABLED, this.ttsEnabled)
    await this.preferences.setString(PreferenceKeys.TTS_ENGINE, this.engine)
    await this.preferences.setString(PreferenceKeys.ELEVENLABS_BASE_URL, normalizedBaseUrl)
    await this.preferences.setString(PreferenceKeys.ELEVENLABS_API_KEY, this.elevenLabsApiKey.trim())
    await this.preferences.setString(PreferenceKeys.ELEVENLABS_VOICE_ID, this.elevenLabsVoiceId.trim())
    await this.preferences.setString(PreferenceKeys.ELEVENLABS_MODEL_ID, this.elevenLabsModelId)
    await this.preferences.setNumber(PreferenceKeys.ELEVENLABS_STABILITY, this.stability)
    await this.preferences.setNumber(PreferenceKeys.ELEVENLABS_SIMILARITY_BOOST, this.similarityBoost)
    await this.preferences.setNumber(PreferenceKeys.ELEVENLABS_SPEED, this.speed)
    setAppUiStateValue(AppStorageKeys.TTS_ENABLED, this.ttsEnabled)

    if (showSuccess) {
      this.showMessage($r('app.string.tts_saved'), SnackBarTone.SUCCESS)
    }
  }

  private async testPlayback(): Promise<void> {
    if (this.isTesting) {
      this.previewService.stop()
      this.isTesting = false
      return
    }
    if (!this.ttsEnabled) {
      this.showMessage($r('app.string.tts_enable_before_test'), SnackBarTone.ERROR)
      return
    }
    if (this.engine === TTSEngineType.ELEVENLABS &&
      (this.elevenLabsApiKey.trim() === '' || this.elevenLabsVoiceId.trim() === '')) {
      this.showMessage($r('app.string.tts_elevenlabs_required'), SnackBarTone.ERROR)
      return
    }

    const pageGeneration = this.settingsLoadGeneration
    await this.saveSettings(false)
    if (pageGeneration !== this.settingsLoadGeneration) {
      return
    }
    const context = this.getUIContext().getHostContext()
    if (context === undefined) {
      this.showMessage($r('app.string.tts_test_failed'), SnackBarTone.ERROR)
      return
    }

    this.isTesting = true
    await this.previewService.init(context)
    if (pageGeneration !== this.settingsLoadGeneration) {
      return
    }
    await this.previewService.speak('你好，欢迎使用 XCube 播报功能。Hello from XCube.', {
      onStart: (): void => {
        if (pageGeneration !== this.settingsLoadGeneration) {
          return
        }
        this.showMessage($r('app.string.tts_test_started'), SnackBarTone.SUCCESS)
      },
      onComplete: (): void => {
        if (pageGeneration !== this.settingsLoadGeneration) {
          return
        }
        this.isTesting = false
      },
      onError: (error: string): void => {
        if (pageGeneration !== this.settingsLoadGeneration) {
          return
        }
        this.isTesting = false
        this.showMessage(error, SnackBarTone.ERROR)
      }
    })
  }

  private showMessage(message: Resource | string, tone: SnackBarTone): void {
    const options = new SnackBarDisplayOptions()
    options.message = message
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  private getModelSelectedIndex(): number {
    for (let index = 0; index < this.modelOptions.length; index++) {
      if (this.modelOptions[index].value === this.elevenLabsModelId) {
        return index
      }
    }
    return 0
  }

  private getVoiceSelectedIndex(): number {
    for (let index = 0; index < this.voiceIds.length; index++) {
      if (this.voiceIds[index] === this.elevenLabsVoiceId) {
        return index
      }
    }
    return 0
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(
      this.layoutSizeClass,
      this.windowWidthVp,
      this.settingsDetailPresentationMode,
      this.windowHeightVp
    )
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private getContentBottomPadding(): number {
    return 24 + getSettingsPageCompactTabsTotalInset(
      this.px2vp(this.bottomAvoidHeight),
      this.settingsDetailPresentationMode
    )
  }

  private getCompactContentTopPadding(): number {
    return this.px2vp(this.topAvoidHeight) + 56
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(
      this.materialType,
      this.materialLevel,
      this.windowWidthVp,
      this.windowHeightVp,
      (): void => this.CompactTitleStackBuilder()
    )
  }

  private handleBack(): void {
    if (ttsSettingsPathStack !== null && ttsSettingsPathStack.size() > 0) {
      ttsSettingsPathStack.pop()
    }
  }

  @Builder
  private EnableCardContent() {
    Row({ space: 14 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.speaker_wave_2'))
          .fontSize(22)
          .fontColor([this.ttsEnabled ? Color.White : this.themePrimary])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.ttsEnabled ? this.themePrimary : Color.Transparent)
      .borderRadius(14)
      .border({ width: 1, color: this.ttsEnabled ? this.themePrimary : this.themePrimaryLight })
      .scale({ x: this.ttsEnabled ? 1 : 0.92, y: this.ttsEnabled ? 1 : 0.92 })
      .animation({ duration: 320, curve: curves.springMotion(0.35, 0.82) })

      Column({ space: 4 }) {
        Text($r('app.string.tts_enabled_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        Text($r('app.string.tts_enabled_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.ttsEnabled })
        .selectedColor(this.themePrimary)
        .switchPointColor(Color.White)
        .systemMaterial(new uiMaterial.Material())
        .animation({ duration: 280, curve: curves.springMotion(0.35, 0.82) })
        .onChange((value: boolean): void => {
          this.setEnabled(value)
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private EngineButton(
    engine: TTSEngineType,
    icon: Resource,
    title: Resource,
    description: Resource
  ) {
    // Keep both choices the same size so labels stay aligned across languages.
    Button() {
      Column({ space: 9 }) {
        Row() {
          Column() {
            SymbolGlyph(icon)
              .fontSize(21)
              .fontColor([this.engine === engine ? Color.White : this.themePrimary])
          }
          .width(38)
          .height(38)
          .justifyContent(FlexAlign.Center)
          .borderRadius(12)
          .backgroundColor(this.engine === engine ? '#26FFFFFF' : Color.Transparent)
          .border({ width: 1, color: this.engine === engine ? '#38FFFFFF' : this.themePrimaryLight })

          Blank()

          if (this.engine === engine) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(18)
              .fontColor([Color.White])
              .transition(
                TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.55, y: 0.55 }))
                  .animation({ duration: 320, curve: curves.springMotion(0.35, 0.82) })
              )
          }
        }
        .width('100%')

        Column({ space: 3 }) {
          Text(title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.engine === engine ? Color.White : $r('app.color.text_primary'))
            .width('100%')

          Text(description)
            .fontSize(11)
            .fontColor(this.engine === engine ? '#EDEAFF' : $r('app.color.text_secondary'))
            .lineHeight(16)
            .maxLines(2)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .layoutWeight(1)
    .height(112)
    .padding(13)
    .backgroundColor(this.engine === engine ? this.themePrimary : Color.Transparent)
    .borderRadius(18)
    .border({ width: 1, color: this.engine === engine ? this.themePrimary : this.themePrimaryLight })
    .opacity(this.ttsEnabled ? 1 : 0.5)
    .animation({ duration: 320, curve: curves.springMotion(0.35, 0.82) })
    .stateEffect(false)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: this.engine === engine ? this.themePrimary : Color.Transparent,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .enabled(this.ttsEnabled)
    .onClick((): void => {
      this.selectEngine(engine)
    })
  }

  @Builder
  private EngineCardContent() {
    Column({ space: 14 }) {
      Row({ space: 9 }) {
        SymbolGlyph($r('sys.symbol.waveform'))
          .fontSize(19)
          .fontColor([this.themePrimary])

        Text($r('app.string.tts_engine_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 12 }) {
        this.EngineButton(
          TTSEngineType.LOCAL,
          $r('sys.symbol.speaker_wave_2'),
          $r('app.string.tts_engine_local'),
          $r('app.string.tts_engine_local_desc')
        )
        this.EngineButton(
          TTSEngineType.ELEVENLABS,
          $r('sys.symbol.cloud'),
          $r('app.string.tts_engine_elevenlabs'),
          $r('app.string.tts_engine_elevenlabs_desc')
        )
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .opacity(this.ttsEnabled ? 1 : 0.55)
    .animation({ duration: 220, curve: Curve.EaseOut })
  }

  @Builder
  private InputField(
    label: Resource,
    value: string,
    placeholder: Resource | string,
    password: boolean,
    onChange: (value: string) => void
  ) {
    Column({ space: 7 }) {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ text: value, placeholder: placeholder })
        .type(password ? InputType.Password : InputType.Normal)
        .enableAutoFill(false)
        .width('100%')
        .height(46)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .padding({ left: 12, right: 12 })
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: Color.Transparent,
          applyShadow: false
        }))
        .enabled(this.ttsEnabled)
        .onChange(onChange)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private VoiceSelector() {
    Column({ space: 7 }) {
      Row({ space: 10 }) {
        Text($r('app.string.tts_voice_id'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)

        Button() {
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
              .fontSize(14)
              .fontColor([this.themePrimary])
              .rotate({ angle: this.isLoadingVoices ? 180 : 0 })
              .animation({ duration: 250, curve: Curve.EaseOut })

            Text(this.isLoadingVoices ?
              $r('app.string.tts_loading_voices') : $r('app.string.tts_load_voices'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)
          }
          .alignItems(VerticalAlign.Center)
        }
        .height(32)
        .padding({ left: 10, right: 10 })
        .backgroundColor(Color.Transparent)
        .borderRadius(14)
        .stateEffect(false)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR,
          materialColor: Color.Transparent,
          applyShadow: false,
          interactive: true,
          lightEffect: { color: undefined }
        }))
        .enabled(this.ttsEnabled && !this.isLoadingVoices)
        .onClick((): void => {
          this.loadVoices()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.voiceOptions.length > 0) {
        Select(this.voiceOptions)
          .selected(this.getVoiceSelectedIndex())
          .value(this.voiceOptions[this.getVoiceSelectedIndex()].value)
          .width('100%')
          .height(46)
          .font({ size: 13 })
          .fontColor($r('app.color.text_primary'))
          .selectedOptionFontColor(this.themePrimary)
          .backgroundColor(Color.Transparent)
          .borderRadius(14)
          .systemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
            materialColor: Color.Transparent,
            applyShadow: false
          }))
          .menuSystemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.THICK
          }))
          .enabled(this.ttsEnabled)
          .onSelect((index: number, _value: string): void => {
            if (index >= 0 && index < this.voiceIds.length) {
              this.elevenLabsVoiceId = this.voiceIds[index]
            }
          })
      } else {
        Select([{
          value: this.isLoadingVoices ?
            $r('app.string.tts_loading_voices') : $r('app.string.tts_voice_fetch_first')
        }])
          .selected(0)
          .width('100%')
          .height(46)
          .font({ size: 13 })
          .fontColor($r('app.color.text_tertiary'))
          .backgroundColor(Color.Transparent)
          .borderRadius(14)
          .systemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
            materialColor: Color.Transparent,
            applyShadow: false
          }))
          .enabled(false)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private StabilitySlider() {
    Column({ space: 10 }) {
      Row() {
        Text($r('app.string.tts_stability'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Text(this.stability.toFixed(2))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
          .width(52)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      Slider({ value: this.stability, min: 0, max: 1, step: 0.05, style: SliderStyle.InSet })
        .width('100%')
        .trackThickness(8)
        .blockSize({ width: 22, height: 22 })
        .selectedColor(this.themePrimaryLight)
        .trackColor(Color.White)
        .blockColor(this.themePrimary)
        .blockBorderColor(this.themePrimary)
        .blockBorderWidth(1)
        .showSteps(false)
        .showTips(false)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN
        }))
        .enabled(this.ttsEnabled)
        .onChange((value: number, _mode: SliderChangeMode): void => {
          this.stability = Math.round(value * 100) / 100
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 10 })
  }

  @Builder
  private SimilaritySlider() {
    Column({ space: 10 }) {
      Row() {
        Text($r('app.string.tts_similarity_boost'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Text(this.similarityBoost.toFixed(2))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
          .width(52)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      Slider({ value: this.similarityBoost, min: 0, max: 1, step: 0.05, style: SliderStyle.InSet })
        .width('100%')
        .trackThickness(8)
        .blockSize({ width: 22, height: 22 })
        .selectedColor(this.themePrimaryLight)
        .trackColor(Color.White)
        .blockColor(this.themePrimary)
        .blockBorderColor(this.themePrimary)
        .blockBorderWidth(1)
        .showSteps(false)
        .showTips(false)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN
        }))
        .enabled(this.ttsEnabled)
        .onChange((value: number, _mode: SliderChangeMode): void => {
          this.similarityBoost = Math.round(value * 100) / 100
        })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  @Builder
  private SpeedSlider() {
    Column({ space: 10 }) {
      Row() {
        Text($r('app.string.tts_speed'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Text(`${this.speed.toFixed(2)}×`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
          .width(52)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      Slider({ value: this.speed, min: 0.7, max: 1.2, step: 0.05, style: SliderStyle.InSet })
        .width('100%')
        .trackThickness(8)
        .blockSize({ width: 22, height: 22 })
        .selectedColor(this.themePrimaryLight)
        .trackColor(Color.White)
        .blockColor(this.themePrimary)
        .blockBorderColor(this.themePrimary)
        .blockBorderWidth(1)
        .showSteps(false)
        .showTips(false)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN
        }))
        .enabled(this.ttsEnabled)
        .onChange((value: number, _mode: SliderChangeMode): void => {
          this.speed = Math.round(value * 100) / 100
        })
    }
    .width('100%')
    .padding({ top: 10, bottom: 4 })
  }

  @Builder
  private ElevenLabsCardContent() {
    Column({ space: 16 }) {
      Row({ space: 9 }) {
        SymbolGlyph($r('sys.symbol.paintbrush_pointed_waveform'))
          .fontSize(19)
          .fontColor([this.themePrimary])
        Text($r('app.string.tts_elevenlabs_config'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      this.InputField(
        $r('app.string.tts_api_base_url'),
        this.elevenLabsBaseUrl,
        DEFAULT_ELEVENLABS_BASE_URL,
        false,
        (value: string): void => {
          if (value !== this.elevenLabsBaseUrl) {
            this.cancelVoiceLoading()
            this.voiceOptions = []
            this.voiceIds = []
          }
          this.elevenLabsBaseUrl = value
        }
      )
      this.InputField(
        $r('app.string.tts_api_key'),
        this.elevenLabsApiKey,
        'xi-api-key',
        true,
        (value: string): void => {
          if (value !== this.elevenLabsApiKey) {
            this.cancelVoiceLoading()
            this.voiceOptions = []
            this.voiceIds = []
          }
          this.elevenLabsApiKey = value
        }
      )
      this.VoiceSelector()

      Column({ space: 7 }) {
        Text($r('app.string.tts_model'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        Select(this.modelOptions)
          .selected(this.getModelSelectedIndex())
          .value(this.elevenLabsModelId)
          .width('100%')
          .height(46)
          .font({ size: 13 })
          .fontColor($r('app.color.text_primary'))
          .selectedOptionFontColor(this.themePrimary)
          .backgroundColor(Color.Transparent)
          .borderRadius(14)
          .systemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
            materialColor: Color.Transparent,
            applyShadow: false
          }))
          .menuSystemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.THICK
          }))
          .enabled(this.ttsEnabled)
          .onSelect((_index: number, value: string): void => {
            this.elevenLabsModelId = value
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Divider()
        .color($r('app.color.divider'))

      Column() {
        this.StabilitySlider()

        Divider()
          .color($r('app.color.divider'))

        this.SimilaritySlider()

        Divider()
          .color($r('app.color.divider'))

        this.SpeedSlider()
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(Color.Transparent)
      .borderRadius(16)
      .border({ width: 1, color: this.themePrimaryLight })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        materialColor: Color.Transparent,
        applyShadow: false
      }))

      Divider()
        .color($r('app.color.divider'))

      Text($r('app.string.tts_output_format_note'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(18)
        .width('100%')

      Text($r('app.string.tts_security_note'))
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .lineHeight(18)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .opacity(this.ttsEnabled ? 1 : 0.5)
    .animation({ duration: 220, curve: Curve.EaseOut })
  }

  @Builder
  private ActionButtons() {
    Row({ space: 12 }) {
      Button() {
        Row({ space: 7 }) {
          SymbolGlyph(this.isTesting ?
            $r('sys.symbol.xmark_circle_fill') : $r('sys.symbol.speaker_wave_2'))
            .fontSize(17)
            .fontColor([this.themePrimary])
            .scale({ x: this.isTesting ? 1.08 : 1, y: this.isTesting ? 1.08 : 1 })
            .animation({ duration: 280, curve: curves.springMotion(0.35, 0.82) })

          Text(this.isTesting ? $r('app.string.tts_stop_test') : $r('app.string.tts_test'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
        }
        .alignItems(VerticalAlign.Center)
      }
        .layoutWeight(1)
        .height(48)
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .border({ width: 1, color: this.themePrimaryLight })
        .scale({ x: this.isTesting ? 0.98 : 1, y: this.isTesting ? 0.98 : 1 })
        .animation({ duration: 280, curve: curves.springMotion(0.35, 0.82) })
        .stateEffect(false)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR,
          materialColor: Color.Transparent,
          applyShadow: false,
          interactive: true,
          lightEffect: { color: undefined }
        }))
        .onClick((): void => {
          this.testPlayback()
        })

      Button() {
        Row({ space: 7 }) {
          SymbolGlyph($r('sys.symbol.save'))
            .fontSize(17)
            .fontColor([Color.White])

          Text($r('app.string.tts_save'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
        }
        .alignItems(VerticalAlign.Center)
      }
        .layoutWeight(1)
        .height(48)
        .backgroundColor(this.themePrimary)
        .borderRadius(16)
        .stateEffect(false)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR,
          materialColor: this.themePrimary,
          applyShadow: false,
          interactive: true,
          lightEffect: { color: undefined }
        }))
        .onClick((): void => {
          this.saveSettings()
        })
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 })
  }

  @Builder
  private PageContent(includeCompactTopSpacer: boolean) {
    Scroll(this.compactScroller) {
      Column() {
        Column({ space: 16 }) {
          if (includeCompactTopSpacer) {
            Blank()
              .width('100%')
              .height(this.getCompactContentTopPadding())
          }

          Column() {
            this.EnableCardContent()
          }
          .width('100%')
          .padding(18)
          .backgroundColor(Color.Transparent)
          .borderRadius(24)
          .border({ width: this.ttsEnabled ? 1.5 : 1, color: this.themePrimaryLight })
          .scale({ x: this.ttsEnabled ? 1 : 0.99, y: this.ttsEnabled ? 1 : 0.99 })
          .animation({ duration: 320, curve: curves.springMotion(0.35, 0.82) })
          .systemMaterial(createTtsSettingsCardMaterial())

          Column() {
            this.EngineCardContent()
          }
          .width('100%')
          .padding(18)
          .backgroundColor(Color.Transparent)
          .borderRadius(24)
          .border({ width: 1, color: this.themePrimaryLight })
          .systemMaterial(createTtsSettingsCardMaterial())

          if (this.engine === TTSEngineType.ELEVENLABS) {
            Column() {
              this.ElevenLabsCardContent()
            }
            .width('100%')
            .padding(18)
            .backgroundColor(Color.Transparent)
            .borderRadius(24)
            .border({ width: 1, color: this.themePrimaryLight })
            .systemMaterial(createTtsSettingsCardMaterial())
            .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
          }

          this.ActionButtons()
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 16, right: 16, top: 2, bottom: this.getContentBottomPadding() })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.settings_tts'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(getAppUiState().themeBackground)
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.settings_tts'),
      onBack: (): void => {
        this.handleBack()
      }
    })
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        HdsNavigation() {
          this.PageContent(true)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(getAppUiState().themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .titleMode(HdsNavigationTitleMode.MINI)
        .systemBarStyle(
          { statusBarContentColor: getHdsStatusBarContentColor() },
          { statusBarContentColor: getHdsStatusBarContentColor() }
        )
        .hideBackButton(false)
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      } else {
        HdsNavigation() {
          this.PageContent(true)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(getAppUiState().themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .titleMode(HdsNavigationTitleMode.MINI)
        .systemBarStyle(
          { statusBarContentColor: getHdsStatusBarContentColor() },
          { statusBarContentColor: getHdsStatusBarContentColor() }
        )
        .hideBackButton(false)
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }
}

@Builder
export function TTSSettingsPageBuilder(name: string, param: Object) {
  NavDestination() {
    TTSSettingsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext): void => {
    ttsSettingsPathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (ttsSettingsPathStack !== null && ttsSettingsPathStack.size() > 0) {
      ttsSettingsPathStack.pop()
    }
    return true
  })
}
