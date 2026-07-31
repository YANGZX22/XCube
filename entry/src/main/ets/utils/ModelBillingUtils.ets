import { ChatMessage, ModelInfo } from '../models/ChatModels'

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
    this.inputPricePerMillion = normalizeBillingPrice(model.inputPricePerMillion)
    this.outputPricePerMillion = normalizeBillingPrice(model.outputPricePerMillion)
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
    } else if (!/\s/.test(normalized.charAt(i))) {
      otherCharacterCount += 1
    }
  }
  return Math.max(1, Math.ceil(cjkCount + otherCharacterCount / 4))
}

function estimateMessagePayloadTokens(message: ChatMessage): number {
  let tokens = estimateTextTokens(message.content) + estimateTextTokens(message.reasoningContent) + 4
  for (let i = 0; i < message.attachments.length; i++) {
    tokens += 64
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
  if (refreshInputTokens || message.estimatedInputTokens <= 0) {
    message.estimatedInputTokens = estimateConversationInputTokens(historyMessages)
  }
  message.estimatedOutputTokens = estimateAssistantOutputTokens(message)
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
