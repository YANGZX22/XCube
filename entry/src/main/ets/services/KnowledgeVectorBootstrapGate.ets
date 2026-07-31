export const DEFAULT_KNOWLEDGE_VECTOR_BOOTSTRAP_WAIT_MS: number = 800

/**
 * 首次 knowledge_search 等待向量 sidecar 快速恢复时可观察到的状态。
 *
 * TIMED_OUT 仅表示首次查询不再等待，并不会取消后台恢复。后台恢复完成后，
 * gate 仍会转为 READY 或 FAILED，后续查询可直接读取最终状态。
 */
export enum KnowledgeVectorBootstrapStatus {
  IDLE = 'idle',
  RUNNING = 'running',
  READY = 'ready',
  FAILED = 'failed',
  TIMED_OUT = 'timed_out'
}

/**
 * sidecar 快速恢复任务的显式完成信号。
 *
 * 调用方应在 sidecar 已打开且混合检索适配器已配置后返回 READY；全量文档
 * 向量迁移应继续在此 Promise 之外后台执行，避免首查等待整库重建。
 */
export class KnowledgeVectorBootstrapCompletion {
  ready: boolean = false
  message: string = ''

  constructor(ready: boolean, message: string = '') {
    this.ready = ready
    this.message = message
  }

  static readyResult(message: string = '向量 sidecar 已就绪'): KnowledgeVectorBootstrapCompletion {
    return new KnowledgeVectorBootstrapCompletion(true, message)
  }

  static failedResult(message: string = '向量 sidecar 快速恢复失败'): KnowledgeVectorBootstrapCompletion {
    return new KnowledgeVectorBootstrapCompletion(false, message)
  }
}

export class KnowledgeVectorBootstrapResult {
  status: KnowledgeVectorBootstrapStatus = KnowledgeVectorBootstrapStatus.IDLE
  message: string = ''

  constructor(
    status: KnowledgeVectorBootstrapStatus = KnowledgeVectorBootstrapStatus.IDLE,
    message: string = ''
  ) {
    this.status = status
    this.message = message
  }

  copy(): KnowledgeVectorBootstrapResult {
    return new KnowledgeVectorBootstrapResult(this.status, this.message)
  }

  isReady(): boolean {
    return this.status === KnowledgeVectorBootstrapStatus.READY
  }

  shouldUseKeywordFallback(): boolean {
    return this.status !== KnowledgeVectorBootstrapStatus.READY
  }
}

/**
 * 冷启动向量检索的限时等待门。
 *
 * track() 只接收“打开 sidecar + 配置检索器”的快速恢复 Promise，不接收
 * 全量文档迁移 Promise。waitForFirstKnowledgeSearch() 应仅在解析并验证真实的
 * knowledge_search 工具调用后执行，工具曝光和普通提示词构建不得调用它。
 */
export class KnowledgeVectorBootstrapGate {
  private waitTimeoutMs: number = DEFAULT_KNOWLEDGE_VECTOR_BOOTSTRAP_WAIT_MS
  private generation: number = 0
  private state: KnowledgeVectorBootstrapResult =
    new KnowledgeVectorBootstrapResult(KnowledgeVectorBootstrapStatus.IDLE)
  private trackedPromise: Promise<KnowledgeVectorBootstrapResult> | null = null
  private firstSearchWaitPromise: Promise<KnowledgeVectorBootstrapResult> | null = null
  private firstSearchWaitConsumed: boolean = false

  constructor(waitTimeoutMs: number = DEFAULT_KNOWLEDGE_VECTOR_BOOTSTRAP_WAIT_MS) {
    if (Number.isFinite(waitTimeoutMs) &&
      Number.isInteger(waitTimeoutMs) &&
      waitTimeoutMs >= 0) {
      this.waitTimeoutMs = waitTimeoutMs
    }
  }

  /**
   * 跟踪一个新的快速恢复任务。新任务会使旧任务的迟到结果失效。
   */
  track(
    quickRecoveryPromise: Promise<KnowledgeVectorBootstrapCompletion>
  ): Promise<KnowledgeVectorBootstrapResult> {
    this.generation += 1
    const taskGeneration = this.generation
    this.state = new KnowledgeVectorBootstrapResult(
      KnowledgeVectorBootstrapStatus.RUNNING,
      '向量 sidecar 正在快速恢复'
    )
    this.firstSearchWaitPromise = null
    this.firstSearchWaitConsumed = false

    const normalizedPromise = quickRecoveryPromise.then(
      (completion: KnowledgeVectorBootstrapCompletion): KnowledgeVectorBootstrapResult => {
        const result = completion.ready
          ? new KnowledgeVectorBootstrapResult(
            KnowledgeVectorBootstrapStatus.READY,
            completion.message === '' ? '向量 sidecar 已就绪' : completion.message
          )
          : new KnowledgeVectorBootstrapResult(
            KnowledgeVectorBootstrapStatus.FAILED,
            completion.message === '' ? '向量 sidecar 快速恢复失败' : completion.message
          )
        this.applyTaskResult(taskGeneration, result)
        return result
      },
      (error: Object): KnowledgeVectorBootstrapResult => {
        const errorMessage = this.safeErrorMessage(error)
        const result = new KnowledgeVectorBootstrapResult(
          KnowledgeVectorBootstrapStatus.FAILED,
          errorMessage === ''
            ? '向量 sidecar 快速恢复失败'
            : `向量 sidecar 快速恢复失败：${errorMessage}`
        )
        this.applyTaskResult(taskGeneration, result)
        return result
      }
    )
    this.trackedPromise = normalizedPromise
    return normalizedPromise
  }

  /**
   * 仅为首个真实 knowledge_search 限时等待。等待中的并发调用会取得同一个
   * Promise；首次等待结束后，后续调用只读取当前状态，不再增加冷启动延迟。
   */
  waitForFirstKnowledgeSearch(): Promise<KnowledgeVectorBootstrapResult> {
    if (this.state.status !== KnowledgeVectorBootstrapStatus.RUNNING ||
      this.trackedPromise === null) {
      return Promise.resolve(this.state.copy())
    }
    if (this.firstSearchWaitPromise !== null) {
      return this.firstSearchWaitPromise
    }
    if (this.firstSearchWaitConsumed) {
      return Promise.resolve(this.state.copy())
    }

    this.firstSearchWaitConsumed = true
    const waitGeneration = this.generation
    const boundedWait = this.createBoundedWait(
      this.trackedPromise,
      waitGeneration
    )
    const sharedWait = boundedWait.then(
      (result: KnowledgeVectorBootstrapResult): KnowledgeVectorBootstrapResult => {
        if (this.generation === waitGeneration) {
          this.firstSearchWaitPromise = null
        }
        return result
      }
    )
    this.firstSearchWaitPromise = sharedWait
    return sharedWait
  }

  current(): KnowledgeVectorBootstrapResult {
    return this.state.copy()
  }

  reset(): void {
    this.generation += 1
    this.state = new KnowledgeVectorBootstrapResult(
      KnowledgeVectorBootstrapStatus.IDLE
    )
    this.trackedPromise = null
    this.firstSearchWaitPromise = null
    this.firstSearchWaitConsumed = false
  }

  private createBoundedWait(
    trackedPromise: Promise<KnowledgeVectorBootstrapResult>,
    waitGeneration: number
  ): Promise<KnowledgeVectorBootstrapResult> {
    return new Promise<KnowledgeVectorBootstrapResult>((resolve): void => {
      let settled = false
      const timerId = setTimeout((): void => {
        if (settled) {
          return
        }
        settled = true
        const timeoutResult = new KnowledgeVectorBootstrapResult(
          KnowledgeVectorBootstrapStatus.TIMED_OUT,
          `向量 sidecar 快速恢复等待超过 ${this.waitTimeoutMs}ms，当前查询使用关键词检索`
        )
        if (this.generation === waitGeneration &&
          this.state.status === KnowledgeVectorBootstrapStatus.RUNNING) {
          this.state = timeoutResult.copy()
        }
        resolve(timeoutResult)
      }, this.waitTimeoutMs)

      trackedPromise.then(
        (result: KnowledgeVectorBootstrapResult): void => {
          if (settled) {
            return
          }
          settled = true
          clearTimeout(timerId)
          resolve(result.copy())
        }
      )
    })
  }

  private applyTaskResult(
    taskGeneration: number,
    result: KnowledgeVectorBootstrapResult
  ): void {
    if (this.generation !== taskGeneration) {
      return
    }
    this.state = result.copy()
  }

  private safeErrorMessage(error: Object): string {
    if (error instanceof Error) {
      return error.message
    }
    return ''
  }
}
