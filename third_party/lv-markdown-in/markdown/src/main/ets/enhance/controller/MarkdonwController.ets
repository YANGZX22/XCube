import { CodeTheme, markdownMermaidThemeChangeEventName } from '../constant/CodeTheme';
import { CodeBlockImpl } from '../impl/CodeBlockImpl';
import { CodeHighlight } from '../model/CodeHighlight';
import { LongPressMenuInfo, TextSelectionActionItem } from '../model/TextSelectionInfo';
import { MermaidSecurityLevel } from '../utils/MermaidHtmlBuilder';
import { generateRandomString } from '../utils/RandomString';
import { MDBaseController } from './BaseController';
import { componentUtils, promptAction } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';

/**
 * @description Markdown 组件的控制器，可以将此对象绑定至 Markdown 组件，然后通过它控制 Markdown 组件的自定义样式。同一个控制器可以控制多个 Markdown 组件，多个 API 支持链式调用语法。
 */
@ObservedV2
export class MarkdownController {
  // 随机字符串
  private union: string = ""
  // ** ================================================= 标题 ==================================================== **
  // 标题-文字颜色
  @Trace private titleColor: ResourceColor | [ResourceColor, ResourceColor, ResourceColor, ResourceColor, ResourceColor, ResourceColor] =
    "#ff1d2c39"
  // 标题-字号（1-6级）
  @Trace private titleSize: [ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number] =
    [30, 28, 24, 20, 18, 16]
  // 标题-行高（1-6级）
  @Trace private titleLineHeight: [ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number] =
    [36, 34, 30, 26, 24, 22]
  // 标题-字体粗细
  @Trace private titleFontWeight: FontWeight | [FontWeight, FontWeight, FontWeight, FontWeight, FontWeight, FontWeight] =
    FontWeight.Bold
  // 标题-字体样式
  @Trace private titleFontStyle: FontStyle | [FontStyle, FontStyle, FontStyle, FontStyle, FontStyle, FontStyle] =
    FontStyle.Normal
  // 标题-字体族（自定义字体）
  @Trace private titleFontFamily: ResourceStr | [ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr] =
    ""
  // ** ================================================= 普通文本 ==================================================== **
  // 普通文本-颜色
  @Trace private textColor: ResourceColor = "#e61f1f39"
  // 普通文本-行高
  @Trace private textLineHeight: ResourceStr | number = 24
  // 普通文本-字号
  @Trace private textSize: ResourceStr | number = 16
  // 普通文本-字体族（自定义字体）
  @Trace private textFontFamily: ResourceStr = ""
  // ** ================================================= 行内代码 ==================================================== **
  // 行内代码-颜色
  @Trace private inlineCodeColor: ResourceColor = "#F4271C"
  // 行内代码-背景颜色
  @Trace private inlineCodeBackgroundColor: ResourceColor = "#0eff0000"
  // 行内代码-背景圆角
  @Trace private inlineCodeBackgroundRadius: Dimension = 5
  // ** ================================================= 引用块 ==================================================== **
  // 引用块-文本颜色
  @Trace private quoteTextColor: ResourceColor = "#6D6D6D"
  // 引用块-左边颜色
  @Trace private quoteBorderColor: ResourceColor = "#F4271C"
  // 引用块-左边宽度
  @Trace private quoteBorderWidth: ResourceStr | number = 4
  // 引用块-背景颜色
  @Trace private quoteBackgroundColor: ResourceColor = Color.Transparent
  // 引用块-圆角
  @Trace private quoteBorderRadius: ResourceStr | number = 0
  // 引用块-内边距
  @Trace private quotePadding: Padding | Length | LocalizedPadding = {
    left: 10,
    top: 2,
    right: 10,
    bottom: 2
  }
  // ** ================================================= 代码块 ==================================================== **
  // 代码块-主题
  @Trace private codeBlockTheme: CodeTheme = "light"
  // 代码块-字体族（自定义字体）
  @Trace private codeBlockFontFamily: ResourceStr = ""
  // 代码块-字号
  @Trace private codeBlockFontSize: ResourceStr | number = 14.8
  // 代码块-行高
  @Trace private codeBlockLineHeight: ResourceStr | number = 22
  // 代码块-索引控制
  @Trace private codeBlockIdxState: boolean = false
  // 代码块-圆角
  @Trace private codeBlockBorderRadius: ResourceStr | number = 14
  // 代码块-自动折叠
  @Trace private codeBlockAutoCollapseEnable: boolean = true
  // 代码块-自动折叠阈值
  @Trace private codeBlockAutoCollapseThreshold: number = 10
  // 代码块-代码高亮
  @Trace private codeHighlight: CodeHighlight = new CodeHighlight()
  // 代码块-点击复制回调
  @Trace private codeCopyListener: (text: string) => void = (text: string) => {
    promptAction.showToast({
      message: "复制失败，请检查 setCodeCopyListener 接口实现",
    })
  }
  // ** ================================================= 图片 ==================================================== **
  // 图片-宽度
  @Trace private imageWidth: ResourceStr | number | null = "100%"
  // 图片-最大宽度
  @Trace private imageMaxWidth: ResourceStr | number | null = null
  // 图片-高度
  @Trace private imageHeight: ResourceStr | number | null = null
  // 图片-最大高度
  @Trace private imageMaxHeight: ResourceStr | number | null = null
  // 图片-圆角
  @Trace private imageBorderRadius: ResourceStr | number = 14
  // 图片-点击监听回调
  @Trace private imageClickListener: (src: string) => boolean = (src: string) => {
    return false
  }
  // 图片-加载代理
  @Trace private imageLoadProxy: (src: string) => string = (src: string) => {
    return src
  }
  // ** ================================================= 超链接 ==================================================== **
  // 超链接-文字颜色
  @Trace private hyperlinkTextColor: ResourceColor = "#0664EC"
  // 超链接-文字字号
  @Trace private hyperlinkTextSize: ResourceStr | number | null = null
  // 超链接-下划线展示状态
  @Trace private hyperlinkUnderlineState: boolean = false
  // 超链接-背景颜色
  @Trace private hyperlinkBackgroundColor: ResourceColor = Color.Transparent
  // 超链接-背景圆角
  @Trace private hyperlinkBackgroundRadius: Dimension = 5
  // 图片-点击监听回调
  @Trace private hyperlinkClickListener: (title: string, src: string,
    anchorInfo?: componentUtils.ComponentInfo) => boolean = (src: string) => {
    return false
  }
  // ** ================================================= 表格 ==================================================== **
  // 表格-背景色
  @Trace private tableBackgroundColor: ResourceColor = "#FFFFFF"
  // 表格-表头背景色
  @Trace private tableTitleBackgroundColor: ResourceColor = "#F5F7FA"
  // 表格-表头文字颜色
  @Trace private tableTitleTextColor: ResourceColor = this.textColor
  // 表格-错行文本颜色
  @Trace private tableInterleaveTextColor: ResourceColor = this.textColor
  // 表格-非错行文本颜色
  @Trace private tableNormalTextColor: ResourceColor = this.textColor
  // 表格-错行背景色
  @Trace private tableInterleaveBackgroundColor: ResourceColor = "#80f5f7fa"
  // 表格-圆角
  @Trace private tableBorderRadius: ResourceStr | number = 14
  // 表格-外边框颜色
  @Trace private tableOuterBorderColor: ResourceColor = Color.Transparent
  // 表格-外边框宽度
  @Trace private tableOuterBorderWidth: ResourceStr | number = 1
  // 表格-内边框颜色
  @Trace private tableInnerBorderColor: ResourceColor = Color.Transparent
  // 表格-内边框宽度
  @Trace private tableInnerBorderWidth: ResourceStr | number = 1
  // 表格-对齐方式
  @Trace private tableAlign: FlexAlign = FlexAlign.Start
  // ** ================================================= 任务列表 ==================================================== **
  // 任务列表-选中颜色
  @Trace private todoSelectedColor: ResourceColor = "#0A59F7"
  // 任务列表-选项大小
  @Trace private todoSelectSize: ResourceStr | number = 16
  // 无序列表-指示点大小
  @Trace private ulPointSize: ResourceStr | number = 5
  // 无序列表-指示点颜色
  @Trace private ulPointColor: ResourceColor | null = null
  // ** ================================================= 脚注 ==================================================== **
  // 脚注-文字颜色
  @Trace private footnoteTextColor: ResourceColor = "#fffa460d"
  // ** ================================================= 分割线 ==================================================== **
  // 分割线-颜色
  @Trace private lineColor: ResourceColor = "#EEE"
  // ** ================================================= 数学公式 ==================================================== **
  // 数学公式-字体大小
  @Trace private latexMathTextSize: number = 24
  // 数学公式-字体颜色（十六进制）
  @Trace private latexMathTextColor: number = 0xFF000000
  // 数学公式-点击监听回调
  @Trace private latexClickListener: (text: string, pixelMap: image.PixelMap) => boolean =
    (_text: string, _pixelMap: image.PixelMap) => {
      return false
    }
  // ** ================================================= Mermaid ==================================================== **
  // Mermaid 代码块预览开关
  @Trace private mermaidEnable: boolean = true
  // Mermaid 深浅色主题
  @Trace private mermaidTheme: CodeTheme = "light"
  // Mermaid 安全级别
  @Trace private mermaidSecurityLevel: MermaidSecurityLevel = "strict"
  // HTML 代码块预览开关
  @Trace private htmlPreviewEnable: boolean = false
  // HTML 代码块预览 JavaScript 开关
  @Trace private htmlPreviewJavaScriptEnable: boolean = false
  // Web 预览池开关
  @Trace private webPreviewPoolEnable: boolean = true
  // Web 预览池预热数量
  @Trace private webPreviewPoolInitialSize: number = 2
  // Web 预览池最大数量
  @Trace private webPreviewPoolMaxSize: number = 4
  // Web 预览池空闲保留数量
  @Trace private webPreviewPoolIdleRetain: number = 2
  // ** ================================================= 语法兼容 ==================================================== **
  // Setext 标题解析
  @Trace private setextHeadingEnable: boolean = false
  // ** ================================================= 线程模式 ==================================================== **
  // 设置是否开启线程加载模式
  @Trace private threadRenderEnable: boolean = true
  // ** ================================================= 懒渲染 ==================================================== **
  // 设置是否开启可见区域懒渲染
  @Trace private lazyRender: boolean = false
  // 设置懒渲染预渲染块数量
  @Trace private lazyPreloadBlockCount: number = 3
  // ** ================================================= 剪贴板复制范围选项 ==================================================== **
  // 设置剪贴板复制范围选项
  @Trace private copyOption: CopyOptions = CopyOptions.None
  // 跨 Text 选区开关
  @Trace private textSelectionEnable: boolean = false
  // 跨 Text 选区复制监听
  @Trace private textSelectionCopyListener: (text: string) => void = (_text: string) => {
    promptAction.showToast({
      message: "复制失败，请检查 setTextSelectionCopyListener 接口实现",
    })
  }
  // 文本选区操作栏自定义按钮。为空时使用默认「复制 / 全选 / 取消」。
  @Trace private textSelectionActionItems: TextSelectionActionItem[] = []
  // 长按菜单模式开关(默认关闭, 非破坏性): 开启后触屏长按改为先弹蒙层菜单(复制/选取文本), 而非立即选区
  @Trace private longPressMenuEnable: boolean = false
  // 长按菜单事件回调(消费端实现蒙层对话框 UI)
  @Trace private longPressMenuListener: (info: LongPressMenuInfo) => void = (_info: LongPressMenuInfo) => {
    promptAction.showToast({
      message: "请通过 setLongPressMenuListener 设置长按菜单回调",
    })
  }
  // ** ================================================= 块级元素间距 ==================================================== **
  // 块级元素间距
  @Trace private blockSpacing: number | ResourceStr = 10

  // function list

  constructor() {
    this.union = generateRandomString()
    MDBaseController.setMarkdownController(this)
  }

  getUnion() {
    return this.union
  }

  // ** ================================================= 标题 ==================================================== **
  /**
   * 设置标题-颜色
   * @param color
   * @version 3.2.2
   */
  setTitleColor(color: ResourceColor | [ResourceColor, ResourceColor, ResourceColor, ResourceColor, ResourceColor, ResourceColor]) {
    this.titleColor = color
    return this
  }

  getTitleColor(): ResourceColor | [ResourceColor, ResourceColor, ResourceColor, ResourceColor, ResourceColor, ResourceColor] {
    return this.titleColor
  }

  /**
   * 设置标题-字号（1-6级）
   * @param titleSize
   */
  setTitleSize(titleSize: [ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number]) {
    this.titleSize = titleSize
    return this
  }

  getTitleSize(): [ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number] {
    return this.titleSize
  }

  /**
   * 设置标题-行高（1-6级）
   * @param lineHeights
   */
  setTitleLineHeight(lineHeights: [ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number]) {
    this.titleLineHeight = lineHeights
    return this
  }

  getTitleLineHeight(): [ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number] {
    return this.titleLineHeight
  }

  /**
   * 设置标题-字体粗细
   * @param fontWeight
   * @version 3.2.2
   */
  setTitleFontWeight(fontWeight: FontWeight | [FontWeight, FontWeight, FontWeight, FontWeight, FontWeight, FontWeight]) {
    this.titleFontWeight = fontWeight
    return this
  }

  getTitleFontWeight(): FontWeight | [FontWeight, FontWeight, FontWeight, FontWeight, FontWeight, FontWeight] {
    return this.titleFontWeight
  }

  /**
   * 设置标题-字体样式
   * @param fontStyle
   * @version 3.2.2
   */
  setTitleFontStyle(fontStyle: FontStyle | [FontStyle, FontStyle, FontStyle, FontStyle, FontStyle, FontStyle]) {
    this.titleFontStyle = fontStyle
    return this
  }

  getTitleFontStyle(): FontStyle | [FontStyle, FontStyle, FontStyle, FontStyle, FontStyle, FontStyle] {
    return this.titleFontStyle
  }

  /**
   * 设置标题-字体族（自定义字体）
   * @description 支持给指定级别的标题设置自定义字体。设置数组格式则为指定级别的标题设置自定义字体，设置唯一自定义字体，则1-6级标题全部生效。
   * @param fontFamily
   * @version 3.2.4
   */
  setTitleFontFamily(fontFamily: ResourceStr | [ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr]) {
    this.titleFontFamily = fontFamily
    return this
  }

  getTitleFontFamily(): ResourceStr | [ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr] {
    return this.titleFontFamily
  }

  // ** ================================================= 普通文本 ==================================================== **
  /**
   * 设置普通文本-颜色
   * @param textColor
   */
  setTextColor(textColor: ResourceColor) {
    this.textColor = textColor
    return this
  }

  getTextColor() {
    return this.textColor
  }

  /**
   * 设置普通文本-行高
   * @param textLineHeight
   */
  setTextLineHeight(textLineHeight: ResourceStr | number) {
    this.textLineHeight = textLineHeight
    return this
  }

  getTextLineHeight() {
    return this.textLineHeight
  }

  /**
   * 设置普通文本-字号
   * @param textSize
   */
  setTextSize(textSize: ResourceStr | number) {
    this.textSize = textSize
    return this
  }

  getTextSize() {
    return this.textSize
  }

  /**
   * 设置普通文本-字体族（自定义字体）
   * @param textSize
   */
  setTextFontFamily(fontFamily: ResourceStr) {
    this.textFontFamily = fontFamily
    return this
  }

  getTextFontFamily() {
    return this.textFontFamily
  }

  // ** ================================================= 行内代码 ==================================================== **
  /**
   * 设置行内代码-颜色
   * @param inlineCodeColor
   */
  setInlineCodeColor(inlineCodeColor: ResourceColor) {
    this.inlineCodeColor = inlineCodeColor
    return this
  }

  getInlineCodeColor(): ResourceColor {
    return this.inlineCodeColor
  }

  /**
   * 设置行内代码-背景颜色
   * @param inlineCodeBackgroundColor
   */
  setInlineCodeBackgroundColor(inlineCodeBackgroundColor: ResourceColor) {
    this.inlineCodeBackgroundColor = inlineCodeBackgroundColor
    return this
  }

  getInlineCodeBackgroundColor(): ResourceColor {
    return this.inlineCodeBackgroundColor
  }

  /**
   * 设置行内代码-背景圆角
   * @param inlineCodeBackgroundRadius
   */
  setInlineCodeBackgroundRadius(radius: Dimension) {
    this.inlineCodeBackgroundRadius = radius
    return this
  }

  getInlineCodeBackgroundRadius(): Dimension {
    return this.inlineCodeBackgroundRadius
  }

  // ** ================================================= 引用块 ==================================================== **
  /**
   * 设置引用块-文本颜色
   * @param color
   * @returns
   */
  setQuoteTextColor(color: ResourceColor) {
    this.quoteTextColor = color
    return this
  }

  getQuoteTextColor() {
    return this.quoteTextColor
  }

  /**
   * 设置引用块-左边颜色
   * @param quoteBorderColor
   * @returns
   */
  setQuoteBorderColor(quoteBorderColor: ResourceColor) {
    this.quoteBorderColor = quoteBorderColor
    return this
  }

  getQuoteBorderColor() {
    return this.quoteBorderColor
  }

  /**
   * 设置引用块-背景颜色
   * @param quoteBackgroundColor
   */
  setQuoteBackgroundColor(quoteBackgroundColor: ResourceColor) {
    this.quoteBackgroundColor = quoteBackgroundColor
    return this
  }

  getQuoteBackgroundColor() {
    return this.quoteBackgroundColor
  }

  /**
   * 设置引用块-圆角
   * @param radius
   * @version 3.2.2
   */
  setQuoteBorderRadius(radius: ResourceStr | number) {
    this.quoteBorderRadius = radius
    return this
  }

  getQuoteBorderRadius() {
    return this.quoteBorderRadius
  }

  /**
   * 设置引用块-左边宽度
   * @param size
   * @version 3.2.2
   */
  setQuoteBorderWidth(size: ResourceStr | number) {
    this.quoteBorderWidth = size
    return this
  }

  getQuoteBorderWidth() {
    return this.quoteBorderWidth
  }

  /**
   * 设置引用块-内边距
   * @param radius
   * @version 3.3.0
   */
  setQuotePadding(padding: Padding | Length | LocalizedPadding) {
    this.quotePadding = padding
    return this
  }

  getQuotePadding() {
    return this.quotePadding
  }

  // ** ================================================= 代码块 ==================================================== **
  /**
   * 设置代码块-主题
   * @param codeBlockTheme
   */
  setCodeBlockTheme(codeBlockTheme: CodeTheme) {
    this.codeBlockTheme = codeBlockTheme
    CodeBlockImpl.handleThemeChange(this.union, codeBlockTheme)
    return this
  }

  getCodeBlockTheme() {
    return this.codeBlockTheme
  }

  /**
   * 设置代码块字体族
   * @param fontFamily
   */
  setCodeBlockFontFamily(fontFamily: ResourceStr) {
    this.codeBlockFontFamily = fontFamily
    return this
  }

  getCodeBlockFontFamily(): ResourceStr {
    return this.codeBlockFontFamily
  }

  /**
   * 设置代码块字号与行高。
   * 两项一起更新，避免动态调整字号时先以旧行高重排一次。
   */
  setCodeBlockTextStyle(fontSize: ResourceStr | number, lineHeight: ResourceStr | number) {
    if (this.codeBlockFontSize == fontSize && this.codeBlockLineHeight == lineHeight) {
      return this
    }
    this.codeBlockFontSize = fontSize
    this.codeBlockLineHeight = lineHeight
    CodeBlockImpl.handleTextStyleChange(this.union)
    return this
  }

  getCodeBlockFontSize(): ResourceStr | number {
    return this.codeBlockFontSize
  }

  getCodeBlockLineHeight(): ResourceStr | number {
    return this.codeBlockLineHeight
  }

  /**
   * 设置代码块-索引展示状态
   * @param codeBlockIdxState
   */
  setCodeBlockIdxState(codeBlockIdxState: boolean) {
    animateTo({ duration: 200 }, () => {
      this.codeBlockIdxState = codeBlockIdxState
    })
    return this
  }

  getCodeBlockIdxState() {
    return this.codeBlockIdxState
  }

  /**
   * 设置代码块-圆角
   * @param radius
   * @version 3.2.2
   */
  setCodeBlockBorderRadius(radius: number | ResourceStr) {
    this.codeBlockBorderRadius = radius
    return this
  }

  getCodeBlockBorderRadius() {
    return this.codeBlockBorderRadius
  }

  /**
   * 设置代码块是否自动折叠
   * @description 默认 false。开启后超过折叠阈值的代码块会折叠并展示展开按钮。
   * @param enable
   */
  setCodeBlockAutoCollapseEnable(enable: boolean) {
    this.codeBlockAutoCollapseEnable = enable
    return this
  }

  getCodeBlockAutoCollapseEnable() {
    return this.codeBlockAutoCollapseEnable
  }

  /**
   * 设置代码块自动折叠阈值
   * @description 默认 10 行。仅在 setCodeBlockAutoCollapseEnable(true) 后生效。
   * @param threshold
   */
  setCodeBlockAutoCollapseThreshold(threshold: number) {
    if (Number.isNaN(threshold) || threshold <= 0) {
      this.codeBlockAutoCollapseThreshold = 10
    } else {
      this.codeBlockAutoCollapseThreshold = Math.floor(threshold)
    }
    return this
  }

  getCodeBlockAutoCollapseThreshold() {
    return this.codeBlockAutoCollapseThreshold
  }

  /**
   * 设置代码高亮着色
   * @param codeHighlight
   */
  setCodeHighlight(codeHighlight: CodeHighlight) {
    this.codeHighlight = codeHighlight
    return this
  }

  getCodeHighlight() {
    return this.codeHighlight
  }

  /**
   * 设置代码块-点击复制监听
   * @param event
   * @returns
   */
  setCodeCopyListener(event: (text: string) => void) {
    this.codeCopyListener = event
    return this
  }

  getCodeCopyListener(text: string) {
    return this.codeCopyListener(text)
  }

  // ** ================================================= 图片 ==================================================== **
  /**
   * 获取图片-宽度
   * @param imageWidth
   */
  setImageWidth(imageWidth: ResourceStr | number | null) {
    this.imageWidth = imageWidth
    return this
  }

  getImageWidth() {
    return this.imageWidth
  }

  /**
   * 设置图片-最大宽度
   * @param imageMaxWidth
   */
  setImageMaxWidth(imageMaxWidth: ResourceStr | number | null) {
    this.imageMaxWidth = imageMaxWidth
    return this
  }

  getImageMaxWidth() {
    return this.imageMaxWidth
  }

  /**
   * 获取图片-高度
   * @param imageWidth
   */
  setImageHeight(imageHeight: ResourceStr | number | null) {
    this.imageHeight = imageHeight
    return this
  }

  getImageHeight() {
    return this.imageHeight
  }

  /**
   * 设置图片-最大高度
   * @param imageMaxWidth
   */
  setImageMaxHeight(imageMaxHeight: ResourceStr | number | null) {
    this.imageMaxHeight = imageMaxHeight
    return this
  }

  getImageMaxHeight() {
    return this.imageMaxHeight
  }

  /**
   * 设置图片-圆角
   * @param radius
   * @version 3.2.2
   */
  setImageBorderRadius(radius: ResourceStr | number) {
    this.imageBorderRadius = radius
    return this
  }

  getImageBorderRadius() {
    return this.imageBorderRadius
  }

  /**
   * 设置图片-点击监听
   * @param event
   * @returns
   */
  setImageClickListener(event: (src: string) => boolean) {
    this.imageClickListener = event
    return this
  }

  getImageClickListener() {
    return this.imageClickListener
  }

  /**
   * 设置图片加载代理
   * @param event
   * @returns
   */
  setImageLoadProxy(event: (src: string) => string) {
    this.imageLoadProxy = event
    return this
  }

  getImageLoadProxy(src: string) {
    return this.imageLoadProxy(src)
  }

  // ** ================================================= 超链接 ==================================================== **
  /**
   * 设置超链接-文字颜色
   * @param hyperlinkTextColor
   */
  setHyperlinkTextColor(hyperlinkTextColor: ResourceColor) {
    this.hyperlinkTextColor = hyperlinkTextColor
    return this
  }

  getHyperlinkTextColor() {
    return this.hyperlinkTextColor
  }

  /**
   * 设置超链接-文字字号
   * @param size
   * @version 3.2.2
   */
  setHyperlinkTextSize(size: ResourceStr | number) {
    this.hyperlinkTextSize = size
    return this
  }

  getHyperlinkTextSize() {
    return this.hyperlinkTextSize
  }

  /**
   * 设置超链接-背景颜色
   * @param inlineCodeBackgroundColor
   */
  setHyperlinkBackgroundColor(bgcolor: ResourceColor) {
    this.hyperlinkBackgroundColor = bgcolor
    return this
  }

  getHyperlinkBackgroundColor(): ResourceColor {
    return this.hyperlinkBackgroundColor
  }

  /**
   * 设置超链接-背景圆角
   * @param radius
   */
  setHyperlinkBackgroundRadius(radius: Dimension) {
    this.hyperlinkBackgroundRadius = radius
    return this
  }

  getHyperlinkBackgroundRadius(): Dimension {
    return this.hyperlinkBackgroundRadius
  }

  /**
   * 设置超链接-下划线展示状态
   * @param hyperlinkUnderlineState
   */
  setHyperlinkUnderlineState(hyperlinkUnderlineState: boolean) {
    this.hyperlinkUnderlineState = hyperlinkUnderlineState
    return this
  }

  getHyperlinkUnderlineState() {
    return this.hyperlinkUnderlineState
  }

  /**
   * 设置超链接-点击监听
   * @param event
   * @returns
   */
  setHyperlinkClickListener(event: (title: string, src: string, anchorInfo?: componentUtils.ComponentInfo) => boolean) {
    this.hyperlinkClickListener = event
    return this
  }

  getHyperlinkClickListener() {
    return this.hyperlinkClickListener
  }

  // ** ================================================= 表格 ==================================================== **
  /**
   * 设置表格背景色
   * @param tableBackgroundColor
   */
  setTableBackgroundColor(tableBackgroundColor: ResourceColor) {
    this.tableBackgroundColor = tableBackgroundColor
    return this
  }

  getTableBackgroundColor() {
    return this.tableBackgroundColor
  }

  /**
   * 设置表格表头文本颜色
   */
  setTableTitleTextColor(tableTitleTextColor: ResourceColor) {
    this.tableTitleTextColor = tableTitleTextColor
    return this
  }

  getTableTitleTextColor() {
    return this.tableTitleTextColor
  }

  /**
   * 设置表格-错行文本颜色
   */
  setTableInterleaveTextColor(tableInterleaveTextColor: ResourceColor) {
    this.tableInterleaveTextColor = tableInterleaveTextColor
  }

  getTableInterleaveTextColor() {
    return this.tableInterleaveTextColor
  }

  /**
   * 设置表格-非错行文本颜色
   */
  setTableNormalTextColor(tableNormalTextColor: ResourceColor) {
    this.tableNormalTextColor = tableNormalTextColor
  }

  getTableNormalTextColor() {
    return this.tableNormalTextColor
  }

  /**
   * 设置表格-表头背景色
   * @param tableTitleBackgroundColor
   */
  setTableTitleBackgroundColor(tableTitleBackgroundColor: ResourceColor) {
    this.tableTitleBackgroundColor = tableTitleBackgroundColor
    return this
  }

  getTableTitleBackgroundColor() {
    return this.tableTitleBackgroundColor
  }

  /**
   * 设置表格-错行背景色
   * @param tableInterleaveBackgroundColor
   */
  setTableInterleaveBackgroundColor(tableInterleaveBackgroundColor: ResourceColor) {
    this.tableInterleaveBackgroundColor = tableInterleaveBackgroundColor
    return this
  }

  getTableInterleaveBackgroundColor() {
    return this.tableInterleaveBackgroundColor
  }

  /**
   * 设置表格-圆角
   * @param radius
   * @version 3.2.2
   */
  setTableBorderRadius(radius: ResourceStr | number) {
    this.tableBorderRadius = radius
    return this
  }

  getTableBorderRadius() {
    return this.tableBorderRadius
  }

  /**
   * 设置表格-外边框颜色
   * @param color
   * @version 3.2.2
   */
  setTableOuterBorderColor(color: ResourceColor) {
    this.tableOuterBorderColor = color
    return this
  }

  getTableOuterBorderColor() {
    return this.tableOuterBorderColor
  }

  /**
   * 设置表格-外边框宽度
   * @param width
   * @version 3.2.2
   */
  setTableOuterBorderWidth(width: ResourceStr | number) {
    this.tableOuterBorderWidth = width
    return this
  }

  getTableOuterBorderWidth() {
    return this.tableOuterBorderWidth
  }

  /**
   * 设置表格-内边框颜色
   * @param color
   * @version 3.2.2
   */
  setTableInnerBorderColor(color: ResourceColor) {
    this.tableInnerBorderColor = color
    return this
  }

  getTableInnerBorderColor() {
    return this.tableInnerBorderColor
  }

  /**
   * 设置表格-内边框宽度
   * @param width
   * @version 3.2.2
   */
  setTableInnerBorderWidth(width: ResourceStr | number) {
    this.tableInnerBorderWidth = width
    return this
  }

  getTableInnerBorderWidth() {
    return this.tableInnerBorderWidth
  }

  /**
   * 设置表格-屏幕对齐方式
   * @param flexAlign 对齐方式
   * @version 3.2.2
   */
  setTableAlign(flexAlign: FlexAlign) {
    this.tableAlign = flexAlign
    return this
  }

  getTableAlign() {
    return this.tableAlign
  }

  // ** ================================================= 任务列表 ==================================================== **
  /**
   * 设置任务列表-选中颜色
   * @param todoSelectedColor
   */
  setTodoSelectedColor(todoSelectedColor: ResourceColor) {
    this.todoSelectedColor = todoSelectedColor
    return this
  }

  getTodoSelectedColor() {
    return this.todoSelectedColor
  }

  /**
   * 设置任务列表-选项大小
   * @param todoSelectSize
   */
  setTodoSelectSize(todoSelectSize: ResourceStr | number) {
    this.todoSelectSize = todoSelectSize
    return this
  }

  getTodoSelectSize() {
    return this.todoSelectSize
  }

  /**
   * 设置无序列表-指示点大小
   * @param size
   * @version 3.2.2
   */
  setUlPointSize(size: ResourceStr | number) {
    this.ulPointSize = size
    return this
  }

  getUlPointSize() {
    return this.ulPointSize
  }

  /**
   * 设置无序列表-指示点颜色
   * @param color
   * @version 3.2.2
   */
  setUlPointColor(color: ResourceColor) {
    this.ulPointColor = color
    return this
  }

  getUlPointColor() {
    return this.ulPointColor
  }

  // ** ================================================= 脚注 ==================================================== **
  /**
   * 设置脚注-文字颜色
   * @param footnoteTextColor
   */
  setFootnoteTextColor(footnoteTextColor: ResourceColor) {
    this.footnoteTextColor = footnoteTextColor
    return this
  }

  getFootnoteTextColor() {
    return this.footnoteTextColor
  }

  // ** ================================================= 分割线 ==================================================== **
  /**
   * 设置分割线-颜色
   * @param lineColor
   * @returns
   */
  setLineColor(lineColor: ResourceColor) {
    this.lineColor = lineColor
    return this
  }

  getLineColor() {
    return this.lineColor
  }

  // ** ================================================= 数学公式 ==================================================== **
  /**
   * 设置数学公式-字体大小
   * @param size
   * @returns
   */
  setLatexMathTextSize(size: number) {
    this.latexMathTextSize = size
    return this
  }

  getLatexMathTextSize() {
    return this.latexMathTextSize
  }

  /**
   * 数学公式-字体颜色（十六进制）
   * @param color
   * @returns
   */
  setLatexMathTextColor(color: number) {
    this.latexMathTextColor = color
    return this
  }

  getLatexMathTextColor() {
    return this.latexMathTextColor
  }

  /**
   * 设置数学公式-点击监听
   * @param event
   * @returns
   */
  setLatexClickListener(event: (text: string, pixelMap: image.PixelMap) => boolean) {
    this.latexClickListener = event
    return this
  }

  getLatexClickListener() {
    return this.latexClickListener
  }

  /**
   * 设置是否开启 mermaid 渲染
   * @param enable
   */
  setMermaidEnable(enable: boolean) {
    this.mermaidEnable = enable
    return this
  }

  getMermaidEnable() {
    return this.mermaidEnable
  }

  /**
   * 设置 Mermaid 深浅色主题
   * @param theme
   */
  setMermaidTheme(theme: CodeTheme) {
    this.mermaidTheme = theme
    getContext().eventHub.emit(markdownMermaidThemeChangeEventName)
    return this
  }

  getMermaidTheme(): CodeTheme {
    return this.mermaidTheme
  }

  /**
   * 设置 Mermaid 预览安全级别
   * @param securityLevel
   */
  setMermaidSecurityLevel(securityLevel: MermaidSecurityLevel) {
    this.mermaidSecurityLevel = securityLevel
    return this
  }

  getMermaidSecurityLevel(): MermaidSecurityLevel {
    return this.mermaidSecurityLevel
  }

  /**
   * 设置是否开启 HTML 代码块预览
   * @param enable
   */
  setHtmlPreviewEnable(enable: boolean) {
    this.htmlPreviewEnable = enable
    return this
  }

  getHtmlPreviewEnable() {
    return this.htmlPreviewEnable
  }

  /**
   * 设置 HTML 代码块预览是否允许执行 JavaScript
   * @description 默认 false。Mermaid 预览不受此开关影响。
   * @param enable
   */
  setHtmlPreviewJavaScriptEnable(enable: boolean) {
    this.htmlPreviewJavaScriptEnable = enable
    return this
  }

  getHtmlPreviewJavaScriptEnable() {
    return this.htmlPreviewJavaScriptEnable
  }

  /**
   * 设置 Mermaid/HTML 内联预览是否复用 ArkWeb 预览池
   * @description 默认 false。开启后会预热少量 Web 组件，并在 Mermaid/HTML 预览之间复用。
   * @param enable
   */
  setWebPreviewPoolEnable(enable: boolean) {
    this.webPreviewPoolEnable = enable
    return this
  }

  getWebPreviewPoolEnable() {
    return this.webPreviewPoolEnable
  }

  /**
   * 设置 ArkWeb 预览池大小
   * @description initialSize 为预热数量，maxSize 为最大动态扩容数量，idleRetain 为长期保留的空闲槽数量。
   * @param initialSize
   * @param maxSize
   * @param idleRetain
   */
  setWebPreviewPoolSize(initialSize: number, maxSize: number, idleRetain: number) {
    const safeMaxSize = Math.max(1, Math.floor(maxSize))
    this.webPreviewPoolInitialSize = Math.min(Math.max(0, Math.floor(initialSize)), safeMaxSize)
    this.webPreviewPoolMaxSize = safeMaxSize
    this.webPreviewPoolIdleRetain = Math.min(Math.max(0, Math.floor(idleRetain)), safeMaxSize)
    return this
  }

  getWebPreviewPoolInitialSize() {
    return this.webPreviewPoolInitialSize
  }

  getWebPreviewPoolMaxSize() {
    return this.webPreviewPoolMaxSize
  }

  getWebPreviewPoolIdleRetain() {
    return this.webPreviewPoolIdleRetain
  }

  /**
   * 设置是否开启线程加载模式（默认开启）
   * @param enable
   */
  setThreadRenderEnable(enable: boolean) {
    this.threadRenderEnable = enable
    return this
  }

  getThreadRenderEnable() {
    return this.threadRenderEnable
  }

  /**
   * 设置是否开启 Setext 标题解析
   * @description 默认 false。开启后，文本下方的 ===== 或 ----- 会解析为一级或二级标题。
   * @param enable
   */
  setSetextHeadingEnable(enable: boolean) {
    this.setextHeadingEnable = enable
    return this
  }

  getSetextHeadingEnable() {
    return this.setextHeadingEnable
  }

  // ** ================================================= 懒渲染 ==================================================== **
  /**
   * 设置是否开启可见区域懒渲染
   * @description 默认 false。开启后屏幕外块先以轻量占位渲染，进入可见区域附近后再渲染真实内容。
   * @param enable
   */
  setLazyRender(enable: boolean) {
    this.lazyRender = enable
    return this
  }

  getLazyRender() {
    return this.lazyRender
  }

  /**
   * 设置懒渲染预渲染块数量
   * @description 默认 3。实际渲染会按内部懒渲染分组折算。
   * @param count
   */
  setLazyPreloadBlockCount(count: number) {
    this.lazyPreloadBlockCount = Math.max(0, count)
    return this
  }

  getLazyPreloadBlockCount() {
    return this.lazyPreloadBlockCount
  }

  // ** ================================================= 剪贴板复制范围选项 ==================================================== **
  /**
   * 设置剪贴板复制范围选项
   * @description 默认 CopyOptions.LocalDevice（支持复制后在所有应用内粘贴）。从 3.3.1 版本开始，该接口不再维护，调用后不再生效，请使用 setTextSelectionEnable() 与 setTextSelectionEnable() 实现文本选择复制功能。
   * @param copyOption
   * @deprecated 3.3.1
   */
  setCopyOption(copyOption: CopyOptions) {
    // this.copyOption = copyOption
  }

  getCopyOption() {
    return this.copyOption
  }

  /**
   * 设置是否开启跨 Text 文本选择能力
   * @description 默认 false
   * @param enable
   * @version 3.3.2
   */
  setTextSelectionEnable(enable: boolean) {
    this.textSelectionEnable = enable
    return this
  }

  getTextSelectionEnable() {
    return this.textSelectionEnable
  }

  /**
   * 设置跨 Text 文本选择复制监听
   * @param event
   * @version 3.3.2
   */
  setTextSelectionCopyListener(event: (text: string) => void) {
    this.textSelectionCopyListener = event
    return this
  }

  getTextSelectionCopyListener() {
    return this.textSelectionCopyListener
  }

  /**
   * 设置跨 Text 文本选择后的操作栏按钮
   * @description 不设置或传空数组时使用默认「复制 / 全选 / 取消」。
   * @param items
   */
  setTextSelectionActionItems(items: TextSelectionActionItem[]) {
    this.textSelectionActionItems = items
    return this
  }

  getTextSelectionActionItems(): TextSelectionActionItem[] {
    return this.textSelectionActionItems
  }

  /**
   * 设置是否开启长按菜单模式(复制 / 选取文本)
   * @description 默认 false(保持既有「长按立即选区」行为)。开启后需配合 setLongPressMenuListener 实现蒙层菜单。
   *   依赖 setTextSelectionEnable(true)。
   * @param enable
   */
  setLongPressMenuEnable(enable: boolean) {
    this.longPressMenuEnable = enable
    return this
  }

  getLongPressMenuEnable() {
    return this.longPressMenuEnable
  }

  /**
   * 设置长按菜单事件回调
   * @description 触屏长按时触发, 回调参数携带按压点坐标、所在段落文本与「选取文本」动作。
   * selectWholeBlock 支持全部 / 段落 / 自定义三种选取类型, 无参调用保持自定义起选。
   * @param event
   */
  setLongPressMenuListener(event: (info: LongPressMenuInfo) => void) {
    this.longPressMenuListener = event
    return this
  }

  getLongPressMenuListener() {
    return this.longPressMenuListener
  }

  // ** ================================================= 块级元素间距 ==================================================== **
  /**
   * 设置块级元素间距
   * @description 默认 10vp。
   * @param copyOption
   * @version 3.3.0
   */
  setBlockSpacing(spacing: number | ResourceStr) {
    this.blockSpacing = spacing
  }

  getBlockSpacing() {
    return this.blockSpacing
  }
}
