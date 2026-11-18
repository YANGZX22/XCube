/**
 * 用途：
 *   建立大 Markdown 文档的解析性能基线，发现明显的耗时和内存退化。
 *
 * 覆盖场景：
 *   100 KB、1 MB、5 MB 混合 Markdown 文档，包含标题、段落、列表、表格、代码块、链接和公式。
 *
 * 如何验证：
 *   执行 node markdown/scripts/benchmark-parser.mjs。每档数据预热后重复解析，输出中位数、P95、
 *   最小值、最大值、AST 节点数和堆内存变化；解析无异常且 AST 非空即视为完成。
 *   本脚本不设置固定耗时门槛，结果仅用于同一环境下的版本对比。
 */

import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { loadRequiredExport } from './lib/load-source-module.mjs';

const parseMarkdown = await loadRequiredExport(
  new URL('../src/main/ets/enhance/utils/ast.js', import.meta.url), 'parseMarkdown'
);

const sizes = [
  { name: '100 KB', bytes: 100 * 1024, iterations: 10 },
  { name: '1 MB', bytes: 1024 * 1024, iterations: 5 },
  { name: '5 MB', bytes: 5 * 1024 * 1024, iterations: 3 }
];

const mixedBlock = `# 性能测试标题

这是包含 **粗体**、[链接](https://example.com)、行内公式 $x_n$ 和 \`code\` 的固定段落。

- 列表项目 A
- 列表项目 B
  - 嵌套项目

| 名称 | 数值 | 说明 |
| :-- | --: | :-: |
| alpha | 100 | **稳定** |
| beta | 200 | $y_n$ |

\`\`\`js
const value = 1;
console.log(value);
\`\`\`

$$E=mc^2$$

`;

function buildDocument(targetBytes) {
  let output = '';
  let index = 0;
  while (Buffer.byteLength(output, 'utf8') < targetBytes) {
    output += `${mixedBlock}<!-- block-${index++} -->\n\n`;
  }
  return output;
}

function percentile(values, ratio) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * ratio) - 1)];
}

console.log('Markdown AST 解析性能基线（无固定阈值）');
for (const size of sizes) {
  const document = buildDocument(size.bytes);
  for (let i = 0; i < 2; i++) parseMarkdown(document, [], {});

  const durations = [];
  const nodeCounts = [];
  const beforeHeap = process.memoryUsage().heapUsed;
  for (let i = 0; i < size.iterations; i++) {
    const started = performance.now();
    const ast = parseMarkdown(document, [], {});
    durations.push(performance.now() - started);
    assert.ok(Array.isArray(ast) && ast.length > 0, `${size.name} AST 不能为空`);
    nodeCounts.push(ast.length);
  }
  const afterHeap = process.memoryUsage().heapUsed;
  assert.equal(new Set(nodeCounts).size, 1, `${size.name} 多次解析的顶层节点数必须稳定`);

  const sorted = [...durations].sort((a, b) => a - b);
  const median = percentile(sorted, 0.5);
  const p95 = percentile(sorted, 0.95);
  const heapDeltaMb = (afterHeap - beforeHeap) / 1024 / 1024;
  console.log(
    `${size.name.padEnd(6)} | ${(Buffer.byteLength(document) / 1024).toFixed(1)} KB | ` +
    `节点 ${nodeCounts[0]} | 中位数 ${median.toFixed(2)} ms | P95 ${p95.toFixed(2)} ms | ` +
    `最小 ${sorted[0].toFixed(2)} ms | 最大 ${sorted.at(-1).toFixed(2)} ms | ` +
    `堆变化 ${heapDeltaMb.toFixed(2)} MB`
  );
}
