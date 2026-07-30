import { uiMaterial } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'

/**
 * 多选工具栏组件
 * 用于消息/会话多选模式下的批量操作
 */
@ComponentV2
export struct MultiSelectToolbar {
  @Param selectedCount: number = 0
  @Param totalCount: number = 0
  @Event onSelectAll: () => void = () => {}
  @Event onDelete: () => void = () => {}
  @Event onShare: () => void = () => {}
  @Event onCancel: () => void = () => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get destructiveButtonMaterialColor(): string {
    return this.isDarkMode ? 'rgba(255, 107, 107, 0.16)' : 'rgba(255, 107, 107, 0.12)'
  }

  private isAllSelected(): boolean {
    return this.totalCount > 0 && this.selectedCount === this.totalCount
  }

  private hasSelection(): boolean {
    return this.selectedCount > 0
  }

  private canToggleSelectAll(): boolean {
    return this.totalCount > 0
  }

  private getSelectAllLabel(): string {
    return this.isAllSelected() ? '取消全选' : '全选'
  }

  @Builder
  private ToolbarAction(symbol: Resource, label: ResourceStr, color: ResourceColor, enabled: boolean,
    destructive: boolean, onTap: () => void) {
    Column({ space: 5 }) {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        SymbolGlyph(symbol)
          .fontSize(18)
          .fontColor([enabled ? color : $r('app.color.text_tertiary')])
      }
      .width(42)
      .height(42)
      .padding(0)
      .enabled(enabled)
      .opacity(enabled ? 1 : 0.45)
      .backgroundColor(Color.Transparent)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        materialColor: destructive && enabled ? this.destructiveButtonMaterialColor : undefined,
        interactive: true,
        lightEffect: { color: undefined }
      }))
      .onClick(() => {
        onTap()
      })

      Text(label)
        .fontSize(11)
        .fontColor(enabled ? color : $r('app.color.text_tertiary'))
        .opacity(enabled ? 1 : 0.6)
    }
    .width(64)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column({ space: 8 }) {
      Text(`已选 ${this.selectedCount} 条`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      Row({ space: 12 }) {
        this.ToolbarAction(
          $r('sys.symbol.xmark'),
          $r('app.string.cancel'),
          $r('app.color.text_secondary'),
          true,
          false,
          (): void => {
            this.onCancel()
          }
        )
        this.ToolbarAction(
          this.isAllSelected() ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'),
          this.getSelectAllLabel(),
          this.themePrimary,
          this.canToggleSelectAll(),
          false,
          (): void => {
            this.onSelectAll()
          }
        )
        this.ToolbarAction(
          $r('sys.symbol.share'),
          $r('app.string.menu_share'),
          $r('app.color.text_secondary'),
          this.hasSelection(),
          false,
          (): void => {
            this.onShare()
          }
        )
        this.ToolbarAction(
          $r('sys.symbol.trash'),
          $r('app.string.delete'),
          $r('app.color.status_error'),
          this.hasSelection(),
          true,
          (): void => {
            this.onDelete()
          }
        )
      }
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(Color.Transparent)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .shadow({
      radius: 8,
      color: 'rgba(0, 0, 0, 0.08)',
      offsetX: 0,
      offsetY: -2
    })
  }
}
