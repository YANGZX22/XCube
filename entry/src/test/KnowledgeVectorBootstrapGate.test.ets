import { describe, it, expect } from '@ohos/hypium'
import {
  KnowledgeVectorBootstrapCompletion,
  KnowledgeVectorBootstrapGate,
  KnowledgeVectorBootstrapResult,
  KnowledgeVectorBootstrapStatus
} from '../main/ets/services/KnowledgeVectorBootstrapGate'

class BootstrapCompletionDeferred {
  promise: Promise<KnowledgeVectorBootstrapCompletion> =
    Promise.resolve(KnowledgeVectorBootstrapCompletion.failedResult())
  private resolvePromise: ((value: KnowledgeVectorBootstrapCompletion) => void) | null = null

  constructor() {
    this.promise = new Promise<KnowledgeVectorBootstrapCompletion>((resolve): void => {
      this.resolvePromise = resolve
    })
  }

  resolve(completion: KnowledgeVectorBootstrapCompletion): void {
    if (this.resolvePromise !== null) {
      this.resolvePromise(completion)
      this.resolvePromise = null
    }
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

export default function knowledgeVectorBootstrapGateTest() {
  describe('knowledgeVectorBootstrapGateTest', () => {
    it('returns_idle_without_a_tracked_recovery', 0, async () => {
      const gate = new KnowledgeVectorBootstrapGate(20)

      const result = await gate.waitForFirstKnowledgeSearch()

      expect(result.status).assertEqual(KnowledgeVectorBootstrapStatus.IDLE)
      expect(result.shouldUseKeywordFallback()).assertEqual(true)
    })

    it('shares_one_bounded_wait_between_concurrent_first_searches', 0, async () => {
      const deferred = new BootstrapCompletionDeferred()
      const gate = new KnowledgeVectorBootstrapGate(100)
      gate.track(deferred.promise)

      const firstWait = gate.waitForFirstKnowledgeSearch()
      const concurrentWait = gate.waitForFirstKnowledgeSearch()

      expect(firstWait === concurrentWait).assertEqual(true)

      deferred.resolve(KnowledgeVectorBootstrapCompletion.readyResult())
      const results = await Promise.all([firstWait, concurrentWait])

      expect(results[0].status).assertEqual(KnowledgeVectorBootstrapStatus.READY)
      expect(results[1].status).assertEqual(KnowledgeVectorBootstrapStatus.READY)
      expect(gate.current().status).assertEqual(KnowledgeVectorBootstrapStatus.READY)
    })

    it('reports_an_explicit_fast_recovery_failure', 0, async () => {
      const deferred = new BootstrapCompletionDeferred()
      const gate = new KnowledgeVectorBootstrapGate(100)
      gate.track(deferred.promise)
      const wait = gate.waitForFirstKnowledgeSearch()

      deferred.resolve(
        KnowledgeVectorBootstrapCompletion.failedResult('测试 sidecar 不可用')
      )
      const result = await wait

      expect(result.status).assertEqual(KnowledgeVectorBootstrapStatus.FAILED)
      expect(result.message.includes('测试 sidecar 不可用')).assertEqual(true)
      expect(result.shouldUseKeywordFallback()).assertEqual(true)
    })

    it('times_out_without_cancelling_background_recovery', 0, async () => {
      const deferred = new BootstrapCompletionDeferred()
      const gate = new KnowledgeVectorBootstrapGate(5)
      const trackedCompletion = gate.track(deferred.promise)

      const timedOut = await gate.waitForFirstKnowledgeSearch()

      expect(timedOut.status).assertEqual(KnowledgeVectorBootstrapStatus.TIMED_OUT)
      expect(gate.current().status).assertEqual(KnowledgeVectorBootstrapStatus.TIMED_OUT)

      deferred.resolve(KnowledgeVectorBootstrapCompletion.readyResult('迟到恢复成功'))
      const eventual = await trackedCompletion

      expect(eventual.status).assertEqual(KnowledgeVectorBootstrapStatus.READY)
      expect(gate.current().status).assertEqual(KnowledgeVectorBootstrapStatus.READY)
      const laterSearch = await gate.waitForFirstKnowledgeSearch()
      expect(laterSearch.status).assertEqual(KnowledgeVectorBootstrapStatus.READY)
    })

    it('does_not_wait_for_the_full_document_migration', 0, async () => {
      const quickRecovery = new BootstrapCompletionDeferred()
      const fullMigration = new VoidDeferred()
      const gate = new KnowledgeVectorBootstrapGate(100)
      gate.track(quickRecovery.promise)
      const wait = gate.waitForFirstKnowledgeSearch()

      quickRecovery.resolve(
        KnowledgeVectorBootstrapCompletion.readyResult('sidecar 配置完成')
      )
      const result: KnowledgeVectorBootstrapResult = await wait

      expect(result.status).assertEqual(KnowledgeVectorBootstrapStatus.READY)
      expect(fullMigration.completed).assertEqual(false)
      fullMigration.resolve()
      await fullMigration.promise
    })

    it('ignores_a_stale_recovery_after_a_new_task_is_tracked', 0, async () => {
      const stale = new BootstrapCompletionDeferred()
      const current = new BootstrapCompletionDeferred()
      const gate = new KnowledgeVectorBootstrapGate(100)
      gate.track(stale.promise)
      gate.track(current.promise)

      stale.resolve(KnowledgeVectorBootstrapCompletion.readyResult('旧任务'))
      await stale.promise
      expect(gate.current().status).assertEqual(KnowledgeVectorBootstrapStatus.RUNNING)

      current.resolve(KnowledgeVectorBootstrapCompletion.failedResult('新任务失败'))
      const result = await gate.waitForFirstKnowledgeSearch()

      expect(result.status).assertEqual(KnowledgeVectorBootstrapStatus.FAILED)
      expect(result.message.includes('新任务失败')).assertEqual(true)
    })
  })
}
