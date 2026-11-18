/**
 * 用途：
 *   集中维护 HTML 输入、预期 Markdown 和预期 AST。
 *
 * 覆盖场景：
 *   常用 HTML 标签、复杂组合 HTML、混合内容、代码保护和异常标签。
 *
 * 如何验证：
 *   由 test-html-to-markdown.mjs 逐条加载执行。每个用例包含唯一名称、HTML 输入、
 *   预期 Markdown 和预期 AST。
 */

const text = (value) => ({ type: 'text', text: value });
const paragraph = (children) => ({ type: 'paragraph', children });
const listItem = (value) => ({ type: 'listItem', children: [paragraph([text(value)])] });
const cell = (children) => ({ type: 'tableCell', children });

export const htmlCases = [
  {
    name: '六级 HTML 标题',
    input: '<h1>H1</h1><h2>H2</h2><h3>H3</h3><h4>H4</h4><h5>H5</h5><h6>H6</h6>',
    expectedMarkdown: '# H1\n\n## H2\n\n### H3\n\n#### H4\n\n##### H5\n\n###### H6',
    expected: [1, 2, 3, 4, 5, 6].map((level) => ({ type: 'heading', level, children: [text(`H${level}`)] }))
  },
  {
    name: '段落 div 和 br',
    input: '<p>第一行<br>第二行</p><div>第三段</div>',
    expectedMarkdown: '第一行  \n第二行\n\n第三段',
    expected: [paragraph([text('第一行\n第二行')]), paragraph([text('第三段')])]
  },
  {
    name: '行内粗体斜体删除线',
    input: '<p><strong>粗体</strong> <b>B</b> <em>斜体</em> <i>I</i> <del>删除</del></p>',
    expectedMarkdown: '**粗体** **B** *斜体* *I* ~~删除~~',
    expected: [paragraph([
      { type: 'bold', children: [text('粗体')] }, text(' '), { type: 'bold', children: [text('B')] }, text(' '),
      { type: 'italic', children: [text('斜体')] }, text(' '), { type: 'italic', children: [text('I')] }, text(' '),
      { type: 'strikethrough', children: [text('删除')] }
    ])]
  },
  {
    name: '链接和图片',
    input: '<p><a href="https://example.com">官网</a> <img src="cover.png" alt="封面"></p>',
    expectedMarkdown: '[官网](https://example.com) ![封面](cover.png)',
    expected: [paragraph([
      { type: 'link', url: 'https://example.com', children: [text('官网')] }, text(' '),
      { type: 'image', alt: '封面', url: 'cover.png', title: '' }
    ])]
  },
  {
    name: '简单无序列表',
    input: '<ul><li>单项</li></ul>',
    expectedMarkdown: '- 单项',
    expected: [{ type: 'ul', children: [listItem('单项')] }]
  },
  {
    name: '简单有序列表',
    input: '<ol><li>单项</li></ol>',
    expectedMarkdown: '1. 单项',
    expected: [{ type: 'ol', children: [listItem('单项')] }]
  },
  {
    name: '简单引用',
    input: '<blockquote>引用内容</blockquote>',
    expectedMarkdown: '> 引用内容',
    expected: [{ type: 'blockquote', children: [paragraph([text('引用内容')])] }]
  },
  {
    name: 'HTML 表格',
    input: '<table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr></tbody></table>',
    expectedMarkdown: '| A | B |\n|---|---|\n| 1 | 2 |',
    expected: [{
      tableId: 0, type: 'table',
      rawMarkdown: '| A | B |\n|---|---|\n| 1 | 2 |',
      header: [cell([paragraph([text('A')])]), cell([paragraph([text('B')])])],
      align: ['none', 'none'],
      rows: [{ type: 'tableRow', children: [cell([text('1')]), cell([text('2')])] }]
    }]
  },
  {
    name: 'font 属性保留并进入 AST',
    input: '<p><font color="red" size="3" face="HarmonyOS Sans">文字</font></p>',
    expectedMarkdown: '<font color="red" size="3" face="HarmonyOS Sans">文字</font>',
    expected: [paragraph([{ type: 'inlineHtmlFont', text: '文字', color: 'red', size: 15, face: 'HarmonyOS Sans' }])]
  },
  {
    name: '连续段落和 Markdown 混排',
    input: '<p>第一段 <strong>重点</strong></p><p>第二段 [链接](https://example.com)</p>',
    expectedMarkdown: '第一段 **重点**\n\n第二段 [链接](https://example.com)',
    expected: [
      paragraph([text('第一段 '), { type: 'bold', children: [text('重点')] }]),
      paragraph([text('第二段 '), { type: 'link', url: 'https://example.com', children: [text('链接')] }])
    ]
  },
  {
    name: '不支持标签移除但保留内容',
    input: '<p>前缀 <custom>内容</custom> 后缀</p>',
    expectedMarkdown: '前缀 内容 后缀',
    expected: [paragraph([text('前缀 内容 后缀')])]
  },
  {
    name: '不完整标签按当前实现降级',
    input: '<p>未闭合 <strong>文本',
    expectedMarkdown: '未闭合 文本',
    expected: [paragraph([text('未闭合 文本')])]
  },
  {
    name: '复杂组合 HTML',
    input: '<h1>标题</h1><p>正文 <strong>重点</strong> <a href="https://example.com">链接</a></p><ul><li>列表</li></ul><table><tr><th>A</th></tr><tr><td>1</td></tr></table>',
    expectedMarkdown: '# 标题\n\n正文 **重点** [链接](https://example.com)\n\n- 列表\n\n| A |\n|---|\n| 1 |',
    expected: [
      { type: 'heading', level: 1, children: [text('标题')] },
      paragraph([text('正文 '), { type: 'bold', children: [text('重点')] }, text(' '), { type: 'link', url: 'https://example.com', children: [text('链接')] }]),
      { type: 'ul', children: [listItem('列表')] },
      { tableId: 0, type: 'table', rawMarkdown: '| A |\n|---|\n| 1 |', header: [cell([paragraph([text('A')])])], align: ['none'], rows: [{ type: 'tableRow', children: [cell([text('1')])] }] }
    ]
  }
];

// 下列用例描述期望的安全转换行为。若生产转换器破坏代码、实体或嵌套结构，测试应失败而不是固化错误结果。
export const htmlRiskCases = [
  {
    name: '代码块保留语言与标签原文',
    input: '<pre><code class="language-html">&lt;div&gt;内容&lt;/div&gt;</code></pre>',
    expectedMarkdown: '```html\n<div>内容</div>\n```',
    expected: [{ type: 'codeBlock', lang: 'html', text: '<div>内容</div>', closed: true }]
  },
  {
    name: '行内代码保护 HTML 标签',
    input: '<p>使用 <code><div>demo</div></code> 示例</p>',
    expectedMarkdown: '使用 `<div>demo</div>` 示例',
    expected: [paragraph([text('使用 '), { type: 'inlineCode', text: '<div>demo</div>' }, text(' 示例')])]
  },
  {
    name: 'HTML 实体正确解码',
    input: '<p>&lt;div&gt; &amp; &#65;</p>',
    expectedMarkdown: '<div> & A',
    expected: [paragraph([text('<div> & A')])]
  },
  {
    name: '多项列表保持项目换行',
    input: '<ul><li>A</li><li>B</li></ul>',
    expectedMarkdown: '- A\n- B',
    expected: [{ type: 'ul', children: [listItem('A'), listItem('B')] }]
  },
  {
    name: '嵌套列表保持层级',
    input: '<ul><li>父项<ul><li>子项</li></ul></li></ul>',
    expectedMarkdown: '- 父项\n  - 子项',
    expected: [{ type: 'ul', children: [{
      type: 'listItem', children: [paragraph([text('父项')]), { type: 'ul', children: [listItem('子项')] }]
    }] }]
  },
  {
    name: '嵌套引用保持层级',
    input: '<blockquote>外层<blockquote>内层</blockquote></blockquote>',
    expectedMarkdown: '> 外层\n> > 内层',
    expected: [{ type: 'blockquote', children: [
      paragraph([text('外层')]), { type: 'blockquote', children: [paragraph([text('内层')])] }
    ] }]
  }
];
