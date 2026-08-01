import {
  KnowledgeVectorBootstrapCompletion,
  KnowledgeVectorBootstrapGate,
  KnowledgeVectorBootstrapResult
} from './KnowledgeVectorBootstrapGate'

export interface KnowledgeVectorStartupPlanLike {
  modelKey: string
  documentIds: string[]
  vectorReady: boolean
  message: string
  migrationGeneration: number
}

export class KnowledgeVectorStartupDocumentResult {
  keywordReady: boolean = false
  vectorReady: boolean = false
  message: string = ''

  constructor(
    keywordReady: boolean = false,
    vectorReady: boolean = false,
    message: string = ''
  ) {
    this.keywordReady = keywordReady
    this.vectorReady = vectorReady
    this.message = message
  }
}

export class KnowledgeVectorStartupMigrationSummary {
  plannedDocuments: number = 0
  attemptedDocuments: number = 0
  keywordReadyDocuments: number = 0
  vectorReadyDocuments: number = 0
  failedDocuments: number = 0
  lastMessage: string = ''
  cancelled: boolean = false
}

export interface KnowledgeVectorStartupDependencies {
  isPlanCurrent(plan: KnowledgeVectorStartupPlanLike): boolean
  waitBeforeMigrations(): Promise<void>
  migrateDocument(
    documentId: string,
    modelKey: string
  ): Promise<KnowledgeVectorStartupDocumentResult>
  yieldBetweenDocuments(): Promise<void>
}

export class KnowledgeVectorStartupDependencyCallbacks implements
  KnowledgeVectorStartupDependencies {
  private planCurrentCallback: (plan: KnowledgeVectorStartupPlanLike) => boolean
  private waitCallback: () => Promise<void>
  private migrateCallback: (
    documentId: string,
    modelKey: string
  ) => Promise<KnowledgeVectorStartupDocumentResult>
  private yieldCallback: () => Promise<void>

  constructor(
    planCurrentCallback: (plan: KnowledgeVectorStartupPlanLike) => boolean,
    waitCallback: () => Promise<void>,
    migrateCallback: (
      documentId: string,
      modelKey: string
    ) => Promise<KnowledgeVectorStartupDocumentResult>,
    yieldCallback: () => Promise<void>
  ) {
    this.planCurrentCallback = planCurrentCallback
    this.waitCallback = waitCallback
    this.migrateCallback = migrateCallback
    this.yieldCallback = yieldCallback
  }

  isPlanCurrent(plan: KnowledgeVectorStartupPlanLike): boolean {
    return this.planCurrentCallback(plan)
  }

  waitBeforeMigrations(): Promise<void> {
    return this.waitCallback()
  }

  migrateDocument(
    documentId: string,
    modelKey: string
  ): Promise<KnowledgeVectorStartupDocumentResult> {
    return this.migrateCallback(documentId, modelKey)
  }

  yieldBetweenDocuments(): Promise<void> {
    return this.yieldCallback()
  }
}

/**
 * 把 sidecar 快速恢复和文档迁移调度绑定在同一个协调器中。
 *
 * track() 只影响首次查询的快速恢复 gate；真正的文档迁移必须由页面首帧加载后
 * 显式调用 startDeferredMigrations()，避免 OCR、切块和向量响应处理阻塞冷启动。
 */
export class KnowledgeVectorStartupCoordinator {
  private gate: KnowledgeVectorBootstrapGate
  private dependencies: KnowledgeVectorStartupDependencies
  private planPromise: Promise<KnowledgeVectorStartupPlanLike> | null = null
  private migrationPromise: Promise<KnowledgeVectorStartupMigrationSummary> | null = null

  constructor(
    gate: KnowledgeVectorBootstrapGate,
    dependencies: KnowledgeVectorStartupDependencies
  ) {
    this.gate = gate
    this.dependencies = dependencies
  }

  track(
    planPromise: Promise<KnowledgeVectorStartupPlanLike>
  ): Promise<KnowledgeVectorBootstrapResult> {
    this.planPromise = planPromise
    this.migrationPromise = null
    return this.gate.track(
      planPromise.then(
        (plan: KnowledgeVectorStartupPlanLike): KnowledgeVectorBootstrapCompletion => {
          return plan.vectorReady
            ? KnowledgeVectorBootstrapCompletion.readyResult(plan.message)
            : KnowledgeVectorBootstrapCompletion.failedResult(plan.message)
        }
      )
    )
  }

  startDeferredMigrations(): Promise<KnowledgeVectorStartupMigrationSummary> {
    if (this.migrationPromise !== null) {
      return this.migrationPromise
    }
    const planPromise = this.planPromise
    if (planPromise === null) {
      return Promise.resolve(new KnowledgeVectorStartupMigrationSummary())
    }
    this.migrationPromise = planPromise.then(
      async (plan: KnowledgeVectorStartupPlanLike): Promise<KnowledgeVectorStartupMigrationSummary> => {
        return await this.runMigrations(plan)
      }
    )
    return this.migrationPromise
  }

  private async runMigrations(
    plan: KnowledgeVectorStartupPlanLike
  ): Promise<KnowledgeVectorStartupMigrationSummary> {
    const summary = new KnowledgeVectorStartupMigrationSummary()
    summary.plannedDocuments = plan.documentIds.length
    if (plan.documentIds.length === 0) {
      return summary
    }

    await this.dependencies.waitBeforeMigrations()
    for (let index = 0; index < plan.documentIds.length; index++) {
      if (!this.dependencies.isPlanCurrent(plan)) {
        summary.cancelled = true
        break
      }

      summary.attemptedDocuments += 1
      try {
        const result = await this.dependencies.migrateDocument(
          plan.documentIds[index],
          plan.modelKey
        )
        if (result.keywordReady) {
          summary.keywordReadyDocuments += 1
        }
        if (result.vectorReady) {
          summary.vectorReadyDocuments += 1
        } else {
          summary.failedDocuments += 1
          if (result.message.trim() !== '') {
            summary.lastMessage = result.message
          }
        }
      } catch (error) {
        summary.failedDocuments += 1
        if (error instanceof Error && error.message.trim() !== '') {
          summary.lastMessage = error.message
        }
      }

      if (index + 1 < plan.documentIds.length) {
        await this.dependencies.yieldBetweenDocuments()
      }
    }
    return summary
  }
}
