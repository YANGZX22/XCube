<p align="center">
  <img src="entry/src/main/resources/base/media/app_icon.png" width="120" />
</p>

<h1 align="center">XCube</h1>

<p align="center">
  A native AI chat client for HarmonyOS 7 (API 26.0.0).<br/>
</p>

<p align="center">
  <a href="./README.zh-CN.md">简体中文</a> | <a href="./LICENSE">MIT License</a>
</p>

> [!IMPORTANT]
> XCube runs only on devices with HarmonyOS 7 (API 26.0.0) or later. If you are not a developer or are still on HarmonyOS 6 or earlier, please sign up for the [Huawei Beta Test Program](https://cn.club.vmall.com/mhw/assets/file-html-app/3b2bca9630d0fcb2bb2dfac09ee415ea20230529103243/index.html?ts=1785306752202#/) to install this app.

---

## Project Origin

> [!NOTE]
> XCube is the continuation of [YANGZX22/chatcube](https://github.com/YANGZX22/chatcube). That version was originally forked from [LongLiveY96/ChatCube](https://github.com/LongLiveY96/ChatCube). Copyright and MIT license notices from both earlier versions are preserved in full.

## About XCube

- XCube focuses on a native ArkTS experience for HarmonyOS 7 (API 26.0.0), with consistent immersive-light materials and polished native interactions.
- It adds web search, Canvas documents, PDF-to-text, Python sandboxing, math charts, calendar read/write, and other tools. The goal is to combine AI with phone-native capabilities while keeping tool permissions, user confirmation flows, and privacy protection explicit.
- This repository will continue exploring more native HarmonyOS SDK capabilities, richer interaction patterns, and new use cases, with ongoing iteration on the user experience.

### Release Identity

- App name: XCube
- Current version: `1.2.1` (versionCode `1002001`)

## Latest Screens

These screenshots reflect the current HarmonyOS 7 (API 26.0.0) build:

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

Includes 15+ AI providers out of the box. You can also add any OpenAI / Anthropic / Gemini-compatible provider.

### Tools, web search, and MCP

Built-in web search supports Bocha, Bing (local), Tavily, and Exa. Models with function-calling support can invoke tools autonomously to retrieve real-time information. Remote streamable MCP servers are also supported.

### Parallel sub-agents

XCube includes a Sub-agent tool for decomposable work such as multi-topic research, source comparisons, or processing several documents independently. The main model can dispatch up to three sub-agents in parallel and then synthesize their reports:

- **Isolated contexts**: each sub-agent receives an independent conversation context containing only the self-contained task written for it by the main model. Sub-agents cannot recursively dispatch more sub-agents.
- **Inherited tools and independent budgets**: sub-agents can use the tools enabled for the current conversation. The main model and every sub-agent each receive five default web searches of their own, with extra searches approved separately by the user. When Knowledge Base is on, each also receives up to five `knowledge_search` queries without consuming another agent's allowance.
- **Live preview**: sub-agent output, tool calls, and execution status appear in the Sub-agent Live Preview panel. `ask_user` prompts open one at a time as dialogs, while the main conversation retains only an expandable result row.

Enable **Sub-agent** from the tool selector in the chat input area. The main model decides whether and how to split the request; the selected model must fully support tool calling.

### Read aloud with local TTS or ElevenLabs

AI replies can be played directly from the message toolbar. Open **Settings → Read Aloud** to enable the feature and choose either speech engine:

- **Local TTS**: uses the HarmonyOS system offline text-to-speech engine. It does not require an API key and does not send reply text to ElevenLabs.
- **[ElevenLabs API](https://elevenlabs.io/docs/overview/capabilities/text-to-speech)**: supports a custom API Base URL and API Key, loads the voices available to the account into a Voice ID selector, and provides `eleven_multilingual_v2`, `eleven_flash_v2_5`, and `eleven_v3` model choices.
- **Voice controls**: ElevenLabs mode exposes stability, similarity, and speed settings. Long replies are split at natural sentence boundaries and played in sequence.
- **Privacy**: the ElevenLabs API Key is stored in the app's local preferences. When ElevenLabs mode is used, the reply text is sent to the configured API endpoint for speech synthesis.

### Vector knowledge base and RAG

XCube includes a dedicated Knowledge Base tab for uploading, managing, and previewing reference material in one place. Models retrieve it on demand through the
[`knowledge_search`](entry/src/main/ets/config/KnowledgeSearchTool.ets) tool:

- **One file entry point**: supports PDF, TXT, Markdown, and JPG, JPEG, PNG, WebP, and BMP images. Images are indexed through OCR; PDFs with too little extracted text automatically fall back to page-image OCR.
- **Structure-aware semantic chunking**: the chunker preserves PDF/OCR page boundaries, Markdown headings, paragraphs, lists, tables, and FAQ pairs, then adds adaptive semantic breakpoints from adjacent-unit embeddings. Each vector is contextualized with the file name, heading path, and page number; embedding failure falls back to deterministic structure-aware chunks instead of blocking keyword indexing.
- **Hybrid retrieval with surrounding context**: chunks are indexed in both a keyword index and an ArkData vector sidecar. Search merges keyword and vector recall, then expands a precise hit with at most one related parent/neighbor chunk on each side so a boundary-spanning answer is less likely to be cut off. Keyword retrieval remains available if vector generation or the vector sidecar fails.
- **Two embedding sources**: [PC/2in1](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/support-device#section36331990919) devices can use local ArkData Embedding without sending document chunks off-device. You can also select a configured OpenAI-compatible Embedding API. API mode sends document chunks to the selected provider, so choose it according to the sensitivity of your files.
- **Strict tool-call boundary**: enabling Knowledge Base in the input bar exposes the tool to the model, but the app does not pre-retrieve content or inject knowledge into the system prompt. Retrieval—and API query embedding when needed—starts only after the model actually calls `knowledge_search`.
- **First-query recovery**: after a real tool call, the first query briefly waits for an existing vector sidecar to reopen. A newly created or stale Data Augmentation Kit retriever may retry once on a cold empty result; ordinary cached no-hit results are not queried twice.
- **Focused follow-up search**: each user turn allows at most five knowledge queries and should stop early after a complete hit. If a result is truncated and has a clear information gap, the model may issue a narrower, non-duplicate query.
- **Local management**: original files, OCR/text results, keyword indexes, and the vector sidecar remain in the app sandbox. Files can be previewed, refreshed, or deleted; refreshing rebuilds indexes with the currently selected embedding backend.

To use it:

1. Open the Knowledge Base tab and use the plus button to upload files.
2. Use the embedding-model button in the upper-right corner to select local ArkData or an API Embedding model, then refresh indexes when needed.
3. Return to chat, turn on Knowledge Base in the input bar, and ask your question. The model decides when and how often to search.

> [!NOTE]
> ArkData application data vectorization currently supports only 2-in-1 devices. Phones and tablets should use API Embedding; keyword knowledge retrieval remains available when no API is configured. Vector-store persistence itself still runs locally through ArkData.

### Built-in intelligent tools

XCube provides a set of local tools that models can call:

- **Sub-agent**: run one to three independent subtasks in parallel, each in an isolated context, and return their reports to the main model for synthesis.
- **Web search**: fetch real-time information with a search budget and user-approved extra searches.
- **Canvas document**: maintain a shared document beside the conversation that both the user and AI can edit, with support for collapsing it into a floating overlay and previewing Markdown.
- **PDF / image to text**: when the model does not have native document reading enabled, uploaded PDFs are temporarily stored in the local sandbox and the model can call `pdf_to_text` to extract their contents; when vision understanding is disabled, uploaded images can be read through CoreVisionKit OCR via `image_to_text`. If the model supports the corresponding native input, the app does not intervene.
- **Python sandbox**: run necessary Python code in a sandboxed environment for calculation, data processing, and intermediate reasoning.
- **Math charts**: generate [VChart](https://ohpm.openharmony.cn/#/cn/detail/@visactor%2Fharmony-vchart) specs for line, bar, area, scatter/bubble, pie, donut, rose, funnel, word cloud, Sankey, and dual-axis/combo charts.
- **Calendar read/write**: read a user-confirmed date range or create new schedule events; users can adjust range, limits, location, and note visibility to protect privacy.
- **Ask user**: let the model ask the user for confirmation through a card when it encounters a critical ambiguity.

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

You can also add any OpenAI-compatible or Anthropic-compatible provider.

## Build and Run

### Requirements

- A smart device running HarmonyOS 7 (API 26.0.0)
- [DevEco Studio (>= 26.0.0 Beta2)](https://developer.huawei.com/consumer/cn/deveco-studio/)

### Build & Run

The speech-recognition model is too large to store in Git and must be added manually before building:

1. Download [sherpa-onnx SenseVoice (Chinese, English, Japanese, Korean, and Cantonese)](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2).
2. Extract the archive.
3. Place the extracted `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` directory in `entry/src/main/resources/rawfile/`.

The model directory and all `*.onnx` files are excluded by `.gitignore` and will not be committed to the repository.

```bash
git clone https://github.com/YANGZX22/XCube.git
cd XCube
cp build-profile.json5.example build-profile.json5
# Edit build-profile.json5 with your signing config
```

## Deploying the HAP

Install the HAP file directly on your device using [Auto-installer](https://github.com/likuai2010/auto-installer/) or [DevEco Testing](https://developer.huawei.com/consumer/cn/deveco-testing/).

> [!IMPORTANT]
> Huawei's signing servers block IP addresses outside mainland China. Keep this in mind when sideloading HarmonyOS NEXT software in countries or regions outside mainland China.

> [!NOTE]
> Apps sideloaded through self-signing on HarmonyOS NEXT are valid for 14 days by default. Completing [Developer Real-Name Authentication](https://developer.huawei.com/consumer/cn/verified/enrollment) extends this period to 180 days.

## License

XCube continues to use the [MIT License](./LICENSE). Copyright notices for LongLiveY96's original ChatCube version and the YANGZX22 continuation are preserved; subsequent XCube modifications are released under the same MIT License.
