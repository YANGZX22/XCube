/**
 * 分享服务
 * 提供消息分享功能：图片分享、Markdown分享、纯文本分享
 */
import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { fileUri } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { ChatMessage, MessageRole } from '../models/ChatModels'

// 分享模式枚举
export enum ShareMode {
  IMAGE = 'image',      // 图片分享（卡片风格）
  MARKDOWN = 'markdown', // Markdown 格式
  TEXT = 'text'         // 纯文本格式
}

// 分享结果
export interface ShareResult {
  success: boolean
  errorMessage: string
}

export class ShareService {
  private context: common.UIAbilityContext | null = null
  private readonly snapshotRetryCount: number = 5
  private readonly snapshotRetryDelayMs: number = 200
  private readonly snapshotScale: number = 1
  private readonly snapshotBuilderDelayMs: number = 600

  // 初始化服务
  init(context: common.UIAbilityContext): void {
    this.context = context
  }

  // 将消息列表转换为 Markdown 格式
  convertToMarkdown(messages: ChatMessage[]): string {
    const lines: string[] = []
    lines.push('# 对话记录\n')
    lines.push(`> 导出时间: ${this.formatDateTime(Date.now())}\n`)
    lines.push('---\n')

    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i]
      const roleLabel = msg.role === MessageRole.USER ? '👤 **用户**' : '🤖 **AI**'
      const time = this.formatTime(msg.timestamp)

      lines.push(`### ${roleLabel} · ${time}\n`)

      // 添加消息内容
      if (msg.content.length > 0) {
        lines.push(msg.content)
        lines.push('')
      }

      if (msg.reasoningContent.trim().length > 0) {
        lines.push('<details>')
        lines.push('<summary>💭 思考过程</summary>\n')
        lines.push(msg.reasoningContent)
        lines.push('</details>\n')
      }

      lines.push('---\n')
    }

    return lines.join('\n')
  }

  // 将消息列表转换为纯文本格式
  convertToPlainText(messages: ChatMessage[]): string {
    const lines: string[] = []
    lines.push('=== 对话记录 ===')
    lines.push(`导出时间: ${this.formatDateTime(Date.now())}`)
    lines.push('')

    for (let i = 0; i < messages.length; i++) {
      const msg = messages[i]
      const roleLabel = msg.role === MessageRole.USER ? '[用户]' : '[AI]'
      const time = this.formatTime(msg.timestamp)

      lines.push(`${roleLabel} ${time}`)
      if (msg.content.length > 0) {
        lines.push(msg.content)
      }

      if (msg.reasoningContent.trim().length > 0) {
        if (msg.content.length > 0) {
          lines.push('')
        }
        lines.push('[思考过程]')
        lines.push(msg.reasoningContent)
      }

      lines.push('')
      lines.push('---')
      lines.push('')
    }

    return lines.join('\n')
  }

  // 将 Canvas 文稿转换为 Markdown。标题单独存储，导出时补成一级标题。
  convertDocumentToMarkdown(title: string, content: string): string {
    const normalizedTitle = title.trim()
    if (normalizedTitle === '') {
      return content
    }
    const titleLine = `# ${normalizedTitle}`
    const normalizedContent = content.trim()
    if (normalizedContent === titleLine || normalizedContent.startsWith(`${titleLine}\n`)) {
      return content
    }
    if (normalizedContent === '') {
      return titleLine
    }
    return `${titleLine}\n\n${content}`
  }

  // 文本分享保留 Canvas 原文，仅在首部附上独立的文稿标题。
  convertDocumentToPlainText(title: string, content: string): string {
    const normalizedTitle = title.trim()
    if (normalizedTitle === '') {
      return content
    }
    if (content.trim() === '') {
      return normalizedTitle
    }
    return `${normalizedTitle}\n\n${content}`
  }

  // 分享文本内容
  async shareText(content: string, title: string = '分享对话'): Promise<ShareResult> {
    if (this.context === null) {
      console.error('ShareService', '[shareText] 服务未初始化')
      return { success: false, errorMessage: '服务未初始化' }
    }

    try {
      console.info('ShareService', `[shareText] 开始分享文本，内容长度: ${content.length}`)
      const shareData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: content,
        title: title
      })

      const controller = new systemShare.ShareController(shareData)
      console.info('ShareService', '[shareText] 打开分享面板')
      await controller.show(this.context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      })

      console.info('ShareService', '[shareText] 分享面板已关闭')
      return { success: true, errorMessage: '' }
    } catch (error) {
      console.error('ShareService', `[shareText] 分享文本失败: ${JSON.stringify(error)}`)
      return { success: false, errorMessage: `分享失败: ${error}` }
    }
  }

  // 分享图片
  async shareImage(imagePath: string, title: string = '分享对话'): Promise<ShareResult> {
    if (this.context === null) {
      console.error('ShareService', '[shareImage] 服务未初始化')
      return { success: false, errorMessage: '服务未初始化' }
    }

    try {
      console.info('ShareService', `[shareImage] 开始分享图片: ${imagePath}`)
      const uri = fileUri.getUriFromPath(imagePath)
      console.info('ShareService', `[shareImage] 文件URI: ${uri}`)

      const shareData = new systemShare.SharedData({
        utd: utd.UniformDataType.PNG,
        uri: uri,
        title: title
      })

      const controller = new systemShare.ShareController(shareData)
      console.info('ShareService', '[shareImage] 打开分享面板')
      await controller.show(this.context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      })

      console.info('ShareService', '[shareImage] 分享面板已关闭')
      return { success: true, errorMessage: '' }
    } catch (error) {
      console.error('ShareService', `[shareImage] 分享图片失败: ${JSON.stringify(error)}`)
      return { success: false, errorMessage: `分享失败: ${error}` }
    }
  }

  // 通过离屏 Builder 渲染长图并保存，避免受当前页面滚动区域和父布局裁剪影响。
  async captureBuilderAsImage(builder: CustomBuilder, uiContext: UIContext,
    scale?: number): Promise<string> {
    let pixelMap: image.PixelMap | null = null
    const effectiveScale = scale ?? this.snapshotScale
    try {
      const snapshot = uiContext.getComponentSnapshot()
      let lastSnapshotError: Object | null = null

      for (let attempt = 0; attempt < this.snapshotRetryCount; attempt++) {
        try {
          pixelMap = await snapshot.createFromBuilder(
            builder,
            this.snapshotBuilderDelayMs,
            true,
            {
              scale: effectiveScale,
              waitUntilRenderFinished: true
            })
          break
        } catch (error) {
          lastSnapshotError = error
          console.error('ShareService',
            `[captureBuilderAsImage] snapshot attempt ${(attempt + 1).toString()} failed: ${this.describeError(error)}`)
          if (attempt < this.snapshotRetryCount - 1) {
            await this.sleep(this.snapshotRetryDelayMs)
          }
        }
      }

      if (pixelMap === null && this.isImageNotReadyError(lastSnapshotError)) {
        console.warn('ShareService',
          '[captureBuilderAsImage] falling back to snapshot without image-ready check')
        try {
          pixelMap = await snapshot.createFromBuilder(
            builder,
            this.snapshotBuilderDelayMs,
            false,
            {
              scale: effectiveScale,
              waitUntilRenderFinished: true
            })
        } catch (error) {
          lastSnapshotError = error
          console.error('ShareService',
            `[captureBuilderAsImage] fallback snapshot failed: ${this.describeError(error)}`)
        }
      }

      if (pixelMap === null) {
        throw new Error(`snapshot.createFromBuilder failed: ${this.describeError(lastSnapshotError)}`)
      }
      return await this.writePixelMapToImageFile(pixelMap)
    } catch (e) {
      const errorMsg = `截图失败: ${this.describeError(e)}`
      console.error('ShareService', errorMsg)
      throw new Error(errorMsg)
    } finally {
      if (pixelMap !== null) {
        pixelMap.release()
      }
    }
  }

  private async writePixelMapToImageFile(pixelMap: image.PixelMap): Promise<string> {
    let packer: image.ImagePacker | null = null
    try {
      packer = image.createImagePacker()
      const packOpts: image.PackingOption = {
        format: 'image/png',
        quality: 100
      }
      const arrayBuffer = await packer.packToData(pixelMap, packOpts)

      const fileName = `share_${Date.now()}.png`
      const imageDir = this.context?.cacheDir ?? this.context?.tempDir ?? ''
      const filePath = `${imageDir}/${fileName}`

      if (imageDir === '') {
        throw new Error('share image directory unavailable')
      }

      try {
        fs.accessSync(imageDir)
      } catch (_error) {
        fs.mkdirSync(imageDir, true)
      }

      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY)
      fs.writeSync(file.fd, arrayBuffer)
      fs.closeSync(file)
      return filePath
    } finally {
      if (packer !== null) {
        packer.release()
      }
    }
  }

  private async sleep(delayMs: number): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(() => resolve(), delayMs)
    })
  }

  private describeError(error: Object | null): string {
    if (error === null) {
      return 'unknown error'
    }
    const text = `${error}`
    if (text !== '' && text !== '[object Object]') {
      return text
    }
    const json = JSON.stringify(error)
    if (json !== '' && json !== '{}') {
      return json
    }
    return 'unknown error'
  }

  private isImageNotReadyError(error: Object | null): boolean {
    return this.describeError(error).indexOf('160001') >= 0
  }

  // 格式化时间
  private formatTime(timestamp: number): string {
    const date = new Date(timestamp)
    const hours = date.getHours()
    const minutes = date.getMinutes().toString().padStart(2, '0')
    const period = hours >= 12 ? 'PM' : 'AM'
    const displayHours = hours % 12 || 12
    return `${displayHours}:${minutes} ${period}`
  }

  // 格式化日期时间
  private formatDateTime(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear()
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    const hours = date.getHours().toString().padStart(2, '0')
    const minutes = date.getMinutes().toString().padStart(2, '0')
    return `${year}-${month}-${day} ${hours}:${minutes}`
  }
}

// 单例实例
let shareServiceInstance: ShareService | null = null

export function getShareService(): ShareService {
  if (shareServiceInstance === null) {
    shareServiceInstance = new ShareService()
  }
  return shareServiceInstance
}
