import { TextReader, ReadStateCode } from '@kit.SpeechKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { http } from '@kit.NetworkKit'
import { media } from '@kit.MediaKit'
import { util } from '@kit.ArkTS'
import { getPreferencesService, PreferenceKeys } from './PreferencesService'

export enum TTSEngineType {
  LOCAL = 'local',
  ELEVENLABS = 'elevenlabs'
}

export const DEFAULT_ELEVENLABS_BASE_URL: string = 'https://api.elevenlabs.io'
export const DEFAULT_ELEVENLABS_MODEL_ID: string = 'eleven_multilingual_v2'
export const DEFAULT_ELEVENLABS_STABILITY: number = 0.5
export const DEFAULT_ELEVENLABS_SIMILARITY_BOOST: number = 0.75
export const DEFAULT_ELEVENLABS_SPEED: number = 1.0

// TTS事件回调接口
export interface TTSCallback {
  onStart: () => void
  onComplete: () => void
  onError: (error: string) => void
}

class TTSSettingsSnapshot {
  enabled: boolean = true
  engine: TTSEngineType = TTSEngineType.LOCAL
  elevenLabsBaseUrl: string = DEFAULT_ELEVENLABS_BASE_URL
  elevenLabsApiKey: string = ''
  elevenLabsVoiceId: string = ''
  elevenLabsModelId: string = DEFAULT_ELEVENLABS_MODEL_ID
  elevenLabsStability: number = DEFAULT_ELEVENLABS_STABILITY
  elevenLabsSimilarityBoost: number = DEFAULT_ELEVENLABS_SIMILARITY_BOOST
  elevenLabsSpeed: number = DEFAULT_ELEVENLABS_SPEED
}

class ElevenLabsVoiceSettingsPayload {
  stability: number
  similarity_boost: number
  speed: number
  use_speaker_boost: boolean = true

  constructor(stability: number, similarityBoost: number, speed: number) {
    this.stability = stability
    this.similarity_boost = similarityBoost
    this.speed = speed
  }
}

class ElevenLabsTTSRequestPayload {
  text: string
  model_id: string
  voice_settings: ElevenLabsVoiceSettingsPayload
  previous_text?: string
  next_text?: string

  constructor(text: string, modelId: string, voiceSettings: ElevenLabsVoiceSettingsPayload) {
    this.text = text
    this.model_id = modelId
    this.voice_settings = voiceSettings
  }
}

interface ElevenLabsVoiceApiItem {
  voice_id: string
  name: string
  category?: string
}

interface ElevenLabsVoicesApiResponse {
  voices: ElevenLabsVoiceApiItem[]
  has_more: boolean
  next_page_token?: string | null
}

export class ElevenLabsVoiceInfo {
  voiceId: string
  name: string
  category: string

  constructor(voiceId: string, name: string, category: string) {
    this.voiceId = voiceId
    this.name = name
    this.category = category
  }
}

export class TTSService {
  private context: common.Context | null = null
  private localReaderInitialized: boolean = false
  private isReading: boolean = false
  private currentCallback: TTSCallback | null = null
  private currentReadId: string = ''
  private activeRequestToken: number = 0
  private activeEngine: TTSEngineType = TTSEngineType.LOCAL
  private localStopPromise: Promise<void> | null = null

  private apiRequest: http.HttpRequest | null = null
  private apiPlayer: media.AVPlayer | null = null
  private apiAudioFile: fileIo.File | null = null
  private apiAudioPath: string = ''
  private apiChunks: string[] = []
  private apiChunkIndex: number = 0
  private apiStartNotified: boolean = false
  private apiSettings: TTSSettingsSnapshot | null = null
  private voiceListRequest: http.HttpRequest | null = null

  // 保存上下文；本地朗读引擎按需初始化，避免用户选择 API 时仍启动系统朗读控件。
  async init(context: common.Context): Promise<void> {
    this.context = context
  }

  // 获取当前 ElevenLabs 账号可用的语音，供设置页的 Voice ID 选择器使用。
  async listElevenLabsVoices(baseUrl: string, apiKey: string): Promise<ElevenLabsVoiceInfo[]> {
    const normalizedApiKey = apiKey.trim()
    if (normalizedApiKey === '') {
      throw new Error('请先填写 ElevenLabs API Key')
    }

    const voices: ElevenLabsVoiceInfo[] = []
    const seenVoiceIds: Set<string> = new Set<string>()
    let nextPageToken: string = ''
    let hasMore: boolean = true
    let pageCount: number = 0

    while (hasMore && pageCount < 20) {
      const request = http.createHttp()
      this.voiceListRequest = request
      let endpoint = `${this.buildElevenLabsApiRoot(baseUrl)}/v2/voices` +
        '?page_size=100&sort=name&sort_direction=asc&include_total_count=false'
      if (nextPageToken !== '') {
        endpoint += `&next_page_token=${encodeURIComponent(nextPageToken)}`
      }

      try {
        const response = await request.request(endpoint, {
          method: http.RequestMethod.GET,
          header: {
            'Accept': 'application/json',
            'xi-api-key': normalizedApiKey
          },
          connectTimeout: 15000,
          readTimeout: 30000,
          expectDataType: http.HttpDataType.STRING
        })
        if (response.responseCode < 200 || response.responseCode >= 300) {
          const detail = this.decodeResponseBody(response.result)
          throw new Error(detail !== '' ?
            `获取 ElevenLabs 语音失败 (${response.responseCode}): ${detail}` :
            `获取 ElevenLabs 语音失败 (${response.responseCode})`)
        }
        if (typeof response.result !== 'string') {
          throw new Error('ElevenLabs 返回了无法识别的语音列表')
        }

        const parsed = JSON.parse(response.result) as ElevenLabsVoicesApiResponse
        if (!Array.isArray(parsed.voices)) {
          throw new Error('ElevenLabs 返回的语音列表格式无效')
        }
        for (let index = 0; index < parsed.voices.length; index++) {
          const item = parsed.voices[index]
          const voiceId = item.voice_id?.trim() ?? ''
          if (voiceId === '' || seenVoiceIds.has(voiceId)) {
            continue
          }
          seenVoiceIds.add(voiceId)
          voices.push(new ElevenLabsVoiceInfo(
            voiceId,
            item.name?.trim() ?? voiceId,
            item.category?.trim() ?? ''
          ))
        }

        hasMore = parsed.has_more === true
        nextPageToken = parsed.next_page_token ?? ''
        if (nextPageToken === '') {
          hasMore = false
        }
        pageCount += 1
      } catch (error) {
        if (error instanceof Error && error.message.startsWith('获取 ElevenLabs')) {
          throw error
        }
        const err = error as BusinessError
        throw new Error(`获取 ElevenLabs 语音失败: ${err.message ?? JSON.stringify(error)}`)
      } finally {
        if (this.voiceListRequest === request) {
          this.voiceListRequest = null
        }
        try {
          request.destroy()
        } catch (_error) {}
      }
    }
    return voices
  }

  cancelVoiceListRequest(): void {
    if (this.voiceListRequest === null) {
      return
    }
    try {
      this.voiceListRequest.destroy()
    } catch (_error) {}
    this.voiceListRequest = null
  }

  // 朗读文本。引擎配置每次读取，设置页修改后无需重建聊天页面。
  async speak(text: string, callback: TTSCallback): Promise<void> {
    if (this.context === null) {
      callback.onError('朗读服务未初始化')
      return
    }

    const settings = await this.loadSettings()
    if (!settings.enabled) {
      callback.onError('播报功能已关闭，请先在设置中开启')
      return
    }

    const processedText = this.preprocessTextForTTS(text)
    if (processedText === '') {
      callback.onError('没有可朗读的内容')
      return
    }

    this.stop()
    this.activeRequestToken += 1
    const requestToken = this.activeRequestToken
    this.currentCallback = callback
    this.activeEngine = settings.engine

    if (settings.engine === TTSEngineType.ELEVENLABS) {
      await this.speakWithElevenLabs(processedText, settings, requestToken)
      return
    }
    await this.speakWithLocalReader(processedText, requestToken)
  }

  private async loadSettings(): Promise<TTSSettingsSnapshot> {
    const prefs = getPreferencesService()
    const settings = new TTSSettingsSnapshot()
    settings.enabled = await prefs.getBoolean(PreferenceKeys.TTS_ENABLED, true)
    const engine = await prefs.getString(PreferenceKeys.TTS_ENGINE, TTSEngineType.LOCAL)
    settings.engine = engine === TTSEngineType.ELEVENLABS ? TTSEngineType.ELEVENLABS : TTSEngineType.LOCAL
    settings.elevenLabsBaseUrl = await prefs.getString(
      PreferenceKeys.ELEVENLABS_BASE_URL,
      DEFAULT_ELEVENLABS_BASE_URL
    )
    settings.elevenLabsApiKey = await prefs.getString(PreferenceKeys.ELEVENLABS_API_KEY, '')
    settings.elevenLabsVoiceId = await prefs.getString(PreferenceKeys.ELEVENLABS_VOICE_ID, '')
    settings.elevenLabsModelId = await prefs.getString(
      PreferenceKeys.ELEVENLABS_MODEL_ID,
      DEFAULT_ELEVENLABS_MODEL_ID
    )
    settings.elevenLabsStability = this.clamp(
      await prefs.getNumber(PreferenceKeys.ELEVENLABS_STABILITY, DEFAULT_ELEVENLABS_STABILITY),
      0,
      1
    )
    settings.elevenLabsSimilarityBoost = this.clamp(
      await prefs.getNumber(
        PreferenceKeys.ELEVENLABS_SIMILARITY_BOOST,
        DEFAULT_ELEVENLABS_SIMILARITY_BOOST
      ),
      0,
      1
    )
    settings.elevenLabsSpeed = this.clamp(
      await prefs.getNumber(PreferenceKeys.ELEVENLABS_SPEED, DEFAULT_ELEVENLABS_SPEED),
      0.7,
      1.2
    )
    return settings
  }

  private async ensureLocalReaderInitialized(): Promise<void> {
    if (this.localReaderInitialized) {
      return
    }
    if (this.context === null) {
      throw new Error('应用上下文不可用')
    }

    const readerParams: TextReader.ReaderParam = {
      isVoiceBrandVisible: true,
      businessBrandInfo: {
        panelName: 'XCube 播报'
      },
      // 1 为系统离线合成，保证“本地 TTS”不依赖第三方 API。
      online: 1,
      person: {
        tone: 0,
        style: 'interaction-broadcast'
      }
    }

    try {
      await TextReader.init(this.context, readerParams)
      TextReader.on('stateChange', (state: TextReader.ReadState) => {
        if (state.id !== this.currentReadId || this.activeEngine !== TTSEngineType.LOCAL) {
          return
        }
        if (state.state === ReadStateCode.PLAYING) {
          this.isReading = true
          if (this.currentCallback !== null) {
            this.currentCallback.onStart()
          }
        } else if (state.state === ReadStateCode.PAUSED || state.state === ReadStateCode.COMPLETED) {
          this.finishCurrentRequest()
        }
      })
      // 用户从系统朗读面板关闭播放时，及时恢复消息工具栏的播报图标。
      TextReader.on('stop', () => {
        if (this.activeEngine === TTSEngineType.LOCAL && this.currentCallback !== null) {
          this.finishCurrentRequest()
        }
      })
      this.localReaderInitialized = true
      console.info('TTSService', 'Local TextReader initialized successfully')
    } catch (error) {
      const err = error as BusinessError
      console.error('TTSService', `Local TextReader init failed: ${err.code}, ${err.message}`)
      throw new Error(`本地 TTS 初始化失败: ${err.message}`)
    }
  }

  private async speakWithLocalReader(text: string, requestToken: number): Promise<void> {
    try {
      await this.waitForLocalStop()
      if (requestToken !== this.activeRequestToken) {
        return
      }
      await this.ensureLocalReaderInitialized()
      if (requestToken !== this.activeRequestToken) {
        return
      }

      this.currentReadId = `xcube${Date.now()}`
      const readInfoList: TextReader.ReadInfo[] = [{
        id: this.currentReadId,
        title: { text: 'AI 回复', isClickable: false },
        bodyInfo: text
      }]
      await TextReader.start(readInfoList, this.currentReadId)
    } catch (error) {
      if (requestToken !== this.activeRequestToken) {
        return
      }
      const message = error instanceof Error ? error.message : JSON.stringify(error)
      this.failCurrentRequest(message.startsWith('本地 TTS') ? message : `朗读失败: ${message}`)
    }
  }

  private async speakWithElevenLabs(
    text: string,
    settings: TTSSettingsSnapshot,
    requestToken: number
  ): Promise<void> {
    if (settings.elevenLabsApiKey.trim() === '') {
      this.failCurrentRequest('请先在播报设置中填写 ElevenLabs API Key')
      return
    }
    if (settings.elevenLabsVoiceId.trim() === '') {
      this.failCurrentRequest('请先在播报设置中填写 ElevenLabs Voice ID')
      return
    }

    // 4,500 字符兼容 Eleven v3 的 5,000 字符限制，并预留前后文参数空间。
    this.apiChunks = this.splitTextForElevenLabs(text, 4500)
    this.apiChunkIndex = 0
    this.apiStartNotified = false
    this.apiSettings = settings
    await this.generateAndPlayCurrentChunk(requestToken)
  }

  private async generateAndPlayCurrentChunk(requestToken: number): Promise<void> {
    if (requestToken !== this.activeRequestToken || this.apiSettings === null) {
      return
    }
    if (this.apiChunkIndex >= this.apiChunks.length) {
      this.finishCurrentRequest()
      return
    }

    const previousText = this.apiChunkIndex > 0 ? this.apiChunks[this.apiChunkIndex - 1] : ''
    const nextText = this.apiChunkIndex + 1 < this.apiChunks.length ? this.apiChunks[this.apiChunkIndex + 1] : ''
    try {
      const audio = await this.requestElevenLabsAudio(
        this.apiChunks[this.apiChunkIndex],
        previousText,
        nextText,
        this.apiSettings,
        requestToken
      )
      if (requestToken !== this.activeRequestToken) {
        return
      }
      await this.playElevenLabsAudio(audio, requestToken)
    } catch (error) {
      if (requestToken !== this.activeRequestToken) {
        return
      }
      const message = error instanceof Error ? error.message : JSON.stringify(error)
      this.failCurrentRequest(message)
    }
  }

  private async requestElevenLabsAudio(
    text: string,
    previousText: string,
    nextText: string,
    settings: TTSSettingsSnapshot,
    requestToken: number
  ): Promise<ArrayBuffer> {
    const request = http.createHttp()
    this.apiRequest = request

    const voiceSettings = new ElevenLabsVoiceSettingsPayload(
      settings.elevenLabsStability,
      settings.elevenLabsSimilarityBoost,
      settings.elevenLabsSpeed
    )
    const payload = new ElevenLabsTTSRequestPayload(text, settings.elevenLabsModelId.trim(), voiceSettings)
    if (previousText !== '') {
      payload.previous_text = previousText
    }
    if (nextText !== '') {
      payload.next_text = nextText
    }

    const endpoint = this.buildElevenLabsEndpoint(settings.elevenLabsBaseUrl, settings.elevenLabsVoiceId)
    try {
      const response = await request.request(endpoint, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
          'xi-api-key': settings.elevenLabsApiKey.trim()
        },
        extraData: JSON.stringify(payload),
        connectTimeout: 15000,
        readTimeout: 180000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      })

      if (requestToken !== this.activeRequestToken) {
        throw new Error('朗读请求已取消')
      }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const detail = this.decodeResponseBody(response.result)
        if (detail !== '') {
          throw new Error(`ElevenLabs 请求失败 (${response.responseCode}): ${detail}`)
        }
        throw new Error(`ElevenLabs 请求失败 (${response.responseCode})`)
      }
      if (!(response.result instanceof ArrayBuffer) || response.result.byteLength <= 0) {
        throw new Error('ElevenLabs 未返回有效音频')
      }
      return response.result
    } catch (error) {
      if (requestToken !== this.activeRequestToken) {
        throw new Error('朗读请求已取消')
      }
      if (error instanceof Error && error.message.startsWith('ElevenLabs')) {
        throw error
      }
      const err = error as BusinessError
      throw new Error(`ElevenLabs 请求失败: ${err.message ?? JSON.stringify(error)}`)
    } finally {
      if (this.apiRequest === request) {
        this.apiRequest = null
      }
      try {
        request.destroy()
      } catch (_error) {}
    }
  }

  private async playElevenLabsAudio(audio: ArrayBuffer, requestToken: number): Promise<void> {
    if (this.context === null) {
      throw new Error('应用上下文不可用')
    }

    const path = `${this.context.cacheDir}/xcube_tts_${Date.now()}_${this.apiChunkIndex}.mp3`
    const outputFile = fileIo.openSync(
      path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
    )
    try {
      fileIo.writeSync(outputFile.fd, audio)
    } finally {
      fileIo.closeSync(outputFile)
    }

    if (requestToken !== this.activeRequestToken) {
      this.deleteFileSafely(path)
      return
    }

    const sourceFile = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
    const player = await media.createAVPlayer()
    if (requestToken !== this.activeRequestToken) {
      fileIo.closeSync(sourceFile)
      this.deleteFileSafely(path)
      await player.release()
      return
    }

    this.apiAudioPath = path
    this.apiAudioFile = sourceFile
    this.apiPlayer = player

    player.on('error', (error: BusinessError) => {
      if (player !== this.apiPlayer || requestToken !== this.activeRequestToken) {
        return
      }
      this.failCurrentRequest(`音频播放失败: ${error.message}`)
    })
    player.on('stateChange', (state: media.AVPlayerState, _reason: media.StateChangeReason) => {
      if (player !== this.apiPlayer || requestToken !== this.activeRequestToken) {
        return
      }
      if (state === 'initialized') {
        player.prepare().catch((error: Error): void => {
          this.failCurrentRequest(`音频准备失败: ${error.message}`)
        })
      } else if (state === 'prepared') {
        player.play().catch((error: Error): void => {
          this.failCurrentRequest(`音频播放失败: ${error.message}`)
        })
      } else if (state === 'playing') {
        this.isReading = true
        if (!this.apiStartNotified && this.currentCallback !== null) {
          this.apiStartNotified = true
          this.currentCallback.onStart()
        }
      } else if (state === 'completed') {
        this.finishApiChunk(player, requestToken)
      }
    })

    player.fdSrc = {
      fd: sourceFile.fd,
      offset: 0,
      length: audio.byteLength
    }
  }

  private finishApiChunk(player: media.AVPlayer, requestToken: number): void {
    if (player !== this.apiPlayer) {
      return
    }
    this.apiPlayer = null
    const audioFile = this.apiAudioFile
    const audioPath = this.apiAudioPath
    this.apiAudioFile = null
    this.apiAudioPath = ''

    this.releaseApiResources(player, audioFile, audioPath).then((): void => {
      if (requestToken !== this.activeRequestToken) {
        return
      }
      this.apiChunkIndex += 1
      this.generateAndPlayCurrentChunk(requestToken)
    })
  }

  private async releaseApiResources(
    player: media.AVPlayer | null,
    audioFile: fileIo.File | null,
    audioPath: string
  ): Promise<void> {
    if (player !== null) {
      try {
        player.off('stateChange')
        player.off('error')
        await player.release()
      } catch (_error) {}
    }
    if (audioFile !== null) {
      try {
        fileIo.closeSync(audioFile)
      } catch (_error) {}
    }
    this.deleteFileSafely(audioPath)
  }

  // 停止本地或 API 播报。
  stop(): void {
    const shouldStopLocalReader = this.localReaderInitialized &&
      this.activeEngine === TTSEngineType.LOCAL &&
      (this.isReading || this.currentCallback !== null)
    this.activeRequestToken += 1
    this.isReading = false
    this.currentCallback = null
    this.currentReadId = ''
    this.apiChunks = []
    this.apiChunkIndex = 0
    this.apiSettings = null

    if (shouldStopLocalReader) {
      const stopPromise = TextReader.stop().catch((error: Error): void => {
        console.error('TTSService', `Local TextReader stop failed: ${error.message}`)
      })
      this.localStopPromise = stopPromise
      stopPromise.then((): void => {
        if (this.localStopPromise === stopPromise) {
          this.localStopPromise = null
        }
      })
    }
    if (this.apiRequest !== null) {
      try {
        this.apiRequest.destroy()
      } catch (_error) {}
      this.apiRequest = null
    }

    const player = this.apiPlayer
    const audioFile = this.apiAudioFile
    const audioPath = this.apiAudioPath
    this.apiPlayer = null
    this.apiAudioFile = null
    this.apiAudioPath = ''
    this.releaseApiResources(player, audioFile, audioPath)
  }

  getReadingStatus(): boolean {
    return this.isReading
  }

  private async waitForLocalStop(): Promise<void> {
    const pendingStop = this.localStopPromise
    if (pendingStop !== null) {
      await pendingStop
    }
  }

  async destroy(): Promise<void> {
    this.stop()
    await this.waitForLocalStop()
    if (this.localReaderInitialized) {
      try {
        TextReader.off('stateChange')
        TextReader.off('stop')
      } catch (error) {
        console.error('TTSService', `Local TextReader listener release failed: ${JSON.stringify(error)}`)
      }
      await TextReader.release().catch((error: Error): void => {
        console.error('TTSService', `Local TextReader release failed: ${JSON.stringify(error)}`)
      })
    }
    this.localReaderInitialized = false
    this.context = null
  }

  private finishCurrentRequest(): void {
    this.isReading = false
    this.currentReadId = ''
    this.apiChunks = []
    this.apiChunkIndex = 0
    this.apiSettings = null
    const callback = this.currentCallback
    this.currentCallback = null
    if (callback !== null) {
      callback.onComplete()
    }
  }

  private failCurrentRequest(message: string): void {
    this.isReading = false
    this.activeRequestToken += 1
    const callback = this.currentCallback
    this.currentCallback = null

    if (this.apiRequest !== null) {
      try {
        this.apiRequest.destroy()
      } catch (_error) {}
      this.apiRequest = null
    }
    const player = this.apiPlayer
    const audioFile = this.apiAudioFile
    const audioPath = this.apiAudioPath
    this.apiPlayer = null
    this.apiAudioFile = null
    this.apiAudioPath = ''
    this.releaseApiResources(player, audioFile, audioPath)

    if (callback !== null) {
      callback.onError(message)
    }
  }

  private buildElevenLabsEndpoint(baseUrl: string, voiceId: string): string {
    const root = this.buildElevenLabsApiRoot(baseUrl)
    return `${root}/v1/text-to-speech/${encodeURIComponent(voiceId.trim())}?output_format=mp3_44100_128`
  }

  private buildElevenLabsApiRoot(baseUrl: string): string {
    let root = baseUrl.trim()
    if (root === '') {
      root = DEFAULT_ELEVENLABS_BASE_URL
    }
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1)
    }
    if (root.endsWith('/v1') || root.endsWith('/v2')) {
      root = root.substring(0, root.length - 3)
    }
    return root
  }

  private decodeResponseBody(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result.length > 500 ? result.substring(0, 500) : result
    }
    if (result instanceof ArrayBuffer) {
      try {
        const text = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(result))
        return text.length > 500 ? text.substring(0, 500) : text
      } catch (_error) {
        return ''
      }
    }
    return ''
  }

  private splitTextForElevenLabs(text: string, maxLength: number): string[] {
    const chunks: string[] = []
    let remaining = text.trim()
    while (remaining.length > maxLength) {
      const candidate = remaining.substring(0, maxLength)
      const minBreakIndex = Math.floor(maxLength * 0.55)
      const separators: string[] = ['\n\n', '\n', '。', '！', '？', '. ', '! ', '? ', '；', '; ', '，', ', ']
      let breakIndex = -1
      let separatorLength = 0

      for (let i = 0; i < separators.length; i++) {
        const separator = separators[i]
        const index = candidate.lastIndexOf(separator)
        if (index >= minBreakIndex && index > breakIndex) {
          breakIndex = index
          separatorLength = separator.length
        }
      }
      if (breakIndex < 0) {
        breakIndex = maxLength
        separatorLength = 0
      }

      const endIndex = breakIndex + separatorLength
      const chunk = remaining.substring(0, endIndex).trim()
      if (chunk !== '') {
        chunks.push(chunk)
      }
      remaining = remaining.substring(endIndex).trim()
    }
    if (remaining !== '') {
      chunks.push(remaining)
    }
    return chunks
  }

  private deleteFileSafely(path: string): void {
    if (path === '') {
      return
    }
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (_error) {}
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.min(max, Math.max(min, value))
  }

  // 文本预处理：保留自然标点，移除不适合播报的 Markdown 和代码。
  private preprocessTextForTTS(markdown: string): string {
    if (markdown === '') {
      return ''
    }

    let text = markdown
    text = text.replace(/```[\s\S]*?```/g, '')
    text = text.replace(/`[^`]*`/g, '')
    text = text.replace(/\*\*\*([^*]+)\*\*\*/g, '$1')
    text = text.replace(/\*\*([^*]+)\*\*/g, '$1')
    text = text.replace(/\*([^*]+)\*/g, '$1')
    text = text.replace(/___([^_]+)___/g, '$1')
    text = text.replace(/__([^_]+)__/g, '$1')
    text = text.replace(/_([^_]+)_/g, '$1')
    text = text.replace(/~~([^~]+)~~/g, '$1')
    text = text.replace(/^#{1,6}\s+/gm, '')
    text = text.replace(/^>\s+/gm, '')
    text = text.replace(/!\[[^\]]*\]\([^)]+\)/g, '')
    text = text.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    text = text.replace(/^[-*+]\s+/gm, '')
    text = text.replace(/^\d+\.\s+/gm, '')
    text = text.replace(/^[-*_]{3,}\s*$/gm, '')
    text = text.replace(/\$\$[\s\S]*?\$\$/g, '公式')
    text = text.replace(/\$[^$]*\$/g, '公式')
    text = text.replace(/\n{3,}/g, '\n\n')
    return text.trim()
  }
}

let sharedTTSService: TTSService | null = null

export function getTTSService(): TTSService {
  if (sharedTTSService === null) {
    sharedTTSService = new TTSService()
  }
  return sharedTTSService
}
