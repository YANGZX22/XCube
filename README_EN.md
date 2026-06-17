<p align="center">
  <img src="AppScope/resources/base/media/foreground.png" width="120" />
</p>

<h1 align="center">ChatCube</h1>

<p align="center">
  A native AI chat client for HarmonyOS 6.1.1 (API 24).<br/>
  One app, 15+ providers, web search, Canvas docs, PDF2TXT, built-in tools, MCP, and ArkTS-native UX.
</p>

<p align="center">
  <a href="./README.md">简体中文</a> · <a href="./LICENSE">MIT License</a>
</p>

---

## Fork Note

> [!NOTE]
> The original author has released their version on the app market, so the [upstream repository](https://github.com/LongLiveY96/ChatCube) is no longer being updated. This repository continues development based on the original project, aiming to preserve the native ArkTS experience while exploring different product ideas, interaction patterns, and capability extensions.

## About This ChatCube Fork

- This fork focuses more heavily on UI work. It is continuously refined around HarmonyOS 6 (API 23), with global immersive-light materials, immersive surfaces, and a stronger emphasis on native feel and visual polish.
- It adds web search, Canvas documents, PDF-to-text, Python sandboxing, math charts, calendar read/write, and other tools. The goal is to combine AI with phone-native capabilities while keeping tool permissions, user confirmation flows, and privacy protection explicit.
- This project will continue exploring more native HarmonyOS SDK capabilities, richer interaction patterns, and new use cases, with ongoing iteration on the user experience.

## Latest Screens

These screenshots reflect the current HarmonyOS 6 (API 23) build:

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/IMAGE1.jpg" width="200" /><br/><sub>Chat</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE2.jpg" width="200" /><br/><sub>Conversations</sub></td>
    <td align="center"><img src="docs/screenshots/providers_new.jpg" width="200" /><br/><sub>Providers</sub></td>
  </tr>
</table>

## Features

### Talk to any model

Connect to 15+ AI providers out of the box. Bring your own API key, pick a model, and start chatting. Add any OpenAI / Anthropic / Gemini compatible provider in seconds.

### Tools, web search, and MCP

Built-in web search supports Bocha, Bing(local), Tavily, and Exa. When a model supports function calling, it can use tools directly, and the tools center can also connect to remote streamable MCP servers.

### Built-in intelligent tools

ChatCube includes local tools that capable models can call directly from a conversation:

- **Web search**: fetch real-time information with a search budget and user-approved extra searches.
- **Canvas document**: maintain a shared document beside the conversation that both the user and AI can edit, with a collapsible floating entry, Markdown preview, and version hints.
- **PDF / image to text**: when the current model does not have native document reading enabled, uploaded PDFs are temporarily registered in the local sandbox and the model can call `pdf_to_text`; when vision understanding is disabled, uploaded images can be read through CoreVisionKit OCR via `image_to_text`. If the model supports the corresponding native input, the app leaves the upload path untouched.
- **Python sandbox**: run necessary Python code in a sandboxed environment for calculation, data processing, and intermediate reasoning.
- **Math charts**: generate VChart specs for line, bar, area, scatter/bubble, pie, donut, rose, funnel, word cloud, Sankey, and dual-axis/combo charts.
- **Calendar read/write**: read a user-confirmed date range or create new schedule events; users can adjust range, limits, location, and note visibility to protect privacy.
- **Ask user**: let the model ask for clarification through a dedicated card when guessing would be risky.

Tool calls follow permission and confirmation flows. Operations involving system data or writes show an approval UI first; if the user refuses, the model continues with the information already available.

### Markdown & beyond

Full markdown rendering — code blocks with syntax highlighting, tables, LaTeX formulas, images. Even raw HTML gets a live preview.

### Looks good, feels good

8 color themes. Dark / Light / System mode. API 23 materials, immersive glass-like effects, and real-time blur are all part of the current visual system. A UI that feels native because it is native.

### Phone & tablet ready

Responsive layouts for phones and HarmonyOS tablets. Chat, settings, and provider management all stay comfortable on larger screens.

### Smart Grip

Detects which hand you're holding the phone with and moves the "New Chat" button to the reachable side. One-handed use, done right.

### Your data, your rules

Export and import everything — conversations, provider configs, preferences. JSON format, no lock-in.

### Stays alive in the background

Switch to another app while waiting for a long response. ChatCube keeps working and notifies you when the reply is ready.

## Supported Providers

| Provider | API Format | Notes |
|----------|-----------|-------|
| OpenAI | OpenAI | GPT-4o, o1, etc. |
| Claude | Anthropic | Claude 4, 3.5, etc. |
| DeepSeek | OpenAI-compatible | DeepSeek-V3, R1, etc. |
| Gemini | Google | Gemini 2.5, etc. |
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

...or add any compatible provider yourself.

## Getting Started

### Requirements

- HarmonyOS 6 (API 23)
- DevEco Studio 5.0+

### Build & Run

```bash
git clone https://github.com/YANGZX22/chatcube.git
cd chatcube
cp build-profile.json5.example build-profile.json5
# Edit build-profile.json5 with your signing config
```

Open in DevEco Studio → Sync → Run.

### Configure providers

In the app: **Settings → Provider Management** → add your API keys.

## License

This project is forked from [LongLiveY96/ChatCube](https://github.com/LongLiveY96/ChatCube) and continues to use the [MIT License](./LICENSE).

The original copyright notice is preserved in `LICENSE`; modifications in this fork are also released under the MIT License.
