import { util } from '@kit.ArkTS'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0002
const TAG = 'PyodideRuntime'

export enum PyodideState {
  UNINITIALIZED = 0,
  LOADING = 1,
  READY = 2,
  FAILED = 3
}

// 与旧 PythonSandboxResult 结构对齐，使上层 UI 卡片无需改动
export class PyodideRunResult {
  ok: boolean = true
  stdout: string[] = []
  result: string = ''
  variables: Record<string, Object> = {}
  warnings: string[] = []
  error: string = ''
  // 仅内部使用：标记运行时不可用，需由调用方降级
  fallback: boolean = false

  constructor(ok: boolean = true) {
    this.ok = ok
  }
}

// UI 层隐藏 Web 宿主需实现的接口，供服务触发网页执行
export interface PyodideHost {
  runPython(requestId: string, codeB64: string, varsB64: string): void
}

class PendingRequest {
  resolve: (result: PyodideRunResult) => void
  timerId: number = -1

  constructor(resolve: (result: PyodideRunResult) => void) {
    this.resolve = resolve
  }
}

export class PyodideRuntimeService {
  private static instance: PyodideRuntimeService | null = null

  private state: PyodideState = PyodideState.UNINITIALIZED
  private host: PyodideHost | null = null
  private pending: Map<string, PendingRequest> = new Map()
  private requestSeq: number = 0
  // 最近一次加载/初始化失败的真实原因，降级时透传给上层
  private lastError: string = ''
  // 等待 onReady 的解析器（host 已挂载但 Pyodide 仍在加载时排队）
  private readyWaiters: ((ready: boolean) => void)[] = []
  private readonly readyTimeoutMs: number = 30000
  private readonly runTimeoutMs: number = 20000

  static getInstance(): PyodideRuntimeService {
    if (PyodideRuntimeService.instance === null) {
      PyodideRuntimeService.instance = new PyodideRuntimeService()
    }
    return PyodideRuntimeService.instance
  }

  // ---- UI 宿主生命周期 ----

  attachHost(host: PyodideHost): void {
    this.host = host
    if (this.state === PyodideState.UNINITIALIZED || this.state === PyodideState.FAILED) {
      this.state = PyodideState.LOADING
    }
    hilog.info(DOMAIN, TAG, 'Pyodide host attached')
  }

  detachHost(host: PyodideHost): void {
    if (this.host === host) {
      this.host = null
      hilog.info(DOMAIN, TAG, 'Pyodide host detached')
    }
  }

  getState(): PyodideState {
    return this.state
  }

  // ---- 网页桥回调 ----

  onReady(): void {
    this.state = PyodideState.READY
    hilog.info(DOMAIN, TAG, 'Pyodide ready')
    const waiters = this.readyWaiters
    this.readyWaiters = []
    for (let i = 0; i < waiters.length; i++) {
      waiters[i](true)
    }
  }

  onError(message: string): void {
    hilog.error(DOMAIN, TAG, `Pyodide error: ${message}`)
    this.lastError = message
    if (this.state !== PyodideState.READY) {
      this.state = PyodideState.FAILED
      const waiters = this.readyWaiters
      this.readyWaiters = []
      for (let i = 0; i < waiters.length; i++) {
        waiters[i](false)
      }
    }
  }

  onResult(requestId: string, json: string): void {
    const entry = this.pending.get(requestId)
    if (entry === undefined) {
      return
    }
    this.pending.delete(requestId)
    if (entry.timerId !== -1) {
      clearTimeout(entry.timerId)
    }
    let parsed: PyodideRunResult
    try {
      const raw = JSON.parse(json) as PyodideRunResult
      parsed = new PyodideRunResult(raw.ok !== false)
      parsed.stdout = raw.stdout ?? []
      parsed.result = raw.result ?? ''
      parsed.variables = raw.variables ?? {}
      parsed.warnings = raw.warnings ?? []
      parsed.error = raw.error ?? ''
    } catch (e) {
      parsed = new PyodideRunResult(false)
      parsed.error = `结果解析失败: ${json}`
    }
    entry.resolve(parsed)
  }

  // ---- 执行入口 ----

  async run(code: string, variables: Record<string, Object> | undefined): Promise<PyodideRunResult> {
    if (this.host === null) {
      return this.fallbackResult('Python 运行时宿主未挂载')
    }

    const ready = await this.waitUntilReady()
    if (!ready) {
      const detail = this.lastError !== '' ? this.lastError : '加载超时（可能无网络或 WebView 未初始化）'
      return this.fallbackResult(`Python 运行时未就绪：${detail}`)
    }

    const host = this.host
    if (host === null) {
      return this.fallbackResult('Python 运行时宿主已分离')
    }

    this.requestSeq += 1
    const requestId = `py-${this.requestSeq}`
    const codeB64 = this.encodeUtf8ToBase64(code)
    const varsB64 = this.encodeUtf8ToBase64(variables === undefined ? '' : JSON.stringify(variables))

    return new Promise<PyodideRunResult>((resolve) => {
      const entry = new PendingRequest(resolve)
      entry.timerId = setTimeout(() => {
        if (this.pending.has(requestId)) {
          this.pending.delete(requestId)
          resolve(this.fallbackResult(`Python 执行超时（${this.runTimeoutMs}ms）`))
        }
      }, this.runTimeoutMs)
      this.pending.set(requestId, entry)
      try {
        host.runPython(requestId, codeB64, varsB64)
      } catch (e) {
        this.pending.delete(requestId)
        if (entry.timerId !== -1) {
          clearTimeout(entry.timerId)
        }
        resolve(this.fallbackResult(`触发执行失败: ${e instanceof Error ? e.message : JSON.stringify(e)}`))
      }
    })
  }

  private waitUntilReady(): Promise<boolean> {
    if (this.state === PyodideState.READY) {
      return Promise.resolve(true)
    }
    if (this.state === PyodideState.FAILED) {
      return Promise.resolve(false)
    }
    return new Promise<boolean>((resolve) => {
      let settled = false
      const waiter = (ready: boolean): void => {
        if (!settled) {
          settled = true
          resolve(ready)
        }
      }
      this.readyWaiters.push(waiter)
      setTimeout(() => {
        if (!settled) {
          settled = true
          resolve(this.state === PyodideState.READY)
        }
      }, this.readyTimeoutMs)
    })
  }

  private fallbackResult(reason: string): PyodideRunResult {
    const result = new PyodideRunResult(false)
    result.fallback = true
    result.error = reason
    return result
  }

  private encodeUtf8ToBase64(value: string): string {
    if (value === '') {
      return ''
    }
    const bytes = new util.TextEncoder().encodeInto(value)
    const helper = new util.Base64Helper()
    return helper.encodeToStringSync(bytes)
  }
}

export function getPyodideRuntimeService(): PyodideRuntimeService {
  return PyodideRuntimeService.getInstance()
}
