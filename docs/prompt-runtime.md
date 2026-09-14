# 模型提示与工具执行

`AgentPrompts.ets` 维护普通聊天与工具聊天共享的执行原则：按任务难度投入推理，围绕实际交付选择工具，证据充分后结束。工具专属说明只在对应工具可用时加入；用户自定义身份与语气、回复语言规则和 Skill 加载仍使用原有入口。

开启知识库表示允许模型检索。问题依赖用户文件或用户明确要求检索时，由模型生成真实 `knowledge_search` 调用；首轮采用 `tool_choice=auto`，保留其他可用工具，也允许直接回答。应用不预检索，结果仍通过标准 tool result 回传。用户设置的检索次数上限继续生效。

子智能体用于独立子任务，合格结果直接整合，只对实质缺口续发。首次派发仍需主线程有可并行工作；补充回复可以直接等待，不要求虚构新交付物。主模型漏收取时仍保留自动收取兜底，避免遗漏后台产出。推理内容在后续子智能体请求中完整回传，不通过删除推理历史来缩短请求。

计划按交付物分组，在实质进度变化时更新。`plan_mode` 的 `step_refs` 可批量更新同一状态，例如 `{"operation":"check","step_refs":["1","2"]}`。任一引用无效则整批不更新；状态未变时不增加计划版本。

`ToolProgressGuard` 按请求和智能体隔离。连续相同工具、等价 JSON 参数且返回结果不变时，第 3 次添加应用提醒，第 5 次停止该智能体当前轮的工具执行，并让模型依据已有信息回答或说明阻塞。它不限制有新结果的工作，也不限制阻塞式子智能体收取或用户交互。新的用户引导或子智能体续发会重新计数，请求结束清理状态。检测是严格等价比较，不声称识别语义重复或所有无效循环。

DeepSeek 的可选档位为关闭、默认、低、高、极限；低档发送 `reasoning_effort=low`，极限档发送 `max`。默认档仍使用供应商默认值，不根据任务自动调整用户选择。协议依据：[DeepSeek 思考模式](https://api-docs.deepseek.com/guides/thinking_mode/)。

回归用例位于 `ToolProgressGuard.test.ets`、`ToolRoundPolicy.test.ets`、`PlanService.test.ets` 和 `RefactorGuard.test.ets`。可用 `node tools/test-prompt-runtime.cjs` 在主机转译运行策略测试和部分执行路径（模拟 HarmonyOS 存储与网络，不调用真实模型）。工具参数模板另用 `python3 tools/validate-tool-schemas.py` 检查运行时 JSON 转义。真实模型效果应在相同模型、档位和工具配置下对照回答质量、首次正文耗时、推理 token 和无效工具轮次。
