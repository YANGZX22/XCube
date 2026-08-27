import { describe, expect, it } from '@ohos/hypium'
import {
  PYTHON_EXECUTION_TIMEOUT_MS,
  PYTHON_MAX_OUTPUT_FILES,
  PYTHON_MAX_OUTPUT_FILE_BYTES,
  PYTHON_MAX_OUTPUT_FILE_TOTAL_BYTES,
  PYTHON_MAX_OUTPUT_IMAGES,
  PYTHON_MAX_OUTPUT_IMAGE_BYTES,
  PYTHON_MAX_OUTPUT_IMAGE_TOTAL_BYTES,
  PYTHON_MAX_REQUESTED_PACKAGES,
  PYTHON_MAX_WORKSPACE_FILE_BYTES,
  PYTHON_MAX_WORKSPACE_FILES,
  PYTHON_MAX_WORKSPACE_RUN_FILES,
  PYTHON_MAX_WORKSPACE_TOTAL_BYTES,
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
  PYTHON_CMU_SERIF_BOLD_FONT_PATH,
  PYTHON_CMU_SERIF_BOLD_ITALIC_FONT_PATH,
  PYTHON_CMU_SERIF_FONT_PATH,
  PYTHON_CMU_SERIF_FONT_URL,
  PYTHON_CMU_SERIF_ITALIC_FONT_PATH,
  PYTHON_CMU_SERIF_REGULAR_FONT_PATH,
  PYTHON_FPDF_IMPORT_NAME,
  PYTHON_FPDF_PACKAGE_NAME,
  PYTHON_SOURCE_HAN_SERIF_BOLD_FONT_PATH,
  PYTHON_SOURCE_HAN_SERIF_BOLD_ITALIC_FONT_PATH,
  PYTHON_SOURCE_HAN_SERIF_FONT_PATH,
  PYTHON_SOURCE_HAN_SERIF_FONT_URL,
  PYTHON_SOURCE_HAN_SERIF_ITALIC_FONT_PATH,
  PYTHON_SOURCE_HAN_SERIF_REGULAR_FONT_PATH
} from '../main/ets/services/PyodideHostHtml'
import {
  getPythonImageExtension,
  sanitizePythonFileName,
  sanitizePythonImageName
} from '../main/ets/services/PythonSandboxArtifactService'
import {
  buildPythonSandboxFileMarkdown,
  buildPythonSandboxFileUrl,
  buildPythonSandboxImageMarkdown,
  buildPythonSandboxImageUrl,
  isPythonSandboxFileAttachmentId,
  isPythonSandboxImageAttachmentId,
  parsePythonSandboxFileUrl,
  parsePythonSandboxImageUrl
} from '../main/ets/services/PythonSandboxArtifactLink'
import {
  buildPythonSandboxRawSchema,
  PYTHON_FONT_USAGE_GUIDANCE,
  PYTHON_PDF_USAGE_GUIDANCE,
  PYTHON_PLOTTING_USAGE_GUIDANCE
} from '../main/ets/config/BuiltinTools'
import {
  encodePythonWorkspaceSessionDirectory,
  normalizePythonWorkspacePath
} from '../main/ets/services/PythonWorkspaceService'
import {
  parsePythonSandboxRequestArguments,
  repairTruncatedPythonToolArguments
} from '../main/ets/services/PythonSandboxService'

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

    it('auto_installs_fpdf2_for_fpdf_imports_without_duplicate_requests', 0, () => {
      expect(PYTHON_FPDF_IMPORT_NAME).assertEqual('fpdf')
      expect(PYTHON_FPDF_PACKAGE_NAME).assertEqual('fpdf2')
      expect(PYODIDE_HOST_HTML.includes("pyodide.pyimport('pyodide.code')")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('codeModule.find_imports(code)')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("['fpdf', 'fpdf2']")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('normalizeDistributionName(packageSpec)')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('resolveAutoPackages(code, requestedPackages')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('installRequestedPackages(request.requestId, packagesToInstall'))
        .assertTrue()
    })

    it('captures_bounded_artifact_files_from_each_isolated_python_run', 0, () => {
      expect(PYTHON_MAX_OUTPUT_IMAGES).assertEqual(4)
      expect(PYTHON_MAX_OUTPUT_IMAGE_BYTES).assertEqual(4 * 1024 * 1024)
      expect(PYTHON_MAX_OUTPUT_IMAGE_TOTAL_BYTES).assertEqual(8 * 1024 * 1024)
      expect(PYTHON_MAX_OUTPUT_FILES).assertEqual(8)
      expect(PYTHON_MAX_OUTPUT_FILE_BYTES).assertEqual(16 * 1024 * 1024)
      expect(PYTHON_MAX_OUTPUT_FILE_TOTAL_BYTES).assertEqual(32 * 1024 * 1024)
      expect(PYODIDE_HOST_HTML.includes("const PYTHON_OUTPUT_ROOT = '/tmp/xcube-python-output'"))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes('prepareOutputDirectory(request.requestId)')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('collectOutputArtifacts(outputContext.outputDir')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("pyodide.globals.set('PYTHON_OUTPUT_DIR'"))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes(
        "setattr(_xcube_builtins, 'PYTHON_OUTPUT_DIR', PYTHON_OUTPUT_DIR)"
      )).assertTrue()
      expect(PYODIDE_HOST_HTML.includes(
        "_xcube_os.environ['XCUBE_PYTHON_OUTPUT_DIR'] = PYTHON_OUTPUT_DIR"
      )).assertTrue()
      expect(PYODIDE_HOST_HTML.includes(
        "delattr(_xcube_builtins, 'PYTHON_OUTPUT_DIR')"
      )).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("clearOutputGlobals();")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('detectImageMime(bytes)')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('detectFileMime(bytes, candidate.name)')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("kind: isImage ? 'image' : 'file'")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes('removeOutputDirectory(outputContext.outputDir)')).assertTrue()
    })

    it('mounts_a_bounded_session_workspace_for_python_and_utf8_data_files', 0, () => {
      expect(PYTHON_MAX_WORKSPACE_FILES).assertEqual(64)
      expect(PYTHON_MAX_WORKSPACE_FILE_BYTES).assertEqual(256 * 1024)
      expect(PYTHON_MAX_WORKSPACE_TOTAL_BYTES).assertEqual(2 * 1024 * 1024)
      expect(PYTHON_MAX_WORKSPACE_RUN_FILES).assertEqual(16)
      expect(normalizePythonWorkspacePath('src/main.py')).assertEqual('src/main.py')
      expect(normalizePythonWorkspacePath('data/input.txt')).assertEqual('data/input.txt')
      expect(normalizePythonWorkspacePath('./notes\\readme.md')).assertEqual('notes/readme.md')
      expect(encodePythonWorkspaceSessionDirectory('abc')).assertEqual('session_616263')

      let rejectedParentPath = false
      try {
        normalizePythonWorkspacePath('../secret.py')
      } catch (_error) {
        rejectedParentPath = true
      }
      expect(rejectedParentPath).assertTrue()

      expect(PYODIDE_HOST_HTML.includes("const PYTHON_WORKSPACE_ROOT = '/tmp/xcube-python-workspace'"))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes('parseWorkspacePayload(request.workspaceB64)')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("pyodide.globals.set('PYTHON_WORKSPACE_DIR'"))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes("file.path.toLowerCase().endsWith('.py')"))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes("combined += '\\n' + file.content;"))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes('result.workspaceFiles = collectWorkspaceFiles'))
        .assertFalse()
      expect(PYODIDE_HOST_HTML.includes('result.workspaceFiles = workspaceCapture.files'))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes('result.workspaceCaptured = workspaceCapture.complete'))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes("new TextDecoder('utf-8', { fatal: true })"))
        .assertTrue()
    })

    it('repairs_only_structurally_truncated_python_tool_json', 0, () => {
      const missingContainerClose =
        '{"action":"write_file","path":"notes.md","content":"完整内容"'
      expect(repairTruncatedPythonToolArguments(missingContainerClose))
        .assertEqual(`${missingContainerClose}}`)
      const parsed = parsePythonSandboxRequestArguments(missingContainerClose)
      expect(parsed.action).assertEqual('write_file')
      expect(parsed.path).assertEqual('notes.md')
      expect(parsed.content).assertEqual('完整内容')

      expect(repairTruncatedPythonToolArguments(
        '{"action":"write_file","path":"notes.md","content":"半截内容'
      )).assertEqual('')
      expect(repairTruncatedPythonToolArguments('{"action":"write_file",')).assertEqual('')
    })

    it('mounts_all_cmu_and_source_han_styles_for_python_output', 0, () => {
      expect(PYTHON_CMU_SERIF_FONT_URL).assertEqual(
        'https://python-fonts.xcube.invalid/CMUSerif-Regular.ttf')
      expect(PYTHON_SOURCE_HAN_SERIF_FONT_URL).assertEqual(
        'https://python-fonts.xcube.invalid/SourceHanSerifSC-Regular.otf')
      expect(PYTHON_CMU_SERIF_FONT_PATH).assertEqual('/usr/share/fonts/xcube/CMUSerif-Regular.ttf')
      expect(PYTHON_SOURCE_HAN_SERIF_FONT_PATH)
        .assertEqual('/usr/share/fonts/xcube/SourceHanSerifSC-Regular.otf')
      expect(PYTHON_CMU_SERIF_FONT_PATH).assertEqual(PYTHON_CMU_SERIF_REGULAR_FONT_PATH)
      expect(PYTHON_SOURCE_HAN_SERIF_FONT_PATH).assertEqual(PYTHON_SOURCE_HAN_SERIF_REGULAR_FONT_PATH)
      expect(PYTHON_CMU_SERIF_BOLD_FONT_PATH).assertEqual('/usr/share/fonts/xcube/CMUSerif-Bold.ttf')
      expect(PYTHON_CMU_SERIF_ITALIC_FONT_PATH).assertEqual('/usr/share/fonts/xcube/CMUSerif-Italic.ttf')
      expect(PYTHON_CMU_SERIF_BOLD_ITALIC_FONT_PATH)
        .assertEqual('/usr/share/fonts/xcube/CMUSerif-BoldItalic.ttf')
      expect(PYTHON_SOURCE_HAN_SERIF_BOLD_FONT_PATH)
        .assertEqual('/usr/share/fonts/xcube/SourceHanSerifSC-Bold.otf')
      expect(PYTHON_SOURCE_HAN_SERIF_ITALIC_FONT_PATH)
        .assertEqual('/usr/share/fonts/xcube/SourceHanSerifSC-Italic.ttf')
      expect(PYTHON_SOURCE_HAN_SERIF_BOLD_ITALIC_FONT_PATH)
        .assertEqual('/usr/share/fonts/xcube/SourceHanSerifSC-BoldItalic.ttf')
      expect(PYODIDE_HOST_HTML.includes("pyodide.globals.set('PYTHON_FONT_EN'")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("pyodide.globals.set('PYTHON_FONT_CJK'")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("pyodide.globals.set('PYTHON_FONT_EN_BOLD'")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("pyodide.globals.set('PYTHON_FONT_EN_ITALIC'")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("pyodide.globals.set('PYTHON_FONT_EN_BOLD_ITALIC'"))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes("pyodide.globals.set('PYTHON_FONT_CJK_BOLD'")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("pyodide.globals.set('PYTHON_FONT_CJK_ITALIC'")).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("pyodide.globals.set('PYTHON_FONT_CJK_BOLD_ITALIC'"))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes("['CMU Serif', 'Source Han Serif SC', 'DejaVu Serif']"))
        .assertTrue()
      expect(PYODIDE_HOST_HTML.includes('_xcube_font_manager.fontManager.addfont')).assertTrue()
      expect(PYODIDE_HOST_HTML.includes("name='Source Han Serif SC', style=_xcube_style"))
        .assertTrue()
    })

    it('guides_models_to_use_mixed_script_fonts_without_losing_fallback', 0, () => {
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes(
        "font.family=['CMU Serif', 'Source Han Serif SC', 'DejaVu Serif']"
      )).assertTrue()
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes('PYTHON_FONT_EN_*')).assertTrue()
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes('PYTHON_FONT_CJK_*')).assertTrue()
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes('XCUBE_PYTHON_FONT_EN_*')).assertTrue()
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes('XCUBE_PYTHON_FONT_CJK_*')).assertTrue()
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes('/usr/share/fonts/xcube/')).assertTrue()
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes('REGULAR、BOLD、ITALIC')).assertTrue()
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes('BOLD_ITALIC')).assertTrue()
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes('Pillow 不会自动回退字体')).assertTrue()
      expect(PYTHON_FONT_USAGE_GUIDANCE.includes('中英混排须按文字脚本切分')).assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes('from fpdf import FPDF')).assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes('HTTPSHandler')).assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes('HTTPSConnection')).assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes("style=''、'B'、'I'、'BI'"))
        .assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes("pdf.add_font('CMU', style=style"))
        .assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes("pdf.add_font('SourceHan', style=style"))
        .assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes(
        "pdf.set_fallback_fonts(['SourceHan'], exact_match=True)"
      )).assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes("pdf.set_font('CMU', style='BI'"))
        .assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes('pdf.page = i')).assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes('fpdf2 没有 set_page()')).assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes('action=run 的当前目录就是本次 PYTHON_OUTPUT_DIR'))
        .assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes('action=run_files 的当前目录是工作区'))
        .assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes('通过 builtins 向入口及其 import 的模块统一暴露'))
        .assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes("os.environ['XCUBE_PYTHON_OUTPUT_DIR']"))
        .assertTrue()
      expect(PYTHON_PDF_USAGE_GUIDANCE.includes('不要探测或硬编码 /tmp')).assertTrue()
    })

    it('guides_models_to_use_headless_plotting_and_repeat_package_declarations', 0, () => {
      expect(PYTHON_PLOTTING_USAGE_GUIDANCE.includes("matplotlib.use('Agg')")).assertTrue()
      expect(PYTHON_PLOTTING_USAGE_GUIDANCE.includes('导入 pyplot、Seaborn 或创建 figure 前')).assertTrue()
      expect(PYTHON_PLOTTING_USAGE_GUIDANCE.includes("cannot import name 'document' from 'js'"))
        .assertTrue()
      expect(PYTHON_PLOTTING_USAGE_GUIDANCE.includes('packages: ["seaborn"]')).assertTrue()
      expect(PYTHON_PLOTTING_USAGE_GUIDANCE.includes('重复、并行或重试调用')).assertTrue()
      expect(PYTHON_PLOTTING_USAGE_GUIDANCE.includes('不得假设先前调用安装的包或导入状态')).assertTrue()
    })

    it('builds_python_tool_schema_with_quoted_package_examples', 0, () => {
      const schemaJson: string = JSON.stringify(buildPythonSandboxRawSchema())
      expect(schemaJson.includes('packages')).assertTrue()
      expect(schemaJson.includes('seaborn')).assertTrue()
      expect(schemaJson.includes("matplotlib.use('Agg')")).assertTrue()
    })

    it('normalizes_python_image_names_and_mime_extensions_before_persisting', 0, () => {
      expect(getPythonImageExtension('image/png')).assertEqual('.png')
      expect(getPythonImageExtension('image/jpeg')).assertEqual('.jpg')
      expect(getPythonImageExtension('image/svg+xml')).assertEqual('')
      expect(sanitizePythonImageName('../bad chart.jpeg', 'image/png')).assertEqual('bad_chart.png')
      expect(sanitizePythonImageName('', 'image/webp')).assertEqual('python_image.webp')
    })

    it('builds_safe_markdown_links_for_python_generated_files', 0, () => {
      const attachmentId = 'python_file_1723456789_1'
      expect(isPythonSandboxFileAttachmentId(attachmentId)).assertTrue()
      expect(isPythonSandboxFileAttachmentId('python_img_1723456789_1')).assertFalse()
      expect(buildPythonSandboxFileUrl(attachmentId))
        .assertEqual('xcube-file://python_file_1723456789_1')
      expect(parsePythonSandboxFileUrl('xcube-file://python_file_1723456789_1'))
        .assertEqual(attachmentId)
      expect(parsePythonSandboxFileUrl('https://example.com/report.pdf')).assertEqual('')
      expect(sanitizePythonFileName('../报告 [最终].pdf', 'application/pdf'))
        .assertEqual('报告 [最终].pdf')
      expect(sanitizePythonFileName('../result', 'text/csv')).assertEqual('result.csv')
      expect(buildPythonSandboxFileMarkdown('报告 [最终].pdf', attachmentId))
        .assertEqual('[报告 \\[最终\\].pdf](xcube-file://python_file_1723456789_1)')
    })

    it('builds_safe_inline_markdown_for_python_generated_images', 0, () => {
      const attachmentId = 'python_img_1723456789_2'
      expect(isPythonSandboxImageAttachmentId(attachmentId)).assertTrue()
      expect(isPythonSandboxImageAttachmentId('python_file_1723456789_2')).assertFalse()
      expect(buildPythonSandboxImageUrl(attachmentId))
        .assertEqual('xcube-image://python_img_1723456789_2')
      expect(parsePythonSandboxImageUrl('xcube-image://python_img_1723456789_2'))
        .assertEqual(attachmentId)
      expect(parsePythonSandboxImageUrl('file:///data/chart.png')).assertEqual('')
      expect(buildPythonSandboxImageMarkdown('趋势图 [最终].png', attachmentId))
        .assertEqual('![趋势图 \\[最终\\].png](xcube-image://python_img_1723456789_2)')
      const schemaJson = JSON.stringify(buildPythonSandboxRawSchema())
      expect(schemaJson.includes('images 中的 markdown 字段')).assertTrue()
      expect(schemaJson.includes('图片不会在气泡顶部自动展示')).assertTrue()
    })
  })
}
