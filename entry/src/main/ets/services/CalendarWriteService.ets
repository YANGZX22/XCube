import abilityAccessCtrl, { Permissions, PermissionRequestResult } from '@ohos.abilityAccessCtrl'
import common from '@ohos.app.ability.common'
import calendarManager from '@ohos.calendarManager'
import { BusinessError } from '@kit.BasicServicesKit'

export enum ScheduleWriteTarget {
  CALENDAR = 'calendar'
}

export interface WriteScheduleRequest {
  target: string
  title: string
  startTime: string
  endTime?: string
  allDay?: boolean
  description?: string
  location?: string
  reminderMinutesBefore?: number
}

export interface ReadScheduleRequest {
  startTime?: string
  endTime?: string
  daysBefore?: number
  daysAfter?: number
  limit?: number
  includeDescription?: boolean
  includeLocation?: boolean
}

export interface WriteScheduleResult {
  ok: boolean
  target: string
  eventId?: number
  startTime: number
  endTime: number
  message: string
}

export interface ReadScheduleEvent {
  id?: number
  calendarName: string
  title: string
  startTime: number
  endTime: number
  allDay: boolean
  location?: string
  description?: string
}

export interface ReadScheduleResult {
  ok: boolean
  target: string
  rangeStart: number
  rangeEnd: number
  daysBefore: number
  daysAfter: number
  count: number
  truncated: boolean
  events: ReadScheduleEvent[]
  message: string
}

class ParsedScheduleRequest {
  target: ScheduleWriteTarget = ScheduleWriteTarget.CALENDAR
  title: string = ''
  startTime: number = 0
  endTime: number = 0
  allDay: boolean = false
  description: string = ''
  location: string = ''
  reminderMinutesBefore: number = 15
}

class ParsedReadScheduleRequest {
  rangeStart: number = 0
  rangeEnd: number = 0
  daysBefore: number = 0
  daysAfter: number = 0
  limit: number = 80
  includeDescription: boolean = false
  includeLocation: boolean = true
}

export class CalendarWriteService {
  private static instance: CalendarWriteService | null = null
  private context: common.UIAbilityContext | null = null

  private constructor() {}

  static getInstance(): CalendarWriteService {
    if (CalendarWriteService.instance === null) {
      CalendarWriteService.instance = new CalendarWriteService()
    }
    return CalendarWriteService.instance
  }

  initialize(context: common.UIAbilityContext): void {
    this.context = context
  }

  async writeSchedule(request: WriteScheduleRequest): Promise<WriteScheduleResult> {
    const parsed = this.parseRequest(request)
    await this.ensureCalendarPermission()
    const eventId = await this.addCalendarEvent(parsed)

    return {
      ok: true,
      target: parsed.target,
      eventId: eventId,
      startTime: parsed.startTime,
      endTime: parsed.endTime,
      message: `已写入系统日历，eventId=${eventId}`
    }
  }

  async readSchedule(request: ReadScheduleRequest): Promise<ReadScheduleResult> {
    const parsed = this.parseReadRequest(request)
    await this.ensureReadCalendarPermission()
    const events = await this.readCalendarEvents(parsed)
    const truncated = events.length > parsed.limit
    const visibleEvents = truncated ? events.slice(0, parsed.limit) : events
    return {
      ok: true,
      target: 'calendar',
      rangeStart: parsed.rangeStart,
      rangeEnd: parsed.rangeEnd,
      daysBefore: parsed.daysBefore,
      daysAfter: parsed.daysAfter,
      count: visibleEvents.length,
      truncated: truncated,
      events: visibleEvents,
      message: `已读取 ${visibleEvents.length} 条日程${truncated ? '，结果已按数量上限截断' : ''}`
    }
  }

  private parseRequest(request: WriteScheduleRequest): ParsedScheduleRequest {
    const parsed = new ParsedScheduleRequest()
    parsed.target = this.normalizeTarget(request.target)
    parsed.title = this.normalizeRequiredText(request.title, '标题不能为空')
    parsed.startTime = this.parseTime(request.startTime, '开始时间不能为空或格式不正确')
    parsed.allDay = request.allDay === true
    parsed.endTime = this.resolveEndTime(parsed.startTime, request.endTime, parsed.allDay)
    parsed.description = this.normalizeOptionalText(request.description)
    parsed.location = this.normalizeOptionalText(request.location)
    parsed.reminderMinutesBefore = this.normalizeReminderMinutes(request.reminderMinutesBefore)

    if (parsed.endTime <= parsed.startTime) {
      throw new Error('结束时间必须晚于开始时间')
    }
    return parsed
  }

  private parseReadRequest(request: ReadScheduleRequest): ParsedReadScheduleRequest {
    const parsed = new ParsedReadScheduleRequest()
    parsed.limit = this.normalizeLimit(request.limit)
    parsed.includeDescription = request.includeDescription === true
    parsed.includeLocation = request.includeLocation !== false

    const startText = this.normalizeOptionalText(request.startTime)
    const endText = this.normalizeOptionalText(request.endTime)
    if (startText !== '' || endText !== '') {
      if (startText === '' || endText === '') {
        throw new Error('读取日程时 start_time 和 end_time 必须同时提供')
      }
      parsed.rangeStart = this.parseTime(startText, '读取日程开始时间格式不正确')
      parsed.rangeEnd = this.parseTime(endText, '读取日程结束时间格式不正确')
      parsed.daysBefore = this.daysBetween(this.startOfLocalDay(Date.now()), parsed.rangeStart)
      parsed.daysAfter = this.daysBetween(this.startOfLocalDay(Date.now()), parsed.rangeEnd)
    } else {
      parsed.daysBefore = this.normalizeDaySpan(request.daysBefore, 0)
      parsed.daysAfter = this.normalizeDaySpan(request.daysAfter, 7)
      const todayStart = this.startOfLocalDay(Date.now())
      parsed.rangeStart = todayStart - parsed.daysBefore * 24 * 60 * 60 * 1000
      parsed.rangeEnd = todayStart + (parsed.daysAfter + 1) * 24 * 60 * 60 * 1000 - 1
    }

    if (parsed.rangeEnd <= parsed.rangeStart) {
      throw new Error('读取日程结束时间必须晚于开始时间')
    }
    return parsed
  }

  private normalizeTarget(target: string): ScheduleWriteTarget {
    const normalized = (target || '').trim().toLowerCase()
    if (normalized === '' || normalized === ScheduleWriteTarget.CALENDAR) {
      return ScheduleWriteTarget.CALENDAR
    }
    if (normalized === 'alarm') {
      throw new Error('闹钟需要特殊权限，当前不支持创建闹钟')
    }
    throw new Error('target 只能是 calendar')
  }

  private normalizeRequiredText(value: string, errorMessage: string): string {
    const text = (value || '').trim()
    if (text === '') {
      throw new Error(errorMessage)
    }
    return text
  }

  private normalizeOptionalText(value: string | undefined): string {
    if (value === undefined) {
      return ''
    }
    return value.trim()
  }

  private parseTime(value: string, errorMessage: string): number {
    const text = (value || '').trim()
    if (text === '') {
      throw new Error(errorMessage)
    }
    const numericValue = Number(text)
    if (!Number.isNaN(numericValue) && numericValue > 0) {
      return numericValue
    }
    const parsed = new Date(text).getTime()
    if (Number.isNaN(parsed)) {
      throw new Error(errorMessage)
    }
    return parsed
  }

  private resolveEndTime(startTime: number, endTime: string | undefined, allDay: boolean): number {
    const text = (endTime || '').trim()
    if (text !== '') {
      return this.parseTime(text, '结束时间格式不正确')
    }
    const oneDayMs = 24 * 60 * 60 * 1000
    const oneHourMs = 60 * 60 * 1000
    return startTime + (allDay ? oneDayMs : oneHourMs)
  }

  private normalizeReminderMinutes(value: number | undefined): number {
    if (value === undefined || Number.isNaN(value)) {
      return 15
    }
    if (value < 0) {
      return 0
    }
    if (value > 10080) {
      return 10080
    }
    return Math.floor(value)
  }

  private normalizeDaySpan(value: number | undefined, fallback: number): number {
    if (value === undefined || Number.isNaN(value)) {
      return fallback
    }
    if (value < 0) {
      return 0
    }
    if (value > 365) {
      return 365
    }
    return Math.floor(value)
  }

  private normalizeLimit(value: number | undefined): number {
    if (value === undefined || Number.isNaN(value)) {
      return 80
    }
    if (value < 1) {
      return 1
    }
    if (value > 300) {
      return 300
    }
    return Math.floor(value)
  }

  private startOfLocalDay(time: number): number {
    const date = new Date(time)
    date.setHours(0, 0, 0, 0)
    return date.getTime()
  }

  private daysBetween(baseStartOfDay: number, time: number): number {
    const targetStart = this.startOfLocalDay(time)
    return Math.floor((targetStart - baseStartOfDay) / (24 * 60 * 60 * 1000))
  }

  private ensureContext(): common.UIAbilityContext {
    if (this.context === null) {
      throw new Error('日历写入服务尚未初始化')
    }
    return this.context
  }

  private ensureCalendarPermission(): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const context = this.ensureContext()
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
      const permissions: Permissions[] = [
        'ohos.permission.READ_CALENDAR',
        'ohos.permission.WRITE_CALENDAR'
      ]
      atManager.requestPermissionsFromUser(
        context,
        permissions,
        (err: BusinessError, data: PermissionRequestResult) => {
          if (err) {
            reject(new Error('申请日历权限失败: ' + JSON.stringify(err)))
            return
          }
          if (data.authResults.length < permissions.length) {
            reject(new Error('日历权限未完整授权'))
            return
          }
          for (let i = 0; i < data.authResults.length; i++) {
            if (data.authResults[i] !== 0) {
              reject(new Error('用户拒绝了日历权限'))
              return
            }
          }
          resolve()
        }
      )
    })
  }

  private ensureReadCalendarPermission(): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const context = this.ensureContext()
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
      const permissions: Permissions[] = ['ohos.permission.READ_CALENDAR']
      atManager.requestPermissionsFromUser(
        context,
        permissions,
        (err: BusinessError, data: PermissionRequestResult) => {
          if (err) {
            reject(new Error('申请读取日历权限失败: ' + JSON.stringify(err)))
            return
          }
          if (data.authResults.length < permissions.length || data.authResults[0] !== 0) {
            reject(new Error('用户拒绝了读取日历权限'))
            return
          }
          resolve()
        }
      )
    })
  }

  private async addCalendarEvent(request: ParsedScheduleRequest): Promise<number> {
    const manager = calendarManager.getCalendarManager(this.ensureContext())
    let calendar: calendarManager.Calendar
    try {
      calendar = await manager.getCalendar()
    } catch (_error) {
      calendar = await manager.createCalendar({
        name: 'XCube',
        type: calendarManager.CalendarType.LOCAL,
        displayName: 'XCube'
      })
    }

    const event: calendarManager.Event = {
      type: calendarManager.EventType.NORMAL,
      title: request.title,
      startTime: request.startTime,
      endTime: request.endTime,
      isAllDay: request.allDay,
      reminderTime: [request.reminderMinutesBefore]
    }
    if (request.description !== '') {
      event.description = request.description
    }
    if (request.location !== '') {
      event.location = { location: request.location }
    }
    return await calendar.addEvent(event)
  }

  private async readCalendarEvents(request: ParsedReadScheduleRequest): Promise<ReadScheduleEvent[]> {
    const manager = calendarManager.getCalendarManager(this.ensureContext())
    const calendars = await manager.getAllCalendars()
    const result: ReadScheduleEvent[] = []
    const eventFilter = calendarManager.EventFilter.filterByTime(request.rangeStart, request.rangeEnd)
    for (let i = 0; i < calendars.length; i++) {
      const calendar = calendars[i]
      let calendarName = ''
      try {
        const account = calendar.getAccount()
        calendarName = account.displayName !== undefined && account.displayName !== '' ? account.displayName : account.name
      } catch (_error) {
        calendarName = 'Calendar'
      }
      try {
        const events = await calendar.getEvents(eventFilter, [
          'id',
          'title',
          'startTime',
          'endTime',
          'isAllDay',
          'location',
          'description'
        ])
        for (let j = 0; j < events.length; j++) {
          result.push(this.toReadScheduleEvent(events[j], calendarName, request))
        }
      } catch (error) {
        console.warn('CalendarWriteService', `Failed to read calendar events: ${JSON.stringify(error)}`)
      }
    }
    result.sort((a: ReadScheduleEvent, b: ReadScheduleEvent): number => {
      return a.startTime - b.startTime
    })
    return result
  }

  private toReadScheduleEvent(
    event: calendarManager.Event,
    calendarName: string,
    request: ParsedReadScheduleRequest
  ): ReadScheduleEvent {
    const item: ReadScheduleEvent = {
      id: event.id,
      calendarName: calendarName,
      title: event.title !== undefined && event.title.trim() !== '' ? event.title : '无标题',
      startTime: event.instanceStartTime !== undefined ? event.instanceStartTime : event.startTime,
      endTime: event.instanceEndTime !== undefined ? event.instanceEndTime : event.endTime,
      allDay: event.isAllDay === true
    }
    if (request.includeLocation && event.location !== undefined) {
      item.location = event.location.location
    }
    if (request.includeDescription && event.description !== undefined && event.description.trim() !== '') {
      item.description = event.description
    }
    return item
  }

}

export function getCalendarWriteService(): CalendarWriteService {
  return CalendarWriteService.getInstance()
}
