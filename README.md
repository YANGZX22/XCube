<p align="center">
  <img src="entry/src/main/resources/base/media/app_icon.png" width="120" />
</p>

<h1 align="center">XCube</h1>

<p align="center">
  A native AI chat client for HarmonyOS 7.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/HarmonyOS-7_(API_26)-4285F4" alt="HarmonyOS 7" />
  <a href="./CHANGELOG.md"><img src="https://img.shields.io/badge/version-1.3.5-2ea44f" alt="Version 1.3.5" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License" /></a>
</p>

<p align="center">
  <a href="./README.zh-CN.md">简体中文</a> · <a href="#features">Features</a> · <a href="#getting-started">Getting Started</a> · <a href="./CHANGELOG.md">Changelog</a>
</p>

> [!IMPORTANT]
> XCube requires **HarmonyOS 7 (API 26.0.0) or later**. Still on HarmonyOS 6 or earlier? Join the [Huawei Beta Test Program](https://cn.club.vmall.com/mhw/assets/file-html-app/3b2bca9630d0fcb2bb2dfac09ee415ea20230529103243/index.html?ts=1785306752202#/) before installing.

## Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/IMAGE1.jpg" width="220" /><br/><sub>Conversation Lists</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE2.jpg" width="220" /><br/><sub>Knowledge Base Page</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE3.jpg" width="220" /><br/><sub>Work with Sub Agents</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/IMAGE4.jpg" width="220" /><br/><sub>Contexts</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE5.jpg" width="220" /><br/><sub>Manuscript Chat</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE6.jpg" width="220" /><br/><sub>Manuscript Conversation List</sub></td>
  </tr>
</table>

## Highlights

- 🤖 **Any model** — 15+ providers built in, plus any OpenAI-, Anthropic-, or Gemini-compatible API
- 🔍 **Web search & MCP** — Bocha, Bing (local), Tavily, Exa, and remote streamable MCP servers
- 🧩 **Conversational sub-agents** — split big tasks across up to 3 agents, then guide each one through multiple follow-up rounds
- 📚 **Local knowledge base** — hybrid keyword + vector RAG with built-in DOCX/XLSX parsing and OCR; files never leave the app sandbox
- 🛠️ **Built-in tools** — Canvas documents, Python sandbox, charts, calendar, and PDF/image/DOCX/XLSX → text
- 🔊 **Read aloud** — HarmonyOS offline TTS or ElevenLabs
- 🔒 **Privacy by design** — explicit tool permissions and confirmation flows throughout

Built entirely in ArkTS with native HarmonyOS interactions and immersive-light materials.

> [!NOTE]
> XCube continues [YANGZX22/chatcube](https://github.com/YANGZX22/chatcube), originally forked from [LongLiveY96/ChatCube](https://github.com/LongLiveY96/ChatCube). Copyright and MIT license notices from both earlier versions are preserved in full.

## Features

### 🤖 Talk to any model

15+ providers work out of the box:

OpenAI · Claude · Gemini · DeepSeek · Grok · Ollama · OpenRouter · SiliconFlow · Qwen · Kimi · Zhipu (GLM) · Doubao · MiniMax · AiHubMix · MiMo

…and you can add any other OpenAI-, Anthropic-, or Gemini-compatible endpoint yourself.

### 🧩 Parallel sub-agents

Turn on **Sub-agent** in the chat input's tool selector, and the main model can split a request — multi-topic research, source comparisons, independent documents — across up to three sub-agents running in parallel, then synthesize their reports. Each returned `agentId` remains addressable for the rest of the main response, so the main model can ask follow-up questions, correct direction, request verification, and refine the same sub-agent's work for as many rounds as needed.

- Each sub-agent keeps its own isolated conversation context, tool history, and search budget across follow-up rounds
- Watch output, tool calls, and status live in the Sub-agent Live Preview panel
- Requires a model with full tool-calling support

### 📚 Knowledge base & RAG

Upload DOCX, XLSX, PDF, Markdown, text, or images in the Knowledge Base tab. DOCX and XLSX files are handled by the app's built-in OOXML parser, while images and scanned PDFs can use local OCR. Models search them on demand through the [`knowledge_search`](entry/src/main/ets/config/KnowledgeSearchTool.ets) tool — nothing is pre-retrieved or injected into the system prompt.

- **Hybrid retrieval** — keyword + vector search with neighbor-chunk expansion, so answers that span a boundary don't get cut off
- **DOCX structure extraction** — preserves headings, paragraphs, lists, line breaks, and tables as chunk-friendly structured text
- **XLSX table extraction** — supports multiple worksheets, shared strings, dates, merged cells, cached formula values, and sparse-cell coordinates
- **Structure-aware chunking** — respects page boundaries, headings, lists, tables, worksheets, and FAQ pairs
- **Two embedding options** — on-device ArkData embedding (PC/2-in-1 devices) or any OpenAI-compatible embedding API
- **Everything stays local** — files, OCR results, indexes, and vectors all live in the app sandbox

> [!NOTE]
> On-device ArkData embedding currently supports 2-in-1 devices only. Phones and tablets can use an API embedding model — and keyword search still works with no API configured at all.

> [!NOTE]
> Office parsing currently supports the OOXML `.docx` and `.xlsx` formats. Legacy `.doc`/`.xls`, encrypted files, macros, chart content, and OCR of images embedded inside documents are not supported. Formulas use the cached value saved in the workbook when available and otherwise preserve the formula expression.

### 🛠️ Built-in tools

| Tool | What it does |
|------|--------------|
| **Web search** | Fetch real-time information within a search budget; extras need your approval |
| **Canvas document** | A shared doc beside the chat that you and the AI can both edit, with Markdown preview |
| **Python sandbox** | Run Python for calculations, data processing, and intermediate reasoning |
| **Math charts** | Generate [VChart](https://ohpm.openharmony.cn/#/cn/detail/@visactor%2Fharmony-vchart) visualizations — line, bar, pie, scatter, Sankey, word cloud, and more |
| **PDF → text** (`pdf_to_text`) | Extract the PDF text layer, with automatic local CoreVisionKit OCR fallback for scans |
| **Image → text** (`image_to_text`) | Recognize text in images with local CoreVisionKit OCR |
| **ModLens Vision*** (`vision_read_image`) | Use [ModLens](https://github.com/liustack/modlens) to provide OCR, layout, semantic, and visual evidence to text-only models; requires a separate deployment |
| **DOCX → text** (`docx_to_text`) | Locally extract DOCX headings, paragraphs, lists, and tables without passing the raw file to models that lack document input |
| **XLSX → text** (`xlsx_to_text`) | Locally extract worksheets, cells, dates, and formula results without passing the raw file to models that lack document input |
| **Calendar** | Read a user-confirmed date range or create events, with privacy controls |
| **Ask user** | Lets the model raise a confirmation card when it hits a critical ambiguity |

#### * Enable ModLens vision for text-only models

HarmonyOS apps cannot run the Node.js CLI required by ModLens directly, so the repository includes an optional lightweight companion gateway that you can deploy yourself on a computer or server. Follow [`tools/modlens-gateway/README.md`](tools/modlens-gateway/README.md) to start the gateway, then open **Settings → Tools → ModLens Vision**, enter its address, test the connection, and enable the tool.

- Images leave the device only after the gateway is explicitly configured and the tool is enabled; ModLens then sends them to its configured vision provider
- The fallback tool is automatically hidden when the active model already has native vision
- When the gateway is unavailable or disabled, or when the model cannot call tools, you can use `image_to_text` instead

### 🔊 Read aloud

Play any reply straight from the message toolbar (**Settings → Read Aloud**):

- **Local TTS** — the HarmonyOS offline engine; no API key, nothing leaves the device
- **ElevenLabs** — bring your own key, pick from your account's voices, tune stability, similarity, and speed

## Getting Started

### Prerequisites

- A device running HarmonyOS 7 (API 26.0.0)
- [DevEco Studio ≥ 26.0.0 Beta2](https://developer.huawei.com/consumer/cn/deveco-studio/)

### 1. Clone and configure

```bash
git clone https://github.com/YANGZX22/XCube.git
cd XCube
cp build-profile.json5.example build-profile.json5
# Edit build-profile.json5 with your signing config
```

### 2. Add the speech-recognition model (one-time)

The ASR model is too large for Git, so add it manually:

1. Download [sherpa-onnx SenseVoice](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2) (Chinese, English, Japanese, Korean, Cantonese)
2. Extract it and move the `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` directory into `entry/src/main/resources/rawfile/`

The model directory is gitignored and will never be committed.

### 3. Run

Open the project in DevEco Studio and run it on your device.

### Sideloading the HAP

Install directly on a device with [Auto-installer](https://github.com/likuai2010/auto-installer/) or [DevEco Testing](https://developer.huawei.com/consumer/cn/deveco-testing/).

> [!IMPORTANT]
> Huawei's signing servers block IP addresses outside mainland China — keep this in mind when sideloading HarmonyOS NEXT software elsewhere.

> [!NOTE]
> Self-signed sideloaded apps are valid for 14 days by default. [Developer Real-Name Authentication](https://developer.huawei.com/consumer/cn/verified/enrollment) extends that to 180 days.

## License

[MIT](./LICENSE) — copyright notices for LongLiveY96's original ChatCube and the YANGZX22 continuation are preserved, and XCube's modifications are released under the same license.
