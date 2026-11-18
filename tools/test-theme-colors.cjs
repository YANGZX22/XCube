// Run: node tools/test-theme-colors.cjs. No device, network or user preferences are accessed.
// UI checks are source guards; state checks execute the real theme/state code with ArkUI storage mocked.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const ts = require(process.env.XCUBE_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
const root = path.resolve(__dirname, '..');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const storage = new Map();
const connectedState = new Map();
global.ObservedV2 = cls => cls;
global.Trace = () => {};
global.AppStorage = {
  get: key => storage.get(key),
  setOrCreate: (key, value) => storage.set(key, value)
};
const originalLoad = Module._load;
Module._load = function(request, parent, isMain) {
  if (request === '@kit.ArkUI') return {
    AppStorageV2: {
      connect: (_type, key, factory) => {
        if (!connectedState.has(key)) connectedState.set(key, factory());
        return connectedState.get(key);
      }
    },
    UIUtils: { addMonitor: () => {}, clearMonitor: () => {} }
  };
  return originalLoad.apply(this, arguments);
};
Module._extensions['.ets'] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    fileName: filename.replace(/\.ets$/, '.ts'),
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, experimentalDecorators: true }
  }).outputText;
  module._compile(output, filename);
};

const { getAppUiState, applyThemeToAppUiState, setAppUiStateValue } =
  require(path.join(root, 'entry/src/main/ets/state/AppUiState.ets'));
const { ALL_THEMES, getManuscriptColors } = require(path.join(root, 'entry/src/main/ets/models/ThemeColors.ets'));
const { AppStorageKeys } = require(path.join(root, 'entry/src/main/ets/config/AppStorageKeys.ets'));
const cases = [];
const test = (name, run) => cases.push({ name, run });

function collectEts(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? collectEts(file) : (file.endsWith('.ets') ? [file] : []);
  });
}

test('UI colors no longer reference fixed lavender divider resources', () => {
  const files = ['components', 'pages'].flatMap(folder =>
    collectEts(path.join(root, 'entry/src/main/ets', folder)));
  for (const file of files) {
    const source = fs.readFileSync(file, 'utf8');
    assert.doesNotMatch(source, /\$r\(['"]app\.color\.(?:divider|primary_light)['"]\)/, file);
    assert.doesNotMatch(source, /#E6E1FD/i, file);
    assert.doesNotMatch(source, /@(?:Param|Local)\s+\w+[^\n]*=\s*getAppUiState\(\)\.themePrimaryLight/, file);
  }
});

test('all theme palettes update the same observable state and stored light accent', () => {
  const state = getAppUiState();
  for (const theme of ALL_THEMES) {
    for (const mode of ['light', 'dark']) {
      setAppUiStateValue(AppStorageKeys.IS_DARK_MODE, mode === 'dark');
      applyThemeToAppUiState(theme.id, theme[mode]);
      assert.strictEqual(getAppUiState(), state);
      assert.equal(state.themePrimaryLight, theme[mode].primaryLight, `${theme.id}/${mode}`);
      assert.equal(storage.get(AppStorageKeys.THEME_PRIMARY_LIGHT), theme[mode].primaryLight);
      assert.equal(state.themePrimary, theme[mode].primary);
      assert.equal(state.isDarkMode, mode === 'dark');
    }
  }
});

test('material banner and usage cards resolve defaults at render time, retaining explicit overrides', () => {
  const banner = read('entry/src/main/ets/components/ImmersiveTaskAlertBanner.ets');
  const metric = read('entry/src/main/ets/pages/UsageStatsPage.ets');
  assert.match(banner, /@Param cardStrokeColor: ResourceColor \| undefined = undefined/);
  assert.match(metric, /@Param primaryLightColor: string \| undefined = undefined/);
  const bannerColor = banner.match(/color: (this\.cardStrokeColor \?\? getAppUiState\(\)\.themePrimaryLight)/)[1];
  const metricColor = metric.match(/\.backgroundColor\((this\.primaryLightColor \?\? getAppUiState\(\)\.themePrimaryLight)\)/)[1];
  const metricCard = metric.slice(metric.indexOf('struct UsageMetricCard'), metric.indexOf('struct UsageStatsPage'));
  assert.match(metricCard, /ImmersiveListSurface\(/);
  assert.doesNotMatch(metricCard, /\.border\(/);
  const evaluateBanner = new Function('getAppUiState', `return ${bannerColor};`);
  const evaluateMetric = new Function('getAppUiState', `return ${metricColor};`);
  const bannerInstance = { cardStrokeColor: undefined };
  const metricInstance = { primaryLightColor: undefined };
  for (const theme of ALL_THEMES) {
    for (const mode of ['light', 'dark']) {
      applyThemeToAppUiState(theme.id, theme[mode]);
      assert.equal(evaluateBanner.call(bannerInstance, getAppUiState), theme[mode].primaryLight);
      assert.equal(evaluateMetric.call(metricInstance, getAppUiState), theme[mode].primaryLight);
    }
  }
  assert.equal(evaluateBanner.call({ cardStrokeColor: '#123456' }, getAppUiState), '#123456');
  assert.equal(evaluateMetric.call({ primaryLightColor: '#654321' }, getAppUiState), '#654321');
});

test('manuscript mode uses its own light accent instead of the lavender resource', () => {
  for (const dark of [false, true]) {
    const colors = getManuscriptColors(dark);
    applyThemeToAppUiState('lavender', colors);
    assert.equal(getAppUiState().themePrimaryLight, colors.primaryLight);
    assert.notEqual(getAppUiState().themePrimaryLight.toUpperCase(), '#E6E1FD');
  }
});

for (const { name, run } of cases) {
  run();
  console.log(`PASS ${name}`);
}
console.log(`${cases.length} theme color regression checks passed (${ALL_THEMES.length} themes, light/dark).`);
