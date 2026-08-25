import { AppStorageKeys } from '../config/AppStorageKeys'
import { getAppUiState, setAppUiStateValue } from '../state/AppUiState'
import { getPreferencesService, PreferenceKeys, PreferencesService } from './PreferencesService'

// 计划步骤的三种状态。模型用的词很杂（done/completed/✓/…），
// 统一由 normalizePlanStepStatus() 收敛到这三个常量。
export const PLAN_STEP_PENDING: string = 'pending'
export const PLAN_STEP_ACTIVE: string = 'in_progress'
export const PLAN_STEP_DONE: string = 'done'

// 计划面板要能一屏读完；超出的步骤会被截断而不是静默丢弃。
export const PLAN_MAX_STEPS: number = 40
export const PLAN_MAX_STEP_TITLE_LENGTH: number = 200

interface PlanStepStorage {
  id?: string
  title?: string
  status?: string
  note?: string
}

interface PlanStorage {
  title?: string
  steps?: PlanStepStorage[]
  updatedAt?: number
  updatedBy?: string
  revision?: number
  activated?: boolean
}

export class PlanStep {
  id: string = ''
  title: string = ''
  status: string = PLAN_STEP_PENDING
  note: string = ''

  constructor(id: string = '', title: string = '', status: string = PLAN_STEP_PENDING, note: string = '') {
    this.id = id
    this.title = title
    this.status = status
    this.note = note
  }
}

export class PlanState {
  title: string = 'Plan'
  steps: PlanStep[] = []
  updatedAt: number = 0
  updatedBy: string = ''
  revision: number = 0
  activated: boolean = false

  constructor(
    title: string = 'Plan',
    steps: PlanStep[] = [],
    updatedAt: number = 0,
    updatedBy: string = '',
    revision: number = 0,
    activated: boolean = false
  ) {
    this.title = title
    this.steps = steps
    this.updatedAt = updatedAt
    this.updatedBy = updatedBy
    this.revision = revision
    this.activated = activated
  }
}

export class PlanMutationResult {
  ok: boolean = true
  message: string = ''
  plan: PlanState = new PlanState()

  constructor(ok: boolean, message: string, plan: PlanState) {
    this.ok = ok
    this.message = message
    this.plan = plan
  }
}

// 模型写状态时用词不固定，这里把常见同义词收敛成三个状态；无法识别的一律当 pending，
// 宁可显示成"未做"也不要凭猜测把一步标成已完成。
export function normalizePlanStepStatus(status: string): string {
  const normalized = status.trim().toLowerCase().replace(/[\s\-]+/g, '_')
  if (normalized === 'done' || normalized === 'complete' || normalized === 'completed' ||
    normalized === 'finish' || normalized === 'finished' || normalized === 'checked' ||
    normalized === 'tick' || normalized === 'ticked' || normalized === 'x' || normalized === '✓' ||
    normalized === 'closed') {
    return PLAN_STEP_DONE
  }
  if (normalized === 'in_progress' || normalized === 'inprogress' || normalized === 'active' ||
    normalized === 'current' || normalized === 'doing' || normalized === 'working' ||
    normalized === 'started' || normalized === 'running' || normalized === 'wip' ||
    normalized === 'ongoing') {
    return PLAN_STEP_ACTIVE
  }
  return PLAN_STEP_PENDING
}

// 解析模型对某一步的引用：1 基序号、步骤 id，或标题（完全匹配 → 前缀 → 子串）。
// 找不到或有歧义都返回 -1：勾错一步比报告失败更糟，宁可让模型换个更明确的引用重试。
export function resolvePlanStepIndex(steps: PlanStep[], reference: string): number {
  const normalized = reference.trim()
  if (normalized === '' || steps.length === 0) {
    return -1
  }

  if (/^[0-9]+$/.test(normalized)) {
    const ordinal = Number.parseInt(normalized, 10)
    return ordinal >= 1 && ordinal <= steps.length ? ordinal - 1 : -1
  }

  const lowered = normalized.toLowerCase()
  for (let i = 0; i < steps.length; i++) {
    if (steps[i].id.toLowerCase() === lowered) {
      return i
    }
  }

  const exact = collectMatches(steps, (title: string): boolean => title === lowered)
  if (exact.length === 1) {
    return exact[0]
  }
  if (exact.length > 1) {
    return -1
  }

  const prefix = collectMatches(steps, (title: string): boolean => title.startsWith(lowered))
  if (prefix.length === 1) {
    return prefix[0]
  }
  if (prefix.length > 1) {
    return -1
  }

  const contains = collectMatches(steps, (title: string): boolean => title.includes(lowered))
  return contains.length === 1 ? contains[0] : -1
}

function collectMatches(steps: PlanStep[], predicate: (title: string) => boolean): number[] {
  const matched: number[] = []
  for (let i = 0; i < steps.length; i++) {
    if (predicate(steps[i].title.trim().toLowerCase())) {
      matched.push(i)
    }
  }
  return matched
}

// 步骤 id 只需在一份计划内稳定且唯一：勾选是按 id 定位的，重排后仍要指向同一步。
export function buildPlanSteps(titles: string[], statuses: string[] = []): PlanStep[] {
  const steps: PlanStep[] = []
  for (let i = 0; i < titles.length && steps.length < PLAN_MAX_STEPS; i++) {
    const title = titles[i].trim().replace(/\s+/g, ' ')
    if (title === '') {
      continue
    }
    const clipped = title.length > PLAN_MAX_STEP_TITLE_LENGTH
      ? title.substring(0, PLAN_MAX_STEP_TITLE_LENGTH) : title
    const status = i < statuses.length ? normalizePlanStepStatus(statuses[i]) : PLAN_STEP_PENDING
    steps.push(new PlanStep(`s${steps.length + 1}`, clipped, status, ''))
  }
  return steps
}

export function countPlanStepsByStatus(steps: PlanStep[], status: string): number {
  let count = 0
  for (let i = 0; i < steps.length; i++) {
    if (steps[i].status === status) {
      count += 1
    }
  }
  return count
}

export class PlanService {
  private static instance: PlanService | null = null
  private preferencesService: PreferencesService = getPreferencesService()
  private cachedPlans: Map<string, PlanState> = new Map()

  static getInstance(): PlanService {
    if (PlanService.instance === null) {
      PlanService.instance = new PlanService()
    }
    return PlanService.instance
  }

  async loadPlan(planId: string = ''): Promise<PlanState> {
    const resolvedPlanId = this.resolvePlanId(planId)
    const cachedPlan = this.cachedPlans.get(resolvedPlanId)
    const raw = await this.preferencesService.getString(this.getPlanPreferenceKey(resolvedPlanId), '')
    if (raw.trim() === '') {
      if (cachedPlan !== undefined) {
        return this.clonePlan(cachedPlan)
      }
      return new PlanState('Plan', [], 0, '', 0, false)
    }
    try {
      const parsed = JSON.parse(raw) as PlanStorage
      const plan = new PlanState(
        this.resolveString(parsed.title, 'Plan'),
        this.parseSteps(parsed.steps),
        this.resolveNumber(parsed.updatedAt),
        this.resolveString(parsed.updatedBy),
        this.resolveNumber(parsed.revision),
        this.resolveBoolean(parsed.activated)
      )
      // 与 CanvasDocumentService 相同的取舍：偏好项写入偶有延迟，
      // 内存里更新的版本优先，避免刚勾上的步骤被旧快照覆盖回去。
      if (cachedPlan !== undefined && (cachedPlan.revision > plan.revision ||
        (cachedPlan.revision === plan.revision && cachedPlan.updatedAt > plan.updatedAt))) {
        return this.clonePlan(cachedPlan)
      }
      this.cachedPlans.set(resolvedPlanId, this.clonePlan(plan))
      return plan
    } catch (error) {
      console.error('PlanService', `Failed to parse plan: ${JSON.stringify(error)}`)
      if (cachedPlan !== undefined) {
        return this.clonePlan(cachedPlan)
      }
      return new PlanState('Plan', [], 0, '', 0, false)
    }
  }

  async activatePlan(updatedBy: string = 'assistant', planId: string = ''): Promise<PlanState> {
    const resolvedPlanId = this.resolvePlanId(planId)
    const current = await this.loadPlan(resolvedPlanId)
    if (current.activated) {
      return current
    }
    const next = new PlanState(current.title, current.steps, Date.now(), updatedBy, current.revision, true)
    await this.persist(next, resolvedPlanId)
    return next
  }

  async setSteps(
    titles: string[],
    statuses: string[] = [],
    title: string = '',
    updatedBy: string = 'assistant',
    planId: string = ''
  ): Promise<PlanState> {
    const resolvedPlanId = this.resolvePlanId(planId)
    const current = await this.loadPlan(resolvedPlanId)
    const nextTitle = title.trim() !== '' ? title.trim() : current.title
    const next = new PlanState(
      nextTitle,
      buildPlanSteps(titles, statuses),
      Date.now(),
      updatedBy,
      current.revision + 1,
      true
    )
    await this.persist(next, resolvedPlanId)
    return next
  }

  async updateStepStatus(
    reference: string,
    status: string,
    updatedBy: string = 'assistant',
    planId: string = ''
  ): Promise<PlanMutationResult> {
    const resolvedPlanId = this.resolvePlanId(planId)
    const current = await this.loadPlan(resolvedPlanId)
    if (current.steps.length === 0) {
      return new PlanMutationResult(false, '当前没有计划步骤，请先用 operation="set" 写入计划', current)
    }
    const index = resolvePlanStepIndex(current.steps, reference)
    if (index < 0) {
      return new PlanMutationResult(false,
        `未能唯一定位步骤 "${reference}"，请改用步骤序号（1-${current.steps.length}）`, current)
    }
    const nextSteps: PlanStep[] = []
    for (let i = 0; i < current.steps.length; i++) {
      const step = current.steps[i]
      nextSteps.push(i === index
        ? new PlanStep(step.id, step.title, normalizePlanStepStatus(status), step.note)
        : new PlanStep(step.id, step.title, step.status, step.note))
    }
    const next = new PlanState(current.title, nextSteps, Date.now(), updatedBy, current.revision + 1, true)
    await this.persist(next, resolvedPlanId)
    return new PlanMutationResult(true, `已更新步骤 ${index + 1}：${nextSteps[index].title}`, next)
  }

  async clearPlan(updatedBy: string = 'assistant', planId: string = ''): Promise<PlanState> {
    const resolvedPlanId = this.resolvePlanId(planId)
    const current = await this.loadPlan(resolvedPlanId)
    const next = new PlanState('Plan', [], Date.now(), updatedBy, current.revision + 1, false)
    await this.persist(next, resolvedPlanId)
    return next
  }

  private async persist(plan: PlanState, planId: string): Promise<void> {
    this.cachedPlans.set(planId, this.clonePlan(plan))
    const serialized = JSON.stringify(plan)
    const preferenceKey = this.getPlanPreferenceKey(planId)
    await this.preferencesService.setString(preferenceKey, serialized)
    const stored = await this.preferencesService.getString(preferenceKey, '')
    if (stored !== serialized) {
      console.warn('PlanService', 'Plan preference write did not verify; using in-memory cache')
    }
    const currentRefreshAt = getAppUiState().planRefreshAt
    const now = Date.now()
    setAppUiStateValue(AppStorageKeys.PLAN_REFRESH_AT, now > currentRefreshAt ? now : currentRefreshAt + 1)
  }

  private parseSteps(steps: PlanStepStorage[] | undefined): PlanStep[] {
    if (steps === undefined || steps === null) {
      return []
    }
    const parsed: PlanStep[] = []
    for (let i = 0; i < steps.length && parsed.length < PLAN_MAX_STEPS; i++) {
      const step = steps[i]
      const title = this.resolveString(step.title).trim()
      if (title === '') {
        continue
      }
      const id = this.resolveString(step.id).trim()
      parsed.push(new PlanStep(
        id !== '' ? id : `s${parsed.length + 1}`,
        title,
        normalizePlanStepStatus(this.resolveString(step.status)),
        this.resolveString(step.note)
      ))
    }
    return parsed
  }

  private resolvePlanId(planId: string): string {
    const explicitId = planId.trim()
    if (explicitId !== '') {
      return explicitId
    }
    const activeSessionId = getAppUiState().activeChatSessionId.trim()
    return activeSessionId !== '' ? activeSessionId : '__unbound__'
  }

  private getPlanPreferenceKey(planId: string): string {
    return `${PreferenceKeys.PLAN_JSON}_${this.normalizeKeySuffix(planId)}`
  }

  private normalizeKeySuffix(value: string): string {
    return value.replace(/[^a-zA-Z0-9_-]/g, '_')
  }

  private clonePlan(plan: PlanState): PlanState {
    const steps: PlanStep[] = []
    for (let i = 0; i < plan.steps.length; i++) {
      const step = plan.steps[i]
      steps.push(new PlanStep(step.id, step.title, step.status, step.note))
    }
    return new PlanState(plan.title, steps, plan.updatedAt, plan.updatedBy, plan.revision, plan.activated)
  }

  private resolveString(value: string | undefined, fallback: string = ''): string {
    if (value === undefined || value === null) {
      return fallback
    }
    return `${value}`
  }

  private resolveNumber(value: number | undefined, fallback: number = 0): number {
    if (value === undefined || value === null || !Number.isFinite(value)) {
      return fallback
    }
    return value
  }

  private resolveBoolean(value: boolean | undefined, fallback: boolean = false): boolean {
    if (value === undefined || value === null) {
      return fallback
    }
    return value
  }
}

export function getPlanService(): PlanService {
  return PlanService.getInstance()
}
