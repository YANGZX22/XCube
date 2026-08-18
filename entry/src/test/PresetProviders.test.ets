import { describe, expect, it } from '@ohos/hypium'
import { ApiStyle, OpenAITransport } from '../main/ets/models/ChatModels'
import {
  getAutoInitializedPresetProviders,
  getPresetProviderById,
  PresetProviderConfig
} from '../main/ets/config/PresetProviders'

export default function presetProvidersTest() {
  describe('presetProvidersTest', () => {
    it('includes_official_openai_compatible_providers', 0, () => {
      const expectedProviders = new Map<string, string>([
        ['groq', 'https://api.groq.com/openai/v1'],
        ['together', 'https://api.together.ai/v1'],
        ['nvidia', 'https://integrate.api.nvidia.com/v1']
      ])

      expectedProviders.forEach((baseUrl: string, providerId: string) => {
        const provider = getPresetProviderById(providerId)
        expect(provider !== null).assertTrue()
        if (provider !== null) {
          expect(provider.baseUrl).assertEqual(baseUrl)
          expect(provider.apiStyle).assertEqual(ApiStyle.OPENAI)
          expect(provider.openaiTransport).assertEqual(OpenAITransport.CHAT_COMPLETIONS)
        }
      })
    })

    it('auto_initializes_new_providers_without_legacy_aiping', 0, () => {
      const providers: PresetProviderConfig[] = getAutoInitializedPresetProviders()
      const ids = new Set<string>()
      for (let i = 0; i < providers.length; i++) {
        ids.add(providers[i].id)
      }

      expect(ids.has('groq')).assertTrue()
      expect(ids.has('together')).assertTrue()
      expect(ids.has('nvidia')).assertTrue()
      expect(ids.has('aiping')).assertFalse()
      expect(ids.size).assertEqual(providers.length)
    })
  })
}
