/**
 * 本地离线语音识别服务（基于 sherpa-onnx + SenseVoice 多语言模型）
 * 用于聊天框「语音输入」：长按录音 → 松手后整段识别 → 返回文字
 *
 * 模型固定为内置 rawfile 中的 SenseVoice（中/英/日/韩/粤），单例懒加载。
 */
import audio from '@ohos.multimedia.audio';
import common from '@ohos.app.ability.common';

import {
  OfflineRecognizer,
  OfflineRecognizerConfig,
  OfflineRecognizerResult,
  OfflineStream,
  Samples
} from '../sherpa/NonStreamingAsr';

// SenseVoice 模型在 rawfile 中的文件夹名（与官方发布包一致）
const SENSE_VOICE_FOLDER = 'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17';

export class AsrResult {
  text: string;
  isFinal: boolean;

  constructor(text: string, isFinal: boolean) {
    this.text = text;
    this.isFinal = isFinal;
  }
}

export type AsrResultCallback = (res: AsrResult) => void;
export type AsrErrorCallback = (msg: string) => void;

export class SherpaAsrService {
  private static instance: SherpaAsrService | null = null;

  private ctx?: common.UIAbilityContext;
  private recognizer?: OfflineRecognizer;
  private initialized: boolean = false;
  private initializing: boolean = false;

  private capturer: audio.AudioCapturer | null = null;
  private capturing: boolean = false;

  private onResult?: AsrResultCallback;
  private onError?: AsrErrorCallback;

  // 录音期间缓存的 PCM 分片，stop() 后整段解码
  private pcmChunks: Int16Array[] = [];

  private readonly sampleRate: number = 16000;
  // SenseVoice 语言：'auto' 自动识别中/英/日/韩/粤
  private senseVoiceLanguage: string = 'auto';

  private constructor() {}

  static getInstance(): SherpaAsrService {
    if (SherpaAsrService.instance === null) {
      SherpaAsrService.instance = new SherpaAsrService();
    }
    return SherpaAsrService.instance;
  }

  isReady(): boolean {
    return this.initialized && this.recognizer !== undefined;
  }

  isInitializing(): boolean {
    return this.initializing;
  }

  isRecording(): boolean {
    return this.capturing;
  }

  /**
   * 初始化 SenseVoice 识别器（幂等）。首次调用会加载 rawfile 中的模型，耗时较长。
   */
  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return;
    }
    if (this.initializing) {
      // 等待正在进行的初始化完成
      while (this.initializing) {
        await new Promise<void>(resolve => setTimeout(resolve, 100));
      }
      return;
    }

    this.initializing = true;
    this.ctx = ctx;

    try {
      const cfg = new OfflineRecognizerConfig();
      cfg.featConfig.sampleRate = this.sampleRate;
      cfg.featConfig.featureDim = 80;

      const base = `rawfile/${SENSE_VOICE_FOLDER}`;
      cfg.modelConfig.senseVoice.model = `${base}/model.int8.onnx`;
      cfg.modelConfig.senseVoice.language = this.senseVoiceLanguage;
      cfg.modelConfig.senseVoice.useItn = true;
      cfg.modelConfig.tokens = `${base}/tokens.txt`;
      cfg.modelConfig.modelType = 'sense_voice';
      cfg.modelConfig.modelingUnit = 'cjkchar';
      cfg.modelConfig.numThreads = 4;
      cfg.modelConfig.debug = false;
      cfg.modelConfig.provider = 'cpu';
      cfg.decodingMethod = 'greedy_search';

      // rawfile 模型需要传 resourceManager
      this.recognizer = new OfflineRecognizer(cfg, ctx.resourceManager);
      this.initialized = true;
      console.info('[SherpaAsr] SenseVoice model initialized');
    } catch (e) {
      console.error('[SherpaAsr] init failed: ' + JSON.stringify(e));
      throw e as Error;
    } finally {
      this.initializing = false;
    }
  }

  /**
   * 设置 SenseVoice 识别语言：'auto' | 'zh' | 'en' | 'ja' | 'ko' | 'yue'
   * 需在 init 前调用才生效。
   */
  setLanguage(language: string): void {
    this.senseVoiceLanguage = language;
  }

  /**
   * 开始录音并缓存音频。识别结果在 stop() 后通过 onResult(isFinal=true) 回调一次。
   */
  start(onResult: AsrResultCallback, onError: AsrErrorCallback): void {
    this.onResult = onResult;
    this.onError = onError;

    if (!this.recognizer) {
      const msg = 'start: recognizer not initialized. Call init() first.';
      console.error('[SherpaAsr] ' + msg);
      if (this.onError) {
        this.onError(msg);
      }
      return;
    }

    if (this.capturing) {
      return;
    }

    this.pcmChunks = [];
    this.capturing = true;
    void this.captureLoop();
  }

  /**
   * 停止录音；触发整段最终解码。
   */
  stop(): void {
    this.capturing = false;
  }

  private async ensureCapturer(): Promise<void> {
    if (this.capturer !== null) {
      return;
    }

    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    };

    const info: audio.AudioCapturerInfo = {
      source: audio.SourceType.SOURCE_TYPE_MIC,
      capturerFlags: 0
    };

    const options: audio.AudioCapturerOptions = {
      streamInfo,
      capturerInfo: info
    };

    try {
      this.capturer = await audio.createAudioCapturer(options);
    } catch (e) {
      if (this.onError) {
        this.onError('无法创建音频捕捉，请检查麦克风权限');
      }
      console.error('[SherpaAsr] AudioCapturer create failed: ' + JSON.stringify(e));
    }
  }

  private async captureLoop(): Promise<void> {
    await this.ensureCapturer();
    if (!this.capturer) {
      this.capturing = false;
      return;
    }

    try {
      await this.capturer.start();
    } catch (e) {
      if (this.onError) {
        this.onError('麦克风启动失败');
      }
      console.error('[SherpaAsr] AudioCapturer start failed: ' + JSON.stringify(e));
      this.capturing = false;
      return;
    }

    while (this.capturing) {
      try {
        const bufferSize: number = await this.capturer.getBufferSize();
        const buf: ArrayBuffer = await this.capturer.read(bufferSize, true);
        const view = new Int16Array(buf);
        if (view.length > 0) {
          const copy = new Int16Array(view.length);
          copy.set(view);
          this.pcmChunks.push(copy);
        }
      } catch (e) {
        console.error('[SherpaAsr] Error reading from mic: ' + JSON.stringify(e));
        if (this.onError) {
          this.onError('录音读取失败');
        }
        break;
      }
    }

    try {
      await this.capturer.stop();
    } catch (e) {
      console.warn('[SherpaAsr] Error stopping capturer: ' + JSON.stringify(e));
    }

    // 整段最终解码
    this.decodeFinal();
  }

  private buildWaveform(): Float32Array | null {
    if (this.pcmChunks.length === 0) {
      return null;
    }

    let totalLen = 0;
    for (const c of this.pcmChunks) {
      totalLen += c.length;
    }
    if (totalLen <= 0) {
      return null;
    }

    const merged = new Int16Array(totalLen);
    let copied = 0;
    for (const c of this.pcmChunks) {
      merged.set(c, copied);
      copied += c.length;
    }
    this.pcmChunks = [];

    const f32 = new Float32Array(merged.length);
    for (let i = 0; i < merged.length; i++) {
      f32[i] = merged[i] / 32768.0;
    }
    return f32;
  }

  private decodeFinal(): void {
    if (!this.recognizer) {
      if (this.onError) {
        this.onError('识别器未就绪');
      }
      return;
    }

    const waveform = this.buildWaveform();
    if (!waveform || waveform.length === 0) {
      console.info('[SherpaAsr] decodeFinal: no audio captured');
      // 仍回调一次空 final，便于 UI 关闭录音态
      if (this.onResult) {
        this.onResult(new AsrResult('', true));
      }
      return;
    }

    const samples: Samples = {
      samples: waveform,
      sampleRate: this.sampleRate
    };

    try {
      const stream: OfflineStream = this.recognizer.createStream();
      stream.acceptWaveform(samples);
      this.recognizer.decode(stream);
      const result: OfflineRecognizerResult = this.recognizer.getResult(stream);
      const text = (result.text ?? '').trim();
      console.info(`[SherpaAsr] final result="${text}"`);
      if (this.onResult) {
        this.onResult(new AsrResult(text, true));
      }
    } catch (e) {
      console.error('[SherpaAsr] decode failed: ' + JSON.stringify(e));
      if (this.onError) {
        this.onError('识别失败');
      }
    }
  }
}

export function getSherpaAsrService(): SherpaAsrService {
  return SherpaAsrService.getInstance();
}
