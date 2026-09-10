// Run after assembleHap. Exercises the actual ArkTS-generated builders without a device.
// This verifies callback ownership and control flow, not GPU blur or visual appearance.
const fs = require('fs'), path = require('path'), vm = require('vm'), assert = require('assert/strict');
const root = path.resolve(__dirname, '..');
const ts = require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const src = path.join(root, 'entry/src/main/ets');
const built = path.join(root, 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets');
let checks = 0;
function check(value, label) { assert.ok(value, label); checks++; }
function parse(s, ets = false) { return ts.createSourceFile(ets ? 'test.ets' : 'test.ts', s, ts.ScriptTarget.Latest, true, ets ? ts.ScriptKind.ETS : ts.ScriptKind.TS); }
function walk(n, predicate, result = []) { if (predicate(n)) result.push(n); ts.forEachChild(n, c => { walk(c, predicate, result); }); return result; }
function runtime(api = 'yes') {
  const ui = { forceWrappedMaterialBlur: true, visualEffectsMode: 'off', themePrimary: '#405080', topAvoidHeight: 72, isDarkMode: false };
  const records = [], created = [], cache = new Map(), empty = {};
  const enums = new Proxy({}, { get: (_t, name) => name });
  const context = { px2vp: n => n / 3, getHostContext: () => ({ resourceManager: { getStringSync: id => String(id) } }),
    animateTo: (_options, action) => action() };
  const decorator = () => undefined;
  class View {
    constructor(parent) { this.parent = parent; }
    initParam(name, value) { this[name] = value; }
    updateParam(name, value) { this[name] = value; }
    finalizeConstruction() {}
    observeComponentCreation2(action) { action(1, true); }
    ifElseBranchUpdateFunction(_index, action) { action(); }
    forEachUpdateFunction(_id, items, action) { items.forEach(action); }
    getUIContext() { return context; }
    static create(component) { created.push(component); }
  }
  const globals = { ViewPU: View, ViewV2: View, Param: decorator, Event: decorator, Local: decorator,
    Monitor: () => decorator, Color: enums, BlurStyle: enums, Alignment: enums, HitTestMode: enums, FlexAlign: enums,
    VerticalAlign: enums, HorizontalAlign: enums, ButtonType: enums, ImageFit: enums,
    $r: id => ({ id }) };
  function native(type) {
    let proxy;
    proxy = new Proxy({}, { get: (_t, name) => (...args) => {
      records.push({ type, name, args });
      if (name === 'attributeModifier') args[0]?.applyNormalAttribute?.(proxy);
      return proxy;
    } });
    return proxy;
  }
  for (const type of ['Stack', 'Row', 'Button', 'SymbolGlyph', 'Image', 'If', 'ForEach']) globals[type] = native(type);
  const material = new Proxy({ Material: { empty } }, { get: (target, key) => {
    check(api === 'yes' && key === 'Material', 'Fallback never reads immersive constructors on unsupported API');
    return target[key];
  } });
  const deviceInfo = api === 'missing' ? {} : { apiAvailable: version => {
    check(version === '26.0.0', 'API version guard');
    if (api === 'throws') throw Error('Unavailable');
    return api === 'yes';
  } };
  function load(relative) {
    if (cache.has(relative)) return cache.get(relative);
    if (relative === 'state/AppUiState') return { getAppUiState: () => ui };
    if (relative === 'models/ThemeColors') return { VisualEffectsMode: { MANUSCRIPT: 'manuscript', OFF: 'off' } };
    const exports = {}; cache.set(relative, exports);
    const code = ts.transpileModule(fs.readFileSync(path.join(built, relative + '.ts'), 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true }
    }).outputText;
    const requireMock = name => {
      if (name === '@ohos:deviceInfo') return { default: deviceInfo };
      if (name === '@ohos:arkui.uiMaterial') return { default: material };
      if (name === '@ohos:arkui.node') return { LengthMetrics: { vp: value => ({ value }) } };
      if (name === '@ohos:arkui.modifier') return { SymbolGlyphModifier: class {} };
      if (name === '@native:ohos.curves') return { default: { springMotion: () => 'spring' } };
      if (name === '@hms:hds.hdsBaseComponent') return { ScrollEffectType: { GRADIENT_BLUR: 2 }, hdsEffect: {} };
      const match = name.match(/entry\/src\/main\/ets\/(.*)&$/);
      if (match) return load(match[1]);
      throw Error('Unexpected dependency: ' + name);
    };
    vm.runInNewContext(code, { ...globals, exports, require: requireMock });
    return exports;
  }
  return { ui, records, created, empty, View, load, native };
}

{
  const env = runtime(), modifier = new (env.load('utils/HdsMaterialSupport').DrawnTabsContentModifier)();
  modifier.applyNormalAttribute(env.native('HdsTabs'));
  const setting = name => env.records.find(r => r.name === name).args[0];
  check(setting('blurStrategy') === 1 && setting('barBackgroundEffect').radius === 0, 'Hidden page-switching tabs do not blur the bottom');
  check(setting('barBackgroundStyle').maskHeight === 0 && setting('barBackgroundStyle').maskColor === 'Transparent', 'No white/black gradient mask remains');
  const border = env.load('utils/DrawnNavigationSupport').getDrawnNavigationBorder();
  check(border.width === 0.5 && border.color === '#35FFFFFF', 'Shared navigation/plus border');
}

for (const api of ['yes', 'no', 'missing', 'throws']) {
  const env = runtime(api), visual = env.load('utils/HdsVisualEffectUtil');
  const originalTitle = () => { titleRenders++; };
  let titleRenders = 0, activated = 0;
  const options = new visual.HdsTopNavigationBlurOptions();
  options.stackBuilder = originalTitle;
  options.menuItems = [{ content: { label: 'Search', action: () => activated++ } },
    { content: { label: 'Disabled', isEnabled: false, action: () => { throw Error('Disabled action'); } } }];
  options.materialType = 101; options.materialLevel = 2;
  const owner = new env.View();
  const title = visual.buildHdsTopNavigationTitleBarOptions(options, owner);
  check(title.style.blurStrategy === undefined && title.style.originalStyle.backgroundStyle === undefined &&
    title.style.scrollEffectOpts.enableScrollEffect === true && title.style.scrollEffectStyle.backgroundStyle.blurRadius === undefined,
    'Top navigation retains the immersive-mode gradient blur settings');
  check(title.style.systemMaterialEffect.materialType === 0, 'No HDS immersive material in fallback');
  check(title.content.menu.value.length === 0, 'No HDS native menu remains');
  // Reproduce the supplied crash: the native callback has no receiver.
  const nativeCallback = title.content.stackBuilder;
  nativeCallback.call(undefined);
  check(env.created.length === 1 && env.created[0].parent === owner, 'Builder remains bound to page when called by native HDS');
  env.created[0].initialRender();
  check(titleRenders === 1, 'Original title content renders exactly once');
  const clicks = env.records.filter(r => r.type === 'Button' && r.name === 'onClick');
  check(clicks.length === 2, 'All menu buttons rendered');
  clicks.forEach(r => r.args[0]());
  check(activated === 1, 'Enabled callback fires once; disabled callback never fires');
  const blurs = env.records.filter(r => r.name === 'backdropBlur');
  check(blurs.length === 0, 'No extra top blur layer');
  check(env.records.filter(r => r.name === 'createWithChild').every(r => r.args[0].stateEffect === false), 'Plain native buttons have no state deformation');
  check(env.records.filter(r => r.name === 'systemMaterial').every(r => r.args[0] === env.empty), 'Only explicit empty material on supported APIs');
  const noOwner = env.load('components/DrawnNavigationTitle').DrawnNavigationTitleBuilder;
  assert.throws(() => noOwner.call(undefined, originalTitle, [], 16), /observeComponentCreation2/); checks++;
  if (api === 'yes') {
    env.ui.forceWrappedMaterialBlur = false;
    const restored = visual.buildHdsTopNavigationTitleBarOptions(options, owner);
    check(restored.content.stackBuilder === originalTitle && restored.content.menu.value === options.menuItems, 'Restore original HDS title/menu without wrappers');
    check(restored.style.systemMaterialEffect.materialType === 101 && restored.style.systemMaterialEffect.materialLevel === 2, 'Restore chosen material parameters');
  }
  env.ui.forceWrappedMaterialBlur = true;
  env.ui.visualEffectsMode = 'manuscript';
  check(!env.load('utils/DrawnNavigationSupport').shouldUseDrawnNavigation(), 'Manuscript appearance is not replaced');
}

for (const count of [2, 3, 4]) {
  const env = runtime(), TabBar = env.load('components/DrawnFloatingTabBar').DrawnFloatingTabBar;
  const rendered = [], clicked = [];
  const bar = new TabBar(new env.View(), { selectedIndex: count - 1, showSelectionBubble: count !== 4, tabCount: count, barWidth: 280,
    barHeight: 56, itemContent: index => rendered.push(index), onSelect: index => clicked.push(index) });
  bar.aboutToAppear(); bar.initialRender();
  check(rendered.join(',') === Array.from({ length: count }, (_, i) => i).join(','), 'One foreground per tab');
  env.records.filter(r => r.name === 'onClick').forEach(r => r.args[0]());
  check(clicked.join(',') === rendered.join(','), 'Plain clicks retain tab indices');
  check(env.records.filter(r => r.name === 'backdropBlur').length === 1, 'One blur surface per bottom bar');
  check(!env.records.some(r => ['scale', 'gesture', 'onTouch'].includes(r.name)), 'No deformation or long-press/drag interception');
  check(env.records.some(r => r.name === 'position') === (count !== 4), 'Only the four-option home preview omits its selected capsule');
}

// Only the native HDS tab bar needs its original upward visual compensation.
{
  const tree = parse(fs.readFileSync(path.join(built, 'pages/Index.ts'), 'utf8'));
  const builder = walk(tree, n => ts.isMethodDeclaration(n) && n.name.getText(tree) === 'CompactBottomTabBarContent')[0];
  check(!!builder, 'Home tab bar builder exists');
  const translations = walk(builder, n => ts.isCallExpression(n) && n.expression.getText(tree) === 'Row.translate');
  check(translations.length === 1, 'One vertical offset for the four home tabs');
  const expression = translations[0].arguments[0].getText(tree);
  for (const [manuscript, drawn, expected] of [[false, true, 0], [false, false, -3], [true, false, 0]]) {
    const offset = vm.runInNewContext(`(${expression})`, {
      isManuscriptMode: () => manuscript, shouldUseDrawnNavigation: () => drawn
    });
    check(offset.y === expected, 'Center drawn home tabs without changing native/manuscript alignment');
  }
}

// Every production entry must provide the actual component owner, not an unbound global builder.
function files(dir) { return fs.readdirSync(dir, { withFileTypes: true }).flatMap(e => e.isDirectory() ? files(path.join(dir, e.name)) : e.name.endsWith('.ets') ? [path.join(dir, e.name)] : []); }
let ownerCalls = 0, drawnTabs = 0;
for (const file of files(src)) {
  const source = fs.readFileSync(file, 'utf8'), tree = parse(source, true);
  for (const call of walk(tree, n => ts.isCallExpression(n) && ['buildHdsTopNavigationTitleBarOptions', 'buildHdsTopNavigationTitleBarOptionsForPage'].includes(n.expression.getText(tree)))) {
    const argument = call.arguments.at(-1).getText(tree);
    check(argument === (file.endsWith('HdsVisualEffectUtil.ets') ? 'builderOwner' : 'this'), 'Explicit owner: ' + file);
    ownerCalls++;
  }
  drawnTabs += walk(tree, n => ts.isCallExpression(n) && n.expression.getText(tree) === 'DrawnFloatingTabBar').length;
}
check(ownerCalls >= 20 && drawnTabs === 5, 'All title entry points and five secondary tab bars migrated');
console.log(JSON.stringify({ result: 'passed', checks, ownerCalls, drawnTabs, visualVerification: 'not performed' }));
