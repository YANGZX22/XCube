<p align="center">
  <img src="entry/src/main/resources/base/media/app_icon.png" width="120" />
</p>

<h1 align="center">XCube</h1>

<p align="center">
  A native AI agent harness for HarmonyOS 7.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/HarmonyOS-7_(API_26)-4285F4" alt="HarmonyOS 7" />
  <a href="./CHANGELOG.md"><img src="https://img.shields.io/badge/version-2.0.10-2ea44f" alt="Version 2.0.10" /></a>
  <a href="https://appgallery.huawei.com/link/invite-test-wap?taskId=ea479545cdb1a7d831163c11b530b911&invitationCode=29VdBr62t8H"><img src="https://img.shields.io/badge/download-2.0.1-CF0A2C" alt="Version 2.0.1 invitation testing link" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License" /></a>
</p>

<p align="center">
  <a href="./README.zh-CN.md">简体中文</a> · <a href="#features">Features</a> · <a href="#getting-started">Getting Started</a> · <a href="./CHANGELOG.md">Changelog</a>
</p>

## Latest Information

> [!IMPORTANT]
> **Immersive Light compatibility:** Starting with HarmonyOS `7.0.0.105` (API 26), the system [restricts](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-overview#约束与限制) application-level and component-level Immersive Light on ordinary ArkUI components. XCube has adapted to this restriction and is working to restore the same visual quality as before it took effect. Update your device to HarmonyOS 7 or later for the best experience. Compatibility work is still ongoing.

> [!NOTE]
> XCube continues [YANGZX22/chatcube](https://github.com/YANGZX22/chatcube), which was originally forked from [LongLiveY96/ChatCube](https://github.com/LongLiveY96/ChatCube). Copyright and MIT license notices from both earlier versions are preserved in full.

## Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/multi-tools.png" width="220" /><br/><sub>Work using Multiple Tools</sub></td>
    <td align="center"><img src="docs/screenshots/new-python.png" width="220" /><br/><sub>Work with Python Packages</sub></td>
    <td align="center"><img src="docs/screenshots/answer-using-knowledge-base.png" width="220" /><br/><sub>Work in RAG</sub></td>
    <td align="center"><img src="docs/screenshots/work-with-sub-agents.png" width="220" /><br/><sub>Work with Subagents</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/map.png" width="220" /><br/><sub>Maps and Navigation</sub></td>
    <td align="center"><img src="docs/screenshots/modlens.png" width="220" /><br/><sub>Enhanced Vision Support</sub></td>
    <td align="center"><img src="docs/screenshots/complicated-projects.png" width="220" /><br/><sub> Complex Projects</sub></td>
    <td align="center"><img src="docs/screenshots/workspace.png" width="220" /><br/><sub>Workspace</sub></td>
  </tr>
</table>

## Project Overview

XCube is built entirely in native ArkTS. It aims to bring Immersive Light across the interface while continually refining the native experience and visual quality.

- **Multi-model support** — built-in configurations for more than 15 providers, plus support for OpenAI-, Anthropic-, and Gemini-compatible APIs
- **Web search and MCP** — Bing (local), Brave, Tavily, Exa, Bocha, DeepSeek Web Search, and remote Streamable MCP servers
- **Multi-turn sub-agent collaboration** — the main agent can delegate complex work to up to three sub-agents, guide them through multiple rounds, and consolidate their results
- **Local knowledge base** — hybrid keyword and vector RAG with built-in DOCX/XLSX parsing and OCR; files remain in the app sandbox
- **Conversation workspace** — stores files per conversation for users to manage and preview, and for the main agent and sub-agents to process together through Python tools
- **Built-in tools** — Canvas documents, Plan mode, Python sandbox, charts, calendar, maps and saved places, plus PDF/image/DOCX/XLSX toolkits that hand models the original file, rendered pages, or extracted text
- **Read aloud** — HarmonyOS offline TTS or ElevenLabs
- **Privacy protection** — explicit permission controls and user confirmation flows for all tools

## Features

### 🤖 Model and Provider Compatibility

Built-in support for more than 15 providers:

OpenAI · Claude · Gemini · DeepSeek · Grok · Ollama · OpenRouter · SiliconFlow · Qwen · Kimi · Z.ai (Zhipu) · Doubao · MiniMax · AiHubMix · MiMo

Custom endpoints that follow the OpenAI, Anthropic, or Gemini API specifications can also be added.

### 📁 Conversation Workspace

Tap **Workspace** in the chat input area to browse the current conversation's file tree and preview files. Each conversation has its own workspace in the app sandbox.

- **Manage files** — long-press an empty area in the root directory to upload a file or create a file or folder; long-press a folder to upload or create inside it, or delete it recursively; long-press a file to delete it.
- **Work with models** — when the **Python** tool is enabled, the main agent and sub-agents share the current conversation's workspace. Models can read files, create or edit text and Python scripts, and run Python to process workspace files. Operations within a conversation run in order, and edits to the same file are checked for version conflicts.

A workspace can hold up to 64 files and 512 folders. Each file is limited to 16 MiB, and the total file size is limited to 32 MiB. Installing additional Python packages may require network access.

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
- **One-tap email import** — an Email category alongside PDF, Word, spreadsheets, and images is available in the knowledge base

> [!NOTE]
> XCube supports native ArkTS ArkData Embedding, but only on 2-in-1 devices. Other devices can use an OpenAI API-compatible Embedding model.

### 🛠️ Built-in Tools

| Tool                           | Function                                                                                                                                                                                                                                                                                                                        |
|--------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Context Compaction**         | Summarizes earlier turns to save context space                                                                                                                                                                                                                                                                                  |
| **Web Search**                 | Retrieves real-time information through Bing (local), Brave, Tavily, Exa, Bocha, or DeepSeek and requests user confirmation before exceeding the search budget                                                                                                                                                                   |
| **Ask User**                   | Requests additional information through a confirmation card when the model encounters a critical ambiguity                                                                                                                                                                                                                      |
| **Sub-agent**                  | Dispatches parallel sub-agents for independent tasks                                                                                                                                                                                                                                                                            |
| **Python**                     | Runs Python for calculations, data processing, and intermediate reasoning                                                                                                                                                                                                                                                       |
| **PDF Toolkit**                | Hands the original PDF to models with native document input; can render a chosen page range to images for models with vision; otherwise extracts the PDF text layer, with automatic local Core Vision Kit OCR fallback for scans                                                                                                |
| **Image Toolkit**              | Hands the original image to models with native vision; otherwise recognizes text in images with local Core Vision Kit OCR                                                                                                                                                                                                       |
| **Vision**<sup>*</sup>         | Hands the original image to models with native vision; otherwise uses [ModLens](https://github.com/liustack/modlens) to provide image OCR, layout, semantic, and visual evidence, which requires a separate deployment                                                                                                          |
| **DOCX Toolkit**               | Hands the original DOCX to models with native document input; otherwise locally extracts headings, paragraphs, lists, and tables without passing the file itself                                                                                                                                                                |
| **XLSX Toolkit**               | Hands the original XLSX to models with native document input; otherwise locally extracts worksheets, cells, dates, and formula results without passing the file itself                                                                                                                                                          |
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
> Before using map features, open **File → Project Structure → Signing Configs → Enable open capabilities** in DevEco Studio, enable **Map Kit**, and apply the configuration. If the debug Profile predates the capability, request or download a new Profile and update the signing configuration.

#### <sup>*</sup> [Optional] Enable ModLens behind the Vision Tool for Text-only Models

HarmonyOS apps cannot directly run the Node.js CLI required by ModLens. The project therefore provides an optional lightweight companion gateway for deployment to a computer or server. Follow [`tools/modlens-gateway/README.md`](tools/modlens-gateway/README.md) to start the gateway, then open **Settings → Tools → Vision**, enter its address, test the connection, and enable the tool.

- Images are sent to the gateway and the vision provider configured in ModLens only after the gateway has been explicitly configured and the tool has been enabled
- The tool stays available to models that already have native vision, but it then returns the original image as native input in the same round instead of calling the gateway
- `image_toolkit` remains available when the gateway is unavailable or disabled, or when the model does not support tool calling

#### <sup>#</sup> Saved-place labels and coordinates are stored locally in the app and are available to the model only when the corresponding tool is enabled. Accessing the current precise location and using Map Kit require location and map permissions.

## Getting Started

### 1. Install from the [Invitation Testing Link](https://appgallery.huawei.com/link/invite-test-wap?taskId=ea479545cdb1a7d831163c11b530b911) (Recommended)

### 2. Build Locally

### Requirements

- A device running HarmonyOS 7 (API 26.0.0) or later
- [DevEco Studio ≥ 26.0.0](https://developer.huawei.com/consumer/cn/deveco-studio/)

#### A. Clone and Configure the Project

```bash
git clone https://github.com/YANGZX22/XCube.git
cd XCube
cp build-profile.json5.example build-profile.json5
# Edit build-profile.json5 and enter the signing configuration
```

#### B. Add the Speech-recognition Model (One-time Setup)

> [!NOTE]
> The ASR model is too large to include in the Git repository and must be added manually:

1. Download [sherpa-onnx SenseVoice](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2) (Chinese, English, Japanese, Korean, and Cantonese)
2. Extract the archive and move the `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` directory to `entry/src/main/resources/rawfile/`

The model directory is excluded by `.gitignore` and will not be committed to the repository.

#### C. Run

Open the project in DevEco Studio and run it on the target device.

### 3. Sideload the HAP (Stop updates)

Download the latest HAP file from the [Releases](https://github.com/YANGZX22/XCube/releases) page, then install it on the device with [Auto-installer](https://github.com/likuai2010/auto-installer/) or [DevEco Testing](https://developer.huawei.com/consumer/cn/deveco-testing/).

> [!IMPORTANT]
> Huawei's signing servers block IP addresses outside mainland China. Account for this restriction when sideloading HarmonyOS NEXT (HarmonyOS 6 or later) software in other regions.

> [!NOTE]
> Self-signed sideloaded apps are valid for 14 days by default. Completing [Developer Real-Name Authentication](https://developer.huawei.com/consumer/cn/verified/enrollment) extends the validity period to 180 days.

## License

[MIT](./LICENSE): Copyright notices for LongLiveY96's original ChatCube and the YANGZX22 continuation are preserved in full; XCube's modifications are released under the same license.
