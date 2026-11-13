export const BUILTIN_BROWSER_TOOL_ID: string = 'builtin_browser'
export const BROWSER_ACTIONS: string[] = [
  'open', 'snapshot', 'read_page', 'find', 'click', 'scroll', 'type', 'back', 'forward', 'reload', 'set_page_mode', 'wait_for_user'
]

export class BrowserRequest {
  action: string = 'snapshot'
  url: string = ''
  snapshot_id: string = ''
  x: number = 0
  y: number = 0
  hasScrollOrigin: boolean = false
  delta_x: number = 0
  delta_y: number = 0
  page_mode: string = ''
  text: string = ''
  submit: boolean = false
  start: number = 0
  max_chars: number = 8000
}

// External pages never gain access to file:, data:, javascript: or application schemes.
export function isBrowserUrlAllowed(value: string): boolean {
  return value === 'about:blank' ||
    (/^https?:\/\/[^\s/\\?#@]+(?:[/?#]|$)/i.test(value) && !/[\u0000-\u0020\\]/.test(value))
}

function stringField(data: Record<string, Object>, key: string): string {
  const value = data[key]
  if (value === undefined) {
    return ''
  }
  if (typeof value !== 'string') {
    throw new Error(`${key} 必须是字符串`)
  }
  return value
}

function numberField(data: Record<string, Object>, key: string, required: boolean = false): number {
  const value = data[key]
  if (value === undefined && !required) {
    return 0
  }
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error(`${key} 必须是有限数值`)
  }
  return value
}

export function parseBrowserRequest(raw: string): BrowserRequest {
  if (raw.length > 65536) {
    throw new Error('浏览器参数过长；单次输入请控制在 16000 字符内')
  }
  let source = raw.trim()
  if (source.startsWith('```') && source.endsWith('```')) {
    source = source.slice(source.indexOf('\n') + 1, -3).trim()
  }
  let parsed: Object = JSON.parse(source) as Object
  // Compatibility with providers that stringify or wrap function arguments. Never repair truncated actions.
  for (let depth = 0; depth < 3; depth++) {
    if (typeof parsed === 'string') {
      parsed = JSON.parse(parsed) as Object
    } else if (parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed)) {
      const wrapped = parsed as Record<string, Object>
      if (wrapped['action'] !== undefined) {
        break
      }
      parsed = wrapped['arguments'] ?? wrapped['input'] ?? wrapped['parameters'] ?? parsed
    }
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('builtin_browser 参数必须是单个 JSON 对象')
  }
  const data = parsed as Record<string, Object>
  const request = new BrowserRequest()
  request.action = stringField(data, 'action').trim()
  if (!BROWSER_ACTIONS.includes(request.action)) {
    throw new Error(`未知浏览器操作：${request.action}`)
  }
  request.url = stringField(data, 'url').trim()
  request.snapshot_id = stringField(data, 'snapshot_id').trim()
  request.page_mode = stringField(data, 'page_mode').trim()
  if (data['page_mode'] !== undefined || request.action === 'set_page_mode') {
    if (!['mobile', 'desktop'].includes(request.page_mode)) {
      throw new Error('page_mode 必须为 mobile（手机版）或 desktop（电脑版）')
    }
    if (request.action !== 'open' && request.action !== 'set_page_mode') {
      throw new Error('page_mode 仅用于 open 或 set_page_mode')
    }
  }
  if (request.action === 'open' && !isBrowserUrlAllowed(request.url)) {
    throw new Error('open 必须提供完整的 http:// 或 https:// URL')
  }
  if (request.action === 'click') {
    request.x = numberField(data, 'x', true)
    request.y = numberField(data, 'y', true)
  }
  if (request.action === 'scroll') {
    if (data['x'] !== undefined || data['y'] !== undefined) {
      request.x = numberField(data, 'x', true)
      request.y = numberField(data, 'y', true)
      request.hasScrollOrigin = true
    }
    request.delta_x = numberField(data, 'delta_x')
    request.delta_y = numberField(data, 'delta_y')
    if (Math.abs(request.delta_x) > 4000 || Math.abs(request.delta_y) > 4000 ||
      (request.delta_x === 0 && request.delta_y === 0)) {
      throw new Error('滚动距离必须非零，且每个方向不超过 4000 截图像素')
    }
  }
  if (request.action === 'type') {
    request.text = stringField(data, 'text')
    if (request.text.length > 16000) {
      throw new Error('单次输入不能超过 16000 字符')
    }
    if (data['submit'] !== undefined && typeof data['submit'] !== 'boolean') {
      throw new Error('submit 必须是布尔值')
    }
    request.submit = data['submit'] === true
    if (request.text === '' && !request.submit) {
      throw new Error('type 需要 text 或 submit=true')
    }
  }
  if (request.action === 'find') {
    request.text = stringField(data, 'text').trim()
    if (request.text === '' || request.text.length > 200) throw new Error('find 需要 1-200 字符的 text 关键词')
  }
  if (request.action === 'read_page') {
    request.start = numberField(data, 'start')
    request.max_chars = data['max_chars'] === undefined ? 8000 : numberField(data, 'max_chars')
    if (!Number.isInteger(request.start) || request.start < 0 || request.start > 500000 ||
      !Number.isInteger(request.max_chars) || request.max_chars < 1 || request.max_chars > 16000) {
      throw new Error('read_page 的 start 必须为 0-500000 整数，max_chars 必须为 1-16000 整数')
    }
  }
  if (['find', 'click', 'scroll', 'type', 'back', 'forward', 'reload', 'set_page_mode'].includes(request.action) &&
    request.snapshot_id === '') {
    throw new Error('操作前必须提供最近一次截图的 snapshot_id；先调用 snapshot')
  }
  return request
}

// Preserve the installed ArkWeb/Chromium versions and OS identity while selecting the site's form factor.
// ArkWeb also uses the Mobile token to select mobile meta-viewport handling.
export function buildBrowserUserAgent(defaultUserAgent: string, pageMode: string): string {
  if (!['mobile', 'desktop'].includes(pageMode) || defaultUserAgent.trim() === '') {
    throw new Error('无法设置浏览器页面模式')
  }
  const agent = defaultUserAgent.replace(/\bMobile\b/g, '')
    .replace(/\((Phone|Tablet|PC);/, pageMode === 'mobile' ? '(Phone;' : '(PC;')
    .replace(/\s{2,}/g, ' ').trim()
  return pageMode === 'mobile' ? `${agent} Mobile` : agent
}

export function assertBrowserPoint(x: number, y: number, width: number, height: number): void {
  if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0 || x >= width || y >= height) {
    throw new Error('点击坐标超出截图范围；请使用截图像素坐标，不能使用百分比或屏幕坐标')
  }
}
