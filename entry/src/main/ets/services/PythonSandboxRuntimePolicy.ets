export const PYTHON_RUNTIME_READY_TIMEOUT_MS: number = 60000
export const PYTHON_PACKAGE_LOAD_TIMEOUT_MS: number = 90000
export const PYTHON_EXECUTION_TIMEOUT_MS: number = 20000
export const PYTHON_MAX_REQUESTED_PACKAGES: number = 8
// Python 产物会先通过 WebView bridge 传回 ArkTS，再落到应用附件沙箱。
// 对数量和体积同时设限，避免模型代码用图片产物耗尽移动端内存。
export const PYTHON_MAX_OUTPUT_IMAGES: number = 4
export const PYTHON_MAX_OUTPUT_IMAGE_BYTES: number = 4 * 1024 * 1024
export const PYTHON_MAX_OUTPUT_IMAGE_TOTAL_BYTES: number = 8 * 1024 * 1024

const PYTHON_PACKAGE_SPEC_PATTERN: RegExp =
  /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}(?:\[[A-Za-z0-9._,-]+\])?(?:[<>=!~]=?[A-Za-z0-9.*+_,<>=!~-]+)?$/

/**
 * Only accept ordinary PyPI distribution names and optional version constraints.
 * URLs, local paths and direct references are deliberately rejected so model-generated
 * code cannot turn package installation into an arbitrary downloader.
 */
export function normalizePythonPackageSpecs(packages: string[] | undefined): string[] {
  if (!Array.isArray(packages)) {
    return []
  }

  const normalized: string[] = []
  for (let i = 0; i < packages.length && normalized.length < PYTHON_MAX_REQUESTED_PACKAGES; i++) {
    if (typeof packages[i] !== 'string') {
      continue
    }
    const candidate = packages[i].trim()
    if (candidate === '' || !PYTHON_PACKAGE_SPEC_PATTERN.test(candidate) || normalized.includes(candidate)) {
      continue
    }
    normalized.push(candidate)
  }
  return normalized
}
