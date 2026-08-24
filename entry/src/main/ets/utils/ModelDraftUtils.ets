import {
  BillingTimePeriod,
  InputMode,
  ModelCapabilities,
  ModelInfo,
  ModelInfoExtendedJson,
  ModelParameters,
  ModelType,
  OutputMode
} from '../models/ChatModels'

function toModelType(raw?: string): ModelType {
  return raw === 'embedding' ? ModelType.EMBEDDING : ModelType.CHAT
}

function toInputMode(raw?: string): InputMode {
  return raw === InputMode.VISION ? InputMode.VISION : InputMode.TEXT
}

function toOutputMode(raw?: string): OutputMode {
  return raw === OutputMode.IMAGE ? OutputMode.IMAGE : OutputMode.TEXT
}

export function applyModelDraft(target: ModelInfo, draft: ModelInfoExtendedJson): void {
  target.name = draft.name
  target.contextLength = draft.contextLength
  target.isEnabled = draft.isEnabled
  target.isRecommended = draft.isRecommended

  if (draft.modelType !== undefined) {
    target.modelType = toModelType(draft.modelType)
  }
  if (draft.inputMode !== undefined) {
    target.inputMode = toInputMode(draft.inputMode)
  }
  if (draft.outputMode !== undefined) {
    target.outputMode = toOutputMode(draft.outputMode)
  }
  if (draft.capabilities !== undefined) {
    target.capabilities = ModelCapabilities.fromJson(draft.capabilities)
  }
  if (draft.parameters !== undefined) {
    target.parameters = ModelParameters.fromJson(draft.parameters)
  }
  if (draft.reasoningStrategyOverride !== undefined) {
    target.reasoningStrategyOverride = draft.reasoningStrategyOverride
  }
  if (draft.billingEnabled !== undefined) {
    target.billingEnabled = draft.billingEnabled
  }
  if (draft.billingCurrency !== undefined && draft.billingCurrency.trim() !== '') {
    target.billingCurrency = draft.billingCurrency.trim().toUpperCase()
  }
  if (draft.inputPricePerMillion !== undefined && Number.isFinite(draft.inputPricePerMillion)) {
    target.inputPricePerMillion = Math.max(0, draft.inputPricePerMillion)
  }
  if (draft.outputPricePerMillion !== undefined && Number.isFinite(draft.outputPricePerMillion)) {
    target.outputPricePerMillion = Math.max(0, draft.outputPricePerMillion)
  }
  if (draft.billingTimeOfUseEnabled !== undefined) {
    target.billingTimeOfUseEnabled = draft.billingTimeOfUseEnabled
  }
  if (draft.billingRestDayOffPeakEnabled !== undefined) {
    target.billingRestDayOffPeakEnabled = draft.billingRestDayOffPeakEnabled
  }
  if (draft.billingPeakPeriods !== undefined && draft.billingPeakPeriods.length > 0) {
    const periods: BillingTimePeriod[] = []
    const count = Math.min(3, draft.billingPeakPeriods.length)
    for (let i = 0; i < count; i++) {
      periods.push(BillingTimePeriod.fromJson(draft.billingPeakPeriods[i]))
    }
    target.billingPeakPeriods = periods
  } else if (draft.billingPeakStartMinutes !== undefined && draft.billingPeakEndMinutes !== undefined) {
    target.billingPeakPeriods = [new BillingTimePeriod(
      draft.billingPeakStartMinutes,
      draft.billingPeakEndMinutes
    )]
  }
  if (draft.billingPeakInputPricePerMillion !== undefined &&
    Number.isFinite(draft.billingPeakInputPricePerMillion)) {
    target.billingPeakInputPricePerMillion = Math.max(0, draft.billingPeakInputPricePerMillion)
  }
  if (draft.billingPeakOutputPricePerMillion !== undefined &&
    Number.isFinite(draft.billingPeakOutputPricePerMillion)) {
    target.billingPeakOutputPricePerMillion = Math.max(0, draft.billingPeakOutputPricePerMillion)
  }
  if (draft.billingOffPeakInputPricePerMillion !== undefined &&
    Number.isFinite(draft.billingOffPeakInputPricePerMillion)) {
    target.billingOffPeakInputPricePerMillion = Math.max(0, draft.billingOffPeakInputPricePerMillion)
  }
  if (draft.billingOffPeakOutputPricePerMillion !== undefined &&
    Number.isFinite(draft.billingOffPeakOutputPricePerMillion)) {
    target.billingOffPeakOutputPricePerMillion = Math.max(0, draft.billingOffPeakOutputPricePerMillion)
  }
}
