import { LatexImpl } from '../impl/LatexImpl';
import { TextNode } from '../model/TreeNode';
import { LatexInfo, LatexUtil } from '../utils/LatextUtil';

export function getLatexText(data: ESObject): string {
  if (typeof data?.text === 'string' && data.text.length > 0) {
    return data.text
  }
  let text = ''
  if (data?.children && data.children.length > 0) {
    for (let i = 0; i < data.children.length; i++) {
      const child = data.children[i] as TextNode
      if (typeof child?.text === 'string') {
        text += child.text
      }
    }
  }
  return text
}

export function preloadLatexImage(markdownUnion: string, latexText: string, ctx: UIContext): Promise<void> {
  if (!latexText) {
    return Promise.resolve()
  }
  return LatexUtil.latexToPixelMap(latexText, LatexImpl.handleLatexMathTextSize(markdownUnion),
    LatexImpl.handleLatexMathTextColor(markdownUnion), ctx).then(() => {
    })
}

export function getCachedLatexImage(markdownUnion: string, latexText: string): LatexInfo | undefined {
  return LatexUtil.getCachedLatex(latexText, LatexImpl.handleLatexMathTextSize(markdownUnion),
    LatexImpl.handleLatexMathTextColor(markdownUnion))
}

@Builder
export function LatexBlockSpanBuilder(markdownUnion: string, latexText: string, image: LatexInfo, ctx: UIContext) {
  ContainerSpan() {
    Span("\n")
      .height(1)
      .lineHeight(1)
    LatexImageSpanBuilder(markdownUnion, latexText, image, ctx)
  }
}

@Builder
export function LatexInlineSpanBuilder(markdownUnion: string, latexText: string, image: LatexInfo, ctx: UIContext) {
  LatexImageSpanBuilder(markdownUnion, latexText, image, ctx)
}

@Builder
export function LatexTextFallbackSpanBuilder(latexText: string) {
  Span(latexText)
}

@Builder
export function LatexImageSpanBuilder(markdownUnion: string, latexText: string, image: LatexInfo, ctx: UIContext) {
  ImageSpan(image.pixelMap)
    .objectFit(ImageFit.Contain)
    .width(ctx.px2vp(image.width))
    .height(ctx.px2vp(image.height))
    .onClick(() => {
      LatexImpl.handleClick(markdownUnion, latexText, image.pixelMap)
    })
}

@Builder
export function LatexBlockImageBuilder(markdownUnion: string, latexText: string, image: LatexInfo, ctx: UIContext) {
  Scroll() {
    Row() {
      Image(image.pixelMap)
        .objectFit(ImageFit.Contain)
        .width(ctx.px2vp(image.width))
        .height(ctx.px2vp(image.height))
        .onClick(() => {
          LatexImpl.handleClick(markdownUnion, latexText, image.pixelMap)
        })
    }
      .width(ctx.px2vp(image.width))
      .height(ctx.px2vp(image.height))
  }
  .width("100%")
  .height(ctx.px2vp(image.height))
  .scrollable(ScrollDirection.Horizontal)
  .nestedScroll({
    scrollForward: NestedScrollMode.SELF_ONLY,
    scrollBackward: NestedScrollMode.SELF_ONLY
  })
  .edgeEffect(EdgeEffect.Spring)
  .scrollBar(BarState.Off)
  .align(Alignment.Start)
}
