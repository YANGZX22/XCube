<p align="center">
  <img src="entry/src/main/resources/base/media/app_icon.png" width="120" />
</p>

<h1 align="center">XCube</h1>

<p align="center">
  A native AI chat client for HarmonyOS 7 (API 26.0.0).
</p>

<p align="center">
  <a href="./README.zh-CN.md">简体中文</a> | <a href="./LICENSE">MIT License</a>
</p>

> [!IMPORTANT]
> XCube requires HarmonyOS 7 (API 26.0.0) or later. If you are not a developer, or your device is still on HarmonyOS 6 or earlier, sign up for the [Huawei Beta Test Program](https://cn.club.vmall.com/mhw/assets/file-html-app/3b2bca9630d0fcb2bb2dfac09ee415ea20230529103243/index.html?ts=1785306752202#/) before installing.

---

## About XCube

- Built in ArkTS for HarmonyOS 7 (API 26.0.0), with consistent immersive-light materials and native interactions throughout.
- Ships with tools that connect the model to the device — web search, Canvas documents, PDF-to-text, a Python sandbox, math charts, and calendar read/write — while keeping tool permissions, confirmation flows, and privacy boundaries explicit.
- Development continues on more native HarmonyOS SDK capabilities, richer interaction patterns, and new use cases.

Current version: `1.2.1` (versionCode `1002001`)

> [!NOTE]
> XCube continues [YANGZX22/chatcube](https://github.com/YANGZX22/chatcube), which was originally forked from [LongLiveY96/ChatCube](https://github.com/LongLiveY96/ChatCube). Copyright and MIT license notices from both earlier versions are preserved in full.

## Latest Screens

These screenshots come from the current HarmonyOS 7 (API 26.0.0) build:

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/IMAGE2.jpg" width="200" /><br/><sub>Conversation Lists</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE3.jpg" width="200" /><br/><sub>Knowledge Base Page</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE1.jpg" width="200" /><br/><sub>Chat Page</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE4.jpg" width="200" /><br/><sub>Working with Sub-agents</sub></td>
  </tr>
</table>

## Features

### Talk to any model

15+ AI providers are included out of the box, and you can add any OpenAI-, Anthropic-, or Gemini-compatible provider yourself.

### Tools, web search, and MCP

Built-in web search covers Bocha, Bing (local), Tavily, and Exa. Models with function calling can invoke tools on their own to fetch real-time information, and remote streamable MCP servers are supported as well.

### Parallel sub-agents

When work splits cleanly — multi-topic research, source comparisons, several documents to process independently — the main model can dispatch up to three sub-agents in parallel and then synthesize their reports.

- **Isolated contexts**: each sub-agent gets its own conversation context containing nothing but the self-contained task the main model wrote for it. Sub-agents cannot dispatch further sub-agents.
- **Inherited tools, independent budgets**: sub-agents may use whichever tools are enabled for the current conversation. The main model and every sub-agent each get five web searches of their own, and any extras are approved separately by the user. With Knowledge Base on, each also gets up to five `knowledge_search` queries without drawing on another agent's allowance.
- **Live preview**: sub-agent output, tool calls, and execution status appear in the Sub-agent Live Preview panel. `ask_user` prompts open one at a time as dialogs, leaving only an expandable result row in the main conversation.

Turn on **Sub-agent** from the tool selector in the chat input area. The main model decides whether and how to split the request, so the selected model must fully support tool calling.

### Read aloud with local TTS or ElevenLabs

AI replies can be played straight from the message toolbar. Open **Settings → Read Aloud** to enable the feature and pick a speech engine:

- **Local TTS**: uses the HarmonyOS offline text-to-speech engine. No API key required, and no reply text is sent to ElevenLabs.
- **[ElevenLabs API](https://elevenlabs.io/docs/overview/capabilities/text-to-speech)**: accepts a custom API base URL and key, loads the account's available voices into a Voice ID selector, and offers the `eleven_multilingual_v2`, `eleven_flash_v2_5`, and `eleven_v3` models.
- **Voice controls**: ElevenLabs mode exposes stability, similarity, and speed. Long replies are split at natural sentence boundaries and played in sequence.
- **Privacy**: the ElevenLabs API key is stored in the app's local preferences, and in ElevenLabs mode the reply text is sent to the configured endpoint for synthesis.

### Vector knowledge base and RAG

A dedicated Knowledge Base tab handles uploading, managing, and previewing reference material in one place. Models retrieve from it on demand through the [`knowledge_search`](entry/src/main/ets/config/KnowledgeSearchTool.ets) tool.

- **One file entry point**: accepts PDF, TXT, Markdown, and JPG, JPEG, PNG, WebP, and BMP images. Images are indexed through OCR, and PDFs that yield too little extracted text fall back to page-image OCR automatically.
- **Structure-aware semantic chunking**: the chunker preserves PDF/OCR page boundaries, Markdown headings, paragraphs, lists, tables, and FAQ pairs, then adds adaptive semantic breakpoints derived from adjacent-unit embeddings. Every vector is contextualized with its file name, heading path, and page number. If embedding fails, chunking falls back to deterministic structure-aware splits rather than blocking keyword indexing.
- **Hybrid retrieval with surrounding context**: chunks land in both a keyword index and an ArkData vector sidecar. Search merges keyword and vector recall, then expands each precise hit with at most one related parent or neighbor chunk on either side, so an answer that spans a boundary is less likely to be cut off. Keyword retrieval stays available if vector generation or the sidecar fails.
- **Two embedding sources**: [PC/2-in-1](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/support-device#section36331990919) devices can use local ArkData Embedding, which keeps document chunks on-device. You can also select a configured OpenAI-compatible embedding API — that mode sends chunks to the provider, so choose it according to how sensitive your files are.
- **Strict tool-call boundary**: enabling Knowledge Base in the input bar only exposes the tool to the model. The app never pre-retrieves content or injects knowledge into the system prompt; retrieval — and API query embedding, when needed — begins only once the model actually calls `knowledge_search`.
- **First-query recovery**: after a real tool call, the first query waits briefly for an existing vector sidecar to reopen. A newly created or stale Data Augmentation Kit retriever may retry once on a cold empty result, while ordinary cached no-hit results are not queried twice.
- **Focused follow-up search**: each user turn allows at most five knowledge queries and should stop early once a complete hit arrives. If a result is truncated and leaves a clear gap, the model may issue a narrower, non-duplicate query.
- **Local management**: original files, OCR/text results, keyword indexes, and the vector sidecar all stay in the app sandbox. Files can be previewed, refreshed, or deleted; refreshing rebuilds indexes with the currently selected embedding backend.

To use it:

1. Open the Knowledge Base tab and upload files with the plus button.
2. Use the embedding-model button in the upper-right corner to select local ArkData or an API embedding model, then refresh indexes if needed.
3. Return to chat, turn on Knowledge Base in the input bar, and ask your question. The model decides when and how often to search.

> [!NOTE]
> ArkData application data vectorization currently supports 2-in-1 devices only. Phones and tablets should use an API embedding model; keyword retrieval still works when no API is configured. Vector-store persistence itself remains local through ArkData.

### Built-in intelligent tools

XCube gives models a set of local tools to call:

- **Sub agent**: run one to three independent subtasks in parallel, each in an isolated context, and return their reports to the main model for synthesis.
- **Web search**: fetch real-time information within a search budget, with extra searches approved by the user.
- **Canvas document**: keep a shared document beside the conversation that both the user and the AI can edit, collapsible into a floating overlay and previewable as Markdown.
- **PDF / image to text**: when a model lacks native document reading, uploaded PDFs are held in the local sandbox and the model can call `pdf_to_text` to extract their contents; when vision understanding is off, uploaded images can be read through CoreVisionKit OCR via `image_to_text`. If the model supports the corresponding native input, the app stays out of the way.
- **Python sandbox**: run Python in a sandboxed environment for calculation, data processing, and intermediate reasoning.
- **Math charts**: generate [VChart](https://ohpm.openharmony.cn/#/cn/detail/@visactor%2Fharmony-vchart) specs for line, bar, area, scatter/bubble, pie, donut, rose, funnel, word cloud, Sankey, and dual-axis/combo charts.
- **Calendar read/write**: read a user-confirmed date range or create new events. Users can adjust the range, limits, location, and note visibility to protect their privacy.
- **Ask user**: let the model raise a card asking for confirmation when it hits a critical ambiguity.

## Supported Providers

| Provider | API Format | Notes |
|----------|-----------|-------|
| OpenAI | OpenAI |  |
| Claude | Anthropic |  |
| DeepSeek | OpenAI-compatible | deepseek-v4-pro/flash |
| Gemini | Google |  |
| Grok | OpenAI-compatible | xAI models |
| Ollama | OpenAI-compatible | Local models |
| OpenRouter | OpenAI-compatible | Multi-provider gateway |
| SiliconFlow | OpenAI-compatible | Chinese AI models |
| Qwen (Alibaba) | OpenAI-compatible | Qwen series |
| Kimi | OpenAI-compatible | Moonshot / Kimi models |
| Zhipu AI | OpenAI-compatible | GLM series |
| Doubao (Volcengine) | OpenAI-compatible | Doubao series |
| MiniMax | OpenAI-compatible | MiniMax models |
| AiHubMix | OpenAI-compatible | Multi-provider gateway |
| MiMo | OpenAI-compatible | Xiaomi MiMo models |

Any other OpenAI-compatible or Anthropic-compatible provider can be added manually.

## Build and Run

### Requirements

- A device running HarmonyOS 7 (API 26.0.0)
- [DevEco Studio (>= 26.0.0 Beta2)](https://developer.huawei.com/consumer/cn/deveco-studio/)

### Add the speech-recognition model

The model is too large to store in Git, so add it manually before building:

1. Download [sherpa-onnx SenseVoice (Chinese, English, Japanese, Korean, and Cantonese)](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2).
2. Extract the archive.
3. Move the extracted `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` directory into `entry/src/main/resources/rawfile/`.

The model directory and all `*.onnx` files are ignored by `.gitignore` and will never be committed.

### Clone and configure

```bash
git clone https://github.com/YANGZX22/XCube.git
cd XCube
cp build-profile.json5.example build-profile.json5
# Edit build-profile.json5 with your signing config
```

Then open the project in DevEco Studio and run it on your device.

## Deploying the HAP

Install the HAP directly on your device with [Auto-installer](https://github.com/likuai2010/auto-installer/) or [DevEco Testing](https://developer.huawei.com/consumer/cn/deveco-testing/).

> [!IMPORTANT]
> Huawei's signing servers block IP addresses outside mainland China — keep this in mind when sideloading HarmonyOS NEXT software elsewhere.

> [!NOTE]
> Apps sideloaded through self-signing on HarmonyOS NEXT are valid for 14 days by default. Completing [Developer Real-Name Authentication](https://developer.huawei.com/consumer/cn/verified/enrollment) extends that to 180 days.

## License

XCube remains under the [MIT License](./LICENSE). Copyright notices for LongLiveY96's original ChatCube and the YANGZX22 continuation are preserved, and subsequent XCube modifications are released under the same license.
