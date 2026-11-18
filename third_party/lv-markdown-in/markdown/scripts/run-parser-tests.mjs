/**
 * 用途：
 *   提供 Markdown 解析测试的一键执行入口，并汇总各测试脚本结果。
 *
 * 覆盖场景：
 *   默认执行 AST 全语法测试和 HTML 转换测试；传入 --with-benchmark 时额外执行大文档性能测试。
 *
 * 如何验证：
 *   执行 node markdown/scripts/run-parser-tests.mjs。所有子脚本返回 0 时输出汇总并返回 0；
 *   任一子脚本失败时保留其错误信息、输出失败汇总并返回非零状态。
 */

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const scriptDirectory = fileURLToPath(new URL('.', import.meta.url));
const withBenchmark = process.argv.includes('--with-benchmark');
const scripts = ['test-markdown-ast.mjs', 'test-html-to-markdown.mjs'];
if (withBenchmark) scripts.push('benchmark-parser.mjs');

let failed = 0;
for (const script of scripts) {
  console.log(`\n=== ${script} ===`);
  const result = spawnSync(process.execPath, [`${scriptDirectory}${script}`], {
    stdio: 'inherit', windowsHide: true
  });
  if (result.error) {
    failed++;
    console.error(result.error);
  } else if (result.status !== 0) {
    failed++;
  }
}

console.log(`\n解析验证汇总: 脚本 ${scripts.length - failed} 通过，${failed} 失败`);
if (failed > 0) process.exitCode = 1;
