import { describe, expect, it } from '@ohos/hypium'
import {
  aggregateDailyUsageActivity,
  buildUsageActivityCalendar,
  getUsageActivityDayKey,
  getUsageActivityLevel,
  getUsageActivityPeriod,
  UsageActivityRecord
} from '../main/ets/utils/UsageActivityUtils'

function usageRecord(timestamp: number, input: number = 100, output: number = 20): UsageActivityRecord {
  return {
    role: 'assistant', timestamp: timestamp, billingEnabled: true, billingCurrency: 'USD',
    estimatedInputTokens: input, estimatedOutputTokens: output, estimatedCost: 0.01
  }
}

export default function usageActivityTest() {
  describe('usageActivityTest', () => {
    it('uses_local_midnights_and_includes_today', 0, () => {
      const period = getUsageActivityPeriod(new Date(2026, 8, 11, 23, 59).getTime())
      expect(getUsageActivityDayKey(period.startMs)).assertEqual('2025-09-12')
      expect(getUsageActivityDayKey(period.endMs)).assertEqual('2026-09-12')
      expect(new Date(period.startMs).getHours()).assertEqual(0)
      expect(new Date(period.endMs).getHours()).assertEqual(0)
    })

    it('includes_leap_day_without_duplicating_calendar_dates', 0, () => {
      const period = getUsageActivityPeriod(new Date(2024, 2, 1).getTime())
      const calendar = buildUsageActivityCalendar([], period.startMs, period.endMs)
      const keys: string[] = []
      for (const week of calendar.weeks) {
        for (const cell of week.cells) {
          if (cell.inRange) {
            keys.push(cell.usage.dayKey)
          }
        }
      }
      expect(keys.length).assertEqual(365)
      expect(new Set<string>(keys).size).assertEqual(365)
      expect(keys.includes('2024-02-29')).assertTrue()
      expect(keys[keys.length - 1]).assertEqual('2024-03-01')
    })

    it('separates_local_days_and_sorts_ascending', 0, () => {
      const midnight = new Date(2026, 8, 11).getTime()
      const days = aggregateDailyUsageActivity([usageRecord(midnight), usageRecord(midnight - 1)],
        new Date(2026, 8, 10).getTime(), new Date(2026, 8, 12).getTime())
      expect(days.length).assertEqual(2)
      expect(days[0].dayKey).assertEqual('2026-09-10')
      expect(days[1].dayKey).assertEqual('2026-09-11')
      expect(days[1].timestamp).assertEqual(midnight)
    })

    it('counts_assistant_tokens_once_with_inclusive_start_and_exclusive_end', 0, () => {
      const start = new Date(2026, 8, 11).getTime()
      const end = new Date(2026, 8, 12).getTime()
      const user = usageRecord(start)
      user.role = 'user'
      const tool = usageRecord(start)
      tool.role = 'tool'
      const days = aggregateDailyUsageActivity([
        usageRecord(start), usageRecord(end - 1), usageRecord(end), usageRecord(start - 1),
        usageRecord(Number.NaN), user, tool
      ], start, end)
      expect(days.length).assertEqual(1)
      expect(days[0].messageCount).assertEqual(2)
      expect(days[0].inputTokens).assertEqual(200)
      expect(days[0].outputTokens).assertEqual(40)
      expect(days[0].totalTokens).assertEqual(240)
    })

    it('keeps_unpriced_tokens_without_claiming_zero_cost', 0, () => {
      const row = usageRecord(new Date(2026, 8, 11).getTime())
      row.billingEnabled = false
      const days = aggregateDailyUsageActivity([row], row.timestamp, row.timestamp + 1)
      expect(days[0].totalTokens).assertEqual(120)
      expect(days[0].unpricedMessageCount).assertEqual(1)
      expect(days[0].costs.length).assertEqual(0)
    })

    it('groups_costs_by_normalized_currency_without_conversion', 0, () => {
      const timestamp = new Date(2026, 8, 11).getTime()
      const usd = usageRecord(timestamp)
      const anotherUsd = usageRecord(timestamp)
      anotherUsd.billingCurrency = ' usd '
      const cny = usageRecord(timestamp)
      cny.billingCurrency = 'CNY'
      cny.estimatedCost = 0.3
      const day = aggregateDailyUsageActivity([usd, cny, anotherUsd], timestamp, timestamp + 1)[0]
      expect(day.costs.length).assertEqual(2)
      expect(day.costs[0].currency).assertEqual('CNY')
      expect(day.costs[0].estimatedCost).assertEqual(0.3)
      expect(day.costs[1].currency).assertEqual('USD')
      expect(day.costs[1].estimatedCost).assertEqual(0.02)
      expect(day.totalTokens).assertEqual(360)
    })

    it('distinguishes_free_usage_from_missing_or_invalid_billing', 0, () => {
      const timestamp = new Date(2026, 8, 11).getTime()
      const free = usageRecord(timestamp)
      free.estimatedCost = 0
      const missing = usageRecord(timestamp)
      missing.billingCurrency = ' '
      const invalid = usageRecord(timestamp)
      invalid.estimatedCost = Number.NaN
      const negative = usageRecord(timestamp)
      negative.estimatedCost = -1
      const day = aggregateDailyUsageActivity([free, missing, invalid, negative], timestamp, timestamp + 1)[0]
      expect(day.costs.length).assertEqual(1)
      expect(day.costs[0].estimatedCost).assertEqual(0)
      expect(day.unpricedMessageCount).assertEqual(3)
    })

    it('sanitizes_invalid_tokens_and_preserves_missing_token_records', 0, () => {
      const timestamp = new Date(2026, 8, 11).getTime()
      const day = aggregateDailyUsageActivity([
        usageRecord(timestamp, Number.NaN, -8), usageRecord(timestamp, Number.POSITIVE_INFINITY, 0)
      ], timestamp, timestamp + 1)[0]
      expect(day.totalTokens).assertEqual(0)
      expect(day.messageCount).assertEqual(2)
    })

    it('renders_empty_days_and_disables_padding_outside_the_period', 0, () => {
      const period = getUsageActivityPeriod(new Date(2026, 8, 11).getTime())
      const calendar = buildUsageActivityCalendar([], period.startMs, period.endMs)
      let count = 0
      let monthWeeks = 0
      for (const month of calendar.months) {
        monthWeeks += month.weekCount
      }
      for (const week of calendar.weeks) {
        expect(week.cells.length).assertEqual(7)
        expect(new Date(week.cells[0].usage.timestamp).getDay()).assertEqual(1)
        for (const cell of week.cells) {
          expect(cell.level).assertEqual(0)
          expect(cell.usage.totalTokens).assertEqual(0)
          if (cell.inRange) {
            count += 1
          } else {
            expect(cell.usage.timestamp < period.startMs || cell.usage.timestamp >= period.endMs).assertTrue()
          }
        }
      }
      expect(count).assertEqual(365)
      expect(monthWeeks).assertEqual(calendar.weeks.length)
      expect(calendar.weeks[0].cells[0].inRange).assertFalse()
      expect(calendar.weeks[calendar.weeks.length - 1].cells[6].inRange).assertFalse()
    })

    it('shows_real_totals_and_does_not_mutate_source_records', 0, () => {
      const period = getUsageActivityPeriod(new Date(2026, 8, 11).getTime())
      const row = usageRecord(new Date(2026, 8, 11).getTime(), 1000000, 200000)
      const days = aggregateDailyUsageActivity([row], period.startMs, period.endMs)
      const calendar = buildUsageActivityCalendar(days, period.startMs, period.endMs)
      const friday = calendar.weeks[calendar.weeks.length - 1].cells[4]
      expect(friday.usage.totalTokens).assertEqual(1200000)
      expect(friday.level).assertEqual(3)
      expect(days.length).assertEqual(1)
      expect(row.estimatedInputTokens).assertEqual(1000000)
    })

    it('uses_fixed_wider_bands_with_inclusive_thresholds', 0, () => {
      expect(getUsageActivityLevel(0)).assertEqual(0)
      expect(getUsageActivityLevel(1)).assertEqual(1)
      expect(getUsageActivityLevel(99999)).assertEqual(1)
      expect(getUsageActivityLevel(100000)).assertEqual(2)
      expect(getUsageActivityLevel(999999)).assertEqual(2)
      expect(getUsageActivityLevel(1000000)).assertEqual(3)
      expect(getUsageActivityLevel(9999999)).assertEqual(3)
      expect(getUsageActivityLevel(10000000)).assertEqual(4)
      expect(getUsageActivityLevel(370000000)).assertEqual(4)
    })

    it('rejects_invalid_usage_when_choosing_a_color', 0, () => {
      expect(getUsageActivityLevel(-1)).assertEqual(0)
      expect(getUsageActivityLevel(Number.NaN)).assertEqual(0)
      expect(getUsageActivityLevel(Number.POSITIVE_INFINITY)).assertEqual(0)
    })

    it('does_not_recolor_existing_days_when_a_larger_peak_is_added', 0, () => {
      const timestamp = new Date(2026, 8, 11).getTime()
      const end = new Date(2026, 8, 13).getTime()
      const first = usageRecord(timestamp, 1000000, 200000)
      const before = buildUsageActivityCalendar(aggregateDailyUsageActivity([first], timestamp, end), timestamp, end)
      const peak = usageRecord(new Date(2026, 8, 12).getTime(), 370000000, 0)
      const after = buildUsageActivityCalendar(aggregateDailyUsageActivity([first, peak], timestamp, end), timestamp, end)
      expect(before.weeks[0].cells[4].level).assertEqual(3)
      expect(after.weeks[0].cells[4].level).assertEqual(3)
      expect(after.weeks[0].cells[5].level).assertEqual(4)
      expect(after.weeks[0].cells[4].usage.totalTokens).assertEqual(1200000)
    })

    it('ignores_out_of_range_records_and_handles_invalid_periods', 0, () => {
      const timestamp = new Date(2026, 8, 11).getTime()
      const days = aggregateDailyUsageActivity([usageRecord(timestamp), usageRecord(timestamp + 86400000, 1e9)],
        timestamp, timestamp + 172800000)
      const calendar = buildUsageActivityCalendar(days, timestamp, new Date(2026, 8, 12).getTime())
      expect(calendar.weeks[0].cells[4].level).assertEqual(1)
      expect(buildUsageActivityCalendar([], timestamp, timestamp).weeks.length).assertEqual(0)
      expect(buildUsageActivityCalendar([], Number.NaN, timestamp).weeks.length).assertEqual(0)
    })
  })
}
