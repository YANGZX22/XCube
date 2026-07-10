<p align="center">
  <img src="AppScope/resources/base/media/foreground.png" width="120" />
</p>

<h1 align="center">ChatCube</h1>

<p align="center">
  A native AI chat client for HarmonyOS 6.1.1 (API 24).<br/>
</p>

<p align="center">
  <a href="./README.md">简体中文</a> | <a href="./LICENSE">MIT License</a>
</p>

---

## Announcement

- 2026/07/10
> [!NOTE]
> As HarmonyOS 7 is approaching, updates to this repository will be paused briefly while the project adopts the new HarmonyOS 7 SDK and adapts to new system features.

---

## Fork Note

> [!NOTE]
> The original author has released their version on the app market, so the [upstream repository](https://github.com/LongLiveY96/ChatCube) is no longer being updated. This repository continues development based on the original project, aiming to preserve the native ArkTS experience while exploring different product ideas, interaction patterns, and capability extensions.

## About This ChatCube Fork

- This fork focuses more heavily on UI work. It is continuously refined around HarmonyOS 6 (API 23), with global immersive-light materials, immersive surfaces, and a stronger emphasis on native feel and visual polish.
- It adds web search, Canvas documents, PDF-to-text, Python sandboxing, math charts, calendar read/write, and other tools. The goal is to combine AI with phone-native capabilities while keeping tool permissions, user confirmation flows, and privacy protection explicit.
- This repository will continue exploring more native HarmonyOS SDK capabilities, richer interaction patterns, and new use cases, with ongoing iteration on the user experience.

## Latest Screens

These screenshots reflect the current HarmonyOS 6 (API 23) build:

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/IMAGE1.jpg" width="200" /><br/><sub>Chat</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE2.jpg" width="200" /><br/><sub>Conversations</sub></td>
  </tr>
</table>

## Features

### Talk to any model

Includes 15+ AI providers out of the box. You can also add any OpenAI / Anthropic / Gemini-compatible provider.

### Tools, web search, and MCP

Built-in web search supports Bocha, Bing (local), Tavily, and Exa. Models with function-calling support can invoke tools autonomously to retrieve real-time information. Remote streamable MCP servers are also supported.

### Built-in intelligent tools

ChatCube provides a set of local tools that models can call:

- **Web search**: fetch real-time information with a search budget and user-approved extra searches.
- **Canvas document**: maintain a shared document beside the conversation that both the user and AI can edit, with support for collapsing it into a floating overlay and previewing Markdown.
- **PDF / image to text**: when the model does not have native document reading enabled, uploaded PDFs are temporarily stored in the local sandbox and the model can call `pdf_to_text` to extract their contents; when vision understanding is disabled, uploaded images can be read through CoreVisionKit OCR via `image_to_text`. If the model supports the corresponding native input, the app does not intervene.
- **Python sandbox**: run necessary Python code in a sandboxed environment for calculation, data processing, and intermediate reasoning.
- **Math charts**: generate VChart specs for line, bar, area, scatter/bubble, pie, donut, rose, funnel, word cloud, Sankey, and dual-axis/combo charts.
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

- A smart device running HarmonyOS 6 (API 23) or later
- [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/)

### Build & Run

```bash
git clone https://github.com/YANGZX22/chatcube.git
cd chatcube
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

This project is forked from [LongLiveY96/ChatCube](https://github.com/LongLiveY96/ChatCube) and continues to use the [MIT License](./LICENSE).

The original copyright notice is preserved in `LICENSE`; modifications in this fork are also released under the MIT License.
