import { MessageAttachment } from '../models/ChatModels'

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
      if (!this.isPdfAttachment(attachment) || attachment.filePath.trim() === '') {
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

  private isPdfAttachment(attachment: MessageAttachment): boolean {
    const mimeType = attachment.mimeType.toLowerCase()
    const name = attachment.name.toLowerCase()
    return mimeType === 'application/pdf' || name.endsWith('.pdf')
  }
}

export function getDocumentAttachmentRegistryService(): DocumentAttachmentRegistryService {
  return DocumentAttachmentRegistryService.getInstance()
}
