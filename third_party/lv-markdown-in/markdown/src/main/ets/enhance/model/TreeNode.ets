// 基础节点
export interface BaseNode {
  type: string;
  children?: TreeNode[] | FootnoteNode[];
  extend?: Map<string, ESObject>;
  renderKey?: string;
}

// 文本节点
export interface TextNode extends BaseNode {
  type: "text";
  text: string;
}

// 加粗、斜体、删除线等内联节点
interface BoldNode extends BaseNode {
  type: "bold";
  children: TreeNode[];
}

interface ItalicNode extends BaseNode {
  type: "italic";
  children: TreeNode[];
}

// 粗斜体节点
export interface BoldItalicNode extends BaseNode {
  type: "bolditalic";
  children: TreeNode[];
}

interface StrikethroughNode extends BaseNode {
  type: "strikethrough";
  children: TreeNode[];
}

// 行内代码
export interface InlineCodeNode extends BaseNode {
  type: "inlineCode";
  text: string;
}

// 行内 font 标签
export interface InlineHtmlFontNode extends BaseNode {
  type: "inlineHtmlFont";
  text: string;
  color?: string;
  size?: number;
  face?: string;
}

// 链接
export interface LinkNode extends BaseNode {
  type: "link";
  text?: string;
  url: string;
  children: TreeNode[];
}

// 图片
export interface ImageNode extends BaseNode {
  type: "image";
  url: string;
  alt?: string;
  title?: string,
  width?: number,
  height?: number
}

// 段落
interface ParagraphNode extends BaseNode {
  type: "paragraph";
  children: TreeNode[];
}

// 分割线
interface HrNode extends BaseNode {
  type: "hr";
}

// 标题
interface HeadingNode extends BaseNode {
  type: "heading";
  level: 1 | 2 | 3 | 4 | 5 | 6;
  children: TreeNode[];
}

// 块引用
interface BlockquoteNode extends BaseNode {
  type: "blockquote";
  children: TreeNode[];
}

// 列表
interface ListItemNode extends BaseNode {
  type: "listItem";
  checked?: boolean,
  children: TreeNode[];
}

interface UlNode extends BaseNode {
  type: "ul";
  children: ListItemNode[];
}

interface OlNode extends BaseNode {
  type: "ol";
  children: ListItemNode[];
}

// 表格
export interface TableCellNode extends BaseNode {
  type: "tableCell";
  children: ParagraphNode[];
}

export interface TableRowNode extends BaseNode {
  type: "tableRow";
  children: TableCellNode[];
}

export interface TableNode extends BaseNode {
  type: "table";
  tableId: number,
  header: TableCellNode[];
  rows: TableRowNode[];
  align?: ("none" | "left" | "center" | "right")[];
}

// 代码块
export interface CodeBlockNode extends BaseNode {
  type: "codeBlock";
  lang?: string;
  text: string;
  closed?: boolean;
}

// 脚注组
export interface FootnotesNode extends BaseNode {
  type: "footnotes";
  children: FootnoteNode[]
}

export interface FootnoteNode extends BaseNode {
  id: string
  children: ParagraphNode[]
}

export interface FootnoteRefNode extends BaseNode {
  type: "footnoteRef";
  id: string
}

// 数学公式节点
export interface LatexNode extends BaseNode {
  type: "latex";
  block: boolean;
  text: string;
}

export interface PluginNode extends BaseNode {
  type: "plugin";
  pluginKey: string;
  display: "inline" | "block";
  raw: string;
  params?: ESObject;
  groups?: string[];
  copyText?: string;
  selectable?: boolean;
}

// 所有节点的联合类型
export type TreeNode =
  | TextNode
    | BoldNode
    | ItalicNode
  | StrikethroughNode
  | InlineCodeNode
  | InlineHtmlFontNode
  | LinkNode
    | ImageNode
    | ParagraphNode
    | HrNode
    | HeadingNode
    | BlockquoteNode
    | UlNode
    | OlNode
    | ListItemNode
    | TableNode
    | TableRowNode
    | TableCellNode
    | CodeBlockNode
    | FootnotesNode
    | FootnoteRefNode
    | LatexNode
    | PluginNode
    | BoldItalicNode;
