import { describe, expect, it } from '@ohos/hypium'
import {
  PYTHON_EXECUTION_TIMEOUT_MS,
  PYTHON_MAX_OUTPUT_IMAGES,
  PYTHON_MAX_OUTPUT_IMAGE_BYTES,
  PYTHON_MAX_OUTPUT_IMAGE_TOTAL_BYTES,
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
  PYODIDE_VERSION,
  PYTHON_CMU_SERIF_FONT_PATH,
  PYTHON_CMU_SERIF_FONT_URL,
  PYTHON_SOURCE_HAN_SERIF_FONT_PATH,
  PYTHON_SOURCE_HAN_SERIF_FONT_URL
} from '../main/ets/services/PyodideHostHtml'
import {
  getPythonImageExtension,
  sanitizePythonImageName
} from '../main/ets/services/PythonSandboxArtifactService'
import { PYTHON_FONT_USAGE_GUIDANCE } from '../main/ets/config/BuiltinTools'

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

    it('captures_bounded_image_files_from_each_isolated_python_run', 0, () => {
      expect(PYTHON_MAX_OUTPUT_IMAGES).assertEqual(4)
      expect(PYTHON_MAX_OUTPUT_IMAGE_BYTES).assertEqual(4 * 1024 * 1024)
      expect(PYTHON_MAX_OUTPUT_IMAGE_TOTAL_BYTES).assertEqual(8 * 1024 * 1024)
      expect(PYODIDE_HOST_HTML.includes("const PYTHON_OUTPUT_ROOT = '/tmp/xcube-python-output'"))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes('prepareOutputDirectory(request.requestId)')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('collectOutputImages(outputContext.outputDir')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("pyodide.globals.set('PYTHON_OUTPUT_DIR'"))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes('detectImageMime(bytes)')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('removeOutputDirectory(outputContext.outputDir)')).assertTrue()
    })

    it('mounts_cmu_and_source_han_fonts_for_python_plotting', 0, () => {
      expect(PYTHON_CMU_SERIF_FONT_URL).assertEqual(
        'https://python-fonts.xcube.invalid/CMUSerif-Regular.ttf')
      expect(PYTHON_SOURCE_HAN_SERIF_FONT_URL).assertEqual(
        'https://python-fonts.xcube.invalid/SourceHanSerifSC-Regular.otf')
      expect(PYTHON_CMU_SERIF_FONT_PATH).assertEqual('/usr/share/fonts/xcube/CMUSerif-Regular.ttf')
      expect(PYTHON_SOURCE_HAN_SERIF_FONT_PATH)
        .assertEqual('/usr/share/fonts/xcube/SourceHanSerifSC-Regular.otf')
      expect(PYODIDE_HOST_HTML.includes("pyodide.globals.set('PYTHON_FONT_EN'")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("pyodide.globals.set('PYTHON_FONT_CJK'")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("['CMU Serif', 'Source Han Serif SC', 'DejaVu Serif']"))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes('_xcube_font_manager.fontManager.addfont')).assertTrue()
    })

    it('guides_models_to_use_mixed_script_fonts_without_losing_fallback', 0, () => {
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes(
        "font.family=['CMU Serif', 'Source Han Serif SC', 'DejaVu Serif']"
      )).assertTrue()
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes('ImageFont.truetype(PYTHON_FONT_EN, size)')).assertTrue()
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes('ImageFont.truetype(PYTHON_FONT_CJK, size)')).assertTrue()
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes('Pillow 不会自动回退字体')).assertTrue()
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes('中英混排须按文字脚本切分')).assertTrue()
    })

    it('normalizes_python_image_names_and_mime_extensions_before_persisting', 0, () => {
      expect(getPythonImageExtension('image/png')).assertEqual('.png')
      expect(getPythonImageExtension('image/jpeg')).assertEqual('.jpg')
      expect(getPythonImageExtension('image/svg+xml')).assertEqual('')
      expect(sanitizePythonImageName('../bad chart.jpeg', 'image/png')).assertEqual('bad_chart.png')
      expect(sanitizePythonImageName('', 'image/webp')).assertEqual('python_image.webp')
    })
  })
}
