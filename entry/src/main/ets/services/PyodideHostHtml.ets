import {
  PYTHON_MAX_OUTPUT_FILES,
  PYTHON_MAX_OUTPUT_FILE_BYTES,
  PYTHON_MAX_OUTPUT_FILE_TOTAL_BYTES,
  PYTHON_MAX_OUTPUT_IMAGES,
  PYTHON_MAX_OUTPUT_IMAGE_BYTES,
  PYTHON_MAX_OUTPUT_IMAGE_TOTAL_BYTES
} from './PythonSandboxRuntimePolicy'

export const PYODIDE_VERSION: string = '314.0.6'
export const PYODIDE_INDEX_URL: string = `https://cdn.jsdelivr.net/pyodide/v${PYODIDE_VERSION}/full/`
// 314.x requires module workers. ArkWeb versions that cannot load a cross-origin
// module from a Blob worker fall back to the newest pre-314 classic-worker runtime.
export const PYODIDE_COMPAT_VERSION: string = '0.29.4'
export const PYODIDE_COMPAT_INDEX_URL: string =
  `https://cdn.jsdelivr.net/pyodide/v${PYODIDE_COMPAT_VERSION}/full/`
export const PYTHON_CMU_SERIF_FONT_URL: string =
  'https://python-fonts.xcube.invalid/CMUSerif-Regular.ttf'
export const PYTHON_SOURCE_HAN_SERIF_FONT_URL: string =
  'https://python-fonts.xcube.invalid/SourceHanSerifSC-Regular.otf'
export const PYTHON_CMU_SERIF_FONT_PATH: string = '/usr/share/fonts/xcube/CMUSerif-Regular.ttf'
export const PYTHON_SOURCE_HAN_SERIF_FONT_PATH: string =
  '/usr/share/fonts/xcube/SourceHanSerifSC-Regular.otf'
export const PYTHON_FPDF_IMPORT_NAME: string = 'fpdf'
export const PYTHON_FPDF_PACKAGE_NAME: string = 'fpdf2'

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
  const BUILTIN_FONT_URLS = new Set([
    '${PYTHON_CMU_SERIF_FONT_URL}',
    '${PYTHON_SOURCE_HAN_SERIF_FONT_URL}'
  ]);
  const BUILTIN_FONTS = [
    { url: '${PYTHON_CMU_SERIF_FONT_URL}', path: '${PYTHON_CMU_SERIF_FONT_PATH}' },
    { url: '${PYTHON_SOURCE_HAN_SERIF_FONT_URL}', path: '${PYTHON_SOURCE_HAN_SERIF_FONT_PATH}' }
  ];
  const AUTO_PACKAGE_BY_IMPORT = new Map([
    ['${PYTHON_FPDF_IMPORT_NAME}', '${PYTHON_FPDF_PACKAGE_NAME}']
  ]);
  const PYTHON_FONT_ROOT = '/usr/share/fonts/xcube';
  const PYTHON_OUTPUT_ROOT = '/tmp/xcube-python-output';
  const MAX_OUTPUT_IMAGES = ${PYTHON_MAX_OUTPUT_IMAGES};
  const MAX_OUTPUT_IMAGE_BYTES = ${PYTHON_MAX_OUTPUT_IMAGE_BYTES};
  const MAX_OUTPUT_IMAGE_TOTAL_BYTES = ${PYTHON_MAX_OUTPUT_IMAGE_TOTAL_BYTES};
  const MAX_OUTPUT_FILES = ${PYTHON_MAX_OUTPUT_FILES};
  const MAX_OUTPUT_FILE_BYTES = ${PYTHON_MAX_OUTPUT_FILE_BYTES};
  const MAX_OUTPUT_FILE_TOTAL_BYTES = ${PYTHON_MAX_OUTPUT_FILE_TOTAL_BYTES};
  const MAX_OUTPUT_DIRECTORY_ENTRIES = 64;
  const MAX_OUTPUT_DIRECTORY_DEPTH = 4;

  const hostPostMessage = self.postMessage.bind(self);
  const nativeFetch = typeof self.fetch === 'function' ? self.fetch.bind(self) : null;
  let packageNetworkAllowed = true;
  let builtinFontNetworkAllowed = true;
  let controlToken = '';
  let pyodide = null;
  let initialGlobalKeys = null;
  let builtinFontWarning = '';
  let matplotlibFontsConfigured = false;

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

  function isAllowedBuiltinFontRequest(input, init) {
    if (!builtinFontNetworkAllowed) return false;
    const method = init && init.method ? String(init.method).toUpperCase() : 'GET';
    if (method !== 'GET' && method !== 'HEAD') return false;
    try {
      const rawUrl = typeof input === 'string' ? input : input.url;
      return BUILTIN_FONT_URLS.has(new URL(rawUrl).href);
    } catch (e) {
      return false;
    }
  }

  if (nativeFetch !== null) {
    self.fetch = function (input, init) {
      if (!isAllowedPackageRequest(input, init) && !isAllowedBuiltinFontRequest(input, init)) {
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

  function joinOutputPath(parent, child) {
    return parent.endsWith('/') ? parent + child : parent + '/' + child;
  }

  function removeOutputDirectory(path) {
    if (!pyodide || !pyodide.FS) return;
    let entries = [];
    try { entries = pyodide.FS.readdir(path); } catch (e) { return; }
    for (const name of entries) {
      if (name === '.' || name === '..') continue;
      const childPath = joinOutputPath(path, name);
      try {
        const stat = pyodide.FS.lstat(childPath);
        if (pyodide.FS.isDir(stat.mode) && !pyodide.FS.isLink(stat.mode)) {
          removeOutputDirectory(childPath);
        } else {
          pyodide.FS.unlink(childPath);
        }
      } catch (e) {}
    }
    try { pyodide.FS.rmdir(path); } catch (e) {}
  }

  function prepareOutputDirectory(requestId) {
    const safeRequestId = String(requestId || 'run').replace(/[^A-Za-z0-9_-]/g, '_');
    const outputDir = joinOutputPath(PYTHON_OUTPUT_ROOT, safeRequestId);
    const previousCwd = pyodide.FS.cwd();
    removeOutputDirectory(outputDir);
    pyodide.FS.mkdirTree(outputDir);
    pyodide.FS.chdir(outputDir);
    pyodide.globals.set('PYTHON_OUTPUT_DIR', outputDir);
    return { outputDir: outputDir, previousCwd: previousCwd };
  }

  function detectImageMime(bytes) {
    if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e &&
      bytes[3] === 0x47 && bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a &&
      bytes[7] === 0x0a) {
      return 'image/png';
    }
    if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 6 && bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46 &&
      bytes[3] === 0x38 && (bytes[4] === 0x37 || bytes[4] === 0x39) && bytes[5] === 0x61) {
      return 'image/gif';
    }
    if (bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 &&
      bytes[3] === 0x46 && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 &&
      bytes[11] === 0x50) {
      return 'image/webp';
    }
    return '';
  }

  function detectFileMime(bytes, name) {
    if (bytes.length >= 5 && bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 &&
      bytes[3] === 0x46 && bytes[4] === 0x2d) {
      return 'application/pdf';
    }
    const normalizedName = String(name || '').toLowerCase();
    const dotIndex = normalizedName.lastIndexOf('.');
    const extension = dotIndex >= 0 ? normalizedName.substring(dotIndex + 1) : '';
    const mimeByExtension = {
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'md': 'text/markdown',
      'csv': 'text/csv',
      'json': 'application/json',
      'xml': 'application/xml',
      'html': 'text/html',
      'htm': 'text/html',
      'svg': 'image/svg+xml',
      'zip': 'application/zip',
      'gz': 'application/gzip',
      'tar': 'application/x-tar',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
    };
    const detectedMime = mimeByExtension[extension];
    return typeof detectedMime === 'string' ? detectedMime : 'application/octet-stream';
  }

  function bytesToBase64(bytes) {
    let binary = '';
    const chunkSize = 0x8000;
    for (let offset = 0; offset < bytes.length; offset += chunkSize) {
      const end = Math.min(offset + chunkSize, bytes.length);
      let chunk = '';
      for (let index = offset; index < end; index++) {
        chunk += String.fromCharCode(bytes[index]);
      }
      binary += chunk;
    }
    return btoa(binary);
  }

  function collectOutputArtifacts(outputDir, warnings) {
    const candidates = [];
    let visitedEntries = 0;

    function walk(path, relativePath, depth) {
      if (depth > MAX_OUTPUT_DIRECTORY_DEPTH || visitedEntries >= MAX_OUTPUT_DIRECTORY_ENTRIES) return;
      let entries = [];
      try { entries = pyodide.FS.readdir(path).slice().sort(); } catch (e) { return; }
      for (const name of entries) {
        if (name === '.' || name === '..' || visitedEntries >= MAX_OUTPUT_DIRECTORY_ENTRIES) continue;
        visitedEntries += 1;
        const childPath = joinOutputPath(path, name);
        const childRelativePath = relativePath === '' ? name : relativePath + '/' + name;
        try {
          const stat = pyodide.FS.lstat(childPath);
          if (pyodide.FS.isLink(stat.mode)) continue;
          if (pyodide.FS.isDir(stat.mode)) {
            walk(childPath, childRelativePath, depth + 1);
          } else if (pyodide.FS.isFile(stat.mode)) {
            candidates.push({ path: childPath, name: childRelativePath, size: Number(stat.size) });
          }
        } catch (e) {}
      }
    }

    walk(outputDir, '', 0);
    if (visitedEntries >= MAX_OUTPUT_DIRECTORY_ENTRIES) {
      warnings.push('Python 输出目录文件过多，仅检查前 ' + MAX_OUTPUT_DIRECTORY_ENTRIES + ' 项');
    }

    const artifacts = [];
    let imageCount = 0;
    let imageTotalBytes = 0;
    let fileCount = 0;
    let fileTotalBytes = 0;
    let warnedImageCount = false;
    let warnedFileCount = false;
    for (const candidate of candidates) {
      if (candidate.size <= 0) continue;
      if (candidate.size > Math.max(MAX_OUTPUT_IMAGE_BYTES, MAX_OUTPUT_FILE_BYTES)) {
        warnings.push('文件 ' + candidate.name + ' 超过单文件大小限制，已忽略');
        continue;
      }
      try {
        const bytes = pyodide.FS.readFile(candidate.path, { encoding: 'binary' });
        const imageMimeType = detectImageMime(bytes);
        const isImage = imageMimeType !== '';
        if (isImage) {
          if (imageCount >= MAX_OUTPUT_IMAGES) {
            if (!warnedImageCount) {
              warnings.push('Python 最多保存 ' + MAX_OUTPUT_IMAGES + ' 张图片，其余图片已忽略');
              warnedImageCount = true;
            }
            continue;
          }
          if (bytes.byteLength > MAX_OUTPUT_IMAGE_BYTES) {
            warnings.push('图片 ' + candidate.name + ' 超过单图 ' + MAX_OUTPUT_IMAGE_BYTES + ' 字节限制，已忽略');
            continue;
          }
          if (imageTotalBytes + bytes.byteLength > MAX_OUTPUT_IMAGE_TOTAL_BYTES) {
            warnings.push('Python 图片总大小超过 ' + MAX_OUTPUT_IMAGE_TOTAL_BYTES + ' 字节限制，该图片已忽略');
            continue;
          }
        } else {
          if (fileCount >= MAX_OUTPUT_FILES) {
            if (!warnedFileCount) {
              warnings.push('Python 最多保存 ' + MAX_OUTPUT_FILES + ' 个普通文件，其余文件已忽略');
              warnedFileCount = true;
            }
            continue;
          }
          if (bytes.byteLength > MAX_OUTPUT_FILE_BYTES) {
            warnings.push('文件 ' + candidate.name + ' 超过单文件 ' + MAX_OUTPUT_FILE_BYTES + ' 字节限制，已忽略');
            continue;
          }
          if (fileTotalBytes + bytes.byteLength > MAX_OUTPUT_FILE_TOTAL_BYTES) {
            warnings.push('Python 文件总大小超过 ' + MAX_OUTPUT_FILE_TOTAL_BYTES + ' 字节限制，该文件已忽略');
            continue;
          }
        }
        artifacts.push({
          name: candidate.name,
          kind: isImage ? 'image' : 'file',
          mimeType: isImage ? imageMimeType : detectFileMime(bytes, candidate.name),
          size: bytes.byteLength,
          data: bytesToBase64(bytes)
        });
        if (isImage) {
          imageCount += 1;
          imageTotalBytes += bytes.byteLength;
        } else {
          fileCount += 1;
          fileTotalBytes += bytes.byteLength;
        }
      } catch (e) {
        warnings.push('读取 Python 产物 ' + candidate.name + ' 失败');
      }
    }
    return artifacts;
  }

  function packageCallbacks(requestId, warnings) {
    return {
      messageCallback: (message) => postHostMessage({
        type: 'packageMessage', requestId: requestId, message: String(message)
      }),
      errorCallback: (message) => warnings.push(String(message))
    };
  }

  function normalizeDistributionName(packageSpec) {
    const match = String(packageSpec).trim().match(/^[A-Za-z0-9][A-Za-z0-9._-]*/);
    return match ? match[0].replace(/[._-]+/g, '-').toLowerCase() : '';
  }

  function resolveAutoPackages(code, requestedPackages, warnings) {
    const packages = requestedPackages.slice();
    let codeModule = null;
    let importsProxy = null;
    try {
      codeModule = pyodide.pyimport('pyodide.code');
      importsProxy = codeModule.find_imports(code);
      const importedModules = importsProxy.toJs();
      AUTO_PACKAGE_BY_IMPORT.forEach((packageName, importName) => {
        if (!importedModules.includes(importName)) return;
        const alreadyRequested = packages.some((packageSpec) =>
          normalizeDistributionName(packageSpec) === normalizeDistributionName(packageName));
        if (!alreadyRequested) packages.push(packageName);
      });
    } catch (e) {
      warnings.push('自动解析 Python 第三方包失败: ' + (e && e.message ? e.message : String(e)));
    } finally {
      if (importsProxy && typeof importsProxy.destroy === 'function') importsProxy.destroy();
      if (codeModule && typeof codeModule.destroy === 'function') codeModule.destroy();
    }
    return packages;
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

  async function installBuiltinFonts() {
    if (nativeFetch === null) {
      throw new Error('当前 Worker 不支持读取内置字体');
    }
    pyodide.FS.mkdirTree(PYTHON_FONT_ROOT);
    const failures = [];
    for (const font of BUILTIN_FONTS) {
      try {
        const response = await self.fetch(font.url, { method: 'GET', cache: 'force-cache' });
        if (!response.ok) {
          throw new Error('HTTP ' + String(response.status));
        }
        const bytes = new Uint8Array(await response.arrayBuffer());
        if (bytes.byteLength === 0) {
          throw new Error('字体文件为空');
        }
        pyodide.FS.writeFile(font.path, bytes);
      } catch (e) {
        failures.push(font.path + ': ' + (e && e.message ? e.message : String(e)));
      }
    }

    pyodide.globals.set('PYTHON_FONT_DIR', PYTHON_FONT_ROOT);
    pyodide.globals.set('PYTHON_FONT_EN', '${PYTHON_CMU_SERIF_FONT_PATH}');
    pyodide.globals.set('PYTHON_FONT_CJK', '${PYTHON_SOURCE_HAN_SERIF_FONT_PATH}');
    pyodide.runPython([
      'import os as _xcube_os',
      "_xcube_os.environ['XCUBE_PYTHON_FONT_DIR'] = '" + PYTHON_FONT_ROOT + "'",
      "_xcube_os.environ['XCUBE_PYTHON_FONT_EN'] = '${PYTHON_CMU_SERIF_FONT_PATH}'",
      "_xcube_os.environ['XCUBE_PYTHON_FONT_CJK'] = '${PYTHON_SOURCE_HAN_SERIF_FONT_PATH}'"
    ].join('\\n'));
    if (failures.length > 0) {
      throw new Error(failures.join('; '));
    }
  }

  function configureMatplotlibFonts(warnings) {
    if (matplotlibFontsConfigured) return;
    let configured = null;
    try {
      configured = pyodide.runPython([
        'import importlib.util as _xcube_importlib_util',
        'import os as _xcube_os',
        "_xcube_has_matplotlib = _xcube_importlib_util.find_spec('matplotlib') is not None",
        'if _xcube_has_matplotlib:',
        '    import matplotlib as _xcube_matplotlib',
        '    from matplotlib import font_manager as _xcube_font_manager',
        "    for _xcube_font_path in ('${PYTHON_CMU_SERIF_FONT_PATH}', '${PYTHON_SOURCE_HAN_SERIF_FONT_PATH}'):",
        '        if _xcube_os.path.isfile(_xcube_font_path):',
        '            _xcube_font_manager.fontManager.addfont(_xcube_font_path)',
        "    _xcube_matplotlib.rcParams['font.family'] = ['CMU Serif', 'Source Han Serif SC', 'DejaVu Serif']",
        "    _xcube_matplotlib.rcParams['font.serif'] = ['CMU Serif', 'Source Han Serif SC', 'DejaVu Serif']",
        "    _xcube_matplotlib.rcParams['axes.unicode_minus'] = False",
        '_xcube_has_matplotlib'
      ].join('\\n'));
      matplotlibFontsConfigured = Boolean(configured);
    } catch (e) {
      warnings.push('配置 Matplotlib 中英文字体失败: ' + (e && e.message ? e.message : String(e)));
    } finally {
      if (configured && typeof configured.destroy === 'function') {
        try { configured.destroy(); } catch (e) {}
      }
    }
  }

  async function runPython(request) {
    const result = {
      ok: true, stdout: [], result: '', variables: {}, warnings: [], error: '', artifacts: []
    };
    if (!pyodide) {
      result.ok = false;
      result.error = 'Pyodide 尚未就绪';
      postHostMessage({ type: 'result', requestId: request.requestId, result: result });
      return;
    }
    if (builtinFontWarning !== '') {
      result.warnings.push(builtinFontWarning);
    }

    const stdout = [];
    pyodide.setStdout({ batched: (message) => stdout.push(message) });
    pyodide.setStderr({ batched: (message) => stdout.push(message) });

    let outputContext = null;
    try {
      const code = b64ToUtf8(request.codeB64);
      const variablesJson = b64ToUtf8(request.varsB64);
      const requestedPackages = parseRequestedPackages(request.packagesB64);
      const packagesToInstall = resolveAutoPackages(code, requestedPackages, result.warnings);

      packageNetworkAllowed = true;
      try {
        await pyodide.loadPackagesFromImports(code, packageCallbacks(request.requestId, result.warnings));
        await installRequestedPackages(request.requestId, packagesToInstall, result.warnings);
      } finally {
        packageNetworkAllowed = false;
      }
      configureMatplotlibFonts(result.warnings);

      postHostMessage({ type: 'executionStarted', requestId: request.requestId });

      outputContext = prepareOutputDirectory(request.requestId);

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
    } finally {
      if (outputContext !== null) {
        try {
          result.artifacts = collectOutputArtifacts(outputContext.outputDir, result.warnings);
        } catch (e) {
          result.warnings.push('收集 Python 文件产物失败: ' + (e && e.message ? e.message : String(e)));
        }
        try { pyodide.FS.chdir(outputContext.previousCwd); } catch (e) {}
        removeOutputDirectory(outputContext.outputDir);
      }
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
      try {
        await installBuiltinFonts();
      } catch (e) {
        builtinFontWarning = '内置绘图字体加载失败: ' + (e && e.message ? e.message : String(e));
      } finally {
        builtinFontNetworkAllowed = false;
      }
      // Do not report ready until the asynchronous Python/JavaScript bridge itself
      // has executed successfully. A synchronous load alone cannot catch webloop breakage.
      await pyodide.runPythonAsync('import math\\nassert math.sqrt(81) == 9');
      const keysProxy = pyodide.runPython('list(globals().keys())');
      initialGlobalKeys = new Set(keysProxy.toJs());
      initialGlobalKeys.add('PYTHON_OUTPUT_DIR');
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
