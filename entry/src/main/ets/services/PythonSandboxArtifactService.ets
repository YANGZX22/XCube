import { AttachmentType, MessageAttachment } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { getAttachmentStorageService } from './AttachmentStorageService'
import { getDocumentAttachmentRegistryService } from './DocumentAttachmentRegistryService'
import {
  buildPythonSandboxFileMarkdown,
  buildPythonSandboxFileUrl
} from './PythonSandboxArtifactLink'
import { PyodideOutputArtifact } from './PyodideRuntimeService'
import {
  PYTHON_MAX_OUTPUT_FILES,
  PYTHON_MAX_OUTPUT_FILE_BYTES,
  PYTHON_MAX_OUTPUT_FILE_TOTAL_BYTES,
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

export class PythonSandboxFileReference {
  attachmentId: string = ''
  name: string = ''
  mimeType: string = ''
  size: number = 0
  url: string = ''
  markdown: string = ''

  constructor(attachmentId: string, name: string, mimeType: string, size: number) {
    this.attachmentId = attachmentId
    this.name = name
    this.mimeType = mimeType
    this.size = size
    this.url = buildPythonSandboxFileUrl(attachmentId)
    this.markdown = buildPythonSandboxFileMarkdown(name, attachmentId)
  }
}

export class PythonSandboxArtifactSaveResult {
  images: PythonSandboxImageReference[] = []
  files: PythonSandboxFileReference[] = []
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

export function getPythonFileDefaultExtension(mimeType: string): string {
  if (mimeType === 'application/pdf') {
    return '.pdf'
  }
  if (mimeType === 'text/plain') {
    return '.txt'
  }
  if (mimeType === 'text/markdown') {
    return '.md'
  }
  if (mimeType === 'text/csv') {
    return '.csv'
  }
  if (mimeType === 'application/json') {
    return '.json'
  }
  if (mimeType === 'application/zip') {
    return '.zip'
  }
  if (mimeType === 'image/svg+xml') {
    return '.svg'
  }
  return ''
}

function getPythonArtifactLeafName(name: string): string {
  const normalized = name.trim().replace(/\\/g, '/')
  const slashIndex = normalized.lastIndexOf('/')
  return slashIndex >= 0 ? normalized.substring(slashIndex + 1) : normalized
}

function truncatePythonArtifactName(name: string, maximumLength: number): string {
  if (name.length <= maximumLength) {
    return name
  }
  const dotIndex = name.lastIndexOf('.')
  if (dotIndex <= 0 || name.length - dotIndex > 16) {
    return name.substring(0, maximumLength)
  }
  const extension = name.substring(dotIndex)
  return `${name.substring(0, maximumLength - extension.length)}${extension}`
}

export function sanitizePythonImageName(name: string, mimeType: string): string {
  const leafName = getPythonArtifactLeafName(name)
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

export function sanitizePythonFileName(name: string, mimeType: string): string {
  const leafName = getPythonArtifactLeafName(name)
  let safeName = leafName.replace(/[\u0000-\u001F\u007F\/:*?"<>|]/g, '_').trim()
  if (safeName === '' || safeName === '.' || safeName === '..') {
    safeName = 'python_file'
  }
  const defaultExtension = getPythonFileDefaultExtension(mimeType)
  const dotIndex = safeName.lastIndexOf('.')
  if (dotIndex <= 0 && defaultExtension !== '') {
    safeName += defaultExtension
  } else if (mimeType === 'application/pdf' && !safeName.toLowerCase().endsWith('.pdf')) {
    safeName = `${dotIndex > 0 ? safeName.substring(0, dotIndex) : safeName}.pdf`
  }
  return truncatePythonArtifactName(safeName, 120)
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

  async saveForCurrentSession(artifacts: PyodideOutputArtifact[]): Promise<PythonSandboxArtifactSaveResult> {
    const result = new PythonSandboxArtifactSaveResult()
    if (artifacts.length === 0) {
      return result
    }

    const sessionId = getAppUiState().activeChatSessionId.trim()
    if (sessionId === '') {
      result.warnings.push('Python 已生成文件，但当前没有活动会话，无法保存为模型可调取的附件')
      return result
    }

    const storage = getAttachmentStorageService()
    if (!storage.isReady()) {
      result.warnings.push('Python 已生成文件，但附件存储尚未初始化，无法保存')
      return result
    }

    let imageTotalBytes = 0
    let fileTotalBytes = 0
    for (let i = 0; i < artifacts.length; i++) {
      const artifact = artifacts[i]
      const isImage = artifact.kind === 'image'
      const decodedBytes = estimateBase64Bytes(artifact.data)
      if (artifact.data === '' || decodedBytes <= 0 || artifact.size <= 0) {
        result.warnings.push(`Python 产物 ${artifact.name} 数据无效，未保存`)
        artifact.data = ''
        continue
      }
      if (Math.abs(decodedBytes - artifact.size) > 2) {
        result.warnings.push(`Python 产物 ${artifact.name} 数据大小校验失败，未保存`)
        artifact.data = ''
        continue
      }

      if (isImage) {
        const extension = getPythonImageExtension(artifact.mimeType)
        if (extension === '') {
          result.warnings.push(`Python 图片 ${artifact.name} 格式无效，未保存`)
          artifact.data = ''
          continue
        }
        if (result.images.length >= PYTHON_MAX_OUTPUT_IMAGES ||
          decodedBytes > PYTHON_MAX_OUTPUT_IMAGE_BYTES || artifact.size > PYTHON_MAX_OUTPUT_IMAGE_BYTES) {
          result.warnings.push(`Python 图片 ${artifact.name} 超过数量或单图大小限制，未保存`)
          artifact.data = ''
          continue
        }
        if (imageTotalBytes + decodedBytes > PYTHON_MAX_OUTPUT_IMAGE_TOTAL_BYTES) {
          result.warnings.push(`Python 图片 ${artifact.name} 使图片总大小超过限制，未保存`)
          artifact.data = ''
          continue
        }
      } else {
        if (result.files.length >= PYTHON_MAX_OUTPUT_FILES || decodedBytes > PYTHON_MAX_OUTPUT_FILE_BYTES ||
          artifact.size > PYTHON_MAX_OUTPUT_FILE_BYTES) {
          result.warnings.push(`Python 文件 ${artifact.name} 超过数量或单文件大小限制，未保存`)
          artifact.data = ''
          continue
        }
        if (fileTotalBytes + decodedBytes > PYTHON_MAX_OUTPUT_FILE_TOTAL_BYTES) {
          result.warnings.push(`Python 文件 ${artifact.name} 使文件总大小超过限制，未保存`)
          artifact.data = ''
          continue
        }
      }

      this.sequence += 1
      const attachmentId = isImage
        ? `python_img_${Date.now()}_${this.sequence}`
        : `python_file_${Date.now()}_${this.sequence}`
      const safeName = isImage
        ? sanitizePythonImageName(artifact.name, artifact.mimeType)
        : sanitizePythonFileName(artifact.name, artifact.mimeType)
      const attachment = new MessageAttachment(
        attachmentId,
        isImage ? AttachmentType.IMAGE : AttachmentType.FILE,
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
        result.warnings.push(`Python 文件 ${safeName} 写入应用沙箱失败`)
        continue
      }

      attachment.filePath = filePath
      getDocumentAttachmentRegistryService().registerAttachments(sessionId, [attachment])
      if (isImage) {
        result.images.push(new PythonSandboxImageReference(
          attachment.id,
          attachment.name,
          attachment.mimeType,
          attachment.size
        ))
        imageTotalBytes += decodedBytes
      } else {
        result.files.push(new PythonSandboxFileReference(
          attachment.id,
          attachment.name,
          attachment.mimeType,
          attachment.size
        ))
        fileTotalBytes += decodedBytes
      }
    }
    return result
  }
}

export function getPythonSandboxArtifactService(): PythonSandboxArtifactService {
  return PythonSandboxArtifactService.getInstance()
}
