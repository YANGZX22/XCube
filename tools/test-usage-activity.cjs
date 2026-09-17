// Tests production usage queries and range controls with synthetic data only.
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { DatabaseSync } = require('node:sqlite');
const ts = require(process.env.XCUBE_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
const root = path.resolve(__dirname, '..');
const cases = [];
const originalLoad = Module._load;
Module._load = function(request, parent, isMain) {
  if (request === '@ohos/hypium') return {
    describe: (_name, fn) => fn(),
    it: (name, _timeout, fn) => cases.push({ name, fn }),
    expect: actual => ({
      assertEqual: expected => assert.strictEqual(actual, expected),
      assertTrue: () => assert.strictEqual(actual, true),
      assertFalse: () => assert.strictEqual(actual, false)
    })
  };
  return originalLoad.apply(this, arguments);
};
function transpile(source, filename) {
  return ts.transpileModule(source, {
    fileName: filename.replace(/\.ets$/, '.ts'),
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS }
  }).outputText;
}
Module._extensions['.ets'] = (module, filename) => module._compile(transpile(fs.readFileSync(filename, 'utf8'), filename), filename);
require(path.join(root, 'entry/src/test/UsageActivity.test.ets')).default();
const activity = require(path.join(root, 'entry/src/main/ets/utils/UsageActivityUtils.ets'));
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/DatabaseService.ets'), 'utf8');
const parsed = ts.createSourceFile('DatabaseService.ts', source, ts.ScriptTarget.Latest, true);
const dbClass = parsed.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'DatabaseService');
const methods = ['collectMessageUsageRows', 'getDailyUsageActivity', 'getUsageBillingSummary',
  'getModelUsageRanking', 'buildModelUsageRankingFromRows', 'isValidUsageModelName',
  'safeGetString', 'safeGetLong', 'safeGetDouble'].map(name => {
  const method = dbClass.members.find(member => member.name?.getText(parsed) === name);
  assert.ok(method, `Missing method ${name}`);
  return method.getText(parsed);
});
const context = vm.createContext({
  aggregateDailyUsageActivity: activity.aggregateDailyUsageActivity,
  MessageRole: { ASSISTANT: 'assistant' },
  TableNames: { SESSIONS: 'chat_sessions', MESSAGES: 'messages' }, exports: {}
});
vm.runInContext(transpile(`export class UsageDatabase {
  rdbStore = null;
  async waitForInitialization() {}
  ${methods.join('\n')}
}`, 'usage.ts'), context);
const service = new context.exports.UsageDatabase();

// Extract the page's non-rendering logic so range tests execute the production methods.
const pageSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/UsageStatsPage.ets'), 'utf8');
const pageStart = pageSource.indexOf('struct UsageStatsPage {');
const buildersStart = pageSource.indexOf('\n  @Builder', pageStart);
assert.ok(pageStart >= 0 && buildersStart > pageStart);
const declarations = pageSource.slice(pageSource.indexOf('const TAG'), pageSource.indexOf('\n@ComponentV2'));
const pageLogic = pageSource.slice(pageStart, buildersStart)
  .replace('struct UsageStatsPage', 'export class UsageStatsPage').replace(/@Local\s+/g, '');
const now = new Date(2026, 8, 17, 12, 30).getTime();
const dayMs = 24 * 60 * 60 * 1000;
const pageContext = vm.createContext({
  exports: {}, Scroller: class {}, Date: { now: () => now }, console,
  Curve: { EaseInOut: 'ease-in-out', EaseOut: 'ease-out' }
});
vm.runInContext(transpile(`${declarations}\n${pageLogic}\n}`, 'usage-page.ts'), pageContext);
function createPage() {
  const page = new pageContext.exports.UsageStatsPage();
  page.getUIContext = () => ({ animateTo: (_options, update) => update() });
  page.startRankingAnimation = () => {};
  return page;
}

cases.push({ name: 'ALL / 7 DAYS / 30 DAYS map to distinct ranges and independent scroll positions', fn: () => {
  const page = createPage();
  const ranges = ['all', 'last_7d', 'last_30d'];
  const starts = [0, now - 7 * dayMs, now - 30 * dayMs];
  const scrollers = new Set();
  ranges.forEach((range, index) => {
    page.currentRange = range;
    assert.equal(page.getCurrentRangeIndex(), index);
    assert.equal(page.getRangeByIndex(index), range);
    assert.equal(page.getRangeStartMs(), starts[index]);
    const scroller = page.getRangeScroller(range);
    assert.equal(page.getRangeScroller(range), scroller);
    scrollers.add(scroller);
  });
  assert.equal(scrollers.size, 3);
  for (const index of [-1, 3, 100]) assert.equal(page.getRangeByIndex(index), 'all');
  for (const locale of ['base', 'zh_CN']) {
    const resources = JSON.parse(fs.readFileSync(path.join(root, `entry/src/main/resources/${locale}/element/string.json`), 'utf8'));
    const labels = ['all', '7d', '30d'].map(key => resources.string.find(item => item.name === `usage_stats_range_${key}`).value);
    assert.deepEqual(labels, locale === 'zh_CN' ? ['全部', '近 7 天', '近 30 天'] : ['ALL', '7 DAYS', '30 DAYS']);
  }
}});

cases.push({ name: 'range swipes advance one tab and stop at both ends', fn: () => {
  const page = createPage();
  const ranges = ['all', 'last_7d', 'last_30d'];
  ranges.forEach((range, index) => {
    page.currentRange = range;
    assert.equal(page.getRangeBySwipeOffset(-72), ranges[index + 1] ?? null);
    assert.equal(page.getRangeBySwipeOffset(72), ranges[index - 1] ?? null);
    assert.equal(page.getRangeBySwipeOffset(-71), null);
    assert.equal(page.getRangeBySwipeOffset(71), null);
    assert.ok(Math.abs(page.getDampedRangeSwipeOffset(10000)) <= 44);
    assert.ok(Math.abs(page.getDampedRangeSwipeOffset(-10000)) <= 44);
  });
  page.currentRange = 'last_7d';
  assert.equal(page.getDampedRangeSwipeOffset(72), -page.getDampedRangeSwipeOffset(-72));
}});

cases.push({ name: 'range changes reload once and heatmap gestures do not change tabs', fn: () => {
  const page = createPage();
  let loads = 0;
  page.loadStats = () => { loads++; };
  page.switchRange('all');
  assert.equal(loads, 0);
  page.switchRange('last_7d');
  assert.equal(page.currentRange, 'last_7d');
  assert.equal(loads, 1);
  page.switchRange('last_7d');
  assert.equal(loads, 1);
  page.activityTouching = true;
  page.handleRangeSwipeStart();
  page.activityTouching = false;
  page.handleRangeSwipeUpdate({ offsetX: -100, offsetY: 0 });
  page.handleRangeSwipeEnd({ offsetX: -100, offsetY: 0 });
  assert.equal(page.currentRange, 'last_7d');
  assert.equal(loads, 1);
  page.handleRangeSwipeStart();
  page.handleRangeSwipeUpdate({ offsetX: -100, offsetY: 0 });
  page.handleRangeSwipeEnd({ offsetX: -100, offsetY: 0 });
  assert.equal(page.currentRange, 'last_30d');
  assert.equal(loads, 2);
  assert.equal(page.rangeSwipeOffsetX, 0);
}});

cases.push({ name: 'overview, ranking and billing receive the same selected range', fn: async () => {
  const calls = [];
  pageContext.getDatabaseService = () => ({
    getUsageOverview: async start => {
      calls.push(['overview', start]);
      return { sessionCount: 1, messageCount: 2, distinctModelCount: 1, activeDayCount: 1 };
    },
    getModelUsageRanking: async start => { calls.push(['ranking', start]); return []; },
    getUsageBillingSummary: async start => { calls.push(['billing', start]); return []; }
  });
  const page = createPage();
  for (const [range, start] of [['all', 0], ['last_7d', now - 7 * dayMs], ['last_30d', now - 30 * dayMs]]) {
    page.currentRange = range;
    calls.length = 0;
    await page.loadStats();
    assert.deepEqual(calls, [['overview', start], ['ranking', start], ['billing', start]]);
    assert.equal(page.isLoading, false);
    assert.equal(page.messageCount, 2);
  }
}});

cases.push({ name: 'usage totals exclude orphan messages without deleting them or affecting valid history', fn: async () => {
  const database = new DatabaseSync(':memory:');
  const startMs = new Date(2026, 8, 9).getTime();
  const endMs = new Date(2026, 8, 10).getTime();
  database.exec(`CREATE TABLE chat_sessions (id TEXT PRIMARY KEY);
    CREATE TABLE messages (id TEXT PRIMARY KEY, session_id TEXT, role TEXT, timestamp INTEGER,
      model_name TEXT DEFAULT 'model', model_id TEXT DEFAULT 'model-id', billing_enabled INTEGER DEFAULT 1,
      billing_currency TEXT DEFAULT 'USD', estimated_input_tokens INTEGER, estimated_output_tokens INTEGER,
      estimated_cost REAL DEFAULT 0.01);
    INSERT INTO chat_sessions VALUES ('existing');`);
  const records = [
    ['orphan', 'missing', 'assistant', startMs, 36436, 534],
    ['null-session', null, 'assistant', startMs, 90000, 90000],
    ['valid', 'existing', 'assistant', startMs, 10, 20],
    ['last', 'existing', 'assistant', endMs - 1, 30, 40],
    ['user', 'existing', 'user', startMs, 900, 900],
    ['before', 'existing', 'assistant', startMs - 1, 1, 2],
    ['end', 'existing', 'assistant', endMs, 3, 4]
  ];
  for (const row of records) database.prepare('INSERT INTO messages (id,session_id,role,timestamp,estimated_input_tokens,estimated_output_tokens) VALUES (?,?,?,?,?,?)').run(...row);
  let failRead = false;
  let closed = 0;
  service.rdbStore = { querySql: async (sql, args) => {
    assert.match(sql, /EXISTS \(SELECT 1 FROM chat_sessions/);
    assert.doesNotMatch(sql, /\b(INSERT|DELETE|UPDATE|content)\b/i);
    const rows = database.prepare(sql).all(...args);
    let index = -1;
    return {
      goToNextRow: () => ++index < rows.length,
      getColumnIndex: name => name,
      getString: name => String(rows[index][name] ?? ''),
      getLong: name => { if (failRead) throw new Error('Read failure'); return Number(rows[index][name] ?? 0); },
      getDouble: name => Number(rows[index][name] ?? 0),
      close: () => closed++
    };
  } };
  try {
    assert.equal((await service.collectMessageUsageRows(startMs, endMs)).length, 3);
    const heatmap = await service.getDailyUsageActivity(startMs, endMs);
    assert.equal(heatmap[0].totalTokens, 100);
    assert.equal(heatmap[0].messageCount, 2);
    const billing = await service.getUsageBillingSummary(startMs);
    assert.equal(billing[0].inputTokens + billing[0].outputTokens, 107);
    assert.equal(billing[0].messageCount, 3);
    assert.equal((await service.getModelUsageRanking(startMs))[0].count, 3);
    assert.equal((await service.collectMessageUsageRows(0)).length, 5);
    assert.equal((await service.collectMessageUsageRows(0, startMs)).length, 1);
    assert.equal(database.prepare('SELECT count(*) AS n FROM messages').get().n, records.length);
    const previousClosed = closed;
    failRead = true;
    await assert.rejects(service.getDailyUsageActivity(startMs, endMs), /Read failure/);
    assert.equal(closed, previousClosed + 1);
  } finally { service.rdbStore = null; database.close(); }
}});

(async () => {
  for (const test of cases) {
    await test.fn();
    console.log(`PASS ${test.name}`);
  }
  console.log(`${cases.length} usage activity checks passed (${process.env.TZ || 'system timezone'}).`);
})().catch(error => { console.error(error); process.exitCode = 1; });
