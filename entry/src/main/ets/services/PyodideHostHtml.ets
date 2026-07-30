// Pyodide 宿主页 HTML。以 dataURL 形式加载（origin 为 data:），
// 规避 ArkWeb 对 resource:// / file:// 页面的跨域拦截——data 协议在 ArkWeb 的
// 跨域白名单内，可正常访问 jsdelivr CDN（其响应头含 access-control-allow-origin: *）。
export const PYODIDE_HOST_HTML: string = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Pyodide Host</title>
  <script src="https://cdn.jsdelivr.net/pyodide/v0.26.4/full/pyodide.js"></script>
</head>
<body>
<script>
  // XCube Pyodide 宿主页：在 ArkWeb(WebView) 里运行真正的 CPython(WASM)。
  // ArkTS 侧通过 runJavaScript 调用 window.__runPythonB64，结果经 PyodideBridge 回调。
  const PYODIDE_INDEX_URL = 'https://cdn.jsdelivr.net/pyodide/v0.26.4/full/';

  let pyodide = null;
  let initialGlobalKeys = null; // Pyodide 启动后的初始全局变量名集合，用于 diff 出用户变量

  // UTF-8 安全的 base64 解码（ArkTS 侧用 base64 传 code/vars，规避引号与换行转义问题）
  function b64ToUtf8(b64) {
    if (!b64) return '';
    const bin = atob(b64);
    const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
    return new TextDecoder('utf-8').decode(bytes);
  }

  // 等待 ArkTS 注册的桥对象注入到 window（registerJavaScriptProxy 时机晚于脚本执行）
  function waitForBridge() {
    return new Promise((resolve) => {
      if (window.PyodideBridge && window.PyodideBridge.onReady) {
        console.log('[pyhost] bridge already present');
        resolve();
        return;
      }
      console.log('[pyhost] waiting for bridge injection...');
      let waited = 0;
      const timer = setInterval(() => {
        waited += 50;
        if (window.PyodideBridge && window.PyodideBridge.onReady) {
          clearInterval(timer);
          console.log('[pyhost] bridge injected after ' + waited + 'ms');
          resolve();
        } else if (waited % 1000 === 0) {
          console.log('[pyhost] still waiting for bridge, ' + waited + 'ms');
        }
      }, 50);
    });
  }

  function safeBridgeError(message) {
    try {
      if (window.PyodideBridge && window.PyodideBridge.onError) {
        window.PyodideBridge.onError(String(message));
      }
    } catch (e) {
      // ignore
    }
  }

  async function bootstrap() {
    console.log('[pyhost] bootstrap start; loadPyodide type=' + (typeof loadPyodide));
    await waitForBridge();
    if (typeof loadPyodide !== 'function') {
      safeBridgeError('pyodide.js 脚本未加载（CDN 不可达？loadPyodide 未定义）');
      return;
    }
    try {
      console.log('[pyhost] calling loadPyodide from ' + PYODIDE_INDEX_URL);
      pyodide = await loadPyodide({ indexURL: PYODIDE_INDEX_URL });
      console.log('[pyhost] loadPyodide done');
      // 记录初始全局变量名，之后据此识别用户新增/修改的变量
      const keys = pyodide.runPython('list(globals().keys())').toJs();
      initialGlobalKeys = new Set(keys);
      console.log('[pyhost] onReady');
      window.PyodideBridge.onReady();
    } catch (e) {
      safeBridgeError('Pyodide 加载失败: ' + (e && e.message ? e.message : e));
    }
  }

  // 收集用户定义的、可 JSON 序列化的变量（排除内置项、下划线开头、函数/模块/类）
  function collectVariables() {
    if (!pyodide || !initialGlobalKeys) return {};
    const out = {};
    let names = [];
    try {
      names = pyodide.runPython('list(globals().keys())').toJs();
    } catch (e) {
      return out;
    }
    for (const name of names) {
      if (typeof name !== 'string') continue;
      if (name.startsWith('_')) continue;
      if (initialGlobalKeys.has(name)) continue;
      let proxy = null;
      try {
        proxy = pyodide.globals.get(name);
        if (proxy === undefined || proxy === null) continue;
        // 跳过 callable / module 等不可序列化对象
        const t = typeof proxy;
        if (t === 'function') continue;
        let jsVal;
        if (proxy && typeof proxy.toJs === 'function') {
          jsVal = proxy.toJs();
        } else {
          jsVal = proxy;
        }
        // 试探是否可 JSON 序列化
        JSON.stringify(jsVal);
        out[name] = jsVal;
      } catch (e) {
        // 不可序列化的变量跳过
      } finally {
        if (proxy && typeof proxy.destroy === 'function') {
          try { proxy.destroy(); } catch (e) {}
        }
      }
    }
    return out;
  }

  // ArkTS 调用入口：requestId 标识本次请求，codeB64/varsB64 为 base64 编码的代码与变量
  window.__runPythonB64 = async function (requestId, codeB64, varsB64) {
    const result = { ok: true, stdout: [], result: '', variables: {}, warnings: [], error: '' };

    if (!pyodide) {
      result.ok = false;
      result.error = 'Pyodide 尚未就绪';
      sendResult(requestId, result);
      return;
    }

    const stdout = [];
    pyodide.setStdout({ batched: (s) => stdout.push(s) });
    pyodide.setStderr({ batched: (s) => stdout.push(s) });

    try {
      const code = b64ToUtf8(codeB64);
      const varsJson = b64ToUtf8(varsB64);
      // 注入入参变量到全局
      if (varsJson) {
        let vars = {};
        try { vars = JSON.parse(varsJson); } catch (e) { vars = {}; }
        for (const k of Object.keys(vars)) {
          if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(k)) {
            pyodide.globals.set(k, pyodide.toPy(vars[k]));
          }
        }
      }

      const ret = await pyodide.runPythonAsync(code);
      result.stdout = stdout;
      if (ret !== undefined && ret !== null) {
        if (typeof ret.toString === 'function') {
          result.result = ret.toString();
        } else {
          result.result = String(ret);
        }
        if (typeof ret.destroy === 'function') {
          try { ret.destroy(); } catch (e) {}
        }
      }
      result.variables = collectVariables();
    } catch (e) {
      result.ok = false;
      result.stdout = stdout;
      result.error = (e && e.message) ? e.message : String(e);
    }
    sendResult(requestId, result);
  };

  function sendResult(requestId, result) {
    try {
      window.PyodideBridge.onResult(requestId, JSON.stringify(result));
    } catch (e) {
      safeBridgeError('回传结果失败: ' + (e && e.message ? e.message : e));
    }
  }

  window.addEventListener('error', (ev) => {
    safeBridgeError('页面错误: ' + (ev && ev.message ? ev.message : 'unknown'));
  });

  bootstrap();
</script>
</body>
</html>`
