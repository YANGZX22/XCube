import { util } from '@kit.ArkTS'

export const DEFAULT_MIMO_TTS_BASE_URL: string = 'https://api.xiaomimimo.com/v1'
export const DEFAULT_MIMO_TTS_VOICE: string = 'mimo_default'
export const MIMO_TTS_VOICES: string[] = ['mimo_default', '冰糖', '茉莉', '苏打', '白桦', 'Mia', 'Chloe', 'Milo', 'Dean']

export enum MiMoTTSModel {
  PRESET = 'mimo-v2.5-tts',
  VOICE_DESIGN = 'mimo-v2.5-tts-voicedesign',
  VOICE_CLONE = 'mimo-v2.5-tts-voiceclone'
}

export class MiMoTTSSettings {
  baseUrl: string = DEFAULT_MIMO_TTS_BASE_URL
  apiKey: string = ''
  model: MiMoTTSModel = MiMoTTSModel.PRESET
  voice: string = DEFAULT_MIMO_TTS_VOICE
  voiceDescription: string = ''
  voiceSample: string = ''
}

interface MiMoTTSMessage {
  role: string
  content: string
}

interface MiMoTTSAudioOptions {
  format: string
  voice?: string
}

export interface MiMoTTSRequest {
  model: string
  messages: MiMoTTSMessage[]
  audio: MiMoTTSAudioOptions
  stream: boolean
}

interface MiMoTTSAudioResponse {
  data?: string
}

interface MiMoTTSResponseMessage {
  audio?: MiMoTTSAudioResponse
}

interface MiMoTTSChoice {
  finish_reason?: string
  message?: MiMoTTSResponseMessage
}

interface MiMoTTSResponse {
  choices?: MiMoTTSChoice[]
}

export function normalizeMiMoTTSModel(model: string): MiMoTTSModel {
  if (model === MiMoTTSModel.VOICE_DESIGN) {
    return MiMoTTSModel.VOICE_DESIGN
  }
  if (model === MiMoTTSModel.VOICE_CLONE) {
    return MiMoTTSModel.VOICE_CLONE
  }
  return MiMoTTSModel.PRESET
}

export function buildMiMoTTSEndpoint(baseUrl: string): string {
  const root = (baseUrl.trim() || DEFAULT_MIMO_TTS_BASE_URL).replace(/\/+$/, '')
  if (root.endsWith('/chat/completions')) {
    return root
  }
  return root.endsWith('/v1') ? `${root}/chat/completions` : `${root}/v1/chat/completions`
}

export function buildMiMoTTSRequest(text: string, settings: MiMoTTSSettings): MiMoTTSRequest {
  const messages: MiMoTTSMessage[] = []
  const audio: MiMoTTSAudioOptions = { format: 'mp3' }
  if (settings.model === MiMoTTSModel.VOICE_DESIGN) {
    if (settings.voiceDescription.trim() === '') {
      throw new Error('MiMo TTS 音色设计需要填写音色描述')
    }
    messages.push({ role: 'user', content: settings.voiceDescription.trim() })
  } else if (settings.model === MiMoTTSModel.VOICE_CLONE) {
    if (settings.voiceSample === '') {
      throw new Error('MiMo TTS 声音克隆需要导入 MP3 或 WAV 音频样本')
    }
    audio.voice = settings.voiceSample
  } else {
    const voice = settings.voice.trim() || DEFAULT_MIMO_TTS_VOICE
    if (!MIMO_TTS_VOICES.includes(voice)) {
      throw new Error('MiMo TTS 预置音色无效，请重新选择音色')
    }
    audio.voice = voice
  }
  // MiMo uses an assistant message for the synthesis text, even without a user message.
  // Keep text optimization disabled so Read Aloud preserves the original reply.
  messages.push({ role: 'assistant', content: text })
  return { model: settings.model, messages: messages, audio: audio, stream: false }
}

export function decodeMiMoTTSAudio(body: string): ArrayBuffer {
  let response: MiMoTTSResponse | null = null
  try {
    response = JSON.parse(body) as MiMoTTSResponse
  } catch (_error) {
    throw new Error('MiMo TTS 返回的响应不是有效 JSON')
  }
  if (response === null || !Array.isArray(response.choices) || response.choices.length === 0) {
    throw new Error('MiMo TTS 未返回有效音频')
  }
  const choice = response.choices[0]
  if (choice?.finish_reason === 'content_filter') {
    throw new Error('MiMo TTS 内容未通过审核')
  }
  if (choice?.finish_reason === 'length') {
    throw new Error('MiMo TTS 音频超过生成长度限制，请缩短文本后重试')
  }
  const data = choice?.message?.audio?.data
  if (typeof data !== 'string' || data.trim() === '') {
    throw new Error('MiMo TTS 未返回有效音频')
  }
  try {
    const bytes = new util.Base64Helper().decodeSync(data)
    if (bytes.byteLength === 0) {
      throw new Error('empty audio')
    }
    return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer
  } catch (_error) {
    throw new Error('MiMo TTS 返回的音频 Base64 无效')
  }
}
