/**
 * 用途：
 *   集中维护 Markdown 输入、解析配置、插件配置和预期 AST。
 *
 * 覆盖场景：
 *   全部基础语法、组合语法、异常输入和历史问题回归。
 *
 * 如何验证：
 *   由 test-markdown-ast.mjs 逐条加载执行。每个用例包含唯一名称、输入内容和预期 AST；
 *   涉及插件或解析开关时额外提供 plugins 或 options。
 */

const text = (value) => ({ type: 'text', text: value });
const paragraph = (children) => ({ type: 'paragraph', children });
const listItem = (children, checked) => checked === undefined
  ? { type: 'listItem', children }
  : { type: 'listItem', checked, children };
const cell = (children) => ({ type: 'tableCell', children });

const inlinePlugin = {
  key: 'ref', display: 'inline', pattern: String.raw`\[ref_(?<id>\d+)\]`,
  matchMode: 'inline-prefix', selectable: true
};
const blockPlugin = {
  key: 'chart', display: 'block', pattern: String.raw`^<chart:(?<name>[a-z]+)>$`,
  matchMode: 'full-line'
};

export const astCases = [
  { name: '空文本', input: '', expected: [] },
  {
    name: '六级标题和分割线',
    input: '# H1\n## H2\n### H3\n#### H4\n##### H5\n###### H6\n---',
    expected: [
      ...[1, 2, 3, 4, 5, 6].map((level) => ({ type: 'heading', level, children: [text(`H${level}`)] })),
      { type: 'hr' }
    ]
  },
  {
    name: 'Setext 标题开关开启', input: '一级标题\n===\n\n二级标题\n---',
    options: { setextHeading: true },
    expected: [
      { type: 'heading', level: 1, children: [text('一级标题')] },
      { type: 'heading', level: 2, children: [text('二级标题')] }
    ]
  },
  {
    name: 'Setext 标题默认关闭', input: '普通文本\n===',
    expected: [paragraph([text('普通文本\n===')])]
  },
  {
    name: '段落换行与全部强调语法',
    input: '第一行\n第二行 **粗体** *斜体* ***粗斜体*** ~~删除~~ `code`',
    expected: [paragraph([
      text(`第一行\n第二行 `),
      { type: 'bold', children: [text('粗体')] }, text(' '),
      { type: 'italic', children: [text('斜体')] }, text(' '),
      { type: 'bolditalic', children: [text('粗斜体')] }, text(' '),
      { type: 'strikethrough', children: [text('删除')] }, text(' '),
      { type: 'inlineCode', text: 'code' }
    ])]
  },
  {
    name: '连续星号和下划线完整保留且标准强调正常解析',
    input: '**** ________ ***粗斜体*** **粗体** *斜体*',
    expected: [paragraph([
      text('**** ________ '),
      { type: 'bolditalic', children: [text('粗斜体')] }, text(' '),
      { type: 'bold', children: [text('粗体')] }, text(' '),
      { type: 'italic', children: [text('斜体')] }
    ])]
  },
  {
    name: '标题组合粗体链接代码公式',
    input: '# **重点** [官网](https://example.com) `code` $x_n$',
    expected: [{ type: 'heading', level: 1, children: [
      { type: 'bold', children: [text('重点')] }, text(' '),
      { type: 'link', url: 'https://example.com', children: [text('官网')] }, text(' '),
      { type: 'inlineCode', text: 'code' }, text(' '),
      { type: 'latex', block: false, text: 'x_n', children: [text('x_n')] }
    ] }]
  },
  {
    name: '链接自动链接和 HTML 实体',
    input: '[文档](https://example.com "说明") https://open.example/path?a=1 &#65; &#x42;',
    expected: [paragraph([
      { type: 'link', url: 'https://example.com', title: '说明', children: [text('文档')] }, text(' '),
      { type: 'link', url: 'https://open.example/path?a=1', title: '', children: [text('https://open.example/path?a=1')] },
      text(' A B')
    ])]
  },
  {
    name: '图片标题尺寸和图片链接',
    input: '![封面](cover.png =600x400 "标题") ![宽](wide.png =320x) ![高](high.png =x180) [![按钮](button.png)](https://example.com)',
    expected: [paragraph([
      { type: 'image', alt: '封面', url: 'cover.png', title: '标题', width: 600, height: 400 }, text(' '),
      { type: 'image', alt: '宽', url: 'wide.png', title: '', width: 320 }, text(' '),
      { type: 'image', alt: '高', url: 'high.png', title: '', height: 180 }, text(' '),
      { type: 'image', alt: '按钮', url: 'button.png', title: '', href: 'https://example.com' }
    ])]
  },
  {
    name: 'font 与段落组合语法',
    input: '正文 <font color="#ff0000" size="24px" face="HarmonyOS Sans">红字</font> **粗体** ~~删除~~ ![图](a.png) https://example.com',
    expected: [paragraph([
      text('正文 '), { type: 'inlineHtmlFont', text: '红字', color: '#ff0000', size: 24, face: 'HarmonyOS Sans' },
      text(' '), { type: 'bold', children: [text('粗体')] }, text(' '),
      { type: 'strikethrough', children: [text('删除')] }, text(' '),
      { type: 'image', alt: '图', url: 'a.png', title: '' }, text(' '),
      { type: 'link', url: 'https://example.com', title: '', children: [text('https://example.com')] }
    ])]
  },
  {
    name: '无序有序任务列表',
    input: '- 普通\n- [x] 完成\n- [ ] 待办\n\n1. 第一\n2. 第二',
    expected: [
      { type: 'ul', children: [
        listItem([paragraph([text('普通')])]), listItem([paragraph([text('完成')])], true),
        listItem([paragraph([text('待办')])], false)
      ] },
      { type: 'ol', children: [listItem([paragraph([text('第一')])]), listItem([paragraph([text('第二')])])] }
    ]
  },
  {
    name: '历史回归普通嵌套列表', input: '- parent\n  - child\n- next',
    expected: [{ type: 'ul', children: [
      listItem([paragraph([text('parent')]), { type: 'ul', children: [listItem([paragraph([text('child')])])] }]),
      listItem([paragraph([text('next')])])
    ] }]
  },
  {
    name: '历史回归列表内块级公式',
    input: '1. alpha\n   $$\n   x_n = n\n   $$\n2. beta',
    expected: [{ type: 'ol', children: [
      listItem([paragraph([text('alpha')]), paragraph([{ type: 'latex', block: true, text: 'x_n = n', children: [text('x_n = n')] }])]),
      listItem([paragraph([text('beta')])])
    ] }]
  },
  {
    name: '历史回归列表内嵌套列表公式表格',
    input: '1. first\n2. second\n   - nested $x_n$\n   $$\n   I = \\int_0^1 x dx\n   $$\n   | A | B |\n   | :- | -: |\n   | 1 | 2 |\n3. third',
    expected: [{ type: 'ol', children: [
      listItem([paragraph([text('first')])]),
      listItem([
        paragraph([text('second')]),
        { type: 'ul', children: [listItem([paragraph([text('nested '), { type: 'latex', block: false, text: 'x_n', children: [text('x_n')] }])])] },
        paragraph([{ type: 'latex', block: true, text: 'I = \\int_0^1 x dx', children: [text('I = \\int_0^1 x dx')] }]),
        {
          tableId: 0, type: 'table', align: ['left', 'right'],
          rawMarkdown: '| A | B |\n| :- | -: |\n| 1 | 2 |',
          header: [cell([paragraph([text('A')])]), cell([paragraph([text('B')])])],
          rows: [{ type: 'tableRow', children: [cell([text('1')]), cell([text('2')])] }]
        }
      ]),
      listItem([paragraph([text('third')])])
    ] }]
  },
  {
    name: '引用中列表和公式', input: '> 说明\n> - 项目 $x_n$\n>   - 子项',
    expected: [{ type: 'blockquote', children: [
      paragraph([text('说明')]),
      { type: 'ul', children: [listItem([
        paragraph([text('项目 '), { type: 'latex', block: false, text: 'x_n', children: [text('x_n')] }]),
        { type: 'ul', children: [listItem([paragraph([text('子项')])])] }
      ])] }
    ] }]
  },
  {
    name: '表格对齐和组合行内语法',
    input: '| 左 | 中 | 右 |\n| :-- | :-: | --: |\n| **粗体** | [链接](https://example.com) `a|b` | $x_n$ |',
    expected: [{
      tableId: 0, type: 'table', align: ['left', 'center', 'right'],
      rawMarkdown: '| 左 | 中 | 右 |\n| :-- | :-: | --: |\n| **粗体** | [链接](https://example.com) `a|b` | $x_n$ |',
      header: [cell([paragraph([text('左')])]), cell([paragraph([text('中')])]), cell([paragraph([text('右')])])],
      rows: [{ type: 'tableRow', children: [
        cell([{ type: 'bold', children: [text('粗体')] }]),
        cell([{ type: 'link', url: 'https://example.com', children: [text('链接')] }, text(' '), { type: 'inlineCode', text: 'a|b' }]),
        cell([{ type: 'latex', block: false, text: 'x_n', children: [text('x_n')] }])
      ] }]
    }]
  },
  {
    name: '表格空单元格补齐', input: '| A | B | C |\n| - | - | - |\n| 1 | |',
    expected: [{
      tableId: 0, type: 'table', align: ['none', 'none', 'none'],
      rawMarkdown: '| A | B | C |\n| - | - | - |\n| 1 | |',
      header: [cell([paragraph([text('A')])]), cell([paragraph([text('B')])]), cell([paragraph([text('C')])])],
      rows: [{ type: 'tableRow', children: [cell([text('1')]), cell([]), cell([])] }]
    }]
  },
  {
    name: '表格原始 Markdown 保留转义和续行',
    input: '| Key | Value |\n| --- | --- |\n| pipe \\| value | first\ncontinued |',
    expected: [{
      tableId: 0, type: 'table', align: ['none', 'none'],
      rawMarkdown: '| Key | Value |\n| --- | --- |\n| pipe \\| value | first\ncontinued |',
      header: [cell([paragraph([text('Key')])]), cell([paragraph([text('Value')])])],
      rows: [{ type: 'tableRow', children: [
        cell([text('pipe | value')]),
        cell([text('first\ncontinued')])
      ] }]
    }]
  },
  {
    name: '表格原始 Markdown 将 CRLF 标准化为 LF',
    input: '| A |\r\n| - |\r\n| 1 |',
    expected: [{
      tableId: 0, type: 'table', align: ['none'], rawMarkdown: '| A |\n| - |\n| 1 |',
      header: [cell([paragraph([text('A')])])], rows: [{ type: 'tableRow', children: [cell([text('1')])] }]
    }]
  },
  {
    name: '异常表头与分隔行列数不一致时降级为段落',
    input: '| 姓名 | ____________________ | 参加工作时间 | ____________ 年 _______ 月 | 岗位（职务） | ____________________ |\n|------|----------------------|--------------|---------------------------|--------------',
    expected: [paragraph([text('| 姓名 | ____________________ | 参加工作时间 | ____________ 年 _______ 月 | 岗位（职务） | ____________________ |\n|------|----------------------|--------------|---------------------------|--------------')])]
  },
  {
    name: '六列表头与分隔行一致且无数据行时生成空表',
    input: '| 姓名 | ____________________ | 参加工作时间 | ____________ 年 _______ 月 | 岗位（职务） | ____________________ |\n|------|----------------------|--------------|---------------------------|--------------|----------------------|',
    expected: [{
      tableId: 0,
      type: 'table',
      rawMarkdown: '| 姓名 | ____________________ | 参加工作时间 | ____________ 年 _______ 月 | 岗位（职务） | ____________________ |\n|------|----------------------|--------------|---------------------------|--------------|----------------------|',
      header: [
        cell([paragraph([text('姓名')])]),
        cell([paragraph([text('____________________')])]),
        cell([paragraph([text('参加工作时间')])]),
        cell([paragraph([text('____________ 年 _______ 月')])]),
        cell([paragraph([text('岗位（职务）')])]),
        cell([paragraph([text('____________________')])])
      ],
      align: ['none', 'none', 'none', 'none', 'none', 'none'],
      rows: []
    }]
  },
  {
    name: '表格数据行少列补空且多列截断',
    input: '| A | B | C |\n| - | - | - |\n| 1 | 2 |\n| 3 | 4 | 5 | 6 |',
    expected: [{
      tableId: 0,
      type: 'table',
      rawMarkdown: '| A | B | C |\n| - | - | - |\n| 1 | 2 |\n| 3 | 4 | 5 | 6 |',
      header: [
        cell([paragraph([text('A')])]),
        cell([paragraph([text('B')])]),
        cell([paragraph([text('C')])])
      ],
      align: ['none', 'none', 'none'],
      rows: [
        { type: 'tableRow', children: [cell([text('1')]), cell([text('2')]), cell([])] },
        { type: 'tableRow', children: [cell([text('3')]), cell([text('4')]), cell([text('5')])] }
      ]
    }]
  },
  {
    name: '空表头与空数据行保持空单元格',
    input: '| | B |\n| - | - |\n| | |',
    expected: [{
      tableId: 0,
      type: 'table',
      rawMarkdown: '| | B |\n| - | - |\n| | |',
      header: [cell([]), cell([paragraph([text('B')])])],
      align: ['none', 'none'],
      rows: [{ type: 'tableRow', children: [cell([]), cell([])] }]
    }]
  },
  {
    name: '代码块闭合和内容不二次解析', input: '```ts\nconst value = "**not bold**";\n```',
    expected: [{ type: 'codeBlock', lang: 'ts', text: 'const value = "**not bold**";', closed: true }]
  },
  {
    name: '未闭合代码块', input: '```js\nconst value = 1;',
    expected: [{ type: 'codeBlock', lang: 'js', text: 'const value = 1;', closed: false }]
  },
  {
    name: '公式分隔符和金额冲突',
    input: '$x_n$ $$E=mc^2$$ \\(a+b\\) \\[c=d\\] $120 $12.5k',
    expected: [paragraph([
      { type: 'latex', block: false, text: 'x_n', children: [text('x_n')] }, text(' '),
      { type: 'latex', block: true, text: 'E=mc^2', children: [text('E=mc^2')] }, text(' '),
      { type: 'latex', block: false, text: 'a+b', children: [text('a+b')] }, text(' '),
      { type: 'latex', block: true, text: 'c=d', children: [text('c=d')] }, text(' $120 $12.5k')
    ])]
  },
  {
    name: '脚注引用与组合正文',
    input: '正文[^note]\n\n[^note]: **重点** [链接](https://example.com)\n    - 子项',
    expected: [
      paragraph([text('正文'), { type: 'footnoteRef', id: 'note' }]),
      { type: 'footnotes', children: [{ id: 'note', children: [
        paragraph([{ type: 'bold', children: [text('重点')] }, text(' '), { type: 'link', url: 'https://example.com', children: [text('链接')] }]),
        { type: 'ul', children: [listItem([paragraph([text('子项')])])] }
      ] }] }
    ]
  },
  {
    name: '行内与块级插件组合',
    input: '# 插件\n\n正文 [ref_42] **粗体** [链接](https://example.com)\n\n<chart:sales>',
    plugins: [inlinePlugin, blockPlugin],
    expected: [
      { type: 'heading', level: 1, children: [text('插件')] },
      paragraph([
        text('正文 '),
        { type: 'plugin', pluginKey: 'ref', display: 'inline', raw: '[ref_42]', params: { id: '42' }, groups: ['42'], copyText: '[ref_42]', selectable: true },
        text(' '), { type: 'bold', children: [text('粗体')] }, text(' '),
        { type: 'link', url: 'https://example.com', children: [text('链接')] }
      ]),
      { type: 'plugin', pluginKey: 'chart', display: 'block', raw: '<chart:sales>', params: { name: 'sales' }, groups: ['sales'], copyText: '<chart:sales>', selectable: false }
    ]
  },
  {
    name: '无效插件正则降级为文本', input: '[bad]',
    plugins: [{ key: 'bad', display: 'inline', pattern: '[', matchMode: 'inline-prefix' }],
    expected: [paragraph([text('[bad]')])]
  },
  {
    name: '未闭合语法稳定降级', input: '**粗体 *斜体 `代码 [链接](url ![图片](img $$公式',
    expected: [paragraph([text('**粗体 *斜体 `代码 [链接](url ![图片](img $$公式')])]
  },
  {
    name: '代码块后表格公式段落组合',
    input: '```js\nlet n = 1;\n```\n\n| A |\n| - |\n| 1 |\n\n$$x_n=n$$\n\n结束',
    expected: [
      { type: 'codeBlock', lang: 'js', text: 'let n = 1;', closed: true },
      { tableId: 0, type: 'table', align: ['none'], rawMarkdown: '| A |\n| - |\n| 1 |', header: [cell([paragraph([text('A')])])], rows: [{ type: 'tableRow', children: [cell([text('1')])] }] },
      paragraph([{ type: 'latex', block: true, text: 'x_n=n', children: [text('x_n=n')] }]), paragraph([text('结束')])
    ]
  },
  {
    name: 'CRLF 空行和特殊字符完整文档',
    input: '# 标题\r\n\r\n普通 < > & 内容\r\n\r\n- A\r\n- B',
    expected: [
      { type: 'heading', level: 1, children: [text('标题')] }, paragraph([text('普通 < > & 内容')]),
      { type: 'ul', children: [listItem([paragraph([text('A')])]), listItem([paragraph([text('B')])])] }
    ]
  },
  {
    name: '深层引用输入不崩溃', input: `${'> '.repeat(40)}深层内容`,
    expected: (() => {
      let node = paragraph([text('深层内容')]);
      for (let i = 0; i < 40; i++) node = { type: 'blockquote', children: [node] };
      return [node];
    })()
  }
];
