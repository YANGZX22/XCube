import { describe, expect, it } from '@ohos/hypium'
import {
  buildLobeIconUrl,
  LOBE_ICONS_PACKAGE_VERSION,
  resolveLobeModelIconFileName,
  resolveLobeModelIconUrl,
  resolveLobeProviderIconFileName
} from '../main/ets/utils/LobeIconResolver'

export default function lobeIconResolverTest() {
  describe('lobeIconResolverTest', () => {
    it('matches_major_model_families', 0, () => {
      expect(resolveLobeModelIconFileName('gpt-5.2')).assertEqual('openai')
      expect(resolveLobeModelIconFileName('claude-opus-4-7')).assertEqual('claude-color')
      expect(resolveLobeModelIconFileName('deepseek-ai/deepseek-v4')).assertEqual('deepseek-color')
      expect(resolveLobeModelIconFileName('Qwen/Qwen3-235B')).assertEqual('qwen-color')
      expect(resolveLobeModelIconFileName('moonshot-v1-128k')).assertEqual('moonshot')
    })

    it('keeps_lobehub_rule_priority', 0, () => {
      expect(resolveLobeModelIconFileName('glm-4.6v')).assertEqual('glmv-color')
      expect(resolveLobeModelIconFileName('glm-4.7')).assertEqual('zai')
      expect(resolveLobeModelIconFileName('gemini-3-pro-image-preview')).assertEqual('nanobanana-color')
    })

    it('falls_back_to_provider_for_unknown_models', 0, () => {
      expect(resolveLobeModelIconFileName('company-model-v1', 'siliconflow')).assertEqual('siliconcloud-color')
      expect(resolveLobeModelIconFileName('company-model-v1', 'ollama')).assertEqual('ollama')
      expect(resolveLobeModelIconFileName('company-model-v1', 'aiping')).assertEqual('')
    })

    it('builds_version_pinned_static_svg_urls', 0, () => {
      expect(LOBE_ICONS_PACKAGE_VERSION).assertEqual('1.94.0')
      expect(buildLobeIconUrl('openai')).assertEqual(
        'https://registry.npmmirror.com/@lobehub/icons-static-svg/1.94.0/files/icons/openai.svg'
      )
      expect(resolveLobeModelIconUrl('gemini-2.5-pro')).assertContain('/gemini-color.svg')
      expect(resolveLobeProviderIconFileName('zhipu')).assertEqual('zhipu-color')
    })
  })
}

