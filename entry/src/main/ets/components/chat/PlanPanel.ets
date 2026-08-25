import { getAppUiState } from '../../state/AppUiState'
import { VisualEffectsMode } from '../../models/ThemeColors'
import { pickLocalizedText } from '../../utils/LocalizedTextUtils'
import { MANUSCRIPT_BODY_FONT, MANUSCRIPT_HEADING_FONT } from '../../utils/ManuscriptVisualUtils'
import { PLAN_STEP_ACTIVE, PLAN_STEP_DONE, PlanStep } from '../../services/PlanService'

@ComponentV2
export struct PlanPanel {
  @Param planTitle: string = 'Plan'
  @Param steps: PlanStep[] = []
  @Event onToggleStep: (index: number) => void = (_index: number): void => {}
  @Event onClearPlan: () => void = (): void => {}
  @Event onClosePanel: () => void = (): void => {}

  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get accentColor(): string {
    if (!this.isManuscriptMode) {
      return this.themePrimary
    }
    return getAppUiState().isDarkMode ? '#C99A52' : '#B68235'
  }

  private getDoneCount(): number {
    let count = 0
    for (let i = 0; i < this.steps.length; i++) {
      if (this.steps[i].status === PLAN_STEP_DONE) {
        count += 1
      }
    }
    return count
  }

  private getProgressText(): string {
    if (this.steps.length === 0) {
      return pickLocalizedText('等待模型写入计划', 'Waiting for the model to lay out a plan')
    }
    const done = this.getDoneCount()
    return pickLocalizedText(
      `已完成 ${done} / ${this.steps.length} 步`,
      `${done} of ${this.steps.length} steps done`
    )
  }

  private getStepIcon(status: string): Resource {
    if (status === PLAN_STEP_DONE) {
      return $r('sys.symbol.checkmark_circle_fill')
    }
    if (status === PLAN_STEP_ACTIVE) {
      return $r('sys.symbol.record_circle')
    }
    return $r('sys.symbol.circle')
  }

  private getStepColor(status: string): ResourceColor {
    if (status === PLAN_STEP_DONE) {
      return this.accentColor
    }
    if (status === PLAN_STEP_ACTIVE) {
      return this.accentColor
    }
    return $r('app.color.text_tertiary')
  }

  @Builder
  private StepRowBuilder(step: PlanStep, index: number) {
    Row({ space: 10 }) {
      SymbolGlyph(this.getStepIcon(step.status))
        .fontSize(16)
        .fontColor([this.getStepColor(step.status)])

      Text(step.title)
        .fontFamily(this.isManuscriptMode ? MANUSCRIPT_BODY_FONT : 'HarmonyOS Sans')
        .fontSize(13)
        .lineHeight(19)
        // 已完成的步骤保留可读性即可，划掉会让长计划难以回看
        .fontColor(step.status === PLAN_STEP_DONE
          ? $r('app.color.text_tertiary') : $r('app.color.text_primary'))
        .decoration({
          type: step.status === PLAN_STEP_DONE ? TextDecorationType.LineThrough : TextDecorationType.None,
          color: $r('app.color.text_tertiary')
        })
        .layoutWeight(1)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 7, bottom: 7 })
    .onClick((): void => {
      this.onToggleStep(index)
    })
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.planTitle.trim() !== '' ? this.planTitle : pickLocalizedText('计划', 'Plan'))
            .fontFamily(this.isManuscriptMode ? MANUSCRIPT_HEADING_FONT : 'HarmonyOS Sans')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.getProgressText())
            .fontFamily(this.isManuscriptMode ? MANUSCRIPT_BODY_FONT : 'HarmonyOS Sans')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(14)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(32)
        .height(32)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .stateEffect(true)
        .enabled(this.steps.length > 0)
        .opacity(this.steps.length > 0 ? 1 : 0.4)
        .onClick((): void => {
          this.onClearPlan()
        })

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(32)
        .height(32)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .stateEffect(true)
        .onClick((): void => {
          this.onClosePanel()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 手稿模式只用线条语言分隔，不加边框或底板
      Divider()
        .strokeWidth(this.isManuscriptMode ? 0.8 : 0.5)
        .color(this.isManuscriptMode ? this.accentColor : getAppUiState().themeDivider)
        .opacity(this.isManuscriptMode ? 0.5 : 1)

      if (this.steps.length === 0) {
        Column() {
          Text(pickLocalizedText(
            '还没有计划步骤。\n让模型开始一个多步任务，或直接说明你的目标。',
            'No steps yet.\nAsk the model to start a multi-step task, or describe your goal.'
          ))
            .fontFamily(this.isManuscriptMode ? MANUSCRIPT_BODY_FONT : 'HarmonyOS Sans')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.steps, (step: PlanStep, index: number) => {
            ListItem({ style: ListItemStyle.NONE }) {
              this.StepRowBuilder(step, index)
            }
          }, (step: PlanStep, index: number): string => `${step.id}_${index}_${step.status}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }
}
