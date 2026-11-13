// Build the HAP first: this regression needs ArkTS's actual @Builder transformation.
// Plain TypeScript transpilation cannot reproduce a lost ArkUI builder receiver.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.XCUBE_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
const root = path.resolve(__dirname, '..');
const sourcePath = path.join(root, 'entry/src/main/ets/components/BuiltinBrowserHost.ets');
const compiledPath = process.env.XCUBE_COMPILED_BROWSER_HOST || path.join(root,
  'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/components/BuiltinBrowserHost.ts');
assert.ok(fs.existsSync(compiledPath), 'Build assembleHap --no-incremental before running the keyboard regression.');
assert.ok(fs.statSync(compiledPath).mtimeMs >= fs.statSync(sourcePath).mtimeMs,
  'The compiled browser host is stale; rebuild assembleHap --no-incremental.');
const compiled = ts.createSourceFile(compiledPath, fs.readFileSync(compiledPath, 'utf8'), ts.ScriptTarget.Latest, true);
const names = new Set(['ModelKeyboard', 'BrowserNodeController', 'BuiltinBrowserTab']);
const code = compiled.statements.filter(node => names.has(node.name?.text))
  .map(node => node.getText(compiled)).join('\n');
assert.match(code, /observeComponentCreation2/, 'Use the ArkTS-transformed component, not uncompiled .ets.');

const service = {
  state: { generation: 1, owner: 'model', sessionId: 'chat', visible: true },
  isCurrent(generation) { return this.state.sessionId !== '' && this.state.generation === generation; },
  detach() {}
};
const observations = [];
const rows = [];
const context = {
  exports: {},
  getBuiltinBrowserService: () => service,
  NodeController: class {},
  webview: { WebviewController: class {} },
  ViewV2: class {
    initParam(name, value) { this[name] = value; }
    finalizeConstruction() {}
    observeComponentCreation2(builder, type) {
      observations.push({ owner: this, type });
      builder(1, true);
    }
  },
  Row: {
    create: () => rows.push('create'),
    width: value => rows.push(['width', value]),
    height: value => rows.push(['height', value]),
    pop: () => rows.push('pop')
  }
};
const javascript = ts.transpileModule(`${code.replace(/@Param\s*/g, '')}\nexports.Tab = BuiltinBrowserTab;`, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, alwaysStrict: true }
}).outputText;
vm.runInNewContext(javascript, context, { filename: compiledPath });
function tabFixture(mount = true) {
  const tab = new context.exports.Tab(null, { generation: service.state.generation });
  if (mount) tab.aboutToAppear();
  let closes = 0;
  const controller = { close: () => { closes++; } };
  return { tab, node: tab.node, info: { controller, attributes: {} }, closes: () => closes };
}
function invokeDetached(options) {
  // ArkWeb invokes the builder later without the owning component as `this`.
  const builder = options.customKeyboard;
  assert.equal(typeof builder, 'function');
  builder();
}
function test(name, run) {
  Object.assign(service.state, { generation: 1, owner: 'model', sessionId: 'chat', visible: true });
  observations.length = 0;
  rows.length = 0;
  run();
  console.log(`PASS ${name}`);
}

test('compiled keyboard builder retains the tab receiver when ArkWeb calls it detached', () => {
  const { tab, node, info } = tabFixture();
  const options = node.keyboardAttached(info);
  assert.equal(options.useSystemKeyboard, false);
  assert.equal(node.keyboard, info.controller);
  invokeDetached(options);
  assert.equal(observations.length, 1);
  assert.equal(observations[0].owner, tab);
  assert.equal(observations[0].type, context.Row);
  assert.deepEqual(rows, ['create', ['width', '100%'], ['height', 1], 'pop']);
  service.state.visible = false;
  invokeDetached(node.keyboardAttached(info));
  assert.equal(observations.length, 2, 'A hidden tab still supports the model keyboard.');
});

test('explicit user takeover uses the system keyboard and invalidates queued model builders', () => {
  const { node, info } = tabFixture();
  const modelOptions = node.keyboardAttached(info);
  service.state.owner = 'user';
  const userOptions = node.keyboardAttached(info);
  assert.equal(userOptions.useSystemKeyboard, true);
  assert.equal(userOptions.customKeyboard, undefined);
  invokeDetached(modelOptions);
  assert.equal(observations.length, 0);
  service.state.owner = 'model';
  node.resetKeyboard();
  invokeDetached(modelOptions);
  assert.equal(observations.length, 0, 'A closed input controller must not reopen its keyboard.');
  invokeDetached(node.keyboardAttached(info));
  assert.equal(observations.length, 1);
});

test('unmounted and destroyed tabs cannot build a keyboard or retain a controller', () => {
  const { tab, node, info, closes } = tabFixture(false);
  node.generation = service.state.generation;
  invokeDetached(node.keyboardAttached(info));
  assert.equal(node.keyboard, null);
  assert.equal(observations.length, 0);
  tab.aboutToAppear();
  const options = node.keyboardAttached(info);
  tab.aboutToDisappear();
  assert.equal(closes(), 1);
  assert.equal(node.keyboard, null);
  assert.equal(node.modelKeyboardBuilder, null);
  invokeDetached(options);
  invokeDetached(node.keyboardAttached(info));
  assert.equal(node.keyboard, null);
  assert.equal(observations.length, 0);
});

test('a previous tab cannot rebuild its keyboard after switching or closing the session', () => {
  const previous = tabFixture();
  const options = previous.node.keyboardAttached(previous.info);
  service.state.generation++;
  invokeDetached(options);
  const current = tabFixture();
  invokeDetached(current.node.keyboardAttached(current.info));
  assert.equal(observations.length, 1);
  assert.equal(observations[0].owner, current.tab);
  service.state.sessionId = '';
  invokeDetached(current.node.keyboardAttached(current.info));
  assert.equal(observations.length, 1);
});

console.log('4 compiled keyboard regressions passed. Native rendering/IME behavior still needs device validation.');
