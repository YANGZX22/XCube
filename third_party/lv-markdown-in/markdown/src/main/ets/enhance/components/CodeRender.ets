import { MDBaseController } from '../controller/BaseController';
import { CodeBlockNode } from '../model/TreeNode';
import { CodeSourceBlockRender } from './CodeSourceBlockRender';
import { HtmlRender } from './HtmlRender';
import { MermaidRender } from './MermaidRender';

@Component
export struct CodeRender {
  @Consume markdownUnion: string
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

  build() {
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
        selectable: false,
        lineNumberWidth: 34,
        contentBottomPadding: 12
      })
    }
  }
}
