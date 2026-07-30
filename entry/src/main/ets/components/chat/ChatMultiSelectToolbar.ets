import {
  createButtonTouchHandler,
  getButtonScale,
  getButtonAnimation
} from '../../utils/ButtonAnimationUtils'
import { getAppUiState } from '../../state/AppUiState'
import { uiMaterial } from '@kit.ArkUI'

@ComponentV2
export struct ChatMultiSelectToolbar {
  private static readonly ACTION_SLOT_WIDTH: number = 60

  @Param selectedCount: number = 0
  @Param totalCount: number = 0
  @Event onSelectAll: () => void = () => {}
  @Event onDelete: () => void = () => {}
  @Event onShare: () => void = () => {}
  @Event onCancel: () => void = () => {}

  @Local private cancelPressed: boolean = false
  @Local private selectAllPressed: boolean = false
  @Local private sharePressed: boolean = false
  @Local private deletePressed: boolean = false

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get panelBorderColor(): string {
    return this.isDarkMode ? 'rgba(255, 255, 255, 0.08)' : 'rgba(0, 0, 0, 0.06)'
  }

  private get panelShadowColor(): string {
    return this.isDarkMode ? 'rgba(0, 0, 0, 0.36)' : 'rgba(15, 23, 42, 0.14)'
  }

  private get destructiveButtonBackground(): string {
    return this.isDarkMode ? 'rgba(255, 107, 107, 0.16)' : 'rgba(255, 107, 107, 0.12)'
  }

  private isAllSelected(): boolean {
    return this.totalCount > 0 && this.selectedCount === this.totalCount
  }

  private canToggleSelectAll(): boolean {
    return this.totalCount > 0
  }

  private hasSelection(): boolean {
    return this.selectedCount > 0
  }

  private getSelectAllLabel(): string {
    return this.isAllSelected() ? '取消全选' : '全选'
  }

  @Builder
  private CancelAction() {
    Column({ space: 6 }) {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(42)
      .height(42)
      .backgroundColor(Color.Transparent)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true,
        lightEffect: { color: undefined }
      }))
      .scale(getButtonScale(this.cancelPressed))
      .animation(getButtonAnimation())
      .onTouch(createButtonTouchHandler((pressed: boolean): void => {
        this.cancelPressed = pressed
      }))
      .onClick(() => {
        this.onCancel()
      })

      Text($r('app.string.cancel'))
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .width(ChatMultiSelectToolbar.ACTION_SLOT_WIDTH)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private SelectAllAction() {
    Column({ space: 6 }) {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        SymbolGlyph(this.isAllSelected() ? $r('sys.symbol.minus_circle') : $r('sys.symbol.checkmark_circle'))
          .fontSize(18)
          .fontColor([this.canToggleSelectAll() ? this.themePrimary : $r('app.color.text_tertiary')])
      }
      .width(42)
      .height(42)
      .enabled(this.canToggleSelectAll())
      .opacity(this.canToggleSelectAll() ? 1 : 0.45)
      .backgroundColor(Color.Transparent)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true,
        lightEffect: { color: undefined }
      }))
      .scale(getButtonScale(this.selectAllPressed))
      .animation(getButtonAnimation())
      .onTouch(createButtonTouchHandler((pressed: boolean): void => {
        this.selectAllPressed = pressed
      }))
      .onClick(() => {
        this.onSelectAll()
      })

      Text(this.getSelectAllLabel())
        .fontSize(11)
        .fontColor(this.canToggleSelectAll() ? $r('app.color.text_secondary') : $r('app.color.text_tertiary'))
        .opacity(this.canToggleSelectAll() ? 1 : 0.6)
    }
    .width(ChatMultiSelectToolbar.ACTION_SLOT_WIDTH)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ShareAction() {
    Column({ space: 6 }) {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(18)
          .fontColor([this.hasSelection() ? $r('app.color.text_primary') : $r('app.color.text_tertiary')])
      }
      .width(42)
      .height(42)
      .enabled(this.hasSelection())
      .opacity(this.hasSelection() ? 1 : 0.45)
      .backgroundColor(Color.Transparent)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        interactive: true,
        lightEffect: { color: undefined }
      }))
      .scale(getButtonScale(this.sharePressed))
      .animation(getButtonAnimation())
      .onTouch(createButtonTouchHandler((pressed: boolean): void => {
        this.sharePressed = pressed
      }))
      .onClick(() => {
        this.onShare()
      })

      Text($r('app.string.menu_share'))
        .fontSize(11)
        .fontColor(this.hasSelection() ? $r('app.color.text_secondary') : $r('app.color.text_tertiary'))
        .opacity(this.hasSelection() ? 1 : 0.6)
    }
    .width(ChatMultiSelectToolbar.ACTION_SLOT_WIDTH)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private DeleteAction() {
    Column({ space: 6 }) {
      Button({ type: ButtonType.Circle, stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([this.hasSelection() ? $r('app.color.status_error') : $r('app.color.text_tertiary')])
      }
      .width(42)
      .height(42)
      .enabled(this.hasSelection())
      .opacity(this.hasSelection() ? 1 : 0.45)
      .backgroundColor(Color.Transparent)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        materialColor: this.hasSelection() ? this.destructiveButtonBackground : undefined,
        interactive: true,
        lightEffect: { color: undefined }
      }))
      .scale(getButtonScale(this.deletePressed))
      .animation(getButtonAnimation())
      .onTouch(createButtonTouchHandler((pressed: boolean): void => {
        this.deletePressed = pressed
      }))
      .onClick(() => {
        this.onDelete()
      })

      Text($r('app.string.delete'))
        .fontSize(11)
        .fontColor(this.hasSelection() ? $r('app.color.status_error') : $r('app.color.text_tertiary'))
        .opacity(this.hasSelection() ? 1 : 0.6)
    }
    .width(ChatMultiSelectToolbar.ACTION_SLOT_WIDTH)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column({ space: 10 }) {
      Text(`已选 ${this.selectedCount} 条`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      Row({ space: 10 }) {
        this.CancelAction()
        this.SelectAllAction()
        this.ShareAction()
        this.DeleteAction()
      }
      .alignItems(VerticalAlign.Top)
    }
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(Color.Transparent)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      interactive: true,
      lightEffect: { color: undefined }
    }))
    .borderRadius(28)
    .border({ width: 1, color: this.panelBorderColor })
    .hitTestBehavior(HitTestMode.Default)
    .onTouch((event: TouchEvent): void => {
      event.stopPropagation()
    })
    .shadow({
      radius: 20,
      color: this.panelShadowColor,
      offsetX: 0,
      offsetY: 8
    })
  }
}
