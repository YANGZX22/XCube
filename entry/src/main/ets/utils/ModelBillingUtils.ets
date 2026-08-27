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

function roundedIntegerPercent(cacheReadTokens: number, denominator: number): number {
  const denominatorQuotient = Math.floor(denominator / 200)
  const denominatorRemainder = denominator % 200
  let lower = 0
  let upper = 100
  while (lower < upper) {
    const candidate = Math.floor((lower + upper + 1) / 2)
    const factor = candidate * 2 - 1
    const threshold = factor * denominatorQuotient + Math.ceil(factor * denominatorRemainder / 200)
    if (cacheReadTokens >= threshold) {
      lower = candidate
    } else {
      upper = candidate - 1
    }
  }
  return lower
}

// 与 deepseek-harness 一致：三类输入分桶互斥，缓存读取除以三者总和。
// 非满命中只有在当前精度会舍入成 100% 时才继续增加小数位。
export function formatCacheHitPercent(
  uncachedInputTokens: number,
  cacheReadTokens: number,
  cacheWriteTokens: number
): string | null {
  const denominator = uncachedInputTokens + cacheReadTokens + cacheWriteTokens
  if (denominator === 0) {
    return null
  }
  const missedInputTokens = uncachedInputTokens + cacheWriteTokens
  if (missedInputTokens === 0) {
    return '100'
  }

  const integerPercent = roundedIntegerPercent(cacheReadTokens, denominator)
  if (integerPercent < 100) {
    return integerPercent.toString()
  }

  let decimalPlaces = 1
  let scaledDoubleGap = missedInputTokens * 200
  const denominatorTens = Math.floor(denominator / 10)
  while (scaledDoubleGap <= denominatorTens) {
    scaledDoubleGap *= 10
    decimalPlaces += 1
  }
  const denominatorOnes = denominator % 10
  let roundedLoss = 5
  for (let loss = 1; loss < 5; loss += 1) {
    const factor = loss * 2 + 1
    const threshold = factor * denominatorTens + Math.floor(factor * denominatorOnes / 10)
    if (scaledDoubleGap <= threshold) {
      roundedLoss = loss
      break
    }
  }
  return `99.${'9'.repeat(decimalPlaces - 1)}${10 - roundedLoss}`
}

// 一次模型请求的 Token 统计器。工具调用会产生多轮 API 请求，因此不能只把
// 可见聊天历史估算一次；每轮优先采用服务端 usage，缺失时才保留本地估算。
export class RequestTokenUsageTracker {
  private completedInputTokens: number = 0
  private completedOutputTokens: number = 0
  private completedUncachedInputTokens: number = 0
  private completedCacheReadTokens: number = 0
  private completedCacheWriteTokens: number = 0
  private currentEstimatedInputTokens: number = 0
  private currentActualInputTokens: number = -1
  private currentActualOutputTokens: number = -1
  private currentCacheReadTokens: number = 0
  private currentCacheWriteTokens: number = 0
  private hasAnyActualUsage: boolean = false
  private allCompletedRoundsExact: boolean = true
  private currentRoundActive: boolean = false

  beginRound(estimatedInputTokens: number): void {
    this.currentEstimatedInputTokens = Math.max(0, Math.round(estimatedInputTokens))
    this.currentActualInputTokens = -1
    this.currentActualOutputTokens = -1
    this.currentCacheReadTokens = 0
    this.currentCacheWriteTokens = 0
    this.currentRoundActive = true
  }

  updateCurrentRoundUsage(
    inputTokens: number,
    outputTokens: number,
    cacheReadTokens: number = 0,
    cacheWriteTokens: number = 0
  ): void {
    if (Number.isFinite(inputTokens) && inputTokens >= 0) {
      this.currentActualInputTokens = Math.max(this.currentActualInputTokens, Math.round(inputTokens))
      this.hasAnyActualUsage = true
    }
    if (Number.isFinite(outputTokens) && outputTokens >= 0) {
      this.currentActualOutputTokens = Math.max(this.currentActualOutputTokens, Math.round(outputTokens))
      this.hasAnyActualUsage = true
    }
    if (Number.isFinite(cacheReadTokens) && cacheReadTokens >= 0) {
      this.currentCacheReadTokens = Math.max(this.currentCacheReadTokens, Math.round(cacheReadTokens))
    }
    if (Number.isFinite(cacheWriteTokens) && cacheWriteTokens >= 0) {
      this.currentCacheWriteTokens = Math.max(this.currentCacheWriteTokens, Math.round(cacheWriteTokens))
    }
  }

  finishRound(estimatedOutputTokens: number): void {
    if (this.currentActualInputTokens < 0 || this.currentActualOutputTokens < 0) {
      this.allCompletedRoundsExact = false
    }
    if (this.currentActualInputTokens >= 0) {
      this.addCompletedInputBuckets(
        this.currentActualInputTokens,
        this.currentCacheReadTokens,
        this.currentCacheWriteTokens
      )
    }
    this.completedInputTokens += this.getCurrentInputTokens()
    this.completedOutputTokens += this.currentActualOutputTokens >= 0 ?
      this.currentActualOutputTokens : Math.max(0, Math.round(estimatedOutputTokens))
    this.currentEstimatedInputTokens = 0
    this.currentActualInputTokens = -1
    this.currentActualOutputTokens = -1
    this.currentCacheReadTokens = 0
    this.currentCacheWriteTokens = 0
    this.currentRoundActive = false
  }

  addCompletedUsage(
    inputTokens: number,
    outputTokens: number,
    exact: boolean,
    cacheReadTokens: number = 0,
    cacheWriteTokens: number = 0
  ): void {
    const normalizedInputTokens = Math.max(0, Math.round(inputTokens))
    this.completedInputTokens += normalizedInputTokens
    this.completedOutputTokens += Math.max(0, Math.round(outputTokens))
    if (exact) {
      this.hasAnyActualUsage = true
      this.addCompletedInputBuckets(normalizedInputTokens, cacheReadTokens, cacheWriteTokens)
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
    const currentCacheReadTokens = this.currentActualInputTokens >= 0 ?
      Math.min(this.currentActualInputTokens, this.currentCacheReadTokens) : 0
    const currentCacheWriteTokens = this.currentActualInputTokens >= 0 ?
      Math.min(this.currentActualInputTokens - currentCacheReadTokens, this.currentCacheWriteTokens) : 0
    const currentUncachedInputTokens = this.currentActualInputTokens >= 0 ?
      Math.max(0, this.currentActualInputTokens - currentCacheReadTokens - currentCacheWriteTokens) : 0
    message.uncachedInputTokens = this.completedUncachedInputTokens + currentUncachedInputTokens
    message.cacheReadTokens = this.completedCacheReadTokens + currentCacheReadTokens
    message.cacheWriteTokens = this.completedCacheWriteTokens + currentCacheWriteTokens
  }

  private getCurrentInputTokens(): number {
    return this.currentActualInputTokens >= 0 ? this.currentActualInputTokens : this.currentEstimatedInputTokens
  }

  private addCompletedInputBuckets(inputTokens: number, cacheReadTokens: number, cacheWriteTokens: number): void {
    const normalizedInputTokens = Math.max(0, Math.round(inputTokens))
    const normalizedCacheReadTokens = Math.min(
      normalizedInputTokens,
      Math.max(0, Math.round(cacheReadTokens))
    )
    const normalizedCacheWriteTokens = Math.min(
      normalizedInputTokens - normalizedCacheReadTokens,
      Math.max(0, Math.round(cacheWriteTokens))
    )
    this.completedUncachedInputTokens +=
      normalizedInputTokens - normalizedCacheReadTokens - normalizedCacheWriteTokens
    this.completedCacheReadTokens += normalizedCacheReadTokens
    this.completedCacheWriteTokens += normalizedCacheWriteTokens
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
