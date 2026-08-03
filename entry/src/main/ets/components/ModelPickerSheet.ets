import { ModelInfo } from '../models/ChatModels'
import {
  ModelRowGroupPosition,
  ModelRowRadius,
  ModelPickerBuildResult,
  ModelPickerModelRow,
  buildModelPickerRows
} from '../config/ModelListProjection'
import { PickerModelGroup } from '../config/ProviderDetailShared'
import { buildModelIconRenderData, ModelIconRenderData } from '../utils/ModelIconRenderUtils'
import { getAppUiState } from '../state/AppUiState'
import { uiMaterial } from '@kit.ArkUI'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'

@ComponentV2
export struct ModelPickerSheet {
  @Param availableModels: string[] = []
  @Param existingModels: ModelInfo[] = []
  @Param providerId: string = ''
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }

  @Local searchKeywords: string = ''
  @Local selectedIds: Set<string> = new Set<string>()
  @Local showSelectedOnly: boolean = false
  @Local activeGroupFilter: number = -1

  @Event onConfirm: (selectedIds: string[]) => void = () => {}
  @Event onCancel: () => void = () => {}

  @Local private groups: PickerModelGroup[] = []
  @Local private displayedGroups: PickerModelGroup[] = []
  private existingModelIdSet: Set<string> = new Set<string>()
  private filteredModelIds: string[] = []
  private visibleModelIds: string[] = []
  private listScroller: Scroller = new Scroller()
  private iconRenderCache: Map<string, ModelIconRenderData> = new Map<string, ModelIconRenderData>()

  aboutToAppear(): void {
    this.initializeSelection()
    this.rebuildRows()
  }

  private initializeSelection(): void {
    const selected = new Set<string>()
    const existingModelIdSet = new Set<string>()
    const availableModelSet = new Set<string>(this.availableModels)
    for (let i = 0; i < this.existingModels.length; i++) {
      const modelId = this.existingModels[i].id
      existingModelIdSet.add(modelId)
      if (availableModelSet.has(modelId)) {
        selected.add(modelId)
      }
    }
    this.existingModelIdSet = existingModelIdSet
    this.selectedIds = selected
  }

  private rebuildRows(): void {
    const startAt = Date.now()
    const result: ModelPickerBuildResult = buildModelPickerRows(
      this.availableModels,
      this.selectedIds,
      this.searchKeywords,
      this.showSelectedOnly
    )
    this.groups = result.groups
    if (this.activeGroupFilter >= 0 && this.activeGroupFilter < result.groups.length) {
      const filteredGroup = result.groups[this.activeGroupFilter]
      const filteredModelIdSet = new Set<string>(filteredGroup.modelIds)
      this.visibleModelIds = result.visibleModelIds.filter((id: string) => filteredModelIdSet.has(id))
      this.displayedGroups = [filteredGroup]
    } else {
      this.visibleModelIds = result.visibleModelIds
      this.displayedGroups = result.groups
    }
    this.filteredModelIds = result.filteredModelIds
    console.info(
      'ModelPickerSheet',
      `[rebuildRows] available=${this.availableModels.length}, visible=${this.visibleModelIds.length}, groups=${this.groups.length}, filtered=${this.filteredModelIds.length}, cost=${Date.now() - startAt}ms`
    )
  }

  private toggleModel(modelId: string): void {
    const newSet = new Set<string>(this.selectedIds)
    if (newSet.has(modelId)) {
      newSet.delete(modelId)
    } else {
      newSet.add(modelId)
    }
    this.selectedIds = newSet
    this.rebuildRows()
  }

  private isSelected(modelId: string): boolean {
    return this.selectedIds.has(modelId)
  }

  private isAllSelected(): boolean {
    const scopeModelIds = this.getSelectableModelIds()
    if (scopeModelIds.length === 0) {
      return false
    }
    for (let i = 0; i < scopeModelIds.length; i++) {
      if (!this.selectedIds.has(scopeModelIds[i])) {
        return false
      }
    }
    return true
  }

  private toggleSelectAll(): void {
    const newSet = new Set<string>(this.selectedIds)
    const scopeModelIds = this.getSelectableModelIds()
    if (this.isAllSelected()) {
      for (let i = 0; i < scopeModelIds.length; i++) {
        newSet.delete(scopeModelIds[i])
      }
    } else {
      for (let i = 0; i < scopeModelIds.length; i++) {
        newSet.add(scopeModelIds[i])
      }
    }
    this.selectedIds = newSet
    this.rebuildRows()
  }

  private toggleSelectedOnly(): void {
    if (!this.showSelectedOnly && this.getSelectedCountInFiltered() === 0) {
      return
    }
    this.showSelectedOnly = !this.showSelectedOnly
    this.rebuildRows()
  }

  private getModelIconRenderData(modelId: string): ModelIconRenderData {
    const cached = this.iconRenderCache.get(modelId)
    if (cached !== undefined) {
      return cached
    }
    const renderData = buildModelIconRenderData(modelId, this.providerId, '')
    this.iconRenderCache.set(modelId, renderData)
    return renderData
  }

  private getRowIconRenderData(row: ModelPickerModelRow): ModelIconRenderData {
    return this.getModelIconRenderData(row.modelId)
  }

  private getListCachedCount(): number {
    if (this.visibleModelIds.length >= 120) {
      return 2
    }
    if (this.visibleModelIds.length >= 40) {
      return 3
    }
    return 4
  }

  private getSelectableModelIds(): string[] {
    return this.showSelectedOnly ? this.visibleModelIds : this.filteredModelIds
  }

  private getSelectedCountInFiltered(): number {
    let count = 0
    for (let i = 0; i < this.filteredModelIds.length; i++) {
      if (this.selectedIds.has(this.filteredModelIds[i])) {
        count++
      }
    }
    return count
  }

  private getCurrentResultCount(): number {
    return this.showSelectedOnly ? this.visibleModelIds.length : this.filteredModelIds.length
  }

  private getModelListMaterial(): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: undefined }
    })
  }

  private buildModelRow(group: PickerModelGroup, modelId: string, index: number): ModelPickerModelRow {
    return {
      groupName: group.name,
      modelId: modelId,
      isExisting: this.existingModelIdSet.has(modelId),
      groupPosition: this.resolveGroupPosition(index, group.modelIds.length)
    } as ModelPickerModelRow
  }

  private resolveGroupPosition(index: number, totalCount: number): ModelRowGroupPosition {
    if (totalCount <= 1) {
      return ModelRowGroupPosition.SINGLE
    }
    if (index === 0) {
      return ModelRowGroupPosition.FIRST
    }
    if (index === totalCount - 1) {
      return ModelRowGroupPosition.LAST
    }
    return ModelRowGroupPosition.MIDDLE
  }

  private buildGroupRenderKey(group: PickerModelGroup): string {
    const modeKey = this.showSelectedOnly ? 'selected' : 'all'
    return `${modeKey}::${group.name}::${group.modelIds.join('|')}`
  }

  private getGroupJumpItemIndex(groupIndex: number): number {
    let itemIndex = 0
    for (let i = 0; i < groupIndex; i++) {
      itemIndex += this.groups[i].modelIds.length
    }
    return itemIndex
  }

  private scrollToGroup(groupIndex: number): void {
    if (groupIndex < 0 || groupIndex >= this.groups.length) {
      return
    }
    this.listScroller.scrollToIndex(this.getGroupJumpItemIndex(groupIndex), true, ScrollAlign.START)
  }

  private confirmSelection(): void {
    const selected: string[] = []
    this.selectedIds.forEach((id: string) => {
      selected.push(id)
    })
    this.onConfirm(selected)
  }

  build() {
    Column() {
      this.SheetHeader()
      this.SearchBar()
      this.SelectionToolbar()
      this.GroupJumpTags()
      this.ModelList()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  SheetHeader() {
    ImmersiveSheetHeader({
      title: $r('app.string.select_models'),
      showTrailing: true,
      trailingColor: this.themePrimary,
      onLeadingClick: (): void => {
        this.onCancel()
      },
      onTrailingClick: (): void => {
        this.confirmSelection()
      }
    })
  }

  @Builder
  SearchBar() {
    Search({ value: this.searchKeywords, placeholder: $r('app.string.filter_models_placeholder') })
      .width(this.windowWidthVp >= 600 ? 360 : '82%')
      .height(40)
      .borderRadius(20)
      .backgroundColor(Color.Transparent)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        materialColor: Color.Transparent,
        applyShadow: false,
        interactive: true,
        lightEffect: { color: undefined }
      }))
      .padding({ left: 16, right: 16 })
      .onChange((value: string) => {
        this.searchKeywords = value
        this.activeGroupFilter = -1
        this.rebuildRows()
      })
  }

  @Builder
  SelectionToolbar() {
    Row({ space: 12 }) {
      Text(`已选 ${this.selectedIds.size} / ${this.availableModels.length}`)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      Blank()

      Button() {
        Row({ space: 6 }) {
          Text(this.isAllSelected()
            ? $r('app.string.model_picker_deselect_all')
            : $r('app.string.model_picker_select_filtered'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getCurrentResultCount() > 0 ? this.themePrimary : $r('app.color.text_tertiary'))

          if (!this.isAllSelected()) {
            Text(`${this.getCurrentResultCount()}`)
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
        }
      }
      .type(ButtonType.Normal)
      .stateEffect(false)
      .height(28)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .enabled(this.getCurrentResultCount() > 0)
      .opacity(this.getCurrentResultCount() > 0 ? 1 : 0.45)
      .onClick(() => {
        if (this.getCurrentResultCount() > 0) {
          this.toggleSelectAll()
        }
      })

      Button() {
        Text(this.showSelectedOnly ? $r('app.string.model_picker_show_all') : $r('app.string.model_picker_show_selected'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.showSelectedOnly ? this.themePrimary : $r('app.color.text_secondary'))
      }
      .height(32)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.showSelectedOnly ? this.themePrimaryLight : getAppUiState().themeSurface)
      .borderRadius(16)
      .enabled(this.showSelectedOnly || this.getSelectedCountInFiltered() > 0)
      .opacity(this.showSelectedOnly || this.getSelectedCountInFiltered() > 0 ? 1 : 0.45)
      .onClick(() => {
        this.toggleSelectedOnly()
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8 })
  }

  @Builder
  GroupJumpTags() {
    if (this.groups.length > 1) {
      Row() {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.groups, (group: PickerModelGroup, index: number) => {
              Button() {
                Text(group.name)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.activeGroupFilter === index
                    ? Color.White
                    : $r('app.color.text_secondary'))
              }
              .type(ButtonType.Normal)
              .stateEffect(false)
              .height(32)
              .padding({ left: 12, right: 12 })
              .backgroundColor(this.activeGroupFilter === index
                ? this.themePrimary
                : getAppUiState().themeSurface)
              .borderRadius(16)
              .onClick(() => {
                this.activeGroupFilter = this.activeGroupFilter === index ? -1 : index
                this.rebuildRows()
              })
            }, (group: PickerModelGroup) => `jump::${group.name}`)
          }
          .padding({ left: 16, right: 16, top: 4, bottom: 4 })
        }
        .width('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.Start)
      }
      .width('100%')
      .height(40)
      .backgroundColor(Color.Transparent)
      .zIndex(1)
    }
  }

  @Builder
  GroupHeader(group: PickerModelGroup) {
    Row({ space: 4 }) {
      Text(group.name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))

      Text(`(${group.modelIds.length})`)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 1 })
    }
    .width('100%')
    .height(36)
    .padding({ left: 16, right: 16, top: 4 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ModelList() {
    if (this.displayedGroups.length === 0) {
      this.EmptyState()
    } else {
      List({ scroller: this.listScroller }) {
        ListItemGroup({ space: 0 }) {
          ForEach(this.displayedGroups, (group: PickerModelGroup) => {
            ListItem() {
              this.GroupHeader(group)
            }

            ForEach(group.modelIds, (modelId: string, index: number) => {
              ListItem() {
                this.ModelRow(this.buildModelRow(group, modelId, index))
              }
            }, (modelId: string) => `${group.name}::${modelId}`)
          }, (group: PickerModelGroup) => this.buildGroupRenderKey(group))
        }
        .divider(null)
        .margin({ left: 16, right: 16, bottom: 40 })
        .backgroundColor(Color.Transparent)
        .borderRadius(16)
        .border({ width: 1, color: this.themePrimaryLight })
        .systemMaterial(this.getModelListMaterial())
      }
      .sticky(StickyStyle.None)
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(this.getListCachedCount())
    }
  }

  @Builder
  ModelRow(row: ModelPickerModelRow) {
    Column() {
      Row() {
        Checkbox()
          .select(this.isSelected(row.modelId))
          .selectedColor(this.themePrimary)
          .hitTestBehavior(HitTestMode.None)

        Column() {
          if (this.getRowIconRenderData(row).hasIcon()) {
            if (this.getRowIconRenderData(row).isRawfile()) {
              Image($rawfile(this.getRowIconRenderData(row).resourcePath))
                .width(20)
                .height(20)
                .objectFit(ImageFit.Contain)
            } else {
              Image(this.getRowIconRenderData(row).resourcePath)
                .width(20)
                .height(20)
                .objectFit(ImageFit.Contain)
            }
          } else {
            SymbolGlyph($r('sys.symbol.ai_edit'))
              .fontSize(16)
              .fontColor([$r('app.color.text_tertiary')])
          }
        }
        .width(32)
        .height(32)
        .borderRadius(8)
        .backgroundColor($r('app.color.model_icon_bg'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .margin({ left: 12 })

        Column() {
          Text(row.modelId)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 10 })
      }
      .width('100%')
      .constraintSize({ minHeight: 56 })
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor(this.isSelected(row.modelId)
        ? withColorAlpha(this.themePrimaryLight, '80')
        : Color.Transparent)
      .borderRadius(this.buildRowRadius(row.groupPosition))
      .onClick(() => {
        this.toggleModel(row.modelId)
      })

      if (this.shouldShowDivider(row.groupPosition)) {
        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 54, right: 12 })
      }
    }
  }

  @Builder
  EmptyState() {
    Column() {
      SymbolGlyph(this.showSelectedOnly ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.magnifyingglass'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])

      Text(this.showSelectedOnly
        ? $r('app.string.model_picker_selected_only_empty')
        : (this.availableModels.length === 0 ? $r('app.string.provider_no_models') : $r('app.string.provider_models_not_found')))
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 16 })

      Text(this.showSelectedOnly
        ? $r('app.string.model_picker_selected_only_empty_hint')
        : (this.availableModels.length === 0 ? $r('app.string.provider_no_models_hint') : $r('app.string.try_different_keyword')))
        .fontSize(14)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 4 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  private buildRowRadius(groupPosition: ModelRowGroupPosition): ModelRowRadius {
    if (groupPosition === ModelRowGroupPosition.SINGLE) {
      return { topLeft: 16, topRight: 16, bottomLeft: 16, bottomRight: 16 }
    }
    if (groupPosition === ModelRowGroupPosition.FIRST) {
      return { topLeft: 16, topRight: 16, bottomLeft: 0, bottomRight: 0 }
    }
    if (groupPosition === ModelRowGroupPosition.LAST) {
      return { topLeft: 0, topRight: 0, bottomLeft: 16, bottomRight: 16 }
    }
    return { topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0 }
  }

  private shouldShowDivider(groupPosition: ModelRowGroupPosition): boolean {
    return groupPosition === ModelRowGroupPosition.FIRST || groupPosition === ModelRowGroupPosition.MIDDLE
  }
}
