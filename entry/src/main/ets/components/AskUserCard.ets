import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { uiMaterial } from '@kit.ArkUI'
import { VisualEffectsMode } from '../models/ThemeColors'
import { MANUSCRIPT_COMPACT_BAR_HEIGHT } from '../utils/ManuscriptVisualUtils'
import {
  buildTimelineBarExpandTransition,
  getTimelineBarExpandAnimation
} from '../utils/TimelineBarTransitionUtils'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'

interface AskUserQuestion {
  id: string
  question: string
  options: string[]
  selectionType: string
}

interface AskUserArgs {
  questions?: Object[]
}

interface AskUserAnswerItem {
  question: string
  selection_type: string
  selected_options: string[]
  custom_answer: string
  answer: string
  skipped: boolean
}

interface AskUserAnswerPayload {
  answers: Record<string, AskUserAnswerItem>
  answered_ids: string[]
  skipped_ids: string[]
  summary: string
}

@ComponentV2
export struct AskUserCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param toolCalls: ToolCall[] = []
  @Param isAnswered: boolean = false
  @Param compactMode: boolean = false
  // 合并进条目块时由外层统一提供边框、材质与投影，卡片自身只出内容
  @Param embedded: boolean = false
  @Param resultContent: string = ''
  @Param resultContents: string[] = []
  @Param pendingCount: number = 1
  @Event onAnswer: (toolCallId: string, answerJson: string) => void =
    (_toolCallId: string, _answerJson: string): void => {}
  @Event onRequestAnswer: (toolCallId: string) => void = (_toolCallId: string): void => {}

  @Local textAnswers: Map<string, string> = new Map()
  @Local multiAnswers: Map<string, Set<string>> = new Map()
  @Local customAnswers: Map<string, string> = new Map()
  @Local isExpanded: boolean = false

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get isManuscriptMode(): boolean {
    return getAppUiState().visualEffectsMode === VisualEffectsMode.MANUSCRIPT
  }

  private getDisplayedToolCalls(): ToolCall[] {
    if (this.compactMode && this.toolCalls.length > 0) {
      return this.toolCalls
    }
    return [this.toolCall]
  }

  private getResultContentAt(index: number): string {
    if (this.compactMode && index >= 0 && index < this.resultContents.length) {
      return this.resultContents[index]
    }
    return this.resultContent
  }

  private getLatestPendingToolCallId(): string {
    const calls = this.getDisplayedToolCalls()
    for (let i = calls.length - 1; i >= 0; i--) {
      if (this.getResultContentAt(i).trim() === '') {
        return calls[i].id
      }
    }
    return calls.length > 0 ? calls[calls.length - 1].id : this.toolCall.id
  }

  private parseQuestions(): AskUserQuestion[] {
    return this.parseQuestionsFor(this.toolCall)
  }

  private parseQuestionsFor(toolCall: ToolCall): AskUserQuestion[] {
    const out: AskUserQuestion[] = []
    try {
      const parsed = JSON.parse(toolCall.arguments) as AskUserArgs
      const rawQs = parsed.questions
      if (!Array.isArray(rawQs)) {
        return out
      }
      const list = rawQs as Object[]
      for (let i = 0; i < list.length; i++) {
        const obj = list[i] as Record<string, Object>
        if (obj === null || obj === undefined) {
          continue
        }
        const id = (obj['id'] as string | undefined) ?? `q_${i + 1}`
        const question = (obj['question'] as string | undefined) ?? ''
        const selectionType = (obj['selection_type'] as string | undefined) ?? 'text'
        const options: string[] = []
        const rawOpts = obj['options'] as Object
        if (Array.isArray(rawOpts)) {
          const arr = rawOpts as string[]
          for (let j = 0; j < arr.length; j++) {
            if (typeof arr[j] === 'string' && arr[j] !== '') {
              options.push(arr[j])
            }
          }
        }
        out.push({ id: id, question: question, options: options, selectionType: selectionType })
      }
    } catch (_error) {}
    return out
  }

  private setTextAnswer(questionId: string, value: string): void {
    const next = new Map<string, string>()
    this.textAnswers.forEach((answer: string, key: string) => {
      next.set(key, answer)
    })
    next.set(questionId, value)
    this.textAnswers = next
  }

  private setCustomAnswer(questionId: string, value: string): void {
    const next = new Map<string, string>()
    this.customAnswers.forEach((answer: string, key: string) => {
      next.set(key, answer)
    })
    next.set(questionId, value)
    this.customAnswers = next
  }

  private toggleMulti(questionId: string, option: string): void {
    const current = this.multiAnswers.get(questionId)
    const nextSet = new Set<string>()
    if (current !== undefined) {
      current.forEach((value: string) => {
        nextSet.add(value)
      })
    }
    if (nextSet.has(option)) {
      nextSet.delete(option)
    } else {
      nextSet.add(option)
    }
    const nextMap = new Map<string, Set<string>>()
    this.multiAnswers.forEach((value: Set<string>, key: string) => {
      nextMap.set(key, value)
    })
    nextMap.set(questionId, nextSet)
    this.multiAnswers = nextMap
  }

  private buildSelectedOptions(question: AskUserQuestion): string[] {
    if (question.selectionType === 'multi') {
      return Array.from(this.multiAnswers.get(question.id) ?? new Set<string>())
    }
    if (question.selectionType === 'single') {
      const selected = this.textAnswers.get(question.id) ?? ''
      return selected.trim() !== '' ? [selected.trim()] : []
    }
    return []
  }

  private buildQuestionAnswer(question: AskUserQuestion, selectedOptions: string[], customAnswer: string): string {
    if (question.selectionType === 'text') {
      return customAnswer
    }
    if (selectedOptions.length > 0 && customAnswer !== '') {
      return `${selectedOptions.join(', ')}；${customAnswer}`
    }
    if (selectedOptions.length > 0) {
      return selectedOptions.join(', ')
    }
    return customAnswer
  }

  private buildPayload(questions: AskUserQuestion[], skipAll: boolean = false): string {
    const answers: Record<string, AskUserAnswerItem> = {}
    const answeredIds: string[] = []
    const skippedIds: string[] = []
    for (let i = 0; i < questions.length; i++) {
      const question = questions[i]
      const selectedOptions = skipAll ? [] : this.buildSelectedOptions(question)
      const customAnswer = skipAll ? '' : ((question.selectionType === 'text'
        ? (this.textAnswers.get(question.id) ?? '')
        : (this.customAnswers.get(question.id) ?? '')).trim())
      const answer = this.buildQuestionAnswer(question, selectedOptions, customAnswer).trim()
      const skipped = answer === ''
      if (skipped) {
        skippedIds.push(question.id)
      } else {
        answeredIds.push(question.id)
      }
      answers[question.id] = {
        question: question.question,
        selection_type: question.selectionType,
        selected_options: selectedOptions,
        custom_answer: customAnswer,
        answer: answer,
        skipped: skipped
      }
    }
    const payload: AskUserAnswerPayload = {
      answers: answers,
      answered_ids: answeredIds,
      skipped_ids: skippedIds,
      summary: answeredIds.length > 0
        ? pickLocalizedText(
          `用户回答了 ${answeredIds.length} 个问题，跳过 ${skippedIds.length} 个问题`,
          `The user answered ${answeredIds.length} question(s) and skipped ${skippedIds.length}.`)
        : pickLocalizedText('用户跳过了本次询问', 'The user skipped these questions.')
    }
    return JSON.stringify(payload)
  }

  private handleSubmit(questions: AskUserQuestion[]): void {
    this.onAnswer(this.toolCall.id, this.buildPayload(questions))
  }

  private handleSkipAll(questions: AskUserQuestion[]): void {
    this.onAnswer(this.toolCall.id, this.buildPayload(questions, true))
  }

  private hasAnyAnswer(questions: AskUserQuestion[]): boolean {
    for (let i = 0; i < questions.length; i++) {
      const question = questions[i]
      if (this.buildSelectedOptions(question).length > 0) {
        return true
      }
      const textAnswer = this.textAnswers.get(question.id) ?? ''
      const customAnswer = this.customAnswers.get(question.id) ?? ''
      if (textAnswer.trim() !== '' || customAnswer.trim() !== '') {
        return true
      }
    }
    return false
  }

  private getQuestionBackgroundColor(): ResourceColor {
    if (this.isManuscriptMode) {
      return Color.Transparent
    }
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  private getChipBackgroundColor(selected: boolean): ResourceColor {
    if (this.isManuscriptMode) {
      return selected ? this.themePrimaryLight : Color.Transparent
    }
    return selected ? this.themePrimary : $r('app.color.surface')
  }

  private getCompactRailColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '88' : '55')
  }

  private isOptionSelected(question: AskUserQuestion, option: string, resultContent: string = ''): boolean {
    if (this.compactMode && resultContent.trim() !== '') {
      const answer = this.getResolvedAnswer(question.id, resultContent)
      return answer !== undefined && Array.isArray(answer.selected_options) && answer.selected_options.includes(option)
    }
    if (question.selectionType === 'multi') {
      const set = this.multiAnswers.get(question.id)
      return set !== undefined && set.has(option)
    }
    return this.textAnswers.get(question.id) === option
  }

  private getResolvedAnswer(questionId: string, resultContent: string): AskUserAnswerItem | undefined {
    if (resultContent.trim() === '') {
      return undefined
    }
    try {
      const payload = JSON.parse(resultContent) as AskUserAnswerPayload
      return payload.answers[questionId]
    } catch (_error) {
      return undefined
    }
  }

  private getDisplayedTextAnswer(question: AskUserQuestion, resultContent: string = ''): string {
    if (!this.compactMode) {
      return this.textAnswers.get(question.id) ?? ''
    }
    const answer = this.getResolvedAnswer(question.id, resultContent)
    if (answer === undefined) {
      return ''
    }
    return answer.answer ?? ''
  }

  private getDisplayedCustomAnswer(question: AskUserQuestion, resultContent: string = ''): string {
    if (!this.compactMode) {
      return this.customAnswers.get(question.id) ?? ''
    }
    const answer = this.getResolvedAnswer(question.id, resultContent)
    if (answer === undefined) {
      return ''
    }
    return answer.custom_answer ?? ''
  }

  private toggleExpanded(): void {
    this.getUIContext().animateTo(getTimelineBarExpandAnimation(), () => {
      this.isExpanded = !this.isExpanded
    })
  }

  build() {
    Column({ space: this.compactMode ? 0 : 10 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(14)
          .fontColor([this.compactMode && !this.isManuscriptMode
            ? $r('app.color.text_secondary') : this.themePrimary])
        Text(this.compactMode
          ? (this.isAnswered
            ? pickLocalizedText('向用户提问结果', 'User Answer Result')
            : pickLocalizedText('等待用户回答', 'Waiting for User'))
          : (this.parseQuestions().length > 1
            ? pickLocalizedText('我有几个问题想确认一下', 'I have a few questions to clarify')
            : pickLocalizedText('我有个问题想确认一下', 'I have a question to clarify')))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.compactMode
            ? (this.isManuscriptMode ? this.themePrimary : $r('app.color.text_secondary'))
            : $r('app.color.text_primary'))
          .margin({ left: 6 })

        if (this.isAnswered) {
          if (this.compactMode) {
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(14)
              .fontColor([$r('app.color.status_success')])
              .margin({ left: 8 })
          } else {
            Blank()
            Text(pickLocalizedText('已回答', 'Answered'))
              .fontSize(10)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.status_success'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
          }
        } else if (this.compactMode) {
          Text(pickLocalizedText('回答', 'Answer'))
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor(this.themePrimary)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(8)
            .onClick(() => {
              this.onRequestAnswer(this.getLatestPendingToolCallId())
            })
        }

        if (this.compactMode && this.getDisplayedToolCalls().length > 1) {
          Blank()
            .layoutWeight(1)

          Text(`× ${this.getDisplayedToolCalls().length}`)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
            .textAlign(TextAlign.Center)
            .padding({ left: 7, right: 7, top: 1, bottom: 1 })
            .borderRadius(this.isManuscriptMode ? 0 : 9)
            .backgroundColor(this.isManuscriptMode ? Color.Transparent : this.themePrimaryLight)
            .border({ width: 0, color: this.themePrimary })
        }

        if (!this.compactMode && this.pendingCount > 1) {
          Blank()
          Text(pickLocalizedText(`${this.pendingCount} 个待回答`, `${this.pendingCount} pending`))
            .fontSize(10)
            .fontColor(this.themePrimary)
            .margin({ left: 8 })
        }

        if (this.compactMode) {
          Blank()
            .layoutWeight(1)

          Row() {
            Text(this.isExpanded ? $r('app.string.common_collapse') : $r('app.string.common_details'))
              .fontSize(11)
              .fontColor(this.isManuscriptMode ? this.themePrimary : $r('app.color.text_tertiary'))

            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(12)
              .fontColor([this.isManuscriptMode ? this.themePrimary : $r('app.color.text_tertiary')])
              .rotate({ angle: this.isExpanded ? 180 : 0 })
              .animation(getTimelineBarExpandAnimation())
              .margin({ left: 2 })
          }
            .onClick(() => {
              this.toggleExpanded()
            })
        }
      }
      .width('100%')
      .height(this.compactMode ? (this.isManuscriptMode ? MANUSCRIPT_COMPACT_BAR_HEIGHT : 36) : undefined)
      .padding(this.compactMode
        ? { left: this.isManuscriptMode ? 14 : 10, right: this.isManuscriptMode ? 14 : 10 }
        : 0)

      if (!this.compactMode) {
        ForEach(this.parseQuestions(), (question: AskUserQuestion, index: number) => {
          this.QuestionBlock(question, index, '')
        }, (question: AskUserQuestion) => question.id)
      } else if (this.isExpanded) {
        Column({ space: 8 }) {
          ForEach(this.getDisplayedToolCalls(), (toolCall: ToolCall, callIndex: number) => {
            Column({ space: 8 }) {
              if (callIndex > 0) {
                Divider()
                  .color($r('app.color.divider'))
                  .margin({ top: 2, bottom: 2 })
              }

              if (this.getDisplayedToolCalls().length > 1) {
                Text(pickLocalizedText(`第 ${callIndex + 1} 次提问`, `Question Set ${callIndex + 1}`))
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }

              ForEach(this.parseQuestionsFor(toolCall), (question: AskUserQuestion, questionIndex: number) => {
                this.QuestionBlock(question, questionIndex, this.getResultContentAt(callIndex))
              }, (question: AskUserQuestion) => question.id)
            }
            .width('100%')
          }, (toolCall: ToolCall) => toolCall.id)
        }
        .width('100%')
        .padding({ left: 10, right: 10, bottom: 8 })
        .transition(buildTimelineBarExpandTransition())
      }

      if (!this.isAnswered && !this.compactMode) {
        Row({ space: 8 }) {
          Button(pickLocalizedText('跳过', 'Skip'))
            .height(32)
            .padding({ left: 14, right: 14 })
            .fontSize(13)
            .fontColor(this.isManuscriptMode ? this.themePrimary : $r('app.color.text_secondary'))
            .backgroundColor(this.isManuscriptMode ? Color.Transparent : $r('app.color.surface'))
            .border({
              width: this.isManuscriptMode ? { bottom: 1 } : 0.5,
              color: this.isManuscriptMode ? this.themePrimary : $r('app.color.divider')
            })
            .borderRadius(this.isManuscriptMode ? 0 : 16)
            .onClick(() => {
              this.handleSkipAll(this.parseQuestions())
            })

          Button(pickLocalizedText('提交', 'Submit'))
            .height(32)
            .padding({ left: 16, right: 16 })
            .fontSize(13)
            .fontColor(this.isManuscriptMode ? this.themePrimary : Color.White)
            .backgroundColor(this.isManuscriptMode ? Color.Transparent : this.themePrimary)
            .border({ width: this.isManuscriptMode ? { bottom: 1 } : 0, color: this.themePrimary })
            .borderRadius(this.isManuscriptMode ? 0 : 16)
            .enabled(this.hasAnyAnswer(this.parseQuestions()))
            .onClick(() => {
              this.handleSubmit(this.parseQuestions())
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }
    }
    .width('100%')
    .padding(this.compactMode ? 0 : 12)
    .backgroundColor(this.isManuscriptMode && !this.compactMode ? this.themeSurface : Color.Transparent)
    .borderRadius(this.embedded || this.isManuscriptMode ? 0 : (this.compactMode ? 12 : 16))
    .border({
      width: this.embedded ? 0 :
        (this.isManuscriptMode ? { top: 1, bottom: 1 } : (this.compactMode ? 0.5 : 1)),
      color: this.isManuscriptMode ? getAppUiState().themeDivider :
        (this.compactMode ? this.getCompactRailColor() : this.themePrimaryLight)
    })
    .systemMaterial(this.embedded || this.isManuscriptMode ? undefined : new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: this.compactMode ? this.themeAiBubble : Color.Transparent,
      applyShadow: !this.compactMode,
      interactive: !this.compactMode,
      lightEffect: { color: this.compactMode ? undefined : Color.White }
    }))
    .shadow({
      radius: this.embedded || this.isManuscriptMode ? 0 : (this.compactMode ? 12 : 24),
      color: this.embedded || this.isManuscriptMode ? Color.Transparent : (this.compactMode
        ? (this.isDarkMode ? 'rgba(0, 0, 0, 0.32)' : 'rgba(15, 23, 42, 0.14)')
        : (this.isDarkMode ? 'rgba(0, 0, 0, 0.48)' : 'rgba(15, 23, 42, 0.22)')),
      offsetX: 0,
      offsetY: this.compactMode ? 0 : 8
    })
  }

  @Builder
  private QuestionBlock(question: AskUserQuestion, index: number, resultContent: string) {
    Column({ space: 6 }) {
      Text(question.question !== '' ? question.question : pickLocalizedText(`问题 ${index + 1}`, `Question ${index + 1}`))
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      if (question.options.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(question.options, (option: string) => {
            this.OptionChip(question, option, resultContent)
          }, (option: string) => option)
        }
      }

      if (question.selectionType === 'text') {
        TextInput({
          text: this.getDisplayedTextAnswer(question, resultContent),
          placeholder: this.compactMode
            ? pickLocalizedText('未回答', 'Not answered')
            : pickLocalizedText('输入你的回答', 'Enter your answer')
        })
          .width('100%')
          .height(36)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor(Color.Transparent)
          .borderRadius(this.isManuscriptMode ? 0 : 8)
          .clip(true)
          .border({
            width: this.isManuscriptMode ? { bottom: 1 } : 0,
            color: this.isManuscriptMode ? getAppUiState().themeDivider : Color.Transparent
          })
          .backgroundBlurStyle(this.isManuscriptMode ? undefined : BlurStyle.COMPONENT_REGULAR)
          .enabled(!this.isAnswered && !this.compactMode)
          .onChange((value: string) => {
            this.setTextAnswer(question.id, value)
          })
      } else {
        TextInput({
          text: this.getDisplayedCustomAnswer(question, resultContent),
          placeholder: this.compactMode
            ? pickLocalizedText('无自定义答案', 'No custom answer')
            : pickLocalizedText('自定义答案，可留空', 'Custom answer (optional)')
        })
          .width('100%')
          .height(34)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor(Color.Transparent)
          .borderRadius(this.isManuscriptMode ? 0 : 8)
          .clip(true)
          .border({
            width: this.isManuscriptMode ? { bottom: 1 } : 0,
            color: this.isManuscriptMode ? getAppUiState().themeDivider : Color.Transparent
          })
          .backgroundBlurStyle(this.isManuscriptMode ? undefined : BlurStyle.COMPONENT_REGULAR)
          .enabled(!this.isAnswered && !this.compactMode)
          .onChange((value: string) => {
            this.setCustomAnswer(question.id, value)
          })
      }
    }
    .width('100%')
    .padding(this.isManuscriptMode ? { top: 10, bottom: 10 } : 10)
    .backgroundColor(this.getQuestionBackgroundColor())
    .borderRadius(this.isManuscriptMode ? 0 : 16)
    .border({
      width: this.isManuscriptMode ? { top: 1, bottom: 1 } : 0,
      color: this.isManuscriptMode ? getAppUiState().themeDivider : Color.Transparent
    })
  }

  @Builder
  private OptionChip(question: AskUserQuestion, option: string, resultContent: string) {
    Row() {
      Text(option)
        .fontSize(12)
        .fontColor(this.isOptionSelected(question, option, resultContent)
          ? (this.isManuscriptMode ? this.themePrimary : Color.White)
          : $r('app.color.text_primary'))
    }
    .height(this.isManuscriptMode ? 30 : undefined)
    .padding({ left: this.isManuscriptMode ? 12 : 10, right: this.isManuscriptMode ? 12 : 10,
      top: this.isManuscriptMode ? 0 : 6, bottom: this.isManuscriptMode ? 0 : 6 })
    .margin({ right: 6, bottom: 6 })
    .backgroundColor(this.getChipBackgroundColor(this.isOptionSelected(question, option, resultContent)))
    .borderRadius(this.isManuscriptMode ? 3 : 12)
    .border({
      width: this.isManuscriptMode ? 1 : 0.5,
      color: this.isManuscriptMode && this.isOptionSelected(question, option, resultContent) ?
        this.themePrimary : $r('app.color.divider')
    })
    .onClick(() => {
      if (this.isAnswered || this.compactMode) {
        return
      }
      if (question.selectionType === 'multi') {
        this.toggleMulti(question.id, option)
      } else {
        this.setTextAnswer(question.id, option)
      }
    })
  }
}
