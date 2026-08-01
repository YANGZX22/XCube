import { describe, it, expect } from '@ohos/hypium'
import {
  KnowledgeVectorBootstrapGate,
  KnowledgeVectorBootstrapStatus
} from '../main/ets/services/KnowledgeVectorBootstrapGate'
import {
  KnowledgeVectorStartupCoordinator,
  KnowledgeVectorStartupDependencies,
  KnowledgeVectorStartupDocumentResult,
  KnowledgeVectorStartupPlanLike
} from '../main/ets/services/KnowledgeVectorStartupCoordinator'

class StartupPlan implements KnowledgeVectorStartupPlanLike {
  modelKey: string = 'model-1'
  documentIds: string[] = []
  vectorReady: boolean = true
  message: string = 'sidecar ready'
  migrationGeneration: number = 1

  constructor(documentIds: string[] = []) {
    this.documentIds = documentIds.slice()
  }
}

class VoidDeferred {
  promise: Promise<void> = Promise.resolve()
  completed: boolean = false
  private resolvePromise: (() => void) | null = null

  constructor() {
    this.promise = new Promise<void>((resolve): void => {
      this.resolvePromise = resolve
    })
  }

  resolve(): void {
    this.completed = true
    if (this.resolvePromise !== null) {
      this.resolvePromise()
      this.resolvePromise = null
    }
  }
}

class StartupDependencies implements KnowledgeVectorStartupDependencies {
  current: boolean = true
  migratedDocumentIds: string[] = []
  waitCount: number = 0
  yieldCount: number = 0
  failFirst: boolean = false
  invalidateAfterFirst: boolean = false
  blockedMigration: VoidDeferred | null = null
  migrationStarted: VoidDeferred = new VoidDeferred()

  isPlanCurrent(_plan: KnowledgeVectorStartupPlanLike): boolean {
    return this.current
  }

  async waitBeforeMigrations(): Promise<void> {
    this.waitCount += 1
  }

  async migrateDocument(
    documentId: string,
    _modelKey: string
  ): Promise<KnowledgeVectorStartupDocumentResult> {
    this.migratedDocumentIds.push(documentId)
    if (this.migratedDocumentIds.length === 1) {
      this.migrationStarted.resolve()
      if (this.blockedMigration !== null) {
        await this.blockedMigration.promise
      }
      if (this.invalidateAfterFirst) {
        this.current = false
      }
      if (this.failFirst) {
        throw new Error('first migration failed')
      }
    }
    return new KnowledgeVectorStartupDocumentResult(true, true)
  }

  async yieldBetweenDocuments(): Promise<void> {
    this.yieldCount += 1
  }
}

export default function knowledgeVectorStartupCoordinatorTest() {
  describe('knowledgeVectorStartupCoordinatorTest', () => {
    it('schedules_all_planned_documents_after_page_start', 0, async () => {
      const gate = new KnowledgeVectorBootstrapGate(100)
      const dependencies = new StartupDependencies()
      const coordinator = new KnowledgeVectorStartupCoordinator(gate, dependencies)
      coordinator.track(Promise.resolve(new StartupPlan(['doc-1', 'doc-2'])))

      const summary = await coordinator.startDeferredMigrations()

      expect(dependencies.migratedDocumentIds.length).assertEqual(2)
      expect(dependencies.migratedDocumentIds[0]).assertEqual('doc-1')
      expect(dependencies.migratedDocumentIds[1]).assertEqual('doc-2')
      expect(dependencies.waitCount).assertEqual(1)
      expect(dependencies.yieldCount).assertEqual(1)
      expect(summary.vectorReadyDocuments).assertEqual(2)
    })

    it('quick_gate_does_not_wait_for_slow_document_migration', 0, async () => {
      const gate = new KnowledgeVectorBootstrapGate(100)
      const dependencies = new StartupDependencies()
      const blockedMigration = new VoidDeferred()
      dependencies.blockedMigration = blockedMigration
      const coordinator = new KnowledgeVectorStartupCoordinator(gate, dependencies)
      coordinator.track(Promise.resolve(new StartupPlan(['doc-1'])))

      const migration = coordinator.startDeferredMigrations()
      const quickResult = await gate.waitForFirstKnowledgeSearch()
      await dependencies.migrationStarted.promise

      expect(quickResult.status).assertEqual(KnowledgeVectorBootstrapStatus.READY)
      expect(blockedMigration.completed).assertEqual(false)

      blockedMigration.resolve()
      await migration
    })

    it('stops_when_the_embedding_plan_is_no_longer_current', 0, async () => {
      const gate = new KnowledgeVectorBootstrapGate(100)
      const dependencies = new StartupDependencies()
      dependencies.invalidateAfterFirst = true
      const coordinator = new KnowledgeVectorStartupCoordinator(gate, dependencies)
      coordinator.track(Promise.resolve(new StartupPlan(['doc-1', 'doc-2'])))

      const summary = await coordinator.startDeferredMigrations()

      expect(dependencies.migratedDocumentIds.length).assertEqual(1)
      expect(dependencies.migratedDocumentIds[0]).assertEqual('doc-1')
      expect(summary.cancelled).assertEqual(true)
    })

    it('continues_after_one_document_fails', 0, async () => {
      const gate = new KnowledgeVectorBootstrapGate(100)
      const dependencies = new StartupDependencies()
      dependencies.failFirst = true
      const coordinator = new KnowledgeVectorStartupCoordinator(gate, dependencies)
      coordinator.track(Promise.resolve(new StartupPlan(['doc-1', 'doc-2'])))

      const summary = await coordinator.startDeferredMigrations()

      expect(dependencies.migratedDocumentIds.length).assertEqual(2)
      expect(summary.failedDocuments).assertEqual(1)
      expect(summary.vectorReadyDocuments).assertEqual(1)
      expect(summary.lastMessage.includes('first migration failed')).assertEqual(true)
    })
  })
}
