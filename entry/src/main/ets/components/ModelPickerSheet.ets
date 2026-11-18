import { getSettingsTypography, SETTINGS_SUBTITLE_LINE_HEIGHT } from './settings/SettingsTypography'
import { ModelFilterSearchField } from './ModelFilterSearchField'
import { ModelListMaterialHost } from './ModelListMaterialHost'
import { ModelInfo } from '../models/ChatModels'
import {
  ModelRowGroupPosition,
  ModelRowRadius,
  ModelPickerBuildResult,
  buildModelPickerRows,
  resolveGroupPosition
} from '../config/ModelListProjection'
import { PickerModelGroup } from '../config/ProviderDetailShared'
import { buildModelIconRenderData, ModelIconRenderData } from '../utils/ModelIconRenderUtils'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'

interface PickerHeaderParams {
  group: PickerModelGroup
}

interface PickerRowParams {
  modelId: string
  groupPosition: ModelRowGroupPosition
}

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

  @Local searchKeywords: string = ''
  @Local selectedIds: Set<string> = new Set<string>()
  @Local showSelectedOnly: boolean = false
  @Local activeGroupName: string = ''

  @Event onConfirm: (selectedIds: string[]) => void = () => {}
  @Event onCancel: () => void = () => {}

  @Local private groups: PickerModelGroup[] = []
  @Local private filteredModelIds: string[] = []
  @Local private visibleModelIds: string[] = []
  private iconRenderCache: Map<string, ModelIconRenderData> = new Map<string, ModelIconRenderData>()

  @Computed
  private get activeGroup(): PickerModelGroup | undefined {
    return this.groups.find((group: PickerModelGroup) => group.name === this.activeGroupName)
  }

  @Computed
  private get displayedGroups(): PickerModelGroup[] {
    return this.activeGroup === undefined ? this.groups : [this.activeGroup]
  }

  private get displayedModelIds(): string[] {
    return this.activeGroup?.modelIds ?? this.visibleModelIds
  }

  aboutToAppear(): void {
    this.initializeSelection()
    this.rebuildRows()
  }

  private initializeSelection(): void {
    const selected = new Set<string>()
    const availableModelSet = new Set<string>(this.availableModels)
    for (let i = 0; i < this.existingModels.length; i++) {
      const modelId = this.existingModels[i].id
      if (availableModelSet.has(modelId)) {
        selected.add(modelId)
      }
    }
    this.selectedIds = selected
  }

  private rebuildRows(): void {
    const result: ModelPickerBuildResult = buildModelPickerRows(
      this.availableModels,
      this.selectedIds,
      this.searchKeywords,
      this.showSelectedOnly
    )
    this.groups = result.groups
    this.filteredModelIds = result.filteredModelIds
    this.visibleModelIds = result.visibleModelIds
    if (this.activeGroupName !== '' && !result.groups.some((group: PickerModelGroup) => group.name === this.activeGroupName)) {
      this.activeGroupName = ''
    }
  }

  private toggleModel(modelId: string): void {
    const newSet = new Set<string>(this.selectedIds)
    if (newSet.has(modelId)) {
      newSet.delete(modelId)
    } else {
      newSet.add(modelId)
    }
    this.selectedIds = newSet
    if (this.showSelectedOnly) {
      this.rebuildRows()
    }
  }

  private isSelected(modelId: string): boolean {
    return this.selectedIds.has(modelId)
  }

  private isAllSelected(): boolean {
    return this.showSelectedOnly ? this.displayedModelIds.length > 0 :
      this.filteredModelIds.length > 0 && this.selectedCountInFiltered === this.filteredModelIds.length
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
    if (this.showSelectedOnly) {
      this.rebuildRows()
    }
  }

  private toggleSelectedOnly(): void {
    if (!this.showSelectedOnly && this.selectedCountInFiltered === 0) {
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

  private getListCachedCount(): number {
    if (this.displayedModelIds.length >= 120) {
      return 2
    }
    if (this.displayedModelIds.length >= 40) {
      return 3
    }
    return 4
  }

  private getSelectableModelIds(): string[] {
    return this.showSelectedOnly ? this.displayedModelIds : this.filteredModelIds
  }

  @Computed
  private get selectedCountInFiltered(): number {
    let count = 0
    const filtered = this.filteredModelIds
    const selected = this.selectedIds
    for (let i = 0; i < filtered.length; i++) {
      if (selected.has(filtered[i])) {
        count++
      }
    }
    return count
  }

  private getCurrentResultCount(): number {
    return this.showSelectedOnly ? this.displayedModelIds.length : this.filteredModelIds.length
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
      ModelListMaterialHost({ useMaterial: this.displayedGroups.length > 0 }) {
        this.ModelList()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  SheetHeader() {
    ImmersiveSheetHeader({
      titleFont: getSettingsTypography().pageTitle,
      titleColor: getAppUiState().themeTextPrimary,
      title: $r('app.string.select_models'),
      materialFeedback: false,
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
    ModelFilterSearchField({
      value: this.searchKeywords,
      onChange: (value: string): void => {
        this.searchKeywords = value
        this.activeGroupName = ''
        this.rebuildRows()
      }
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
      .enabled(this.showSelectedOnly || this.selectedCountInFiltered > 0)
      .opacity(this.showSelectedOnly || this.selectedCountInFiltered > 0 ? 1 : 0.45)
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
            ForEach(this.groups, (group: PickerModelGroup) => {
              Button() {
                Text(group.name)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.activeGroupName === group.name
                    ? Color.White
                    : $r('app.color.text_secondary'))
              }
              .type(ButtonType.Normal)
              .stateEffect(false)
              .height(32)
              .padding({ left: 12, right: 12 })
              .backgroundColor(this.activeGroupName === group.name
                ? this.themePrimary
                : getAppUiState().themeSurface)
              .borderRadius(16)
              .onClick(() => {
                this.activeGroupName = this.activeGroupName === group.name ? '' : group.name
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
  GroupHeader($$: PickerHeaderParams) {
    Row({ space: 4 }) {
      Text($$.group.name)
        .font(getSettingsTypography().sectionTitle)
        .fontColor(getAppUiState().themeTextPrimary)

      Text(`(${$$.group.modelIds.length})`)
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
      List() {
        Repeat<PickerModelGroup>(this.displayedGroups)
          .each((group: RepeatItem<PickerModelGroup>) => {
            ListItemGroup({ header: this.GroupHeader({ group: group.item }) }) {
              Repeat<string>(group.item.modelIds)
                .each((model: RepeatItem<string>) => {
                  ListItem() {
                    this.ModelRow({
                      modelId: model.item,
                      groupPosition: resolveGroupPosition(model.index, group.item.modelIds.length)
                    })
                  }
                })
                .key((modelId: string) => modelId)
                .virtualScroll()
            }
            .divider(null)
          })
          .key((group: PickerModelGroup) => group.name)
          .virtualScroll()
        ListItem() {
          Column().height(40)
        }
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
  ModelRow($$: PickerRowParams) {
    Column() {
      Row() {
        Checkbox()
          .select(this.isSelected($$.modelId))
          .selectedColor(this.themePrimary)
          .hitTestBehavior(HitTestMode.None)

        Column() {
          if (this.getModelIconRenderData($$.modelId).hasIcon()) {
            if (this.getModelIconRenderData($$.modelId).isRawfile()) {
              Image($rawfile(this.getModelIconRenderData($$.modelId).resourcePath))
                .width(20)
                .height(20)
                .objectFit(ImageFit.Contain)
            } else {
              Image(this.getModelIconRenderData($$.modelId).resourcePath)
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
          Text($$.modelId)
            .font(getSettingsTypography().itemTitle)
            .fontColor(getAppUiState().themeTextPrimary)
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
      .backgroundColor(this.isSelected($$.modelId)
        ? withColorAlpha(this.themePrimaryLight, '80')
        : Color.Transparent)
      .borderRadius(this.buildRowRadius($$.groupPosition))
      .onClick(() => {
        this.toggleModel($$.modelId)
      })

      if (this.shouldShowDivider($$.groupPosition)) {
        Divider()
          .color(getAppUiState().themePrimaryLight)
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
        .font(getSettingsTypography().itemTitle)
        .width('100%')
        .textAlign(TextAlign.Start)
        .fontColor(getAppUiState().themeTextPrimary)
        .margin({ top: 16 })

      Text(this.showSelectedOnly
        ? $r('app.string.model_picker_selected_only_empty_hint')
        : (this.availableModels.length === 0 ? $r('app.string.provider_no_models_hint') : $r('app.string.try_different_keyword')))
        .font(getSettingsTypography().subtitle)
        .width('100%')
        .textAlign(TextAlign.Start)
        .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
        .fontColor(getAppUiState().themeTextSecondary)
        .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
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
