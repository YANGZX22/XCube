import {
  ToolConfig,
  ToolDefinition,
  ToolFunction,
  ToolParameters,
  ToolPermissionLevel,
  ToolSourceType
} from '../models/ChatModels'
import { ToolExecutor } from '../services/ToolRegistry'
import {
  getPlanService,
  PLAN_MAX_STEPS,
  PLAN_STEP_ACTIVE,
  PLAN_STEP_DONE,
  PLAN_STEP_PENDING,
  PlanMutationResult,
  PlanState,
  PlanStep,
  countPlanStepsByStatus
} from '../services/PlanService'

export const PLAN_MODE_TOOL_ID: string = 'plan_mode'

// 模型给步骤的写法很多：纯字符串、{title,status}、{step,done}…… 全部接受，
// 拒绝一种写法只会让模型重试而不是写对。
interface PlanStepArg {
  title?: string
  step?: string
  name?: string
  text?: string
  content?: string
  status?: string
  state?: string
  done?: boolean
}

interface PlanToolArgs {
  operation?: string
  action?: string
  title?: string
  steps?: (string | PlanStepArg)[]
  plan?: (string | PlanStepArg)[]
  items?: (string | PlanStepArg)[]
  step?: string | number
  step_refs?: string[]
  index?: string | number
  status?: string
}

class PlanStepOutput {
  index: number = 0
  title: string = ''
  status: string = PLAN_STEP_PENDING

  constructor(index: number, step: PlanStep) {
    this.index = index
    this.title = step.title
    this.status = step.status
  }
}

class PlanToolOutput {
  ok: boolean = true
  operation: string = ''
  message: string = ''
  title: string = 'Plan'
  totalSteps: number = 0
  doneSteps: number = 0
  steps: PlanStepOutput[] = []

  constructor(ok: boolean, operation: string, message: string, plan: PlanState) {
    this.ok = ok
    this.operation = operation
    this.message = message
    this.title = plan.title
    this.totalSteps = plan.steps.length
    this.doneSteps = countPlanStepsByStatus(plan.steps, PLAN_STEP_DONE)
    const steps: PlanStepOutput[] = []
    for (let i = 0; i < plan.steps.length; i++) {
      steps.push(new PlanStepOutput(i + 1, plan.steps[i]))
    }
    this.steps = steps
  }
}

class PlanToolErrorOutput {
  ok: boolean = false
  error: string = ''

  constructor(error: string) {
    this.error = error
  }
}

export class PlanModeExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    try {
      const params = JSON.parse(args) as PlanToolArgs
      const operation = this.normalizeOperation(params)
      const service = getPlanService()

      if (operation === 'read') {
        const plan = await service.activatePlan('assistant')
        return JSON.stringify(new PlanToolOutput(true, operation, '已读取当前计划', plan))
      }

      if (operation === 'set') {
        const titles = this.resolveStepTitles(params)
        if (titles.length === 0) {
          const current = await service.loadPlan()
          return JSON.stringify(new PlanToolOutput(false, operation,
            'steps 不能为空；请给出至少一个步骤', current))
        }
        const plan = await service.setSteps(titles, this.resolveStepStatuses(params),
          this.resolveString(params.title), 'assistant')
        return JSON.stringify(new PlanToolOutput(true, operation,
          `已写入 ${plan.steps.length} 个步骤`, plan))
      }

      if (operation === 'clear') {
        const plan = await service.clearPlan('assistant')
        return JSON.stringify(new PlanToolOutput(true, operation, '已清空计划', plan))
      }

      const reference = this.resolveStepReference(params)
      const references: string[] = []
      if (params.step_refs !== undefined) {
        if (params.step !== undefined || params.index !== undefined) {
          return JSON.stringify(new PlanToolErrorOutput('step 与 step_refs 只能提供其中一个'))
        }
        if (!Array.isArray(params.step_refs) || params.step_refs.length === 0 ||
          params.step_refs.length > PLAN_MAX_STEPS) {
          return JSON.stringify(new PlanToolErrorOutput(`step_refs 必须包含 1-${PLAN_MAX_STEPS} 个步骤引用`))
        }
        for (let i = 0; i < params.step_refs.length; i++) {
          if (typeof params.step_refs[i] !== 'string' || params.step_refs[i].trim() === '') {
            return JSON.stringify(new PlanToolErrorOutput('step_refs 中的每项必须是非空字符串'))
          }
          references.push(params.step_refs[i])
        }
      } else if (reference !== '') {
        references.push(reference)
      }
      if (references.length === 0) {
        const current = await service.loadPlan()
        return JSON.stringify(new PlanToolOutput(false, operation,
          '请用 step 或 step_refs 指明要更新的步骤（序号或标题）', current))
      }
      const status = operation === 'check' ? PLAN_STEP_DONE
        : (operation === 'start' ? PLAN_STEP_ACTIVE : PLAN_STEP_PENDING)
      const result: PlanMutationResult = await service.updateStepsStatus(references, status, 'assistant')
      return JSON.stringify(new PlanToolOutput(result.ok, operation, result.message, result.plan))
    } catch (error) {
      return JSON.stringify(new PlanToolErrorOutput(`计划操作失败: ${this.stringifyError(error)}`))
    }
  }

  // 没写 operation 时按载荷推断：带 steps 就是建计划，带 step 就是勾选，都没有就是读取。
  private normalizeOperation(params: PlanToolArgs): string {
    const raw = this.resolveString(params.operation) !== ''
      ? this.resolveString(params.operation) : this.resolveString(params.action)
    const normalized = raw.trim().toLowerCase().replace(/[\s\-]+/g, '_')
    if (normalized === '') {
      if (this.resolveStepTitles(params).length > 0) {
        return 'set'
      }
      return this.resolveStepReference(params) !== '' || params.step_refs !== undefined ? 'check' : 'read'
    }
    if (normalized === 'write' || normalized === 'create' || normalized === 'update' ||
      normalized === 'replace' || normalized === 'plan' || normalized === 'rewrite' ||
      normalized === 'overwrite' || normalized === 'add') {
      return 'set'
    }
    if (normalized === 'tick' || normalized === 'complete' || normalized === 'completed' ||
      normalized === 'done' || normalized === 'finish' || normalized === 'check_off' ||
      normalized === 'checkoff' || normalized === 'mark_done') {
      return 'check'
    }
    if (normalized === 'begin' || normalized === 'in_progress' || normalized === 'active' ||
      normalized === 'working' || normalized === 'mark_active') {
      return 'start'
    }
    if (normalized === 'reset' || normalized === 'undo' || normalized === 'reopen') {
      return 'uncheck'
    }
    if (normalized === 'delete' || normalized === 'remove' || normalized === 'reset_plan') {
      return 'clear'
    }
    return normalized
  }

  private resolveStepList(params: PlanToolArgs): (string | PlanStepArg)[] {
    if (params.steps !== undefined && params.steps !== null) {
      return params.steps
    }
    if (params.plan !== undefined && params.plan !== null) {
      return params.plan
    }
    if (params.items !== undefined && params.items !== null) {
      return params.items
    }
    return []
  }

  private resolveStepTitles(params: PlanToolArgs): string[] {
    const list = this.resolveStepList(params)
    const titles: string[] = []
    for (let i = 0; i < list.length; i++) {
      const title = this.resolveStepTitle(list[i])
      if (title !== '') {
        titles.push(title)
      }
    }
    return titles
  }

  private resolveStepStatuses(params: PlanToolArgs): string[] {
    const list = this.resolveStepList(params)
    const statuses: string[] = []
    for (let i = 0; i < list.length; i++) {
      const entry = list[i]
      if (this.resolveStepTitle(entry) === '') {
        continue
      }
      if (typeof entry === 'string') {
        statuses.push(PLAN_STEP_PENDING)
        continue
      }
      const step = entry as PlanStepArg
      if (step.done === true) {
        statuses.push(PLAN_STEP_DONE)
        continue
      }
      const status = this.resolveString(step.status) !== ''
        ? this.resolveString(step.status) : this.resolveString(step.state)
      statuses.push(status !== '' ? status : PLAN_STEP_PENDING)
    }
    return statuses
  }

  private resolveStepTitle(entry: string | PlanStepArg): string {
    if (typeof entry === 'string') {
      return entry.trim()
    }
    if (entry === undefined || entry === null) {
      return ''
    }
    const step = entry as PlanStepArg
    const candidates: string[] = [
      this.resolveString(step.title),
      this.resolveString(step.step),
      this.resolveString(step.name),
      this.resolveString(step.text),
      this.resolveString(step.content)
    ]
    for (let i = 0; i < candidates.length; i++) {
      if (candidates[i].trim() !== '') {
        return candidates[i].trim()
      }
    }
    return ''
  }

  private resolveStepReference(params: PlanToolArgs): string {
    if (typeof params.step === 'number') {
      return `${params.step}`
    }
    if (typeof params.step === 'string' && params.step.trim() !== '') {
      return params.step.trim()
    }
    if (typeof params.index === 'number') {
      return `${params.index}`
    }
    if (typeof params.index === 'string' && params.index.trim() !== '') {
      return params.index.trim()
    }
    return ''
  }

  private resolveString(value: string | undefined): string {
    if (value === undefined || value === null) {
      return ''
    }
    return `${value}`
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message
    }
    return JSON.stringify(error)
  }
}

export function createPlanModeToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "operation": {
        "type": "string",
        "enum": ["set", "check", "start", "uncheck", "read", "clear"],
        "description": "set=写入或重写整个计划；check=把某一步标记为已完成；start=把某一步标记为进行中；uncheck=撤销某一步的完成标记；read=读取当前计划；clear=清空计划。省略时按载荷推断。在有实质进度时更新，可一次批量更新多个已完成步骤。"
      },
      "title": {
        "type": "string",
        "description": "可选，计划的标题，一句话概括整体目标。仅在 operation=set 时使用。"
      },
      "steps": {
        "type": "array",
        "items": { "type": "string" },
        "description": "operation=set 时必填，最多 ${PLAN_MAX_STEPS} 步。按执行顺序给出步骤，每步一句祈使句，描述一个可验证的产出（例如'迁移 users 表并跑通回归测试'），不要写成'思考一下'这类无法判断完成的条目。set 会替换整个计划；仅在范围变化时重写，普通进度使用 check 更新。步骤应按交付物分组，不为思考、读一次结果或修改一句话拆出步骤。"
      },
      "step_refs": {
        "type": "array",
        "items": { "type": "string" },
        "minItems": 1,
        "maxItems": ${PLAN_MAX_STEPS},
        "description": "check/start/uncheck 时可批量更新的步骤序号或标题，例如第 1、2 步。任一引用无效则整批不修改；与 step 二选一。"
      },
      "step": {
        "type": "string",
        "description": "check/start/uncheck 时用 step 或 step_refs 指定目标。用步骤序号（如 \\"2\\"）指明目标步骤最可靠；也接受步骤标题原文。标题匹配不唯一时会返回失败而不是猜测。批量更新时改用 step_refs。"
      }
    },
    "additionalProperties": false
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)

  const func = new ToolFunction(
    PLAN_MODE_TOOL_ID,
    '为确实需要多步工作的任务维护简短计划；简单问答、翻译或一两步可完成的任务直接处理。' +
      '先 set 列出按交付物分组的步骤，再执行工作。在有实质进度时用 check 更新完成状态，' +
      '多个已完成步骤可通过 step_refs 一次更新；start 只在有助于展示长步骤进度时使用。' +
      '不要为每个细小动作单独更新，不重复读写未变化的计划。只有产出真实存在的步骤才能标记完成，' +
      '失败或跳过的步骤保持未完成。任务范围未改变时不要重建计划。',
    parameters
  )

  return new ToolDefinition(func)
}

export function createPlanModeToolConfig(): ToolConfig {
  return new ToolConfig(
    PLAN_MODE_TOOL_ID,
    '计划模式',
    '模型可以列出多步任务的计划，并在完成时逐条勾选',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    PLAN_MODE_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}
