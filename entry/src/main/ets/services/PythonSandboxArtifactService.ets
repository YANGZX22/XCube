import { AttachmentType, MessageAttachment } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { getAttachmentStorageService } from './AttachmentStorageService'
import { getDocumentAttachmentRegistryService } from './DocumentAttachmentRegistryService'
import { PyodideImageArtifact } from './PyodideRuntimeService'
import {
  PYTHON_MAX_OUTPUT_IMAGES,
  PYTHON_MAX_OUTPUT_IMAGE_BYTES,
  PYTHON_MAX_OUTPUT_IMAGE_TOTAL_BYTES
} from './PythonSandboxRuntimePolicy'

export class PythonSandboxImageReference {
  attachmentId: string = ''
  name: string = ''
  mimeType: string = ''
  size: number = 0

  constructor(attachmentId: string, name: string, mimeType: string, size: number) {
    this.attachmentId = attachmentId
    this.name = name
    this.mimeType = mimeType
    this.size = size
  }
}

export class PythonSandboxArtifactSaveResult {
  images: PythonSandboxImageReference[] = []
  warnings: string[] = []
}

export function getPythonImageExtension(mimeType: string): string {
  if (mimeType === 'image/png') {
    return '.png'
  }
  if (mimeType === 'image/jpeg') {
    return '.jpg'
  }
  if (mimeType === 'image/gif') {
    return '.gif'
  }
  if (mimeType === 'image/webp') {
    return '.webp'
  }
  return ''
}

export function sanitizePythonImageName(name: string, mimeType: string): string {
  const normalized = name.trim().replace(/\\/g, '/')
  const slashIndex = normalized.lastIndexOf('/')
  const leafName = slashIndex >= 0 ? normalized.substring(slashIndex + 1) : normalized
  const dotIndex = leafName.lastIndexOf('.')
  const rawStem = dotIndex > 0 ? leafName.substring(0, dotIndex) : leafName
  let stem = rawStem.replace(/[^A-Za-z0-9._-]/g, '_')
  if (stem === '' || stem === '.' || stem === '..') {
    stem = 'python_image'
  }
  if (stem.length > 80) {
    stem = stem.substring(0, 80)
  }
  return `${stem}${getPythonImageExtension(mimeType)}`
}

function estimateBase64Bytes(data: string): number {
  if (data === '') {
    return 0
  }
  let padding = 0
  if (data.endsWith('==')) {
    padding = 2
  } else if (data.endsWith('=')) {
    padding = 1
  }
  return Math.max(0, Math.floor(data.length * 3 / 4) - padding)
}

export class PythonSandboxArtifactService {
  private static instance: PythonSandboxArtifactService | null = null
  private sequence: number = 0

  static getInstance(): PythonSandboxArtifactService {
    if (PythonSandboxArtifactService.instance === null) {
      PythonSandboxArtifactService.instance = new PythonSandboxArtifactService()
    }
    return PythonSandboxArtifactService.instance
  }

  async saveForCurrentSession(artifacts: PyodideImageArtifact[]): Promise<PythonSandboxArtifactSaveResult> {
    const result = new PythonSandboxArtifactSaveResult()
    if (artifacts.length === 0) {
      return result
    }

    const sessionId = getAppUiState().activeChatSessionId.trim()
    if (sessionId === '') {
      result.warnings.push('Python 已生成图片，但当前没有活动会话，无法保存为模型可调取的附件')
      return result
    }

    const storage = getAttachmentStorageService()
    if (!storage.isReady()) {
      result.warnings.push('Python 已生成图片，但附件存储尚未初始化，无法保存图片')
      return result
    }

    let totalBytes = 0
    for (let i = 0; i < artifacts.length && result.images.length < PYTHON_MAX_OUTPUT_IMAGES; i++) {
      const artifact = artifacts[i]
      const extension = getPythonImageExtension(artifact.mimeType)
      const decodedBytes = estimateBase64Bytes(artifact.data)
      if (extension === '' || artifact.data === '' || decodedBytes <= 0) {
        result.warnings.push(`Python 图片 ${artifact.name} 格式无效，未保存`)
        continue
      }
      if (decodedBytes > PYTHON_MAX_OUTPUT_IMAGE_BYTES || artifact.size > PYTHON_MAX_OUTPUT_IMAGE_BYTES) {
        result.warnings.push(`Python 图片 ${artifact.name} 超过单图大小限制，未保存`)
        continue
      }
      if (Math.abs(decodedBytes - artifact.size) > 2) {
        result.warnings.push(`Python 图片 ${artifact.name} 数据大小校验失败，未保存`)
        continue
      }
      if (totalBytes + decodedBytes > PYTHON_MAX_OUTPUT_IMAGE_TOTAL_BYTES) {
        result.warnings.push('Python 图片总大小超过限制，其余图片未保存')
        break
      }

      this.sequence += 1
      const attachmentId = `python_img_${Date.now()}_${this.sequence}`
      const safeName = sanitizePythonImageName(artifact.name, artifact.mimeType)
      const attachment = new MessageAttachment(
        attachmentId,
        AttachmentType.IMAGE,
        safeName,
        '',
        artifact.mimeType,
        decodedBytes
      )
      attachment.base64Data = artifact.data
      const filePath = await storage.saveAttachment(attachment)
      attachment.base64Data = ''
      artifact.data = ''
      if (filePath === '') {
        result.warnings.push(`Python 图片 ${safeName} 写入应用沙箱失败`)
        continue
      }

      attachment.filePath = filePath
      getDocumentAttachmentRegistryService().registerAttachments(sessionId, [attachment])
      result.images.push(new PythonSandboxImageReference(
        attachment.id,
        attachment.name,
        attachment.mimeType,
        attachment.size
      ))
      totalBytes += decodedBytes
    }
    return result
  }
}

export function getPythonSandboxArtifactService(): PythonSandboxArtifactService {
  return PythonSandboxArtifactService.getInstance()
}
