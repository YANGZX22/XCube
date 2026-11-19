import { Context } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { checkSkillPath, isSkillMarkdown, normalizeSkillBundle, packSkill, readPackedSkillFile, readStoredSkillMetadata,
  SKILL_ENTRY, SkillFile, skillFileText, skillTextFile, unpackSkill } from '../utils/SkillPackage'
import { SkillPackageStorage } from './SkillPackageStorage'
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
  bundleKey: string = ''
  manualOnly: boolean = false
  paths: string[] = [SKILL_ENTRY]

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
  offset?: number
  max_chars?: number | string
  maxChars?: number | string
}

interface SkillRecord {
  id: string
  name: string
  description: string
  content: string
  enabled: boolean
  createdAt: number
  updatedAt: number
  bundleKey?: string
  paths?: string[]
  manualOnly?: boolean
  archive?: string
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

  files?: string[]
  encoding: string
  offset: number
  next_offset?: number

  constructor(skill: SkillConfig, path: string, content: string, encoding: string, offset: number, end: number) {
    this.id = skill.id
    this.name = skill.name
    this.description = skill.description
    this.path = skill.id + '/' + path
    this.offset = offset
    this.encoding = encoding
    this.content = content.slice(offset, end)
    this.truncated = end < content.length
    if (this.truncated) this.next_offset = end
    if (path === SKILL_ENTRY) this.files = skill.paths
  }
}

class SkillListOutput {
  ok: boolean = true
  message: string = ''
  skills: SkillSummary[] = []

  constructor(skills: SkillConfig[]) {
    this.message = skills.length > 0
      ? '传入 skill_id 读取 SKILL.md 和文件清单，再用同一 skill_id 和相对 path 读取所需文件。'
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
  private storage: SkillPackageStorage | null = null
  private pending: Promise<void> = Promise.resolve()
  private readonly defaultAppHelpContent: string = `# 应用使用帮助

本技能用于回答 APP 的使用、配置和功能说明问题。

## 使用方式

- 当用户询问本应用怎么用、功能入口在哪里、某项配置是什么意思、导入导出是否覆盖某类数据、子智能体/工具/技能/记忆/分享/统计/WebDAV/OCR/文档解析等能力如何使用时，先读取本 Skill 再回答。
- APP 支持多模型聊天、助手管理、子智能体、工具调用、联网搜索、MCP Server、Python/数学绘图、Canvas 文档、日程读取/写入、PDF/图片文字提取、主题/字体/输入方式设置、数据导入导出、WebDAV 同步、会话分享和用量统计等能力；具体入口以应用当前界面为准。
- 回答时优先给出具体入口和操作步骤，必要时说明前提条件、限制和注意事项。
- 如果帮助资料没有明确说明，不要编造入口或能力边界；请直接说明“当前帮助中没有明确说明”。
- 如果用户的问题不够具体，而继续回答可能误导，使用 ask_user 工具确认 1 个最关键的问题。

## Skill

在设置的工具中心打开 Skill。可新增技能，也可导入 SKILL.md、ZIP、.skill 包或包含 SKILL.md 的文件夹。点预览后可切换 Markdown 文档。启用后，模型可按相对路径读取技能里引用的文件。

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

  initialize(context: Context): void {
    this.storage = new SkillPackageStorage(context.filesDir + '/skill_packages')
  }

  private store(): SkillPackageStorage {
    if (!this.storage) throw new Error('Skill storage is unavailable')
    return this.storage
  }

  private exclusive<T>(action: () => Promise<T>): Promise<T> {
    const result = this.pending.then(action)
    this.pending = result.then((): void => {}, (): void => {})
    return result
  }

  async loadSkills(): Promise<SkillConfig[]> {
    const raw = await this.preferencesService.getString(PreferenceKeys.SKILL_CONFIGS_JSON, '')
    if (!raw.trim()) return [this.createDefaultAppHelpSkill()]
    return this.parseRecords(raw).map((item: SkillRecord): SkillConfig => this.fromRecord(item))
  }

  private parseRecords(raw: string): SkillRecord[] {
    const records = JSON.parse(raw) as SkillRecord[]
    if (!Array.isArray(records)) throw new Error('Invalid skill catalog')
    return records
  }

  private fromRecord(item: SkillRecord): SkillConfig {
    if (typeof item.id !== 'string' || !item.id || typeof item.name !== 'string' || !item.name.trim()) {
      throw new Error('Invalid skill identity')
    }
    const skill = new SkillConfig(item.id, item.name, item.description ?? '', item.content ?? '',
      item.enabled !== false, item.createdAt ?? Date.now(), item.updatedAt ?? Date.now())
    skill.manualOnly = item.manualOnly === true
    skill.bundleKey = item.bundleKey ?? ''
    skill.paths = skill.bundleKey && item.paths ? item.paths : [SKILL_ENTRY]
    return skill
  }

  private toRecord(skill: SkillConfig): SkillRecord {
    return { id: skill.id, name: skill.name, description: skill.description, content: skill.content,
      enabled: skill.enabled, createdAt: skill.createdAt, updatedAt: skill.updatedAt,
      bundleKey: skill.bundleKey, paths: skill.paths, manualOnly: skill.manualOnly }
  }

  private async saveIndex(skills: SkillConfig[]): Promise<void> {
    const records = skills.map((skill: SkillConfig): SkillRecord => this.toRecord(skill))
    await this.preferencesService.setString(PreferenceKeys.SKILL_CONFIGS_JSON, JSON.stringify(records), true)
  }

  async filesForSkill(skill: SkillConfig): Promise<SkillFile[]> {
    if (!skill.bundleKey) return [skillTextFile(SKILL_ENTRY, skill.content)]
    return unpackSkill(await this.store().read(skill.bundleKey)).files
  }

  async savePackage(skill: SkillConfig, files: SkillFile[]): Promise<void> {
    const normalized = normalizeSkillBundle(files).files
    for (const file of normalized) {
      if (isSkillMarkdown(file.path)) skillFileText(file)
    }
    const blob = packSkill(normalized)
    await this.exclusive(async (): Promise<void> => {
      const skills = await this.loadSkills()
      const index = skills.findIndex((entry: SkillConfig): boolean => entry.id === skill.id)
      if (skill.id && (index < 0 || skill.bundleKey !== skills[index].bundleKey)) {
        throw new Error('Skill changed since it was opened')
      }
      const now = Date.now()
      const next = new SkillConfig(skill.id || this.buildNewSkillId(skill.name), skill.name.trim(),
        skill.description.trim(), '', skill.enabled, skill.createdAt || now, now)
      const previous = index < 0 ? '' : skills[index].bundleKey
      next.manualOnly = readStoredSkillMetadata(skillFileText(normalized[0]), next.name, next.description).manualOnly
      next.paths = normalized.map((file: SkillFile): string => file.path)
      next.bundleKey = await this.store().write(blob)
      if (index < 0) skills.push(next)
      else skills[index] = next
      try {
        await this.saveIndex(skills)
      } catch (error) {
        await this.store().remove(next.bundleKey)
        throw error as Error
      }
      if (previous) await this.store().remove(previous)
    })
  }

  async setSkillEnabled(id: string, enabled: boolean): Promise<void> {
    await this.exclusive(async (): Promise<void> => {
      const skills = await this.loadSkills()
      const skill = skills.find((item: SkillConfig): boolean => item.id === id)
      if (skill) {
        skill.enabled = enabled
        skill.updatedAt = Date.now()
        await this.saveIndex(skills)
      }
    })
  }

  async deleteSkill(id: string): Promise<void> {
    await this.exclusive(async (): Promise<void> => {
      const skills = await this.loadSkills()
      const skill = skills.find((item: SkillConfig): boolean => item.id === id)
      if (!skill) return
      await this.saveIndex(skills.filter((item: SkillConfig): boolean => item.id !== id))
      if (skill.bundleKey) await this.store().remove(skill.bundleKey)
    })
  }

  async exportCatalog(): Promise<string> {
    return this.exclusive(async (): Promise<string> => {
      const records: SkillRecord[] = []
      for (const skill of await this.loadSkills()) {
        const record = this.toRecord(skill)
        if (skill.bundleKey) record.archive = new util.Base64Helper().encodeToStringSync(await this.store().read(skill.bundleKey))
        record.bundleKey = ''
        records.push(record)
      }
      return JSON.stringify(records)
    })
  }

  async restoreCatalog(raw: string): Promise<void> {
    const records = this.parseRecords(raw)
    await this.exclusive(async (): Promise<void> => {
      const previous = await this.loadSkills()
      const restored: SkillConfig[] = []
      const staged: string[] = []
      try {
        for (const record of records) {
          const skill = this.fromRecord(record)
          if (restored.some((item: SkillConfig): boolean => item.id === skill.id)) throw new Error('Duplicate skill id')
          if (record.bundleKey && !record.archive) throw new Error('Skill backup has no archive')
          skill.bundleKey = ''
          if (record.archive) {
            const files = unpackSkill(new util.Base64Helper().decodeSync(record.archive)).files
            skill.manualOnly = readStoredSkillMetadata(skillFileText(files[0]), skill.name, skill.description).manualOnly
            skill.paths = files.map((file: SkillFile): string => file.path)
            skill.bundleKey = await this.store().write(packSkill(files))
            staged.push(skill.bundleKey)
          }
          restored.push(skill)
        }
        await this.saveIndex(restored)
      } catch (error) {
        for (const key of staged) await this.store().remove(key)
        throw error as Error
      }
      for (const old of previous) {
        if (old.bundleKey) await this.store().remove(old.bundleKey)
      }
    })
  }

  async readForTool(args: string): Promise<string> {
    try {
      const params = this.parseArgs(args)
      return await this.exclusive(async (): Promise<string> => {
        const skills = await this.getEnabledSkills()
        let target = (params.skill_id ?? params.skillId ?? params.id ?? params.name ?? '').trim()
        let path = (params.path ?? '').trim().replace(/^\.\//, '')
        if (!target && !path) return JSON.stringify(new SkillListOutput(skills))
        if (!target) {
          const slash = path.indexOf('/')
          target = slash < 0 ? path : path.slice(0, slash)
          path = slash < 0 ? '' : path.slice(slash + 1)
        }
        const lookup = target.toLowerCase()
        let skill = skills.find((item: SkillConfig): boolean => item.id.toLowerCase() === lookup)
        if (!skill) {
          const matches = skills.filter((item: SkillConfig): boolean => item.name.toLowerCase() === lookup)
          if (matches.length > 1) throw new Error('Multiple enabled skills share this name. Use skill_id: ' + target)
          skill = matches[0]
        }
        if (!skill) throw new Error('Enabled skill not found: ' + target)
        if (!skill.paths.includes(path) && path.startsWith(skill.id + '/')) path = path.slice(skill.id.length + 1)
        path = !path || (!skill.paths.includes(path) && path.toLowerCase() === 'skill.md')
          ? SKILL_ENTRY : checkSkillPath(path)
        if (!skill.paths.includes(path)) throw new Error('File not found: ' + path)
        let content = skill.content
        let encoding = 'utf8'
        if (skill.bundleKey) {
          const file = readPackedSkillFile(await this.store().read(skill.bundleKey), path)
          try {
            content = skillFileText(file)
            if (content.includes('\u0000')) throw new Error('Binary')
          } catch {
            content = new util.Base64Helper().encodeToStringSync(file.bytes)
            encoding = 'base64'
          }
        }
        const max = this.resolveNumber(params.maxChars, this.resolveNumber(params.max_chars, 16000))
        const start = Math.min(content.length, Math.max(0, Math.floor(this.resolveNumber(params.offset, 0))))
        const end = max <= 0 ? content.length : Math.min(content.length, start + Math.max(1, Math.floor(max)))
        return JSON.stringify(new SkillReadOutput(skill, path, content, encoding, start, end))
      })
    } catch (error) {
      return JSON.stringify(new SkillErrorOutput(this.stringifyError(error)))
    }
  }

  async getEnabledSkills(): Promise<SkillConfig[]> {
    return (await this.loadSkills()).filter((skill: SkillConfig): boolean => skill.enabled && !skill.manualOnly)
  }

  buildNewSkillId(name: string): string {
    return (this.normalizeSkillId(name).slice(0, 64) || 'skill') + '_' + util.generateRandomUUID()
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
