export const PYODIDE_VERSION: string = '314.0.6'
export const PYODIDE_INDEX_URL: string = `https://cdn.jsdelivr.net/pyodide/v${PYODIDE_VERSION}/full/`
// 314.x requires module workers. ArkWeb versions that cannot load a cross-origin
// module from a Blob worker fall back to the newest pre-314 classic-worker runtime.
export const PYODIDE_COMPAT_VERSION: string = '0.29.4'
export const PYODIDE_COMPAT_INDEX_URL: string =
  `https://cdn.jsdelivr.net/pyodide/v${PYODIDE_COMPAT_VERSION}/full/`

// The page itself only coordinates ArkTS and a dedicated worker. Python never runs on
// the WebView main thread, so a timed-out worker can be terminated without freezing the host.
export const PYODIDE_HOST_HTML: string = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>XCube Python Host</title>
</head>
<body>
<script id="python-worker-source" type="javascript/worker">
  import { loadPyodide as runtimeLoader } from '${PYODIDE_INDEX_URL}pyodide.mjs';

  const PYODIDE_INDEX_URL = '${PYODIDE_INDEX_URL}';
  const PACKAGE_NETWORK_HOSTS = new Set(['cdn.jsdelivr.net', 'pypi.org', 'files.pythonhosted.org']);

  const hostPostMessage = self.postMessage.bind(self);
  const nativeFetch = typeof self.fetch === 'function' ? self.fetch.bind(self) : null;
  let packageNetworkAllowed = true;
  let controlToken = '';
  let pyodide = null;
  let initialGlobalKeys = null;

  function postHostMessage(message) {
    message.controlToken = controlToken;
    hostPostMessage(message);
  }

  function b64ToUtf8(b64) {
    if (!b64) return '';
    const bin = atob(b64);
    const bytes = Uint8Array.from(bin, (char) => char.charCodeAt(0));
    return new TextDecoder('utf-8').decode(bytes);
  }

  function parseRequestedPackages(packagesB64) {
    if (!packagesB64) return [];
    try {
      const parsed = JSON.parse(b64ToUtf8(packagesB64));
      if (!Array.isArray(parsed)) return [];
      return parsed.filter((item) => typeof item === 'string' && item.length > 0 && item.length <= 128 &&
        !item.includes('/') && !item.includes('\\\\') && !item.includes('@') && !item.includes(':'));
    } catch (e) {
      return [];
    }
  }

  function isAllowedPackageRequest(input, init) {
    if (!packageNetworkAllowed) return false;
    const method = init && init.method ? String(init.method).toUpperCase() : 'GET';
    if (method !== 'GET' && method !== 'HEAD') return false;
    try {
      const rawUrl = typeof input === 'string' ? input : input.url;
      const url = new URL(rawUrl, PYODIDE_INDEX_URL);
      return url.protocol === 'https:' && PACKAGE_NETWORK_HOSTS.has(url.hostname);
    } catch (e) {
      return false;
    }
  }

  if (nativeFetch !== null) {
    self.fetch = function (input, init) {
      if (!isAllowedPackageRequest(input, init)) {
        return Promise.reject(new Error('Python 沙箱禁止用户代码直接访问网络'));
      }
      return nativeFetch(input, init);
    };
  }

  function deniedCapability(name) {
    return function () {
      throw new Error('Python 沙箱不允许访问 ' + name);
    };
  }

  function hideGlobal(name) {
    try {
      Object.defineProperty(self, name, { configurable: false, writable: false, value: undefined });
    } catch (e) {
      try { self[name] = undefined; } catch (ignored) {}
    }
  }

  function lockWorkerCapabilities() {
    // Package downloads use the guarded fetch above. Other network, code-loading and
    // persistent browser APIs are unavailable to model-generated Python code.
    self.importScripts = deniedCapability('importScripts');
    self.XMLHttpRequest = deniedCapability('XMLHttpRequest');
    self.WebSocket = deniedCapability('WebSocket');
    self.EventSource = deniedCapability('EventSource');
    self.Worker = deniedCapability('Worker');
    self.SharedWorker = deniedCapability('SharedWorker');
    // Keep the JavaScript scheduler primitives intact: Pyodide's webloop and FFI
    // call them after initialization. Outbound messages are authenticated instead.
    hideGlobal('loadPyodide');
    hideGlobal('indexedDB');
    hideGlobal('caches');
  }

  function collectVariables() {
    if (!pyodide || !initialGlobalKeys) return {};
    let serialized = null;
    try {
      // Never call toJs() blindly on modules, DataFrames or arbitrary user objects.
      // Only bounded, exact built-in JSON types are copied out of the sandbox.
      const script = [
        'import json as _xcube_json',
        'import math as _xcube_math',
        '_xcube_skip = object()',
        '_xcube_baseline = set(' + JSON.stringify(Array.from(initialGlobalKeys)) + ')',
        'def _xcube_safe(value, depth=0):',
        '    value_type = type(value)',
        '    if value_type in (type(None), bool, int, str):',
        '        return value',
        '    if value_type is float:',
        '        return value if _xcube_math.isfinite(value) else str(value)',
        '    if depth >= 4:',
        '        return _xcube_skip',
        '    if value_type in (list, tuple):',
        '        if len(value) > 200:',
        '            return _xcube_skip',
        '        converted = []',
        '        for item in value:',
        '            safe_item = _xcube_safe(item, depth + 1)',
        '            if safe_item is _xcube_skip:',
        '                return _xcube_skip',
        '            converted.append(safe_item)',
        '        return converted',
        '    if value_type is dict:',
        '        if len(value) > 200:',
        '            return _xcube_skip',
        '        converted = {}',
        '        for key, item in value.items():',
        '            if type(key) is not str:',
        '                return _xcube_skip',
        '            safe_item = _xcube_safe(item, depth + 1)',
        '            if safe_item is _xcube_skip:',
        '                return _xcube_skip',
        '            converted[key] = safe_item',
        '        return converted',
        '    return _xcube_skip',
        '_xcube_out = {}',
        'for _xcube_name, _xcube_value in list(globals().items()):',
        '    if _xcube_name.startswith("_") or _xcube_name in _xcube_baseline:',
        '        continue',
        '    _xcube_value_safe = _xcube_safe(_xcube_value)',
        '    if _xcube_value_safe is not _xcube_skip:',
        '        _xcube_out[_xcube_name] = _xcube_value_safe',
        '_xcube_json.dumps(_xcube_out, ensure_ascii=False, allow_nan=False)'
      ].join('\\n');
      serialized = pyodide.runPython(script);
      return JSON.parse(String(serialized));
    } catch (e) {
      return {};
    } finally {
      if (serialized && typeof serialized.destroy === 'function') {
        try { serialized.destroy(); } catch (e) {}
      }
    }
  }

  function packageCallbacks(requestId, warnings) {
    return {
      messageCallback: (message) => postHostMessage({
        type: 'packageMessage', requestId: requestId, message: String(message)
      }),
      errorCallback: (message) => warnings.push(String(message))
    };
  }

  async function installRequestedPackages(requestId, packages, warnings) {
    if (packages.length === 0) return;
    const callbacks = packageCallbacks(requestId, warnings);
    await pyodide.loadPackage('micropip', callbacks);
    const micropip = pyodide.pyimport('micropip');
    try {
      for (const packageSpec of packages) {
        postHostMessage({
          type: 'packageMessage', requestId: requestId, message: 'Installing ' + packageSpec
        });
        await micropip.install(packageSpec);
      }
    } finally {
      if (micropip && typeof micropip.destroy === 'function') micropip.destroy();
    }
  }

  async function runPython(request) {
    const result = { ok: true, stdout: [], result: '', variables: {}, warnings: [], error: '' };
    if (!pyodide) {
      result.ok = false;
      result.error = 'Pyodide 尚未就绪';
      postHostMessage({ type: 'result', requestId: request.requestId, result: result });
      return;
    }

    const stdout = [];
    pyodide.setStdout({ batched: (message) => stdout.push(message) });
    pyodide.setStderr({ batched: (message) => stdout.push(message) });

    try {
      const code = b64ToUtf8(request.codeB64);
      const variablesJson = b64ToUtf8(request.varsB64);
      const requestedPackages = parseRequestedPackages(request.packagesB64);

      packageNetworkAllowed = true;
      try {
        await pyodide.loadPackagesFromImports(code, packageCallbacks(request.requestId, result.warnings));
        await installRequestedPackages(request.requestId, requestedPackages, result.warnings);
      } finally {
        packageNetworkAllowed = false;
      }

      postHostMessage({ type: 'executionStarted', requestId: request.requestId });

      if (variablesJson) {
        let variables = {};
        try { variables = JSON.parse(variablesJson); } catch (e) { variables = {}; }
        for (const key of Object.keys(variables)) {
          if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
            pyodide.globals.set(key, pyodide.toPy(variables[key]));
          }
        }
      }

      const returned = await pyodide.runPythonAsync(code);
      result.stdout = stdout;
      if (returned !== undefined && returned !== null) {
        result.result = typeof returned.toString === 'function' ? returned.toString() : String(returned);
        if (typeof returned.destroy === 'function') {
          try { returned.destroy(); } catch (e) {}
        }
      }
      result.variables = collectVariables();
    } catch (e) {
      packageNetworkAllowed = false;
      result.ok = false;
      result.stdout = stdout;
      result.error = e && e.message ? e.message : String(e);
    }
    postHostMessage({ type: 'result', requestId: request.requestId, result: result });
  }

  async function initializeRuntime() {
    try {
      if (typeof runtimeLoader !== 'function') {
        throw new Error('pyodide.mjs 未在模块 Worker 内完成初始化');
      }
      pyodide = await runtimeLoader({ indexURL: PYODIDE_INDEX_URL });
      packageNetworkAllowed = false;
      lockWorkerCapabilities();
      // Do not report ready until the asynchronous Python/JavaScript bridge itself
      // has executed successfully. A synchronous load alone cannot catch webloop breakage.
      await pyodide.runPythonAsync('import math\\nassert math.sqrt(81) == 9');
      const keysProxy = pyodide.runPython('list(globals().keys())');
      initialGlobalKeys = new Set(keysProxy.toJs());
      keysProxy.destroy();
      postHostMessage({ type: 'ready' });
    } catch (e) {
      packageNetworkAllowed = false;
      postHostMessage({ type: 'fatalError', message: 'Pyodide 加载失败: ' +
        (e && e.message ? e.message : String(e)) });
    }
  }

  self.addEventListener('message', (event) => {
    const message = event.data || {};
    if (message.type === 'initialize' && controlToken === '') {
      controlToken = String(message.controlToken || '');
      if (controlToken !== '') initializeRuntime();
      return;
    }
    if (message.controlToken !== controlToken || controlToken === '') return;
    if (message.type === 'run') runPython(message);
  });
</script>
<script>
  const PYODIDE_CURRENT_INDEX_URL = '${PYODIDE_INDEX_URL}';
  const PYODIDE_COMPAT_INDEX_URL = '${PYODIDE_COMPAT_INDEX_URL}';
  const PYODIDE_COMPAT_SCRIPT_URL = PYODIDE_COMPAT_INDEX_URL + 'pyodide.js';
  let pythonWorker = null;
  let workerGeneration = 0;
  let currentControlToken = '';
  let preferredWorkerMode = 'module';
  let compatibilityRuntimeSourcePromise = null;

  function waitForBridge() {
    return new Promise((resolve) => {
      if (window.PyodideBridge && window.PyodideBridge.onReady) {
        resolve();
        return;
      }
      const timer = setInterval(() => {
        if (window.PyodideBridge && window.PyodideBridge.onReady) {
          clearInterval(timer);
          resolve();
        }
      }, 50);
    });
  }

  function safeBridgeError(message) {
    try {
      if (window.PyodideBridge && window.PyodideBridge.onError) {
        window.PyodideBridge.onError(String(message));
      }
    } catch (e) {}
  }

  function createControlToken() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
      return window.crypto.randomUUID();
    }
    return String(Date.now()) + '-' + String(Math.random()).substring(2);
  }

  function loadCompatibilityRuntimeSource() {
    if (compatibilityRuntimeSourcePromise === null) {
      compatibilityRuntimeSourcePromise = fetch(PYODIDE_COMPAT_SCRIPT_URL, {
        method: 'GET', cache: 'force-cache'
      }).then((response) => {
        if (!response.ok) {
          throw new Error('下载兼容版 pyodide.js 失败，HTTP ' + String(response.status));
        }
        return response.text();
      }).catch((error) => {
        compatibilityRuntimeSourcePromise = null;
        throw error;
      });
    }
    return compatibilityRuntimeSourcePromise;
  }

  function configureWorker(worker, generation, mode) {
    worker.onmessage = (event) => {
      if (generation !== workerGeneration || worker !== pythonWorker) return;
      const message = event.data || {};
      if (message.controlToken !== currentControlToken) return;
      if (message.type === 'ready') {
        window.PyodideBridge.onReady();
      } else if (message.type === 'executionStarted') {
        window.PyodideBridge.onExecutionStart(String(message.requestId || ''));
      } else if (message.type === 'packageMessage') {
        console.log('[pyhost] ' + String(message.message || ''));
      } else if (message.type === 'result') {
        window.PyodideBridge.onResult(String(message.requestId || ''), JSON.stringify(message.result));
      } else if (message.type === 'fatalError') {
        if (mode === 'module') {
          preferredWorkerMode = 'classic';
          startCompatibilityWorker(generation).catch((error) => {
            safeBridgeError('Pyodide 模块版和 ArkWeb 兼容版均加载失败: ' + String(error));
          });
        } else {
          safeBridgeError(String(message.message || 'Python Worker 初始化失败'));
        }
      }
    };
    worker.onerror = (event) => {
      if (generation !== workerGeneration || worker !== pythonWorker) return;
      const detail = event && event.message ? event.message :
        (mode === 'module' ? '模块脚本加载失败（ArkWeb 未提供详细信息）' :
          '兼容运行时脚本加载失败（ArkWeb 未提供详细信息）');
      if (mode === 'module') {
        if (event && typeof event.preventDefault === 'function') event.preventDefault();
        preferredWorkerMode = 'classic';
        startCompatibilityWorker(generation).catch((error) => {
          safeBridgeError('Pyodide 模块版和 ArkWeb 兼容版均加载失败: ' + detail + '; ' + String(error));
        });
      } else {
        safeBridgeError('Python Worker 错误: ' + detail);
      }
    };
  }

  async function startCompatibilityWorker(previousGeneration) {
    if (previousGeneration !== workerGeneration) return;
    if (pythonWorker !== null) {
      pythonWorker.terminate();
      pythonWorker = null;
    }
    workerGeneration += 1;
    const generation = workerGeneration;
    currentControlToken = createControlToken();
    let workerSource = document.getElementById('python-worker-source').textContent;
    const importEnd = workerSource.indexOf(';');
    if (importEnd < 0) throw new Error('无法生成 ArkWeb 兼容 Worker');
    workerSource = workerSource.substring(importEnd + 1)
      .split(PYODIDE_CURRENT_INDEX_URL).join(PYODIDE_COMPAT_INDEX_URL)
      .split('runtimeLoader').join('__xcubeRuntimeLoaderCompat');
    const runtimeSource = await loadCompatibilityRuntimeSource();
    if (generation !== workerGeneration) return;
    const classicSource = runtimeSource +
      '\\n;(function () {\\nconst __xcubeRuntimeLoaderCompat = self.loadPyodide;\\n' +
      workerSource + '\\n})();\\n';
    const workerUrl = URL.createObjectURL(new Blob([classicSource], { type: 'text/javascript' }));
    const worker = new Worker(workerUrl);
    URL.revokeObjectURL(workerUrl);
    pythonWorker = worker;
    configureWorker(worker, generation, 'classic');
    worker.postMessage({ type: 'initialize', controlToken: currentControlToken });
  }

  function startPythonWorker() {
    if (pythonWorker !== null) {
      pythonWorker.terminate();
      pythonWorker = null;
    }
    workerGeneration += 1;
    const generation = workerGeneration;
    currentControlToken = createControlToken();

    if (preferredWorkerMode === 'classic') {
      startCompatibilityWorker(generation).catch((error) => {
        safeBridgeError('ArkWeb 兼容版 Pyodide 加载失败: ' + String(error));
      });
      return;
    }

    const workerSource = document.getElementById('python-worker-source').textContent;
    const workerUrl = URL.createObjectURL(new Blob([workerSource], { type: 'text/javascript' }));
    // Pyodide 314.x uses an ES module runtime and explicitly rejects classic workers.
    const worker = new Worker(workerUrl, { type: 'module' });
    URL.revokeObjectURL(workerUrl);
    pythonWorker = worker;
    configureWorker(worker, generation, 'module');
    worker.postMessage({ type: 'initialize', controlToken: currentControlToken });
  }

  window.__runPythonB64 = function (requestId, codeB64, varsB64, packagesB64) {
    if (pythonWorker === null) {
      safeBridgeError('Python Worker 尚未就绪');
      return;
    }
    pythonWorker.postMessage({
      type: 'run',
      controlToken: currentControlToken,
      requestId: requestId,
      codeB64: codeB64,
      varsB64: varsB64,
      packagesB64: packagesB64
    });
  };

  window.__resetPythonRuntime = function () {
    try {
      startPythonWorker();
    } catch (error) {
      safeBridgeError(String(error));
    }
  };

  window.addEventListener('error', (event) => {
    safeBridgeError('页面错误: ' + (event && event.message ? event.message : 'unknown'));
  });

  waitForBridge().then(() => {
    try {
      startPythonWorker();
    } catch (error) {
      safeBridgeError(String(error));
    }
  });
</script>
</body>
</html>`
