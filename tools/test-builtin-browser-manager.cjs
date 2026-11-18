// Production per-conversation coordination and persistence; native Web/Cookie storage is mocked.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.XCUBE_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
const base = path.resolve(__dirname, '../entry/src/main/ets');
const keys = { BROWSER_SAVE_COOKIES: 'browser_save_cookies', BROWSER_OPEN_PAGES_JSON: 'browser_open_pages_json' };
const modules = new Map();
let now = 100000;
let tick = () => {};
const nativeCookies = [];
const nativeCleanup = [];
let nativeCleanupFailure = '';
function preferences(values = {}) {
  return {
    values: new Map(Object.entries(values)), reads: 0, writes: [], beforeWrite: null,
    async getString(key, fallback) { this.reads++; return this.values.get(key) ?? fallback; },
    async getBoolean(key, fallback) { this.reads++; return this.values.get(key) ?? fallback; },
    async setString(key, value) {
      if (this.beforeWrite) await this.beforeWrite(key, value);
      this.values.set(key, value); this.writes.push([key, value]);
    },
    async setBoolean(key, value) {
      if (this.beforeWrite) await this.beforeWrite(key, value);
      this.values.set(key, value); this.writes.push([key, value]);
    }
  };
}
function load(relative) {
  const filename = path.resolve(base, relative.endsWith('.ets') ? relative : `${relative}.ets`);
  if (modules.has(filename)) return modules.get(filename);
  const exports = {};
  modules.set(filename, exports);
  const source = fs.readFileSync(filename, 'utf8').replace(/@(ObservedV2|Trace|Computed)\s*/g, '');
  const javascript = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS }
  }).outputText;
  vm.runInNewContext(javascript, {
    exports, console, Date: { now: () => now },
    setTimeout: (fn, ms) => setTimeout(() => { now += ms; tick(); fn(); }, 0),
    setInterval: (fn, ms) => setInterval(() => { now += ms; fn(); }, 1), clearInterval,
    require: dependency => {
      if (dependency === '@kit.ArkWeb') return { webview: { WebCookieManager: {
        saveCookieAsync: async () => nativeCookies.push('save'),
        clearAllCookies: async () => {
          nativeCookies.push('clear');
          if (nativeCleanupFailure === 'cookies') throw new Error('cookie store failure');
        },
        clearAllCookiesSync: incognito => nativeCleanup.push(['private-cookies', incognito])
      }, WebStorage: { deleteAllData: incognito => nativeCleanup.push(['site-storage', incognito]) },
      WebviewController: { removeAllCache: disk => nativeCleanup.push(['resource-cache', disk]) } } };
      if (dependency.endsWith('/PreferencesService')) return { PreferenceKeys: keys, getPreferencesService: () => preferences() };
      return load(path.relative(base, path.resolve(path.dirname(filename), dependency)));
    }
  }, { filename });
  return exports;
}
const { BuiltinBrowserManager } = load('services/BuiltinBrowserManager');
const { BrowserCapture, BrowserTypingResult } = load('services/BuiltinBrowserService');
const { parseBrowserRequest } = load('services/BuiltinBrowserPolicy');
const request = (action, fields = {}) => parseBrowserRequest(JSON.stringify({ action, ...fields }));
const cases = [];
const test = (name, run) => cases.push({ name, run });
const saved = store => JSON.parse(store.values.get(keys.BROWSER_OPEN_PAGES_JSON) ?? '[]');
async function fixture(store = preferences()) {
  const events = [];
  const cookies = {
    save: async () => events.push('save-cookies'),
    clearSaved: async () => events.push('clear-cookies'),
    clearAllData: async () => events.push('clear-all-data')
  };
  const manager = new BuiltinBrowserManager(store, cookies);
  const hosts = new Map();
  await manager.initialize();
  function attach() {
    for (const browser of manager.state.sessions) {
      if (!browser.state.sessionId) continue;
      const sessionId = browser.state.sessionId;
      if (hosts.get(sessionId)?.generation === browser.state.generation) continue;
      const host = {
        generation: browser.state.generation, clicks: [], active: false,
        destroy: () => events.push(`destroy-${sessionId}`),
        resetKeyboard: () => {}, setActive: value => { host.active = value; },
        navigate: url => {
          browser.state.url = url; browser.state.loading = false; browser.invalidate();
        },
        setPageMode: () => {}, back: () => {}, forward: () => {}, reload: () => {},
        click: async (x, y) => host.clicks.push([x, y]), scroll: async () => {},
        type: async () => new BrowserTypingResult(),
        capture: async () => Object.assign(new BrowserCapture(), {
          base64: 'eA==', bytes: 1, width: 800, height: 600, viewportWidth: 800, viewportHeight: 600,
          url: browser.state.url, title: sessionId
        })
      };
      browser.attach(browser.state.generation, host);
      hosts.set(sessionId, host);
    }
  }
  tick = attach;
  async function show(sessionId) { await manager.showForUser(sessionId); attach(); return manager.getSession(sessionId); }
  const run = (sessionId, action, fields = {}) => manager.execute(request(action, fields), sessionId, `request-${sessionId}`, () => false);
  return { manager, store, events, hosts, cookies, run, show, attach };
}

test('different conversations keep independent pages, control, snapshots and concurrent operations', async () => {
  const { manager, run, show, hosts } = await fixture();
  const a = await show('a');
  const firstA = await run('a', 'open', { url: 'https://a.example/' });
  const b = await show('b');
  const firstB = await run('b', 'open', { url: 'https://b.example/' });
  assert.equal(a.state.visible, false);
  assert.equal(b.state.visible, true);
  assert.equal(a.state.owner, 'model');
  assert.equal(hosts.get('a').active, true, 'hiding a chat keeps its model active');
  assert.notEqual(firstA.result.snapshot_id, firstB.result.snapshot_id);
  await assert.rejects(run('b', 'click', { snapshot_id: firstA.result.snapshot_id, x: 10, y: 10 }), /截图已失效/);
  assert.equal(hosts.get('b').clicks.length, 0);
  const [nextA, nextB] = await Promise.all([
    run('a', 'click', { snapshot_id: firstA.result.snapshot_id, x: 10, y: 20 }),
    run('b', 'click', { snapshot_id: firstB.result.snapshot_id, x: 30, y: 40 })
  ]);
  assert.equal(nextA.result.url, 'https://a.example/');
  assert.equal(nextB.result.url, 'https://b.example/');
  assert.deepEqual(hosts.get('a').clicks, [[10, 20]]);
  assert.deepEqual(hosts.get('b').clicks, [[30, 40]]);
  b.takeOver();
  assert.equal(a.state.owner, 'model');
  manager.endRequest('request-a');
  assert.equal(a.state.owner, 'idle');
  assert.equal(b.state.owner, 'user');
  await show('a');
  assert.equal(a.state.visible, true);
  assert.equal(b.state.visible, false);
  assert.equal(b.state.owner, 'user');
});

test('background conversations do not cover the active chat and launch approval is scoped to each chat', async () => {
  const { manager, run, show } = await fixture();
  await show('a');
  await run('a', 'open', { url: 'https://a.example/' });
  const open = request('open', { url: 'https://next.example/' });
  assert.equal(manager.requiresLaunchApproval(open, 'a'), false);
  assert.equal(manager.requiresLaunchApproval(open, 'b'), true);
  for (const action of ['snapshot', 'wait_for_user']) assert.equal(manager.requiresLaunchApproval(request(action), 'b'), false);
  manager.setActiveSession('a');
  await run('b', 'open', { url: 'https://b.example/' });
  assert.equal(manager.getSession('b').state.visible, false);
  assert.equal(manager.getSession('a').state.visible, true);
  manager.leaveSession('b');
  assert.equal(manager.getSession('a').state.visible, true, 'late disappearance from another chat cannot hide this one');
  manager.getSession('b').state.url = 'about:blank';
  assert.equal(manager.requiresLaunchApproval(open, 'b'), true);
  assert.equal(manager.requiresLaunchApproval(open, 'a'), false);
});

test('restart lazily restores every live URL and page mode, including hidden pages', async () => {
  const { manager, store, run, show } = await fixture();
  const a = await show('a');
  await run('a', 'open', { url: 'https://a.example/path#heading', page_mode: 'desktop' });
  await show('b');
  await run('b', 'open', { url: 'https://b.example/' });
  assert.equal(a.state.visible, false);
  manager.setForeground(false);
  await manager.flush();
  assert.deepEqual(saved(store), [
    { sessionId: 'a', url: 'https://a.example/path#heading', pageMode: 'desktop' },
    { sessionId: 'b', url: 'https://b.example/', pageMode: 'mobile' }
  ]);
  const restored = await fixture(store);
  assert.equal(restored.manager.state.sessions.length, 0, 'startup does not mount hidden Web components');
  const pendingA = restored.manager.getSession('a');
  assert.equal(pendingA.state.sessionId, '', 'binding a chat does not load its remembered page');
  assert.equal(pendingA.state.hasPage, true, 'a saved URL activates the chip before Web is mounted');
  assert.equal(pendingA.state.modelRequestActive, false, 'remembered pages do not start the flow light');
  assert.equal(restored.manager.requiresLaunchApproval(request('open', { url: 'https://a.example/' }), 'a'), true);
  const reopenedA = await restored.show('a');
  assert.equal(reopenedA.state.initialUrl, 'https://a.example/path#heading');
  assert.equal(reopenedA.state.hasPage, true, 'the saved page stays active while ArkWeb starts loading it');
  assert.equal(reopenedA.state.pageMode, 'desktop');
  assert.equal(reopenedA.state.owner, 'idle', 'old model or user control is not resumed');
  const reopenedB = await restored.show('b');
  assert.equal(reopenedB.state.initialUrl, 'https://b.example/');
});

test('navigation updates saved URLs and closing or deleting removes only that page', async () => {
  const { manager, store, run, show } = await fixture();
  const a = await show('a');
  await run('a', 'open', { url: 'https://a.example/' });
  await show('b');
  await run('b', 'open', { url: 'https://b.example/' });
  a.state.url = 'https://a.example/redirect';
  a.notifyPageChanged();
  await manager.flush();
  assert.equal(saved(store)[0].url, a.state.url);
  a.closeSession('a');
  assert.equal(a.state.hasPage, false);
  await manager.flush();
  assert.deepEqual(saved(store).map(page => page.sessionId), ['b']);
  const restored = await fixture(store);
  await restored.manager.forgetSession('b');
  assert.deepEqual(saved(store), [], 'deleting an unloaded remembered page also removes it');
  const fresh = await restored.show('a');
  assert.equal(fresh.state.initialUrl, 'about:blank');
  await manager.forgetSession('b');
  assert.equal(manager.getSession('a'), a);
  assert.equal(manager.state.sessions.length, 1);
});

test('an in-flight preference write cannot resurrect a subsequently closed page', async () => {
  const { manager, store, run, show } = await fixture();
  const a = await show('a');
  await run('a', 'open', { url: 'https://a.example/' });
  await manager.flush();
  let release, started;
  const writing = new Promise(resolve => { started = resolve; });
  store.beforeWrite = async () => {
    store.beforeWrite = null;
    started();
    await new Promise(resolve => { release = resolve; });
  };
  a.state.url = 'https://a.example/new';
  a.notifyPageChanged();
  await writing;
  a.closeSession('a');
  const flush = manager.flush();
  release();
  await flush;
  assert.deepEqual(saved(store), []);
});

test('Cookie opt-in persists and rebuilds every page; opt-out disposes normal pages before clearing cookies', async () => {
  const { manager, store, events, run, show, attach } = await fixture();
  const a = await show('a');
  const frame = (await run('a', 'open', { url: 'https://a.example/' })).result.snapshot_id;
  const b = await show('b');
  await run('b', 'open', { url: 'https://b.example/' });
  manager.endRequest('request-a');
  manager.endRequest('request-b');
  b.takeOver();
  const generations = [a.state.generation, b.state.generation];
  assert.equal(manager.state.saveCookies, false);
  await manager.setSaveCookies(true);
  attach();
  assert.equal(store.values.get(keys.BROWSER_SAVE_COOKIES), true);
  for (const [i, browser] of [a, b].entries()) {
    assert.equal(browser.state.saveCookies, true);
    assert.ok(browser.state.generation > generations[i]);
  }
  assert.equal(a.state.visible, false);
  assert.equal(b.state.visible, true);
  assert.equal(b.state.owner, 'user');
  assert.equal(a.state.initialUrl, 'https://a.example/');
  await assert.rejects(run('a', 'click', { snapshot_id: frame, x: 10, y: 10 }), /截图已失效/);
  const restored = await fixture(store);
  assert.equal(restored.manager.state.saveCookies, true);
  assert.equal((await restored.show('c')).state.saveCookies, true, 'new conversations use the same Cookie setting');
  events.length = 0;
  await manager.flush();
  assert.ok(events.includes('save-cookies'));
  a.pause('cancelled');
  events.length = 0;
  await manager.setSaveCookies(false);
  assert.deepEqual(events.slice(0, 3), ['destroy-a', 'destroy-b', 'clear-cookies']);
  assert.equal(a.state.saveCookies, false);
  assert.equal(b.state.saveCookies, false);
  assert.equal(a.state.owner, 'paused');
  assert.equal(a.state.pauseReason, 'cancelled');
  assert.equal(store.values.get(keys.BROWSER_SAVE_COOKIES), false);
  const count = events.length;
  await manager.flush();
  assert.equal(events.length, count, 'private mode never persists the native cookie jar');
});

test('Cookie changes do not interrupt an active operation and new calls cannot enter during a mode switch', async () => {
  const { manager, store, run, show } = await fixture();
  await show('a');
  const running = run('a', 'snapshot');
  await assert.rejects(manager.setSaveCookies(true), /正在操作/);
  await running;
  assert.equal(manager.state.saveCookies, false);
  let release, started;
  const writing = new Promise(resolve => { started = resolve; });
  store.beforeWrite = async key => {
    if (key !== keys.BROWSER_SAVE_COOKIES) return;
    started();
    await new Promise(resolve => { release = resolve; });
  };
  const changing = manager.setSaveCookies(true);
  await writing;
  await assert.rejects(run('a', 'snapshot'), /正在切换 Cookie/);
  release();
  await changing;
  assert.equal(manager.state.changingCookies, false);
});

test('early lifecycle callbacks do not load defaults before preferences are initialized', async () => {
  const store = preferences({ [keys.BROWSER_SAVE_COOKIES]: true });
  const manager = new BuiltinBrowserManager(store);
  manager.setForeground(false);
  await manager.flush();
  assert.equal(store.reads, 0);
  const browser = manager.getSession('a');
  await manager.initialize();
  assert.equal(manager.state.saveCookies, true);
  assert.equal(browser.state.saveCookies, true, 'early chat binding receives the loaded setting');
});

test('malformed saved records are ignored and Cookie persistence uses only the native store', async () => {
  for (const raw of ['broken json', '{}', JSON.stringify([null, 2, {},
    { sessionId: 'unsafe', url: 'javascript:alert(1)' },
    { sessionId: '', url: 'https://example.com' }])]) {
    const { manager, store, show } = await fixture(preferences({ [keys.BROWSER_OPEN_PAGES_JSON]: raw }));
    assert.equal((await show('unsafe')).state.initialUrl, 'about:blank');
    await manager.forgetSession('unsafe');
    assert.deepEqual(saved(store), []);
  }
  const store = preferences();
  const manager = new BuiltinBrowserManager(store);
  await manager.initialize();
  nativeCookies.length = 0;
  await manager.setSaveCookies(true);
  await manager.flush();
  await manager.setSaveCookies(false);
  assert.deepEqual(nativeCookies, ['save', 'save', 'clear', 'save']);
  assert.deepEqual([...store.values.keys()].sort(), Object.values(keys).sort(), 'no cookie values are stored in preferences');
});

test('leaving an untouched empty browser keeps the chip inactive and saves no page', async () => {
  const { manager, store, show } = await fixture();
  const browser = await show('a');
  assert.equal(manager.dismissOnBack(), true);
  assert.equal(browser.state.hasPage, false);
  await show('a');
  browser.hide();
  assert.equal(browser.state.hasPage, false);
  await manager.flush();
  assert.deepEqual(saved(store), []);
  const restarted = await fixture(store);
  assert.equal(restarted.manager.getSession('a').state.hasPage, false);
});

test('blank URLs are dropped on restore and when a live page returns to blank', async () => {
  const page = { sessionId: 'saved', url: 'https://saved.example/', pageMode: 'desktop' };
  const store = preferences({ [keys.BROWSER_OPEN_PAGES_JSON]: JSON.stringify([
    { sessionId: 'empty', url: 'about:blank', pageMode: 'desktop' }, page
  ]) });
  const { manager, show } = await fixture(store);
  assert.equal(manager.getSession('empty').state.hasPage, false);
  assert.equal(manager.getSession('saved').state.hasPage, true);
  await manager.flush();
  assert.deepEqual(saved(store), [page]);
  const browser = await show('empty');
  browser.takeOver();
  browser.userNavigate('https://example.com/');
  browser.hide();
  assert.equal(browser.state.hasPage, true);
  await show('empty');
  browser.userNavigate('about:blank');
  browser.hide();
  assert.equal(browser.state.hasPage, false);
  await manager.flush();
  assert.deepEqual(saved(store), [page]);
});

test('open and remembered page activity is separate from model flow-light activity', async () => {
  const { manager, run, show } = await fixture();
  const browser = manager.getSession('a');
  assert.equal(browser.state.hasPage, false);
  await show('a');
  assert.equal(browser.state.hasPage, false);
  assert.equal(browser.state.modelRequestActive, false);
  await run('a', 'open', { url: 'https://example.com/' });
  assert.equal(browser.state.modelRequestActive, true);
  manager.endRequest('request-a');
  browser.hide();
  assert.equal(browser.state.hasPage, true);
  assert.equal(browser.state.modelRequestActive, false);
  browser.closeSession('a');
  assert.equal(browser.state.hasPage, false);
});

test('clear closes every live page and removes both loaded and unloaded URL memories without changing Cookie opt-in', async () => {
  const store = preferences({
    [keys.BROWSER_SAVE_COOKIES]: true,
    [keys.BROWSER_OPEN_PAGES_JSON]: JSON.stringify([
      { sessionId: 'unloaded', url: 'https://saved.example/', pageMode: 'desktop' },
      { sessionId: 'bound', url: 'https://bound.example/', pageMode: 'mobile' }
    ])
  });
  const { manager, show, run, events } = await fixture(store);
  const bound = manager.getSession('bound');
  const a = await show('a');
  await run('a', 'open', { url: 'https://a.example/' });
  const b = await show('b');
  await run('b', 'open', { url: 'https://b.example/' });
  await manager.flush();
  events.length = 0;
  await manager.clearAllData();
  assert.deepEqual(events, ['destroy-a', 'destroy-b', 'clear-all-data']);
  assert.deepEqual(saved(store), []);
  for (const browser of [a, b, bound]) {
    assert.equal(browser.state.sessionId, '');
    assert.equal(browser.state.visible, false);
    assert.equal(browser.state.hasPage, false);
    assert.equal(browser.state.modelRequestActive, false);
  }
  assert.equal(manager.getSession('a'), a, 'existing ChatPage state bindings remain valid');
  assert.equal(manager.state.saveCookies, true);
  assert.equal(store.values.get(keys.BROWSER_SAVE_COOKIES), true);
  const restarted = await fixture(store);
  assert.equal(restarted.manager.getSession('unloaded').state.hasPage, false);
  assert.equal((await show('bound')).state.initialUrl, 'about:blank');
  assert.equal((await show('a')).state.initialUrl, 'about:blank');
});

test('clear cancels in-flight capture and blocks reopening, Cookie switching and stale writes until finished', async () => {
  const { manager, store, show, run, hosts, cookies, events } = await fixture();
  const browser = await show('a');
  await run('a', 'open', { url: 'https://a.example/' });
  await manager.flush();
  let captureStarted, releaseCapture;
  const captureReady = new Promise(resolve => { captureStarted = resolve; });
  hosts.get('a').capture = async () => {
    captureStarted();
    return new Promise(resolve => { releaseCapture = resolve; });
  };
  const captured = run('a', 'snapshot');
  const cancelledCapture = assert.rejects(captured, /已取消|已关闭/);
  await captureReady;
  let writeStarted, releaseWrite;
  const writing = new Promise(resolve => { writeStarted = resolve; });
  store.beforeWrite = async () => {
    store.beforeWrite = null;
    writeStarted();
    await new Promise(resolve => { releaseWrite = resolve; });
  };
  browser.state.url = 'https://a.example/late';
  browser.notifyPageChanged();
  await writing;
  let cleanupStarted, finishCleanup;
  const cleaning = new Promise(resolve => { cleanupStarted = resolve; });
  cookies.clearAllData = async () => {
    cleanupStarted();
    await new Promise(resolve => { finishCleanup = resolve; });
  };
  const cleared = manager.clearAllData();
  await Promise.resolve();
  await assert.rejects(run('a', 'open', { url: 'https://new.example/' }), /正在清空/);
  await assert.rejects(manager.showForUser('b'), /正在清空/);
  await assert.rejects(manager.setSaveCookies(true), /正在清空/);
  releaseWrite();
  await cleaning;
  releaseCapture(Object.assign(new BrowserCapture(), { base64: 'late-frame' }));
  await cancelledCapture;
  const saves = events.filter(event => event === 'save-cookies').length;
  await manager.flush();
  assert.equal(events.filter(event => event === 'save-cookies').length, saves);
  finishCleanup();
  await cleared;
  assert.deepEqual(saved(store), []);
  assert.equal(browser.state.hasPage, false);
  assert.equal(manager.state.clearingData, false);
});

test('cleanup failure is reported, other cleanup still runs, and the next clear can retry', async () => {
  const { manager, store, show, run, cookies, events } = await fixture();
  await show('a');
  await run('a', 'open', { url: 'https://example.com/' });
  await manager.flush();
  store.beforeWrite = async () => { throw new Error('disk full'); };
  await assert.rejects(manager.clearAllData(), /网址/);
  assert.ok(events.includes('clear-all-data'), 'storage cleanup proceeds even if URL persistence fails');
  assert.equal(manager.state.clearingData, false);
  store.beforeWrite = null;
  cookies.clearAllData = async () => { throw new Error('native cache failure'); };
  await assert.rejects(manager.clearAllData(), /缓存和 Cookie/);
  assert.deepEqual(saved(store), []);
  assert.equal(manager.state.clearingData, false);
  cookies.clearAllData = async () => events.push('retry-cleanup');
  await manager.clearAllData();
  assert.equal(events.at(-1), 'retry-cleanup');
});

test('native cleanup covers normal/private cookies, site storage and disk cache even with no open page', async () => {
  const manager = new BuiltinBrowserManager(preferences());
  await manager.initialize();
  nativeCookies.length = 0;
  nativeCleanup.length = 0;
  await manager.clearAllData();
  assert.equal(manager.state.sessions.length, 0);
  assert.deepEqual(nativeCookies, ['clear', 'save']);
  const expected = [['private-cookies', true], ['site-storage', false], ['site-storage', true], ['resource-cache', true]];
  assert.deepEqual(nativeCleanup, expected);
  nativeCleanup.length = 0;
  nativeCleanupFailure = 'cookies';
  try {
    await assert.rejects(manager.clearAllData(), /缓存和 Cookie/);
    assert.deepEqual(nativeCleanup, expected, 'failed normal-cookie deletion does not skip the other stores');
  } finally {
    nativeCleanupFailure = '';
  }
});

(async () => {
  for (const { name, run } of cases) {
    tick = () => {};
    await run();
    console.log(`PASS ${name}`);
  }
  console.log(`Passed ${cases.length} browser manager tests.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
