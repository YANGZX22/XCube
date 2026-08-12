/**
 * LobeHub Icons adapter for ArkUI.
 *
 * @lobehub/icons is a React component package, so HarmonyOS consumes the
 * framework-neutral SVG assets published by the same project. Model matching
 * follows the ordered ModelIcon rules from @lobehub/icons 5.15.0 (MIT).
 */

export const LOBE_ICONS_PACKAGE_VERSION: string = '1.94.0'
export const LOBE_ICONS_CDN_BASE_URL: string =
  `https://registry.npmmirror.com/@lobehub/icons-static-svg/${LOBE_ICONS_PACKAGE_VERSION}/files/icons`

class LobeIconMapping {
  fileName: string
  keywords: string[]

  constructor(fileName: string, keywords: string[]) {
    this.fileName = fileName
    this.keywords = keywords
  }
}

// Keep this list ordered. The first matching rule is the behavior of LobeHub's ModelIcon.
const MODEL_ICON_MAPPINGS: LobeIconMapping[] = [
  new LobeIconMapping('openai', ['gpt-3']),
  new LobeIconMapping('openai', ['gpt-4']),
  new LobeIconMapping('openai', ['gpt-5']),
  new LobeIconMapping('sora-color', ['sora']),
  new LobeIconMapping('openai', ['gpt-oss']),
  new LobeIconMapping('openai', ['o1-', '^o1', '/o1', 'o3-', '^o3', '/o3', 'o4-', '^o4', '/o4']),
  new LobeIconMapping('dalle-color', ['dalle', 'dall-e']),
  new LobeIconMapping('openai', [
    'text-embedding-', 'tts-', 'whisper-', 'codex', 'davinci', 'babbage', 'omni-moderation',
    'text-moderation', 'text-adb', 'text-ada', 'computer-use'
  ]),
  new LobeIconMapping('openai', ['^gpt-', '/gpt-', 'openai']),
  new LobeIconMapping('glmv-color', ['^glm-(.*)v', '/glm-(.*)v', '-glm-(.*)v']),
  new LobeIconMapping('zai', ['^glm-5', '/glm-5', '/glm5', '-glm-4', '^glm-4', '/glm-4', '/glm4', '-glm-5']),
  new LobeIconMapping('chatglm-color', ['^glm-', '/glm-', 'chatglm', '-glm-']),
  new LobeIconMapping('codegeex-color', ['^codegeex', '/codegeex']),
  new LobeIconMapping('claude-color', ['claude']),
  new LobeIconMapping('anthropic', ['anthropic']),
  new LobeIconMapping('aws-color', ['titan']),
  new LobeIconMapping('fireworks-color', ['accounts/fireworks/models/fire']),
  new LobeIconMapping('internlm-color', ['internlm', 'internvl']),
  new LobeIconMapping('nousresearch', ['deephermes', 'hermes', 'genstruct', 'minos']),
  new LobeIconMapping('nvidia-color', ['nemotron', 'openreasoning', 'nemoretriever', 'neva-', 'nv-']),
  new LobeIconMapping('meta-color', ['llama', '/l3']),
  new LobeIconMapping('llava-color', ['llava']),
  new LobeIconMapping('nanobanana-color', [
    'gemini-3.1-flash-image-preview', 'gemini-3-pro-image-preview',
    'gemini-\\d+(?:\\.\\d+)?-(?:flash(?:-lite)?|pro)-image(?:-preview)?(?::|$)',
    'nanobanana', 'nano-banana'
  ]),
  new LobeIconMapping('gemini-color', ['gemini']),
  new LobeIconMapping('deepmind-color', ['^imagen-', '/imagen-', '^imagen\\d/', '/imagen\\d']),
  new LobeIconMapping('gemma-color', ['gemma']),
  new LobeIconMapping('moonshot', ['kimi', 'moonshot']),
  new LobeIconMapping('qiniu-color', ['qiniu']),
  new LobeIconMapping('qwen-color', ['qwen', 'qwq', 'qvq', 'wanx', 'wan\\d/', 'wan\\d\\.\\d-', 'tongyi', 'gte-rerank']),
  new LobeIconMapping('minimax-color', ['minimax', 'abab', '^image-']),
  new LobeIconMapping('mistral-color', [
    'mistral', 'mixtral', 'codestral', 'mathstral', '/mn-', 'pixtral', 'ministral', 'magistral',
    'devstral', 'voxtral'
  ]),
  new LobeIconMapping('perplexity-color', ['pplx', 'sonar']),
  new LobeIconMapping('yi-color', ['^yi-', '/yi-', '-yi-']),
  new LobeIconMapping('openrouter-color', ['^openrouter']),
  new LobeIconMapping('relace', ['^relace-', '/relace-']),
  new LobeIconMapping('arcee-color', [
    '^trinity-', '/trinity-', 'afm-4.5b', 'caller-large', 'spotlight', 'maestro-reasoning',
    'virtuoso-medium-v2', 'virtuoso-large', 'coder-large', 'arcee-blitz'
  ]),
  new LobeIconMapping('essentialai-color', ['^rnj-', '/rnj-']),
  new LobeIconMapping('deepcogito-color', ['^deepcogito-', '/deepcogito-', '^cogito-', '/cogito-']),
  new LobeIconMapping('morph-color', ['^morph-', '/morph-']),
  new LobeIconMapping('ai2-color', ['^olmo-', '/olmo-']),
  new LobeIconMapping('inception', ['^mercury', '/mercury']),
  new LobeIconMapping('openchat-color', ['^openchat']),
  new LobeIconMapping('aya-color', ['aya']),
  new LobeIconMapping('cohere-color', ['command']),
  new LobeIconMapping('dbrx-color', ['dbrx']),
  new LobeIconMapping('stepfun-color', ['step']),
  new LobeIconMapping('aimass-color', ['taichu']),
  new LobeIconMapping('ai360-color', ['360gpt', '360zhinao']),
  new LobeIconMapping('baichuan-color', ['baichuan']),
  new LobeIconMapping('rwkv-color', ['rwkv', '/eagle-']),
  new LobeIconMapping('wenxin-color', ['ernie', 'irag']),
  new LobeIconMapping('jina', ['^jina', '/jina']),
  new LobeIconMapping('jimeng-color', ['^jimeng-', '/jimeng-', 'seedream', 'seededit', 'seedance-']),
  new LobeIconMapping('doubao-color', ['^ep-', 'doubao-']),
  new LobeIconMapping('kling-color', ['^kling', 'kling-', 'klingai']),
  new LobeIconMapping('hunyuan-color', ['hunyuan']),
  new LobeIconMapping('fishaudio', ['^d_', '^g_', '^wd_']),
  new LobeIconMapping('bytedance-color', ['skylark', 'seed-', 'bytedance']),
  new LobeIconMapping('burncloud-color', ['burncloud']),
  new LobeIconMapping('stability-color', [
    'stable-diffusion', 'stable-video', 'stable-cascade', 'sdxl', 'stablelm', '^stable-', '^sd3', '^sd2', '^sd1'
  ]),
  new LobeIconMapping('flux', ['flux']),
  new LobeIconMapping('suno', ['suno']),
  new LobeIconMapping('microsoft-color', ['wizardlm', '/phi-', '^phi-', '-phi-', 'mai-', 'microsoft']),
  new LobeIconMapping('adobe-color', ['firefly']),
  new LobeIconMapping('ai21', ['jamba', '^j2-', 'ai21']),
  new LobeIconMapping('upstage-color', ['^solar-', '/solar']),
  new LobeIconMapping('palm-color', ['palm']),
  new LobeIconMapping('sensenova-color', ['sensechat', 'sensenova']),
  new LobeIconMapping('grok', ['^grok-', '/grok-']),
  new LobeIconMapping('ideogram', ['ideogram', '^v_1', '^v_2', '^v3$', '^upscale$', '^describe$']),
  new LobeIconMapping('spark-color', [
    'spark', 'general$', 'generalv3$', 'generalv3.5$', '4.0ultra$', 'pro-128k$', '^max-32k$', '^lite$', '^x1$'
  ]),
  new LobeIconMapping('udio-color', ['udio']),
  new LobeIconMapping('deepseek-color', ['deepseek']),
  new LobeIconMapping('voyage-color', ['voyage']),
  new LobeIconMapping('assemblyai-color', ['assemblyai']),
  new LobeIconMapping('liquid', ['liquid', 'lfm']),
  new LobeIconMapping('inflection', ['inflection-']),
  new LobeIconMapping('aionlabs-color', ['aion-']),
  new LobeIconMapping('aihubmix-color', ['aihubmix']),
  new LobeIconMapping('v0', ['^v0-']),
  new LobeIconMapping('vertexai-color', ['^veo-', '/veo-', '^veo3']),
  new LobeIconMapping('google-color', ['google', 'learnlm', 'nano-banana']),
  new LobeIconMapping('cogview-color', ['cogview']),
  new LobeIconMapping('kolors-color', ['kolors']),
  new LobeIconMapping('baiducloud-color', ['baidu', 'qianfan']),
  new LobeIconMapping('phind', ['phind']),
  new LobeIconMapping('dolphin', ['dolphin']),
  new LobeIconMapping('ibm', ['ibm', 'granite']),
  new LobeIconMapping('skywork-color', ['skywork']),
  new LobeIconMapping('bilibiliindex', ['bilibili-index', 'index-tts']),
  new LobeIconMapping('bilibili-color', ['bilibili']),
  new LobeIconMapping('lg-color', ['kmmlu', 'exaone', 'lgai']),
  new LobeIconMapping('tii-color', ['falcon']),
  new LobeIconMapping('menlo-color', ['menlo', 'lucy', 'jan-nano']),
  new LobeIconMapping('longcat-color', ['longcat']),
  new LobeIconMapping('kwaipilot-color', ['kat-']),
  new LobeIconMapping('nova-color', ['^nova-', '/nova-']),
  new LobeIconMapping('xiaomimimo', ['^mimo-', '/mimo-']),
  new LobeIconMapping('baai', ['^baai', '^bge-', '/beg-', 'touchd', 'robobrain']),
  new LobeIconMapping('ace', ['ace-step'])
]

const PROVIDER_ICON_MAPPINGS: LobeIconMapping[] = [
  new LobeIconMapping('openai', ['openai', 'chatgpt']),
  new LobeIconMapping('anthropic', ['anthropic']),
  new LobeIconMapping('claude-color', ['claude']),
  new LobeIconMapping('deepseek-color', ['deepseek']),
  new LobeIconMapping('gemini-color', ['gemini']),
  new LobeIconMapping('google-color', ['google']),
  new LobeIconMapping('openrouter-color', ['openrouter']),
  new LobeIconMapping('siliconcloud-color', ['siliconflow', 'siliconcloud']),
  new LobeIconMapping('qwen-color', ['qwen', 'dashscope']),
  new LobeIconMapping('alibabacloud-color', ['alibaba', 'alibabacloud', 'bailian']),
  new LobeIconMapping('kimi-color', ['kimi']),
  new LobeIconMapping('moonshot', ['moonshot']),
  new LobeIconMapping('zhipu-color', ['zhipu', 'zhipuai', 'bigmodel']),
  new LobeIconMapping('volcengine-color', ['doubao', 'volcengine']),
  new LobeIconMapping('minimax-color', ['minimax']),
  new LobeIconMapping('aihubmix-color', ['aihubmix']),
  new LobeIconMapping('xai', ['grok', 'xai']),
  new LobeIconMapping('xiaomimimo', ['mimo', 'xiaomimimo', 'xiaomi']),
  new LobeIconMapping('ollama', ['ollama', 'ollama-cloud']),
  new LobeIconMapping('mistral-color', ['mistral']),
  new LobeIconMapping('cohere-color', ['cohere']),
  new LobeIconMapping('groq', ['groq']),
  new LobeIconMapping('perplexity-color', ['perplexity']),
  new LobeIconMapping('together-color', ['together', 'togetherai']),
  new LobeIconMapping('fireworks-color', ['fireworks', 'fireworksai']),
  new LobeIconMapping('huggingface-color', ['huggingface']),
  new LobeIconMapping('openai', ['azure-openai']),
  new LobeIconMapping('azureai-color', ['azure', 'azureai']),
  new LobeIconMapping('bedrock-color', ['bedrock', 'aws']),
  new LobeIconMapping('vertexai-color', ['vertexai', 'vertex-ai']),
  new LobeIconMapping('lmstudio', ['lmstudio', 'lm-studio']),
  new LobeIconMapping('modelscope-color', ['modelscope']),
  new LobeIconMapping('nvidia-color', ['nvidia']),
  new LobeIconMapping('replicate', ['replicate']),
  new LobeIconMapping('cloudflare-color', ['cloudflare', 'workersai']),
  new LobeIconMapping('vllm-color', ['vllm']),
  new LobeIconMapping('baiducloud-color', ['baidu', 'qianfan']),
  new LobeIconMapping('hunyuan-color', ['hunyuan', 'tencent']),
  new LobeIconMapping('spark-color', ['spark', 'iflytek']),
  new LobeIconMapping('baichuan-color', ['baichuan']),
  new LobeIconMapping('stepfun-color', ['stepfun']),
  new LobeIconMapping('internlm-color', ['internlm']),
  new LobeIconMapping('novita-color', ['novita']),
  new LobeIconMapping('ppio-color', ['ppio']),
  new LobeIconMapping('giteeai', ['giteeai']),
  new LobeIconMapping('newapi-color', ['newapi']),
  new LobeIconMapping('lobehub-color', ['lobehub'])
]

function resolveFirstMapping(value: string, mappings: LobeIconMapping[]): string {
  const normalized = value.trim().toLowerCase()
  if (normalized === '') {
    return ''
  }

  for (let i = 0; i < mappings.length; i++) {
    const mapping = mappings[i]
    for (let j = 0; j < mapping.keywords.length; j++) {
      try {
        if (new RegExp(mapping.keywords[j], 'i').test(normalized)) {
          return mapping.fileName
        }
      } catch (_error) {
        // A malformed future rule must not break icon rendering.
      }
    }
  }
  return ''
}

export function buildLobeIconUrl(fileName: string): string {
  if (fileName === '') {
    return ''
  }
  return `${LOBE_ICONS_CDN_BASE_URL}/${fileName}.svg`
}

export function resolveLobeProviderIconFileName(providerId: string): string {
  return resolveFirstMapping(providerId, PROVIDER_ICON_MAPPINGS)
}

export function resolveLobeProviderIconUrl(providerId: string): string {
  return buildLobeIconUrl(resolveLobeProviderIconFileName(providerId))
}

export function resolveLobeModelIconFileName(modelId: string, providerId: string = ''): string {
  const matchedModelIcon = resolveFirstMapping(modelId, MODEL_ICON_MAPPINGS)
  if (matchedModelIcon !== '') {
    return matchedModelIcon
  }
  return resolveLobeProviderIconFileName(providerId)
}

export function resolveLobeModelIconUrl(modelId: string, providerId: string = ''): string {
  return buildLobeIconUrl(resolveLobeModelIconFileName(modelId, providerId))
}

