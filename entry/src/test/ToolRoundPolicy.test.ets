import { describe, expect, it } from '@ohos/hypium'
import { ToolDefinition, ToolFunction, ToolParameters } from '../main/ets/models/ChatModels'
import { selectToolRound, ToolRoundOptions } from '../main/ets/utils/ToolRoundPolicy'

function makeTools(names: string[]): ToolDefinition[] {
  return names.map((name: string) => new ToolDefinition(new ToolFunction(name, name, new ToolParameters())))
}

export default function toolRoundPolicyTest() {
  describe('ToolRoundPolicy', () => {
    it('allows_a_direct_answer_with_knowledge_enabled_and_keeps_other_tools', 0, () => {
      const tools = makeTools(['knowledge_search', 'python_sandbox', 'web_search'])
      const selection = selectToolRound(tools, new ToolRoundOptions())
      expect(selection.toolChoice).assertEqual('auto')
      expect(selection.tools.length).assertEqual(3)
      expect(selection.tools[1].function.name).assertEqual('python_sandbox')
    })

    it('removes_only_the_retrieval_tool_whose_budget_is_exhausted', 0, () => {
      const tools = makeTools(['knowledge_search', 'python_sandbox', 'web_search'])
      const options = new ToolRoundOptions()
      options.knowledgeSearchCount = 2
      options.knowledgeSearchLimit = 2
      options.webSearchCount = 1
      options.webSearchLimit = 2
      const selection = selectToolRound(tools, options)
      expect(selection.toolChoice).assertEqual('auto')
      expect(selection.tools.length).assertEqual(2)
      expect(selection.tools[0].function.name).assertEqual('python_sandbox')
      expect(selection.tools[1].function.name).assertEqual('web_search')
      expect(tools.length).assertEqual(3)
    })

    it('keeps_unlimited_retrieval_available_after_many_calls', 0, () => {
      const options = new ToolRoundOptions()
      options.webSearchCount = 100
      options.knowledgeSearchCount = 100
      expect(selectToolRound(makeTools(['knowledge_search', 'web_search']), options).tools.length).assertEqual(2)
    })

    it('removes_compact_after_success_without_disabling_other_tools', 0, () => {
      const options = new ToolRoundOptions()
      options.compactCompleted = true
      const selection = selectToolRound(makeTools(['compact', 'python_sandbox']), options)
      expect(selection.tools.length).assertEqual(1)
      expect(selection.tools[0].function.name).assertEqual('python_sandbox')
    })

    it('requests_a_final_answer_without_tools_after_no_progress', 0, () => {
      const options = new ToolRoundOptions()
      options.stopForNoProgress = true
      const selection = selectToolRound(makeTools(['knowledge_search', 'python_sandbox']), options)
      expect(selection.tools.length).assertEqual(0)
      expect(selection.toolChoice).assertEqual('none')
      expect(selectToolRound([], new ToolRoundOptions()).toolChoice).assertEqual('none')
    })
  })
}
