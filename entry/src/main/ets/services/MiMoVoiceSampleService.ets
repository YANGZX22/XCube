import { common } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'

// App-side import limit to keep reference audio and its Base64 copy bounded in memory.
const MAX_VOICE_SAMPLE_BYTES: number = 10 * 1024 * 1024

function voiceSamplePath(context: common.Context): string {
  return `${context.filesDir}/mimo_tts_reference_audio`
}

export function hasMiMoVoiceSample(context: common.Context): boolean {
  return fileIo.accessSync(voiceSamplePath(context))
}

function readVoiceSample(path: string): Uint8Array {
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
  try {
    const size = fileIo.statSync(file.fd).size
    if (size <= 0 || size > MAX_VOICE_SAMPLE_BYTES) {
      throw new Error('音频样本须为非空文件，且不超过 10 MiB')
    }
    const bytes = new Uint8Array(size)
    let offset = 0
    while (offset < size) {
      const chunk = new ArrayBuffer(Math.min(size - offset, 1024 * 1024))
      const count = fileIo.readSync(file.fd, chunk)
      if (count <= 0) {
        throw new Error('音频样本读取不完整，请重新导入')
      }
      bytes.set(new Uint8Array(chunk, 0, count), offset)
      offset += count
    }
    return bytes
  } finally {
    fileIo.closeSync(file)
  }
}

export function importMiMoVoiceSample(context: common.Context, uri: string): string {
  const encodedName = uri.substring(uri.lastIndexOf('/') + 1).split('?')[0].split('#')[0]
  let name = encodedName
  try {
    name = decodeURIComponent(encodedName)
  } catch (_error) {}
  if (!/\.(mp3|wav)$/i.test(name)) {
    throw new Error('请选择 MP3 或 WAV 音频样本')
  }
  const bytes = readVoiceSample(uri)
  const path = voiceSamplePath(context)
  const temporaryPath = `${path}.tmp`
  try {
    const file = fileIo.openSync(temporaryPath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
    try {
      const written = fileIo.writeSync(file.fd, bytes.buffer as ArrayBuffer)
      if (written !== bytes.byteLength) {
        throw new Error('音频样本保存不完整，请重新导入')
      }
    } finally {
      fileIo.closeSync(file)
    }
    fileIo.renameSync(temporaryPath, path)
  } finally {
    if (fileIo.accessSync(temporaryPath)) {
      fileIo.unlinkSync(temporaryPath)
    }
  }
  return name
}

export function readMiMoVoiceSample(context: common.Context): string {
  if (!hasMiMoVoiceSample(context)) {
    throw new Error('MiMo TTS 声音克隆需要导入 MP3 或 WAV 音频样本')
  }
  return new util.Base64Helper().encodeToStringSync(readVoiceSample(voiceSamplePath(context)))
}
