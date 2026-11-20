import { MDBaseController } from '../controller/BaseController';
import { CodeBlockNode } from '../model/TreeNode';
import { CodeSourceBlockRender } from './CodeSourceBlockRender';
import { HtmlRender } from './HtmlRender';
import { MermaidRender } from './MermaidRender';
import { RichBlockSurface } from './RichBlockSurface';

@Component
export struct CodeRender {
  @Consume markdownUnion: string
  @Consume selectionUnion: string
  @Prop base: CodeBlockNode | undefined = undefined

  // 当前 fenced code 未闭合时抑制预览: Mermaid/HTML 先展示源码, 收到闭合 ``` 后再切预览。
  private isPreviewSuppressed(): boolean {
    return this.base?.closed === false
  }

  private isMermaidCodeBlock(): boolean {
    return MDBaseController.getMarkdownController(this.markdownUnion).getMermaidEnable() &&
      (this.base?.lang || "").trim().toLowerCase() == "mermaid"
  }

  private isHtmlCodeBlock(): boolean {
    const lang = (this.base?.lang || "").trim().toLowerCase()
    return MDBaseController.getMarkdownController(this.markdownUnion).getHtmlPreviewEnable() &&
      (lang == "html" || lang == "htm")
  }

  private isActionAreaVisible(): boolean {
    const lang = (this.base?.lang || "").trim().toLowerCase()
    if (lang == "html" || lang == "htm" || lang == "mermaid") {
      return true
    }
    return MDBaseController.getMarkdownController(this.markdownUnion).getCodeBlockActionAreaVisible()
  }

  private codeSelectionUnion(): string {
    const controller = MDBaseController.getMarkdownController(this.markdownUnion)
    return controller.getTextSelectionEnable() && controller.getTextSelectionActionItems().length > 0 ? this.selectionUnion : ''
  }

  @Builder
  private CodeContent() {
    if (this.isMermaidCodeBlock()) {
      MermaidRender({ base: this.base, streamingActive: this.isPreviewSuppressed() })
    } else if (this.isHtmlCodeBlock()) {
      HtmlRender({ base: this.base, streamingActive: this.isPreviewSuppressed() })
    } else {
      CodeSourceBlockRender({
        markdownUnion: this.markdownUnion,
        lang: this.base?.lang || "code",
        text: this.base?.text || "",
        autoCollapse: this.base?.closed !== false,
        selectionUnion: this.codeSelectionUnion(),
        lineNumberWidth: 34,
        contentBottomPadding: 12,
        actionAreaVisible: this.isActionAreaVisible()
      })
    }
  }

  build() {
    if (MDBaseController.getMarkdownController(this.markdownUnion).richBlockBackdrop) {
      RichBlockSurface({ inset: 3 }) {
        this.CodeContent()
      }
    } else {
      this.CodeContent()
    }
  }
}
