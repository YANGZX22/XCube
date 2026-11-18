/**
 * 用途：
 *   验证生产环境 htmlToMarkdown() 的 HTML 转换结果，并验证转换后的 Markdown 是否生成正确 AST。
 *
 * 覆盖场景：
 *   HTML 标题、段落、换行、行内样式、链接、图片、列表、引用、表格、代码、font、
 *   HTML 实体、混合内容和异常标签。
 *
 * 如何验证：
 *   执行 node markdown/scripts/test-html-to-markdown.mjs。第一阶段比较转换 Markdown，第二阶段比较完整 AST；
 *   失败时输出阶段、用例名称和首个差异路径，并返回非零状态。
 *
 * 限制：
 *   本脚本验证 HTML 转换函数及转换后的 AST，不验证生产链路是否正确判断当前文本需要执行 HTML 转换。
 */

import { htmlCases, htmlRiskCases } from './cases/html-cases.mjs';
import { loadRequiredExport } from './lib/load-source-module.mjs';
import {
  assertUniqueCaseNames, compareValues, normalizeMarkdown, printFailure, printSuiteSummary, runUtilitySelfCheck
} from './lib/test-utils.mjs';

const htmlToMarkdown = await loadRequiredExport(
  new URL('../src/main/ets/enhance/utils/html2md.js', import.meta.url), 'htmlToMarkdown'
);
const parseMarkdown = await loadRequiredExport(
  new URL('../src/main/ets/enhance/utils/ast.js', import.meta.url), 'parseMarkdown'
);

runUtilitySelfCheck();
const allCases = [...htmlCases, ...htmlRiskCases];
assertUniqueCaseNames(allCases, 'HTML');

let passed = 0;
let failed = 0;
for (const testCase of allCases) {
  try {
    const actualMarkdown = normalizeMarkdown(htmlToMarkdown(testCase.input));
    const markdownComparison = compareValues(normalizeMarkdown(testCase.expectedMarkdown), actualMarkdown);
    if (!markdownComparison.pass) {
      failed++;
      printFailure({
        suite: 'HTML', name: testCase.name, stage: 'HTML → Markdown', input: testCase.input,
        comparison: markdownComparison
      });
      continue;
    }

    const actualAst = parseMarkdown(actualMarkdown, [], {});
    const astComparison = compareValues(testCase.expected, actualAst);
    if (!astComparison.pass) {
      failed++;
      printFailure({
        suite: 'HTML', name: testCase.name, stage: 'HTML → Markdown → AST', input: testCase.input,
        comparison: astComparison
      });
    } else {
      passed++;
    }
  } catch (error) {
    failed++;
    console.error(`\n[异常] HTML / ${testCase.name}`);
    console.error(`输入:\n${testCase.input}`);
    console.error(error?.stack || error);
  }
}

printSuiteSummary('HTML', passed, failed);
if (failed > 0) process.exitCode = 1;

export const result = { suite: 'HTML', passed, failed };
