<p align="center">
  <img src="entry/src/main/resources/base/media/app_icon.png" width="120" />
</p>

<h1 align="center">XCube</h1>

<p align="center">
  基于 HarmonyOS 7 打造的原生 AI 智能体工作台。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/HarmonyOS-7_(API_26)-4285F4" alt="HarmonyOS 7" />
  <a href="./CHANGELOG.md"><img src="https://img.shields.io/badge/version-2.0.10-2ea44f" alt="版本 2.0.10" /></a>
  <a href="https://appgallery.huawei.com/link/invite-test-wap?taskId=ea479545cdb1a7d831163c11b530b911&invitationCode=29VdBr62t8H"><img src="https://img.shields.io/badge/download-2.0.1-CF0A2C" alt="版本 2.0.1 邀测链接" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License" /></a>
</p>

<p align="center">
  <a href="./README.md">English</a> · <a href="#功能特性">功能特性</a> · <a href="#快速开始">快速开始</a> · <a href="./CHANGELOG.md">更新日志</a>
</p>

## 最新信息

> [!IMPORTANT]
> **Immersive Light 兼容性问题**: 自 `HarmonyOS 7.0.0.105` (API 26) 起，普通 ArkUI 组件通过应用级开启或者组件级开启方式开启沉浸光感被[限制](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-overview#约束与限制)，XCube 已对此限制进行兼容，并尝试恢复到和限制前同等视觉效果。将设备版本升至 HarmonyOS 7 及以上版本以获得最佳体验。兼容性适配仍需时间。

> [!NOTE]
> XCube 延续自 [YANGZX22/chatcube](https://github.com/YANGZX22/chatcube)，该项目最初由 [LongLiveY96/ChatCube](https://github.com/LongLiveY96/ChatCube) 分支而来。两个早期版本的版权与 MIT 许可证声明均完整保留。

## 界面截图

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/multi-tools.png" width="220" /><br/><sub>多工具组合工作</sub></td>
    <td align="center"><img src="docs/screenshots/new-python.png" width="220" /><br/><sub>使用各种 Python 包</sub></td>
    <td align="center"><img src="docs/screenshots/answer-using-knowledge-base.png" width="220" /><br/><sub>RAG 智能问答</sub></td>
    <td align="center"><img src="docs/screenshots/work-with-sub-agents.png" width="220" /><br/><sub>和子智能体协调工作</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/map.png" width="220" /><br/><sub>集成地图与导航</sub></td>
    <td align="center"><img src="docs/screenshots/modlens.png" width="220" /><br/><sub>更好视觉支持</sub></td>
    <td align="center"><img src="docs/screenshots/complicated-projects.png" width="220" /><br/><sub>复杂工程处理能力</sub></td>
    <td align="center"><img src="docs/screenshots/workspace.png" width="220" /><br/><sub>工作区</sub></td>
  </tr>
</table>

## 项目概览

XCube 完全基于原生 ArkTS 构建，强调沉浸光感的全局性、沉浸式界面，不断打磨原生体验和视觉质感

- **多模型兼容**：内置 15 个以上的服务商，并支持 OpenAI、Anthropic 和 Gemini 兼容 API
- **联网搜索与 MCP**：支持 Bing (本地)、Brave、Tavily、Exa、博查和 DeepSeek Web Search，以及远程 Streamable MCP Server
- **多轮子智能体协作**：主智能体可将复杂任务分配给最多 3 个子智能体，并在多轮交互后统一汇总结果
- **本地知识库**：结合关键词与向量的混合 RAG，内置 DOCX／XLSX 解析与 OCR；文件始终保留在应用沙箱内
- **会话工作区**：按会话保存文件，支持用户管理与预览，并供主智能体和子智能体通过 Python 工具协作处理
- **内置工具**：Canvas 文档、计划模式、Python 沙箱、图表、日历、地图与常用地点，以及交付原文件、页面图或提取文本的 PDF／图片／DOCX／XLSX 工具包等等
- **回复播报**：支持 HarmonyOS 原生 TTS 或 ElevenLabs
- **隐私保护**：所有工具均设置明确的权限控制与用户确认流程

## 功能特性

### 🤖 模型与服务商兼容性

内置对以下 15 个以上服务商的支持：

OpenAI · Claude · Gemini · DeepSeek · Grok · Ollama · OpenRouter · SiliconFlow · Qwen · Kimi · Zhipu · Doubao · MiniMax · AiHubMix · MiMo

此外，用户可以添加符合 OpenAI、Anthropic 或 Gemini 接口规范的自定义端点。

### 📁 会话工作区

在聊天输入区点击 **工作区**，即可查看当前会话的文件树和文件预览。工作区按会话分别保存在应用沙箱内。

- **管理文件**：长按根目录空白处可上传文件、新建文件或文件夹；长按文件夹可在其中上传、新建或递归删除；长按文件可删除。
- **与模型协作**：启用 **Python** 工具后，主智能体和子智能体共享当前会话的工作区。模型可读取文件、创建或修改文本与 Python 脚本，也可运行 Python 处理工作区内的文件；同一会话的操作按顺序执行，修改同一文件时会检查版本冲突。

工作区最多保存 64 个文件、512 个文件夹；单文件不超过 16 MiB，文件总量不超过 32 MiB。安装额外 Python 包可能需要联网。

### 🧩 并行子智能体

在对话输入区的工具选择器中启用**子智能体**后，主模型可以将多主题调研、来源比较和独立文档处理等任务分配给最多三个子智能体并行执行，再汇总各自的结果。每个返回的 `agentId` 在当前主回复期间持续有效，主模型可继续向同一子智能体提问、调整任务方向、要求复核或深化分析，并根据需要进行多轮交互。

- 每个子智能体在后续轮次中持续保留独立的对话上下文、工具历史与搜索预算
- “子智能体实时预览”面板可展示实时输出、工具调用和运行状态
- 此功能需要模型完整支持工具调用

### 📚 知识库与 RAG

“知识库”标签页支持上传 DOCX、XLSX、PDF、Markdown、文本和图片。DOCX 与 XLSX 由应用内置的 OOXML 解析器处理，图片和扫描版 PDF 可使用本地 OCR。模型按需通过 [`knowledge_search`](entry/src/main/ets/config/KnowledgeSearchTool.ets) 工具检索资料；应用不会预先执行检索，也不会将知识片段注入系统提示词。

- **混合检索**：融合关键词与向量检索，并扩展相邻片段，以保留跨分块内容的完整性
- **DOCX 结构解析**：保留标题、段落、列表、换行和表格，并转换为适合语义分块的结构化文本
- **XLSX 表格解析**：支持多工作表、共享字符串、日期、合并单元格、公式缓存值和稀疏单元格坐标
- **结构感知分块**：保留页边界、标题、列表、表格、工作表与 FAQ 问答对等文档结构
- **邮件一键导入**：知识库内设与 PDF、Word、表格、图片并列的“邮件”栏。

> [!NOTE]
> XCube 支持 ArkTS 原生 ArkData Embedding。但仅支持 2-in-1 设备。其余设备可以使用兼容 OpenAI API 格式的 Embedding 模型。

### 🛠️ 内置工具

| 工具                           | 功能                                                                                                            |
|------------------------------|---------------------------------------------------------------------------------------------------------------|
| **上下文压缩**                    | 将较早对话压缩为摘要以节省上下文                                                                                              |
| **联网搜索**                     | 通过 Bing（本地）、Brave、Tavily、Exa、博查或 DeepSeek 获取实时信息；超出搜索预算时请求用户确认                                                |
| **向用户提问**                    | 模型遇到关键歧义时，可通过确认卡片请求用户补充信息                                                                                     |
| **子智能体**                     | 派出并行子智能体处理独立子任务                                                                                               |
| **Python**                   | 运行 Python 进行计算、数据处理和中间推导                                                                                      |
| **PDF 工具包**                  | 模型支持原生文档输入时直接交付原始 PDF；也可将指定页码渲染成图片交给有视觉能力的模型；否则提取 PDF 文本层，扫描件自动回退到本地 Core Vision Kit OCR                |
| **图片工具包**                    | 模型支持原生视觉输入时直接交付原图；否则使用本地 Core Vision Kit OCR 识别图片文字                                                          |
| **视觉理解**<sup>*</sup>         | 模型支持原生视觉输入时直接交付原图；否则通过 [ModLens](https://github.com/liustack/modlens) 提供图片 OCR、布局、语义与视觉线索，需要单独部署              |
| **DOCX 工具包**                 | 模型支持原生文档输入时直接交付原始 DOCX；否则在本地提取标题、段落、列表和表格，不把原始文件交给模型                                                         |
| **XLSX 工具包**                 | 模型支持原生文档输入时直接交付原始 XLSX；否则在本地提取工作表、单元格、日期及公式结果，不把原始文件交给模型                                                    |
| **Skill**                    | 读取用户已启用的技能说明                                                                                                  |
| **Canvas 文档**                | 在对话区域旁维护用户与 AI 均可编辑的共享文档，并支持 Markdown 预览                                                                      |
| **计划模式**                     | 由模型创建多步骤任务计划，并在各步骤实际完成后更新状态。计划状态仅允许模型修改；用户可通过 `/plan` 打开只读面板查看当前执行项与总体进度。计划按会话保存在本地，并在再次进入会话时自动恢复             |
| **数学绘图**                     | 生成基于 [VChart](https://ohpm.openharmony.cn/#/cn/detail/@visactor%2Fharmony-vchart) 的折线图、柱状图、饼图、散点图、桑基图、词云图等可视化 |
| **读取日程**                     | 经用户确认后读取系统日历事件                                                                                                |
| **写入日程**                     | 经用户确认后写入系统日历事件                                                                                                |
| **读取邮件**                     | 通过 IMAP 搜索并读取已授权邮箱，并向模型返回受支持附件的本地文本提取或 OCR 结果。AI 发起的每次读取都需用户明确批准；邮箱凭据保存在系统安全资产存储中，且不会提供给模型                    |
| **发送邮件**                     | 通过 SMTP 向指定邮箱发送邮件。AI 发起的每次发送都需用户明确确认收件人、主题与正文；邮箱凭据不会提供给模型                                                     |
| **常用地点**<sup>#</sup>         | 在 **设置 → 工具 → 常用地点** 中通过地点搜索、地图选点或当前精确位置保存任意数量的标签（如“家”“公司”），供模型按标签读取和使用                                       |
| **地图**                       | 使用 HarmonyOS Map Kit 搜索地点，并在聊天中展示当前位置、目的地、路线折线、精确位置与地图跟随                                                      |
| **花瓣导航**                     | 将搜索地点、坐标或已保存的常用地点标签交给花瓣地图进行路线导航                                                                               |

> [!IMPORTANT]
> 使用地图相关功能前，必须在 DevEco Studio 中打开 **File → Project Structure → Signing Configs → Enable open capabilities**，启用 **Map Kit** 并应用配置。如果调试 Profile 早于该能力生成，还需重新申请或下载 Profile 并更新签名配置。

#### <sup>*</sup>[可选] 为文本模型在视觉理解工具背后启用 ModLens

HarmonyOS 应用无法直接运行 ModLens 所需的 Node.js CLI，因此项目提供可选的轻量伴随网关，供用户部署至计算机或服务器。请按照 [`tools/modlens-gateway/README.md`](tools/modlens-gateway/README.md) 启动网关，再进入 **设置 → 工具中心 → 视觉理解** 填写地址、测试连接并启用工具。

- 仅在完成显式配置并启用工具后，图片才会发送至网关及 ModLens 中配置的视觉服务商
- 当前模型已有原生视觉能力时，该工具仍可使用，但会在同一轮直接返回原图作为原生输入，不再经过网关
- 网关不可用、未启用或模型不支持工具调用时，可选用 `image_toolkit`

#### <sup>#</sup>常用地点及其坐标保存在应用本地，只有启用对应工具后模型才能读取；获取当前精确位置和使用 Map Kit 时需要授予应用位置与地图权限。

## 快速开始

### 1. 从[邀测链接](https://appgallery.huawei.com/link/invite-test-wap?taskId=ea479545cdb1a7d831163c11b530b911)直接安装 (即将上线)

### 2. 本地编译

### 环境要求

- 运行 HarmonyOS 7 (API 26.0.0) 及以上版本的设备
- [DevEco Studio ≥ 26.0.0](https://developer.huawei.com/consumer/cn/deveco-studio/)

#### A. 克隆并配置项目

```bash
git clone https://github.com/YANGZX22/XCube.git
cd XCube
cp build-profile.json5.example build-profile.json5
# 编辑 build-profile.json5，填写签名配置
```

#### B. 添加语音识别模型（一次性配置）

> [!NOTE]
> ASR 模型体积过大，未纳入 Git 仓库，需要手动添加：

1. 下载 [sherpa-onnx SenseVoice](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2)（支持中文、英语、日语、韩语和粤语）
2. 解压文件，将 `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` 目录移动到 `entry/src/main/resources/rawfile/`

该模型目录已被 `.gitignore` 排除，不会提交到仓库。

#### C. 运行

使用 DevEco Studio 打开项目，并在目标设备上运行。

### 3. 侧载 HAP (停止发布；仅更新版本号)

在 [Release](https://github.com/YANGZX22/XCube/releases) 页面下载最新版本 HAP 文件后，可以通过 [Auto-installer](https://github.com/likuai2010/auto-installer/) 或 [DevEco Testing](https://developer.huawei.com/consumer/cn/deveco-testing/) 将 HAP 安装至设备。

> [!IMPORTANT]
> 华为签名服务器会屏蔽中国大陆以外的 IP 地址。在其他地区侧载 HarmonyOS NEXT (HarmonyOS 6 及以上版本) 软件时，应将注意此限制。

> [!NOTE]
> 自签名侧载应用默认有效期为 14 天。完成[开发者实名认证](https://developer.huawei.com/consumer/cn/verified/enrollment)后可延长至 180 天。

## 许可证

[MIT](./LICENSE): 完整保留 LongLiveY96 原始 ChatCube 与 YANGZX22 后续版本的版权声明；XCube 的修改同样以 MIT 许可证发布。
