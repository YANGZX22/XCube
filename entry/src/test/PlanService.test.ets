import { describe, expect, it } from '@ohos/hypium'
import {
  buildPlanSteps,
  countPlanStepsByStatus,
  normalizePlanStepStatus,
  PLAN_MAX_STEPS,
  PLAN_STEP_ACTIVE,
  PLAN_STEP_DONE,
  PLAN_STEP_PENDING,
  PlanStep,
  resolvePlanStepIndex
} from '../main/ets/services/PlanService'

function makeSteps(titles: string[]): PlanStep[] {
  return buildPlanSteps(titles)
}

export default function planServiceTest() {
  describe('planServiceTest', () => {
    it('normalizes_the_status_words_models_actually_emit', 0, () => {
      expect(normalizePlanStepStatus('done')).assertEqual(PLAN_STEP_DONE)
      expect(normalizePlanStepStatus('Completed')).assertEqual(PLAN_STEP_DONE)
      expect(normalizePlanStepStatus('  FINISHED ')).assertEqual(PLAN_STEP_DONE)
      expect(normalizePlanStepStatus('in progress')).assertEqual(PLAN_STEP_ACTIVE)
      expect(normalizePlanStepStatus('in-progress')).assertEqual(PLAN_STEP_ACTIVE)
      expect(normalizePlanStepStatus('wip')).assertEqual(PLAN_STEP_ACTIVE)
    })

    it('treats_unknown_status_words_as_pending', 0, () => {
      // 认不出的词一律当未完成：显示成"没做"比凭猜测勾上安全
      expect(normalizePlanStepStatus('maybe')).assertEqual(PLAN_STEP_PENDING)
      expect(normalizePlanStepStatus('')).assertEqual(PLAN_STEP_PENDING)
      expect(normalizePlanStepStatus('blocked')).assertEqual(PLAN_STEP_PENDING)
    })

    it('resolves_a_step_by_ordinal', 0, () => {
      const steps = makeSteps(['Read the spec', 'Write the migration', 'Run the tests'])
      expect(resolvePlanStepIndex(steps, '1')).assertEqual(0)
      expect(resolvePlanStepIndex(steps, '3')).assertEqual(2)
      // 越界的序号不能回退成"最后一步"
      expect(resolvePlanStepIndex(steps, '0')).assertEqual(-1)
      expect(resolvePlanStepIndex(steps, '4')).assertEqual(-1)
    })

    it('resolves_a_step_by_id_or_title', 0, () => {
      const steps = makeSteps(['Read the spec', 'Write the migration', 'Run the tests'])
      expect(resolvePlanStepIndex(steps, 's2')).assertEqual(1)
      expect(resolvePlanStepIndex(steps, 'Write the migration')).assertEqual(1)
      expect(resolvePlanStepIndex(steps, '  write the MIGRATION  ')).assertEqual(1)
      expect(resolvePlanStepIndex(steps, 'Write')).assertEqual(1)
      expect(resolvePlanStepIndex(steps, 'migration')).assertEqual(1)
    })

    it('refuses_to_guess_when_a_title_is_ambiguous', 0, () => {
      // 勾错一步比报告失败更糟，歧义一律返回 -1 让模型改用序号
      const steps = makeSteps(['Run the unit tests', 'Run the integration tests'])
      expect(resolvePlanStepIndex(steps, 'Run the')).assertEqual(-1)
      expect(resolvePlanStepIndex(steps, 'tests')).assertEqual(-1)
      expect(resolvePlanStepIndex(steps, 'Run the unit tests')).assertEqual(0)
    })

    it('returns_not_found_for_missing_or_empty_references', 0, () => {
      const steps = makeSteps(['Read the spec'])
      expect(resolvePlanStepIndex(steps, '')).assertEqual(-1)
      expect(resolvePlanStepIndex(steps, '   ')).assertEqual(-1)
      expect(resolvePlanStepIndex(steps, 'deploy')).assertEqual(-1)
      expect(resolvePlanStepIndex([], '1')).assertEqual(-1)
    })

    it('builds_steps_with_stable_ids_and_drops_blank_titles', 0, () => {
      const steps = buildPlanSteps(['  First  ', '', '   ', 'Second'])
      expect(steps.length).assertEqual(2)
      expect(steps[0].id).assertEqual('s1')
      expect(steps[0].title).assertEqual('First')
      expect(steps[1].id).assertEqual('s2')
      expect(steps[1].title).assertEqual('Second')
      expect(steps[0].status).assertEqual(PLAN_STEP_PENDING)
    })

    it('applies_supplied_statuses_positionally', 0, () => {
      const steps = buildPlanSteps(['One', 'Two', 'Three'], ['done', 'in_progress'])
      expect(steps[0].status).assertEqual(PLAN_STEP_DONE)
      expect(steps[1].status).assertEqual(PLAN_STEP_ACTIVE)
      // 状态数组比步骤短时，剩下的按未完成处理
      expect(steps[2].status).assertEqual(PLAN_STEP_PENDING)
    })

    it('caps_the_step_count', 0, () => {
      const titles: string[] = []
      for (let i = 0; i < PLAN_MAX_STEPS + 12; i++) {
        titles.push(`Step ${i + 1}`)
      }
      expect(buildPlanSteps(titles).length).assertEqual(PLAN_MAX_STEPS)
    })

    it('counts_steps_by_status', 0, () => {
      const steps = buildPlanSteps(['One', 'Two', 'Three'], ['done', 'done', 'pending'])
      expect(countPlanStepsByStatus(steps, PLAN_STEP_DONE)).assertEqual(2)
      expect(countPlanStepsByStatus(steps, PLAN_STEP_PENDING)).assertEqual(1)
      expect(countPlanStepsByStatus([], PLAN_STEP_DONE)).assertEqual(0)
    })
  })
}
