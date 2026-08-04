import { MDBaseController } from '../controller/BaseController';
import { WebDialogController } from '../controller/WebDialogController';
import { BaseNode, FootnoteRefNode, InlineHtmlFontNode, LinkNode, TextNode, TreeNode } from '../model/TreeNode';
import { componentUtils } from '@kit.ArkUI';
import { Logger } from '../utils/Logger';

const TAG = "TextImpl"

export namespace TextImpl {
  export function handleFontColor(markdownUnion: string, data: ESObject, base?: TreeNode | undefined): ResourceColor {
    if (data?.type == "inlineHtmlFont" && typeof data?.color === 'string' && data.color.length > 0) {
      return data.color
    }
    // 行内代码
    if ((data as TreeNode)?.type == "inlineCode") {
      return MDBaseController.getMarkdownController(markdownUnion).getInlineCodeColor()
    }
    // 超链接
    if ((data as TreeNode)?.type == "link") {
      return MDBaseController.getMarkdownController(markdownUnion).getHyperlinkTextColor()
    }
    // 标题
    if (base?.type == "heading") {
      let titleColor = MDBaseController.getMarkdownController(markdownUnion).getTitleColor()
      if (titleColor instanceof Array && titleColor.length == 6) {
        return titleColor[((base.level || 1) as number) - 1]
      } else {
        return titleColor
      }
    }
    // 脚注
    if ((data as TreeNode)?.type == "footnoteRef") {
      return MDBaseController.getMarkdownController(markdownUnion).getFootnoteTextColor()
    }
    // 表格-表头文本样式
    if ((data as TreeNode)?.extend?.get("tableCell") == true) {
      return MDBaseController.getMarkdownController(markdownUnion).getTableTitleTextColor()
    }
    // 表格-表体文本样式
    if ((data as TreeNode)?.extend?.get("tableRow") == true) {
      if ((data as TreeNode)?.extend?.get("interleaveText") == true) {
        return MDBaseController.getMarkdownController(markdownUnion).getTableInterleaveTextColor()
      } else {
        return MDBaseController.getMarkdownController(markdownUnion).getTableNormalTextColor()
      }
    }

    // 引用块
    if ((data as TreeNode)?.extend?.get("blockquote") == true || base?.extend?.get("blockquote") == true) {
      return MDBaseController.getMarkdownController(markdownUnion).getQuoteTextColor()
    }

    // 默认颜色
    return MDBaseController.getMarkdownController(markdownUnion).getTextColor()
  }

  export function handleBackgroundColor(markdownUnion: string, data: ESObject) {
    // 行内代码背景色
    if ((data as TreeNode)?.type == "inlineCode") {
      return MDBaseController.getMarkdownController(markdownUnion).getInlineCodeBackgroundColor()
    }
    if ((data as TreeNode)?.type == "link") {
      return MDBaseController.getMarkdownController(markdownUnion).getHyperlinkBackgroundColor()
    }
    // 默认背景颜色
    return null
  }

  export function handleBackgroundRadius(markdownUnion: string, data: ESObject) {
    let radius: Dimension = 5
    // 行内代码背景色
    if ((data as TreeNode)?.type == "inlineCode") {
      radius = MDBaseController.getMarkdownController(markdownUnion).getInlineCodeBackgroundRadius()
    }
    if ((data as TreeNode)?.type == "link") {
      radius = MDBaseController.getMarkdownController(markdownUnion).getHyperlinkBackgroundRadius()
    }
    // 默认背景颜色
    return radius
  }

  export function handleDecoration(markdownUnion: string, data: ESObject): DecorationStyleInterface {
    // 删除线
    if ((data as TreeNode)?.type == "strikethrough") {
      return {
        type: TextDecorationType.LineThrough,
        color: MDBaseController.getMarkdownController(markdownUnion).getTextColor()
      }
    }
    // 下划线
    if ((data as TreeNode)?.type == "link") {
      if (MDBaseController.getMarkdownController(markdownUnion).getHyperlinkUnderlineState()) {
        return {
          type: TextDecorationType.Underline,
          color: MDBaseController.getMarkdownController(markdownUnion).getHyperlinkTextColor(),
          style: TextDecorationStyle.SOLID
        }
      } else {
        return { type: TextDecorationType.None }
      }
    }
    // 默认背景颜色
    return { type: TextDecorationType.None }
  }

  export function handleText(markdownUnion: string, data: TreeNode | TextNode | FootnoteRefNode | LinkNode) {
    // 行内代码增加左右空格，美观
    if (data?.type == "inlineCode") {
      return ` ${data?.text} `
    }
    // 超链接增加左右空格，美观
    if (data?.type == "link" &&
      MDBaseController.getMarkdownController(markdownUnion).getHyperlinkBackgroundColor() != Color.Transparent) {
      return ` ${data?.text} `
    }
    // 脚注
    if (data?.type == "footnoteRef") {
      return `[${data.id}]`
    }
    return (data as TextNode)?.text?.replace("<br>", "\n") || ""
  }

  export function handleFontWeight(markdownUnion: string, data: ESObject,
    base?: TreeNode | undefined): FontWeight | null {
    if (base?.type == "heading" || base?.type == "bolditalic") {
      let fontWeight = MDBaseController.getMarkdownController(markdownUnion).getTitleFontWeight()
      if (fontWeight instanceof Array && fontWeight.length == 6 && base?.type == "heading") {
        return fontWeight[((base?.level || 1) as number) - 1]
      } else {
        return fontWeight as FontWeight
      }
    }
    if (data?.type == "bold" || data?.type == "heading") {
      return FontWeight.Bold
    }
    return null
  }

  export function handleFontStyle(markdownUnion: string, data: ESObject, base?: TreeNode | undefined): FontStyle {
    if (base?.type == "heading") {
      let fontStyle = MDBaseController.getMarkdownController(markdownUnion).getTitleFontStyle()
      if (fontStyle instanceof Array && fontStyle.length == 6) {
        return fontStyle[((base?.level || 1) as number) - 1]
      } else {
        return fontStyle as FontStyle
      }
    }
    if (base?.type == "bolditalic") {
      return FontStyle.Italic
    }
    return data?.type == "italic" ? FontStyle.Italic : FontStyle.Normal
  }

  export function handleLineHeight(markdownUnion: string, base?: TreeNode): ResourceStr | number {
    let r: ResourceStr | number = MDBaseController.getMarkdownController(markdownUnion).getTextLineHeight()
    if (base?.type == "heading") {
      switch (base?.level) {
        case 1:
          r = MDBaseController.getMarkdownController(markdownUnion).getTitleLineHeight()[0]
          break;
        case 2:
          r = MDBaseController.getMarkdownController(markdownUnion).getTitleLineHeight()[1]
          break;
        case 3:
          r = MDBaseController.getMarkdownController(markdownUnion).getTitleLineHeight()[2]
          break;
        case 4:
          r = MDBaseController.getMarkdownController(markdownUnion).getTitleLineHeight()[3]
          break;
        case 5:
          r = MDBaseController.getMarkdownController(markdownUnion).getTitleLineHeight()[4]
          break;
        case 6:
          r = MDBaseController.getMarkdownController(markdownUnion).getTitleLineHeight()[5]
          break;
      }
    }
    return r
  }

  export function handleFontSize(markdownUnion: string, data?: BaseNode | undefined, base?: TreeNode | undefined) {
    let r: ResourceStr | number = MDBaseController.getMarkdownController(markdownUnion).getTextSize()
    const inlineFontSize = (data as InlineHtmlFontNode | undefined)?.size
    if (data?.type == "inlineHtmlFont" && typeof inlineFontSize === 'number' && inlineFontSize > 0) {
      return inlineFontSize
    }
    // 脚注
    if (data?.type == "footnoteRef") {
      return 13
    }
    if (data?.type == "link") {
      let linkSize = MDBaseController.getMarkdownController(markdownUnion).getHyperlinkTextSize()
      if (linkSize) {
        return linkSize
      }
    }
    if (base?.type == "heading") {
      switch (base.level) {
        case 1:
          r = MDBaseController.getMarkdownController(markdownUnion).getTitleSize()[0]
          break;
        case 2:
          r = MDBaseController.getMarkdownController(markdownUnion).getTitleSize()[1]
          break;
        case 3:
          r = MDBaseController.getMarkdownController(markdownUnion).getTitleSize()[2]
          break;
        case 4:
          r = MDBaseController.getMarkdownController(markdownUnion).getTitleSize()[3]
          break;
        case 5:
          r = MDBaseController.getMarkdownController(markdownUnion).getTitleSize()[4]
          break;
        case 6:
          r = MDBaseController.getMarkdownController(markdownUnion).getTitleSize()[5]
          break;
      }
    }
    return r
  }

  export function handleFontFamily(markdownUnion: string, data?: BaseNode | undefined,
    base?: TreeNode | undefined): ResourceStr {
    const inlineFontFace = (data as InlineHtmlFontNode | undefined)?.face
    if (data?.type == "inlineHtmlFont" && typeof inlineFontFace === 'string' && inlineFontFace.length > 0) {
      return inlineFontFace
    }
    // 标题
    if (base?.type == "heading") {
      let fontFamily = MDBaseController.getMarkdownController(markdownUnion).getTitleFontFamily()
      if (fontFamily instanceof Array && fontFamily.length == 6) {
        return fontFamily[((base.level || 1) as number) - 1]
      } else {
        return fontFamily
      }
    } else {
      // 默认字体族
      return MDBaseController.getMarkdownController(markdownUnion).getTextFontFamily()
    }
  }

  export function handleClick(markdownUnion: string, data: ESObject) {
    if (data && data.type == "link") {
      let title: string = data?.text || ""
      let url: string = data?.url || ""
      let h = MDBaseController.getMarkdownController(markdownUnion).getHyperlinkClickListener()
      // 判断是否是锚点
      let anchorInfo: componentUtils.ComponentInfo | undefined = undefined
      if (url.startsWith("#")) {
        // 移除原始锚点中的#，然后使用与生成锚点id相同的规则处理
        let anchorText = url.replace(/^#/, '')
        let id = "#" + generateAnchorId(anchorText)
        Logger.info(TAG, "anchor id > " + id)
        try {
          anchorInfo = componentUtils.getRectangleById(id)
          Logger.info(TAG, "anchor info > " + JSON.stringify(anchorInfo))
        } catch (error) {
        }
      }
      if (!h(title, url, anchorInfo)) {
        WebDialogController.getInstance().openBindSheet(title, url)
      }
    }
  }

  export function handleSpanId(markdownUnion: string, data: ESObject): string {
    if (data && data.type == "heading") {
      Logger.info(TAG, "handle heading SpanId data > " + JSON.stringify(data))
      if (data?.children && data?.children.length > 0) {
        let text: string = (data?.children[0]?.text) || ""
        // 处理标题文本，生成符合规则的锚点id
        let anchorId = generateAnchorId(text)
        return "#" + anchorId
      }
    }
    return ""
  }

  function generateAnchorId(text: string): string {
    // 1. 空格转换为短横线
    // 2. 英文字母转为小写
    // 3. 中文保留原样
    // 4. 特殊字符移除（保留数字和字母）
    let result = text
      .toLowerCase() // 转为小写
      .replace(/\s+/g, '-') // 空格转短横线
      .replace(/[^a-z0-9\u4e00-\u9fa5-]/g, '') // 移除特殊字符，保留中文、数字、字母和短横线
    return result
  }

  export function handleCopyOption(markdownUnion: string): CopyOptions {
    return MDBaseController.getMarkdownController(markdownUnion).getCopyOption()
  }
}
