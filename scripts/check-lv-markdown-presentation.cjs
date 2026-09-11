// Run after assembleHap. Exercises compiled logic; native/GPU appearance still needs device verification.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert/strict');
const ts = require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const built = path.join(root, 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug');
const markdown = 'markdown/src/main/ets/enhance/';
let checks = 0;
function equal(actual, expected) { assert.deepEqual(actual, expected); checks++; }
function extract(file, name, method = false) {
  const tree = ts.createSourceFile('test.ts', fs.readFileSync(path.join(built, file), 'utf8'), ts.ScriptTarget.Latest, true);
  let result;
  function visit(node) {
    if ((method ? ts.isMethodDeclaration(node) : ts.isFunctionDeclaration(node)) && node.name?.getText(tree) === name) {
      result = node.getText(tree);
    }
    ts.forEachChild(node, visit);
  }
  visit(tree);
  assert.ok(result, `${file}: ${name} exists`);
  return result;
}
function evaluate(source, globals = {}) {
  const exports = {};
  const code = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }
  }).outputText;
  vm.runInNewContext(code, { exports, ...globals });
  return exports;
}

// Inline code uses monospace Latin glyphs with the surrounding font as the Chinese fallback.
let codeFont = 'XCubeJetBrainsMono';
let bodyFont = 'Body Serif';
let titleFont = 'Heading Serif';
const controller = {
  getCodeBlockFontFamily: () => codeFont,
  getTextFontFamily: () => bodyFont,
  getTitleFontFamily: () => titleFont
};
const { handleFontFamily } = evaluate(extract(markdown + 'impl/TextImpl.ts', 'handleFontFamily'), {
  MDBaseController: { getMarkdownController: () => controller }
});
for (const type of ['paragraph', 'heading', 'table', 'blockquote']) {
  for (const text of ['const value = 42', '中文', '中文 value = 42']) {
    equal(handleFontFamily('test', { type: 'inlineCode', text }, { type }),
      `XCubeJetBrainsMono, ${type === 'heading' ? titleFont : bodyFont}`);
  }
}
bodyFont = 'HarmonyOS Sans';
equal(handleFontFamily('test', { type: 'inlineCode', text: '中文 text' }), 'XCubeJetBrainsMono, HarmonyOS Sans');
bodyFont = 'XCubeCMUSerif,XCubeSourceHanSerifSC';
equal(handleFontFamily('test', { type: 'inlineCode', text: '中文 text' }),
  'XCubeJetBrainsMono, XCubeCMUSerif,XCubeSourceHanSerifSC');
titleFont = 'XCubeCommonSerif,XCubeSourceHanSerifSC';
equal(handleFontFamily('test', { type: 'inlineCode', text: '中文 text' }, { type: 'heading', level: 2 }),
  'XCubeJetBrainsMono, XCubeCommonSerif,XCubeSourceHanSerifSC');
titleFont = 'Heading Serif';
bodyFont = '';
equal(handleFontFamily('test', { type: 'inlineCode' }), 'XCubeJetBrainsMono');
bodyFont = codeFont;
equal(handleFontFamily('test', { type: 'inlineCode' }), 'XCubeJetBrainsMono');
bodyFont = 'Body Serif';
codeFont = '';
equal(handleFontFamily('test', { type: 'inlineCode' }), 'monospace, Body Serif');
equal(handleFontFamily('test', { type: 'text' }), 'Body Serif');
equal(handleFontFamily('test', { type: 'text' }, { type: 'heading' }), 'Heading Serif');
equal(handleFontFamily('test', { type: 'inlineHtmlFont', face: 'Custom Font' }), 'Custom Font');

// Only inline formula layout dimensions shrink; cached pixel map and click payload stay intact.
let dimensions = {}, click, clicked;
const imageSpan = {
  create: pixelMap => { dimensions.pixelMap = pixelMap; }, objectFit() {},
  width: value => { dimensions.width = value; }, height: value => { dimensions.height = value; },
  onClick: action => { click = action; }
};
const formula = evaluate(['LatexImageSpanBuilder', 'LatexInlineSpanBuilder', 'LatexBlockSpanBuilder']
  .map(name => extract(markdown + 'builders/LatexBuilder.ts', name)).join('\n'), {
  ImageSpan: imageSpan, ImageFit: { Contain: 0 },
  ContainerSpan: { create() {}, pop() {} }, Span: { create() {}, height() {}, lineHeight() {} },
  LatexImpl: { handleClick: (...args) => { clicked = args; } }
});
const view = { observeComponentCreation2: action => action(1, true) };
const image = { width: 240, height: 80, pixelMap: {} };
for (const density of [1, 2, 3]) {
  for (const [builder, scale] of [['LatexInlineSpanBuilder', 0.9], ['LatexBlockSpanBuilder', 1]]) {
    dimensions = {};
    formula[builder].call(view, 'test', 'x^2', image, { px2vp: value => value / density });
    equal(dimensions.width, image.width / density * scale);
    equal(dimensions.height, image.height / density * scale);
    equal(dimensions.pixelMap, image.pixelMap);
    click();
    equal(clicked, ['test', 'x^2', image.pixelMap]);
  }
}

// Native menu policy: immersive uses no opaque background; fallback never calls unavailable APIs.
const factorySource = extract('entry/src/main/ets/utils/LvMarkdownMenuUtils.ts', 'getLvMarkdownSelectionMenuOptions');
for (const mode of ['immersive', 'forced-blur', 'unsupported']) {
  const api = mode !== 'unsupported';
  const empty = {};
  const uiMaterial = api ? {
    ImmersiveStyle: { THICK: 'thick' }, Material: { empty },
    ImmersiveMaterial: class { constructor(options) { this.style = options.style; } }
  } : new Proxy({}, { get() { throw new Error('Unavailable material API was accessed'); } });
  const { getLvMarkdownSelectionMenuOptions: factory } = evaluate(factorySource, {
    uiMaterial, shouldUseWrappedMaterial: () => mode === 'immersive', isWrappedMaterialApiAvailable: () => api,
    Color: { Transparent: 'transparent' }, BlurStyle: { NONE: 'none' }
  });
  const options = factory();
  equal(options === factory(), false);
  if (mode === 'immersive') {
    equal(options.systemMaterial.style, 'thick');
    equal(options.backgroundColor, undefined);
    equal(options.backgroundBlurStyle, undefined);
    equal(options.backgroundEffect, undefined);
  } else {
    equal(options.backgroundColor, 'transparent');
    equal(options.backgroundEffect.radius, 24);
    equal(options.systemMaterial, api ? empty : undefined);
  }
}

// Menu closure resets visibility and preserves the caller callback once per opening.
const menuMethod = extract(markdown + 'index.ts', 'getSelectionMenuOptions', true);
equal(/Object\.assign|\.\.\./.test(menuMethod), false);
const { MenuHarness } = evaluate(`export class MenuHarness { ${menuMethod} }`, {
  Placement: { BottomLeft: 'bottom-left' }
});
const menu = new MenuHarness();
let hidden = 0, notified = 0;
menu.hideSelectionActionBar = () => { hidden++; };
menu.selectionMenuOptions = () => ({ systemMaterial: 'native-material', onDisappear: () => { notified++; } });
for (let i = 1; i <= 3; i++) {
  const options = menu.getSelectionMenuOptions();
  equal(options.systemMaterial, 'native-material');
  equal(options.placement, 'bottom-left');
  equal(options.enableArrow, false);
  options.onDisappear();
  equal(hidden, i);
  equal(notified, i);
}
menu.selectionMenuOptions = () => ({});
menu.getSelectionMenuOptions().onDisappear();
equal(hidden, 4);

console.log(JSON.stringify({ result: 'passed', checks, visualVerification: 'not performed' }));
