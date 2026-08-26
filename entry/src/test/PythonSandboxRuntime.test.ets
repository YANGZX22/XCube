import { describe, expect, it } from '@ohos/hypium'
import {
  PYTHON_EXECUTION_TIMEOUT_MS,
  PYTHON_MAX_REQUESTED_PACKAGES,
  PYTHON_PACKAGE_LOAD_TIMEOUT_MS,
  PYTHON_RUNTIME_READY_TIMEOUT_MS,
  normalizePythonPackageSpecs
} from '../main/ets/services/PythonSandboxRuntimePolicy'
import {
  PYODIDE_COMPAT_INDEX_URL,
  PYODIDE_COMPAT_VERSION,
  PYODIDE_HOST_HTML,
  PYODIDE_INDEX_URL,
  PYODIDE_VERSION
} from '../main/ets/services/PyodideHostHtml'

export default function pythonSandboxRuntimeTest() {
  describe('pythonSandboxRuntimeTest', () => {
    it('pins_the_current_pyodide_runtime_and_auto_loads_scientific_imports', 0, () => {
      expect(PYODIDE_VERSION).assertEqual('314.0.6')
      expect(PYODIDE_INDEX_URL).assertEqual('https://cdn.jsdelivr.net/pyodide/v314.0.6/full/')
      expect(PYODIDE_COMPAT_VERSION).assertEqual('0.29.4')
      expect(PYODIDE_COMPAT_INDEX_URL).assertEqual('https://cdn.jsdelivr.net/pyodide/v0.29.4/full/')
      expect(PYODIDE_HOST_HTML.includes('loadPackagesFromImports')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("pyodide.loadPackage('micropip'")).assertTrue()
    })

    it('runs_python_in_a_restartable_worker_with_separate_timeout_phases', 0, () => {
      expect(PYODIDE_HOST_HTML.includes("pyodide.mjs';")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("new Worker(workerUrl, { type: 'module' })")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('startCompatibilityWorker')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("const worker = new Worker(workerUrl);")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('pythonWorker.terminate()')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('PYODIDE_COMPAT_SCRIPT_URL')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("type: 'executionStarted'")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("runPythonAsync('import math")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('Never call toJs() blindly')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('len(value) > 200')).assertTrue()
      expect(PYTHON_RUNTIME_READY_TIMEOUT_MS).assertEqual(60000)
      expect(PYTHON_PACKAGE_LOAD_TIMEOUT_MS).assertEqual(90000)
      expect(PYTHON_EXECUTION_TIMEOUT_MS).assertEqual(20000)
    })

    it('limits_user_network_and_persistent_browser_capabilities', 0, () => {
      expect(PYODIDE_HOST_HTML.includes('PACKAGE_NETWORK_HOSTS')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("hideGlobal('indexedDB')")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("deniedCapability('WebSocket')")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("deniedCapability('postMessage')")).assertFalse()
      expect(PYODIDE_HOST_HTML.includes('message.controlToken !== currentControlToken')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('Python 沙箱禁止用户代码直接访问网络')).assertTrue()
    })

    it('accepts_only_bounded_package_names_and_version_constraints', 0, () => {
      const normalized = normalizePythonPackageSpecs([
        ' pandas==3.0.2 ',
        'snowballstemmer>=2.2.0',
        'pandas==3.0.2',
        'https://example.com/evil.whl',
        '../local-package',
        'owner@https://example.com/package.whl'
      ])
      expect(normalized.length).assertEqual(2)
      expect(normalized[0]).assertEqual('pandas==3.0.2')
      expect(normalized[1]).assertEqual('snowballstemmer>=2.2.0')

      const manyPackages: string[] = []
      for (let i = 0; i < PYTHON_MAX_REQUESTED_PACKAGES + 3; i++) {
        manyPackages.push(`package-${i}`)
      }
      expect(normalizePythonPackageSpecs(manyPackages).length).assertEqual(PYTHON_MAX_REQUESTED_PACKAGES)
    })
  })
}
