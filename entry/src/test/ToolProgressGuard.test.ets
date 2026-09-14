import { describe, expect, it } from '@ohos/hypium'
import { ToolProgressGuard, TOOL_PROGRESS_WARNING, TOOL_PROGRESS_STOP } from '../main/ets/utils/ToolProgressGuard'

export default function toolProgressGuardTest() {
  describe('ToolProgressGuard', () => {
    it('warns_then_stops_identical_calls_with_identical_results', 0, () => {
      const guard = new ToolProgressGuard()
      guard.beginTurn('r1', 'main')
      const notices: string[] = []
      for (let i = 0; i < 5; i++) {
        notices.push(guard.observe('r1', 'main', 'read_file', '{"path":"a"}', '{"text":"hello"}'))
      }
      expect(notices[0]).assertEqual('')
      expect(notices[1]).assertEqual('')
      expect(notices[2]).assertEqual(TOOL_PROGRESS_WARNING)
      expect(notices[3]).assertEqual('')
      expect(notices[4]).assertEqual(TOOL_PROGRESS_STOP)
      expect(guard.shouldStop('r1', 'main')).assertTrue()
    })

    it('recognizes_equivalent_nested_json_despite_key_order_and_whitespace', 0, () => {
      const guard = new ToolProgressGuard()
      guard.beginTurn('r', 'main')
      guard.observe('r', 'main', 'lookup', '{"b":{"x":1,"y":2},"a":[1,2]}', '{"ok":false,"error":"missing"}')
      guard.observe('r', 'main', 'lookup', '{ "a": [1,2], "b": {"y":2,"x":1}}', '{"error":"missing","ok":false}')
      expect(guard.observe('r', 'main', 'lookup', '{"a":[1,2],"b":{"x":1,"y":2}}', '{"ok":false,"error":"missing"}'))
        .assertEqual(TOOL_PROGRESS_WARNING)
    })

    it('allows_repeated_calls_when_the_result_changes', 0, () => {
      const guard = new ToolProgressGuard()
      guard.beginTurn('r', 'main')
      for (let i = 0; i < 20; i++) {
        expect(guard.observe('r', 'main', 'status', '{}', `{"progress":${i}}`)).assertEqual('')
      }
      expect(guard.shouldStop('r', 'main')).assertFalse()
    })

    it('does_not_merge_distinct_strings_arrays_or_tools', 0, () => {
      const guard = new ToolProgressGuard()
      guard.beginTurn('r', 'main')
      guard.observe('r', 'main', 'run', '{"text":"a b","items":[1,2]}', 'null')
      guard.observe('r', 'main', 'run', '{"text":"a  b","items":[1,2]}', 'null')
      expect(guard.observe('r', 'main', 'run', '{"text":"a  b","items":[2,1]}', 'null')).assertEqual('')
      expect(guard.observe('r', 'main', 'check', '{"text":"a  b","items":[2,1]}', 'null')).assertEqual('')
    })

    it('isolates_requests_and_agents_and_resets_for_new_user_input', 0, () => {
      const guard = new ToolProgressGuard()
      guard.beginTurn('r1', 'main')
      guard.beginTurn('r1', 'child')
      guard.beginTurn('r2', 'main')
      for (let i = 0; i < 5; i++) {
        guard.observe('r1', 'main', 'tool', '{}', 'same')
      }
      expect(guard.shouldStop('r1', 'child')).assertFalse()
      expect(guard.shouldStop('r2', 'main')).assertFalse()
      guard.beginTurn('r1', 'main')
      expect(guard.shouldStop('r1', 'main')).assertFalse()
      expect(guard.observe('r1', 'main', 'tool', '{}', 'same')).assertEqual('')
    })

    it('exempts_blocking_collection_but_detects_unchanged_nonblocking_polls', 0, () => {
      const guard = new ToolProgressGuard()
      guard.beginTurn('r', 'main')
      for (let i = 0; i < 10; i++) {
        expect(guard.observe('r', 'main', 'sub_agent_result', '{}', 'same')).assertEqual('')
      }
      for (let i = 0; i < 5; i++) {
        guard.observe('r', 'main', 'sub_agent_result', '{"wait":false}', '{"status":"running"}')
      }
      expect(guard.shouldStop('r', 'main')).assertTrue()
    })

    it('clears_ended_request_agents_and_ignores_late_results', 0, () => {
      const guard = new ToolProgressGuard()
      guard.beginTurn('r', 'main')
      guard.beginTurn('r', 'child')
      guard.endRequest('r')
      for (let i = 0; i < 8; i++) {
        expect(guard.observe('r', 'child', 'tool', '{}', 'same')).assertEqual('')
      }
      expect(guard.shouldStop('r', 'child')).assertFalse()
    })
  })
}
