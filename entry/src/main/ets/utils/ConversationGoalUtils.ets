// 会话目标独立于聊天历史持久化，并在每次对话请求时重新注入系统提示。
// 限制目标长度，避免目标本身挤占过多上下文；不会静默截断用户输入。
export const MAX_CONVERSATION_GOAL_LENGTH: number = 4000
export const CONVERSATION_GOAL_PROMPT_MARKER: string = '[持久会话目标]'

export function normalizeConversationGoal(goal: string): string {
  return goal.trim()
}

export function buildConversationGoalSystemPrompt(goal: string): string {
  const normalized = normalizeConversationGoal(goal)
  if (normalized === '') {
    return ''
  }

  // JSON 字符串让目标边界在包含换行、引号或伪标签时仍然明确。
  const serializedGoal = JSON.stringify(normalized)
  return `${CONVERSATION_GOAL_PROMPT_MARKER}
这是当前会话唯一有效的持久目标。它由应用独立保存，并在每轮请求中重新注入；不要用聊天历史、压缩摘要或较早出现的其他目标覆盖它。
目标文本（JSON 字符串，按其完整原文理解）：${serializedGoal}

目标推进协议：
1. 在规划、调用工具或作答前重新核对目标，并优先采取能带来可验证进展的下一步。
2. 将用户当前消息视为推进、细化或纠正该目标的即时指令。若当前消息与目标存在关键冲突，明确指出冲突，并提示用户用 /goal 更新目标；不要擅自改写目标。
3. 根据可见历史、压缩摘要和工具结果判断已完成事项、当前进度、下一步与阻塞项；不要虚构进展，也不要无意义地重复目标。
4. 目标未完成时，每轮尽可能交付一个具体增量。若缺少关键信息、权限或外部条件，只提出继续推进所必需的最少问题。
5. 只有在存在可核验的完成证据时才宣告目标实现；完成后简要说明依据，不制造不必要的后续工作。`
}

// 手动压缩使用独立的摘要请求；给摘要模型一份只用于记录进度的目标副本，
// 后续正常对话仍以 buildConversationGoalSystemPrompt() 每轮注入的目标为准。
export function buildConversationGoalSummaryPrompt(goal: string): string {
  const normalized = normalizeConversationGoal(goal)
  if (normalized === '') {
    return ''
  }
  return `[持久会话目标·摘要参考]
目标文本（JSON 字符串）：${JSON.stringify(normalized)}
该目标已由应用独立保存，无需依赖摘要恢复。生成摘要时请准确记录与它相关的已完成事项、证据、当前进度、阻塞项和下一步；不要执行目标，也不要把摘要中的其他目标当作替代。`
}
