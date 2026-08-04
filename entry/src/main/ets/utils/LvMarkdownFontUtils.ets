import { text } from '@kit.ArkGraphics2D'

export const LV_MARKDOWN_CODE_FONT_FAMILY: string = 'XCubeJetBrainsMono'

let jetBrainsMonoRegistered: boolean = false

export function ensureLvMarkdownCodeFont(): string {
  if (jetBrainsMonoRegistered) {
    return LV_MARKDOWN_CODE_FONT_FAMILY
  }

  try {
    const fontCollection = text.FontCollection.getGlobalInstance()
    fontCollection.loadFontSync(
      LV_MARKDOWN_CODE_FONT_FAMILY,
      $rawfile('fonts/JetBrainsMono-Regular.ttf')
    )
    jetBrainsMonoRegistered = true
    return LV_MARKDOWN_CODE_FONT_FAMILY
  } catch (error) {
    console.error('LvMarkdownFontUtils',
      `Failed to register JetBrains Mono: ${JSON.stringify(error)}`)
    return 'monospace'
  }
}
