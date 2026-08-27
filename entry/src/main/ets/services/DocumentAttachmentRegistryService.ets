import { MessageAttachment } from '../models/ChatModels'
import { isPythonSandboxFileAttachmentId } from './PythonSandboxArtifactLink'

export function isDocxDocumentAttachment(attachment: MessageAttachment): boolean {
  const mimeType = attachment.mimeType.toLowerCase()
  const name = attachment.name.toLowerCase()
  return mimeType === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
    name.endsWith('.docx')
}

export function isXlsxDocumentAttachment(attachment: MessageAttachment): boolean {
  const mimeType = attachment.mimeType.toLowerCase()
  const name = attachment.name.toLowerCase()
  return mimeType === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
    name.endsWith('.xlsx')
}

export function isOfficeOpenXmlDocumentAttachment(attachment: MessageAttachment): boolean {
  return isDocxDocumentAttachment(attachment) || isXlsxDocumentAttachment(attachment)
}

export class RegisteredDocumentAttachment {
  sessionId: string = ''
  attachmentId: string = ''
  name: string = ''
  filePath: string = ''
  mimeType: string = ''
  size: number = 0

  constructor(sessionId: string, attachment: MessageAttachment) {
    this.sessionId = sessionId
    this.attachmentId = attachment.id
    this.name = attachment.name
    this.filePath = attachment.filePath
    this.mimeType = attachment.mimeType
    this.size = attachment.size
  }
}

export class DocumentAttachmentRegistryService {
  private static instance: DocumentAttachmentRegistryService | null = null
  private documentsBySession: Map<string, Map<string, RegisteredDocumentAttachment>> = new Map()

  static getInstance(): DocumentAttachmentRegistryService {
    if (DocumentAttachmentRegistryService.instance === null) {
      DocumentAttachmentRegistryService.instance = new DocumentAttachmentRegistryService()
    }
    return DocumentAttachmentRegistryService.instance
  }

  registerAttachments(sessionId: string, attachments: MessageAttachment[]): void {
    const normalizedSessionId = sessionId.trim()
    if (normalizedSessionId === '') {
      return
    }
    let sessionDocuments = this.documentsBySession.get(normalizedSessionId)
    if (sessionDocuments === undefined) {
      sessionDocuments = new Map()
      this.documentsBySession.set(normalizedSessionId, sessionDocuments)
    }
    for (let i = 0; i < attachments.length; i++) {
      const attachment = attachments[i]
      if ((!this.isPdfAttachment(attachment) && !this.isImageAttachment(attachment) &&
        !isOfficeOpenXmlDocumentAttachment(attachment) &&
        !isPythonSandboxFileAttachmentId(attachment.id)) ||
        attachment.filePath.trim() === '') {
        continue
      }
      sessionDocuments.set(attachment.id, new RegisteredDocumentAttachment(normalizedSessionId, attachment))
    }
  }

  getAttachment(sessionId: string, attachmentId: string): RegisteredDocumentAttachment | null {
    const sessionDocuments = this.documentsBySession.get(sessionId.trim())
    if (sessionDocuments === undefined) {
      return null
    }
    return sessionDocuments.get(attachmentId.trim()) ?? null
  }

  listAttachments(sessionId: string): RegisteredDocumentAttachment[] {
    const sessionDocuments = this.documentsBySession.get(sessionId.trim())
    if (sessionDocuments === undefined) {
      return []
    }
    const documents: RegisteredDocumentAttachment[] = []
    sessionDocuments.forEach((value: RegisteredDocumentAttachment): void => {
      documents.push(value)
    })
    return documents
  }

  unregisterAttachment(sessionId: string, attachmentId: string): void {
    const normalizedSessionId = sessionId.trim()
    const normalizedAttachmentId = attachmentId.trim()
    if (normalizedSessionId === '' || normalizedAttachmentId === '') {
      return
    }
    const sessionDocuments = this.documentsBySession.get(normalizedSessionId)
    if (sessionDocuments === undefined) {
      return
    }
    sessionDocuments.delete(normalizedAttachmentId)
    if (sessionDocuments.size === 0) {
      this.documentsBySession.delete(normalizedSessionId)
    }
  }

  clearSession(sessionId: string): void {
    const normalizedSessionId = sessionId.trim()
    if (normalizedSessionId !== '') {
      this.documentsBySession.delete(normalizedSessionId)
    }
  }

  listAllFilePaths(): string[] {
    const filePaths: string[] = []
    this.documentsBySession.forEach((sessionDocuments: Map<string, RegisteredDocumentAttachment>): void => {
      sessionDocuments.forEach((attachment: RegisteredDocumentAttachment): void => {
        const filePath = attachment.filePath.trim()
        if (filePath !== '' && filePaths.indexOf(filePath) < 0) {
          filePaths.push(filePath)
        }
      })
    })
    return filePaths
  }

  private isPdfAttachment(attachment: MessageAttachment): boolean {
    const mimeType = attachment.mimeType.toLowerCase()
    const name = attachment.name.toLowerCase()
    return mimeType === 'application/pdf' || name.endsWith('.pdf')
  }

  private isImageAttachment(attachment: MessageAttachment): boolean {
    const mimeType = attachment.mimeType.toLowerCase()
    const name = attachment.name.toLowerCase()
    return mimeType.startsWith('image/') || name.endsWith('.jpg') || name.endsWith('.jpeg') ||
      name.endsWith('.png') || name.endsWith('.webp') || name.endsWith('.bmp') || name.endsWith('.gif')
  }

}

export function getDocumentAttachmentRegistryService(): DocumentAttachmentRegistryService {
  return DocumentAttachmentRegistryService.getInstance()
}
