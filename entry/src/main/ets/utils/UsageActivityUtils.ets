// Only stored usage metadata is needed; message text and attachments are never read.
export interface UsageActivityRecord {
  role: string
  timestamp: number
  billingEnabled: boolean
  billingCurrency: string
  estimatedInputTokens: number
  estimatedOutputTokens: number
  estimatedCost: number
}

export interface UsageActivityCost {
  currency: string
  estimatedCost: number
}

export interface DailyUsageActivity {
  dayKey: string
  timestamp: number
  inputTokens: number
  outputTokens: number
  totalTokens: number
  messageCount: number
  unpricedMessageCount: number
  costs: UsageActivityCost[]
}

export interface UsageActivityPeriod {
  startMs: number
  endMs: number // Exclusive: the next local midnight, not a fixed 24-hour offset.
}

export interface UsageActivityCell {
  usage: DailyUsageActivity
  inRange: boolean
  level: number
}

export interface UsageActivityWeek {
  key: string
  cells: UsageActivityCell[]
}

export interface UsageActivityMonth {
  key: string
  month: number
  weekCount: number
}

export interface UsageActivityCalendar {
  weeks: UsageActivityWeek[]
  months: UsageActivityMonth[]
}

export function getUsageActivityDayKey(timestamp: number): string {
  const date = new Date(timestamp)
  return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`
}

export function getUsageActivityPeriod(now: number = Date.now()): UsageActivityPeriod {
  const today = new Date(now)
  today.setHours(0, 0, 0, 0)
  const start = new Date(today.getTime())
  start.setDate(start.getDate() - 364)
  const end = new Date(today.getTime())
  end.setDate(end.getDate() + 1)
  return { startMs: start.getTime(), endMs: end.getTime() }
}

function emptyUsageActivity(timestamp: number): DailyUsageActivity {
  const date = new Date(timestamp)
  date.setHours(0, 0, 0, 0)
  return {
    dayKey: getUsageActivityDayKey(timestamp),
    timestamp: date.getTime(),
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    messageCount: 0,
    unpricedMessageCount: 0,
    costs: []
  }
}

function validUsageAmount(value: number): number {
  return Number.isFinite(value) ? Math.max(0, value) : 0
}

export function aggregateDailyUsageActivity(
  rows: UsageActivityRecord[], startMs: number, endMs: number
): DailyUsageActivity[] {
  const days = new Map<string, DailyUsageActivity>()
  for (const row of rows) {
    // Input/cache usage is already accumulated on the assistant message. Counting user
    // messages or adding cache buckets again would double-count the same request.
    if (row.role !== 'assistant' || !Number.isFinite(row.timestamp) ||
      row.timestamp < startMs || row.timestamp >= endMs) {
      continue
    }
    const key = getUsageActivityDayKey(row.timestamp)
    let day = days.get(key)
    if (day === undefined) {
      day = emptyUsageActivity(row.timestamp)
      days.set(key, day)
    }
    day.inputTokens += Math.floor(validUsageAmount(row.estimatedInputTokens))
    day.outputTokens += Math.floor(validUsageAmount(row.estimatedOutputTokens))
    day.totalTokens = day.inputTokens + day.outputTokens
    day.messageCount += 1
    const currency = row.billingCurrency.trim().toUpperCase()
    if (!row.billingEnabled || currency === '' || !Number.isFinite(row.estimatedCost) || row.estimatedCost < 0) {
      day.unpricedMessageCount += 1
      continue
    }
    const cost = day.costs.find((item: UsageActivityCost): boolean => item.currency === currency)
    if (cost !== undefined) {
      cost.estimatedCost += row.estimatedCost
    } else {
      day.costs.push({ currency: currency, estimatedCost: row.estimatedCost })
    }
  }
  const result = Array.from(days.values())
  result.sort((a: DailyUsageActivity, b: DailyUsageActivity): number => a.timestamp - b.timestamp)
  for (const day of result) {
    day.costs.sort((a: UsageActivityCost, b: UsageActivityCost): number => a.currency.localeCompare(b.currency))
  }
  return result
}

export function getUsageActivityLevel(tokens: number): number {
  if (!Number.isFinite(tokens) || tokens <= 0) {
    return 0
  }
  // Fixed, wider bands for agent workloads: >0–100K, 100K–1M, 1M–10M, 10M+.
  // New peak days must not change the meaning of colors on existing days.
  if (tokens < 100000) {
    return 1
  }
  if (tokens < 1000000) {
    return 2
  }
  return tokens < 10000000 ? 3 : 4
}

export function buildUsageActivityCalendar(
  days: DailyUsageActivity[], startMs: number, endMs: number
): UsageActivityCalendar {
  const calendar: UsageActivityCalendar = { weeks: [], months: [] }
  if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs) {
    return calendar
  }
  const byDay = new Map<string, DailyUsageActivity>()
  for (const day of days) {
    if (day.timestamp >= startMs && day.timestamp < endMs) {
      byDay.set(day.dayKey, day)
    }
  }
  const cursor = new Date(startMs)
  cursor.setHours(0, 0, 0, 0)
  // Monday at the top, with blank padding before the first date and after today.
  cursor.setDate(cursor.getDate() - (cursor.getDay() + 6) % 7)
  while (cursor.getTime() < endMs) {
    const week: UsageActivityWeek = { key: getUsageActivityDayKey(cursor.getTime()), cells: [] }
    let month = -1
    let monthKey = ''
    for (let weekday = 0; weekday < 7; weekday++) {
      const timestamp = cursor.getTime()
      const key = getUsageActivityDayKey(timestamp)
      const inRange = timestamp >= startMs && timestamp < endMs
      const usage = byDay.get(key) ?? emptyUsageActivity(timestamp)
      week.cells.push({ usage: usage, inRange: inRange, level: getUsageActivityLevel(usage.totalTokens) })
      if (inRange && ((calendar.weeks.length === 0 && month < 0) || cursor.getDate() === 1)) {
        month = cursor.getMonth() + 1
        monthKey = key.substring(0, 7)
      }
      cursor.setDate(cursor.getDate() + 1)
    }
    if (month > 0) {
      calendar.months.push({ key: monthKey, month: month, weekCount: 0 })
    }
    if (calendar.months.length > 0) {
      calendar.months[calendar.months.length - 1].weekCount += 1
    }
    calendar.weeks.push(week)
  }
  return calendar
}
