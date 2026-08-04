import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { parseMarkdown } from '../main/ets/enhance/utils/ast';
import { isHtmlLike } from '../main/ets/enhance/utils/HtmlDetectionUtil';

function parse(markdown: string): ESObject[] {
  return parseMarkdown(markdown, [], {}) as ESObject[];
}

function childrenOf(node: ESObject): ESObject[] {
  return (node.children ?? []) as ESObject[];
}

function expectNodeType(node: ESObject, type: string): void {
  expect(node.type).assertEqual(type);
}

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('keeps block latex inside ordered list item', 0, () => {
      const tree = parse([
        '1. alpha',
        '   $$',
        '   x_n = n',
        '   $$',
        '2. beta'
      ].join('\n'));

      expect(tree.length).assertEqual(1);
      const list = tree[0];
      expectNodeType(list, 'ol');
      expect(childrenOf(list).length).assertEqual(2);

      const firstItem = childrenOf(list)[0];
      expect(childrenOf(firstItem).length).assertEqual(2);
      const latexParagraph = childrenOf(firstItem)[1];
      expectNodeType(latexParagraph, 'paragraph');

      const latexNode = childrenOf(latexParagraph)[0];
      expectNodeType(latexNode, 'latex');
      expect(latexNode.block).assertEqual(true);
      expect(latexNode.text).assertEqual('x_n = n');
    });

    it('keeps ordered list numbering after nested list and block latex', 0, () => {
      const tree = parse([
        '1. first',
        '2. second',
        '   - nested',
        '   $$',
        '   I = \\int_0^1 x dx',
        '   $$',
        '3. third'
      ].join('\n'));

      expect(tree.length).assertEqual(1);
      const list = tree[0];
      expectNodeType(list, 'ol');
      expect(childrenOf(list).length).assertEqual(3);

      const secondItem = childrenOf(list)[1];
      expect(childrenOf(secondItem).length).assertEqual(3);
      expectNodeType(childrenOf(secondItem)[1], 'ul');

      const latexParagraph = childrenOf(secondItem)[2];
      expectNodeType(latexParagraph, 'paragraph');
      const latexNode = childrenOf(latexParagraph)[0];
      expectNodeType(latexNode, 'latex');
      expect(latexNode.block).assertEqual(true);
      expect(latexNode.text).assertEqual('I = \\int_0^1 x dx');
    });

    it('keeps table continuation inside list item', 0, () => {
      const tree = parse([
        '- item',
        '  | A | B |',
        '  | - | - |',
        '  | 1 | 2 |',
        '- next'
      ].join('\n'));

      expect(tree.length).assertEqual(1);
      const list = tree[0];
      expectNodeType(list, 'ul');
      expect(childrenOf(list).length).assertEqual(2);

      const firstItem = childrenOf(list)[0];
      expect(childrenOf(firstItem).length).assertEqual(2);
      const table = childrenOf(firstItem)[1];
      expectNodeType(table, 'table');
      expect((table.header as ESObject[]).length).assertEqual(2);
      expect((table.rows as ESObject[]).length).assertEqual(1);
    });

    it('keeps ordinary nested list structure', 0, () => {
      const tree = parse([
        '- parent',
        '  - child',
        '- next'
      ].join('\n'));

      expect(tree.length).assertEqual(1);
      const list = tree[0];
      expectNodeType(list, 'ul');
      expect(childrenOf(list).length).assertEqual(2);

      const parentItem = childrenOf(list)[0];
      expect(childrenOf(parentItem).length).assertEqual(2);
      const nestedList = childrenOf(parentItem)[1];
      expectNodeType(nestedList, 'ul');
      expect(childrenOf(nestedList).length).assertEqual(1);
    });

    it('keeps inline latex as inline node in list item', 0, () => {
      const tree = parse([
        '- inline $x_n$ value',
        '- next'
      ].join('\n'));

      const list = tree[0];
      const firstParagraph = childrenOf(childrenOf(list)[0])[0];
      const inlineNodes = childrenOf(firstParagraph);
      expectNodeType(inlineNodes[1], 'latex');
      expect(inlineNodes[1].block).assertEqual(false);
      expect(inlineNodes[1].text).assertEqual('x_n');
    });

    it('recognizes indented tilde fence and language token', 0, () => {
      const tree = parse([
        '  ~~~~typescript title=sample',
        '  const value = 1',
        '  ~~~~'
      ].join('\n'));

      expect(tree.length).assertEqual(1);
      expectNodeType(tree[0], 'codeBlock');
      expect(tree[0].lang).assertEqual('typescript');
      expect(tree[0].text).assertEqual('const value = 1');
      expect(tree[0].closed).assertEqual(true);
    });

    it('does not close a long fence with a shorter marker', 0, () => {
      const tree = parse([
        '````markdown',
        '```',
        'inside',
        '````'
      ].join('\n'));

      expect(tree.length).assertEqual(1);
      expectNodeType(tree[0], 'codeBlock');
      expect(tree[0].text).assertEqual('```\ninside');
      expect(tree[0].closed).assertEqual(true);
    });

    it('keeps fenced code inside a list item', 0, () => {
      const tree = parse([
        '- example',
        '  ```ts',
        '  const value = 1',
        '  ```',
        '- next'
      ].join('\n'));

      expect(tree.length).assertEqual(1);
      const firstItem = childrenOf(tree[0])[0];
      expect(childrenOf(firstItem).length).assertEqual(2);
      const codeBlock = childrenOf(firstItem)[1];
      expectNodeType(codeBlock, 'codeBlock');
      expect(codeBlock.lang).assertEqual('ts');
      expect(codeBlock.text).assertEqual('const value = 1');
      expect(codeBlock.closed).assertEqual(true);
    });

    it('ignores HTML tags inside Markdown code', 0, () => {
      const markdown = [
        'before',
        '```html',
        '<div>code</div>',
        '```',
        'after'
      ].join('\n');

      expect(isHtmlLike(markdown)).assertEqual(false);
      expect(isHtmlLike('Use `<div>` as text')).assertEqual(false);
      expect(isHtmlLike('<div>real HTML</div>')).assertEqual(true);
    });

    it('keeps multiple fenced blocks with mixed leading whitespace', 0, () => {
      const tree = parse([
        '```python',
        'print("first")',
        '```',
        '运行后会输出：',
        '\t\u00A0\u200B```',
        '# Python 简单示例',
        '<div>code output</div>',
        '\uFEFF　```',
        '后续正文'
      ].join('\n'));

      expect(tree.length).assertEqual(4);
      expectNodeType(tree[0], 'codeBlock');
      expect(tree[0].lang).assertEqual('python');
      expect(tree[0].closed).assertEqual(true);
      expectNodeType(tree[1], 'paragraph');
      expectNodeType(tree[2], 'codeBlock');
      expect(tree[2].lang).assertEqual(null);
      expect(tree[2].text).assertEqual('# Python 简单示例\n<div>code output</div>');
      expect(tree[2].closed).assertEqual(true);
      expectNodeType(tree[3], 'paragraph');
      expect(isHtmlLike([
        '\t\u00A0```html',
        '<div>inside code</div>',
        '　```'
      ].join('\n'))).assertEqual(false);
    });
  });
}
