/**
 * 用途：
 *   提供 AST 标准化、深度比较、差异定位、结果统计和失败输出能力。
 *
 * 覆盖场景：
 *   对象、数组、基本类型、缺失字段、undefined 字段及嵌套 AST。
 *
 * 如何验证：
 *   由 AST 和 HTML 主测试脚本使用；runUtilitySelfCheck() 会确认相同对象比较通过，
 *   不同对象能够返回准确的首个差异路径。
 */

import assert from 'node:assert/strict';
import { inspect } from 'node:util';

export function normalizeValue(value) {
  if (Array.isArray(value)) {
    return value.map(normalizeValue);
  }
  if (value && typeof value === 'object') {
    const normalized = {};
    for (const key of Object.keys(value)) {
      if (value[key] !== undefined) {
        normalized[key] = normalizeValue(value[key]);
      }
    }
    return normalized;
  }
  return value;
}

export function findFirstDifference(expected, actual, path = '$') {
  if (Object.is(expected, actual)) {
    return null;
  }
  if (Array.isArray(expected) || Array.isArray(actual)) {
    if (!Array.isArray(expected) || !Array.isArray(actual)) {
      return { path, expected, actual };
    }
    if (expected.length !== actual.length) {
      return { path: `${path}.length`, expected: expected.length, actual: actual.length };
    }
    for (let i = 0; i < expected.length; i++) {
      const diff = findFirstDifference(expected[i], actual[i], `${path}[${i}]`);
      if (diff) return diff;
    }
    return null;
  }
  if (expected && actual && typeof expected === 'object' && typeof actual === 'object') {
    const expectedKeys = Object.keys(expected).sort();
    const actualKeys = Object.keys(actual).sort();
    if (expectedKeys.length !== actualKeys.length || expectedKeys.some((key, i) => key !== actualKeys[i])) {
      return { path: `${path}.[keys]`, expected: expectedKeys, actual: actualKeys };
    }
    for (const key of expectedKeys) {
      const diff = findFirstDifference(expected[key], actual[key], `${path}.${key}`);
      if (diff) return diff;
    }
    return null;
  }
  return { path, expected, actual };
}

export function compareValues(expected, actual) {
  const normalizedExpected = normalizeValue(expected);
  const normalizedActual = normalizeValue(actual);
  try {
    assert.deepStrictEqual(normalizedActual, normalizedExpected);
    return { pass: true, expected: normalizedExpected, actual: normalizedActual, difference: null };
  } catch {
    return {
      pass: false,
      expected: normalizedExpected,
      actual: normalizedActual,
      difference: findFirstDifference(normalizedExpected, normalizedActual)
    };
  }
}

export function normalizeMarkdown(text) {
  return String(text).replace(/\r\n?/g, '\n').replace(/[ \t]+$/gm, '').trimEnd();
}

export function formatValue(value) {
  return inspect(value, { depth: null, colors: false, compact: false, maxArrayLength: null, breakLength: 100 });
}

export function printFailure({ suite, name, stage, input, comparison }) {
  const diff = comparison.difference || { path: '$', expected: comparison.expected, actual: comparison.actual };
  console.error(`\n[失败] ${suite} / ${name} / ${stage}`);
  console.error(`输入:\n${input}`);
  console.error(`首个差异: ${diff.path}`);
  console.error(`预期值: ${formatValue(diff.expected)}`);
  console.error(`实际值: ${formatValue(diff.actual)}`);
  console.error(`完整预期:\n${formatValue(comparison.expected)}`);
  console.error(`完整实际:\n${formatValue(comparison.actual)}`);
}

export function assertUniqueCaseNames(cases, suiteName) {
  const names = new Set();
  for (const testCase of cases) {
    if (!testCase.name || !Object.hasOwn(testCase, 'input') || !Object.hasOwn(testCase, 'expected')) {
      throw new TypeError(`${suiteName} 用例必须包含 name、input 和 expected: ${formatValue(testCase)}`);
    }
    if (names.has(testCase.name)) {
      throw new Error(`${suiteName} 存在重复用例名称: ${testCase.name}`);
    }
    names.add(testCase.name);
  }
}

export function runUtilitySelfCheck() {
  const same = compareValues({ a: [1, { b: undefined, c: 'ok' }] }, { a: [1, { c: 'ok' }] });
  assert.equal(same.pass, true, '标准化后的相同对象应比较通过');
  const different = compareValues({ a: [{ value: 1 }] }, { a: [{ value: 2 }] });
  assert.equal(different.pass, false, '不同对象不应比较通过');
  assert.equal(different.difference.path, '$.a[0].value', '应返回首个准确差异路径');
}

export function printSuiteSummary(suiteName, passed, failed) {
  console.log(`${suiteName}: 通过 ${passed}，失败 ${failed}`);
}
