/**
 * 用途：
 *   在不修改工程模块配置的情况下，加载使用 ESM export 语法的生产 JavaScript 源码。
 *
 * 覆盖场景：
 *   加载 ast.js 和 html2md.js，供 Node 测试脚本直接调用生产函数。
 *
 * 如何验证：
 *   由主测试脚本间接验证。模块必须成功加载 parseMarkdown 和 htmlToMarkdown；
 *   导出缺失或源码加载失败时立即抛错并终止测试。
 */

import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const moduleCache = new Map();

export async function loadSourceModule(sourcePath) {
  const sourceUrl = sourcePath instanceof URL ? sourcePath : pathToFileURL(sourcePath);
  const cacheKey = sourceUrl.href;
  if (moduleCache.has(cacheKey)) {
    return moduleCache.get(cacheKey);
  }

  const source = await readFile(sourceUrl, 'utf8');
  const encoded = Buffer.from(`${source}\n//# sourceURL=${sourceUrl.href}\n`, 'utf8').toString('base64');
  const loaded = import(`data:text/javascript;base64,${encoded}`);
  moduleCache.set(cacheKey, loaded);
  return loaded;
}

export async function loadRequiredExport(sourcePath, exportName) {
  const loaded = await loadSourceModule(sourcePath);
  const exported = loaded[exportName];
  if (typeof exported !== 'function') {
    throw new TypeError(`生产源码缺少函数导出 ${exportName}: ${sourcePath}`);
  }
  return exported;
}
