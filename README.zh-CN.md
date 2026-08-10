<p align="center">
  <img src="entry/src/main/resources/base/media/app_icon.png" width="120" />
</p>

<h1 align="center">XCube</h1>

<p align="center">
  一个面向鸿蒙 7 (API 26.0.0) 的原生 AI 聊天客户端。<br/>
</p>

<p align="center">
  <a href="./README.md">English</a> | <a href="./LICENSE">MIT License</a>
</p>

> [!IMPORTANT]
> XCube 仅在 HarmonyOS 7 (API 26.0.0) 及以上版本的设备上运行。如果您非开发者或仍处于HarmonyOS 6及以下版本，请报名[花粉 Beta 版测试计划](https://cn.club.vmall.com/mhw/assets/file-html-app/3b2bca9630d0fcb2bb2dfac09ee415ea20230529103243/index.html?ts=1785306752202#/)以安装本应用。

---

## 项目来源

> [!NOTE]
> XCube 是 [YANGZX22/chatcube](https://github.com/YANGZX22/chatcube) 的全新延续版本；该版本最初基于 [LongLiveY96/ChatCube](https://github.com/LongLiveY96/ChatCube) 分支开发。两个早期版本的版权与 MIT 授权声明均完整保留。

## 关于 XCube

- 面向 HarmonyOS 7（API 26.0.0）持续打磨原生 ArkTS 体验，强调沉浸光感的全局性与界面一致性
- 补充联网搜索、Canvas 文档、PDF 转文本、Python 沙箱、数学绘图、读写日程等工具，致力于结合 AI 与手机本身功能交互并提供工具调用权限和用户确认流程以及隐私保护
- 本仓库将尝试更多原生 HarmonyOS SDK 能力，探索更丰富的交互方式和使用场景，持续迭代优化用户体验

### 发布信息

- 应用名称：XCube
- 当前版本：`1.3.0` (versionCode `1003000`)

## 最新界面预览

以下截图基于当前 HarmonyOS 7 (API 26.0.0) 版本：

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/IMAGE1.jpg" width="220" /><br/><sub>会话列表</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE2.jpg" width="220" /><br/><sub>知识库界面</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE3.jpg" width="220" /><br/><sub>和子智能体协同工作</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/IMAGE4.jpg" width="220" /><br/><sub>上下文</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE5.jpg" width="220" /><br/><sub>手稿模式对话界面</sub></td>
    <td align="center"><img src="docs/screenshots/IMAGE6.jpg" width="220" /><br/><sub>手稿模式会话列表</sub></td>
  </tr>
</table>

## 功能特性

### 和任何模型对话

内置 15+ AI 服务商。支持自定义添加任何 OpenAI / Anthropic / Gemini 兼容的服务商。

### 工具、联网搜索与 MCP

内置联网搜索，支持 博查、Bing (local)、Tavily、Exa。支持 Function Calling 的模型可以自主调用工具获取实时信息。支持接入远端 streamable MCP Server。

### 并行子智能体

XCube 内置“子智能体”工具。对于多主题调研、多来源对比或多份材料分别处理等可拆分任务，主模型可以一次派出最多 3 个子智能体并行执行，再汇总它们的结果回答：

- **隔离上下文**：每个子智能体获得独立对话上下文，只接收主模型为它编写的自包含任务，不会递归派生新的子智能体。
- **继承工具与独立预算**：子智能体使用当前对话已开启的工具。主模型和每个子智能体各自拥有默认 5 次联网搜索额度，追加搜索也分别征求用户确认；开启知识库时，也各自拥有最多 5 次 `knowledge_search` 查询额度，不会相互挤占。
- **实时预览**：子智能体的输出、工具调用和执行状态会显示在“子智能体实时预览”面板中；`ask_user` 会以弹窗逐个询问，主对话仅保留可展开的结果栏。

在对话输入区的工具选择中开启“子智能体”后即可使用。是否派出、如何拆分由主模型判断；所选模型需完整支持工具调用。

### 本地 TTS 与 ElevenLabs 播报

AI 回复可通过消息工具栏直接播报。进入 **设置 → 播报** 开启功能，并选择需要的语音引擎：

- **本地 TTS**：使用 HarmonyOS 系统离线文字转语音引擎，无需 API Key，也不会将回复文本发送给 ElevenLabs。
- **[ElevenLabs API](https://elevenlabs.io/docs/overview/capabilities/text-to-speech)**：支持自定义 API 基础地址与 API Key，可加载账号下的语音并通过 Voice ID 选择器切换，同时支持 `eleven_multilingual_v2`、`eleven_flash_v2_5` 和 `eleven_v3` 模型。
- **语音参数**：ElevenLabs 模式可调整稳定性、相似度和语速；较长的回复会按自然语句分段并依次播放。
- **隐私说明**：ElevenLabs API Key 保存在应用本地偏好设置中。使用 ElevenLabs 模式时，回复文本会发送到所配置的 API 地址进行语音合成。

### 向量知识库与 RAG

XCube 内置独立的“知识库”页，可在一处上传、管理和预览资料，并通过
[`knowledge_search`](entry/src/main/ets/config/KnowledgeSearchTool.ets) 工具让模型按需检索：

- **统一文件入口**：支持 PDF、TXT、Markdown，以及 JPG、JPEG、PNG、WebP、BMP 图片；图片会通过 OCR 建立索引，PDF 提取文字过少时会自动转为图片 OCR。
- **结构感知语义分块**：分块器会保留 PDF/OCR 页边界、Markdown 标题、段落、列表、表格和 FAQ 问答对，再根据相邻内容单元的向量加入自适应语义断点。每个向量都会补充文件名、标题路径和页码作为上下文；若 Embedding 失败，则回退到确定性的结构感知分块，不会阻断关键词索引。
- **带相邻上下文的混合检索**：文档片段会同时写入关键词索引和 ArkData 向量 sidecar。检索会融合关键词与向量召回结果，并在精确命中后向两侧各扩展至多一个相关父级或相邻片段，减少跨边界答案被截断的情况。向量生成或向量 sidecar 不可用时，关键词检索仍可继续工作。
- **两种向量来源**：[PC/2in1](https://developer.huawei.com/consumer/cn/doc/harmonyos-releases/support-device#section36331990919) 设备可使用本地 ArkData Embedding，文档片段不离开设备；也可选择已配置的 OpenAI-compatible Embedding API。API 模式会把文档片段发送给所选服务商，请根据资料敏感程度选择。
- **严格的工具调用边界**：输入区开启“知识库”后，应用只向模型提供知识库工具；不会预先检索，也不会把知识片段直接塞入系统提示词。只有模型实际调用 `knowledge_search` 后，应用才执行检索并在需要时为本次 query 请求 API Embedding。
- **首次查询恢复**：模型实际调用工具后，首次查询会短暂等待已有向量 sidecar 重新打开。对于新建或已过期的 Data Augmentation Kit 检索器，冷启动返回空结果时可重试一次；普通的缓存未命中不会重复查询。
- **智能续查**：一次用户提问最多允许 5 次知识库查询；完整命中后应提前结束。若结果被截断且存在明确缺口，模型可以使用更聚焦、非重复的 query 继续查询。
- **本地管理**：原文件、OCR/文本结果、关键词索引和向量 sidecar 均保存在应用沙箱中。列表支持预览、更新和删除，更新会使用当前选中的向量后端重建索引。

使用方式：

1. 打开底部“知识库”页，点击右上角加号上传文件。
2. 点击右上角向量模型按钮选择本地 ArkData 或 API Embedding，然后按需更新索引。
3. 回到对话，在输入区将“知识库”切换为开启状态后提问；模型会自行判断查询次数和关键词。

> [!NOTE]
> ArkData 应用数据向量化目前仅支持 2-in-1 设备。手机和平板请使用 API Embedding；未配置 API 时仍可使用关键词知识检索。向量数据库持久化本身仍由设备侧 ArkData 完成。

### 内置智能工具

XCube 提供一组可由模型调用的本地工具：

- **子智能体**：将 1–3 个独立子任务并行交给隔离上下文的子智能体，完成后由主模型汇总。
- **联网搜索**：按需获取实时信息，支持搜索次数预算与用户确认追加搜索。
- **Canvas 文档**：在对话右侧维护一份用户和 AI 都能修改的共享文档，支持隐藏到浮层和 Markdown 预览。
- **PDF / 图片转文本**：当模型未开启原生文档阅读能力时，用户上传的 PDF 会暂存到本地沙箱，模型可调用 `pdf_to_text` 获取文本内容；当模型未开启视觉理解时，用户上传的图片可通过 `image_to_text` 调用 CoreVisionKit OCR 识别文字。若模型支持对应原生输入，应用不额外干预。
- **Python 沙箱**：在沙箱化环境中执行必要的 Python 代码，用于计算、数据处理和中间推导。
- **数学绘图**：基于 [VChart](https://ohpm.openharmony.cn/#/cn/detail/@visactor%2Fharmony-vchart) 生成结构化图表，支持折线图、柱状图、面积图、散点/气泡图、饼图、环形图、玫瑰图、漏斗图、词云图、桑基图、双轴/柱线组合图等。
- **读写日程**：经用户确认后读取指定范围内的日程，或写入新的日程事件；读取范围、数量、地点和备注等隐私字段可由用户确认和调整。
- **向用户提问**：模型遇到关键歧义时，可以通过卡片向用户确认。

## 支持的服务商

| 服务商        | API 格式    | 说明                    |
|------------|-----------|-----------------------|
| OpenAI     | OpenAI    |                       |
| Claude     | Anthropic |                       |
| DeepSeek   | OpenAI 兼容 | deepseek-v4-pro/flash |
| Gemini     | Google    |                       |
| Grok       | OpenAI 兼容 | xAI 模型                |
| Ollama     | OpenAI 兼容 | 本地模型                  |
| OpenRouter | OpenAI 兼容 | 多服务商网关                |
| 硅基流动       | OpenAI 兼容 | 国产 AI 模型              |
| 阿里云百炼      | OpenAI 兼容 | 通义千问系列                |
| Kimi       | OpenAI 兼容 | Moonshot / Kimi 模型    |
| 智谱 AI      | OpenAI 兼容 | GLM 系列                |
| 火山引擎       | OpenAI 兼容 | 豆包系列                  |
| MiniMax    | OpenAI 兼容 | MiniMax 模型            |
| AiHubMix   | OpenAI 兼容 | 多服务商网关                |
| MiMo       | OpenAI 兼容 | 小米 MiMo 模型            |

同时支持添加任何兼容（OpenAI 兼容/ Anthropic 兼容）的服务商。

## 构建与运行

### 环境要求

- HarmonyOS 7 (API 26.0.0) 智能设备
- [DevEco Studio (>= 26.0.0 Beta2)](https://developer.huawei.com/consumer/cn/deveco-studio/)

### 构建运行

语音识别模型文件体积较大，不纳入 Git 仓库，构建前需要手动放入：

1. 下载 [sherpa-onnx SenseVoice 中/英/日/韩/粤语音识别模型](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2)。
2. 解压下载的压缩包。
3. 将解压得到的 `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` 文件夹放入 `entry/src/main/resources/rawfile/`。

模型目录及所有 `*.onnx` 文件已由 `.gitignore` 排除，不会提交到仓库。

```bash
git clone https://github.com/YANGZX22/XCube.git
cd XCube
cp build-profile.json5.example build-profile.json5
# 编辑 build-profile.json5 填入你的签名配置
```

## 部署 HAP

使用 [Auto-installer](https://github.com/likuai2010/auto-installer/) 或 [DevEco Testing](https://developer.huawei.com/consumer/cn/deveco-testing/) 直接在设备上安装 HAP 文件。

> [!IMPORTANT]
> 华为的签名服务器会屏蔽中国大陆以外的IP地址。若要在中国大陆以外的国家/地区为HarmonyOS NEXT侧载软件，请注意。

> [!NOTE]
> 在 HarmonyOS NEXT 上通过自签名侧载的应用，其默认有效期为 14 天。完成 [开发者实名认证](https://developer.huawei.com/consumer/cn/verified/enrollment) 后，该有效期将延长至 180 天。

## 许可证

XCube 继续采用 [MIT License](./LICENSE)。LongLiveY96 的 ChatCube 原始版本及 YANGZX22 后续版本的版权声明均已保留，XCube 的后续修改同样以 MIT License 发布。
