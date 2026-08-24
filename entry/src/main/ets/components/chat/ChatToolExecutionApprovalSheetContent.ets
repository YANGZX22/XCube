import { uiMaterial } from '@kit.ArkUI'
import { ToolPreviewEntry } from '../../utils/ToolPayloadSummaryUtils'
import { getAppUiState } from '../../state/AppUiState'
import { pickLocalizedText } from '../../utils/LocalizedTextUtils'
import { ImmersiveSheetHeader } from '../ImmersiveSheetHeader'

@ComponentV2
export struct ChatToolExecutionApprovalSheetContent {
  @Param sourceLabel: string = ''
  @Param toolName: string = ''
  @Param titleText: string = ''
  @Param argumentSummary: string = ''
  @Param argumentEntries: ToolPreviewEntry[] = []
  @Param argumentsPreview: string = '{}'
  @Param argumentsTruncated: boolean = false
  @Param showRawArguments: boolean = false
  @Param showWriteSafetyUi: boolean = true
  @Param showRiskNotice: boolean = true
  @Param showReadScheduleRangeUi: boolean = false
  @Param readScheduleDaysBeforeText: string = '0'
  @Param readScheduleDaysAfterText: string = '7'
  @Param readScheduleLimitText: string = '80'
  @Param readScheduleIncludeDescription: boolean = false
  @Param readScheduleIncludeLocation: boolean = true
  @Param themePrimary: ResourceColor = ''
  @Param isDarkMode: boolean = false
  @Event onToggleShowRaw: () => void = (): void => {}
  @Event onReadScheduleDaysBeforeChange: (value: string) => void = (_value: string): void => {}
  @Event onReadScheduleDaysAfterChange: (value: string) => void = (_value: string): void => {}
  @Event onReadScheduleLimitChange: (value: string) => void = (_value: string): void => {}
  @Event onReadScheduleIncludeDescriptionChange: (value: boolean) => void = (_value: boolean): void => {}
  @Event onReadScheduleIncludeLocationChange: (value: boolean) => void = (_value: boolean): void => {}
  @Event onCancel: () => void = (): void => {}
  @Event onApprove: () => void = (): void => {}

  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }

  build() {
    Column() {
      ImmersiveSheetHeader({
        title: this.titleText.trim() !== ''
          ? this.titleText
          : pickLocalizedText('确认工具调用', 'Approve Tool Call'),
        onLeadingClick: (): void => {
          this.onCancel()
        }
      })

      Column({ space: 16 }) {
        if (this.showWriteSafetyUi) {
          Row({ space: 10 }) {
            Text(pickLocalizedText(
              '该工具可能修改外部状态，请确认后再继续。',
              'This tool may change external state. Confirm before continuing.'
            ))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)

            Text(pickLocalizedText('写操作', 'Write'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor('#D9485F')
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }

      if (this.showWriteSafetyUi) {
        Column({ space: 10 }) {
          Column({ space: 4 }) {
            Text(pickLocalizedText('来源', 'Source'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
            Text(this.sourceLabel.trim() !== '' ? this.sourceLabel : pickLocalizedText('未知来源', 'Unknown source'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 4 }) {
            Text(pickLocalizedText('工具', 'Tool'))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
            Text(this.toolName.trim() !== '' ? this.toolName : pickLocalizedText('未知工具', 'Unknown tool'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor(this.themeSurface)
      }

      if (this.showWriteSafetyUi && this.showRiskNotice) {
        Column({ space: 6 }) {
          Text(pickLocalizedText('风险提醒', 'Risk Notice'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor('#B85A00')

          Text(pickLocalizedText(
            '这是写操作工具。模型只是提出调用，真正执行前仍需要你明确批准。',
            'This is a write tool. The model only proposes the call, and you still have to explicitly approve it.'
          ))
            .fontSize(12)
            .lineHeight(18)
            .fontColor(this.isDarkMode ? '#FFD6A6' : '#8A4B08')
            .width('100%')
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor(this.isDarkMode ? '#3B2413' : '#FFF3E8')
      }

      if (this.showReadScheduleRangeUi) {
        Column({ space: 12 }) {
          Column({ space: 4 }) {
            Text(pickLocalizedText('读取范围', 'Read Range'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))

            Text(pickLocalizedText(
              '只会把这个范围内的日程提供给模型。',
              'Only events in this range will be provided to the model.'
            ))
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Row({ space: 8 }) {
            this.ReadScheduleNumberField(
              pickLocalizedText('向前天数', 'Days Back'),
              this.readScheduleDaysBeforeText,
              pickLocalizedText('0', '0'),
              (value: string): void => {
                this.onReadScheduleDaysBeforeChange(value)
              }
            )

            this.ReadScheduleNumberField(
              pickLocalizedText('向后天数', 'Days Ahead'),
              this.readScheduleDaysAfterText,
              pickLocalizedText('7', '7'),
              (value: string): void => {
                this.onReadScheduleDaysAfterChange(value)
              }
            )

            this.ReadScheduleNumberField(
              pickLocalizedText('数量上限', 'Limit'),
              this.readScheduleLimitText,
              pickLocalizedText('80', '80'),
              (value: string): void => {
                this.onReadScheduleLimitChange(value)
              }
            )
          }
          .width('100%')

          Column({ space: 8 }) {
            this.ReadScheduleToggleRow(
              pickLocalizedText('包含地点', 'Include Location'),
              this.readScheduleIncludeLocation,
              (value: boolean): void => {
                this.onReadScheduleIncludeLocationChange(value)
              }
            )

            this.ReadScheduleToggleRow(
              pickLocalizedText('包含备注', 'Include Notes'),
              this.readScheduleIncludeDescription,
              (value: boolean): void => {
                this.onReadScheduleIncludeDescriptionChange(value)
              }
            )
          }
          .width('100%')
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor(Color.Transparent)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: Color.Transparent,
          applyShadow: false,
          interactive: false,
          lightEffect: { color: undefined }
        }))
      }

      Column({ space: 8 }) {
        Row() {
          Text(pickLocalizedText('关键参数', 'Key Arguments'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(this.showRawArguments
            ? pickLocalizedText('收起原始参数', 'Hide Raw Arguments')
            : pickLocalizedText('查看原始参数', 'Show Raw Arguments'))
            .fontSize(11)
            .fontColor(this.themePrimary)
            .onClick(() => {
              this.onToggleShowRaw()
            })
        }
        .width('100%')

        if (this.argumentEntries.length > 0) {
          Column({ space: 8 }) {
            ForEach(this.argumentEntries, (entry: ToolPreviewEntry) => {
              Row() {
                Column({ space: 2 }) {
                  Text(this.resolveArgumentDisplayLabel(entry.label))
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(entry.label)
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width(104)
                .alignItems(HorizontalAlign.Start)

                Text(entry.value)
                  .layoutWeight(1)
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }, (entry: ToolPreviewEntry, index: number) => `${entry.label}_${index}`)
          }
          .width('100%')
          .padding(12)
          .borderRadius(14)
          .backgroundColor(this.themeSurface)
        } else {
          Text(this.argumentSummary)
            .width('100%')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .padding(12)
            .borderRadius(14)
            .backgroundColor(this.themeSurface)
        }

        if (this.showRawArguments) {
          Scroll() {
            Text(this.argumentsPreview)
              .width('100%')
              .fontSize(12)
              .lineHeight(18)
              .fontFamily('monospace')
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Start)
          }
          .width('100%')
          .constraintSize({ maxHeight: 220 })
          .padding(12)
          .borderRadius(14)
          .backgroundColor(this.isDarkMode ? '#14171F' : '#F6F8FC')
        }

        if (this.showRawArguments && this.argumentsTruncated) {
          Text(pickLocalizedText(
            '仅展示前 800 个字符，避免长参数把确认面板撑坏。',
            'Only the first 800 characters are shown to keep the approval panel readable.'
          ))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
      }
      .width('100%')

      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .layoutWeight(1)
          .height(46)
          .type(ButtonType.Capsule)
          .backgroundColor(this.themeSurface)
          .fontColor($r('app.color.text_primary'))
          .border({
            width: 0.5,
            color: $r('app.color.divider')
          })
          .onClick(() => {
            this.onCancel()
          })

        Button(pickLocalizedText('继续执行', 'Continue'))
          .layoutWeight(1)
          .height(46)
          .type(ButtonType.Capsule)
          .backgroundColor(this.themePrimary)
          .fontColor(Color.White)
          .onClick(() => {
            this.onApprove()
          })
      }
      .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 24 })
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private ReadScheduleNumberField(
    label: string,
    value: string,
    placeholder: string,
    onChange: (value: string) => void
  ) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      TextInput({ text: value, placeholder: placeholder })
        .width('100%')
        .height(38)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor(Color.Transparent)
        .borderRadius(10)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: Color.Transparent,
          applyShadow: false,
          interactive: true,
          lightEffect: { color: undefined }
        }))
        .textAlign(TextAlign.Center)
        .onChange((input: string) => {
          onChange(input)
        })
    }
    .layoutWeight(1)
    .constraintSize({ minWidth: 0 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ReadScheduleToggleRow(label: string, checked: boolean, onChange: (value: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .width(56)
        .height(30)
        .selectedColor(this.themePrimary)
        .systemMaterial(new uiMaterial.Material())
        .switchPointColor(Color.White)
        .onChange((isOn: boolean) => {
          onChange(isOn)
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 10 })
    .borderRadius(12)
    .backgroundColor(Color.Transparent)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: false,
      lightEffect: { color: undefined }
    }))
    .alignItems(VerticalAlign.Center)
  }

  private resolveArgumentDisplayLabel(label: string): string {
    switch (label) {
      case 'days_before':
      case 'daysBefore':
        return pickLocalizedText('向前天数', 'Days Back')
      case 'days_after':
      case 'daysAfter':
        return pickLocalizedText('向后天数', 'Days Ahead')
      case 'limit':
        return pickLocalizedText('数量上限', 'Result Limit')
      case 'include_description':
      case 'includeDescription':
        return pickLocalizedText('包含备注', 'Include Notes')
      case 'include_location':
      case 'includeLocation':
        return pickLocalizedText('包含地点', 'Include Location')
      case 'title':
        return pickLocalizedText('标题', 'Title')
      case 'start_time':
      case 'startTime':
        return pickLocalizedText('开始时间', 'Start Time')
      case 'end_time':
      case 'endTime':
        return pickLocalizedText('结束时间', 'End Time')
      case 'all_day':
      case 'allDay':
        return pickLocalizedText('全天事件', 'All Day')
      case 'description':
        return pickLocalizedText('备注', 'Notes')
      case 'location':
        return pickLocalizedText('地点', 'Location')
      case 'reminder_minutes_before':
      case 'reminderMinutesBefore':
        return pickLocalizedText('提前提醒', 'Reminder')
      case 'query':
      case 'q':
      case 'keywords':
        return pickLocalizedText('搜索内容', 'Search Query')
      case 'url':
        return pickLocalizedText('链接', 'URL')
      case 'page':
        return pickLocalizedText('页码', 'Page')
      default:
        return pickLocalizedText('参数', 'Argument')
    }
  }
}
