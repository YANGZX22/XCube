import { util } from '@kit.ArkTS'
import { hilog } from '@kit.PerformanceAnalysisKit'
import {
  PYTHON_EXECUTION_TIMEOUT_MS,
  PYTHON_PACKAGE_LOAD_TIMEOUT_MS,
  PYTHON_RUNTIME_READY_TIMEOUT_MS
} from './PythonSandboxRuntimePolicy'

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
  runPython(requestId: string, codeB64: string, varsB64: string, packagesB64: string): void
  resetPython(): boolean
}

enum PythonRunPhase {
  PACKAGE_LOADING = 0,
  EXECUTING = 1
}

class PendingRequest {
  resolve: (result: PyodideRunResult) => void
  timerId: number = -1
  phase: PythonRunPhase = PythonRunPhase.PACKAGE_LOADING

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
  private readonly readyTimeoutMs: number = PYTHON_RUNTIME_READY_TIMEOUT_MS

  static getInstance(): PyodideRuntimeService {
    if (PyodideRuntimeService.instance === null) {
      PyodideRuntimeService.instance = new PyodideRuntimeService()
    }
    return PyodideRuntimeService.instance
  }

  // ---- UI 宿主生命周期 ----

  attachHost(host: PyodideHost): void {
    this.host = host
    this.state = PyodideState.LOADING
    this.lastError = ''
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
    this.state = PyodideState.FAILED
    const waiters = this.readyWaiters
    this.readyWaiters = []
    for (let i = 0; i < waiters.length; i++) {
      waiters[i](false)
    }
    this.failPendingRequests(`Python 运行时错误：${message}`)
  }

  onExecutionStart(requestId: string): void {
    const entry = this.pending.get(requestId)
    if (entry === undefined || entry.phase === PythonRunPhase.EXECUTING) {
      return
    }
    this.armTimeout(requestId, entry, PythonRunPhase.EXECUTING, PYTHON_EXECUTION_TIMEOUT_MS)
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

  async run(code: string, variables: Record<string, Object> | undefined,
    packages: string[] = []): Promise<PyodideRunResult> {
    if (this.host === null) {
      return this.fallbackResult('Python 运行时宿主未挂载')
    }

    const ready = await this.waitUntilReady()
    if (!ready) {
      const detail = this.lastError !== '' ? this.lastError :
        `加载超时（运行时未在 ${this.readyTimeoutMs}ms 内完成初始化）`
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
    const packagesB64 = this.encodeUtf8ToBase64(JSON.stringify(packages))

    return new Promise<PyodideRunResult>((resolve) => {
      const entry = new PendingRequest(resolve)
      this.pending.set(requestId, entry)
      this.armTimeout(requestId, entry, PythonRunPhase.PACKAGE_LOADING, PYTHON_PACKAGE_LOAD_TIMEOUT_MS)
      try {
        host.runPython(requestId, codeB64, varsB64, packagesB64)
      } catch (e) {
        this.pending.delete(requestId)
        if (entry.timerId !== -1) {
          clearTimeout(entry.timerId)
        }
        resolve(this.fallbackResult(`触发执行失败: ${e instanceof Error ? e.message : JSON.stringify(e)}`))
      }
    })
  }

  private armTimeout(requestId: string, entry: PendingRequest, phase: PythonRunPhase,
    timeoutMs: number): void {
    if (entry.timerId !== -1) {
      clearTimeout(entry.timerId)
    }
    entry.phase = phase
    entry.timerId = setTimeout(() => {
      this.handlePhaseTimeout(requestId, entry, timeoutMs)
    }, timeoutMs)
  }

  private handlePhaseTimeout(requestId: string, entry: PendingRequest, timeoutMs: number): void {
    if (this.pending.get(requestId) !== entry) {
      return
    }
    this.pending.delete(requestId)
    if (entry.timerId !== -1) {
      clearTimeout(entry.timerId)
      entry.timerId = -1
    }

    const wasPackageLoading = entry.phase === PythonRunPhase.PACKAGE_LOADING
    const result = wasPackageLoading ?
      this.fallbackResult(`Python 包加载超时（${timeoutMs}ms）`) :
      this.failureResult(`Python 执行超时（${timeoutMs}ms），已强制终止并重建运行时`)
    this.restartRuntime()
    entry.resolve(result)
  }

  private restartRuntime(): void {
    const host = this.host
    if (host === null) {
      this.state = PyodideState.UNINITIALIZED
      return
    }
    this.state = PyodideState.LOADING
    this.lastError = ''
    try {
      if (!host.resetPython()) {
        this.onError('重建 Python 运行时失败：WebView 未接受重置请求')
        return
      }
      hilog.info(DOMAIN, TAG, 'Pyodide worker reset requested')
    } catch (e) {
      this.onError(`重建 Python 运行时失败：${e instanceof Error ? e.message : JSON.stringify(e)}`)
    }
  }

  private failPendingRequests(reason: string): void {
    this.pending.forEach((entry: PendingRequest, requestId: string): void => {
      this.pending.delete(requestId)
      if (entry.timerId !== -1) {
        clearTimeout(entry.timerId)
      }
      const result = entry.phase === PythonRunPhase.PACKAGE_LOADING ?
        this.fallbackResult(reason) : this.failureResult(reason)
      entry.resolve(result)
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

  private failureResult(reason: string): PyodideRunResult {
    const result = new PyodideRunResult(false)
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
