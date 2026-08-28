class PythonWorkspaceSessionQueue {
  tail: Promise<void> = Promise.resolve()
  pendingCount: number = 0
}

// Python 执行、产物注册和会话删除共用的按会话队列。
// 不同会话仍可独立推进；同一会话则保证完整工具调用与删除严格有序。
export class PythonWorkspaceSessionCoordinator {
  private queues: Map<string, PythonWorkspaceSessionQueue> = new Map()
  private deletedSessions: Set<string> = new Set()

  async runExclusive<T>(sessionId: string, task: () => Promise<T>): Promise<T> {
    const normalizedSessionId = this.normalizeSessionId(sessionId)
    let queue = this.queues.get(normalizedSessionId)
    if (queue === undefined) {
      queue = new PythonWorkspaceSessionQueue()
      this.queues.set(normalizedSessionId, queue)
    }
    const previous = queue.tail
    let release: () => void = (): void => {}
    const current = new Promise<void>((resolve) => {
      release = resolve
    })
    queue.tail = current
    queue.pendingCount += 1
    await previous
    try {
      return await task()
    } finally {
      queue.pendingCount = Math.max(0, queue.pendingCount - 1)
      release()
      if (queue.pendingCount === 0 && queue.tail === current) {
        this.queues.delete(normalizedSessionId)
      }
    }
  }

  markDeleted(sessionId: string): void {
    this.deletedSessions.add(this.normalizeSessionId(sessionId))
  }

  restore(sessionId: string): void {
    this.deletedSessions.delete(this.normalizeSessionId(sessionId))
  }

  isDeleted(sessionId: string): boolean {
    return this.deletedSessions.has(this.normalizeSessionId(sessionId))
  }

  listActiveSessionIds(): string[] {
    return Array.from(this.queues.keys())
  }

  assertWritable(sessionId: string): void {
    if (this.isDeleted(sessionId)) {
      throw new Error('当前会话已删除，拒绝写入或回写 Python 工作区')
    }
  }

  private normalizeSessionId(sessionId: string): string {
    const normalized = sessionId.trim()
    if (normalized === '') {
      throw new Error('当前没有有效会话，无法协调 Python 工作区')
    }
    return normalized
  }
}
