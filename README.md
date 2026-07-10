<p align="center">
  <img src="AppScope/resources/base/media/foreground.png" width="120" />
</p>

<h1 align="center">ChatCube</h1>

<p align="center">
  一个面向鸿蒙 6.1.1（API 24）的原生 AI 聊天客户端。<br/>
</p>

<p align="center">
  <a href="./README.en-US.md">English</a> | <a href="./LICENSE">MIT License</a>
</p>

---

## 公告

- 2026/07/10
> [!NOTE]
> 由于 HarmonyOS 7 即将上线，本仓库将短暂暂停更新一段时间，以应用新的 HarmonyOS 7 SDK 并适应新的系统特性。

---

## Fork 说明

> [!NOTE]
> 原作者已将其版本上架应用市场，因此[原仓库](https://github.com/LongLiveY96/ChatCube)目前已停止更新。本仓库基于原项目继续维护，旨在保留原生 ArkTS 体验的基础上，尝试更多不一样的产品思路、交互方案和能力扩展。

## 关于本 ChatCube 分支

- 更加着手于 UI, 围绕鸿蒙 6（API 23）持续打磨，强调沉浸光感的全局性、沉浸式界面，力求在原生体验和视觉质感上都做到极致
- 补充联网搜索、Canvas 文档、PDF 转文本、Python 沙箱、数学绘图、读写日程等工具，致力于结合 AI 与手机本身功能交互并提供工具调用权限和用户确认流程以及隐私保护
- 本仓库将尝试更多原生 HarmonyOS SDK 能力，探索更丰富的交互方式和使用场景，持续迭代优化用户体验

## 最新界面预览

以下截图基于当前鸿蒙 6（API 23）版本：

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/IMAGE1.jpg" width="200" /><br/><sub>对话</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE2.jpg" width="200" /><br/><sub>会话</sub></td>
  </tr>
</table>

## 功能特性

### 和任何模型对话

内置 15+ AI 服务商。支持自定义添加任何 OpenAI / Anthropic / Gemini 兼容的服务商。

### 工具、联网搜索与 MCP

内置联网搜索，支持 博查、Bing (local)、Tavily、Exa。支持 Function Calling 的模型可以自主调用工具获取实时信息。支持接入远端 streamable MCP Server。

### 内置智能工具

ChatCube 提供一组可由模型调用的本地工具：

- **联网搜索**：按需获取实时信息，支持搜索次数预算与用户确认追加搜索。
- **Canvas 文档**：在对话右侧维护一份用户和 AI 都能修改的共享文档，支持隐藏到浮层和 Markdown 预览。
- **PDF / 图片转文本**：当模型未开启原生文档阅读能力时，用户上传的 PDF 会暂存到本地沙箱，模型可调用 `pdf_to_text` 获取文本内容；当模型未开启视觉理解时，用户上传的图片可通过 `image_to_text` 调用 CoreVisionKit OCR 识别文字。若模型支持对应原生输入，应用不额外干预。
- **Python 沙箱**：在沙箱化环境中执行必要的 Python 代码，用于计算、数据处理和中间推导。
- **数学绘图**：基于 [VChart](https://ohpm.openharmony.cn/#/cn/detail/@visactor%2Fharmony-vchart) 生成结构化图表，支持折线图、柱状图、面积图、散点/气泡图、饼图、环形图、玫瑰图、漏斗图、词云图、桑基图、双轴/柱线组合图等。
- **读写日程**：经用户确认后读取指定范围内的日程，或写入新的日程事件；读取范围、数量、地点和备注等隐私字段可由用户确认和调整。
- **向用户提问**：模型遇到关键歧义时，可以通过卡片向用户确认。

## 支持的服务商

| 服务商 | API 格式 | 说明 |
|--------|---------|------|
| OpenAI | OpenAI |  |
| Claude | Anthropic |  |
| DeepSeek | OpenAI 兼容 | deepseek-v4-pro/flash |
| Gemini | Google |  |
| Grok | OpenAI 兼容 | xAI 模型 |
| Ollama | OpenAI 兼容 | 本地模型 |
| OpenRouter | OpenAI 兼容 | 多服务商网关 |
| 硅基流动 | OpenAI 兼容 | 国产 AI 模型 |
| 阿里云百炼 | OpenAI 兼容 | 通义千问系列 |
| Kimi | OpenAI 兼容 | Moonshot / Kimi 模型 |
| 智谱 AI | OpenAI 兼容 | GLM 系列 |
| 火山引擎 | OpenAI 兼容 | 豆包系列 |
| MiniMax | OpenAI 兼容 | MiniMax 模型 |
| AiHubMix | OpenAI 兼容 | 多服务商网关 |
| MiMo | OpenAI 兼容 | 小米 MiMo 模型 |

同时支持添加任何兼容（OpenAI 兼容/ Anthropic 兼容）的服务商。

## 构建与运行

### 环境要求

- 鸿蒙 6 (API 23) 或以上智能设备
- [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/)

### 构建运行

```bash
git clone https://github.com/YANGZX22/chatcube.git
cd chatcube
cp build-profile.json5.example build-profile.json5
# 编辑 build-profile.json5 填入你的签名配置
```

## 部署 Hap

使用 [Auto-installer](https://github.com/likuai2010/auto-installer/) 或者 [DevEcho Testing](https://developer.huawei.com/consumer/cn/deveco-testing/) 直接在设备上安装 Hap 文件。

> [!IMPORTANT]
> 华为的签名服务器会屏蔽中国大陆以外的IP地址。若要在中国大陆以外的国家/地区为HarmonyOS NEXT侧载软件，请注意。
<!-- > Huawei's signing servers block IP addresses outside mainland China. To sideload software for HarmonyOS NEXT in countries/regions outside mainland China. -->

> [!NOTE]
> 在 HarmonyOS NEXT 上通过自签名侧载的应用，其默认有效期为 14 天。完成 [开发者实名认证](https://developer.huawei.com/consumer/cn/verified/enrollment) 后，该有效期将延长至 180 天。
<!-- > Apps sideloaded via self-signing on HarmonyOS NEXT have a default validity period of 14 days. Completing [Developer Real-Name Authentication](https://developer.huawei.com/consumer/cn/verified/enrollment) extends this period to 180 days. -->

## 许可证

本项目基于 [LongLiveY96/ChatCube](https://github.com/LongLiveY96/ChatCube) fork 并继续采用 [MIT License](./LICENSE)。

原项目版权声明已保留在 `LICENSE` 中；本 fork 的修改部分同样以 MIT License 发布。
