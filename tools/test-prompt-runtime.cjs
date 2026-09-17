// Runs the real ArkTS policy tests and selected execution paths on Node.
// HarmonyOS storage/network/logging and UI decorators are mocked; no API calls are made.
// Override XCUBE_TYPESCRIPT_PATH when DevEco Studio is installed elsewhere.
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const assert = require('node:assert/strict');
const ts = require(process.env.XCUBE_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
const root = path.resolve(__dirname, '..');
const cases = [];
const prefs = new Map();
const uiState = { activeChatSessionId: 'prompt-test', planRefreshAt: 0 };
let configuredLanguage = 'system';
let systemLanguage = 'en-US';
const noop = () => {};
global.ObservedV2 = cls => cls;
global.Observed = cls => cls;
global.Trace = noop;
global.$r = name => name;
const hypium = {
  describe: (_name, fn) => fn(),
  it: (name, _timeout, fn) => cases.push({ name, fn }),
  expect: actual => ({
    assertEqual: expected => assert.strictEqual(actual, expected),
    assertTrue: () => assert.strictEqual(actual, true),
    assertFalse: () => assert.strictEqual(actual, false)
  })
};
const oldLoad = Module._load;
Module._load = function(request, parent, isMain) {
  if (request === '@ohos/hypium') return hypium;
  if (request === '@kit.ArkTS') return { util: {} };
  if (request === '@kit.NetworkKit') return { http: {} };
  if (request === '@kit.LocalizationKit') return { i18n: { System: { getSystemLanguage: () => systemLanguage } } };
  if (request === '../viewmodels/SettingsManager') return { getSettingsManager: () => ({ getLanguage: () => configuredLanguage }) };
  if (request === '@kit.PerformanceAnalysisKit') return { hilog: { debug: noop, info: noop, warn: noop, error: noop } };
  if (request.endsWith('/PreferencesService') || request === './PreferencesService') return {
    PreferenceKeys: { PLAN_JSON: 'plan' },
    getPreferencesService: () => ({
      getString: async (k, fallback) => prefs.get(k) ?? fallback,
      getBoolean: async (k, fallback) => prefs.get(k) ?? fallback,
      getNumber: async (k, fallback) => prefs.get(k) ?? fallback,
      setString: async (k,v) => prefs.set(k,v)
    })
  };
  if (request.endsWith('/state/AppUiState')) return { getAppUiState: () => uiState, setAppUiStateValue: (k,v) => uiState[k] = v };
  if (request === './HttpService') return { getHttpService: () => ({}), HttpMethod: {} };
  if (request === '../config/BuiltinTools' && parent?.filename.endsWith('/ToolExecutionService.ets')) return { ASK_USER_TOOL_ID: 'ask_user' };
  return oldLoad.apply(this, arguments);
};
Module._extensions['.ets'] = function(module, filename) {
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    fileName: filename.replace(/\.ets$/, '.ts'),
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, experimentalDecorators: true }
  }).outputText;
  module._compile(code, filename);
};
for (const file of ['ToolProgressGuard', 'ToolRoundPolicy', 'PlanService', 'PromptLanguage']) {
  require(path.join(root, `entry/src/test/${file}.test.ets`)).default();
}
cases.push({ name: 'app prompt language follows live settings and system changes without a stale cache', fn: () => {
  const { getAppPromptLanguage } = require(path.join(root, 'entry/src/main/ets/utils/LocalizedTextUtils.ets'));
  configuredLanguage = 'en-US'; systemLanguage = 'zh-CN';
  assert.equal(getAppPromptLanguage(), 'en-US');
  configuredLanguage = 'zh-CN'; systemLanguage = 'en-US';
  assert.equal(getAppPromptLanguage(), 'zh-CN');
  configuredLanguage = 'system';
  assert.equal(getAppPromptLanguage(), 'en-US');
  systemLanguage = 'zh-CN';
  assert.equal(getAppPromptLanguage(), 'zh-CN');
  systemLanguage = 'en-US';
}});
cases.push({ name: 'plan executor applies a batch atomically and preserves the plan after invalid input', fn: async () => {
  const { PlanModeExecutor, createPlanModeToolDefinition } = require(path.join(root, 'entry/src/main/ets/config/PlanTool.ets'));
  assert.equal(createPlanModeToolDefinition().function.name, 'plan_mode');
  const executor = new PlanModeExecutor();
  await executor.execute(JSON.stringify({ operation: 'set', steps: ['Read', 'Implement', 'Test'] }));
  let result = JSON.parse(await executor.execute(JSON.stringify({ operation: 'check', step_refs: ['1', '2'] })));
  assert.equal(result.doneSteps, 2);
  result = JSON.parse(await executor.execute(JSON.stringify({ operation: 'uncheck', step_refs: ['1', 'missing'] })));
  assert.equal(result.ok, false);
  assert.equal(result.doneSteps, 2);
  result = JSON.parse(await executor.execute(JSON.stringify({ operation: 'check', step_refs: [3] })));
  assert.ok(result.error.includes('step_refs'));
  result = JSON.parse(await executor.execute(JSON.stringify({ operation: 'check', step: '3', step_refs: ['1'] })));
  assert.ok(result.error.includes('只能提供其中一个'));
}});
cases.push({ name: 'DeepSeek wire request preserves low/high/max and reasoning history', fn: () => {
  const { AIApiService, RequestMessage } = require(path.join(root, 'entry/src/main/ets/services/AIApiService.ets'));
  const models = require(path.join(root, 'entry/src/main/ets/models/ChatModels.ets'));
  const api = AIApiService.createIsolated();
  const compatibility = require(path.join(root, 'entry/src/main/ets/services/ProviderCompatibilityRegistry.ets'));
  const config = { providerId: 'deepseek', providerType: models.ProviderType.DEEPSEEK, apiStyle: models.ApiStyle.OPENAI, modelSupportsReasoning: true, apiKey: '', baseUrl: 'https://api.deepseek.com', apiPath: '/chat/completions' };
  const controlMode = compatibility.resolveReasoningControlMode(config, 'deepseek-v4-flash', true);
  assert.equal(controlMode, compatibility.ReasoningControlMode.LOW_HIGH_MAX);
  const history = [new RequestMessage('user', 'hello'), new RequestMessage('assistant', 'answer')];
  history[1].reasoningContent = 'prior reasoning';
  const tool = new models.ToolDefinition(new models.ToolFunction('knowledge_search', 'search', new models.ToolParameters()));
  for (const [level, effort] of [['low','low'],['medium','high'],['high','high'],['xhigh','max'],['auto',undefined]]) {
    const normalized = compatibility.normalizeReasoningLevelForControl(level, controlMode);
    const body = api.buildRequestBody(config, history, 'deepseek-v4-flash', 0.7, 1024, normalized, [tool], 'auto');
    assert.equal(body.reasoning_effort, effort);
    assert.equal(body.thinking.type, 'enabled');
    assert.equal(body.messages[1].reasoning_content, 'prior reasoning');
    assert.equal(body.tools.length, 1);
  }
  const off = api.buildRequestBody(config, history, 'deepseek-v4-flash', 0.7, 1024, 'off', [tool], 'auto');
  assert.equal(off.thinking.type, 'disabled');
  const final = api.buildRequestBody(config, history, 'deepseek-v4-flash', 0.7, 1024, 'low', undefined, 'none');
  assert.equal(final.tools, undefined);
}});
cases.push({ name: 'tool execution stops repeated work before a sixth execution and preserves JSON fields', fn: async () => {
  const models = require(path.join(root, 'entry/src/main/ets/models/ChatModels.ets'));
  const { ToolExecutionContext, RegisteredTool, getToolRegistry } = require(path.join(root, 'entry/src/main/ets/services/ToolRegistry.ets'));
  const { getToolExecutionService } = require(path.join(root, 'entry/src/main/ets/services/ToolExecutionService.ets'));
  const registry = getToolRegistry();
  const service = getToolExecutionService();
  let executions = 0;
  const config = new models.ToolConfig('prompt_probe', 'Prompt probe', '', null, true, false, models.ToolSourceType.BUILTIN, 'builtin', 'prompt_probe', 'test', models.ToolPermissionLevel.READ);
  const definition = new models.ToolDefinition(new models.ToolFunction('prompt_probe', '', new models.ToolParameters()));
  registry.registerTool(new RegisteredTool('prompt_probe', config, definition, { execute: async () => { executions++; return '{"ok":true,"text":"unchanged"}'; } }));
  service.beginToolTurn('probe');
  const ctx = new ToolExecutionContext('session', 'probe', 'main');
  for (let i=0; i<6; i++) {
    const result = await service.executeToolCall(new models.ToolCall(String(i), 'prompt_probe', '{}'), ['prompt_probe'], ctx);
    const parsed = JSON.parse(result.content);
    if (i<5) assert.equal(parsed.text, 'unchanged');
    if (i===2 || i===4) assert.ok(parsed.applicationExecutionNotice);
    if (i===5) assert.equal(parsed.error, 'tool_no_progress');
  }
  assert.equal(executions, 5);
  assert.equal(service.shouldStopToolLoop('probe'), true);
  service.beginToolTurn('probe');
  await service.executeToolCall(new models.ToolCall('new', 'prompt_probe', '{}'), ['prompt_probe'], ctx);
  assert.equal(executions, 6);
  service.endToolRequest('probe');
  assert.equal(service.shouldStopToolLoop('probe'), false);
  registry.unregisterTool('prompt_probe');
}});
cases.push({ name: 'sub-agent stops a stalled tool loop, preserves reasoning history and resets for follow-up', fn: async () => {
  const models = require(path.join(root, 'entry/src/main/ets/models/ChatModels.ets'));
  const { SubAgentService, SubAgentRuntimeConfig, SubAgentLiveState } = require(path.join(root, 'entry/src/main/ets/services/SubAgentService.ets'));
  const { isToolProgressStop } = require(path.join(root, 'entry/src/main/ets/utils/ToolProgressGuard.ets'));
  const { getResponseLanguageContinuationReminder } = require(path.join(root, 'entry/src/main/ets/utils/SystemPromptTemplateUtils.ets'));
  const { ToolExecutionContext, RegisteredTool, getToolRegistry } = require(path.join(root, 'entry/src/main/ets/services/ToolRegistry.ets'));
  const { getToolExecutionService } = require(path.join(root, 'entry/src/main/ets/services/ToolExecutionService.ets'));
  const registry = getToolRegistry();
  const execution = getToolExecutionService();
  const service = SubAgentService.getInstance();
  const definition = new models.ToolDefinition(new models.ToolFunction('child_probe', '', new models.ToolParameters()));
  const config = new models.ToolConfig('child_probe', 'Child probe', '', null, true, false, models.ToolSourceType.BUILTIN, 'builtin', 'child_probe', 'test', models.ToolPermissionLevel.READ);
  let executions = 0;
  let turnRound = 0;
  const usage = [];
  registry.registerTool(new RegisteredTool('child_probe', config, definition, { execute: async () => { executions++; return '{"ok":true,"text":"unchanged"}'; } }));
  const runtime = new SubAgentRuntimeConfig(
    {}, 'test-model', 0.7, 1024, models.ReasoningLevel.LOW, [definition], '2026-09-14',
    new ToolExecutionContext('session', 'child-request', 'main'),
    (call, allowed, _budget, ctx) => execution.executeToolCall(call, allowed, ctx),
    actor => { turnRound = 0; execution.beginToolTurn('child-request', actor, runtime.promptLanguage); },
    actor => execution.shouldStopToolLoop('child-request', actor),
    noop, noop, () => false, (...args) => usage.push(args)
  );
  const zhPrompt = service.buildSubAgentSystemPrompt(runtime, 'Probe', true, true, true);
  assert.ok(zhPrompt.includes('面向用户的输出语言'));
  runtime.promptLanguage = 'en-US';
  service.configureRuntime(runtime);
  const live = new SubAgentLiveState();
  live.name = 'Probe';
  const session = service.createSubAgentSession(runtime, live);
  assert.ok(session.messages[0].content.includes('User-facing output language'));
  assert.equal(/[\u3400-\u9fff]/.test(session.messages[0].content), false);
  session.apiService.estimateRequestInputTokens = () => 100;
  session.apiService.streamChatRequestWithTools = (...args) => {
    turnRound++;
    const messages = args[1], tools = args[11], choice = args[12];
    const reminder = getResponseLanguageContinuationReminder(runtime.promptLanguage);
    assert.equal(messages.at(-1).content, reminder);
    assert.equal(messages.filter(message => message.role === 'system' && message.content === reminder).length, 1);
    const previousCalls = messages.filter(message => message.role === 'assistant' && message.toolCalls.length > 0);
    for (const message of previousCalls) assert.ok(message.reasoningContent.startsWith('reasoning '));
    args[8](`reasoning ${turnRound}`);
    if (turnRound === 6) {
      assert.equal(tools, undefined);
      assert.equal(choice, 'none');
      assert.equal(previousCalls.length, session.conversationTurns * 5);
      args[3]('已有结果有限，重复查询未取得进展。');
      args[4]([]);
    } else {
      assert.equal(tools.length, 1);
      assert.equal(messages.some(message => message.role === 'system' && isToolProgressStop(message.content)), false);
      args[4]([new models.ToolCall(`call-${turnRound}`, 'child_probe', '{}')]);
    }
    return { destroy: noop };
  };
  try {
    for (let turn = 1; turn <= 2; turn++) {
      const report = await service.runSubAgentTurn(runtime, session, '继续核对');
      assert.equal(report.rounds, 6);
      assert.equal(report.toolCallCount, 5);
      assert.equal(report.result, '已有结果有限，重复查询未取得进展。');
      assert.equal(executions, turn * 5);
      assert.equal(session.messages.at(-1).reasoningContent, 'reasoning 6');
      assert.equal(execution.shouldStopToolLoop('child-request', 'main'), false);
    }
    assert.equal(usage.length, 12);
    assert.ok(usage.every(item => item[1] > 0));
  } finally {
    service.clearRuntime();
    execution.endToolRequest('child-request');
    registry.unregisterTool('child_probe');
  }
}});
(async () => {
  let failed = 0;
  for (const test of cases) {
    try { await test.fn(); console.log('PASS', test.name); }
    catch (error) { failed++; console.error('FAIL', test.name, error.stack); }
  }
  console.log(`${cases.length-failed}/${cases.length} passed (host transpilation; platform storage/network mocked)`);
  process.exitCode = failed ? 1 : 0;
})();
