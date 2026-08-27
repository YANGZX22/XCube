<p align="center">
  <img src="entry/src/main/resources/base/media/app_icon.png" width="120" />
</p>

<h1 align="center">XCube</h1>

<p align="center">
  A native AI agent harness for HarmonyOS 7.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/HarmonyOS-7_(API_26)-4285F4" alt="HarmonyOS 7" />
  <a href="./CHANGELOG.md"><img src="https://img.shields.io/badge/version-1.3.6-2ea44f" alt="Version 1.3.6" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License" /></a>
</p>

<p align="center">
  <a href="./README.zh-CN.md">简体中文</a> · <a href="#features">Features</a> · <a href="#getting-started">Getting Started</a> · <a href="./CHANGELOG.md">Changelog</a>
</p>

## Basic Information

> [!NOTE]
> As the official release of HarmonyOS 7 approaches, updates to this repository will be put on hold. Once the official version is released, this app may be made available via the Huawei AppGallery’s invitation-only testing feature, at which point installation will be more convenient. Please note, however, that this app may NEVER be officially listed on the Huawei AppGallery.

> [!IMPORTANT]
> XCube requires **HarmonyOS 7 (API 26.0.0) or later**. Users on HarmonyOS 6 or earlier must first join the [Huawei Beta Test Program](https://cn.club.vmall.com/mhw/assets/file-html-app/3b2bca9630d0fcb2bb2dfac09ee415ea20230529103243/index.html?ts=1785306752202#/) before installing the app. Refer to the program website for current test dates.

> [!NOTE]
> XCube continues [YANGZX22/chatcube](https://github.com/YANGZX22/chatcube), which was originally forked from [LongLiveY96/ChatCube](https://github.com/LongLiveY96/ChatCube). Copyright and MIT license notices from both earlier versions are preserved in full.

## Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/multi-tools.png" width="220" /><br/><sub>Work using Multiple Tools</sub></td>
    <td align="center"><img src="docs/screenshots/new-python.png" width="220" /><br/><sub>Work with Python Packages</sub></td>
    <td align="center"><img src="docs/screenshots/answer-using-knowledge-base.png" width="220" /><br/><sub>Work in RAG</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/work-with-sub-agents.png" width="220" /><br/><sub>Work with Subagents</sub></td>
    <td align="center"><img src="docs/screenshots/map.png" width="220" /><br/><sub>Map Integration</sub></td>
    <td align="center"><img src="docs/screenshots/modlens.png" width="220" /><br/><sub>Better Vision Support</sub></td>
  </tr>
</table>

## Project Overview

- 🤖 **Multi-model support** — built-in configurations for more than 15 providers, plus support for OpenAI-, Anthropic-, and Gemini-compatible APIs
- 🔍 **Web search and MCP** — Bing (local), Brave, Tavily, Exa, Bocha, DeepSeek Web Search, and remote Streamable MCP servers
- 🧩 **Multi-turn sub-agent collaboration** — the main agent can delegate complex work to up to three sub-agents, guide them through multiple rounds, and consolidate their results
- 📚 **Local knowledge base** — hybrid keyword and vector RAG with built-in DOCX/XLSX parsing and OCR; files remain in the app sandbox
- 🛠️ **Built-in tools** — Canvas documents, Plan mode, Python sandbox, charts, calendar, maps and saved places, plus PDF/image/DOCX/XLSX text extraction
- 🔊 **Read aloud** — HarmonyOS offline TTS or ElevenLabs
- 🔒 **Privacy protection** — explicit permission controls and user confirmation flows for all tools

Built entirely in ArkTS, with continued emphasis on refining native HarmonyOS interactions and immersive-light materials.

## Features

### 🤖 Model and Provider Compatibility

Built-in support for more than 15 providers:

OpenAI · Claude · Gemini · DeepSeek · Grok · Ollama · OpenRouter · SiliconFlow · Qwen · Kimi · Zhipu (GLM) · Doubao · MiniMax · AiHubMix · MiMo

Custom endpoints that follow the OpenAI, Anthropic, or Gemini API specifications can also be added.

### 🔍 Web Search

Enable `web_search` under **Tool Center → Web Search**, then choose Bing (local), Brave, Tavily, Exa, Bocha, or DeepSeek Web Search. Each conversation has its own search budget, and the model requests confirmation before exceeding it.

By default, DeepSeek Web Search reads the API key from the currently selected DeepSeek provider for each search. The key is not copied into search settings, and auto mode only calls DeepSeek's official Anthropic endpoint. You can disable auto mode to configure a separate API key and Anthropic-compatible endpoint. DeepSeek Web Search makes a model request and consumes token balance on the corresponding account.

### 🧩 Parallel Sub-agents

After **Sub-agent** is enabled in the chat input tool selector, the main model can distribute multi-topic research, source comparison, and independent document processing across up to three sub-agents running in parallel, then consolidate their results. Each returned `agentId` remains available for the current main response, allowing the main model to ask follow-up questions, adjust direction, request verification, or deepen the analysis over multiple rounds.

- Each sub-agent retains its own conversation context, tool history, and search budget across follow-up rounds
- The Sub-agent Live Preview panel displays real-time output, tool calls, and execution status
- This feature requires a model with full tool-calling support

### 📚 Knowledge Base and RAG

The Knowledge Base tab accepts DOCX, XLSX, PDF, Markdown, text, and image uploads. DOCX and XLSX files are processed by the app's built-in OOXML parser, while images and scanned PDFs can use local OCR. Models retrieve material on demand through the [`knowledge_search`](entry/src/main/ets/config/KnowledgeSearchTool.ets) tool; the app neither performs retrieval in advance nor injects knowledge snippets into the system prompt.

- **Hybrid retrieval** — combines keyword and vector search with neighboring-chunk expansion to preserve content that spans chunk boundaries
- **DOCX structure extraction** — preserves headings, paragraphs, lists, line breaks, and tables as structured text suitable for semantic chunking
- **XLSX table extraction** — supports multiple worksheets, shared strings, dates, merged cells, cached formula values, and sparse-cell coordinates
- **Structure-aware chunking** — preserves page boundaries, headings, lists, tables, worksheets, and FAQ pairs
- **Two embedding options** — on-device ArkData Embedding on PC/2-in-1 devices, or any OpenAI-compatible Embedding API
- **Local data storage** — files, OCR results, indexes, and vectors are stored in the app sandbox
- **Email import** — an Email category alongside PDF, Word, spreadsheets, and images can import selected IMAP messages in one tap; message bodies, supported attachments, and inline images enter the same parsing/OCR pipeline.

> [!NOTE]
> On-device ArkData Embedding currently supports 2-in-1 devices only. Phones and tablets can use an API Embedding model; keyword retrieval remains available when no Embedding API is configured.

> [!NOTE]
> Office parsing currently supports the OOXML `.docx` and `.xlsx` formats. Legacy `.doc`/`.xls` files, encrypted files, macros, chart content, and OCR of images embedded in documents are not supported. Formulas use the cached value saved in the workbook when available; otherwise, the formula expression is preserved.

### 🛠️ Built-in Tools

| Tool                           | Function                                                                                                                                                                                                                                                                                                                        |
|--------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Context Compaction**         | Summarizes earlier turns to save context space                                                                                                                                                                                                                                                                                  |
| **Web Search**                 | Retrieves real-time information through Bing (local), Brave, Tavily, Exa, Bocha, or DeepSeek and requests user confirmation before exceeding the search budget                                                                                                                                                                   |
| **Ask User**                   | Requests additional information through a confirmation card when the model encounters a critical ambiguity                                                                                                                                                                                                                      |
| **Sub-agent**                  | Dispatches parallel sub-agents for independent tasks                                                                                                                                                                                                                                                                            |
| **Python**                     | Runs Python for calculations, data processing, and intermediate reasoning                                                                                                                                                                                                                                                       |
| **PDF to Text**                | Extracts the PDF text layer, with automatic local Core Vision Kit OCR fallback for scanned documents                                                                                                                                                                                                                            |
| **Image to Text**              | Recognizes text in images with local Core Vision Kit OCR                                                                                                                                                                                                                                                                        |
| **ModLens Vision**<sup>*</sup> | Uses [ModLens](https://github.com/liustack/modlens) to provide image OCR, layout, semantic, and visual evidence to models without native vision; requires a separate deployment                                                                                                                                                 |
| **DOCX to Text**               | Locally extracts DOCX headings, paragraphs, lists, and tables without passing the original file to models that lack document input                                                                                                                                                                                              |
| **XLSX to Text**               | Locally extracts worksheets, cells, dates, and formula results without passing the original file to models that lack document input                                                                                                                                                                                             |
| **Skill**                      | Reads instructions from enabled user skills                                                                                                                                                                                                                                                                                     |
| **Canvas Document**            | Maintains a shared document beside the conversation that both the user and AI can edit, with Markdown preview support                                                                                                                                                                                                           |
| **Plan Mode**                  | Allows the model to create a multi-step plan and update each step after it is actually completed. Only the model can modify plan status; users can open the read-only panel with `/plan` to view the active step and overall progress. Plans are stored locally per conversation and restored when the conversation is reopened |
| **Math & Charts**              | Generates [VChart](https://ohpm.openharmony.cn/#/cn/detail/@visactor%2Fharmony-vchart) line, bar, pie, scatter, Sankey, word-cloud, and other visualizations                                                                                                                                                                    |
| **Read Calendar**              | Reads calendar events after user approval                                                                                                                                                                                                                                                                                       |
| **Write Calendar**             | Creates calendar events after user approval                                                                                                                                                                                                                                                                                     |
| **Read Email**                 | Searches and reads an authorized inbox through IMAP, including locally extracted text or OCR results from supported attachments. Every model-initiated read requires explicit approval; mailbox credentials are kept in the system secure asset store and are never exposed to the model                                                                                                                    |
| **Send Email**                 | Sends mail to specified recipients through SMTP. Every model-initiated send requires explicit approval of the recipients, subject, and body; mailbox credentials are never exposed to the model                                                                                                                                 |
| **Saved Places**<sup>#</sup>   | Saves any number of labels such as “Home” or “Work” under **Settings → Tools → Saved Places** through place search, map selection, or the current precise location, allowing the model to resolve and use them by label                                                                                                         |
| **Map**                        | Uses HarmonyOS Map Kit to search for places and display the current location, destination, route polyline, precise position, and map following in the conversation                                                                                                                                                              |
| **Petal Navigation**           | Sends a searched place, coordinates, or a saved-place label to Petal Maps for route navigation                                                                                                                                                                                                                                  |

> [!IMPORTANT]
> Before using map features, open **File → Project Structure → Signing Configs → Enable open capabilities** in DevEco Studio, enable **Map Kit**, and apply the configuration. If the debug Profile predates the capability, request or download a new Profile and update the signing configuration. An app without Map Kit enabled typically receives error `1002600004`. See the [Map Kit integration guide](docs/map-kit-integration.md#上线前必须完成的控制台配置) for complete instructions.

#### <sup>*</sup> [Optional] Enable ModLens Vision for Text-only Models

HarmonyOS apps cannot directly run the Node.js CLI required by ModLens. The project therefore provides an optional lightweight companion gateway for deployment to a computer or server. Follow [`tools/modlens-gateway/README.md`](tools/modlens-gateway/README.md) to start the gateway, then open **Settings → Tools → ModLens Vision**, enter its address, test the connection, and enable the tool.

- Images are sent to the gateway and the vision provider configured in ModLens only after the gateway has been explicitly configured and the tool has been enabled
- The fallback tool is automatically hidden when the active model already has native vision capability
- `image_to_text` remains available when the gateway is unavailable or disabled, or when the model does not support tool calling

#### <sup>#</sup> Saved-place labels and coordinates are stored locally in the app and are available to the model only when the corresponding tool is enabled. Accessing the current precise location and using Map Kit require location and map permissions.

### 🔊 Read Aloud

Model responses can be read aloud from the message toolbar (**Settings → Read Aloud**):

- **Local TTS** — uses the HarmonyOS offline speech engine; no API key is required, and playback content is processed only on the device
- **ElevenLabs** — uses a user-configured API key and supports selecting a voice from the account and adjusting stability, similarity, and speed

## Getting Started

### Prerequisites

- A phone, tablet, or 2-in-1 device running HarmonyOS 7 (API 26.0.0) or later
- [DevEco Studio ≥ 26.0.0 Beta2](https://developer.huawei.com/consumer/cn/deveco-studio/)

### 1. Clone and Configure the Project

```bash
git clone https://github.com/YANGZX22/XCube.git
cd XCube
cp build-profile.json5.example build-profile.json5
# Edit build-profile.json5 and enter the signing configuration
```

### 2. Add the Speech-recognition Model (One-time Setup)

> [!NOTE]
> The ASR model is too large to include in the Git repository and must be added manually:

1. Download [sherpa-onnx SenseVoice](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2) (Chinese, English, Japanese, Korean, and Cantonese)
2. Extract the archive and move the `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` directory to `entry/src/main/resources/rawfile/`

The model directory is excluded by `.gitignore` and will not be committed to the repository.

### 3. Run

Open the project in DevEco Studio and run it on the target device.

#### Or Sideload the HAP Directly

Download the latest HAP file from the [Releases](https://github.com/YANGZX22/XCube/releases) page, then install it on the device with [Auto-installer](https://github.com/likuai2010/auto-installer/) or [DevEco Testing](https://developer.huawei.com/consumer/cn/deveco-testing/).

> [!IMPORTANT]
> Huawei's signing servers block IP addresses outside mainland China. Account for this restriction when sideloading HarmonyOS NEXT (HarmonyOS 6 or later) software in other regions.

> [!NOTE]
> Self-signed sideloaded apps are valid for 14 days by default. Completing [Developer Real-Name Authentication](https://developer.huawei.com/consumer/cn/verified/enrollment) extends the validity period to 180 days.

## License

[MIT](./LICENSE): Copyright notices for LongLiveY96's original ChatCube and the YANGZX22 continuation are preserved in full; XCube's modifications are released under the same license.
