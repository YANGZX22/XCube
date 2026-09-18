// Exercise the real TTS service with simulated HarmonyOS network/audio APIs.
// Run: node tools/test-tts.cjs (no device, credentials or billable API requests).
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const assert = require('node:assert/strict');
const ts = require(process.env.XCUBE_TYPESCRIPT_PATH || '/Applications/DevEco-Studio.app/Contents/tools/arktsdoc/node_modules/typescript/lib/typescript.js');
const root = path.resolve(__dirname, '..');
const prefs = new Map();
const preferenceSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/PreferencesService.ets'), 'utf8');
const keys = Object.fromEntries([...preferenceSource.matchAll(/static readonly (\w+): string = '([^']+)'/g)].map(match => [match[1], match[2]]));
let requests = [], players = [], requestHandler, playerFactory, localStarts = 0;
const openFiles = new Set();
const fileIo = {
  OpenMode: { READ_ONLY: 0, WRITE_ONLY: 1, CREATE: 64, TRUNC: 512 },
  openSync: (name, mode) => {
    const fd = fs.openSync(name, mode === 0 ? 'r' : 'w');
    openFiles.add(fd);
    return { fd };
  },
  closeSync: file => { fs.closeSync(file.fd); openFiles.delete(file.fd); },
  accessSync: name => fs.existsSync(name),
  unlinkSync: name => fs.unlinkSync(name),
  renameSync: (from, to) => fs.renameSync(from, to),
  statSync: fd => fs.fstatSync(fd),
  readSync: (fd, buffer) => fs.readSync(fd, new Uint8Array(buffer)),
  writeSync: (fd, buffer) => fs.writeSync(fd, new Uint8Array(buffer))
};
class FakePlayer {
  handlers = new Map();
  released = false;
  on(event, callback) { this.handlers.set(event, callback); }
  off(event) { this.handlers.delete(event); }
  emit(state) { this.handlers.get('stateChange')?.(state, 'test'); }
  set fdSrc(source) { this.source = source; this.emit('initialized'); }
  async prepare() { this.emit('prepared'); }
  async play() { this.emit('playing'); }
  async release() { this.released = true; }
}
const load = Module._load;
Module._load = function(request, parent, isMain) {
  if (request === '@kit.SpeechKit') return { TextReader: {
    init: async () => {}, on: () => {}, off: () => {}, start: async () => { localStarts++; },
    stop: async () => {}, release: async () => {}
  }, ReadStateCode: {} };
  if (request === '@kit.CoreFileKit') return { fileIo };
  if (request === '@kit.NetworkKit') return { http: {
    RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 'string', ARRAY_BUFFER: 'arraybuffer' },
    createHttp: () => {
      const request = {
        destroyed: false,
        async request(url, options) { this.url = url; this.options = options; requests.push(this); return requestHandler(this); },
        destroy() { this.destroyed = true; }
      };
      return request;
    }
  } };
  if (request === '@kit.MediaKit') return { media: { createAVPlayer: async () => {
    const player = await playerFactory(); players.push(player); return player;
  } } };
  if (request === '@kit.ArkTS') return { util: {
    TextDecoder: class { decodeToString(bytes) { return new TextDecoder().decode(bytes); } },
    Base64Helper: class {
      decodeSync(value) {
        if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) throw new Error('Invalid Base64');
        // Buffer uses pooled backing storage, also testing correct byteOffset/byteLength slicing.
        return Buffer.from(value, 'base64');
      }
      encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); }
    }
  } };
  if (request === './PreferencesService') return {
    PreferenceKeys: keys,
    getPreferencesService: () => ({
      getString: async (key, fallback) => prefs.get(key) ?? fallback,
      getBoolean: async (key, fallback) => prefs.get(key) ?? fallback,
      getNumber: async (key, fallback) => prefs.get(key) ?? fallback
    })
  };
  return load.apply(this, arguments);
};
Module._extensions['.ets'] = (module, filename) => {
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    fileName: filename.replace(/\.ets$/, '.ts'),
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS }
  }).outputText;
  module._compile(output, filename);
};
const { TTSService, TTSEngineType, normalizeTTSEngine } = require(path.join(root, 'entry/src/main/ets/services/TTSService.ets'));
const { MiMoTTSModel, MiMoTTSSettings, MIMO_TTS_VOICES, buildMiMoTTSEndpoint, buildMiMoTTSRequest, decodeMiMoTTSAudio } =
  require(path.join(root, 'entry/src/main/ets/utils/MiMoTTSUtils.ets'));
const { importMiMoVoiceSample, readMiMoVoiceSample } = require(path.join(root, 'entry/src/main/ets/services/MiMoVoiceSampleService.ets'));
const audioBytes = Buffer.from('ID3 fake audio fixture');
const audioResponse = (data = audioBytes.toString('base64'), reason = 'stop') => JSON.stringify({
  choices: [{ finish_reason: reason, message: { audio: { data } } }]
});
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };
const cases = [];
const test = (name, run) => cases.push({ name, run });

async function fixture(run) {
  prefs.clear(); requests = []; players = []; localStarts = 0;
  prefs.set(keys.TTS_ENGINE, TTSEngineType.MIMO);
  prefs.set(keys.MIMO_TTS_API_KEY, ' test-key ');
  requestHandler = async () => ({ responseCode: 200, result: audioResponse() });
  playerFactory = async () => new FakePlayer();
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'chatcube-tts-'));
  const context = { filesDir: path.join(directory, 'files'), cacheDir: path.join(directory, 'cache') };
  fs.mkdirSync(context.filesDir); fs.mkdirSync(context.cacheDir);
  const service = new TTSService();
  const events = [];
  const callback = { onStart: () => events.push('start'), onComplete: () => events.push('complete'), onError: error => events.push(error) };
  await service.init(context);
  try { await run({ service, callback, events, context, directory }); }
  finally { await service.destroy(); await tick(); fs.rmSync(directory, { recursive: true, force: true }); }
  assert.equal(openFiles.size, 0, 'All audio/sample descriptors must be closed');
}

test('recognizes MiMo and keeps legacy engine defaults', async () => {
  assert.equal(normalizeTTSEngine('mimo'), TTSEngineType.MIMO);
  assert.equal(normalizeTTSEngine('elevenlabs'), TTSEngineType.ELEVENLABS);
  assert.equal(normalizeTTSEngine('unknown'), TTSEngineType.LOCAL);
  await fixture(async ({ service, callback }) => {
    prefs.delete(keys.TTS_ENGINE);
    await service.speak('本地朗读', callback);
    assert.equal(localStarts, 1);
    assert.equal(requests.length, 0);
  });
});

test('normalizes host, /v1 and full chat completion URLs', () => {
  for (const base of ['', ' https://api.xiaomimimo.com/ ', 'https://api.xiaomimimo.com/v1///', 'https://api.xiaomimimo.com/v1/chat/completions/']) {
    assert.equal(buildMiMoTTSEndpoint(base), 'https://api.xiaomimimo.com/v1/chat/completions');
  }
  assert.equal(buildMiMoTTSEndpoint('https://proxy.example/mimo/v1'), 'https://proxy.example/mimo/v1/chat/completions');
});

test('all preset voices use assistant text and non-streaming MP3', () => {
  const settings = new MiMoTTSSettings();
  for (const voice of MIMO_TTS_VOICES) {
    settings.voice = voice;
    assert.deepEqual(buildMiMoTTSRequest('原文', settings), {
      model: 'mimo-v2.5-tts', messages: [{ role: 'assistant', content: '原文' }],
      audio: { format: 'mp3', voice }, stream: false
    });
  }
  settings.voice = '';
  assert.equal(buildMiMoTTSRequest('原文', settings).audio.voice, 'mimo_default');
  settings.voice = 'invalid';
  assert.throws(() => buildMiMoTTSRequest('原文', settings), /预置音色无效/);
});

test('voice design sends description as user and omits voice and text optimization', () => {
  const settings = new MiMoTTSSettings();
  settings.model = MiMoTTSModel.VOICE_DESIGN;
  assert.throws(() => buildMiMoTTSRequest('原文', settings), /音色描述/);
  settings.voiceDescription = ' 温暖女声 ';
  assert.deepEqual(buildMiMoTTSRequest('原文', settings), {
    model: MiMoTTSModel.VOICE_DESIGN,
    messages: [{ role: 'user', content: '温暖女声' }, { role: 'assistant', content: '原文' }],
    audio: { format: 'mp3' }, stream: false
  });
});

test('decodes only returned audio bytes and rejects missing, filtered, truncated or corrupt output', () => {
  assert.deepEqual(Buffer.from(decodeMiMoTTSAudio(audioResponse())), audioBytes);
  for (const body of ['broken', 'null', '{}', '{"choices":[]}', '{"choices":[null]}', audioResponse(''), audioResponse('%%%'), audioResponse(123), audioResponse(undefined, 'content_filter'), audioResponse(undefined, 'length')]) {
    assert.throws(() => decodeMiMoTTSAudio(body), /MiMo TTS/);
  }
});

test('MiMo service sends API-key JSON, plays MP3, reports start/complete and removes cache', () => fixture(async ({ service, callback, events, context }) => {
  await service.speak('**你好**，MiMo。', callback);
  assert.equal(localStarts, 0);
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, 'https://api.xiaomimimo.com/v1/chat/completions');
  assert.equal(requests[0].options.header['api-key'], 'test-key');
  assert.equal(requests[0].options.header['Content-Type'], 'application/json');
  assert.equal(requests[0].options.expectDataType, 'string');
  assert.equal(JSON.parse(requests[0].options.extraData).messages[0].content, '你好，MiMo。');
  assert.equal(requests[0].destroyed, true);
  assert.equal(players.length, 1);
  assert.deepEqual(events, ['start']);
  const cache = fs.readdirSync(context.cacheDir);
  assert.equal(cache.length, 1);
  assert.deepEqual(fs.readFileSync(path.join(context.cacheDir, cache[0])), audioBytes);
  players[0].emit('completed');
  await tick();
  assert.deepEqual(events, ['start', 'complete']);
  assert.equal(service.getReadingStatus(), false);
  assert.deepEqual(fs.readdirSync(context.cacheDir), []);
}));

test('long replies play sequentially with one start and one completion', () => fixture(async ({ service, callback, events }) => {
  const text = '你好，世界。'.repeat(450);
  await service.speak(text, callback);
  for (let index = 0; index < 10 && !events.includes('complete'); index++) {
    players[index].emit('completed');
    await tick();
  }
  assert.deepEqual(events, ['start', 'complete']);
  assert.ok(requests.length >= 3);
  const texts = requests.map(request => JSON.parse(request.options.extraData).messages[0].content);
  assert.ok(texts.every(text => text.length <= 1000));
  assert.equal(texts.join(''), text);
  assert.ok(players.every(player => player.released));
}));

test('voice sample import survives reuse, replaces atomically and is sent as raw Base64', () => fixture(async ({ service, callback, context, directory }) => {
  prefs.set(keys.MIMO_TTS_MODEL, MiMoTTSModel.VOICE_CLONE);
  assert.throws(() => readMiMoVoiceSample(context), /导入/);
  const input = path.join(directory, '参考.wav');
  fs.writeFileSync(input, 'RIFF first sample');
  assert.equal(importMiMoVoiceSample(context, input), '参考.wav');
  const input2 = path.join(directory, 'voice.MP3');
  fs.writeFileSync(input2, audioBytes);
  importMiMoVoiceSample(context, input2);
  assert.throws(() => importMiMoVoiceSample(context, path.join(directory, 'bad.aac')), /MP3/);
  fs.writeFileSync(input, '');
  assert.throws(() => importMiMoVoiceSample(context, input), /非空/);
  fs.truncateSync(input, 10 * 1024 * 1024 + 1);
  assert.throws(() => importMiMoVoiceSample(context, input), /10 MiB/);
  assert.equal(readMiMoVoiceSample(context), audioBytes.toString('base64'));
  await service.speak('克隆音色', callback);
  const body = JSON.parse(requests[0].options.extraData);
  assert.equal(body.model, MiMoTTSModel.VOICE_CLONE);
  assert.equal(body.audio.voice, audioBytes.toString('base64'));
  assert.deepEqual(body.messages, [{ role: 'assistant', content: '克隆音色' }]);
}));

test('missing credentials, description, reference audio and disabled TTS never call the API', async () => {
  for (const [key, value, message] of [
    [keys.MIMO_TTS_API_KEY, '', /API Key/],
    [keys.MIMO_TTS_MODEL, MiMoTTSModel.VOICE_DESIGN, /音色描述/],
    [keys.MIMO_TTS_MODEL, MiMoTTSModel.VOICE_CLONE, /音频样本/],
    [keys.TTS_ENABLED, false, /关闭/]
  ]) await fixture(async ({ service, callback, events }) => {
    prefs.set(key, value);
    await service.speak('测试', callback);
    assert.equal(requests.length, 0);
    assert.equal(events.length, 1);
    assert.match(events[0], message);
  });
});

test('HTTP, network and invalid audio failures complete with one error and no playback', async () => {
  for (const handler of [
    async () => ({ responseCode: 401, result: '{"error":"unauthorized"}' }),
    async () => { throw new Error('timeout'); },
    async () => ({ responseCode: 200, result: audioResponse('%%%') }),
    async () => ({ responseCode: 200, result: '{}' })
  ]) await fixture(async ({ service, callback, events }) => {
    requestHandler = handler;
    await service.speak('测试', callback);
    assert.equal(events.length, 1);
    assert.match(events[0], /MiMo TTS/);
    assert.equal(players.length, 0);
    assert.equal(requests[0].destroyed, true);
    assert.equal(service.getReadingStatus(), false);
  });
});

test('cancelled responses cannot play or affect a replacement request', () => fixture(async ({ service, callback, events }) => {
  const first = deferred();
  requestHandler = () => first.promise;
  const pending = service.speak('旧请求', callback);
  await tick();
  assert.equal(requests.length, 1);
  service.stop();
  assert.equal(requests[0].destroyed, true);
  requestHandler = async () => ({ responseCode: 200, result: audioResponse() });
  await service.speak('新请求', callback);
  first.resolve({ responseCode: 200, result: audioResponse() });
  await pending;
  assert.equal(players.length, 1);
  assert.deepEqual(events, ['start']);
  players[0].emit('completed');
  await tick();
  assert.deepEqual(events, ['start', 'complete']);
}));

test('ElevenLabs retains its binary endpoint, credentials and voice settings', () => fixture(async ({ service, callback, events }) => {
  prefs.set(keys.TTS_ENGINE, TTSEngineType.ELEVENLABS);
  prefs.set(keys.ELEVENLABS_API_KEY, 'eleven-key');
  prefs.set(keys.ELEVENLABS_VOICE_ID, 'voice-id');
  requestHandler = async () => ({ responseCode: 200, result: Uint8Array.from(audioBytes).buffer });
  await service.speak('ElevenLabs', callback);
  assert.match(requests[0].url, /\/v1\/text-to-speech\/voice-id\?output_format=mp3_44100_128$/);
  assert.equal(requests[0].options.header['xi-api-key'], 'eleven-key');
  assert.equal(requests[0].options.expectDataType, 'arraybuffer');
  const payload = JSON.parse(requests[0].options.extraData);
  assert.equal(payload.text, 'ElevenLabs');
  assert.equal(payload.model_id, 'eleven_multilingual_v2');
  assert.equal(payload.voice_settings.speed, 1);
  assert.deepEqual(events, ['start']);
}));

test('player creation failure closes the audio file and removes temporary MP3', () => fixture(async ({ service, callback, events, context }) => {
  playerFactory = async () => { throw new Error('Player unavailable'); };
  await service.speak('测试', callback);
  assert.deepEqual(events, ['Player unavailable']);
  assert.equal(openFiles.size, 0);
  assert.deepEqual(fs.readdirSync(context.cacheDir), []);
}));

test('late preparation failures and cancelled player creation cannot affect new playback', () => fixture(async ({ service, callback, events, context }) => {
  const oldPreparation = deferred();
  playerFactory = async () => {
    const player = new FakePlayer();
    player.prepare = () => oldPreparation.promise;
    return player;
  };
  await service.speak('准备中', callback);
  assert.deepEqual(events, []);
  service.stop();
  playerFactory = async () => new FakePlayer();
  await service.speak('新播放', callback);
  oldPreparation.reject(new Error('Old player released'));
  await tick();
  assert.deepEqual(events, ['start']);
  assert.equal(service.getReadingStatus(), true);
  service.stop();
  await tick();

  const creation = deferred();
  const fixedTime = Date.now;
  Date.now = () => 123456789;
  try {
    playerFactory = () => creation.promise;
    const pending = service.speak('创建中', callback);
    await tick();
    service.stop();
    playerFactory = async () => new FakePlayer();
    await service.speak('另一段播放', callback);
    const cancelledPlayer = new FakePlayer();
    creation.resolve(cancelledPlayer);
    await pending;
    assert.equal(cancelledPlayer.released, true);
    assert.equal(fs.readdirSync(context.cacheDir).length, 1, 'Old cancellation must not delete new audio');
    assert.equal(service.getReadingStatus(), true);
    assert.deepEqual(events, ['start', 'start']);
  } finally { Date.now = fixedTime; }
}));

(async () => {
  for (const { name, run } of cases) { await run(); console.log(`PASS ${name}`); }
  console.log(`${cases.length} TTS regression checks passed.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
