/**
 * 用途：
 *   直接调用生产环境 parseMarkdown()，验证 Markdown 文本生成的 AST 节点树是否正确。
 *
 * 覆盖场景：
 *   基础块级语法、行内语法、列表、表格、代码块、公式、脚注、插件、异常输入、
 *   递归保护，以及多种语法嵌套和组合场景。
 *
 * 如何验证：
 *   执行 node markdown/scripts/test-markdown-ast.mjs。脚本将实际 AST 与用例中的预期 AST
 *   完整深度比较；失败时输出输入、差异字段路径、预期值和实际值，并返回非零状态。
 */

import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { astCases } from './cases/ast-cases.mjs';
import { loadRequiredExport } from './lib/load-source-module.mjs';
import {
  assertUniqueCaseNames, compareValues, printFailure, printSuiteSummary, runUtilitySelfCheck
} from './lib/test-utils.mjs';

const astSource = new URL('../src/main/ets/enhance/utils/ast.js', import.meta.url);
const parseMarkdown = await loadRequiredExport(astSource, 'parseMarkdown');

runUtilitySelfCheck();
assertUniqueCaseNames(astCases, 'AST');

const getSurfaceBlocks = await loadRequiredExport(astSource, 'getMarkdownSurfaceBlocks');
const figure = '![Figure](xcube-image://python_img_example)';
const code = ['~~~~md', figure, '~~~', '~~~~'].join('\n');
const table = '| A | B |\n| --- | --- |\n| 1 | 2 |';
const preview = ['Before', figure, code, table, 'After'].join('\n\n');
assert.deepEqual(getSurfaceBlocks(preview).map(block => [block.kind, block.source.trim()]), [
  ['', 'Before'], ['image', figure], ['code', code], ['table', table], ['', 'After']
]);
assert.deepEqual(getSurfaceBlocks('~~~~py\nprint(1)'), [{ kind: 'code', source: '~~~~py\nprint(1)' }]);
assert.deepEqual(getSurfaceBlocks('`' + figure + '` and an ordinary | pipe'), []);
const withFootnote = preview + '\n\nSee [^n].\n\n[^n]: Note.';
assert.deepEqual(getSurfaceBlocks(withFootnote), [{ kind: 'document', source: withFootnote }]);

let passed = 0;
let failed = 0;
for (const testCase of astCases) {
  try {
    const actual = parseMarkdown(testCase.input, testCase.plugins ?? [], testCase.options ?? {});
    const comparison = compareValues(testCase.expected, actual);
    if (comparison.pass) {
      passed++;
    } else {
      failed++;
      printFailure({
        suite: 'AST', name: testCase.name, stage: 'Markdown → AST', input: testCase.input, comparison
      });
    }
  } catch (error) {
    failed++;
    console.error(`\n[异常] AST / ${testCase.name}`);
    console.error(`输入:\n${testCase.input}`);
    console.error(error?.stack || error);
  }
}

printSuiteSummary('AST', passed, failed);
if (failed > 0) process.exitCode = 1;

export const result = { suite: 'AST', passed, failed, source: fileURLToPath(astSource) };
