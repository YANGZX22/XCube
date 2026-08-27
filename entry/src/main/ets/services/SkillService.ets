import { getPreferencesService, PreferenceKeys, PreferencesService } from './PreferencesService'

@ObservedV2
export class SkillConfig {
  @Trace id: string = ''
  @Trace name: string = ''
  @Trace description: string = ''
  @Trace content: string = ''
  @Trace enabled: boolean = true
  @Trace createdAt: number = 0
  @Trace updatedAt: number = 0

  constructor(
    id: string = '',
    name: string = '',
    description: string = '',
    content: string = '',
    enabled: boolean = true,
    createdAt: number = 0,
    updatedAt: number = 0
  ) {
    this.id = id
    this.name = name
    this.description = description
    this.content = content
    this.enabled = enabled
    this.createdAt = createdAt
    this.updatedAt = updatedAt
  }
}

interface UseSkillArgs {
  skill_id?: string
  skillId?: string
  id?: string
  name?: string
  path?: string
  max_chars?: number | string
  maxChars?: number | string
}

class SkillConfigJson {
  id: string = ''
  name: string = ''
  description: string = ''
  content: string = ''
  enabled: boolean = true
  createdAt: number = 0
  updatedAt: number = 0
}

class SkillSummary {
  id: string = ''
  name: string = ''
  description: string = ''
  path: string = ''

  constructor(skill: SkillConfig) {
    this.id = skill.id
    this.name = skill.name
    this.description = skill.description
    this.path = `${skill.id}/SKILL.md`
  }
}

class SkillReadOutput {
  ok: boolean = true
  id: string = ''
  name: string = ''
  description: string = ''
  path: string = ''
  content: string = ''
  truncated: boolean = false

  constructor(skill: SkillConfig, content: string, truncated: boolean) {
    this.id = skill.id
    this.name = skill.name
    this.description = skill.description
    this.path = `${skill.id}/SKILL.md`
    this.content = content
    this.truncated = truncated
  }
}

class SkillListOutput {
  ok: boolean = true
  message: string = ''
  skills: SkillSummary[] = []

  constructor(skills: SkillConfig[]) {
    this.message = skills.length > 0
      ? '传入 skill_id、name 或 path 读取某个 skill 的 SKILL.md 正文。'
      : '当前没有已启用的 skill。'
    for (let i = 0; i < skills.length; i++) {
      this.skills.push(new SkillSummary(skills[i]))
    }
  }
}

class SkillErrorOutput {
  ok: boolean = false
  error: string = ''

  constructor(error: string) {
    this.error = error
  }
}

export class SkillService {
  private static instance: SkillService | null = null
  private preferencesService: PreferencesService
  private readonly defaultAppHelpContent: string = `# 应用使用帮助

本技能用于回答 APP 的使用、配置和功能说明问题。

## 使用方式

- 当用户询问本应用怎么用、功能入口在哪里、某项配置是什么意思、导入导出是否覆盖某类数据、子智能体/工具/技能/记忆/分享/统计/WebDAV/OCR/文档解析等能力如何使用时，先读取本 Skill 再回答。
- APP 支持多模型聊天、助手管理、子智能体、工具调用、联网搜索、MCP Server、Python/数学绘图、Canvas 文档、日程读取/写入、PDF/图片文字提取、主题/字体/输入方式设置、数据导入导出、WebDAV 同步、会话分享和用量统计等能力；具体入口以应用当前界面为准。
- 回答时优先给出具体入口和操作步骤，必要时说明前提条件、限制和注意事项。
- 如果帮助资料没有明确说明，不要编造入口或能力边界；请直接说明“当前帮助中没有明确说明”。
- 如果用户的问题不够具体，而继续回答可能误导，使用 ask_user 工具确认 1 个最关键的问题。

## 子智能体

- 入口：在对话输入区打开工具选择，启用“子智能体”。启用后由主模型自主判断是否需要派出，不会对每个问题强制使用。
- 适用场景：多主题调研、多来源对比、多份材料分别处理等能拆成独立子任务的请求。简单任务或强依赖先后顺序的任务通常不使用。
- 执行方式：主模型一次最多派出 3 个子智能体并行执行。每个子智能体使用独立上下文，看不到主对话历史，且不能继续递归派生子智能体；完成后会把结果交给主模型汇总。
- 工具与检索次数：子智能体继承当前对话已开启的工具。“工具中心 → 每轮检索次数”可分别为联网搜索与知识库查询选择不设限制或 1～10 次；主模型和每个子智能体分别独立计数，不会相互挤占。
- 实时预览：子智能体工具卡片提供“实时预览”入口，可查看每个子智能体的输出、工具调用和执行状态。子智能体发起的 ask_user 提问会以弹窗逐个显示，后到的问题优先回答；主对话仅保留可展开的结果栏。
- 前提：所选模型需完整支持工具调用。`

  private constructor() {
    this.preferencesService = getPreferencesService()
  }

  static getInstance(): SkillService {
    if (SkillService.instance === null) {
      SkillService.instance = new SkillService()
    }
    return SkillService.instance
  }

  async isToolEnabled(): Promise<boolean> {
    return await this.preferencesService.getBoolean(PreferenceKeys.SKILL_TOOL_ENABLED, false)
  }

  async setToolEnabled(enabled: boolean): Promise<void> {
    await this.preferencesService.setBoolean(PreferenceKeys.SKILL_TOOL_ENABLED, enabled)
  }

  async loadSkills(): Promise<SkillConfig[]> {
    const raw = await this.preferencesService.getString(PreferenceKeys.SKILL_CONFIGS_JSON, '[]')
    if (raw.trim() === '') {
      return [this.createDefaultAppHelpSkill()]
    }
    try {
      const parsed = JSON.parse(raw) as Array<Record<string, Object>>
      const skills: SkillConfig[] = []
      for (let i = 0; i < parsed.length; i++) {
        const item = parsed[i]
        const id = this.normalizeSkillId(this.readString(item, 'id'))
        const name = this.readString(item, 'name')
        if (id === '' || name.trim() === '') {
          continue
        }
        skills.push(new SkillConfig(
          id,
          name,
          this.readString(item, 'description'),
          this.readString(item, 'content'),
          this.readBoolean(item, 'enabled', true),
          this.readNumber(item, 'createdAt', Date.now()),
          this.readNumber(item, 'updatedAt', Date.now())
        ))
      }
      if (skills.length === 0) {
        return [this.createDefaultAppHelpSkill()]
      }
      return skills
    } catch (error) {
      console.error('SkillService', `Failed to parse skills: ${JSON.stringify(error)}`)
      return [this.createDefaultAppHelpSkill()]
    }
  }

  async saveSkills(skills: SkillConfig[]): Promise<void> {
    const serialized: SkillConfigJson[] = []
    for (let i = 0; i < skills.length; i++) {
      const skill = skills[i]
      const id = this.normalizeSkillId(skill.id)
      const name = skill.name.trim()
      if (id === '' || name === '') {
        continue
      }
      const item = new SkillConfigJson()
      item.id = id
      item.name = name
      item.description = skill.description.trim()
      item.content = skill.content
      item.enabled = skill.enabled
      item.createdAt = skill.createdAt > 0 ? skill.createdAt : Date.now()
      item.updatedAt = skill.updatedAt > 0 ? skill.updatedAt : Date.now()
      serialized.push(item)
    }
    await this.preferencesService.setString(PreferenceKeys.SKILL_CONFIGS_JSON, JSON.stringify(serialized))
  }

  async readForTool(args: string): Promise<string> {
    try {
      const params = this.parseArgs(args)
      const skills = await this.getEnabledSkills()
      const target = this.resolveTarget(params)
      if (target === '') {
        return JSON.stringify(new SkillListOutput(skills))
      }
      const skill = this.findSkill(skills, target)
      if (skill === null) {
        return JSON.stringify(new SkillErrorOutput(`未找到已启用的 skill: ${target}`))
      }
      const maxChars = this.resolveNumber(params.maxChars, this.resolveNumber(params.max_chars, 16000))
      const content = skill.content
      const clipped = maxChars > 0 && content.length > maxChars ? content.substring(0, maxChars) : content
      return JSON.stringify(new SkillReadOutput(skill, clipped, clipped.length < content.length))
    } catch (error) {
      return JSON.stringify(new SkillErrorOutput(`读取 skill 失败: ${this.stringifyError(error)}`))
    }
  }

  async getEnabledSkills(): Promise<SkillConfig[]> {
    const skills = await this.loadSkills()
    const enabled: SkillConfig[] = []
    for (let i = 0; i < skills.length; i++) {
      if (skills[i].enabled) {
        enabled.push(skills[i])
      }
    }
    return enabled
  }

  buildNewSkillId(name: string): string {
    const normalizedName = this.normalizeSkillId(name)
    const base = normalizedName !== '' ? normalizedName : 'skill'
    return `${base}_${Date.now()}`
  }

  private createDefaultAppHelpSkill(): SkillConfig {
    const now = Date.now()
    return new SkillConfig(
      'app_help',
      'app-help',
      '基于应用内帮助中心回答 XCube 的使用、配置、子智能体和其他功能说明问题',
      this.defaultAppHelpContent,
      true,
      now,
      now
    )
  }

  private parseArgs(args: string): UseSkillArgs {
    if (args.trim() === '') {
      return {}
    }
    return JSON.parse(args) as UseSkillArgs
  }

  private resolveTarget(params: UseSkillArgs): string {
    if (params.skill_id !== undefined) {
      return `${params.skill_id}`.trim()
    }
    if (params.skillId !== undefined) {
      return `${params.skillId}`.trim()
    }
    if (params.id !== undefined) {
      return `${params.id}`.trim()
    }
    if (params.path !== undefined) {
      return `${params.path}`.trim()
    }
    if (params.name !== undefined) {
      return `${params.name}`.trim()
    }
    return ''
  }

  private findSkill(skills: SkillConfig[], target: string): SkillConfig | null {
    const normalizedTarget = target.trim().toLowerCase()
    const pathTarget = normalizedTarget.endsWith('/skill.md')
      ? normalizedTarget.substring(0, normalizedTarget.length - '/skill.md'.length)
      : normalizedTarget
    for (let i = 0; i < skills.length; i++) {
      if (skills[i].id.toLowerCase() === pathTarget || skills[i].name.toLowerCase() === normalizedTarget) {
        return skills[i]
      }
    }
    return null
  }

  private normalizeSkillId(value: string): string {
    return value.trim().toLowerCase().replace(/[^a-z0-9_\-]+/g, '_').replace(/^_+|_+$/g, '')
  }

  private resolveNumber(value: number | string | undefined, fallback: number): number {
    if (value === undefined || value === null) {
      return fallback
    }
    if (typeof value === 'number') {
      return Number.isFinite(value) ? value : fallback
    }
    const parsed = Number.parseInt(value, 10)
    return Number.isNaN(parsed) ? fallback : parsed
  }

  private readString(item: Record<string, Object>, key: string, fallback: string = ''): string {
    const value = item[key]
    if (value === undefined || value === null) {
      return fallback
    }
    return `${value}`
  }

  private readBoolean(item: Record<string, Object>, key: string, fallback: boolean): boolean {
    const value = item[key]
    return typeof value === 'boolean' ? value : fallback
  }

  private readNumber(item: Record<string, Object>, key: string, fallback: number): number {
    const value = item[key]
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message
    }
    return JSON.stringify(error)
  }
}

export function getSkillService(): SkillService {
  return SkillService.getInstance()
}
