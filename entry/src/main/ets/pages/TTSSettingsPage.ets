import { uiMaterial } from '@kit.ArkUI'
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
  TTSEngineType,
  TTSService
} from '../services/TTSService'
import { getAppUiState, setAppUiStateValue } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsStatusBarContentColor,
  getHdsTopNavigationContentTopPadding
} from '../utils/HdsVisualEffectUtil'
import {
  getSettingsPageCompactTabsTotalInset,
  getSettingsPageContentMaxWidth
} from '../utils/SettingsPageLayoutHelper'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'

let ttsSettingsPathStack: NavPathStack | null = null

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
  private previewService: TTSService = new TTSService()

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
    this.loadSettings()
  }

  aboutToDisappear(): void {
    this.previewService.destroy()
    this.isTesting = false
  }

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) *
      160
  }

  private async loadSettings(): Promise<void> {
    this.ttsEnabled = await this.preferences.getBoolean(PreferenceKeys.TTS_ENABLED, true)
    const savedEngine = await this.preferences.getString(PreferenceKeys.TTS_ENGINE, TTSEngineType.LOCAL)
    this.engine = savedEngine === TTSEngineType.ELEVENLABS ? TTSEngineType.ELEVENLABS : TTSEngineType.LOCAL
    this.elevenLabsBaseUrl = await this.preferences.getString(
      PreferenceKeys.ELEVENLABS_BASE_URL,
      DEFAULT_ELEVENLABS_BASE_URL
    )
    this.elevenLabsApiKey = await this.preferences.getString(PreferenceKeys.ELEVENLABS_API_KEY, '')
    this.elevenLabsVoiceId = await this.preferences.getString(PreferenceKeys.ELEVENLABS_VOICE_ID, '')
    if (this.elevenLabsVoiceId !== '') {
      this.voiceOptions = [{ value: this.elevenLabsVoiceId }]
      this.voiceIds = [this.elevenLabsVoiceId]
    }
    this.elevenLabsModelId = await this.preferences.getString(
      PreferenceKeys.ELEVENLABS_MODEL_ID,
      DEFAULT_ELEVENLABS_MODEL_ID
    )
    this.stability = await this.preferences.getNumber(
      PreferenceKeys.ELEVENLABS_STABILITY,
      DEFAULT_ELEVENLABS_STABILITY
    )
    this.similarityBoost = await this.preferences.getNumber(
      PreferenceKeys.ELEVENLABS_SIMILARITY_BOOST,
      DEFAULT_ELEVENLABS_SIMILARITY_BOOST
    )
    this.speed = await this.preferences.getNumber(PreferenceKeys.ELEVENLABS_SPEED, DEFAULT_ELEVENLABS_SPEED)
    if (this.engine === TTSEngineType.ELEVENLABS && this.elevenLabsApiKey.trim() !== '') {
      await this.loadVoices(false)
    }
  }

  private async loadVoices(showSuccess: boolean = true): Promise<void> {
    if (this.elevenLabsApiKey.trim() === '') {
      this.showMessage($r('app.string.tts_voice_api_key_required'), SnackBarTone.ERROR)
      return
    }

    this.isLoadingVoices = true
    try {
      const voices = await this.previewService.listElevenLabsVoices(
        this.elevenLabsBaseUrl,
        this.elevenLabsApiKey
      )
      this.applyVoiceOptions(voices)
      if (showSuccess) {
        this.showMessage(
          voices.length > 0 ? $r('app.string.tts_voices_loaded') : $r('app.string.tts_voices_empty'),
          voices.length > 0 ? SnackBarTone.SUCCESS : SnackBarTone.DEFAULT
        )
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error)
      if (showSuccess) {
        this.showMessage(message, SnackBarTone.ERROR)
      }
    } finally {
      this.isLoadingVoices = false
    }
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

    await this.saveSettings(false)
    const context = this.getUIContext().getHostContext()
    if (context === undefined) {
      this.showMessage($r('app.string.tts_test_failed'), SnackBarTone.ERROR)
      return
    }

    this.isTesting = true
    await this.previewService.init(context)
    await this.previewService.speak('你好，欢迎使用 XCube 播报功能。Hello from XCube.', {
      onStart: (): void => {
        this.showMessage($r('app.string.tts_test_started'), SnackBarTone.SUCCESS)
      },
      onComplete: (): void => {
        this.isTesting = false
      },
      onError: (error: string): void => {
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
    return getHdsTopNavigationContentTopPadding(
      this.px2vp(this.topAvoidHeight),
      this.windowWidthVp,
      this.windowHeightVp
    )
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
    Row({ space: 12 }) {
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
    Button() {
      Column({ space: 7 }) {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontColor([this.engine === engine ? Color.White : this.themePrimary])

        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.engine === engine ? Color.White : $r('app.color.text_primary'))

        Text(description)
          .fontSize(11)
          .fontColor(this.engine === engine ? '#EDEAFF' : $r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .maxLines(2)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .height(112)
    .padding({ left: 10, right: 10, top: 12, bottom: 12 })
    .backgroundColor(this.engine === engine ? this.themePrimary : Color.Transparent)
    .borderRadius(18)
    .border({ width: 1, color: this.engine === engine ? this.themePrimary : this.themePrimaryLight })
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
      this.engine = engine
    })
  }

  @Builder
  private EngineCardContent() {
    Column({ space: 14 }) {
      Text($r('app.string.tts_engine_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

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
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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
  private ParameterSlider(
    label: Resource,
    valueText: string,
    value: number,
    min: number,
    max: number,
    step: number,
    onChange: (value: number) => void
  ) {
    Column({ space: 8 }) {
      Row() {
        Text(label)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Text(valueText)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
      }
      .width('100%')

      Slider({ value: value, min: min, max: max, step: step, style: SliderStyle.InSet })
        .width('100%')
        .trackThickness(16)
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
        .onChange(onChange)
    }
    .width('100%')
  }

  @Builder
  private ElevenLabsCardContent() {
    Column({ space: 14 }) {
      Row({ space: 9 }) {
        SymbolGlyph($r('sys.symbol.paintbrush_pointed_waveform'))
          .fontSize(20)
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
            this.voiceOptions = []
            this.voiceIds = []
          }
          this.elevenLabsApiKey = value
        }
      )
      this.VoiceSelector()

      Row() {
        Text($r('app.string.tts_model'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)

        Select(this.modelOptions)
          .selected(this.getModelSelectedIndex())
          .value(this.elevenLabsModelId)
          .height(40)
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
      .alignItems(VerticalAlign.Center)

      Divider()
        .color($r('app.color.divider'))

      this.ParameterSlider(
        $r('app.string.tts_stability'),
        this.stability.toFixed(2),
        this.stability,
        0,
        1,
        0.05,
        (value: number): void => {
          this.stability = value
        }
      )

      this.ParameterSlider(
        $r('app.string.tts_similarity_boost'),
        this.similarityBoost.toFixed(2),
        this.similarityBoost,
        0,
        1,
        0.05,
        (value: number): void => {
          this.similarityBoost = value
        }
      )

      this.ParameterSlider(
        $r('app.string.tts_speed'),
        `${this.speed.toFixed(2)}×`,
        this.speed,
        0.7,
        1.2,
        0.05,
        (value: number): void => {
          this.speed = value
        }
      )

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
  }

  @Builder
  private ActionButtons() {
    Row({ space: 12 }) {
      Button(this.isTesting ? $r('app.string.tts_stop_test') : $r('app.string.tts_test'))
        .layoutWeight(1)
        .height(44)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.themePrimary)
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
        .onClick((): void => {
          this.testPlayback()
        })

      Button($r('app.string.tts_save'))
        .layoutWeight(1)
        .height(44)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor(this.themePrimary)
        .borderRadius(14)
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
  }

  @Builder
  private PageContent() {
    Scroll() {
      Row() {
        Column({ space: 14 }) {
          if (!this.isDetailPaneMode()) {
            Blank()
              .width('100%')
              .height(this.getCompactContentTopPadding())
          }

          Column() {
            this.EnableCardContent()
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(20)
          .border({ width: 1, color: this.themePrimaryLight })
          .systemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
            materialColor: Color.Transparent,
            applyShadow: false,
            interactive: false,
            lightEffect: { color: undefined }
          }))

          Column() {
            this.EngineCardContent()
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.Transparent)
          .borderRadius(20)
          .border({ width: 1, color: this.themePrimaryLight })
          .systemMaterial(new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
            materialColor: Color.Transparent,
            applyShadow: false,
            interactive: false,
            lightEffect: { color: undefined }
          }))

          if (this.engine === TTSEngineType.LOCAL) {
            Column({ space: 8 }) {
              Row({ space: 9 }) {
                SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                  .fontSize(20)
                  .fontColor([this.themePrimary])
                Text($r('app.string.tts_local_ready'))
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
              }
              .width('100%')

              Text($r('app.string.tts_local_note'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .lineHeight(18)
                .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.Transparent)
            .borderRadius(20)
            .border({ width: 1, color: this.themePrimaryLight })
            .systemMaterial(new uiMaterial.ImmersiveMaterial({
              style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
              materialColor: Color.Transparent,
              applyShadow: false,
              interactive: false,
              lightEffect: { color: undefined }
            }))
          } else {
            Column() {
              this.ElevenLabsCardContent()
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Color.Transparent)
            .borderRadius(20)
            .border({ width: 1, color: this.themePrimaryLight })
            .systemMaterial(new uiMaterial.ImmersiveMaterial({
              style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
              materialColor: Color.Transparent,
              applyShadow: false,
              interactive: false,
              lightEffect: { color: undefined }
            }))
          }

          this.ActionButtons()
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, bottom: this.getContentBottomPadding() })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
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
      .height(64)
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
        Column() {
          this.DetailPaneHeader()
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        HdsNavigation() {
          this.PageContent()
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
