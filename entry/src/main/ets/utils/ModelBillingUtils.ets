import { BillingTimePeriod, ChatMessage, MessageAttachment, ModelInfo } from '../models/ChatModels'

export class ModelBillingSnapshot {
  enabled: boolean = false
  currency: string = 'CNY'
  inputPricePerMillion: number = 0
  outputPricePerMillion: number = 0

  constructor(model: ModelInfo | null = null) {
    if (model === null) {
      return
    }
    this.enabled = model.billingEnabled
    this.currency = normalizeBillingCurrency(model.billingCurrency)
    const prices = resolveModelBillingPrices(model)
    this.inputPricePerMillion = prices.inputPricePerMillion
    this.outputPricePerMillion = prices.outputPricePerMillion
  }
}

export class ResolvedBillingPrices {
  inputPricePerMillion: number
  outputPricePerMillion: number
  isPeak: boolean

  constructor(inputPricePerMillion: number, outputPricePerMillion: number, isPeak: boolean) {
    this.inputPricePerMillion = inputPricePerMillion
    this.outputPricePerMillion = outputPricePerMillion
    this.isPeak = isPeak
  }
}

export function normalizeBillingCurrency(currency: string): string {
  const normalized = currency.trim().toUpperCase()
  return normalized !== '' ? normalized : 'CNY'
}

export function normalizeBillingPrice(price: number): number {
  if (!Number.isFinite(price) || price < 0) {
    return 0
  }
  return price
}

export function parseBillingPrice(text: string): number {
  const normalized = text.trim().replace(',', '.')
  if (normalized === '') {
    return 0
  }
  return normalizeBillingPrice(Number(normalized))
}

export function normalizeBillingMinuteOfDay(minutes: number): number {
  if (!Number.isFinite(minutes)) {
    return 0
  }
  return Math.max(0, Math.min(1439, Math.floor(minutes)))
}

// start === end 表示峰时段为空；跨午夜时（如 22:00–08:00）按两段峰时处理。
export function isBillingPeakMinute(currentMinutes: number, startMinutes: number, endMinutes: number): boolean {
  const current = normalizeBillingMinuteOfDay(currentMinutes)
  const start = normalizeBillingMinuteOfDay(startMinutes)
  const end = normalizeBillingMinuteOfDay(endMinutes)
  if (start === end) {
    return false
  }
  if (start < end) {
    return current >= start && current < end
  }
  return current >= start || current < end
}

export function isBillingPeakInPeriods(currentMinutes: number, periods: BillingTimePeriod[]): boolean {
  const count = Math.min(3, periods.length)
  for (let i = 0; i < count; i++) {
    if (isBillingPeakMinute(currentMinutes, periods[i].startMinutes, periods[i].endMinutes)) {
      return true
    }
  }
  return false
}

// 峰时段是左闭右开的环形区间；首尾相接不算重叠，start === end 的空时段也不参与判断。
export function doBillingPeakPeriodsOverlap(
  first: BillingTimePeriod,
  second: BillingTimePeriod
): boolean {
  const firstStart = normalizeBillingMinuteOfDay(first.startMinutes)
  const firstEnd = normalizeBillingMinuteOfDay(first.endMinutes)
  const secondStart = normalizeBillingMinuteOfDay(second.startMinutes)
  const secondEnd = normalizeBillingMinuteOfDay(second.endMinutes)
  if (firstStart === firstEnd || secondStart === secondEnd) {
    return false
  }
  return isBillingPeakMinute(firstStart, secondStart, secondEnd) ||
    isBillingPeakMinute(secondStart, firstStart, firstEnd)
}

export function hasOverlappingBillingPeakPeriods(periods: BillingTimePeriod[]): boolean {
  const count = Math.min(3, periods.length)
  for (let firstIndex = 0; firstIndex < count; firstIndex++) {
    for (let secondIndex = firstIndex + 1; secondIndex < count; secondIndex++) {
      if (doBillingPeakPeriodsOverlap(periods[firstIndex], periods[secondIndex])) {
        return true
      }
    }
  }
  return false
}

export function getDeviceLocalMinuteOfDay(date: Date = new Date()): number {
  return date.getHours() * 60 + date.getMinutes()
}

// 设备本地日期的周六、周日视为法定休息日；中国调休与节假日需外部日历才能准确识别。
export function isDeviceLocalRestDay(date: Date = new Date()): boolean {
  const dayOfWeek = date.getDay()
  return dayOfWeek === 0 || dayOfWeek === 6
}

export function resolveModelBillingPrices(model: ModelInfo, date: Date = new Date()): ResolvedBillingPrices {
  if (!model.billingTimeOfUseEnabled) {
    return new ResolvedBillingPrices(
      normalizeBillingPrice(model.inputPricePerMillion),
      normalizeBillingPrice(model.outputPricePerMillion),
      false
    )
  }
  const useRestDayOffPeak = model.billingRestDayOffPeakEnabled && isDeviceLocalRestDay(date)
  const isPeak = !useRestDayOffPeak &&
    isBillingPeakInPeriods(getDeviceLocalMinuteOfDay(date), model.billingPeakPeriods)
  if (isPeak) {
    return new ResolvedBillingPrices(
      normalizeBillingPrice(model.billingPeakInputPricePerMillion),
      normalizeBillingPrice(model.billingPeakOutputPricePerMillion),
      true
    )
  }
  return new ResolvedBillingPrices(
    normalizeBillingPrice(model.billingOffPeakInputPricePerMillion),
    normalizeBillingPrice(model.billingOffPeakOutputPricePerMillion),
    false
  )
}

export function estimateTextTokens(text: string): number {
  const normalized = text.trim()
  if (normalized === '') {
    return 0
  }
  let cjkCount = 0
  let otherCharacterCount = 0
  for (let i = 0; i < normalized.length; i++) {
    const code = normalized.charCodeAt(i)
    const isCjk =
      (code >= 0x3400 && code <= 0x9FFF) ||
      (code >= 0x3040 && code <= 0x30FF) ||
      (code >= 0xAC00 && code <= 0xD7AF)
    if (isCjk) {
      cjkCount += 1
    } else {
      // 空格、换行与 Markdown/JSON 缩进同样会进入 tokenizer，不能从估算中丢掉。
      otherCharacterCount += 1
    }
  }
  return Math.max(1, Math.ceil(cjkCount + otherCharacterCount / 4))
}

// 二进制附件由供应商的文件/视觉管线或本地读取工具解析，原始字节数不是模型输入
// Token。发送前只估算消息封装与附件元数据；供应商返回 usage 后由真实值覆盖。
export function estimateProviderManagedAttachmentTokens(attachment: MessageAttachment): number {
  const metadataTokens = estimateTextTokens(attachment.name) + estimateTextTokens(attachment.mimeType) + 8
  if (attachment.mimeType.toLowerCase().startsWith('image/')) {
    // 对 auto detail 无法在客户端预知图像切片数，仅保留常见的基础图像预算。
    return metadataTokens + 85
  }
  return metadataTokens + 32
}

// 一次模型请求的 Token 统计器。工具调用会产生多轮 API 请求，因此不能只把
// 可见聊天历史估算一次；每轮优先采用服务端 usage，缺失时才保留本地估算。
export class RequestTokenUsageTracker {
  private completedInputTokens: number = 0
  private completedOutputTokens: number = 0
  private currentEstimatedInputTokens: number = 0
  private currentActualInputTokens: number = -1
  private currentActualOutputTokens: number = -1
  private hasAnyActualUsage: boolean = false
  private allCompletedRoundsExact: boolean = true
  private currentRoundActive: boolean = false

  beginRound(estimatedInputTokens: number): void {
    this.currentEstimatedInputTokens = Math.max(0, Math.round(estimatedInputTokens))
    this.currentActualInputTokens = -1
    this.currentActualOutputTokens = -1
    this.currentRoundActive = true
  }

  updateCurrentRoundUsage(inputTokens: number, outputTokens: number): void {
    if (Number.isFinite(inputTokens) && inputTokens >= 0) {
      this.currentActualInputTokens = Math.max(this.currentActualInputTokens, Math.round(inputTokens))
      this.hasAnyActualUsage = true
    }
    if (Number.isFinite(outputTokens) && outputTokens >= 0) {
      this.currentActualOutputTokens = Math.max(this.currentActualOutputTokens, Math.round(outputTokens))
      this.hasAnyActualUsage = true
    }
  }

  finishRound(estimatedOutputTokens: number): void {
    if (this.currentActualInputTokens < 0 || this.currentActualOutputTokens < 0) {
      this.allCompletedRoundsExact = false
    }
    this.completedInputTokens += this.getCurrentInputTokens()
    this.completedOutputTokens += this.currentActualOutputTokens >= 0 ?
      this.currentActualOutputTokens : Math.max(0, Math.round(estimatedOutputTokens))
    this.currentEstimatedInputTokens = 0
    this.currentActualInputTokens = -1
    this.currentActualOutputTokens = -1
    this.currentRoundActive = false
  }

  addCompletedUsage(inputTokens: number, outputTokens: number, exact: boolean): void {
    this.completedInputTokens += Math.max(0, Math.round(inputTokens))
    this.completedOutputTokens += Math.max(0, Math.round(outputTokens))
    if (exact) {
      this.hasAnyActualUsage = true
    } else {
      this.allCompletedRoundsExact = false
    }
  }

  applyToMessage(message: ChatMessage): void {
    message.tokenUsageTracked = true
    const currentRoundExact = !this.currentRoundActive ||
      (this.currentActualInputTokens >= 0 && this.currentActualOutputTokens >= 0)
    message.tokenUsageExact = this.hasAnyActualUsage && this.allCompletedRoundsExact && currentRoundExact
    message.estimatedInputTokens = this.completedInputTokens + this.getCurrentInputTokens()
    message.estimatedOutputTokens = this.completedOutputTokens +
      (this.currentActualOutputTokens >= 0 ? this.currentActualOutputTokens : 0)
  }

  private getCurrentInputTokens(): number {
    return this.currentActualInputTokens >= 0 ? this.currentActualInputTokens : this.currentEstimatedInputTokens
  }
}

function estimateMessagePayloadTokens(message: ChatMessage): number {
  let tokens = estimateTextTokens(message.content) + estimateTextTokens(message.reasoningContent) + 4
  for (let i = 0; i < message.attachments.length; i++) {
    tokens += estimateProviderManagedAttachmentTokens(message.attachments[i])
  }
  for (let i = 0; i < message.toolCalls.length; i++) {
    const toolCall = message.toolCalls[i]
    tokens += estimateTextTokens(toolCall.functionName)
    tokens += estimateTextTokens(toolCall.arguments)
  }
  for (let i = 0; i < message.toolResults.length; i++) {
    tokens += estimateTextTokens(message.toolResults[i].content)
  }
  return tokens
}

export function estimateConversationInputTokens(messages: ChatMessage[]): number {
  let tokens = 3
  for (let i = 0; i < messages.length; i++) {
    tokens += estimateMessagePayloadTokens(messages[i])
  }
  return tokens
}

export function estimateAssistantOutputTokens(message: ChatMessage): number {
  return Math.max(0, estimateMessagePayloadTokens(message) - 4)
}

export function calculateEstimatedCost(
  inputTokens: number,
  outputTokens: number,
  inputPricePerMillion: number,
  outputPricePerMillion: number
): number {
  const inputCost = Math.max(0, inputTokens) * normalizeBillingPrice(inputPricePerMillion) / 1_000_000
  const outputCost = Math.max(0, outputTokens) * normalizeBillingPrice(outputPricePerMillion) / 1_000_000
  return inputCost + outputCost
}

export function applyEstimatedBilling(
  message: ChatMessage,
  historyMessages: ChatMessage[],
  billing: ModelBillingSnapshot,
  refreshInputTokens: boolean = false
): void {
  if (!billing.enabled) {
    return
  }
  message.billingEnabled = true
  message.billingCurrency = billing.currency
  message.inputPricePerMillion = billing.inputPricePerMillion
  message.outputPricePerMillion = billing.outputPricePerMillion
  if (!message.tokenUsageTracked && (refreshInputTokens || message.estimatedInputTokens <= 0)) {
    message.estimatedInputTokens = estimateConversationInputTokens(historyMessages)
  }
  if (!message.tokenUsageTracked) {
    message.estimatedOutputTokens = estimateAssistantOutputTokens(message)
  }
  message.estimatedCost = calculateEstimatedCost(
    message.estimatedInputTokens,
    message.estimatedOutputTokens,
    message.inputPricePerMillion,
    message.outputPricePerMillion
  )
}

export function getBillingCurrencySymbol(currency: string): string {
  const normalized = normalizeBillingCurrency(currency)
  if (normalized === 'CNY' || normalized === 'JPY') {
    return '¥'
  }
  if (normalized === 'USD') {
    return '$'
  }
  if (normalized === 'EUR') {
    return '€'
  }
  if (normalized === 'GBP') {
    return '£'
  }
  if (normalized === 'KRW') {
    return '₩'
  }
  return `${normalized} `
}

function trimTrailingZeroes(value: string): string {
  let result = value
  while (result.includes('.') && result.endsWith('0')) {
    result = result.substring(0, result.length - 1)
  }
  if (result.endsWith('.')) {
    result = result.substring(0, result.length - 1)
  }
  return result
}

export function formatBillingAmount(currency: string, amount: number): string {
  const safeAmount = Number.isFinite(amount) && amount > 0 ? amount : 0
  const symbol = getBillingCurrencySymbol(currency)
  if (safeAmount === 0) {
    return `${symbol}0`
  }
  if (safeAmount < 0.000001) {
    return `< ${symbol}0.000001`
  }
  const fractionDigits = safeAmount < 0.01 ? 6 : (safeAmount < 1 ? 4 : 2)
  return `${symbol}${trimTrailingZeroes(safeAmount.toFixed(fractionDigits))}`
}
