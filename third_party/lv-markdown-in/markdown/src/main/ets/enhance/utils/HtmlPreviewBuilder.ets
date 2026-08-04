import { CodeTheme } from '../constant/CodeTheme'

function escapeHtml(value: string): string {
  return (value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

export function buildHtmlPreviewDocument(html: string, renderTheme: CodeTheme = 'light',
  javaScriptEnable: boolean = false): string {
  const background = renderTheme == 'dark' ? '#181A1F' : '#ffffff'
  const color = renderTheme == 'dark' ? '#F9FAFB' : '#111827'
  const csp = javaScriptEnable ? '' :
    '<meta http-equiv="Content-Security-Policy" content="script-src &#39;none&#39;; object-src &#39;none&#39;; base-uri &#39;none&#39;">'
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  ${csp}
  <style>
    html, body {
      margin: 0;
      padding: 0;
      min-height: 100%;
      background: ${background};
      color: ${color};
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "HarmonyOS Sans", sans-serif;
    }
    body {
      box-sizing: border-box;
      padding: 12px;
      overflow: auto;
    }
    * {
      box-sizing: border-box;
      max-width: 100%;
    }
    img, video, canvas, svg {
      max-width: 100%;
      height: auto;
    }
    table {
      border-collapse: collapse;
    }
  </style>
</head>
<body>
${html || ''}
</body>
</html>`
}

export function buildHtmlPreviewMissingDocument(text: string, renderTheme: CodeTheme = 'light'): string {
  const background = renderTheme == 'dark' ? '#181A1F' : '#ffffff'
  const color = renderTheme == 'dark' ? '#FFB4B4' : '#a8071a'
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    html, body {
      margin: 0;
      padding: 12px;
      background: ${background};
      color: ${color};
      font-family: monospace;
      white-space: pre-wrap;
    }
  </style>
</head>
<body>${escapeHtml(text || 'HTML 预览加载失败')}</body>
</html>`
}
