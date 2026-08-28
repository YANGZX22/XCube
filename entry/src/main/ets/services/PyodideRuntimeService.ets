import { util } from '@kit.ArkTS'
import { hilog } from '@kit.PerformanceAnalysisKit'
import {
  PYTHON_EXECUTION_TIMEOUT_MS,
  PYTHON_PACKAGE_LOAD_TIMEOUT_MS,
  PYTHON_RUNTIME_READY_TIMEOUT_MS
} from './PythonSandboxRuntimePolicy'
import { PythonWorkspaceFileData } from './PythonWorkspaceService'

const DOMAIN = 0x0002
const TAG = 'PyodideRuntime'

export enum PyodideState {
  UNINITIALIZED = 0,
  LOADING = 1,
  READY = 2,
  FAILED = 3
}

// 仅在 WebView -> ArkTS bridge 内短暂存在；落盘后不会把 base64 返回给模型。
export class PyodideOutputArtifact {
  kind: string = 'file'
  name: string = ''
  mimeType: string = ''
  size: number = 0
  data: string = ''
}

// 与旧 PythonSandboxResult 结构对齐，使上层 UI 卡片无需改动
export class PyodideRunResult {
  ok: boolean = true
  stdout: string[] = []
  result: string = ''
  variables: Record<string, Object> = {}
  warnings: string[] = []
  error: string = ''
  artifacts: PyodideOutputArtifact[] = []
  workspaceFiles: PythonWorkspaceFileData[] = []
  workspaceCaptured: boolean = false
  // 仅内部使用：标记运行时不可用，需由调用方降级
  fallback: boolean = false

  constructor(ok: boolean = true) {
    this.ok = ok
  }
}

// UI 层隐藏 Web 宿主需实现的接口，供服务触发网页执行
export interface PyodideHost {
  runPython(requestId: string, codeB64: string, varsB64: string, packagesB64: string,
    workspaceB64: string): void
  resetPython(): boolean
}

export class PyodideWorkspaceRequest {
  files: PythonWorkspaceFileData[] = []
  runFiles: string[] = []

  constructor(files: PythonWorkspaceFileData[], runFiles: string[]) {
    this.files = files
    this.runFiles = runFiles
  }
}

enum PythonRunPhase {
  PACKAGE_LOADING = 0,
  EXECUTING = 1
}

class PendingRequest {
  resolve: (result: PyodideRunResult) => void
  timerId: number = -1
  phase: PythonRunPhase = PythonRunPhase.PACKAGE_LOADING
  lastPackageProgress: string = ''

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
    if (this.host !== null && this.host !== host) {
      this.resolveReadyWaiters(false)
      this.failPendingRequests('Python 运行时宿主已替换')
    }
    this.host = host
    this.state = PyodideState.LOADING
    this.lastError = ''
    hilog.info(DOMAIN, TAG, 'Pyodide host attached')
  }

  detachHost(host: PyodideHost): void {
    if (this.host === host) {
      this.host = null
      this.state = PyodideState.UNINITIALIZED
      this.lastError = 'Python 运行时宿主已分离'
      this.resolveReadyWaiters(false)
      this.failPendingRequests(this.lastError)
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
    this.resolveReadyWaiters(true)
  }

  onError(message: string): void {
    hilog.error(DOMAIN, TAG, `Pyodide error: ${message}`)
    this.lastError = message
    this.state = PyodideState.FAILED
    this.resolveReadyWaiters(false)
    this.failPendingRequests(`Python 运行时错误：${message}`)
  }

  onExecutionStart(requestId: string): void {
    const entry = this.pending.get(requestId)
    if (entry === undefined || entry.phase === PythonRunPhase.EXECUTING) {
      return
    }
    this.armTimeout(requestId, entry, PythonRunPhase.EXECUTING, PYTHON_EXECUTION_TIMEOUT_MS)
  }

  onPackageProgress(requestId: string, message: string): void {
    const entry = this.pending.get(requestId)
    if (entry === undefined || entry.phase !== PythonRunPhase.PACKAGE_LOADING) {
      return
    }
    entry.lastPackageProgress = message.trim().substring(0, 240)
    // 包加载限制的是“无进展”时长，而不是科学计算包首次下载的总时长。
    this.armTimeout(requestId, entry, PythonRunPhase.PACKAGE_LOADING, PYTHON_PACKAGE_LOAD_TIMEOUT_MS)
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
      parsed.workspaceCaptured = raw.workspaceCaptured === true
      const artifacts = raw.artifacts ?? []
      for (let i = 0; i < artifacts.length; i++) {
        const source = artifacts[i]
        if (typeof source.name !== 'string' || typeof source.mimeType !== 'string' ||
          typeof source.size !== 'number' || typeof source.data !== 'string') {
          continue
        }
        const artifact = new PyodideOutputArtifact()
        artifact.kind = source.kind === 'file' ? 'file' : 'image'
        artifact.name = source.name
        artifact.mimeType = source.mimeType
        artifact.size = source.size
        artifact.data = source.data
        parsed.artifacts.push(artifact)
      }
      const workspaceFiles = raw.workspaceFiles ?? []
      for (let i = 0; i < workspaceFiles.length; i++) {
        const source = workspaceFiles[i]
        if (typeof source.path !== 'string' || typeof source.content !== 'string' ||
          typeof source.size !== 'number') {
          continue
        }
        parsed.workspaceFiles.push(new PythonWorkspaceFileData(source.path, source.content, source.size))
      }
    } catch (e) {
      parsed = new PyodideRunResult(false)
      parsed.error = `结果解析失败: ${json}`
    }
    entry.resolve(parsed)
  }

  // ---- 执行入口 ----

  async run(code: string, variables: Record<string, Object> | undefined,
    packages: string[] = [], workspace?: PyodideWorkspaceRequest): Promise<PyodideRunResult> {
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
    if (this.pending.size > 0) {
      return this.failureResult('Python 运行时已有正在执行或加载包的请求；' +
        '同一会话的 python_sandbox 必须串行调用')
    }

    this.requestSeq += 1
    const requestId = `py-${this.requestSeq}`
    const codeB64 = this.encodeUtf8ToBase64(code)
    const varsB64 = this.encodeUtf8ToBase64(variables === undefined ? '' : JSON.stringify(variables))
    const packagesB64 = this.encodeUtf8ToBase64(JSON.stringify(packages))
    const workspaceB64 = workspace === undefined ? '' : this.encodeUtf8ToBase64(JSON.stringify(workspace))

    return new Promise<PyodideRunResult>((resolve) => {
      const entry = new PendingRequest(resolve)
      this.pending.set(requestId, entry)
      this.armTimeout(requestId, entry, PythonRunPhase.PACKAGE_LOADING, PYTHON_PACKAGE_LOAD_TIMEOUT_MS)
      try {
        host.runPython(requestId, codeB64, varsB64, packagesB64, workspaceB64)
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
    const progressDetail = entry.lastPackageProgress === '' ? '' :
      `；最后进度：${entry.lastPackageProgress}`
    const result = wasPackageLoading ?
      this.fallbackResult(`Python 包加载连续 ${timeoutMs}ms 无进展${progressDetail}`) :
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
      let timerId = -1
      const waiter = (ready: boolean): void => {
        if (!settled) {
          settled = true
          if (timerId !== -1) {
            clearTimeout(timerId)
          }
          resolve(ready)
        }
      }
      this.readyWaiters.push(waiter)
      timerId = setTimeout(() => {
        if (!settled) {
          settled = true
          const index = this.readyWaiters.indexOf(waiter)
          if (index >= 0) {
            this.readyWaiters.splice(index, 1)
          }
          resolve(this.state === PyodideState.READY)
        }
      }, this.readyTimeoutMs)
    })
  }

  private resolveReadyWaiters(ready: boolean): void {
    const waiters = this.readyWaiters
    this.readyWaiters = []
    for (let i = 0; i < waiters.length; i++) {
      waiters[i](ready)
    }
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
