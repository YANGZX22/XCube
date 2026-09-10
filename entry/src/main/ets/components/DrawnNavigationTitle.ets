import { SymbolGlyphModifier } from '@kit.ArkUI'
import { HdsNavigationMenuItemOptions, IconType } from '@kit.UIDesignKit'
import { image } from '@kit.ImageKit'
import { getAppUiState } from '../state/AppUiState'
import { PlainNavigationButtonModifier } from '../utils/DrawnNavigationSupport'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

@ComponentV2
struct DrawnNavigationTitle {
  @BuilderParam titleContent: () => void
  @Param menuItems: HdsNavigationMenuItemOptions[] = []
  @Param endPadding: number = 16

  private getMenuLabel(item: HdsNavigationMenuItemOptions): string {
    const label = item.content?.label
    if (typeof label === 'string') {
      return label
    }
    return label ? this.getUIContext().getHostContext()?.resourceManager.getStringSync(label.id) ?? '' : ''
  }

  @Builder
  private MenuIcon(icon: IconType | undefined) {
    if (icon instanceof SymbolGlyphModifier) {
      SymbolGlyph()
        .fontSize(20)
        .attributeModifier(icon)
    } else if (icon !== undefined) {
      Image(icon as ResourceStr | image.PixelMap)
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 顶部沿用 HDS 标题区域的原有渐变模糊；这里仅自绘内容和普通按钮，不叠背景。
      this.titleContent()

      if (this.menuItems.length > 0) {
        Row({ space: 4 }) {
          ForEach(this.menuItems, (item: HdsNavigationMenuItemOptions) => {
            Button({ type: ButtonType.Circle, stateEffect: false }) {
              this.MenuIcon(item.content?.icon)
            }
            .width(40)
            .height(40)
            .padding(0)
            .backgroundColor(withColorAlpha(getAppUiState().themePrimary, '12'))
            .borderRadius(20)
            .border({ width: 0.5, color: getAppUiState().isDarkMode ? '#40FFFFFF' : '#35FFFFFF' })
            .attributeModifier(new PlainNavigationButtonModifier())
            .enabled(item.content?.isEnabled ?? true)
            .accessibilityText(this.getMenuLabel(item))
            .onClick(() => {
              if (item.content?.isEnabled !== false) {
                item.content?.action?.()
              }
            })
          })
        }
        .height(56)
        .position({ x: '100%', y: 0 })
        .translate({ x: -this.endPadding - this.menuItems.length * 40 - (this.menuItems.length - 1) * 4 })
      }
    }
    .width('100%')
    .height(56)
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

@Builder
export function DrawnNavigationTitleBuilder(content: () => void, menus: HdsNavigationMenuItemOptions[],
  endPadding: number) {
  DrawnNavigationTitle({
    titleContent: content,
    menuItems: menus,
    endPadding: endPadding
  })
}
