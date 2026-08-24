/**
 * 模型编辑半模态组件
 * 单页滚动布局：核心信息 → 能力标签 → 可折叠高级参数
 */
import {
  BillingTimePeriod,
  BillingTimePeriodJson,
  ModelInfo,
  InputMode,
  OutputMode,
  ModelInfoExtendedJson
} from '../models/ChatModels'
import { LengthMetrics, uiMaterial } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import {
  hasOverlappingBillingPeakPeriods,
  normalizeBillingCurrency,
  normalizeBillingMinuteOfDay,
  parseBillingPrice
} from '../utils/ModelBillingUtils'
import { showToast } from '../utils/ToastUtil'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'
import { DEFAULT_MODEL_CONTEXT_WINDOW_TOKENS } from '../utils/ContextWindowUtils'

@ComponentV2
struct ModelCapabilityButton {
  @Param icon: Resource = $r('sys.symbol.checkmark_circle')
  @Param label: string = ''
  @Param selected: boolean = false
  @Event onTap: () => void = () => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }

  build() {
    Button({ type: ButtonType.Capsule, stateEffect: false }) {
      Row({ space: 6 }) {
        SymbolGlyph(this.icon)
          .fontSize(16)
          .fontColor([this.selected ? this.themePrimary : $r('app.color.text_primary')])

        Text(this.label)
          .fontSize(13)
          .fontWeight(FontWeight.Regular)
          .fontColor(this.selected ? this.themePrimary : $r('app.color.text_primary'))
      }
      .alignItems(VerticalAlign.Center)
    }
    .height(36)
    .padding({ left: 12, right: 14 })
    .backgroundColor(this.selected ? this.themePrimaryLight : Color.Transparent)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: this.selected ? this.themePrimaryLight : Color.Transparent,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .onClick(() => {
      this.onTap()
    })
  }
}

@ComponentV2
export struct ModelEditSheet {
  @Param model: ModelInfo = new ModelInfo('', '')
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  @Local tempName: string = ''
  @Local contextLengthText: string = ''
  // 能力开关状态（用于触发 UI 刷新）
  @Local capSupportsTools: boolean = false
  @Local capSupportsReasoning: boolean = false
  @Local capSupportsWebSearch: boolean = false
  @Local capSupportsVision: boolean = false
  @Local capSupportsDocuments: boolean = false
  @Local capSupportsStreaming: boolean = false
  @Local capOutputImage: boolean = false
  @Local reasoningStrategyOverride: string = ''
  // 高级参数折叠状态
  @Local isAdvancedExpanded: boolean = false
  // 高级参数本地状态（驱动 Slider 实时刷新）
  @Local paramTemperature: number = 0.7
  @Local paramTopP: number = 1.0
  @Local paramPresencePenalty: number = 0
  @Local paramFrequencyPenalty: number = 0
  @Local maxOutputTokensText: string = ''
  // 计费配置
  @Local billingEnabled: boolean = false
  @Local billingCurrency: string = 'CNY'
  @Local billingCurrencySelectedIndex: number = 0
  @Local inputPriceText: string = ''
  @Local outputPriceText: string = ''
  @Local billingTimeOfUseEnabled: boolean = false
  @Local billingRestDayOffPeakEnabled: boolean = false
  @Local billingPeakPeriods: BillingTimePeriod[] = [new BillingTimePeriod(8 * 60, 22 * 60)]
  @Local billingPeakInputPriceText: string = ''
  @Local billingPeakOutputPriceText: string = ''
  @Local billingOffPeakInputPriceText: string = ''
  @Local billingOffPeakOutputPriceText: string = ''
  private billingPickerPeriodIndex: number = -1
  private billingPickerIsStart: boolean = true
  private billingPickerSelectedMinutes: number = 0
  private billingPickerInitialTime: Date = new Date(2000, 0, 1, 0, 0, 0, 0)
  private billingTimePickerDialogId: number = -1
  private billingEmptyPeriodAnchored: boolean[] = [false, false, false]
  private readonly billingCurrencies: string[] = ['CNY', 'USD', 'EUR', 'GBP', 'JPY', 'KRW']
  private readonly billingCurrencyOptions: SelectOption[] = [
    { value: 'CNY' },
    { value: 'USD' },
    { value: 'EUR' },
    { value: 'GBP' },
    { value: 'JPY' },
    { value: 'KRW' }
  ]
  // 回调函数
  @Event onSave: (draft: ModelInfoExtendedJson) => Promise<void> = async (_draft: ModelInfoExtendedJson): Promise<void> => {
  }
  @Event onCancel: () => void = () => {
  }
  @Event onAdvancedExpandedChange: (expanded: boolean) => void = (_expanded: boolean): void => {
  }

  private get shouldUseFullHeight(): boolean {
    return this.isAdvancedExpanded || this.billingEnabled
  }

  aboutToAppear(): void {
    this.syncDraftFromModel()
    this.updateSheetExpansion()
  }

  private syncDraftFromModel(): void {
    this.tempName = this.model.name
    this.contextLengthText = this.model.contextLength > 0 ? this.model.contextLength.toString() : ''
    this.capSupportsTools = this.model.capabilities.supportsTools
    this.capSupportsReasoning = this.model.capabilities.supportsReasoning
    this.capSupportsWebSearch = this.model.capabilities.supportsWebSearch
    this.capSupportsVision = this.model.capabilities.supportsVision
    this.capSupportsDocuments = this.model.capabilities.supportsDocuments
    this.capSupportsStreaming = this.model.capabilities.supportsStreaming
    this.capOutputImage = this.model.outputMode === OutputMode.IMAGE
    this.reasoningStrategyOverride = this.model.reasoningStrategyOverride
    this.paramTemperature = this.model.parameters.temperature
    this.paramTopP = this.model.parameters.topP
    this.paramPresencePenalty = this.model.parameters.presencePenalty
    this.paramFrequencyPenalty = this.model.parameters.frequencyPenalty
    this.maxOutputTokensText = this.model.parameters.maxTokens > 0 ?
      this.model.parameters.maxTokens.toString() : ''
    this.billingEnabled = this.model.billingEnabled
    this.billingCurrency = normalizeBillingCurrency(this.model.billingCurrency)
    this.billingCurrencySelectedIndex = this.getBillingCurrencyIndex(this.billingCurrency)
    this.inputPriceText = this.model.inputPricePerMillion > 0 ?
      this.model.inputPricePerMillion.toString() : ''
    this.outputPriceText = this.model.outputPricePerMillion > 0 ?
      this.model.outputPricePerMillion.toString() : ''
    this.billingTimeOfUseEnabled = this.model.billingTimeOfUseEnabled
    this.billingRestDayOffPeakEnabled = this.model.billingRestDayOffPeakEnabled
    this.billingPeakPeriods = this.copyBillingPeakPeriods(this.model.billingPeakPeriods)
    this.billingEmptyPeriodAnchored = [false, false, false]
    this.billingPeakInputPriceText = this.formatBillingPriceForInput(this.model.billingPeakInputPricePerMillion)
    this.billingPeakOutputPriceText = this.formatBillingPriceForInput(this.model.billingPeakOutputPricePerMillion)
    this.billingOffPeakInputPriceText = this.formatBillingPriceForInput(this.model.billingOffPeakInputPricePerMillion)
    this.billingOffPeakOutputPriceText = this.formatBillingPriceForInput(this.model.billingOffPeakOutputPricePerMillion)
  }

  private formatBillingPriceForInput(price: number): string {
    return price > 0 ? price.toString() : ''
  }

  private formatBillingTime(minutes: number): string {
    const normalized = normalizeBillingMinuteOfDay(minutes)
    const hour = Math.floor(normalized / 60).toString().padStart(2, '0')
    const minute = (normalized % 60).toString().padStart(2, '0')
    return `${hour}:${minute}`
  }

  private copyBillingPeakPeriods(source: BillingTimePeriod[]): BillingTimePeriod[] {
    const result: BillingTimePeriod[] = []
    const count = Math.min(3, source.length)
    for (let i = 0; i < count; i++) {
      result.push(new BillingTimePeriod(source[i].startMinutes, source[i].endMinutes))
    }
    if (result.length === 0) {
      result.push(new BillingTimePeriod(8 * 60, 22 * 60))
    }
    return result
  }

  private updateBillingPeakPeriod(index: number, startMinutes?: number, endMinutes?: number): void {
    const next = this.copyBillingPeakPeriods(this.billingPeakPeriods)
    if (index < 0 || index >= next.length) {
      return
    }
    if (startMinutes !== undefined) {
      next[index].startMinutes = normalizeBillingMinuteOfDay(startMinutes)
    }
    if (endMinutes !== undefined) {
      next[index].endMinutes = normalizeBillingMinuteOfDay(endMinutes)
    }
    this.billingPeakPeriods = next
  }

  private addBillingPeakPeriod(): void {
    if (this.billingPeakPeriods.length >= 3) {
      return
    }
    const next = this.copyBillingPeakPeriods(this.billingPeakPeriods)
    next.push(new BillingTimePeriod(0, 0))
    this.billingPeakPeriods = next
    this.billingEmptyPeriodAnchored[next.length - 1] = false
  }

  private removeBillingPeakPeriod(index: number): void {
    if (this.billingPeakPeriods.length <= 1) {
      return
    }
    const next: BillingTimePeriod[] = []
    for (let i = 0; i < this.billingPeakPeriods.length; i++) {
      if (i !== index) {
        next.push(new BillingTimePeriod(
          this.billingPeakPeriods[i].startMinutes,
          this.billingPeakPeriods[i].endMinutes
        ))
      }
    }
    this.billingPeakPeriods = next
    const nextAnchored: boolean[] = []
    for (let i = 0; i < this.billingEmptyPeriodAnchored.length; i++) {
      if (i !== index) {
        nextAnchored.push(this.billingEmptyPeriodAnchored[i])
      }
    }
    while (nextAnchored.length < 3) {
      nextAnchored.push(false)
    }
    this.billingEmptyPeriodAnchored = nextAnchored
  }

  private showBillingTimePicker(periodIndex: number, isStart: boolean, minutes: number): void {
    const normalized = normalizeBillingMinuteOfDay(minutes)
    this.billingPickerPeriodIndex = periodIndex
    this.billingPickerIsStart = isStart
    this.billingPickerSelectedMinutes = normalized
    this.billingPickerInitialTime = new Date(
      2000, 0, 1, Math.floor(normalized / 60), normalized % 60, 0, 0
    )
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: (): void => {
        this.BillingTimePickerDialog()
      },
      autoCancel: true,
      alignment: DialogAlignment.Center,
      cornerRadius: 24,
      backgroundColor: Color.Transparent,
      backgroundBlurStyle: BlurStyle.NONE,
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THICK
      })
    })
      .then((dialogId: number): void => {
        this.billingTimePickerDialogId = dialogId
      })
      .catch((error: Object): void => {
        console.error('ModelEditSheet', `Failed to open time picker: ${JSON.stringify(error)}`)
      })
  }

  private closeBillingTimePickerDialog(): void {
    if (this.billingTimePickerDialogId < 0) {
      return
    }
    this.getUIContext().getPromptAction().closeCustomDialog(this.billingTimePickerDialogId)
    this.billingTimePickerDialogId = -1
  }

  private acceptBillingTimePicker(): void {
    if (this.billingPickerPeriodIndex < 0) {
      this.closeBillingTimePickerDialog()
      return
    }
    const next = this.copyBillingPeakPeriods(this.billingPeakPeriods)
    if (this.billingPickerPeriodIndex >= next.length) {
      this.closeBillingTimePickerDialog()
      return
    }
    const editingPeriod = next[this.billingPickerPeriodIndex]
    if (editingPeriod.startMinutes === editingPeriod.endMinutes &&
      !this.billingEmptyPeriodAnchored[this.billingPickerPeriodIndex]) {
      // 新增时段先用首次选择的时间作为锚点，保持空区间，随后再设置另一端。
      editingPeriod.startMinutes = this.billingPickerSelectedMinutes
      editingPeriod.endMinutes = this.billingPickerSelectedMinutes
    } else if (this.billingPickerIsStart) {
      editingPeriod.startMinutes = this.billingPickerSelectedMinutes
    } else {
      editingPeriod.endMinutes = this.billingPickerSelectedMinutes
    }
    if (hasOverlappingBillingPeakPeriods(next)) {
      this.showBillingPeriodOverlapMessage()
      return
    }
    this.billingPeakPeriods = next
    this.billingEmptyPeriodAnchored[this.billingPickerPeriodIndex] =
      editingPeriod.startMinutes === editingPeriod.endMinutes
    this.closeBillingTimePickerDialog()
  }

  private showBillingPeriodOverlapMessage(): void {
    showToast(this.getUIContext(), pickLocalizedText(
      '峰时段不能重叠，请调整开始或结束时间',
      'Peak periods cannot overlap. Adjust the start or end time.'
    ))
  }

  private saveDraft(): void {
    if (this.billingEnabled && this.billingTimeOfUseEnabled &&
      hasOverlappingBillingPeakPeriods(this.billingPeakPeriods)) {
      this.showBillingPeriodOverlapMessage()
      return
    }
    this.onSave(this.buildDraft())
  }

  private updateBillingPickerSelection(value: TimePickerResult): void {
    if (value.hour === undefined || value.minute === undefined) {
      return
    }
    this.billingPickerSelectedMinutes = value.hour * 60 + value.minute
  }

  private get billingTimePickerTitle(): string {
    return this.billingPickerIsStart ?
      pickLocalizedText('选择开始时间', 'Select start time') :
      pickLocalizedText('选择结束时间', 'Select end time')
  }

  @Builder
  private BillingTimePickerDialog() {
    Column({ space: 16 }) {
      Text(this.billingTimePickerTitle)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      TimePicker({ selected: this.billingPickerInitialTime })
        .useMilitaryTime(true)
        .enableCascade(true)
        .selectedTextStyle({
          color: this.themePrimary,
          font: { weight: FontWeight.Medium }
        })
        .onChange((value: TimePickerResult): void => {
          this.updateBillingPickerSelection(value)
        })

      Row({ space: 12 }) {
        Button(pickLocalizedText('取消', 'Cancel'))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor($r('app.color.status_error'))
          .type(ButtonType.Capsule)
          .stateEffect(false)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.closeBillingTimePickerDialog()
          })

        Button(pickLocalizedText('确定', 'Done'))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor(Color.White)
          .type(ButtonType.Capsule)
          .stateEffect(false)
          .backgroundColor(this.themePrimary)
          .onClick(() => {
            this.acceptBillingTimePicker()
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .alignItems(HorizontalAlign.Start)
  }

  private updateSheetExpansion(): void {
    this.onAdvancedExpandedChange(this.shouldUseFullHeight)
  }

  private setBillingTimeOfUseEnabled(enabled: boolean): void {
    if (enabled &&
      this.billingPeakInputPriceText === '' && this.billingPeakOutputPriceText === '' &&
      this.billingOffPeakInputPriceText === '' && this.billingOffPeakOutputPriceText === '') {
      this.billingPeakInputPriceText = this.inputPriceText
      this.billingPeakOutputPriceText = this.outputPriceText
      this.billingOffPeakInputPriceText = this.inputPriceText
      this.billingOffPeakOutputPriceText = this.outputPriceText
    }
    this.billingTimeOfUseEnabled = enabled
    this.updateSheetExpansion()
  }

  private getBillingCurrencyIndex(currency: string): number {
    const normalized = normalizeBillingCurrency(currency)
    for (let i = 0; i < this.billingCurrencies.length; i++) {
      if (this.billingCurrencies[i] === normalized) {
        return i
      }
    }
    return 0
  }

  private buildDraft(): ModelInfoExtendedJson {
    const parsedContextLength = Number(this.contextLengthText.trim())
    const parsedMaxOutputTokens = Number(this.maxOutputTokensText.trim())
    return {
      id: this.model.id,
      name: this.tempName,
      contextLength: Number.isFinite(parsedContextLength) && parsedContextLength > 0 ?
        Math.floor(parsedContextLength) : DEFAULT_MODEL_CONTEXT_WINDOW_TOKENS,
      isEnabled: this.model.isEnabled,
      isRecommended: this.model.isRecommended,
      modelType: this.model.modelType,
      inputMode: this.capSupportsVision ? InputMode.VISION : InputMode.TEXT,
      outputMode: this.capOutputImage ? OutputMode.IMAGE : OutputMode.TEXT,
      capabilities: {
        supportsTools: this.capSupportsTools,
        supportsReasoning: this.capSupportsReasoning,
        supportsWebSearch: this.capSupportsWebSearch,
        supportsVision: this.capSupportsVision,
        supportsDocuments: this.capSupportsDocuments,
        supportsStreaming: this.capSupportsStreaming
      },
      reasoningStrategyOverride: this.reasoningStrategyOverride,
      billingEnabled: this.billingEnabled,
      billingCurrency: this.billingCurrency,
      inputPricePerMillion: parseBillingPrice(this.inputPriceText),
      outputPricePerMillion: parseBillingPrice(this.outputPriceText),
      billingTimeOfUseEnabled: this.billingTimeOfUseEnabled,
      billingRestDayOffPeakEnabled: this.billingRestDayOffPeakEnabled,
      billingPeakPeriods: this.billingPeakPeriods.slice(0, 3).map(
        (period: BillingTimePeriod): BillingTimePeriodJson => period.toJson()
      ),
      billingPeakInputPricePerMillion: parseBillingPrice(this.billingPeakInputPriceText),
      billingPeakOutputPricePerMillion: parseBillingPrice(this.billingPeakOutputPriceText),
      billingOffPeakInputPricePerMillion: parseBillingPrice(this.billingOffPeakInputPriceText),
      billingOffPeakOutputPricePerMillion: parseBillingPrice(this.billingOffPeakOutputPriceText),
      parameters: {
        temperature: this.paramTemperature,
        topP: this.paramTopP,
        maxTokens: Number.isFinite(parsedMaxOutputTokens) && parsedMaxOutputTokens > 0 ?
          Math.floor(parsedMaxOutputTokens) : this.model.parameters.maxTokens,
        presencePenalty: this.paramPresencePenalty,
        frequencyPenalty: this.paramFrequencyPenalty
      }
    }
  }

  build() {
    Column() {
      this.HeaderBar()

      Divider()
        .color($r('app.color.divider'))
        .margin({ left: 20, right: 20 })

      Scroll() {
        Column() {
          // 核心信息区
          this.ModelIdSection()

          Divider()
            .color($r('app.color.divider'))
            .margin({ left: 16, right: 16 })

          this.ModelNameSection()

          Divider()
            .color($r('app.color.divider'))
            .margin({ left: 16, right: 16 })

          this.ContextLengthSection()

          Divider()
            .color($r('app.color.divider'))
            .margin({ left: 16, right: 16 })

          // 能力标签区
          this.CapabilityChipsSection()

          Divider()
            .color($r('app.color.divider'))
            .margin({ left: 16, right: 16 })

          this.BillingSection()

          Divider()
            .color($r('app.color.divider'))
            .margin({ left: 16, right: 16 })

          // 可折叠高级参数区
          this.AdvancedParametersSection()
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 34 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(this.shouldUseFullHeight ? 1 : 0)
    }
    .width('100%')
    .height(this.shouldUseFullHeight ? '100%' : 'auto')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  HeaderBar() {
    ImmersiveSheetHeader({
      title: '编辑模型',
      showTrailing: true,
      trailingColor: this.themePrimary,
      onLeadingClick: (): void => {
        this.onCancel()
      },
      onTrailingClick: (): void => {
        this.saveDraft()
      }
    })
  }

  @Builder
  ModelIdSection() {
    Row() {
      Column() {
        Text('模型 ID')
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 4 })

        Text(this.model.id)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button() {
        SymbolGlyph($r('sys.symbol.rectangle_on_rectangle'))
          .fontSize(16)
          .fontColor([$r('app.color.text_primary')])
      }
      .type(ButtonType.Circle)
      .width(32)
      .height(32)
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  ModelNameSection() {
    Column() {
      Text('模型名称')
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 })

      TextInput({ text: this.tempName, placeholder: '输入模型显示名称' })
        .width('100%')
        .height(44)
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: Color.Transparent,
          applyShadow: false
        }))
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.tempName = value
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  ContextLengthSection() {
    Column({ space: 8 }) {
      Text(pickLocalizedText('上下文长度（Token）', 'Context length (tokens)'))
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))

      TextInput({
        text: this.contextLengthText,
        placeholder: pickLocalizedText('默认 256000', 'Default: 256000')
      })
        .width('100%')
        .height(44)
        .type(InputType.Number)
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: Color.Transparent,
          applyShadow: false
        }))
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.contextLengthText = value
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  CapabilityChipsSection() {
    Column() {
      Text('模型能力')
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 12 })

      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ModelCapabilityButton({
          icon: $r('sys.symbol.wrench_and_screwdriver'),
          label: '工具调用',
          selected: this.capSupportsTools,
          onTap: (): void => {
            this.capSupportsTools = !this.capSupportsTools
          }
        })
        ModelCapabilityButton({
          icon: $r('sys.symbol.AI_deep_thinking'),
          label: '推理',
          selected: this.capSupportsReasoning,
          onTap: (): void => {
            this.capSupportsReasoning = !this.capSupportsReasoning
          }
        })
        ModelCapabilityButton({
          icon: $r('sys.symbol.ohos_wifi'),
          label: '联网搜索',
          selected: this.capSupportsWebSearch,
          onTap: (): void => {
            this.capSupportsWebSearch = !this.capSupportsWebSearch
          }
        })
        ModelCapabilityButton({
          icon: $r('sys.symbol.pdf_doc'),
          label: '文档阅读',
          selected: this.capSupportsDocuments,
          onTap: (): void => {
            this.capSupportsDocuments = !this.capSupportsDocuments
          }
        })
        ModelCapabilityButton({
          icon: $r('sys.symbol.ohos_photo'),
          label: '视觉理解',
          selected: this.capSupportsVision,
          onTap: (): void => {
            this.capSupportsVision = !this.capSupportsVision
          }
        })
        ModelCapabilityButton({
          icon: $r('sys.symbol.picture'),
          label: '图片生成',
          selected: this.capOutputImage,
          onTap: (): void => {
            this.capOutputImage = !this.capOutputImage
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  BillingSection() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text(pickLocalizedText('模型计费', 'Model billing'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          Text(pickLocalizedText(
            '预估对话费用，可能因缓存和 Token 统计方式不同而与实际费用略有差异',
            'Estimated conversation costs may differ slightly from actual charges due to caching and token-counting methods'
          ))
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.billingEnabled })
          .selectedColor(this.themePrimary)
          .systemMaterial(new uiMaterial.Material())
          .switchPointColor(Color.White)
          .onChange((value: boolean) => {
            this.billingEnabled = value
            this.updateSheetExpansion()
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.billingEnabled) {
        Divider()
          .color($r('app.color.divider'))

        Row() {
          Text(pickLocalizedText('币种', 'Currency'))
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Select(this.billingCurrencyOptions)
            .selected(this.billingCurrencySelectedIndex)
            .value(this.billingCurrency)
            .height(38)
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
            .onSelect((index: number, value: string) => {
              this.billingCurrencySelectedIndex = index
              this.billingCurrency = normalizeBillingCurrency(value)
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row() {
          Column({ space: 3 }) {
            Text(pickLocalizedText('峰谷计费', 'Time-of-use pricing'))
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))

            Text(pickLocalizedText('按设备当前时区选择峰时或谷时价格',
              'Choose peak or off-peak prices using the device time zone'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Toggle({ type: ToggleType.Switch, isOn: this.billingTimeOfUseEnabled })
            .selectedColor(this.themePrimary)
            .systemMaterial(new uiMaterial.Material())
            .switchPointColor(Color.White)
            .onChange((value: boolean) => {
              this.setBillingTimeOfUseEnabled(value)
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.billingTimeOfUseEnabled) {
          Column({ space: 8 }) {
            Row() {
              Text(pickLocalizedText('峰时段（设备本地时间）', 'Peak periods (device local time)'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)

              if (this.billingPeakPeriods.length < 3) {
                Button(pickLocalizedText('添加时段', 'Add period'))
                  .height(30)
                  .fontSize(11)
                  .fontColor(this.themePrimary)
                  .type(ButtonType.Capsule)
                  .stateEffect(false)
                  .backgroundColor(Color.Transparent)
                  .systemMaterial(new uiMaterial.ImmersiveMaterial({
                    style: uiMaterial.ImmersiveStyle.REGULAR,
                    materialColor: Color.Transparent,
                    interactive: true,
                    lightEffect: { color: undefined }
                  }))
                  .onClick(() => {
                    this.addBillingPeakPeriod()
                  })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            ForEach(this.billingPeakPeriods, (period: BillingTimePeriod, index: number) => {
              this.BillingPeriodRow(period, index)
            }, (period: BillingTimePeriod, index: number): string =>
              `${index}_${period.startMinutes}_${period.endMinutes}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Row({ space: 8 }) {
            Checkbox()
              .select(this.billingRestDayOffPeakEnabled)
              .selectedColor(this.themePrimary)
              .hitTestBehavior(HitTestMode.None)

            Text(pickLocalizedText('法定休息日为谷价', 'Use off-peak prices on statutory rest days'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
          }
          .width('100%')
          .height(36)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.billingRestDayOffPeakEnabled = !this.billingRestDayOffPeakEnabled
          })

          this.BillingPricePair(
            pickLocalizedText('峰时价格', 'Peak prices'),
            this.billingPeakInputPriceText,
            this.billingPeakOutputPriceText,
            (value: string): void => {
              this.billingPeakInputPriceText = value
            },
            (value: string): void => {
              this.billingPeakOutputPriceText = value
            }
          )

          this.BillingPricePair(
            pickLocalizedText('谷时价格', 'Off-peak prices'),
            this.billingOffPeakInputPriceText,
            this.billingOffPeakOutputPriceText,
            (value: string): void => {
              this.billingOffPeakInputPriceText = value
            },
            (value: string): void => {
              this.billingOffPeakOutputPriceText = value
            }
          )
        } else {
          this.BillingPricePair(
            pickLocalizedText('标准价格', 'Standard prices'),
            this.inputPriceText,
            this.outputPriceText,
            (value: string): void => {
              this.inputPriceText = value
            },
            (value: string): void => {
              this.outputPriceText = value
            }
          )
        }

        Text(pickLocalizedText(
          `单位：${this.billingCurrency} / 百万 Token`,
          `Unit: ${this.billingCurrency} / million tokens`
        ))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  BillingPeriodRow(period: BillingTimePeriod, index: number) {
    Row({ space: 8 }) {
      Text(`${index + 1}`)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width(18)
        .textAlign(TextAlign.Center)

      this.BillingTimeButton(
        pickLocalizedText('开始', 'Start'),
        period.startMinutes,
        (): void => {
          this.showBillingTimePicker(index, true, period.startMinutes)
        }
      )

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontColor([$r('app.color.text_tertiary')])

      this.BillingTimeButton(
        pickLocalizedText('结束', 'End'),
        period.endMinutes,
        (): void => {
          this.showBillingTimePicker(index, false, period.endMinutes)
        }
      )

      if (this.billingPeakPeriods.length > 1) {
        Button() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(14)
            .fontColor([$r('app.color.text_tertiary')])
        }
        .type(ButtonType.Circle)
        .stateEffect(false)
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.removeBillingPeakPeriod(index)
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  BillingTimeButton(label: string, minutes: number, onTap: () => void) {
    Button() {
      Column({ space: 2 }) {
        Text(label)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))

        Text(this.formatBillingTime(minutes))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
      }
    }
    .layoutWeight(1)
    .height(50)
    .backgroundColor(Color.Transparent)
    .borderRadius(14)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: Color.Transparent,
      applyShadow: false
    }))
    .onClick(() => {
      onTap()
    })
  }

  @Builder
  BillingPricePair(
    title: string,
    inputValue: string,
    outputValue: string,
    onInputChange: (value: string) => void,
    onOutputChange: (value: string) => void
  ) {
    Column({ space: 7 }) {
      Text(title)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row({ space: 10 }) {
        this.BillingPriceInput(
          pickLocalizedText('输入', 'Input'),
          inputValue,
          onInputChange
        )

        this.BillingPriceInput(
          pickLocalizedText('输出', 'Output'),
          outputValue,
          onOutputChange
        )
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  BillingPriceInput(label: string, value: string, onChange: (value: string) => void) {
    Column({ space: 7 }) {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ text: value, placeholder: '0.00' })
        .width('100%')
        .height(42)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor(Color.Transparent)
        .borderRadius(14)
        .padding({ left: 12, right: 12 })
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: Color.Transparent,
          applyShadow: false
        }))
        .onChange((text: string) => {
          onChange(text)
        })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  AdvancedParametersSection() {
    Column() {
      // 折叠标题行
      Row() {
        Text('高级参数')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.text_tertiary')])
          .rotate({ angle: this.isAdvancedExpanded ? 90 : 0 })
          .animation({ duration: 200, curve: Curve.EaseOut })
      }
      .width('100%')
      .height(48)
      .onClick(() => {
        const expanded = !this.isAdvancedExpanded
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
          this.isAdvancedExpanded = expanded
          this.updateSheetExpansion()
        })
      })

      // 展开内容
      if (this.isAdvancedExpanded) {
        Divider()
          .color($r('app.color.divider'))

        Column() {
          Column({ space: 8 }) {
            Text(pickLocalizedText('最大输出 Token', 'Maximum output tokens'))
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .width('100%')

            TextInput({ text: this.maxOutputTokensText, placeholder: '32768' })
              .width('100%')
              .height(42)
              .type(InputType.Number)
              .backgroundColor(Color.Transparent)
              .borderRadius(14)
              .padding({ left: 12, right: 12 })
              .systemMaterial(new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
                materialColor: Color.Transparent,
                applyShadow: false
              }))
              .onChange((value: string) => {
                this.maxOutputTokensText = value
              })

            Text(pickLocalizedText(
              '该预算会从上下文总窗口中预留；发送时还会按实际输入自动收紧。',
              'Reserved from the total context window and tightened against actual input at send time.'
            ))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 12, bottom: 12 })

          Divider()
            .color($r('app.color.divider'))

          // 温度
          Column() {
            Row() {
              Column() {
                Text('温度 (Temperature)')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('控制输出的随机性，值越高越有创意')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.paramTemperature.toFixed(2))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
                .width(50)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Slider({
              value: this.paramTemperature,
              min: 0,
              max: 2,
              step: 0.1,
              style: SliderStyle.InSet
            })
              .systemMaterial(new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.ULTRA_THIN
              }))
              .selectedColor(this.themePrimaryLight)
              .trackColor(Color.White)
              .blockColor(this.themePrimary)
              .blockBorderColor(this.themePrimary)
              .blockBorderWidth(1)
              .showSteps(false)
              .showTips(false)
              .margin({ top: 8 })
              .onChange((v: number) => {
                this.paramTemperature = v
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })

          Divider()
            .color($r('app.color.divider'))

          // Top P
          Column() {
            Row() {
              Column() {
                Text('Top P')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('核采样参数，控制词汇选择范围')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.paramTopP.toFixed(2))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
                .width(50)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Slider({
              value: this.paramTopP,
              min: 0,
              max: 1,
              step: 0.05,
              style: SliderStyle.InSet
            })
              .systemMaterial(new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.ULTRA_THIN
              }))
              .selectedColor(this.themePrimaryLight)
              .trackColor(Color.White)
              .blockColor(this.themePrimary)
              .blockBorderColor(this.themePrimary)
              .blockBorderWidth(1)
              .showSteps(false)
              .showTips(false)
              .margin({ top: 8 })
              .onChange((v: number) => {
                this.paramTopP = v
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })

          Divider()
            .color($r('app.color.divider'))

          // 存在惩罚
          Column() {
            Row() {
              Column() {
                Text('存在惩罚 (Presence Penalty)')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('减少重复话题的出现')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.paramPresencePenalty.toFixed(2))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
                .width(50)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Slider({
              value: this.paramPresencePenalty,
              min: -2,
              max: 2,
              step: 0.1,
              style: SliderStyle.InSet
            })
              .systemMaterial(new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.ULTRA_THIN
              }))
              .selectedColor(this.themePrimaryLight)
              .trackColor(Color.White)
              .blockColor(this.themePrimary)
              .blockBorderColor(this.themePrimary)
              .blockBorderWidth(1)
              .showSteps(false)
              .showTips(false)
              .margin({ top: 8 })
              .onChange((v: number) => {
                this.paramPresencePenalty = v
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })

          Divider()
            .color($r('app.color.divider'))

          // 频率惩罚
          Column() {
            Row() {
              Column() {
                Text('频率惩罚 (Frequency Penalty)')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text('减少重复词汇的出现')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(this.paramFrequencyPenalty.toFixed(2))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.themePrimary)
                .width(50)
                .textAlign(TextAlign.End)
            }
            .width('100%')

            Slider({
              value: this.paramFrequencyPenalty,
              min: -2,
              max: 2,
              step: 0.1,
              style: SliderStyle.InSet
            })
              .systemMaterial(new uiMaterial.ImmersiveMaterial({
                style: uiMaterial.ImmersiveStyle.ULTRA_THIN
              }))
              .selectedColor(this.themePrimaryLight)
              .trackColor(Color.White)
              .blockColor(this.themePrimary)
              .blockBorderColor(this.themePrimary)
              .blockBorderWidth(1)
              .showSteps(false)
              .showTips(false)
              .margin({ top: 8 })
              .onChange((v: number) => {
                this.paramFrequencyPenalty = v
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })

          Divider()
            .color($r('app.color.divider'))

          // 重置按钮
          Button('重置为默认值')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor(Color.Transparent)
            .borderRadius(12)
            .border({ width: 0.5, color: $r('app.color.divider') })
            .height(44)
            .width('100%')
            .margin({ top: 12 })
            .onClick(() => {
              this.paramTemperature = 0.7
              this.paramTopP = 1.0
              this.paramPresencePenalty = 0
              this.paramFrequencyPenalty = 0
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: 0,
      bottom: 16
    })
    .backgroundColor(Color.Transparent)
  }
}
