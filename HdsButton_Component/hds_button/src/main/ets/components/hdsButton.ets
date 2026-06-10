import { HdsMiniBarButton } from './HdsMiniBarButton';

/**
 * @deprecated 建议使用 HdsMiniBarButton 代替
 * hdsButton 为向后兼容保留的别名组件
 */
@ComponentV2
export struct hdsButton {
  build() {
    HdsMiniBarButton()
  }
}
