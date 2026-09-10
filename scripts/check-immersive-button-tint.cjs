// Run after assembleHap. Checks compiled material options; it does not verify GPU rendering.
const fs = require('fs'), path = require('path'), vm = require('vm'), assert = require('assert/strict');
const ts = require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const built = path.join(root, 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets');
const pages = { WebDAVSyncPage: 5, ImportDataPage: 2, ExportDataPage: 1, TTSSettingsPage: 2, ThemeModeSettingsPage: 1 };
let checks = 0, factories = 0;
function check(value, label) { assert.ok(value, label); checks++; }
function parse(source, ets = false) {
  return ts.createSourceFile(ets ? 'test.ets' : 'test.ts', source, ts.ScriptTarget.Latest, true,
    ets ? ts.ScriptKind.ETS : ts.ScriptKind.TS);
}
function walk(node, predicate, matches = []) {
  if (predicate(node)) matches.push(node);
  ts.forEachChild(node, child => { walk(child, predicate, matches); });
  return matches;
}
function loadPureModule(relative) {
  const exports = {};
  const code = ts.transpileModule(fs.readFileSync(path.join(built, relative + '.ts'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }
  }).outputText;
  vm.runInNewContext(code, { exports });
  return exports;
}
const { withColorAlpha } = loadPureModule('utils/ColorAlphaUtils');
const { ALL_THEMES } = loadPureModule('models/ThemeColors');
const Color = { Transparent: 'transparent' };
const uiMaterial = { ImmersiveStyle: { THIN: 1, ULTRA_THIN: 0 }, ImmersiveMaterial: class {
  constructor(options) { Object.assign(this, options); }
} };
for (const [page, expected] of Object.entries(pages)) {
  const tree = parse(fs.readFileSync(path.join(built, 'pages', page + '.ts'), 'utf8'));
  const materials = walk(tree, node => ts.isNewExpression(node) &&
    node.expression.getText(tree) === 'uiMaterial.ImmersiveMaterial');
  const tinted = materials.filter(node => {
    const color = node.arguments[0].properties.find(property => property.name?.getText(tree) === 'materialColor');
    return color?.initializer.getText(tree).includes('this.themePrimary');
  });
  // ArkTS emits the builder factory for creation, updates and the params generator.
  check(tinted.length >= expected && tinted.length % expected === 0, page + ': all affected material factories covered');
  factories += tinted.length;
  for (const node of tinted) {
    for (const theme of ALL_THEMES) {
      for (const mode of ['light', 'dark']) {
        for (const selected of [true, false]) {
          const state = { themePrimary: theme[mode].primary, chatFontSize: selected ? 19 : 15, engine: selected ? 'local' : 'cloud' };
          const material = vm.runInNewContext(`(function () { return ${node.getText(tree)}; }).call(state)`, {
            size: 19, engine: 'local', withColorAlpha, Color, uiMaterial, state
          });
          check(material.interactive && material.lightEffect !== null && material.lightEffect !== undefined,
            page + ': deformation and light feedback retained');
          check(material.style === 0 || material.style === 1, page + ': thin material style retained');
          const colorExpression = node.arguments[0].properties.find(property => property.name?.getText(tree) === 'materialColor').initializer;
          if (ts.isConditionalExpression(colorExpression)) {
            check((material.materialColor === Color.Transparent) === !selected, page + ': tint only the selected option');
          }
          if (material.materialColor !== Color.Transparent) {
            const tint = material.materialColor;
            check(/^#26[0-9a-f]{6}$/i.test(tint) && tint.slice(3) === state.themePrimary.slice(1),
              page + ': translucent theme tint, never the same opaque color as the foreground');
          }
        }
      }
    }
  }
}

// Test/stop speech, engine options and font presets must not add a second outline over the material edge.
for (const [page, member] of [['TTSSettingsPage', 'ActionButtons'], ['TTSSettingsPage', 'EngineButton'],
  ['ThemeModeSettingsPage', 'FontPresetButton']]) {
  const tree = parse(fs.readFileSync(path.join(built, 'pages', page + '.ts'), 'utf8'));
  const builder = walk(tree, node => ts.isMethodDeclaration(node) && node.name.getText(tree) === member)[0];
  check(!!builder, member + ': builder exists');
  const borders = walk(builder, node => ts.isCallExpression(node) && node.expression.getText(tree) === 'Button.border');
  check(borders.length > 0, member + ': button outline covered');
  for (const border of borders) {
    for (const immersive of [true, false]) {
      const value = vm.runInNewContext(`(function () { return ${border.arguments[0].getText(tree)}; }).call(state)`, {
        shouldUseWrappedMaterial: () => immersive, engine: 'local', size: 19,
        state: { themePrimary: '#97A3D9', themePrimaryLight: '#282D46', engine: 'local', chatFontSize: 19 }
      });
      check(value.width === (immersive ? 0 : 1), member + ': remove duplicate outline only in immersive mode');
    }
  }
}

// Optional pre-edit snapshot: ensure this visual fix preserves native callbacks and enabled states.
if (process.argv[2]) {
  for (const page of Object.keys(pages)) {
    const protectedCalls = source => {
      const tree = parse(source, true);
      return walk(tree, node => ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) &&
        ['onClick', 'enabled', 'onChange', 'onTouch'].includes(node.expression.name.text))
        .map(node => node.expression.name.text + ':' + node.arguments.map(arg => arg.getText(tree)).join(','));
    };
    assert.deepEqual(protectedCalls(fs.readFileSync(path.join(root, 'entry/src/main/ets/pages', page + '.ets'), 'utf8')),
      protectedCalls(fs.readFileSync(path.join(process.argv[2], page + '.ets'), 'utf8')));
    checks++;
  }
}
console.log(JSON.stringify({ result: 'passed', checks, factories, visualVerification: 'not performed' }));
