/**
 * 分享消息卡片组件
 * 用于渲染分享图片的卡片样式
 */
import { ChatMessage, MessageRole, MessageAttachment, AttachmentType } from '../models/ChatModels'
import { getPresetProviderById } from '../config/PresetProviders'
import { getCachedModelIconPath, buildIconResourcePath, resolveShareModelIdentity } from '../utils/ProviderIconUtils'
import { ChatMarkdownHybridRenderer } from './ChatMarkdownHybridRenderer'
import { getAppUiState } from '../state/AppUiState'

@ComponentV2
export struct ShareMessageCard {
  @Param messages: ChatMessage[] = []
  @Param appName: string = 'ChatCube'
  @Param currentModelId: string = ''
  @Param iconRenderVersion: number = 0
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themeUserBubble(): string {
    return getAppUiState().themeUserBubble
  }
  private get themeUserBubbleText(): string {
    return getAppUiState().themeUserBubbleText
  }
  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  // 获取卡片背景色
  private getCardBackground(): ResourceColor {
    return $r('app.color.surface')
  }

  // 获取主文字颜色
  private getPrimaryTextColor(): ResourceColor {
    return $r('app.color.text_primary')
  }

  // 获取次要文字颜色
  private getSecondaryTextColor(): ResourceColor {
    return $r('app.color.text_secondary')
  }

  // 获取分割线颜色
  private getDividerColor(): ResourceColor {
    return $r('app.color.divider')
  }

  // 获取AI头像背景色
  private getAiAvatarBgColor(): ResourceColor {
    return this.themeAiBubble
  }

  // 获取 AI 内容容器背景色
  private getAiContentBgColor(): ResourceColor {
    return this.themeAiBubble
  }

  // 获取用户消息气泡背景色（使用主题色）
  private getUserBubbleBgColor(): string {
    return this.themeUserBubble
  }

  // 获取用户消息文字颜色
  private getUserBubbleTextColor(): string {
    return this.themeUserBubbleText
  }

  // 分享长图只允许使用本地已缓存图标，避免离屏渲染时回退到网络资源。
  private getMessageModelIconPath(message: ChatMessage): string {
    const id = resolveShareModelIdentity(message.modelId, this.currentModelId, message.modelName)
    if (id === '' || id === undefined) {
      return ''
    }
    return getCachedModelIconPath(id)
  }

  private resolveModelBrandKey(message: ChatMessage): string {
    const id = resolveShareModelIdentity(message.modelId, this.currentModelId, message.modelName)
    const lower = id.toLowerCase()

    if (lower.includes('gpt') || lower.includes('o1') || lower.includes('o3') || lower.includes('o4') ||
      lower.includes('chatgpt')) {
      return 'openai'
    }
    if (lower.includes('claude')) {
      return 'anthropic'
    }
    if (lower.includes('gemini')) {
      return 'gemini'
    }
    if (lower.includes('deepseek')) {
      return 'deepseek'
    }
    if (lower.includes('qwen') || lower.includes('qwq') || lower.includes('qvq')) {
      return 'qwen'
    }
    if (lower.includes('glm') || lower.includes('zhipu') || lower.includes('bigmodel') || lower.includes('cogview') ||
      lower.includes('codegeex') || lower.includes('charglm') || lower.includes('characterglm')) {
      return 'zhipu'
    }
    if (lower.includes('grok')) {
      return 'grok'
    }
    if (lower.includes('moonshot') || lower.includes('kimi')) {
      return 'moonshotai'
    }
    if (lower.includes('minimax') || lower.includes('abab')) {
      return 'minimax'
    }
    return ''
  }

  private getModelBadgeText(message: ChatMessage): string {
    const preset = getPresetProviderById(this.resolveModelBrandKey(message))
    if (preset !== null && preset.textIcon !== '') {
      return preset.textIcon
    }
    const modelName = message.modelName.trim()
    if (modelName !== '') {
      return modelName.substring(0, 1).toUpperCase()
    }
    return 'AI'
  }

  private getModelBadgeBgColor(message: ChatMessage): string {
    const preset = getPresetProviderById(this.resolveModelBrandKey(message))
    if (preset !== null && preset.textIconBgColor !== '') {
      return preset.textIconBgColor
    }
    return this.themePrimary
  }

  // 获取消息模型图标资源路径（空字符串表示无可用图标）
  private getMessageModelIconResourcePath(message: ChatMessage): string {
    const iconPath = this.getMessageModelIconPath(message)
    if (iconPath === '') {
      return ''
    }
    return buildIconResourcePath(iconPath)
  }

  build() {
    // 外层底板容器：带圆角和裁剪，确保截图时圆角生效
    Column() {
      // 内层卡片内容
      Column() {
        // 卡片头部：应用名称和时间
        Row() {
          // 应用图标
          Image($r('app.media.app_icon'))
            .width(24)
            .height(24)
            .borderRadius(6)
            .syncLoad(true)

          Text(this.appName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getPrimaryTextColor())
            .margin({ left: 8 })

          Blank()

          Text(this.formatDateTime(Date.now()))
            .fontSize(12)
            .fontColor(this.getSecondaryTextColor())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

        Divider()
          .color(this.getDividerColor())
          .margin({ left: 16, right: 16 })

        // 消息列表
        Column() {
          ForEach(this.messages, (message: ChatMessage, index: number) => {
            this.MessageItem(message, index)
          }, (message: ChatMessage) => message.id)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
      .width('100%')
      .backgroundColor(this.getCardBackground())
    }
    .width('100%')
    // 底板背景色：使用轻微的灰色作为分享图片的背景
    .backgroundColor(this.isDarkMode ? '#1A1A1A' : '#F5F5F5')
    .borderRadius(16)
    .clip(true) // 关键：启用裁剪确保圆角生效
    .shadow({
      radius: 20,
      color: this.isDarkMode ? 'rgba(0, 0, 0, 0.3)' : 'rgba(0, 0, 0, 0.1)',
      offsetX: 0,
      offsetY: 4
    })
  }

  @Builder
  MessageItem(message: ChatMessage, index: number) {
    Column() {
      if (message.role === MessageRole.USER) {
        // 用户消息
        Row() {
          Blank()

          Column() {
            // 附件展示
            if (message.hasAttachments()) {
              this.ShareAttachments(message, true)
            }

            // 文本内容
            if (message.content.length > 0) {
              Text(message.content)
                .fontSize(15)
                .fontColor(this.getUserBubbleTextColor())
                .lineHeight(21)
                .padding(message.hasAttachments() ? { left: 8, right: 8 } : { left: 0, right: 0 })
            }
          }
          .padding(message.hasAttachments() ? { left: 8, right: 8, top: 8, bottom: 8 } : { left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor(this.getUserBubbleBgColor())
          .borderRadius({
            topLeft: 20,
            topRight: 20,
            bottomLeft: 20,
            bottomRight: 6
          })
          .border({ width: 0.5, color: 'rgba(255, 255, 255, 0.15)' })
          .constraintSize({ maxWidth: '75%' })
        }
        .width('100%')
        .margin({ bottom: 12 })
      } else {
        // AI 消息
        Row() {
          // 模型图标
          Column() {
            if (this.getMessageModelIconResourcePath(message) !== '') {
              Image(this.getMessageModelIconResourcePath(message))
                .width(18)
                .height(18)
                .objectFit(ImageFit.Contain)
                .syncLoad(true)
                .borderRadius(9)
            } else {
              Text(this.getModelBadgeText(message))
                .fontSize(12)
                .fontColor(Color.White)
                .fontWeight(FontWeight.Bold)
            }
          }
          .width(30)
          .height(30)
          .borderRadius(8)
          .backgroundColor(this.getMessageModelIconResourcePath(message) !== '' ?
            $r('app.color.model_icon_bg') : this.getModelBadgeBgColor(message))
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .flexShrink(0)

          Column() {
            Column() {
              // 附件展示（AI 生成的图片等）
              if (message.hasAttachments()) {
                this.ShareAttachments(message, false)
              }

              // 消息内容 - 使用 Markdown 渲染（紧凑样式）
              if (message.content.length > 0) {
                ChatMarkdownHybridRenderer({
                  content: message.content,
                  isInputEnded: true,
                  incrementalAnalysis: false,
                  useCangjieComponent: true,
                  chatFontSize: 14,
                  themeRenderKey: message.id,
                  showCodeFullScreen: false
                })
                  .width('100%')
                  .backgroundColor(Color.Transparent)
              }
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 10 })
            .backgroundColor(this.getAiContentBgColor())
            .borderRadius(16)
            .border({ width: 0.5, color: $r('app.color.bubble_border') })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 10 })
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .margin({ bottom: 12 })
      }
    }
    .width('100%')
  }


  // 分享卡片中的附件展示（无交互手势，纯静态展示）
  @Builder
  ShareAttachments(message: ChatMessage, isUserMessage: boolean) {
    Column() {
      ForEach(message.attachments, (attachment: MessageAttachment) => {
        if (attachment.type === AttachmentType.IMAGE) {
          // 图片附件：直接显示图片
          if (attachment.filePath !== '') {
            Image('file://' + attachment.filePath)
              .constraintSize({
                maxWidth: 180,
                maxHeight: 180
              })
              .objectFit(ImageFit.Contain)
              .borderRadius(8)
              .margin({ bottom: 4 })
              .syncLoad(true)
          } else if (attachment.base64Data !== '') {
            Image(`data:${attachment.mimeType};base64,${attachment.base64Data}`)
              .constraintSize({
                maxWidth: 180,
                maxHeight: 180
              })
              .objectFit(ImageFit.Contain)
              .borderRadius(8)
              .margin({ bottom: 4 })
              .syncLoad(true)
          }
        } else {
          // 文件附件：图标+文件名
          Row() {
            SymbolGlyph($r('sys.symbol.doc'))
              .fontSize(18)
              .fontColor([isUserMessage ? 'rgba(255,255,255,0.8)' : $r('app.color.text_tertiary')])

            Text(attachment.name)
              .fontSize(12)
              .fontColor(isUserMessage ? 'rgba(255,255,255,0.9)' : $r('app.color.text_secondary'))
              .margin({ left: 6 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .padding(8)
          .backgroundColor(isUserMessage ? 'rgba(255,255,255,0.15)' : $r('app.color.divider'))
          .borderRadius(8)
          .margin({ bottom: 4 })
        }
      }, (attachment: MessageAttachment) => attachment.id || attachment.filePath)
    }
    .alignItems(isUserMessage ? HorizontalAlign.End : HorizontalAlign.Start)
  }

  // 格式化日期时间
  private formatDateTime(timestamp: number): string {
    const date = new Date(timestamp)
    const year = date.getFullYear()
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    const hours = date.getHours().toString().padStart(2, '0')
    const minutes = date.getMinutes().toString().padStart(2, '0')
    return `${year}/${month}/${day} ${hours}:${minutes}`
  }
}

// 用于截图的 Builder
@Builder
export function ShareMessageCardBuilder(messages: ChatMessage[], appName: string) {
  ShareMessageCard({
    messages: messages,
    appName: appName
  })
}

