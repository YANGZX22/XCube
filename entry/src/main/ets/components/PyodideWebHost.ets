import { webview } from '@kit.ArkWeb'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { getPyodideRuntimeService, PyodideHost } from '../services/PyodideRuntimeService'
import {
  PYODIDE_HOST_HTML,
  PYTHON_CMU_SERIF_BOLD_FONT_URL,
  PYTHON_CMU_SERIF_BOLD_ITALIC_FONT_URL,
  PYTHON_CMU_SERIF_ITALIC_FONT_URL,
  PYTHON_CMU_SERIF_REGULAR_FONT_URL,
  PYTHON_SOURCE_HAN_SERIF_BOLD_FONT_URL,
  PYTHON_SOURCE_HAN_SERIF_BOLD_ITALIC_FONT_URL,
  PYTHON_SOURCE_HAN_SERIF_ITALIC_FONT_URL,
  PYTHON_SOURCE_HAN_SERIF_REGULAR_FONT_URL
} from '../services/PyodideHostHtml'

const DOMAIN = 0x0002
const TAG = 'PyodideWebHost'

// 注入到网页 window.PyodideBridge 的对象，方法由网页 JS 回调
class PyodideBridge {
  onReady(): void {
    getPyodideRuntimeService().onReady()
  }

  onExecutionStart(requestId: string): void {
    getPyodideRuntimeService().onExecutionStart(requestId)
  }

  onResult(requestId: string, json: string): void {
    getPyodideRuntimeService().onResult(requestId, json)
  }

  onError(message: string): void {
    getPyodideRuntimeService().onError(message)
  }
}

// PyodideHost 实现：struct 无法 implements 接口，故由普通类承载，持有 WebView 控制器
class PyodideHostAdapter implements PyodideHost {
  private controller: webview.WebviewController | null = null

  setController(controller: webview.WebviewController): void {
    this.controller = controller
  }

  clearController(): void {
    this.controller = null
  }

  runPython(requestId: string, codeB64: string, varsB64: string, packagesB64: string,
    workspaceB64: string): void {
    const controller = this.controller
    if (controller === null) {
      getPyodideRuntimeService().onError('WebView 控制器未就绪')
      return
    }
    const script = `window.__runPythonB64("${requestId}","${codeB64}","${varsB64}",` +
      `"${packagesB64}","${workspaceB64}")`
    try {
      controller.runJavaScript(script)
    } catch (e) {
      hilog.error(DOMAIN, TAG, `runJavaScript failed: ${JSON.stringify(e)}`)
      getPyodideRuntimeService().onError('触发网页执行失败')
    }
  }

  resetPython(): boolean {
    const controller = this.controller
    if (controller === null) {
      return false
    }
    try {
      controller.runJavaScript('window.__resetPythonRuntime()')
      return true
    } catch (e) {
      hilog.error(DOMAIN, TAG, `reset Python worker failed: ${JSON.stringify(e)}`)
      return false
    }
  }
}

@ComponentV2
export struct PyodideWebHost {
  private controller: webview.WebviewController = new webview.WebviewController()
  private bridge: PyodideBridge = new PyodideBridge()
  private adapter: PyodideHostAdapter = new PyodideHostAdapter()

  // 以 dataURL 内联加载，使页面 origin 为 data:（在 ArkWeb 跨域白名单内），
  // 从而允许访问 jsdelivr CDN 加载 Pyodide WASM/脚本。
  private getDataUrl(): string {
    return 'data:text/html;charset=utf-8,' + encodeURIComponent(PYODIDE_HOST_HTML)
  }

  private createFontResponse(resource: Resource, mimeType: string): WebResourceResponse {
    const response = new WebResourceResponse()
    response.setResponseData(resource)
    response.setResponseEncoding('binary')
    response.setResponseMimeType(mimeType)
    response.setResponseHeader([
      { headerKey: 'Access-Control-Allow-Origin', headerValue: '*' },
      { headerKey: 'Cache-Control', headerValue: 'public, max-age=31536000, immutable' }
    ])
    response.setResponseCode(200)
    response.setReasonMessage('OK')
    response.setResponseIsReady(true)
    return response
  }

  aboutToAppear(): void {
    getPyodideRuntimeService().attachHost(this.adapter)
  }

  aboutToDisappear(): void {
    getPyodideRuntimeService().detachHost(this.adapter)
    this.adapter.clearController()
  }

  build() {
    // 1x1 极小隐藏宿主：仅用于在 WebView 内运行 Pyodide。
    // 用 1x1 而非 0 尺寸，确保 WebView 完成渲染初始化并执行 JS。
    Web({ src: this.getDataUrl(), controller: this.controller })
      .width(1)
      .height(1)
      .opacity(0)
      .hitTestBehavior(HitTestMode.None)
      .javaScriptAccess(true)
      .domStorageAccess(false)
      .onInterceptRequest((event) => {
        if (!event) {
          return null
        }
        const url = event.request.getRequestUrl()
        if (url === PYTHON_CMU_SERIF_REGULAR_FONT_URL) {
          return this.createFontResponse(
            $rawfile('fonts/cmu-serif/fonts_/CMU Serif Roman.ttf'),
            'font/ttf'
          )
        }
        if (url === PYTHON_CMU_SERIF_BOLD_FONT_URL) {
          return this.createFontResponse(
            $rawfile('fonts/cmu-serif/fonts_/CMU Serif Bold Extended Roman.ttf'),
            'font/ttf'
          )
        }
        if (url === PYTHON_CMU_SERIF_ITALIC_FONT_URL) {
          return this.createFontResponse(
            $rawfile('fonts/cmu-serif/fonts_/CMU Serif Italic.ttf'),
            'font/ttf'
          )
        }
        if (url === PYTHON_CMU_SERIF_BOLD_ITALIC_FONT_URL) {
          return this.createFontResponse(
            $rawfile('fonts/cmu-serif/fonts_/CMU Serif Bold Extended Italic.ttf'),
            'font/ttf'
          )
        }
        if (url === PYTHON_SOURCE_HAN_SERIF_REGULAR_FONT_URL) {
          return this.createFontResponse($rawfile('fonts/SourceHanSerifSC-Regular.otf'), 'font/otf')
        }
        if (url === PYTHON_SOURCE_HAN_SERIF_BOLD_FONT_URL) {
          return this.createFontResponse($rawfile('fonts/SourceHanSerifSC-Bold.otf'), 'font/otf')
        }
        if (url === PYTHON_SOURCE_HAN_SERIF_ITALIC_FONT_URL) {
          return this.createFontResponse($rawfile('fonts/SourceHanSerifSC-Italic.ttf'), 'font/ttf')
        }
        if (url === PYTHON_SOURCE_HAN_SERIF_BOLD_ITALIC_FONT_URL) {
          return this.createFontResponse($rawfile('fonts/SourceHanSerifSC-ItalicBold.ttf'), 'font/ttf')
        }
        return null
      })
      .onControllerAttached(() => {
        try {
          this.controller.registerJavaScriptProxy(
            this.bridge,
            'PyodideBridge',
            ['onReady', 'onExecutionStart', 'onResult', 'onError']
          )
          this.adapter.setController(this.controller)
          hilog.info(DOMAIN, TAG, 'Pyodide web controller attached & proxy registered')
        } catch (e) {
          hilog.error(DOMAIN, TAG, `registerJavaScriptProxy failed: ${JSON.stringify(e)}`)
        }
      })
      .onPageEnd((event) => {
        hilog.info(DOMAIN, TAG, `onPageEnd url=${event ? event.url : 'n/a'}`)
      })
      .onConsole((event) => {
        if (event) {
          const msg = event.message
          hilog.info(DOMAIN, TAG, `[web console] ${msg.getMessage()}`)
        }
        return false
      })
      .onErrorReceive((event) => {
        if (event) {
          hilog.error(DOMAIN, TAG,
            `onErrorReceive: ${event.error.getErrorInfo()} url=${event.request.getRequestUrl()}`)
        }
      })
      .onHttpErrorReceive((event) => {
        if (event) {
          hilog.error(DOMAIN, TAG,
            `onHttpErrorReceive: code=${event.response.getResponseCode()} url=${event.request.getRequestUrl()}`)
        }
      })
  }
}
