// Run the ArkTS data/signature regressions on Node; no device or API requests.
// Optional: --compare-ref <git-ref> benchmarks against a previous implementation.
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const assert = require('node:assert/strict');
const { performance } = require('node:perf_hooks');
const { execFileSync } = require('node:child_process');
const ts = require(process.env.XCUBE_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
const root = path.resolve(__dirname, '..');
const cases = [];
global.ObservedV2 = cls => cls;
global.Observed = cls => cls;
global.Trace = () => {};
const hypium = {
  describe: (_name, fn) => fn(),
  it: (name, _timeout, fn) => cases.push({ name, fn }),
  expect: actual => ({
    assertEqual: expected => assert.strictEqual(actual, expected),
    assertTrue: () => assert.strictEqual(actual, true),
    assertFalse: () => assert.strictEqual(actual, false)
  })
};
const originalLoad = Module._load;
Module._load = function(request, parent, isMain) {
  if (request === '@ohos/hypium') return hypium;
  return originalLoad.apply(this, arguments);
};
function compile(module, filename, source) {
  const code = ts.transpileModule(source, {
    fileName: filename.replace(/\.ets$/, '.ts'),
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, experimentalDecorators: true }
  }).outputText;
  module._compile(code, filename);
}
Module._extensions['.ets'] = (module, filename) => compile(module, filename, fs.readFileSync(filename, 'utf8'));
for (const name of ['ChatTimelinePerformance', 'ResponseTimeline']) {
  require(path.join(root, `entry/src/test/${name}.test.ets`)).default();
}
const models = require(path.join(root, 'entry/src/main/ets/models/ChatModels.ets'));
const { TimelineToolIndex } = require(path.join(root, 'entry/src/main/ets/utils/TimelineToolIndex.ets'));
const relativeDataSource = 'entry/src/main/ets/components/chat/ChatMessageListDataSource.ets';
const dataSourcePath = path.join(root, relativeDataSource);
const current = require(dataSourcePath);

cases.push({ name: 'per-segment queries do not rescan historical tool arrays', fn: () => {
  for (const count of [50, 200, 800]) {
    const calls = Array.from({ length: count }, (_, i) => new models.ToolCall(`call-${i}`, 'tool'));
    const results = calls.map(call => new models.ToolResult(call.id, 'result'));
    let reads = 0;
    const observe = array => new Proxy(array, {
      get(target, key, receiver) {
        if (typeof key === 'string' && /^\d+$/.test(key)) reads++;
        return Reflect.get(target, key, receiver);
      }
    });
    const index = new TimelineToolIndex(observe(calls), observe(results));
    reads = 0;
    for (let i = 0; i < count; i++) {
      // Grouping, chart and map projection all request the same scoped call.
      for (let projection = 0; projection < 3; projection++) {
        assert.strictEqual(index.getCalls([`call-${i}`])[0], calls[i]);
      }
      assert.strictEqual(index.getResult(`call-${i}`), results[i]);
    }
    assert.equal(reads, 0, `${count} calls: historical arrays were rescanned`);
  }
}});
cases.push({ name: 'row composition does not rebuild a supplied content signature', fn: () => {
  const message = new models.ChatMessage('row', models.MessageRole.ASSISTANT, 'text');
  const content = current.buildChatMessageContentRenderSignature(message, false, 'model', 15, 'theme');
  Object.defineProperty(message, 'toolResults', { get() { throw new Error('duplicate content scan'); } });
  current.buildChatMessageRowRenderSignature(message, false, true, false, false, false, false,
    'model', 15, 'theme', '', [], '', '', 0, content);
}});

for (const { name, fn } of cases) {
  fn();
  console.log(`PASS ${name}`);
}
console.log(`${cases.length} regression checks passed.`);

const compareAt = process.argv.indexOf('--compare-ref');
if (compareAt >= 0) {
  const ref = process.argv[compareAt + 1];
  assert.ok(ref && !ref.startsWith('-'), 'Provide a Git ref after --compare-ref');
  const previousSource = execFileSync('git', ['show', `${ref}:${relativeDataSource}`], { cwd: root, encoding: 'utf8' });
  const baselineModule = new Module(dataSourcePath + '.baseline.ets', module);
  baselineModule.paths = Module._nodeModulePaths(path.dirname(dataSourcePath));
  compile(baselineModule, dataSourcePath + '.baseline.ets', previousSource);
  function fixture(rounds) {
    const message = new models.ChatMessage('bench', models.MessageRole.ASSISTANT, 'reply');
    message.isGenerating = true;
    for (let i = 0; i < rounds; i++) {
      const id = `call-${i}`;
      message.toolCalls.push(new models.ToolCall(id, 'python_sandbox', 'a'.repeat(1024)));
      message.toolResults.push(new models.ToolResult(id, 't'.repeat(16384)));
      message.responseSegments.push(new models.AssistantResponseSegment(`reason-${i}`,
        models.AssistantResponseSegmentType.REASONING, 'r'.repeat(4096)));
      message.responseSegments.push(new models.AssistantResponseSegment(`tools-${i}`,
        models.AssistantResponseSegmentType.TOOL_CALLS, '', [id]));
    }
    return message;
  }
  function measure(api, rounds) {
    const message = fixture(rounds);
    const samples = [];
    let signatureChars = 0;
    for (let i = 0; i < 24; i++) {
      message.reasoningContent += `chunk-${i}`;
      message.responseSegments[message.responseSegments.length - 2].content += `chunk-${i}`;
      const start = performance.now();
      const content = api.buildChatMessageContentRenderSignature(message, false, 'model', 15, 'theme');
      const row = api.buildChatMessageRowRenderSignature(message, false, true, false, false, false, false,
        'model', 15, 'theme', '', [], '', '', 0, content);
      const elapsed = performance.now() - start;
      signatureChars = row.length;
      if (i >= 4) samples.push(elapsed);
    }
    samples.sort((a, b) => a - b);
    return { medianMs: Number(samples[Math.floor(samples.length / 2)].toFixed(3)), signatureChars };
  }
  for (const rounds of [50, 150, 300]) {
    console.log(JSON.stringify({ rounds, baseline: measure(baselineModule.exports, rounds), current: measure(current, rounds) }));
  }
}
