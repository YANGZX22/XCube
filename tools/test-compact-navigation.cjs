// Build the debug HAP first. Exercise the geometry and click handlers emitted by ArkTS.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.XCUBE_TYPESCRIPT_PATH ||
  '/Applications/DevEco-Studio.app/Contents/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
const entry = path.resolve(__dirname, '../entry');
const compiled = path.join(entry, 'build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/Index.ts');
assert.ok(fs.statSync(compiled).mtimeMs >= fs.statSync(path.join(entry, 'src/main/ets/pages/Index.ets')).mtimeMs,
  'Rebuild the debug HAP before running the navigation regression.');
const source = ts.createSourceFile(compiled, fs.readFileSync(compiled, 'utf8'), ts.ScriptTarget.Latest, true);
const index = source.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'Index');
const methods = new Set(['getExpandedCompactTabBarWidth', 'getCompactBottomTabBarWidth', 'getCompactMiniBarX',
  'getCompactBottomBarsWidth', 'getManuscriptNavigationWidth', 'getManuscriptNavigationHeight',
  'compactFloatingStyle', 'isTabActive', 'setCompactNavigationCollapsed', 'activateNavigationTab',
  'CompactBottomBarsOverlay', 'CompactBottomTabBarBuilder', 'CompactBottomTabBarContent', 'CompactTabItem']);
const code = index.members.filter(member => methods.has(member.name?.text) ||
  /^(COMPACT_|TAB_(ASSISTANTS|CHAT|KNOWLEDGE|SETTINGS)$)/.test(member.name?.text)).map(member => member.getText(source)).join('\n');
const initializeTabs = index.members.find(ts.isConstructorDeclaration).body.statements
  .find(statement => statement.expression?.left?.getText(source) === 'this.compactTabs').getText(source);
let nodes, items, appearance;
function component(type) {
  let node;
  return new Proxy({}, { get(_, key) {
    return value => {
      if (key === 'create' || key === 'createWithChild') {
        node = { type, options: value };
        nodes.push(node);
      } else if (key === 'tabBar') {
        value.builder();
      } else if (key !== 'pop') {
        node[key] = value;
      }
    };
  } });
}
const env = {
  ...Object.fromEntries(['Row', 'Stack', 'Button', 'HdsTabs', 'TabContent', 'ForEach', 'If'].map(k => [k, component(k)])),
  Context: { animation() {} }, curves: { springMotion: () => 'spring' },
  FlexAlign: { Start: 'start', End: 'end' }, VerticalAlign: { Top: 0 }, Direction: { Ltr: 0 },
  Alignment: { Center: 'center' }, HitTestMode: { Transparent: 1 }, AccessibilityRoleType: { BUTTON: 1 },
  ButtonType: { Circle: 1 }, BarPosition: { End: 0 }, Color: { White: 'white', Transparent: 0 },
  INDEX_TAB_ASSISTANTS: 0, INDEX_TAB_CHAT: 1, INDEX_TAB_KNOWLEDGE: 2, INDEX_TAB_SETTINGS: 3,
  getHdsMaterialLightColor: value => value, getHdsSystemMaterialEffect: () => ({ materialType: 101 }),
  shouldUseWrappedMaterial: () => appearance === 'material', shouldUseDrawnNavigation: () => appearance === 'blur',
  HdsTabsBlurModifier: class {}, getDrawnNavigationBorder: () => ({}), getBlurBottomShadow: () => ({}),
  IndexBottomTabItem: class { constructor(_parent, props) { Object.assign(this, props); } },
  ViewV2: { create: item => items.push(item) }
};
const Page = vm.runInNewContext(ts.transpileModule('class Index { constructor() {' + initializeTabs + '}\n' + code + '}\nIndex', {
  compilerOptions: { target: ts.ScriptTarget.ES2022 }
}).outputText, env);

function render(page) {
  nodes = [];
  items = [];
  page.CompactBottomBarsOverlay();
  const dock = nodes.find(n => n.justifyContent);
  assert.equal(dock.width, '100%');
  assert.equal(dock.position, undefined);
  assert.equal(dock.justifyContent, page.plusOnLeft ? 'end' : 'start');
  const host = nodes.find(n => n.type === 'HdsTabs');
  if (appearance === 'material') {
    assert.equal(host.width, page.getCompactBottomTabBarWidth());
    assert.equal(host.barFloatingStyle.lightColor, page.themePrimary);
    assert.equal(host.barFloatingStyle.systemMaterialEffect.materialType, 101);
  }
  const content = nodes.find(n => n.type === 'Stack' && n.options?.alignContent === 'center');
  assert.equal(content.translate.y, appearance === 'material' ? -3 : 0);
  return { items, cells: nodes.filter(n => n.type === 'Row' && n.onClick), orb: nodes.find(n => n.type === 'Button'),
    row: nodes.find(n => n.type === 'Row' && n.backgroundColor === 0 && n.padding?.left !== undefined),
    plus: nodes.find(n => n.zIndex === 1).position.x };
}
for (appearance of ['material', 'blur', 'manuscript']) {
  for (const [screen, width] of [[320, 224], [360, 264], [390, 284], [440, 316], [840, 348]]) {
    for (const plusOnLeft of [true, false]) {
      for (let selected = 0; selected < 4; selected++) {
        const page = Object.assign(new Page(), {
          windowWidthVp: screen, compactBottomBarsWidthVp: screen, compactNavigationCollapsed: false,
          currentTabIndex: selected, navigationTabBounceTriggers: [-1, -1, -1, -1],
          plusOnLeft,
          themePrimary: '#725BC0', lightColorMode: 'theme', springs: 0,
          shouldPlaceCompactMiniBarOnLeft() { return this.plusOnLeft; },
          isManuscriptMode: () => appearance === 'manuscript', getManuscriptBottomBarHeight: () => 76,
          getCompactTabsFloatingBottomMargin: () => 12, getManuscriptTabLabel: i => String(i),
          observeComponentCreation2: callback => callback(1, true), ifElseBranchUpdateFunction: (_, build) => build(),
          forEachUpdateFunction: (_, tabs, build) => tabs.forEach(build), CompactBottomMiniBarControl() {},
          switchToTab(i) { this.currentTabIndex = i; },
          getUIContext() { return { animateTo: (options, update) => {
            assert.equal(options.curve, 'spring'); this.springs++; update();
          } }; }
        });
        const open = render(page);
        assert.equal(page.getExpandedCompactTabBarWidth(), width);
        // The original slots use the actual native content bounds, including its own insets.
        assert.equal(open.row.width, '100%');
        assert.equal(open.row.padding.left, appearance === 'blur' ? 12 : 0);
        assert.equal(open.row.padding.right, open.row.padding.left);
        assert.deepEqual(open.cells.map(c => c.layoutWeight), [1, 1, 1, 1]);
        assert.ok(open.cells.every(c => c.width === undefined && c.position === undefined && c.translate === undefined));
        assert.deepEqual(Array.from(page.compactTabs, tab => tab.index), [0, 1, 2, 3]);
        assert.deepEqual(open.items.map(i => i.label.id), Array.from(page.compactTabs, tab => tab.label.id));

        page.setCompactNavigationCollapsed(true);
        const ball = render(page);
        assert.equal(ball.plus, open.plus);
        assert.equal(ball.orb.width, 56);
        assert.equal(ball.items.length, 1);
        assert.equal(ball.items[0].navigationTransitionId, open.items[selected].navigationTransitionId);
        page.plusOnLeft = !plusOnLeft;
        render(page).orb.onClick();
        const reopened = render(page);
        assert.equal(page.springs, 2);
        assert.deepEqual(reopened.items.map(i => i.navigationTransitionId), open.items.map(i => i.navigationTransitionId));
        const next = (selected + 1) % 4;
        reopened.cells[next].onClick();
        reopened.cells[next].onClick();
        assert.equal(page.currentTabIndex, next);
        assert.equal(page.navigationTabBounceTriggers[next], 1);
      }
    }
  }
}
console.log('Passed compact navigation layout, shared icon, and input regressions.');
