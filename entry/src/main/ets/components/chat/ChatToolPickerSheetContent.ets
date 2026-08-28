import { uiMaterial } from '@kit.ArkUI'
import { ToolConfig, ToolPermissionLevel, ToolSourceType } from '../../models/ChatModels'
import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { pickLocalizedText } from '../../utils/LocalizedTextUtils'
import { getLocalizedBuiltinToolDescription, getLocalizedBuiltinToolName } from '../../utils/ToolDisplayTextUtils'
import { ImmersiveSheetHeader } from '../ImmersiveSheetHeader'
import { resolveToolSymbolResource } from '../../utils/ToolIconUtils'

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

class BuiltinToolCategory {
  key: string = ''
  title: string = ''
  tools: ToolConfig[] = []

  constructor(key: string, title: string) {
    this.key = key
    this.title = title
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
  @Event onToggleAll: (toolIds: string[], enabled: boolean) => void =
    (_toolIds: string[], _enabled: boolean): void => {}

  private get themeSurface(): string {
    return getAppUiState().themeSurface
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
      if (tool.id !== 'knowledge_search' && !this.isMcpChatTool(tool)) {
        builtinTools.push(tool)
      }
    }
    return builtinTools
  }

  private resolveBuiltinCategoryKey(toolId: string): string {
    if (toolId === 'web_search' || toolId === 'saved_places' || toolId === 'map_search_route' ||
      toolId === 'open_map_route') {
      return 'search_map'
    }
    if (toolId === 'read_schedule' || toolId === 'write_schedule' || toolId === 'canvas_document' ||
      toolId === 'math_chart') {
      return 'schedule_content'
    }
    if (toolId === 'pdf_to_text' || toolId === 'image_to_text' || toolId === 'vision_read_image' ||
      toolId === 'docx_to_text' || toolId === 'xlsx_to_text') {
      return 'file_recognition'
    }
    return 'intelligence_development'
  }

  private getBuiltinToolCategories(): BuiltinToolCategory[] {
    const categories: BuiltinToolCategory[] = [
      new BuiltinToolCategory('search_map', pickLocalizedText('搜索与地图', 'Search & Maps')),
      new BuiltinToolCategory('schedule_content', pickLocalizedText('日程与内容', 'Calendar & Content')),
      new BuiltinToolCategory('file_recognition', pickLocalizedText('文件与识别', 'Files & Recognition')),
      new BuiltinToolCategory('intelligence_development',
        pickLocalizedText('智能与开发', 'Intelligence & Development'))
    ]
    const tools = this.getBuiltinChatTools()
    for (let i = 0; i < tools.length; i++) {
      const categoryKey = this.resolveBuiltinCategoryKey(tools[i].id)
      for (let j = 0; j < categories.length; j++) {
        if (categories[j].key === categoryKey) {
          categories[j].tools.push(tools[i])
          break
        }
      }
    }
    const visibleCategories: BuiltinToolCategory[] = []
    for (let i = 0; i < categories.length; i++) {
      if (categories[i].tools.length > 0) {
        visibleCategories.push(categories[i])
      }
    }
    return visibleCategories
  }

  private getAllVisibleToolIds(): string[] {
    const toolIds: string[] = []
    for (let i = 0; i < this.availableChatTools.length; i++) {
      const toolId = this.availableChatTools[i].id
      if (!toolIds.includes(toolId)) {
        toolIds.push(toolId)
      }
    }
    return toolIds
  }

  private getSelectedVisibleToolCount(): number {
    const toolIds = this.getAllVisibleToolIds()
    let count = 0
    for (let i = 0; i < toolIds.length; i++) {
      if (this.selectedToolIds.includes(toolIds[i])) {
        count += 1
      }
    }
    return count
  }

  private areAllVisibleToolsSelected(): boolean {
    const toolIds = this.getAllVisibleToolIds()
    return toolIds.length > 0 && this.getSelectedVisibleToolCount() === toolIds.length
  }

  private getMcpToolGroups(): McpToolGroup[] {
    const groups: McpToolGroup[] = []
    const groupIndexes: Map<string, number> = new Map()
    for (let i = 0; i < this.availableChatTools.length; i++) {
      const tool = this.availableChatTools[i]
      if (tool.id === 'knowledge_search' || !this.isMcpChatTool(tool)) {
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

  private hasVisibleChatTools(): boolean {
    return this.getBuiltinChatTools().length > 0 || this.getMcpToolGroups().length > 0
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

  private getCardBorderColor(): ResourceColor {
    return $r('app.color.divider')
  }

  private getBuiltinDescription(tool: ToolConfig): string {
    return getLocalizedBuiltinToolDescription(tool.id, tool.description)
  }

  private getToolSymbolResource(toolId: string): Resource {
    return resolveToolSymbolResource(toolId)
  }

  @Builder
  private ToolIcon(toolId: string, size: number) {
    if (toolId === 'docx_to_text') {
      Image($r('app.media.doc_docx'))
        .width(size)
        .height(size)
        .fillColor(this.themePrimary)
    } else if (toolId === 'xlsx_to_text') {
      Image($r('app.media.doc_xlsx'))
        .width(size)
        .height(size)
        .fillColor(this.themePrimary)
    } else {
      SymbolGlyph(this.getToolSymbolResource(toolId))
        .fontSize(size)
        .fontColor([this.themePrimary])
    }
  }

  @Builder
  private BuiltinToolListRow(tool: ToolConfig) {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        this.ToolIcon(tool.id, 17)
      }
      .width(40)
      .height(40)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        materialColor: Color.Transparent,
        applyShadow: false,
        interactive: true,
        lightEffect: { color: undefined }
      }))
      .onClick(() => {
        this.onToggleTool(tool.id, !this.isToolSelected(tool.id))
      })

      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(getLocalizedBuiltinToolName(tool.id, tool.name))
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
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.isToolSelected(tool.id) })
        .selectedColor(this.themePrimary)
        .systemMaterial(new uiMaterial.Material())
        .switchPointColor(Color.White)
        .onChange((value: boolean) => {
          this.onToggleTool(tool.id, value)
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      ImmersiveSheetHeader({
        title: pickLocalizedText('选择工具', 'Choose Tools'),
        trailingSymbol: $r('sys.symbol.arrow_clockwise'),
        showTrailing: true,
        trailingButtonEnabled: !this.isRefreshingMcpToolAvailability,
        trailingLoading: this.isRefreshingMcpToolAvailability,
        leadingColor: this.themePrimary,
        trailingColor: this.themePrimary,
        onLeadingClick: (): void => {
          this.onClose()
        },
        onTrailingClick: (): void => {
          this.onRefresh()
        }
      })

      Scroll() {
        Column({ space: 18 }) {
          if (!this.hasVisibleChatTools()) {
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
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text(pickLocalizedText('全部工具', 'All Tools'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))

                Text(pickLocalizedText(
                  `已开启 ${this.getSelectedVisibleToolCount()} / ${this.getAllVisibleToolIds().length}`,
                  `${this.getSelectedVisibleToolCount()} / ${this.getAllVisibleToolIds().length} enabled`
                ))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Button(pickLocalizedText('全部关闭', 'Disable All'))
                .height(34)
                .padding({ left: 12, right: 12 })
                .type(ButtonType.Capsule)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor(Color.Transparent)
                .enabled(this.getSelectedVisibleToolCount() > 0)
                .opacity(this.getSelectedVisibleToolCount() > 0 ? 1 : 0.45)
                .systemMaterial(new uiMaterial.ImmersiveMaterial({
                  style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
                  materialColor: Color.Transparent,
                  applyShadow: false,
                  interactive: true,
                  lightEffect: { color: undefined }
                }))
                .onClick(() => {
                  this.onToggleAll(this.getAllVisibleToolIds(), false)
                })

              Button(pickLocalizedText('全部开启', 'Enable All'))
                .height(34)
                .padding({ left: 12, right: 12 })
                .type(ButtonType.Capsule)
                .fontSize(11)
                .fontColor(this.themePrimary)
                .backgroundColor(Color.Transparent)
                .enabled(!this.areAllVisibleToolsSelected())
                .opacity(!this.areAllVisibleToolsSelected() ? 1 : 0.45)
                .systemMaterial(new uiMaterial.ImmersiveMaterial({
                  style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
                  materialColor: Color.Transparent,
                  applyShadow: false,
                  interactive: true,
                  lightEffect: { color: undefined }
                }))
                .onClick(() => {
                  this.onToggleAll(this.getAllVisibleToolIds(), true)
                })
            }
            .width('100%')
            .padding(12)
            .borderRadius(18)
            .backgroundColor(Color.Transparent)
            .systemMaterial(new uiMaterial.ImmersiveMaterial({
              style: uiMaterial.ImmersiveStyle.REGULAR,
              materialColor: Color.Transparent,
              applyShadow: false,
              interactive: false,
              lightEffect: { color: undefined }
            }))
            .alignItems(VerticalAlign.Center)

            if (this.getBuiltinChatTools().length > 0) {
              Column({ space: 16 }) {
                ForEach(this.getBuiltinToolCategories(), (category: BuiltinToolCategory) => {
                  Column({ space: 8 }) {
                    Row({ space: 6 }) {
                      Text(category.title)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                        .layoutWeight(1)

                      Text(`${category.tools.length}`)
                        .fontSize(11)
                        .fontColor($r('app.color.text_tertiary'))
                    }
                    .width('100%')
                    .padding({ left: 4, right: 4 })

                    Column() {
                      ForEach(category.tools, (tool: ToolConfig, index: number) => {
                        this.BuiltinToolListRow(tool)
                        if (index < category.tools.length - 1) {
                          Divider()
                            .strokeWidth(0.5)
                            .color($r('app.color.divider'))
                            .margin({ left: 64, right: 12 })
                        }
                      }, (tool: ToolConfig) => tool.id)
                    }
                    .width('100%')
                    .borderRadius(18)
                    .backgroundColor(Color.Transparent)
                    .border({ width: 0.8, color: this.getCardBorderColor() })
                    .systemMaterial(new uiMaterial.ImmersiveMaterial({
                      style: uiMaterial.ImmersiveStyle.REGULAR,
                      materialColor: Color.Transparent,
                      applyShadow: false,
                      interactive: false,
                      lightEffect: { color: undefined }
                    }))
                  }
                  .width('100%')
                }, (category: BuiltinToolCategory) => category.key)
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
                    Button({ type: ButtonType.Circle, stateEffect: false }) {
                      SymbolGlyph($r('sys.symbol.link'))
                        .fontSize(19)
                        .fontColor([this.themePrimary])
                    }
                    .width(40)
                    .height(40)
                    .padding(0)
                    .backgroundColor(Color.Transparent)
                    .systemMaterial(new uiMaterial.ImmersiveMaterial({
                      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
                      materialColor: Color.Transparent,
                      applyShadow: false,
                      interactive: true,
                      lightEffect: { color: undefined }
                    }))
                    .onClick(() => {
                      this.onToggleMcpGroup(group.toolIds, !this.isMcpToolGroupSelected(group))
                    })

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
                  .backgroundColor(Color.Transparent)
                  .border({
                    width: 0.8,
                    color: this.getCardBorderColor()
                  })
                  .systemMaterial(new uiMaterial.ImmersiveMaterial({
                    style: uiMaterial.ImmersiveStyle.REGULAR,
                    materialColor: Color.Transparent,
                    applyShadow: false,
                    interactive: true,
                    lightEffect: { color: undefined }
                  }))
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
