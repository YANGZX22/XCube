<p align="center">
  <img src="AppScope/resources/base/media/foreground.png" width="120" />
</p>

<h1 align="center">ChatCube</h1>

<p align="center">
  一个面向鸿蒙 6.1.1（API 24）的原生 AI 聊天客户端。<br/>
  一个应用，15+ 服务商，联网搜索、Canvas 文档、PDF2TXT、内置工具、MCP 与 ArkTS 原生体验。
</p>

<p align="center">
  <a href="./README_EN.md">English</a> · <a href="./LICENSE">MIT License</a>
</p>

---

## 公告

2026/07/10
> [!NOTE]
> As HarmonyOS 7 is approaching, this repo will be paused for a while for applying the new HarmonyOS 7 SDK and adapting to the new system features. 
>
> 由于 HarmonyOS 7 即将上线，本仓库将暂停一段时间，以应用新的 HarmonyOS 7 SDK 并适应新的系统特性。

---

## Fork 说明

> [!NOTE]
> 原作者已将其版本上架应用市场，因此[原仓库](https://github.com/LongLiveY96/ChatCube)目前已停止更新。本仓库基于原项目继续维护，旨在保留原生 ArkTS 体验的基础上，尝试更多不一样的产品思路、交互方案和能力扩展。

## 关于本 ChatCube 分支

- 更加着手于 UI, 围绕鸿蒙 6（API 23）持续打磨，强调沉浸光感的全局性、沉浸式界面，力求在原生体验和视觉质感上都做到极致
- 补充联网搜索、Canvas 文档、PDF 转文本、Python 沙箱、数学绘图、读写日程等工具，致力于结合 AI 与手机本身功能交互并提供工具调用权限和用户确认流程以及隐私保护
- 本项目将尝试更多原生 HarmonyOS SDK 能力，探索更丰富的交互方式和使用场景，持续迭代优化用户体验

## 最新界面预览

以下截图基于当前鸿蒙 6（API 23）版本：

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/IMAGE1.jpg" width="200" /><br/><sub>对话</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE2.jpg" width="200" /><br/><sub>会话</sub></td>
    <td align="center"><img src="docs/screenshots/providers_new.jpg" width="200" /><br/><sub>服务商管理</sub></td>
  </tr>
</table>

## 功能特性

### 和任何模型对话

内置 15+ AI 服务商，填入 API Key 选个模型就能聊。支持自定义添加任何 OpenAI / Anthropic / Gemini 兼容的服务商，几秒搞定。

### 工具、联网搜索与 MCP

内置联网搜索，支持 博查、Bing(local)、Tavily、Exa。支持 Function Calling 的模型可以自主调用工具获取实时信息，工具中心也支持接入远端 streamable MCP Server，把能力继续往外扩。

### 内置智能工具

ChatCube 提供一组可由模型调用的本地工具，常见任务不必离开对话：

- **联网搜索**：按需获取实时信息，支持搜索次数预算与用户确认追加搜索。
- **Canvas 文档**：在对话右侧维护一份用户和 AI 都能修改的共享文档，支持隐藏到浮层、Markdown 预览和版本提示。
- **PDF / 图片转文本**：当当前模型未开启原生文档阅读能力时，用户上传的 PDF 会暂存到本地沙箱，模型可调用 `pdf_to_text` 获取文本内容；当模型未开启视觉理解时，用户上传的图片可通过 `image_to_text` 调用 CoreVisionKit OCR 识别文字。若模型支持对应原生输入，应用不额外干预。
- **Python 沙箱**：在沙箱化环境中执行必要的 Python 代码，用于计算、数据处理和中间推导。
- **数学绘图**：基于 [VChart](https://ohpm.openharmony.cn/#/cn/detail/@visactor%2Fharmony-vchart) 生成结构化图表，支持折线图、柱状图、面积图、散点/气泡图、饼图、环形图、玫瑰图、漏斗图、词云图、桑基图、双轴/柱线组合图等。
- **读写日程**：经用户确认后读取指定范围内的日程，或写入新的日程事件；读取范围、数量、地点和备注等隐私字段可由用户确认和调整。
- **向用户提问**：模型遇到关键歧义时，可以用专用卡片向用户确认，而不是直接猜。

工具调用遵循权限和确认流程：涉及系统数据或写入操作时，会先展示确认 UI；用户拒绝后模型会继续基于现有信息回答。

### Markdown 及更多

完整的 Markdown 渲染，支持语法高亮代码块、表格、LaTeX 公式、图片。甚至原始 HTML 也能实时预览。

### 好看，好用

8 种配色主题，深色 / 浅色 / 跟随系统。基于 API 23 的高级材质、沉浸光感和玻璃质感持续打磨。原生 UI 的流畅感，因为它就是原生的。

### 手机、平板都顺手

针对手机、平板和大屏设备做了布局适配。聊天、设置、服务商管理等页面在更大屏幕上也能保持清晰、顺手的使用体验。

### 智感握姿

检测你用哪只手握着手机，自动把「新对话」按钮移到够得着的一侧。单手操作，就该这么简单。

### 数据在你手里

导出和导入一切，对话、服务商配置、偏好设置都能带走。JSON 格式，没有锁定。

### 后台也不掉线

切到其他应用等待长回复？ChatCube 在后台继续工作，回复完成后通知你。

## 支持的服务商

| 服务商 | API 格式 | 说明 |
|--------|---------|------|
| OpenAI | OpenAI | GPT-4o、o1 等 |
| Claude | Anthropic | Claude 4、3.5 等 |
| DeepSeek | OpenAI 兼容 | DeepSeek-V3、R1 等 |
| Gemini | Google | Gemini 2.5 等 |
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

……或者自己添加任何兼容的服务商。

## 快速开始

### 环境要求

- 鸿蒙 6（API 23）
- DevEco Studio 5.0+

### 构建运行

```bash
git clone https://github.com/YANGZX22/chatcube.git
cd chatcube
cp build-profile.json5.example build-profile.json5
# 编辑 build-profile.json5 填入你的签名配置
```

用 DevEco Studio 打开 → 同步 → 运行。

### 配置服务商

在应用中：**设置 → 服务商管理** → 添加你的 API Key。

## 许可证

本项目基于 [LongLiveY96/ChatCube](https://github.com/LongLiveY96/ChatCube) fork 并继续采用 [MIT License](./LICENSE)。

原项目版权声明已保留在 `LICENSE` 中；本 fork 的修改部分同样以 MIT License 发布。
