import { uiMaterial } from '@kit.ArkUI'
import { ToolConfig, ToolPermissionLevel, ToolSourceType } from '../../models/ChatModels'
import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { pickLocalizedText } from '../../utils/LocalizedTextUtils'

class McpToolGroup {
  sourceId: string = ''
  displayName: string = ''
  toolIds: string[] = []
  hasWriteTool: boolean = false

  constructor(sourceId: string, displayName: string) {
    this.sourceId = sourceId
    this.displayName = displayName
  }
}

@ComponentV2
export struct ChatToolPickerSheetContent {
  @Param availableChatTools: ToolConfig[] = []
  @Param selectedToolIds: string[] = []
  @Param isRefreshingMcpToolAvailability: boolean = false
  @Param themePrimary: ResourceColor = ''
  @Param themePrimaryLight: ResourceColor = ''
  @Param isDarkMode: boolean = false
  @Event onClose: () => void = (): void => {}
  @Event onRefresh: () => void = (): void => {}
  @Event onToggleTool: (toolId: string, enabled: boolean) => void =
    (_toolId: string, _enabled: boolean): void => {}
  @Event onToggleMcpGroup: (toolIds: string[], enabled: boolean) => void =
    (_toolIds: string[], _enabled: boolean): void => {}

  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }

  private get themePrimaryLightHex(): string {
    return getAppUiState().themePrimaryLight
  }

  private isMcpChatTool(tool: ToolConfig): boolean {
    return tool.sourceType === ToolSourceType.MCP && tool.sourceId.trim() !== ''
  }

  private isToolSelected(toolId: string): boolean {
    return this.selectedToolIds.includes(toolId)
  }

  private getBuiltinChatTools(): ToolConfig[] {
    const builtinTools: ToolConfig[] = []
    for (let i = 0; i < this.availableChatTools.length; i++) {
      const tool = this.availableChatTools[i]
      if (!this.isMcpChatTool(tool)) {
        builtinTools.push(tool)
      }
    }
    return builtinTools
  }

  private getMcpToolGroups(): McpToolGroup[] {
    const groups: McpToolGroup[] = []
    const groupIndexes: Map<string, number> = new Map()
    for (let i = 0; i < this.availableChatTools.length; i++) {
      const tool = this.availableChatTools[i]
      if (!this.isMcpChatTool(tool)) {
        continue
      }
      const existingIndex = groupIndexes.get(tool.sourceId)
      if (existingIndex === undefined) {
        const displayName = tool.sourceLabel.trim() !== '' ? tool.sourceLabel : tool.sourceId
        const group = new McpToolGroup(tool.sourceId, displayName)
        group.toolIds.push(tool.id)
        group.hasWriteTool = tool.permissionLevel === ToolPermissionLevel.WRITE
        groups.push(group)
        groupIndexes.set(tool.sourceId, groups.length - 1)
        continue
      }
      groups[existingIndex].toolIds.push(tool.id)
      if (tool.permissionLevel === ToolPermissionLevel.WRITE) {
        groups[existingIndex].hasWriteTool = true
      }
    }
    return groups
  }

  private isMcpToolGroupSelected(group: McpToolGroup): boolean {
    if (group.toolIds.length === 0) {
      return false
    }
    for (let i = 0; i < group.toolIds.length; i++) {
      if (!this.selectedToolIds.includes(group.toolIds[i])) {
        return false
      }
    }
    return true
  }

  private getCardBackground(selected: boolean): ResourceColor {
    return selected
      ? withColorAlpha(this.themePrimaryLightHex, 'D9')
      : withColorAlpha(this.themeSurface, 'CC')
  }

  private getCardBorderColor(): ResourceColor {
    return $r('app.color.divider')
  }

  private getCardShadowColor(selected: boolean): string {
    return selected ? 'rgba(0, 125, 255, 0.10)' : 'rgba(15, 23, 42, 0.04)'
  }

  private getBuiltinDescription(tool: ToolConfig): string {
    const description = tool.description.trim()
    return description !== '' ? description : pickLocalizedText(
      '应用内原生能力，可在当前聊天中按需调用。',
      'Built-in app capability that can be exposed to the model in this chat.'
    )
  }

  private getToolSymbolResource(toolId: string): Resource {
    if (toolId === 'web_search') {
      return $r('sys.symbol.worldclock_fill_2')
    }
    if (toolId === 'ask_user') {
      return $r('sys.symbol.ellipsis_message')
    }
    if (toolId === 'python_sandbox') {
      return $r('sys.symbol.doc_text')
    }
    if (toolId === 'canvas_document') {
      return $r('sys.symbol.paintbrush_pointed_waveform')
    }
    if (toolId === 'pdf_to_text') {
      return $r('sys.symbol.pdf_doc')
    }
    if (toolId === 'image_to_text') {
      return $r('sys.symbol.picture')
    }
    if (toolId === 'use_skill') {
      return $r('sys.symbol.more')
    }
    if (toolId === 'math_chart') {
      return $r('sys.symbol.histogram')
    }
    if (toolId === 'read_schedule') {
      return $r('sys.symbol.calendar')
    }
    if (toolId === 'write_schedule') {
      return $r('sys.symbol.calendar_badge_plus')
    }
    return $r('sys.symbol.wrench_and_screwdriver')
  }

  @Builder
  private BuiltinToolGridCard(tool: ToolConfig) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(this.getToolSymbolResource(tool.id))
            .fontSize(17)
            .fontColor([this.themePrimary])
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .clip(true)
        .backgroundColor(Color.Transparent)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN
        }))

        Toggle({ type: ToggleType.Switch, isOn: this.isToolSelected(tool.id) })
          .selectedColor(this.themePrimary)
          .systemMaterial(new uiMaterial.Material())
          .switchPointColor(Color.White)
          .onChange((value: boolean) => {
            this.onToggleTool(tool.id, value)
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text(tool.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (tool.permissionLevel === ToolPermissionLevel.WRITE) {
            Text(pickLocalizedText('需确认', 'Approval'))
              .fontSize(10)
              .fontColor(this.isDarkMode ? '#FFD6A6' : '#8A4B08')
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .borderRadius(999)
              .backgroundColor(this.isDarkMode ? '#3B2413' : '#FFF3E8')
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.getBuiltinDescription(tool))
          .fontSize(11)
          .lineHeight(16)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(138)
    .padding(12)
    .borderRadius(18)
    .backgroundColor(this.getCardBackground(this.isToolSelected(tool.id)))
    .border({
      width: 0.8,
      color: this.getCardBorderColor()
    })
    .shadow({
      radius: this.isToolSelected(tool.id) ? 14 : 10,
      color: this.getCardShadowColor(this.isToolSelected(tool.id)),
      offsetX: 0,
      offsetY: this.isToolSelected(tool.id) ? 6 : 4
    })
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([this.themePrimary])
          }
          .width('100%')
          .height('100%')
        }
        .width(36)
        .height(36)
        .padding(0)
        .borderRadius(18)
        .clip(true)
        .backgroundColor(Color.Transparent)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR,
          interactive: true,
          lightEffect: { color: undefined }
        }))
        .onClick(() => {
          this.onClose()
        })

        Text(pickLocalizedText('选择工具', 'Choose Tools'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)

        Button({ type: ButtonType.Normal, stateEffect: false }) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.isRefreshingMcpToolAvailability) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(this.themePrimary)
            } else {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(18)
                .fontColor([this.themePrimary])
            }
          }
          .width('100%')
          .height('100%')
        }
        .width(36)
        .height(36)
        .padding(0)
        .borderRadius(18)
        .clip(true)
        .backgroundColor(Color.Transparent)
        .enabled(!this.isRefreshingMcpToolAvailability)
        .opacity(this.isRefreshingMcpToolAvailability ? 0.72 : 1)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR,
          interactive: true,
          lightEffect: { color: undefined }
        }))
        .onClick(() => {
          if (!this.isRefreshingMcpToolAvailability) {
            this.onRefresh()
          }
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 18 }) {
          if (this.availableChatTools.length === 0) {
            Column({ space: 8 }) {
              Column() {
                SymbolGlyph($r('sys.symbol.gearshape'))
                  .fontSize(22)
                  .fontColor([this.themePrimary])
              }
              .width(48)
              .height(48)
              .borderRadius(14)
              .backgroundColor(this.themePrimaryLight)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Text(pickLocalizedText('暂无可用工具', 'No tools available'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(this.isRefreshingMcpToolAvailability
                ? pickLocalizedText('正在后台刷新工具，请稍候再试。', 'Refreshing tools in the background. Try again shortly.')
                : pickLocalizedText(
                  '请确认当前模型已开启工具能力，或到工具服务启用联网搜索 / MCP Server。',
                  'Make sure the current model has tool calling enabled, or enable web search / MCP servers in Tool Services.'
                ))
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 28, bottom: 28 })
            .borderRadius(20)
            .backgroundColor(withColorAlpha(this.themeSurface, 'CC'))
            .border({
              width: 0.5,
              color: $r('app.color.divider')
            })
            .shadow({ radius: 12, color: 'rgba(15, 23, 42, 0.04)', offsetX: 0, offsetY: 4 })
            .alignItems(HorizontalAlign.Center)
          } else {
            if (this.getBuiltinChatTools().length > 0) {
              Column({ space: 12 }) {
                Column({ space: 4 }) {
                  Text(pickLocalizedText('内置工具', 'Built-in Tools'))
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))

                  Text(pickLocalizedText(
                    '单个能力单独开关，启用后才会暴露给模型。',
                    'Each capability is toggled separately and only exposed to the model after enabling.'
                  ))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)

                Grid() {
                  ForEach(this.getBuiltinChatTools(), (tool: ToolConfig) => {
                    GridItem() {
                      this.BuiltinToolGridCard(tool)
                    }
                  }, (tool: ToolConfig) => tool.id)
                }
                .columnsTemplate('1fr 1fr')
                .columnsGap(10)
                .rowsGap(10)
                .width('100%')
              }
              .width('100%')
            }

            if (this.getMcpToolGroups().length > 0) {
              Column({ space: 12 }) {
                Text(pickLocalizedText('MCP 服务', 'MCP Services'))
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')

                ForEach(this.getMcpToolGroups(), (group: McpToolGroup) => {
                  Row({ space: 12 }) {
                    Stack({ alignContent: Alignment.Center }) {
                      SymbolGlyph($r('sys.symbol.link'))
                        .fontSize(19)
                        .fontColor([this.themePrimary])
                    }
                    .width(40)
                    .height(40)
                    .borderRadius(20)
                    .clip(true)
                    .backgroundColor(Color.Transparent)
                    .systemMaterial(new uiMaterial.ImmersiveMaterial({
                      style: uiMaterial.ImmersiveStyle.ULTRA_THIN
                    }))

                    Column({ space: 8 }) {
                      Row({ space: 8 }) {
                        Text(group.displayName)
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                          .layoutWeight(1)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })

                        if (group.hasWriteTool) {
                          Text(pickLocalizedText('需确认', 'Approval'))
                            .fontSize(10)
                            .fontColor(this.isDarkMode ? '#FFD6A6' : '#8A4B08')
                            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                            .borderRadius(999)
                            .backgroundColor(this.isDarkMode ? '#3B2413' : '#FFF3E8')
                        }
                      }
                      .width('100%')
                      .alignItems(VerticalAlign.Center)
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Toggle({ type: ToggleType.Switch, isOn: this.isMcpToolGroupSelected(group) })
                      .selectedColor(this.themePrimary)
                      .systemMaterial(new uiMaterial.Material())
                      .switchPointColor(Color.White)
                      .onChange((value: boolean) => {
                        this.onToggleMcpGroup(group.toolIds, value)
                      })
                  }
                  .width('100%')
                  .padding(14)
                  .borderRadius(18)
                  .backgroundColor(this.getCardBackground(this.isMcpToolGroupSelected(group)))
                  .border({
                    width: 0.8,
                    color: this.getCardBorderColor()
                  })
                  .shadow({
                    radius: this.isMcpToolGroupSelected(group) ? 14 : 10,
                    color: this.getCardShadowColor(this.isMcpToolGroupSelected(group)),
                    offsetX: 0,
                    offsetY: this.isMcpToolGroupSelected(group) ? 6 : 4
                  })
                }, (group: McpToolGroup) => group.sourceId)
              }
              .width('100%')
            }
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .constraintSize({ maxHeight: 520 })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }
}
