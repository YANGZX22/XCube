import { buffer } from '@kit.ArkTS'
import { CodeTheme } from '../constant/CodeTheme'

export type MermaidTheme = "default" | "dark" | "forest" | "neutral"

export type MermaidSecurityLevel = "strict" | "loose" | "antiscript" | "sandbox"

const MERMAID_RAWFILE_PATH = "mermaid/mermaid.main.js"
let mermaidScriptCache: string = ""
let mermaidScriptLoading: Promise<string> | undefined = undefined

function escapeScriptContent(script: string): string {
  return script.replace(/<\/script>/gi, '<\\/script>')
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

async function readRawfileText(context: Context, path: string): Promise<string> {
  const uint8Array = context.resourceManager.getRawFileContentSync(path)
  const arrayBuffer = buffer.from(uint8Array).buffer
  const blob = new buffer.Blob([arrayBuffer])
  return await blob.text()
}

async function readMermaidScript(context: Context): Promise<string> {
  if (mermaidScriptCache.length > 0) {
    return mermaidScriptCache
  }
  if (mermaidScriptLoading) {
    return await mermaidScriptLoading
  }
  mermaidScriptLoading = readRawfileText(context, MERMAID_RAWFILE_PATH)
  try {
    mermaidScriptCache = await mermaidScriptLoading
    return mermaidScriptCache
  } finally {
    mermaidScriptLoading = undefined
  }
}

export async function buildMermaidHtml(context: Context, diagram: string, theme: MermaidTheme,
  securityLevel: MermaidSecurityLevel, renderTheme: CodeTheme = "light"): Promise<string> {
  const mermaidScript = await readMermaidScript(context)
  const diagramJson = JSON.stringify(diagram)
  const themeJson = JSON.stringify(theme)
  const securityLevelJson = JSON.stringify(securityLevel)
  const isDark = renderTheme == "dark"
  const backgroundColor = isDark ? "#181A1F" : "#ffffff"
  const textColor = isDark ? "#F9FAFB" : "#1f2933"
  const errorBackgroundColor = isDark ? "#351C21" : "#fff1f0"
  const errorTextColor = isDark ? "#FFB4B4" : "#a8071a"

  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=3.0">
  <style>
    html, body {
      margin: 0;
      padding: 0;
      height: 100%;
      overflow: hidden;
      overscroll-behavior: none;
      background: ${backgroundColor};
      color: ${textColor};
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    body {
      height: 100vh;
      box-sizing: border-box;
    }
    #container {
      width: 100%;
      height: 100vh;
      overflow: auto;
      overscroll-behavior: contain;
      background: ${backgroundColor};
    }
    #container svg {
      max-width: 100%;
      height: auto;
    }
    .error {
      margin: 0;
      padding: 12px;
      border-radius: 8px;
      background: ${errorBackgroundColor};
      color: ${errorTextColor};
      white-space: pre-wrap;
      font-size: 13px;
      line-height: 20px;
    }
  </style>
  <script>
${escapeScriptContent(mermaidScript)}
  </script>
</head>
<body>
  <div id="container"></div>
  <script>
    const diagram = ${diagramJson};
    mermaid.initialize({
      startOnLoad: false,
      theme: ${themeJson},
      securityLevel: ${securityLevelJson}
    });
    mermaid.render("lv_mermaid_diagram", diagram)
      .then(function(result) {
        document.getElementById("container").innerHTML = result.svg;
      })
      .catch(function(error) {
        document.getElementById("container").innerHTML =
          '<pre class="error">' + ${JSON.stringify("Mermaid 渲染失败\n")} + String(error)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;") + '</pre>';
      });
  </script>
</body>
</html>`
}

export function buildMermaidMissingHtml(renderTheme: CodeTheme = "light"): string {
  const isDark = renderTheme == "dark"
  const backgroundColor = isDark ? "#181A1F" : "#ffffff"
  const textColor = isDark ? "#F9FAFB" : "#1f2933"
  const tipBackgroundColor = isDark ? "#332B1A" : "#fff7e6"
  const tipTextColor = isDark ? "#FFD591" : "#8a4b00"

  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { margin: 0; padding: 16px; font-family: system-ui, sans-serif; background: ${backgroundColor}; color: ${textColor}; }
    .tip { padding: 12px; border-radius: 8px; background: ${tipBackgroundColor}; color: ${tipTextColor}; line-height: 22px; }
  </style>
</head>
<body>
  <div class="tip">未找到 ${escapeHtml(MERMAID_RAWFILE_PATH)}，请将 mermaid.main.js 放入 markdown 模块 rawfile 目录后重试。</div>
</body>
</html>`
}
