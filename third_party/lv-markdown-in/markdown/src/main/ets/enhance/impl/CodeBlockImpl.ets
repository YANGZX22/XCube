import { CodeTheme, markdownCodeThemeChangeEventName } from '../constant/CodeTheme';
import { MDBaseController } from '../controller/BaseController';
import { CodeHighlight } from '../model/CodeHighlight';
import { TreeNode } from '../model/TreeNode';
import { Logger } from '../utils/Logger';

export namespace CodeBlockImpl {
  export function handleBackgroundColor(them: CodeTheme) {
    if (them == "dark") {
      return "#181A1F"
    } else {
      return "#F9FAFB"
    }
  }

  export function handleThemeChange(markdownUnion: string, them: CodeTheme) {
    Logger.info("markdownUnion > " + markdownUnion)
    handleCodeHighlight(markdownUnion, them)
    getContext().eventHub.emit(markdownCodeThemeChangeEventName)
  }

  export async function copyText(markdownUnion: string, text: string) {
    MDBaseController.getMarkdownController(markdownUnion).getCodeCopyListener(text)
  }

  export function handleCodeBlockBorderRadius(markdownUnion: string): number | ResourceStr {
    return MDBaseController.getMarkdownController(markdownUnion).getCodeBlockBorderRadius()
  }

  export function handleCodeHighlight(markdownUnion: string, them: CodeTheme) {
    if (them == "dark") {
      MDBaseController.getMarkdownController(markdownUnion).setCodeHighlight({
        keyword: '#E2DA85', // 关键字
        method: '#65CCDC', // 方法名
        type: '#CC7830', // 类型
        modifier: '#4169e1', // 修饰符
        constant: '#FFFFF6', // 常量
        variable: '#FFFFF6', // 变量
        operator: '#E2DA90', // 运算符
        punctuation: '#E2DA90', // 标点
        brace: '#ffea78a3', // 括号
        bigBrace: '#FAA23D', //大括号
        string: '#AA7DFC', // 字符串
        number: '#B3E54C', // 数字 |
        boolean: '#E2DA90', // 布尔值
        nullish: '#E2DA90', // 空值
        promise: '#CC6B32', // Promise
        tag: '#008b8b', // HTML标签
        attrName: '#CC6B32', // 属性名
        attrValue: '#ff50641c', // 属性值
        doctype: '#ff8c00', // 文档声明
        comment: '#80807C', // 注释
        decorator: '#ffe559a0', // ArkTS 装饰器
        component: '#20b2aa', // ArkTS UI组件
        normal: '#ffe5e5de'         // 普通文本
      })
    }
    if (them == "light") {
      MDBaseController.getMarkdownController(markdownUnion).setCodeHighlight(new CodeHighlight())
    }
  }

  export function setExtend(node: TreeNode, ...map: [string, ESObject][]) {
    if (node.extend == undefined) {
      node.extend = new Map(map)
    } else {
      map.forEach((item: [string, ESObject]) => {
        node.extend!!.set(item[0], item[1])
      })
    }
  }
}