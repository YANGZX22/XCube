// Run production coordination/parser code and the native adapter with mocked ArkUI boundaries.
// Rendering, IME behavior and Web touch dispatch still require the on-device checklist.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.XCUBE_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
const root = path.resolve(__dirname, '..');
const base = path.join(root, 'entry/src/main/ets');
const modules = new Map();
let now = 100000;
let delayHook = null;
function transpile(source) {
  return ts.transpileModule(source.replace(/@(ObservedV2|Trace|Computed)\s*/g, ''), {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS }
  }).outputText;
}
function load(relative) {
  const filename = path.resolve(base, relative.endsWith('.ets') ? relative : `${relative}.ets`);
  if (modules.has(filename)) return modules.get(filename);
  const exports = {};
  modules.set(filename, exports);
  const context = {
    exports, console, Date: { now: () => now },
    setTimeout: (fn, ms) => setTimeout(() => {
      now += ms;
      if (delayHook) delayHook(ms);
      fn();
    }, 0),
    setInterval: (fn, ms) => setInterval(() => { now += ms; fn(); }, 1),
    clearInterval,
    require: dependency => load(path.relative(base, path.resolve(path.dirname(filename), dependency)))
  };
  vm.runInNewContext(transpile(fs.readFileSync(filename, 'utf8')), context, { filename });
  return exports;
}
const policy = load('services/BuiltinBrowserPolicy');
const { browserDelay, BuiltinBrowserService, BrowserCapture, BrowserTypingResult } = load('services/BuiltinBrowserService');
const adapterBrowser = new BuiltinBrowserService();
const getTestBrowser = () => adapterBrowser;
function managerForBrowser(browser) {
  return {
    initialize: async () => {},
    getSession: sessionId => { assert.equal(sessionId, 'chat-a'); return browser; },
    execute: (request, sessionId, requestId, cancelled) => {
      assert.equal(sessionId, 'chat-a');
      return browser.execute(request, sessionId, requestId, cancelled);
    },
    requiresLaunchApproval: (request, sessionId) => {
      assert.equal(sessionId, 'chat-a');
      return browser.requiresLaunchApproval(request);
    },
    endRequest: requestId => browser.endRequest(requestId)
  };
}
const inputBridge = load('services/BuiltinBrowserInput');
const pageBridge = load('services/BuiltinBrowserPage');
const cases = [];
const test = (name, fn) => cases.push({ name, fn });
const request = (action, fields = {}) => policy.parseBrowserRequest(JSON.stringify({ action, ...fields }));
const screenshot = () => Object.assign(new BrowserCapture(), {
  base64: 'eA==', bytes: 1, width: 800, height: 600, viewportWidth: 1600, viewportHeight: 1200,
  focusedEditable: true
});
function fixture(service = new BuiltinBrowserService()) {
  const calls = [];
  const activity = [];
  const host = {
    destroy: () => {},
    setActive: active => activity.push(active),
    navigate: url => { calls.push(['open', url]); service.state.url = url; },
    find: text => { calls.push(['find', text]); service.state.findMatches = 2; service.state.findDone = true; },
    readPage: async (start, maxChars) => Object.assign(new pageBridge.BrowserPageText(), {
      url: service.state.url, title: 'Document', start, text: 'page content'.slice(0, maxChars), next_start: start + Math.min(12, maxChars)
    }),
    back: () => calls.push(['back']), forward: () => calls.push(['forward']),
    reload: () => calls.push(['reload']), resetKeyboard: () => {},
    setPageMode: mode => calls.push(['mode', mode]),
    click: async (x, y) => { calls.push(['click', x, y]); },
    scroll: async (x, y, dx, dy) => { calls.push(['scroll', x, y, dx, dy]); },
    type: async (text, submit) => {
      calls.push(['type', text, submit]);
      return Object.assign(new BrowserTypingResult(), { inputMethod: 'native_keyboard', textInserted: text !== '', submitSent: submit });
    },
    capture: async () => { calls.push(['snapshot']); return screenshot(); }
  };
  service.showForUser('chat-a');
  service.attach(service.state.generation, host);
  service.resume();
  const run = (action, fields = {}, cancelled = () => false) =>
    service.execute(request(action, fields), 'chat-a', 'request-a', cancelled);
  return { service, calls, host, run, activity };
}

test('parses flat, fenced, wrapped and stringified JSON without changing multiline text', () => {
  const args = { action: 'type', text: '中文\n"quoted" \\ path', snapshot_id: 'browser-1-1' };
  for (const raw of [JSON.stringify(args), JSON.stringify(JSON.stringify(args)),
    JSON.stringify({ arguments: JSON.stringify(args) }), `\`\`\`json\n${JSON.stringify(args)}\n\`\`\``]) {
    assert.equal(policy.parseBrowserRequest(raw).text, args.text);
  }
});

test('rejects truncated/malformed actions, unsafe URLs and invalid coordinates/text', () => {
  for (const raw of ['[]', 'null', '5', '{"action":"open"', '{"action":"unknown"}',
    '{"action":"click","snapshot_id":"x","x":"1","y":2}',
    '{"action":"type","snapshot_id":"x","text":"a","submit":"true"}']) {
    assert.throws(() => policy.parseBrowserRequest(raw));
  }
  for (const url of ['file:///data/private', 'javascript:alert(1)', 'data:text/html,x',
    'intent://app', 'https://user:password@example.com', 'https://example.com\\@evil', 'https://exa\nmple.com']) {
    assert.equal(policy.isBrowserUrlAllowed(url), false, url);
    assert.throws(() => request('open', { url }));
  }
  assert.equal(policy.isBrowserUrlAllowed('https://example.com/search?q=%E4%B8%AD'), true);
  assert.throws(() => request('scroll', { snapshot_id: 'x' }));
  assert.throws(() => request('scroll', { snapshot_id: 'x', delta_y: 4001 }));
  assert.throws(() => request('type', { snapshot_id: 'x', text: 'x'.repeat(16001) }));
  for (const action of ['find', 'click', 'scroll', 'type', 'back', 'forward', 'reload', 'set_page_mode']) {
    assert.throws(() => request(action));
  }
  for (const fields of [{ x: 1 }, { y: 1 }, { x: '1', y: 2 }, { x: 1, y: null }]) {
    assert.throws(() => request('scroll', { snapshot_id: 'x', delta_y: 100, ...fields }));
  }
  for (const page_mode of ['', 'tablet', null, true]) {
    assert.throws(() => request('set_page_mode', { snapshot_id: 'x', page_mode }));
    assert.throws(() => request('open', { url: 'https://example.com', page_mode }));
  }
  assert.throws(() => request('reload', { snapshot_id: 'x', page_mode: 'desktop' }));
});

test('page reading and find validate bounded arguments and preserve their separate snapshot contracts', () => {
  assert.equal(request('read_page').max_chars, 8000);
  assert.equal(request('read_page', { start: 16000, max_chars: 2000 }).start, 16000);
  for (const fields of [{ start: -1 }, { start: 1.5 }, { start: 500001 }, { max_chars: 0 }, { max_chars: 16001 }]) {
    assert.throws(() => request('read_page', fields));
  }
  for (const text of ['', ' ', 'x'.repeat(201)]) {
    assert.throws(() => request('find', { snapshot_id: 'frame', text }));
  }
  assert.throws(() => request('find', { text: 'References' }));
});

test('read_page returns paginated text without capturing or invalidating the latest visual frame', async () => {
  const { run, calls, service } = fixture();
  const frame = (await run('open', { url: 'https://example.com/' })).result.snapshot_id;
  calls.length = 0;
  service.hide();
  const output = await run('read_page', { start: 20, max_chars: 4 });
  assert.equal(output.capture, null);
  assert.equal(output.result.snapshot_id, '');
  assert.equal(output.result.page_text.text, 'page');
  assert.equal(output.result.page_text.start, 20);
  assert.equal(output.result.browser_visible, false);
  assert.equal(calls.length, 0);
  const found = await run('find', { snapshot_id: frame, text: 'References' });
  assert.deepEqual(calls[0], ['find', 'References']);
  assert.equal(found.result.find_matches, 2);
  assert.ok(found.capture);
  await assert.rejects(run('click', { snapshot_id: frame, x: 10, y: 10 }), /截图已失效/);
});

test('read_page discards extracted text if the user takes over during the read', async () => {
  const { run, service, host } = fixture();
  host.readPage = async () => { service.takeOver(); return { text: 'must not be returned' }; };
  const result = await run('read_page');
  assert.equal(result.result.status, 'user_control');
  assert.equal(result.result.page_text, null);
});

test('open never reports requested URL as success when the native capture is still blank', async () => {
  const { run, host, service } = fixture();
  host.capture = async () => Object.assign(screenshot(), { url: 'about:blank', title: '' });
  await assert.rejects(run('open', { url: 'https://example.com/' }), /当前仍为 about:blank/);
  assert.equal(service.state.url, 'about:blank');
});

test('open → screenshot → click → type → scroll uses fresh frames and pixel scaling', async () => {
  const { run, calls } = fixture();
  let output = await run('open', { url: 'https://example.com/' });
  assert.equal(output.result.url, 'https://example.com/');
  assert.equal(output.capture.base64, 'eA==');
  assert.equal(JSON.stringify(output.result).includes('base64'), false);
  const first = output.result.snapshot_id;
  output = await run('click', { snapshot_id: first, x: 123, y: 234 });
  assert.deepEqual(calls.find(call => call[0] === 'click'), ['click', 246, 468]);
  assert.notEqual(output.result.snapshot_id, first);
  await assert.rejects(run('click', { snapshot_id: first, x: 1, y: 1 }), /截图已失效/);
  output = await run('type', { snapshot_id: output.result.snapshot_id, text: '你好 browser', submit: true });
  assert.deepEqual(calls.find(call => call[0] === 'type'), ['type', '你好 browser', true]);
  await run('scroll', { snapshot_id: output.result.snapshot_id, delta_y: 300 });
  assert.deepEqual(calls.find(call => call[0] === 'scroll'), ['scroll', 800, 600, 0, 600]);
});

test('page mode is selected before open, persists across navigation and changes only with a fresh frame', async () => {
  const { run, calls, service } = fixture();
  let result = await run('open', { url: 'https://example.com/', page_mode: 'desktop' });
  assert.equal(result.result.page_mode, 'desktop');
  assert.deepEqual(calls.slice(0, 2), [['mode', 'desktop'], ['open', 'https://example.com/']]);
  result = await run('open', { url: 'https://example.com/next' });
  assert.equal(result.result.page_mode, 'desktop');
  assert.equal(calls.filter(call => call[0] === 'mode').length, 1);
  await assert.rejects(run('set_page_mode', { snapshot_id: 'stale', page_mode: 'mobile' }), /截图已失效/);
  service.hide();
  service.setForeground(false);
  const oldFrame = result.result.snapshot_id;
  result = await run('set_page_mode', { snapshot_id: oldFrame, page_mode: 'mobile' });
  assert.equal(result.result.page_mode, 'mobile');
  assert.equal(result.result.action_executed, true);
  assert.equal(result.result.browser_visible, false);
  assert.deepEqual(calls.slice(-3), [['mode', 'mobile'], ['reload'], ['snapshot']]);
  await assert.rejects(run('click', { snapshot_id: oldFrame, x: 5, y: 5 }), /截图已失效/);
  result = await run('set_page_mode', { snapshot_id: result.result.snapshot_id, page_mode: 'mobile' });
  assert.equal(result.result.action_executed, false);
  assert.equal(calls.filter(call => call[0] === 'reload').length, 1);
  service.closeSession('chat-a');
  service.showForUser('chat-b');
  assert.equal(service.state.pageMode, 'mobile');
});

test('model mode switch respects takeover; user mode switch requires explicit takeover', async () => {
  const { run, calls, service } = fixture();
  const frame = (await run('snapshot')).result.snapshot_id;
  assert.throws(() => service.userSetPageMode('desktop'), /接管页面/);
  service.takeOver();
  const output = await run('set_page_mode', { snapshot_id: frame, page_mode: 'desktop' });
  assert.equal(output.result.status, 'user_control');
  assert.equal(output.result.page_mode, 'mobile');
  assert.equal(calls.some(call => call[0] === 'mode'), false);
  service.userSetPageMode('desktop');
  assert.equal(service.state.pageMode, 'desktop');
  assert.deepEqual(calls.slice(-2), [['mode', 'desktop'], ['reload']]);
});

test('targeted scroll scales its origin and distances and rejects invalid/stale origins before dispatch', async () => {
  const { run, calls } = fixture();
  const frame = (await run('snapshot')).result.snapshot_id;
  await assert.rejects(run('scroll', { snapshot_id: frame, x: 800, y: 20, delta_y: 200 }), /超出截图/);
  await assert.rejects(run('scroll', { snapshot_id: frame, x: -1, y: 20, delta_y: 200 }), /超出截图/);
  assert.equal(calls.some(call => call[0] === 'scroll'), false);
  await run('scroll', { snapshot_id: frame, x: 123, y: 234, delta_x: -100, delta_y: 200 });
  assert.deepEqual(calls.find(call => call[0] === 'scroll'), ['scroll', 246, 468, -200, 400]);
  await assert.rejects(run('scroll', { snapshot_id: frame, x: 123, y: 234, delta_y: 200 }), /截图已失效/);
});

test('bounds and layout changes block clicks before dispatch', async () => {
  const { run, service, calls } = fixture();
  let frame = (await run('snapshot')).result.snapshot_id;
  await assert.rejects(run('click', { snapshot_id: frame, x: 800, y: 1 }), /超出截图/);
  await assert.rejects(run('click', { snapshot_id: frame, x: -1, y: 1 }), /超出截图/);
  service.invalidate();
  await assert.rejects(run('click', { snapshot_id: frame, x: 1, y: 1 }), /截图已失效/);
  assert.equal(calls.some(call => call[0] === 'click'), false);
});

test('takeover pauses actions and screenshots; resume never replays the pending action', async () => {
  const { run, service, calls } = fixture();
  const frame = (await run('snapshot')).result.snapshot_id;
  service.takeOver();
  const count = calls.length;
  const output = await run('click', { snapshot_id: frame, x: 10, y: 20 });
  assert.equal(output.result.status, 'user_control');
  assert.equal(output.capture, null);
  assert.equal(calls.length, count);
  delayHook = () => service.resume();
  const resumed = await run('wait_for_user');
  delayHook = null;
  assert.ok(resumed.result.snapshot_id);
  assert.equal(resumed.result.action_executed, false);
  assert.equal(calls.some(call => call[0] === 'click'), false);
  await assert.rejects(run('click', { snapshot_id: frame, x: 10, y: 20 }), /截图已失效/);
});

test('giving control before wait_for_user arrives is consumed without another handoff', async () => {
  const { run, service } = fixture();
  await run('snapshot');
  service.takeOver();
  service.resume();
  const output = await run('wait_for_user');
  assert.ok(output.capture);
  assert.equal(service.state.owner, 'model');
});

test('intentional handoff waits for the user and does not execute any webpage actions', async () => {
  const { run, service, calls } = fixture();
  let observed = false;
  delayHook = () => {
    if (service.state.waitingForUser) {
      assert.equal(service.state.owner, 'paused');
      observed = true;
      service.resume();
      delayHook = null;
    }
  };
  const output = await run('wait_for_user');
  assert.equal(observed, true);
  assert.ok(output.capture);
  assert.deepEqual(calls, [['snapshot']]);
});

test('an open prepared before takeover is not replayed after the user returns control', async () => {
  const { run, service, calls } = fixture();
  await run('snapshot');
  service.takeOver();
  service.resume();
  const output = await run('open', { url: 'https://example.com/old-navigation' });
  assert.equal(output.result.action_executed, false);
  assert.equal(calls.some(call => call[0] === 'open'), false);
  assert.ok(output.capture);
});

test('a user action during settling discards capture, and reports the preceding action occurred', async () => {
  const { run, service, calls } = fixture();
  const frame = (await run('snapshot')).result.snapshot_id;
  const count = calls.filter(call => call[0] === 'snapshot').length;
  delayHook = () => { delayHook = null; service.takeOver(); };
  const output = await run('click', { snapshot_id: frame, x: 5, y: 5 });
  assert.equal(output.result.action_executed, true);
  assert.equal(output.result.status, 'user_control');
  assert.equal(calls.filter(call => call[0] === 'snapshot').length, count);
});

test('parallel operations and other sessions cannot use the active tab', async () => {
  const { run, service } = fixture();
  const first = run('snapshot');
  await assert.rejects(run('snapshot'), /必须串行/);
  await first;
  await assert.rejects(service.execute(request('snapshot'), 'chat-b', 'b', () => false), /当前会话不匹配/);
  assert.throws(() => service.showForUser('chat-b'), /当前会话不匹配/);
});

test('request cancellation, endRequest and session deletion release a human wait', async () => {
  for (const mode of ['cancel', 'end', 'delete']) {
    const { run, service } = fixture();
    let cancelled = false;
    delayHook = () => {
      delayHook = null;
      if (mode === 'cancel') cancelled = true;
      if (mode === 'end') service.endRequest('request-a');
      if (mode === 'delete') service.closeSession('chat-a');
    };
    await assert.rejects(run('wait_for_user', {}, () => cancelled), /取消|关闭/);
    assert.equal(service.state.busy, false);
    assert.equal(service.state.waitingForUser, false);
  }
});

test('hide/back/background preserve model control and allow click, input and scrolling without reopening', async () => {
  const { run, service, calls, activity } = fixture();
  let frame = (await run('snapshot')).result.snapshot_id;
  assert.equal(service.dismissOnBack(), true);
  assert.equal(service.dismissOnBack(), false);
  service.setForeground(false);
  assert.equal(service.state.owner, 'model');
  let result = await run('click', { snapshot_id: frame, x: 20, y: 30 });
  assert.equal(result.result.action_executed, true);
  assert.equal(result.result.browser_visible, false);
  assert.equal(result.result.app_foreground, false);
  result = await run('type', { snapshot_id: result.result.snapshot_id, text: '后台输入', submit: true });
  result = await run('scroll', { snapshot_id: result.result.snapshot_id, delta_y: 200 });
  assert.ok(result.capture);
  assert.equal(service.state.visible, false);
  assert.deepEqual(calls.filter(call => ['click', 'type', 'scroll'].includes(call[0])),
    [['click', 40, 60], ['type', '后台输入', true], ['scroll', 800, 600, 0, 400]]);
  assert.ok(activity.every(active => active));
  service.setForeground(true);
  assert.equal(service.state.owner, 'model');
  assert.equal(service.state.visible, false);
});

test('hiding or backgrounding a user-controlled tab never silently grants the model control', async () => {
  const { run, service, calls, activity } = fixture();
  service.takeOver();
  service.hide();
  service.setForeground(false);
  assert.equal((await run('snapshot')).capture, null);
  assert.equal(service.state.owner, 'user');
  assert.equal(activity.at(-1), false);
  service.setForeground(true);
  service.showForUser('chat-a');
  assert.equal(service.state.owner, 'user');
  assert.equal((await run('snapshot')).result.status, 'user_control');
  assert.equal(calls.length, 0);
});

test('visibility changes while an action settles do not cancel its screenshot or reset the editable target', async () => {
  const { run, service, host } = fixture();
  const frame = (await run('snapshot')).result.snapshot_id;
  let resets = 0;
  host.resetKeyboard = () => { resets++; };
  delayHook = () => {
    delayHook = null;
    service.hide();
    service.setForeground(false);
  };
  const output = await run('click', { snapshot_id: frame, x: 10, y: 10 });
  assert.ok(output.capture);
  assert.equal(output.result.action_executed, true);
  assert.equal(resets, 0);
});

test('a new request reactivates an idle hidden tab without bringing it to the front', async () => {
  const { run, service, activity } = fixture();
  await run('snapshot');
  service.hide();
  service.setForeground(false);
  service.endRequest('request-a');
  assert.equal(service.state.owner, 'idle');
  assert.equal(activity.at(-1), false);
  const output = await service.execute(request('open', { url: 'https://example.com/next' }),
    'chat-a', 'request-b', () => false);
  assert.equal(output.result.action_executed, true);
  assert.ok(output.capture);
  assert.equal(activity.at(-1), true);
  assert.equal(service.state.visible, false);
  service.endRequest('request-b');
  assert.equal(activity.at(-1), false);
});

test('render/cancel pauses are not undone by background/foreground transitions', async () => {
  const { run, service } = fixture();
  service.pause('cancelled');
  service.hide();
  service.setForeground(false);
  service.setForeground(true);
  assert.equal((await run('snapshot')).capture, null);
  assert.equal(service.state.owner, 'paused');
  assert.equal(service.state.pauseReason, 'cancelled');
});

test('closing destroys the frame; late host attachment from the previous generation is ignored', async () => {
  const { run, service, host } = fixture();
  const oldGeneration = service.state.generation;
  await run('snapshot');
  service.closeSession('chat-a');
  service.showForUser('chat-b');
  service.attach(oldGeneration, host);
  assert.equal(service.host, null);
  service.closeSession('chat-b');
});

test('layout changes while capturing discard the image; a blocked capture has a deadline', async () => {
  const { run, service, host } = fixture();
  host.capture = async () => { service.invalidate(); return screenshot(); };
  await assert.rejects(run('snapshot'), /截图期间/);
  host.capture = () => new Promise(() => {});
  await assert.rejects(run('snapshot'), /截图超时/);
  assert.equal(service.state.busy, false);
});

test('takeover during image capture never returns the screenshot to the model', async () => {
  const { run, service, host } = fixture();
  host.capture = async () => { service.takeOver(); return screenshot(); };
  const output = await run('snapshot');
  assert.equal(output.capture, null);
  assert.equal(output.result.status, 'user_control');
});

test('a first open mounts a model-owned tab and rejects a cancelled open without creating one', async () => {
  const service = new BuiltinBrowserService();
  const open = request('open', { url: 'https://example.com/' });
  await assert.rejects(service.execute(open, 'new-chat', 'new-request', () => true), /取消/);
  assert.equal(service.state.sessionId, '');
  const host = {
    destroy() {}, setActive() {},
    navigate: url => { service.state.url = url; }, resetKeyboard() {},
    capture: async () => screenshot()
  };
  delayHook = () => { service.attach(service.state.generation, host); delayHook = null; };
  const result = await service.execute(open, 'new-chat', 'new-request', () => false);
  assert.equal(service.state.initialUrl, open.url);
  assert.equal(service.state.sessionId, 'new-chat');
  assert.equal(service.state.visible, true);
  assert.equal(service.state.owner, 'model');
  assert.ok(result.capture);
  service.endRequest('new-request');
  assert.equal(service.state.owner, 'idle');
});

test('first open can initialize while the application is already in the background', async () => {
  const service = new BuiltinBrowserService();
  service.setForeground(false);
  const host = { destroy() {}, setActive() {}, resetKeyboard() {},
    navigate: url => { service.state.url = url; }, capture: async () => screenshot() };
  delayHook = () => { service.attach(service.state.generation, host); delayHook = null; };
  const output = await service.execute(request('open', { url: 'https://example.com/' }), 'chat', 'request', () => false);
  assert.ok(output.capture);
  assert.equal(output.result.app_foreground, false);
  assert.equal(service.state.owner, 'model');
  service.closeSession('chat');
});

test('human wait expires without a screenshot or implicit control grant', async () => {
  const { run, calls, service } = fixture();
  delayHook = () => { now += 120001; delayHook = null; };
  const output = await run('wait_for_user');
  assert.equal(output.result.status, 'paused');
  assert.equal(output.capture, null);
  assert.equal(service.state.owner, 'paused');
  assert.equal(calls.length, 0);
});

test('executor returns screenshot bytes through the image side channel, never tool JSON', async () => {
  const service = getTestBrowser();
  if (service.state.sessionId) service.closeSession(service.state.sessionId);
  fixture(service);
  const exports = {};
  const code = fs.readFileSync(path.join(base, 'config/BuiltinBrowserTool.ets'), 'utf8');
  vm.runInNewContext(transpile(code), {
    exports,
    require: dependency => {
      if (dependency.endsWith('/BuiltinBrowserPolicy')) return policy;
      if (dependency.endsWith('/BuiltinBrowserManager')) return { getBuiltinBrowserManager: () => managerForBrowser(service) };
      if (dependency.endsWith('/NativeFileInputService')) return {
        canOfferNativeFileInput: context => context?.supportsVision,
        pushNativeFileInput: (context, id, name, mimeType, size, base64Data, filePath) => {
          context.inputAttachments.push({ id, name, mimeType, size, base64Data, filePath });
          return true;
        }
      };
      return {};
    }
  });
  const executor = new exports.BuiltinBrowserExecutor();
  const context = { sessionId: 'chat-a', requestId: 'request-a', actorId: 'main', supportsVision: true,
    inputAttachments: [], isCancelled: () => false };
  const output = JSON.parse(await executor.execute('{"action":"snapshot"}', context));
  assert.equal(context.inputAttachments.length, 1);
  assert.equal(context.inputAttachments[0].id, output.snapshot_id);
  assert.equal(context.inputAttachments[0].base64Data, 'eA==');
  assert.equal(context.inputAttachments[0].mimeType, 'image/jpeg');
  assert.equal(context.inputAttachments[0].filePath, '');
  assert.equal(JSON.stringify(output).includes('eA=='), false);
  await assert.rejects(executor.execute('{"action":"snapshot"}', { ...context, supportsVision: false }), /视觉模型/);
  await assert.rejects(executor.execute('{"action":"snapshot"}', { ...context, actorId: 'worker-1' }), /主智能体/);
  service.closeSession('chat-a');
});

// Extract only the non-UI native adapter class, so these tests exercise the exact production math/events.
const hostSource = fs.readFileSync(path.join(base, 'components/BuiltinBrowserHost.ets'), 'utf8');
const classStart = hostSource.indexOf('class BrowserNodeController');
const classEnd = hostSource.indexOf('\n@ComponentV2', classStart);
const enumValues = { TouchType: { Down: 0, Up: 1, Move: 2, Cancel: 3 }, SourceType: { TouchScreen: 2 }, SourceTool: { Finger: 1 },
  KeyType: { Down: 0, Up: 1 }, KeySource: { Keyboard: 1 },
  KeyCode: { KEYCODE_ENTER: 2054 }, IntentionCode: { INTENTION_UNKNOWN: -1 } };
const rect = { size: { width: 1600, height: 1200 }, windowOffset: { x: 60, y: 120 }, screenOffset: { x: 80, y: 150 } };
let releasePixels = 0, releasePacker = 0, failPacking = false;
const adapterContext = {
  exports: {}, NodeController: class {}, webview: { WebviewController: class {},
    WebSoftKeyboardBehaviorMode: { DEFAULT: 0, DISABLE_AUTO_KEYBOARD_ON_ACTIVE: 1 },
    UserAgentMetadata: class {
      setMobile(value) { this.mobile = value; }
      setFormFactors(value) { this.formFactors = Array.from(value); }
    }, UserAgentFormFactor: { MOBILE: 'Mobile', DESKTOP: 'Desktop' } }, ...enumValues,
  MODEL_POINTER_ID: 787, BuiltinBrowserService, isBrowserUrlAllowed: policy.isBrowserUrlAllowed,
  assertBrowserPoint: policy.assertBrowserPoint, buildBrowserUserAgent: policy.buildBrowserUserAgent,
  browserDelay, BrowserCapture, BrowserTypingResult, ...inputBridge, ...pageBridge, setTimeout, clearTimeout,
  inputMethod: { EnterKeyType: { UNSPECIFIED: 0, DONE: 6 } },
  systemDateTime: { TimeType: { ACTIVE: 1 }, getUptime: () => now * 1000000 },
  image: { createImagePacker: () => ({
    packToData: async () => { if (failPacking) throw new Error('packing failed'); return new Uint8Array([1, 2]).buffer; },
    release: async () => { releasePacker++; }
  }) },
  util: { Base64Helper: class { encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); } } }
};
vm.runInNewContext(transpile(`${hostSource.slice(classStart, classEnd)}\nexports.Adapter = BrowserNodeController;`), adapterContext);
function adapterFixture() {
  const adapter = new adapterContext.exports.Adapter();
  adapter.browser = getTestBrowser();
  adapter.componentId = 'builtin-browser-web-test';
  adapter.web.runJavaScript = async () => '"editable"';
  adapter.web.getUrl = () => 'https://example.com/';
  adapter.web.getTitle = () => 'Fixture';
  const events = [];
  const keys = [];
  adapter.ui = {
    dispatchKeyEvent: (id, event) => { keys.push({ id, ...JSON.parse(JSON.stringify(event)) }); return true; },
    px2vp: value => value / 2,
    vp2px: value => value * 2,
    getComponentUtils: () => ({ getRectangleById: () => rect }),
    getComponentSnapshot: () => ({ get: async () => ({
      getImageInfo: async () => ({ size: { width: 800, height: 600 } }),
      release: async () => { releasePixels++; }
    }) })
  };
  adapter.root = { postTouchEvent: event => { events.push(JSON.parse(JSON.stringify(event))); return true; } };
  return { adapter, events, keys };
}

test('native clicks dispatch local px plus window metadata, independent of screenshot scale', async () => {
  const { adapter, events } = adapterFixture();
  const pending = adapter.click(200, 300, () => false);
  assert.equal(events.length, 1, 'The press must get a frame before release.');
  await pending;
  assert.equal(events.length, 2);
  assert.deepEqual(events.map(event => event.type), [0, 1]);
  assert.equal(events[0].touches[0].x, 200);
  assert.equal(events[0].touches[0].y, 300);
  assert.equal(events[0].touches[0].windowX, 260);
  assert.equal(events[0].touches[0].windowY, 420);
  assert.equal(events[0].touches[0].displayX, 280);
  assert.equal(events[0].touches[0].displayY, 450);
  assert.equal(events[1].touches[0].id, 787);
  assert.ok(events[1].timestamp - events[0].timestamp >= 50 * 1000000);
});

test('slide animations and hidden presentation do not shift local clicks or cancel a native gesture', async () => {
  const { adapter, events } = adapterFixture();
  let shifted = rect;
  adapter.ui.getComponentUtils = () => ({ getRectangleById: () => shifted });
  delayHook = () => { shifted = { ...rect, windowOffset: { x: 60, y: 1520 } }; };
  await adapter.click(200, 300, () => false);
  delayHook = null;
  assert.deepEqual(events.map(event => event.type), [0, 1]);
  assert.deepEqual(events.map(event => [event.touches[0].x, event.touches[0].y]), [[200, 300], [200, 300]]);
  assert.equal(events[1].touches[0].windowY, 1820);
  events.length = 0;
  delayHook = () => { shifted = { ...rect, windowOffset: { x: 60, y: 120 } }; };
  await adapter.scroll(800, 600, 0, 400, () => false);
  delayHook = null;
  assert.equal(events.at(-1).type, 1);
  assert.equal(events.at(-1).touches[0].y, 200);
});

test('history arrows track the native history position and ignore callbacks from a closed tab', () => {
  const { service } = fixture();
  const { adapter } = adapterFixture();
  adapter.browser = service;
  adapter.generation = service.state.generation;
  let index = 0;
  let entries = 1;
  adapter.web.accessBackward = () => index > 0;
  adapter.web.accessForward = () => index < entries - 1;
  const arrows = () => [service.state.canGoBack, service.state.canGoForward];
  assert.deepEqual(arrows(), [false, false]);

  entries = 2;
  index = 1;
  adapter.navigationCommitted({ isMainFrame: true, isSameDocument: true, url: 'https://example.com/#section' });
  assert.deepEqual(arrows(), [true, false]);
  index = 0;
  adapter.syncHistoryAvailability();
  assert.deepEqual(arrows(), [false, true]);
  entries = 3;
  index = 1;
  adapter.navigationCommitted({ isMainFrame: true, isSameDocument: false, url: 'https://example.com/next' });
  assert.deepEqual(arrows(), [true, true]);

  service.closeSession('chat-a');
  service.showForUser('chat-a');
  adapter.syncHistoryAvailability();
  assert.deepEqual(arrows(), [false, false]);
});

test('initial Web.src navigation is not duplicated and late blank callbacks cannot overwrite it', () => {
  const service = getTestBrowser();
  fixture(service);
  const { adapter } = adapterFixture();
  adapter.generation = service.state.generation;
  adapter.initialUrl = 'https://example.com/first';
  const urls = [];
  adapter.web.loadUrl = url => urls.push(url);
  adapter.navigate(adapter.initialUrl);
  assert.deepEqual(urls, []);
  adapter.pageChanged(adapter.initialUrl, true);
  adapter.pageChanged('about:blank', false);
  assert.equal(service.state.url, adapter.initialUrl);
  assert.equal(service.state.loading, true);
  adapter.pageChanged(adapter.initialUrl, false);
  assert.equal(service.state.loading, false);
  adapter.navigate('https://example.com/second');
  assert.deepEqual(urls, ['https://example.com/second']);
  assert.equal(service.state.url, adapter.initialUrl, 'Requested URL is not yet the committed page.');
});

test('navigating a newly opened empty browser waits for its bootstrap document only once', () => {
  const service = getTestBrowser();
  fixture(service);
  const { adapter } = adapterFixture();
  adapter.generation = service.state.generation;
  adapter.web.getUrl = () => 'about:blank';
  const loads = [];
  adapter.web.loadUrl = url => loads.push(url);
  adapter.navigate('https://example.com/old');
  adapter.navigate('https://example.com/guide');
  assert.equal(loads.length, 0);
  assert.equal(service.state.loading, true);
  adapter.pageChanged('about:blank', false);
  assert.deepEqual(loads, ['https://example.com/guide']);
  adapter.pageChanged('https://example.com/guide', true);
  adapter.pageChanged('about:blank', false);
  assert.equal(loads.length, 1);
  assert.equal(service.state.url, 'https://example.com/guide');
});

test('same-document fragments do not reload; missing anchors produce explicit guidance', async () => {
  const service = getTestBrowser();
  fixture(service);
  const { adapter } = adapterFixture();
  adapter.generation = service.state.generation;
  adapter.web.loadUrl = () => assert.fail('same-document fragments must not reload');
  adapter.web.runJavaScript = async () => '"missing"';
  adapter.navigate('https://example.com/#article-structure');
  await Promise.resolve();
  assert.equal(service.state.loading, false);
  assert.match(service.state.error, /锚点|find/);
  adapter.navigationCommitted({ isMainFrame: true, isSameDocument: true, url: 'https://example.com/#actual' });
  assert.equal(service.state.url, 'https://example.com/#actual');
});

test('native find uses the first query then next match, and reads native match counts', () => {
  const service = getTestBrowser();
  fixture(service);
  const { adapter } = adapterFixture();
  adapter.generation = service.state.generation;
  const calls = [];
  adapter.web.searchAllAsync = text => calls.push(['all', text]);
  adapter.web.searchNext = forward => calls.push(['next', forward]);
  adapter.find('References');
  assert.equal(service.state.findDone, false);
  adapter.searchResult({ numberOfMatches: 3, activeMatchOrdinal: 0, isDoneCounting: true });
  adapter.find('References');
  adapter.find('Article structure');
  assert.deepEqual(calls, [['all', 'References'], ['next', true], ['all', 'Article structure']]);
});

test('a failed DOWN releases CANCEL, never a potentially confirming UP', async () => {
  const { adapter, events } = adapterFixture();
  adapter.root.postTouchEvent = event => {
    events.push(event.type);
    if (event.type === 0) throw new Error('dispatch');
    return true;
  };
  await assert.rejects(adapter.click(20, 20, () => false), /dispatch/);
  assert.deepEqual(events, [0, 3]);
});

test('click cancellation, changed viewport and failed hit-test never finish as a click', async () => {
  for (const cause of ['cancel', 'layout', 'detach', 'miss']) {
    const { adapter, events } = adapterFixture();
    let stopped = false;
    const post = adapter.root.postTouchEvent;
    adapter.root.postTouchEvent = event => { post(event); return cause !== 'miss'; };
    delayHook = () => {
      if (cause === 'cancel') stopped = true;
      if (cause === 'detach') adapter.root = null;
      if (cause === 'layout') adapter.ui.getComponentUtils = () => ({ getRectangleById: () => ({ ...rect,
        size: { width: 1200, height: 1600 } }) });
    };
    await assert.rejects(adapter.click(200, 300, () => stopped), /中止|派发失败/);
    delayHook = null;
    assert.deepEqual(events.map(event => event.type), [0, 3], cause);
    assert.ok(events[1].timestamp > events[0].timestamp, 'Even immediate cleanup needs a unique timestamp.');
  }
  const { adapter, events } = adapterFixture();
  await assert.rejects(adapter.click(200, 300, () => true), /中止/);
  assert.equal(events.length, 0);
});

test('service awaits the click release and passes takeover cancellation to the adapter', async () => {
  for (const takeover of [false, true]) {
    const { run, host, service, calls } = fixture();
    const { adapter, events } = adapterFixture();
    host.click = (...args) => adapter.click(...args);
    const frame = (await run('snapshot')).result.snapshot_id;
    calls.length = 0;
    delayHook = ms => {
      if (ms !== 50) return;
      assert.equal(calls.some(call => call[0] === 'snapshot'), false);
      if (takeover) service.takeOver();
    };
    const result = run('click', { snapshot_id: frame, x: 50, y: 80 });
    if (takeover) {
      await assert.rejects(result, /中止/);
      assert.deepEqual(events.map(event => event.type), [0, 3]);
      assert.equal(calls.length, 0);
    } else {
      assert.equal((await result).result.action_executed, true);
      assert.deepEqual(events.map(event => event.type), [0, 1]);
      assert.deepEqual(calls, [['snapshot']]);
    }
    assert.equal(service.state.busy, false);
    delayHook = null;
  }
});

test('only explicit header takeover enters user control; focus/page/lifecycle work remains idle or paused', async () => {
  const { service, run, host } = fixture();
  service.endRequest('unrelated-request');
  assert.equal(service.state.owner, 'model');
  service.showForUser('chat-a');
  assert.equal(service.state.owner, 'model');
  service.invalidate(); // Navigation, layout and scroll notifications do not transfer control.
  await run('snapshot');
  service.endRequest('request-a');
  assert.equal(service.state.owner, 'idle');
  assert.throws(() => service.userNavigate('https://example.com/'), /接管页面/);
  assert.throws(() => service.userNavigateHistory('back'), /接管页面/);
  await run('snapshot'); // A new request can use an idle tab without asking the user to give it back.
  assert.equal(service.state.owner, 'model');
  service.takeOver(); // The header button.
  assert.equal(service.state.owner, 'user');
  service.userNavigate('https://example.com/manual');
  assert.equal(service.state.url, 'https://example.com/manual');
  service.resume();
  assert.equal(service.state.owner, 'model');
  service.setForeground(false);
  assert.equal(service.state.owner, 'model');
  service.setForeground(true);
  service.showForUser('chat-a');
  assert.equal(service.state.owner, 'model');
  host.capture = async () => screenshot();
  assert.ok((await run('snapshot')).capture);
});

test('browser launch and blank-page navigation require approval; active-page controls and handoff do not', () => {
  const source = fs.readFileSync(path.join(base, 'services/ToolExecutionService.ets'), 'utf8');
  const parsed = ts.createSourceFile('approval.ts', source, ts.ScriptTarget.Latest, true);
  const fn = parsed.statements.find(node => ts.isFunctionDeclaration(node) && node.name.text === 'requiresToolApproval');
  const service = new BuiltinBrowserService();
  const context = { exports: {}, BUILTIN_BROWSER_TOOL_ID: 'builtin_browser',
    parseBrowserRequest: policy.parseBrowserRequest, getBuiltinBrowserManager: () => managerForBrowser(service),
    ToolPermissionLevel: { WRITE: 'write', READ: 'read' } };
  vm.runInNewContext(transpile(fn.getText(parsed)), context);
  const needsApproval = (tool, args) => context.exports.requiresToolApproval(tool, args, 'chat-a');
  const browser = { id: 'builtin_browser', permissionLevel: 'write', requiresUserApproval: true,
    approvalRequiredActions: Array.from(policy.BROWSER_ACTIONS) };
  const actions = [
    { action: 'open', url: 'https://example.com/' },
    { action: 'snapshot' },
    { action: 'read_page' },
    { action: 'find', snapshot_id: 'browser-1-1', text: 'Article structure' },
    { action: 'click', snapshot_id: 'browser-1-1', x: 5, y: 8 },
    { action: 'scroll', snapshot_id: 'browser-1-1', delta_y: 300 },
    { action: 'type', snapshot_id: 'browser-1-1', text: '中文 input', submit: true },
    { action: 'back', snapshot_id: 'browser-1-1' },
    { action: 'forward', snapshot_id: 'browser-1-1' },
    { action: 'reload', snapshot_id: 'browser-1-1' },
    { action: 'set_page_mode', snapshot_id: 'browser-1-1', page_mode: 'desktop' },
    { action: 'wait_for_user' }
  ];
  assert.deepEqual(actions.map(args => args.action).sort(), Array.from(policy.BROWSER_ACTIONS).sort());
  for (const args of actions) {
    for (const raw of [JSON.stringify(args), JSON.stringify(JSON.stringify(args)),
      JSON.stringify({ arguments: JSON.stringify(args) })]) {
      assert.equal(policy.parseBrowserRequest(raw).action, args.action);
      assert.equal(needsApproval(browser, raw), args.action === 'open', args.action);
      assert.equal(needsApproval({ ...browser, id: 'other-write-tool' }, raw), true);
    }
  }
  const open = JSON.stringify(actions[0]);
  service.showForUser('chat-a');
  assert.equal(needsApproval(browser, open), true, 'a manually opened blank tab still needs confirmation');
  for (const url of ['', 'about:blank', 'about:blank#section', 'about:blank?test=1']) {
    service.state.url = url;
    assert.equal(needsApproval(browser, open), true, url);
  }
  service.state.url = 'https://example.com/';
  service.hide();
  service.setForeground(false);
  for (const args of actions) {
    assert.equal(needsApproval(browser, JSON.stringify(args)), false, `existing page: ${args.action}`);
  }
  service.state.url = 'about:blank';
  assert.equal(needsApproval(browser, open), true, 'returning to a blank page requires confirmation again');
  assert.equal(needsApproval(browser, '{"action":"wait_for_user"}'), false);
  service.state.url = 'https://example.com/';
  service.closeSession('chat-a');
  assert.equal(needsApproval(browser, open), true, 'closed tabs require approval even if the previous URL is retained');
  const readTool = { id: 'other-read-tool', permissionLevel: 'read', requiresUserApproval: false,
    approvalRequiredActions: ['delete'] };
  assert.equal(needsApproval(readTool, '{"action":"list"}'), false);
  assert.equal(needsApproval(readTool, '{"action":"delete"}'), true);
  assert.equal(needsApproval({ ...readTool, requiresUserApproval: true }, '{"action":"list"}'), true);
  // Invalid calls go straight to validation, never to an approval dialog.
  for (const raw of ['{"action":"click"', '{"action":"unknown"}', '{"action":"back"}']) {
    assert.equal(needsApproval(browser, raw), false);
    assert.throws(() => policy.parseBrowserRequest(raw));
  }
});

test('launch confirmation blocks execution until approved; rejection and cancellation never create a tab', async () => {
  const service = new BuiltinBrowserService();
  const { calls, host } = fixture(service);
  service.closeSession('chat-a');
  calls.length = 0;
  const browser = { id: 'builtin_browser', name: 'Browser', sourceType: 'builtin', sourceLabel: 'Built-in',
    permissionLevel: 'write', requiresUserApproval: false, approvalRequiredActions: [] };
  const executor = { execute: async (args, context) => JSON.stringify((await service.execute(
    policy.parseBrowserRequest(args), context.sessionId, context.requestId, context.isCancelled)).result) };
  const registered = { id: browser.id, config: browser, definition: { function: { name: browser.id } }, executor };
  const registry = {
    getToolIdByFunctionName: name => name === browser.id ? browser.id : undefined,
    getTool: id => id === browser.id ? registered : undefined,
    getToolExecutor: id => id === browser.id ? executor : undefined
  };
  class ToolContext {
    constructor() {
      this.sessionId = 'chat-a'; this.requestId = 'request-a'; this.actorId = 'main';
      this.inputAttachments = []; this.isCancelled = () => false;
    }
    withActor(actorId) { return Object.assign(new ToolContext(), this, { actorId, inputAttachments: [] }); }
  }
  class ToolResult {
    constructor(toolCallId, content, isError, displayName, sourceLabel) {
      Object.assign(this, { toolCallId, content, isError, displayName, sourceLabel });
    }
  }
  const exports = {};
  vm.runInNewContext(transpile(fs.readFileSync(path.join(base, 'services/ToolExecutionService.ets'), 'utf8')), {
    exports, console, Date,
    require: dependency => {
      if (dependency.endsWith('/BuiltinBrowserPolicy')) return policy;
      if (dependency.endsWith('/BuiltinBrowserManager')) return { getBuiltinBrowserManager: () => managerForBrowser(service) };
      if (dependency.endsWith('/ToolRegistry')) return { getToolRegistry: () => registry, ToolExecutionContext: ToolContext };
      if (dependency.endsWith('/ChatModels')) return { ToolResult, ToolPermissionLevel: { WRITE: 'write', READ: 'read' } };
      if (dependency.endsWith('/BuiltinTools')) return { ASK_USER_TOOL_ID: 'ask_user' };
      if (dependency.endsWith('/ToolIdAliases')) return { resolveLegacyToolId: id => id };
      if (dependency.endsWith('/PromptLanguageUtils')) return { PromptLanguage: { ZH_CN: 'zh-CN' } };
      if (dependency.endsWith('/ToolProgressGuard')) return { ToolProgressGuard: class {
        shouldStop() { return false; } observe() { return ''; }
      } };
      return {};
    }
  });
  const execution = exports.ToolExecutionService.getInstance();
  const context = new ToolContext();
  let decision, confirmations = 0, sequence = 0;
  execution.setApprovalCallback(() => {
    confirmations++;
    return new Promise(resolve => { decision = resolve; });
  });
  const run = (action, fields = {}) => execution.executeToolCall({
    id: `approval-test-${++sequence}`, functionName: browser.id,
    arguments: JSON.stringify({ action, ...fields }), displayName: '', sourceLabel: ''
  }, [browser.id], context);

  let pending = run('open', { url: 'https://example.com/' });
  assert.equal(confirmations, 1);
  assert.equal(service.state.sessionId, '', 'no browser is mounted while confirmation is pending');
  assert.equal(calls.length, 0);
  decision(exports.ToolApprovalResult.reject());
  assert.equal(JSON.parse((await pending).content).rejected, true);
  assert.equal(service.state.sessionId, '');
  assert.equal(calls.length, 0);

  pending = run('open', { url: 'https://example.com/' });
  decision(exports.ToolApprovalResult.cancel());
  assert.equal(JSON.parse((await pending).content).cancelled, true);
  assert.equal(service.state.sessionId, '');
  assert.equal(calls.length, 0);

  delayHook = () => service.attach(service.state.generation, host);
  pending = run('open', { url: 'https://example.com/' });
  assert.equal(confirmations, 3);
  assert.equal(service.state.sessionId, '');
  decision(exports.ToolApprovalResult.approve());
  const opened = await pending;
  assert.equal(opened.isError, false);
  assert.equal(service.state.url, 'https://example.com/');
  assert.equal(calls.filter(call => call[0] === 'open').length, 1);
  delayHook = null;

  service.hide();
  service.setForeground(false);
  assert.equal((await run('snapshot')).isError, false);
  assert.equal((await run('open', { url: 'https://example.com/next' })).isError, false);
  assert.equal(confirmations, 3, 'normal browsing continues without another prompt');

  service.state.url = 'about:blank';
  const navigationCount = calls.filter(call => call[0] === 'open').length;
  pending = run('open', { url: 'https://example.com/again' });
  assert.equal(confirmations, 4);
  assert.equal(calls.filter(call => call[0] === 'open').length, navigationCount);
  decision(exports.ToolApprovalResult.reject());
  assert.equal(JSON.parse((await pending).content).rejected, true);
  assert.equal(service.state.url, 'about:blank');
  assert.equal(calls.filter(call => call[0] === 'open').length, navigationCount);

  service.closeSession('chat-a');
  pending = run('open', { url: 'https://example.com/reopen' });
  assert.equal(confirmations, 5);
  context.isCancelled = () => true;
  decision(exports.ToolApprovalResult.approve());
  assert.equal((await pending).isError, true);
  assert.equal(service.state.sessionId, '', 'cancelling the request during approval never mounts a tab');
  assert.equal(calls.filter(call => call[0] === 'open').length, navigationCount);
});

test('text uses the real keyboard callback controller without invoking the fallback after insertion', async () => {
  const { adapter } = adapterFixture();
  const calls = [];
  adapter.web.runJavaScript = async script => {
    assert.equal(script, inputBridge.BROWSER_FOCUSED_EDITOR_SCRIPT);
    return '"editable"';
  };
  adapter.keyboard = { insertText: text => calls.push(['text', text]), sendFunctionKey: key => calls.push(['enter', key]) };
  const result = await adapter.type('中文 ✓', true, () => false);
  assert.deepEqual(calls, [['text', '中文 ✓'], ['enter', 6]]);
  assert.equal(result.inputMethod, 'native_keyboard');
  assert.equal(result.textInserted, true);
  assert.equal(result.submitSent, true);
  adapter.keyboard.insertText = () => { throw new Error('uncertain native result'); };
  await assert.rejects(adapter.type('do not duplicate', false, () => false), /uncertain native result/);
});

test('same-input clicks and delayed load completion preserve the keyboard; navigation closes it', async () => {
  const service = getTestBrowser();
  fixture(service);
  const { adapter } = adapterFixture();
  adapter.generation = service.state.generation;
  let closes = 0;
  const keyboard = { close: () => { closes++; } };
  adapter.keyboard = keyboard;
  await adapter.click(100, 100, () => false);
  assert.equal(adapter.keyboard, keyboard);
  service.state.url = 'https://example.com/';
  adapter.pageChanged('https://example.com/', false);
  assert.equal(adapter.keyboard, keyboard);
  assert.equal(closes, 0);
  adapter.pageChanged('https://example.com/next', true);
  assert.equal(adapter.keyboard, null);
  assert.equal(closes, 1);
  service.closeSession('chat-a');
});

test('focused editor without a keyboard sends native Enter to its Web node after inserting once', async () => {
  const { adapter, keys } = adapterFixture();
  const scripts = [];
  adapter.web.runJavaScript = async script => {
    scripts.push(script);
    return script === inputBridge.BROWSER_FOCUSED_EDITOR_SCRIPT ? '"editable"' : '"inserted"';
  };
  assert.equal((await adapter.capture()).focusedEditable, true);
  scripts.length = 0;
  const result = await adapter.type('中文\n"text"', true, () => false);
  assert.equal(scripts.length, 2);
  assert.equal(result.textInserted, true);
  assert.equal(result.submitSent, true);
  assert.equal(result.inputMethod, 'focused_element');
  assert.deepEqual(keys.map(key => [key.id, key.type, key.keyCode]), [
    ['builtin-browser-web-test', 0, 2054], ['builtin-browser-web-test', 1, 2054]
  ]);
  assert.ok(keys[1].timestamp > keys[0].timestamp);
});

test('Enter-only works on a focused control in a hidden tab without reinserting text or taking focus', async () => {
  const service = getTestBrowser();
  fixture(service);
  service.hide();
  service.setForeground(false);
  for (const focus of ['editable', 'none', 'opaque']) {
    const { adapter, keys } = adapterFixture();
    adapter.web.runJavaScript = async script => {
      assert.equal(script, inputBridge.BROWSER_FOCUSED_EDITOR_SCRIPT);
      return JSON.stringify(focus);
    };
    const result = await adapter.type('', true, () => false);
    assert.equal(result.textInserted, false);
    assert.equal(result.submitSent, true);
    assert.equal(keys.length, 2);
    assert.equal(service.state.visible, false);
    assert.equal(service.state.owner, 'model');
  }
  const { run } = fixture();
  const frame = (await run('snapshot')).result.snapshot_id;
  const output = await run('type', { snapshot_id: frame, text: '', submit: true });
  assert.equal(output.result.action_executed, true);
  assert.equal(output.result.text_inserted, false);
  assert.equal(output.result.submit_sent, true);
});

test('physical keys remain blocked, except Enter synchronously dispatched by the model', async () => {
  const service = getTestBrowser();
  fixture(service);
  const { adapter } = adapterFixture();
  const enter = { keyCode: 2054, type: 0 };
  assert.equal(adapter.blockHardwareKey(enter), true);
  let dispatched = 0;
  adapter.ui.dispatchKeyEvent = (_id, event) => {
    dispatched++;
    assert.equal(adapter.blockHardwareKey(event), false);
    assert.equal(adapter.blockHardwareKey({ ...event, keyCode: 2017 }), true);
    // Not consumed is not a reason to replay the Enter or fall back to another channel.
    return false;
  };
  assert.equal((await adapter.type('', true, () => false)).submitSent, true);
  assert.equal(dispatched, 2);
  assert.equal(adapter.blockHardwareKey(enter), true);
  service.takeOver();
  assert.equal(adapter.blockHardwareKey(enter), false);
});

test('Enter errors preserve insertion progress, release the key guard and never replay submission', async () => {
  for (const channel of ['native', 'key-down', 'key-up']) {
    const { adapter, keys } = adapterFixture();
    adapter.web.runJavaScript = async script => script === inputBridge.BROWSER_FOCUSED_EDITOR_SCRIPT ? '"editable"' : '"inserted"';
    const calls = [];
    if (channel === 'native') {
      adapter.keyboard = {
        insertText: text => calls.push(text),
        sendFunctionKey: () => { calls.push('enter'); throw new Error('uncertain'); }
      };
    } else {
      adapter.ui.dispatchKeyEvent = (_id, event) => {
        calls.push(event.type);
        if (event.type === (channel === 'key-down' ? 0 : 1)) throw new Error('uncertain');
        return true;
      };
    }
    const result = await adapter.type('once', true, () => false);
    assert.equal(result.textInserted, true);
    assert.equal(result.submitSent, false);
    assert.match(result.message, /可能已发生/);
    assert.deepEqual(calls, channel === 'native' ? ['once', 'enter'] : [0, 1]);
    assert.equal(keys.length, 0);
    assert.equal(adapter.dispatchingModelEnter, false);
  }
});

test('cancellation after insertion does not submit; replaced keyboard is never used', async () => {
  for (const cause of ['cancel', 'keyboard']) {
    const { adapter, keys } = adapterFixture();
    let stopped = false;
    let inserts = 0;
    adapter.keyboard = { insertText: () => { inserts++; }, sendFunctionKey: () => assert.fail('must not submit') };
    delayHook = () => {
      if (cause === 'cancel') stopped = true;
      else adapter.keyboard = null;
    };
    const pending = adapter.type('once', true, () => stopped);
    if (cause === 'cancel') await assert.rejects(pending, /未发送 Enter/);
    else {
      const result = await pending;
      assert.equal(result.textInserted, true);
      assert.equal(result.submitSent, false);
      assert.match(result.message, /已切换/);
    }
    delayHook = null;
    assert.equal(inserts, 1);
    assert.equal(keys.length, 0);
  }
});

test('navigation between text insertion and Enter never submits into the next document', async () => {
  const service = getTestBrowser();
  fixture(service);
  const { adapter, keys } = adapterFixture();
  adapter.generation = service.state.generation;
  adapter.web.runJavaScript = async script => script === inputBridge.BROWSER_FOCUSED_EDITOR_SCRIPT ? '"editable"' : '"inserted"';
  delayHook = () => {
    adapter.pageChanged('https://example.com/next', true);
    adapter.pageChanged('https://example.com/next', false);
  };
  const result = await adapter.type('once', true, () => false);
  delayHook = null;
  assert.equal(result.textInserted, true);
  assert.equal(result.submitSent, false);
  assert.match(result.message, /已切换/);
  assert.equal(keys.length, 0);
});

test('non-editable focus and cancellation block input even if a cached keyboard exists', async () => {
  const { adapter } = adapterFixture();
  adapter.keyboard = { insertText: () => assert.fail('must not insert'), sendFunctionKey: () => assert.fail('must not submit') };
  adapter.web.runJavaScript = async () => '"none"';
  assert.equal((await adapter.capture()).focusedEditable, false);
  await assert.rejects(adapter.type('test', false, () => false), /没有可编辑输入框/);
  let cancelled = false;
  adapter.web.runJavaScript = async () => { cancelled = true; return '"editable"'; };
  await assert.rejects(adapter.type('test', false, () => cancelled), /已取消/);
});

test('opaque frames use an attached native controller, and never a guessed DOM target', async () => {
  const { adapter } = adapterFixture();
  adapter.web.runJavaScript = async () => '"opaque"';
  await assert.rejects(adapter.type('test', false, () => false), /跨域 iframe/);
  let inserted = '';
  adapter.keyboard = { insertText: text => { inserted = text; } };
  await adapter.type('test', false, () => false);
  assert.equal(inserted, 'test');
});

test('tool results retain typing progress when fallback cannot send Enter', async () => {
  const { run, host } = fixture();
  host.type = async () => Object.assign(new BrowserTypingResult(), {
    inputMethod: 'focused_element', textInserted: true, submitSent: false, message: '未发送 Enter；请点击提交。'
  });
  const frame = (await run('snapshot')).result.snapshot_id;
  const output = await run('type', { snapshot_id: frame, text: 'query', submit: true });
  assert.equal(output.result.action_executed, true);
  assert.equal(output.result.text_inserted, true);
  assert.equal(output.result.submit_sent, false);
  assert.equal(output.result.input_method, 'focused_element');
  assert.match(output.result.message, /未发送 Enter/);
  assert.ok(output.capture);
});

test('mobile/desktop UA and Client Hints agree without replacing installed engine versions', () => {
  const { adapter } = adapterFixture();
  const ua = 'Mozilla/5.0 (Tablet; OpenHarmony 7.0) AppleWebKit/537.36 Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.1.2 Mobile';
  let readCount = 0;
  const agents = [], hints = [];
  adapter.web.getUserAgent = () => { readCount++; return ua; };
  adapter.web.setUserAgentMetadata = (agent, metadata) => hints.push([agent, metadata.mobile, metadata.formFactors]);
  adapter.web.setCustomUserAgent = agent => agents.push(agent);
  adapter.setPageMode('desktop');
  adapter.setPageMode('mobile');
  assert.equal(readCount, 1);
  assert.ok(agents[0].includes('(PC; OpenHarmony 7.0)'));
  assert.ok(!agents[0].includes('Mobile'));
  assert.ok(agents[1].includes('(Phone; OpenHarmony 7.0)'));
  assert.ok(agents[1].endsWith(' Mobile'));
  for (const agent of agents) {
    assert.ok(agent.includes('Chrome/132.0.0.0'));
    assert.ok(agent.includes('ArkWeb/6.0.1.2'));
  }
  assert.deepEqual(hints, [[agents[0], false, ['Desktop']], [agents[1], true, ['Mobile']]]);
  assert.equal(policy.buildBrowserUserAgent(agents[1], 'mobile'), agents[1]);
});

test('page mode initialization errors pause the host instead of escaping the native attach callback', () => {
  const service = getTestBrowser();
  fixture(service);
  service.detach(service.state.generation);
  const { adapter } = adapterFixture();
  adapter.generation = service.state.generation;
  adapter.web.getUserAgent = () => { throw new Error('native initialization failed'); };
  assert.doesNotThrow(() => adapter.attach());
  assert.equal(service.state.owner, 'paused');
  assert.equal(service.state.pauseReason, 'page_mode_initialization_failed');
  assert.match(service.state.error, /页面模式初始化失败/);
  service.closeSession('chat-a');
});

test('nested scroll sends a paced native gesture at the chosen point with opposite finger direction', async () => {
  const { adapter, events } = adapterFixture();
  adapter.web.scrollBy = () => assert.fail('must not scroll only the root page');
  await adapter.scroll(800, 600, 200, 400, () => false);
  assert.equal(events[0].type, 0);
  assert.equal(events.at(-1).type, 1);
  assert.ok(events.slice(1, -1).every(event => event.type === 2 && event.pressure === 1));
  assert.deepEqual([events[0].touches[0].windowX, events[0].touches[0].windowY], [860, 720]);
  assert.deepEqual([events.at(-1).touches[0].windowX, events.at(-1).touches[0].windowY], [660, 320]);
  assert.ok(events.every(event => event.touches[0].id === 787));
  assert.ok(events.at(-1).timestamp > events[0].timestamp);
  events.length = 0;
  await adapter.scroll(800, 600, -200, -400, () => false);
  assert.deepEqual([events.at(-1).touches[0].windowX, events.at(-1).touches[0].windowY], [1060, 1120]);
});

test('scroll stays inside the viewport and never generates a tap for tiny/edge gestures', async () => {
  const { adapter, events } = adapterFixture();
  await adapter.scroll(800, 600, 0, 8000, () => false);
  assert.ok(events.every(event => event.touches[0].windowY >= rect.windowOffset.y + 4));
  assert.equal(events.at(-1).touches[0].windowY, rect.windowOffset.y + 4);
  assert.equal(events.filter(event => event.type === 0).length, 1);
  events.length = 0;
  await assert.rejects(adapter.scroll(800, 600, 0, 1, () => false), /滚动距离太小/);
  await assert.rejects(adapter.scroll(800, 2, 0, 400, () => false), /滚动距离太小/);
  assert.equal(events.length, 0);
});

test('scroll cancellation, takeover, layout changes and dispatch errors release CANCEL without an UP click', async () => {
  for (const cause of ['cancel', 'layout', 'dispatch']) {
    const { adapter, events } = adapterFixture();
    let stopped = false;
    let moved = false;
    adapter.root.postTouchEvent = event => {
      events.push(event);
      if (event.type === 2) {
        if (cause === 'dispatch') return false;
        moved = true;
      }
      return true;
    };
    delayHook = () => {
      if (!moved) return;
      delayHook = null;
      if (cause === 'cancel') stopped = true;
      if (cause === 'layout') adapter.ui.getComponentUtils = () => ({ getRectangleById: () => ({ ...rect,
        size: { width: 1200, height: 1600 } }) });
    };
    await assert.rejects(adapter.scroll(800, 600, 0, 400, () => stopped), /中止|失败/);
    delayHook = null;
    assert.equal(events.at(-1).type, 3);
    assert.equal(events.some(event => event.type === 1), false);
  }
  const { run, host, service } = fixture();
  const { adapter, events } = adapterFixture();
  host.scroll = (...args) => adapter.scroll(...args);
  const frame = (await run('snapshot')).result.snapshot_id;
  delayHook = () => { delayHook = null; service.takeOver(); };
  await assert.rejects(run('scroll', { snapshot_id: frame, delta_y: 200 }), /中止/);
  assert.equal(service.state.owner, 'user');
  assert.equal(events.at(-1).type, 3);
  assert.equal(service.state.busy, false);
});

test('background activation does not request automatic keyboard display and window blur preserves model input', async () => {
  const { adapter } = adapterFixture();
  const service = getTestBrowser();
  const calls = [];
  service.state.owner = 'model';
  adapter.web.setSoftKeyboardBehaviorMode = mode => calls.push(['mode', mode]);
  adapter.web.onActive = () => calls.push(['active']);
  adapter.web.onInactive = () => calls.push(['inactive']);
  adapter.setActive(true);
  assert.deepEqual(calls, [['mode', 1], ['active']]);
  const keyboard = { insertText: text => calls.push(['text', text]), close: () => calls.push(['close']) };
  adapter.keyboard = keyboard;
  adapter.handleBlur();
  assert.equal(adapter.keyboard, keyboard);
  await adapter.type('continue in background', false, () => false);
  assert.deepEqual(calls.at(-1), ['text', 'continue in background']);
  service.state.owner = 'user';
  adapter.handleBlur();
  assert.equal(adapter.keyboard, null);
  adapter.setActive(false);
  assert.deepEqual(calls.slice(-3), [['close'], ['mode', 0], ['inactive']]);
  service.state.owner = 'idle';
});

test('image pixels and packer are released on success and encoding failure', async () => {
  const pixelsBefore = releasePixels;
  const packerBefore = releasePacker;
  const { adapter } = adapterFixture();
  const shot = await adapter.capture();
  assert.equal(shot.width, 800);
  assert.equal(shot.viewportWidth, 1600);
  failPacking = true;
  await assert.rejects(adapter.capture(), /packing failed/);
  failPacking = false;
  assert.equal(releasePixels - pixelsBefore, 2);
  assert.equal(releasePacker - packerBefore, 2);
});

test('request context retains two latest browser images and preserves user/file images and tool results', async () => {
  const source = fs.readFileSync(path.join(base, 'services/AIApiService.ets'), 'utf8');
  const parsed = ts.createSourceFile('api.ts', source, ts.ScriptTarget.Latest, true);
  const requestClass = parsed.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'RequestMessage');
  const method = requestClass.members.find(node => node.name?.getText(parsed) === 'trimBrowserSnapshots');
  const context = { exports: {} };
  vm.runInNewContext(transpile(`export class Message { ${method.getText(parsed)} }`), context);
  const { run } = fixture();
  const frames = ['browser-1-1', 'browser-1-2'];
  for (let i = 0; i < 4; i++) frames.push((await run('snapshot')).result.snapshot_id);
  const messages = [
    { sourceToolCallId: '', attachments: [{ id: 'user-image' }] },
    ...frames.map((id, i) => ({ sourceToolCallId: `tool-${i}`, attachments: [{ id }] })),
    { sourceToolCallId: 'read-file', attachments: [{ id: 'workspace-image' }] },
    { sourceToolCallId: '', role: 'tool', content: '{"snapshot_id":"browser-1-1"}', attachments: [] }
  ];
  context.exports.Message.trimBrowserSnapshots(messages);
  assert.deepEqual(messages.flatMap(message => message.attachments.map(attachment => attachment.id)),
    ['user-image', ...frames.slice(-2), 'workspace-image']);
  assert.equal(messages.at(-1).content, '{"snapshot_id":"browser-1-1"}');
});

(async () => {
  for (const { name, fn } of cases) {
    try {
      await fn();
      console.log(`PASS ${name}`);
    } finally {
      delayHook = null;
    }
  }
  console.log(`${cases.length} browser tests passed.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
