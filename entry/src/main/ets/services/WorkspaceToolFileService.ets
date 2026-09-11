import { AttachmentType, MessageAttachment } from '../models/ChatModels'
import { RegisteredDocumentAttachment } from './DocumentAttachmentRegistryService'
import { getPythonWorkspaceService, normalizePythonWorkspacePath } from './PythonWorkspaceService'
import { getWorkspaceMimeType } from '../utils/WorkspaceFileCodec'

// Called only after a real, enabled tool call. Never registers arbitrary filesystem
// paths or relies on whichever conversation happens to be visible during execution.
export async function withWorkspaceToolFile<T>(sessionId: string | undefined, rawPath: string,
  kind: string, read: (attachment: RegisteredDocumentAttachment) => Promise<T>): Promise<T> {
  if (sessionId === undefined || sessionId.trim() === '') {
    throw new Error('工作区读取必须绑定工具请求的会话')
  }
  const workspace = getPythonWorkspaceService()
  return await workspace.runSessionExclusive(sessionId, async (): Promise<T> => {
    workspace.assertSessionWritable(sessionId)
    const path = normalizePythonWorkspacePath(rawPath)
    const mime = getWorkspaceMimeType(path)
    const extension = path.substring(path.lastIndexOf('.')).toLowerCase()
    if ((kind === 'image' && !mime.startsWith('image/')) ||
      (kind === 'pdf' && mime !== 'application/pdf') ||
      ((kind === '.docx' || kind === '.xlsx') && extension !== kind)) {
      throw new Error('工作区文件类型与读取工具不匹配')
    }
    const filePath = workspace.getFilePath(sessionId, path)
    const info = workspace.listFiles(sessionId).find((file) => file.path === path)
    if (info === undefined) {
      throw new Error('工作区文件不存在')
    }
    const attachment = new MessageAttachment(
      `workspace:${path}:${info.modifiedAt}`, mime.startsWith('image/') ? AttachmentType.IMAGE : AttachmentType.FILE,
      path, filePath, mime, info.size)
    return await read(new RegisteredDocumentAttachment(sessionId, attachment))
  })
}
