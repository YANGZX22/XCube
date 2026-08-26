export class LicenseCatalogItem {
  name: string = ''
  version: string = ''
  licenseName: string = ''
  noticeZh: string = ''
  noticeEn: string = ''

  constructor(name: string, version: string, licenseName: string, noticeZh: string, noticeEn: string) {
    this.name = name
    this.version = version
    this.licenseName = licenseName
    this.noticeZh = noticeZh
    this.noticeEn = noticeEn
  }
}

export const RUNTIME_LICENSES: LicenseCatalogItem[] = [
  new LicenseCatalogItem(
    'XCube', '1.3.6', 'MIT',
    'Copyright © 2026 longlivey、YANGZX22。',
    'Copyright © 2026 longlivey and YANGZX22.'
  ),
  new LicenseCatalogItem(
    '@luvi/lv-markdown-in', '3.4.4', 'MIT',
    'Copyright © 2023-present LiuWei。',
    'Copyright © 2023-present LiuWei.'
  ),
  new LicenseCatalogItem(
    '@luvi/html2md', '1.0.3', 'MIT',
    'Copyright © 2024-present LiuWei。',
    'Copyright © 2024-present LiuWei.'
  ),
  new LicenseCatalogItem(
    '@cangjie-tpc/markdown_hybrid', '1.3.6', 'Apache-2.0',
    'Cangjie-TPC Markdown4cj 混合库。',
    'Cangjie-TPC Markdown4cj hybrid library.'
  ),
  new LicenseCatalogItem(
    '@cangjie-tpc/formula_hybrid', '1.3.0', 'MIT',
    'Formula 混合库；许可证文件标注 Copyright © 2020 Nano Michael。',
    'Formula hybrid library; its license file credits Copyright © 2020 Nano Michael.'
  ),
  new LicenseCatalogItem(
    '@cangjie-tpc/prism_hybrid', '1.2.6', 'Apache-2.0',
    'Cangjie-TPC Prism4cj 代码高亮库。',
    'Cangjie-TPC Prism4cj syntax-highlighting library.'
  ),
  new LicenseCatalogItem(
    'sherpa_onnx', '1.12.20', 'Apache-2.0',
    'The next-gen Kaldi team 提供的端侧语音处理运行库。',
    'On-device speech runtime provided by the next-gen Kaldi team.'
  ),
  new LicenseCatalogItem(
    '@visactor/harmony-vchart', '1.13.5', 'MIT',
    'Copyright © 2023 ByteDance, Inc. and its affiliates。',
    'Copyright © 2023 ByteDance, Inc. and its affiliates.'
  )
]

export const ASSET_LICENSES: LicenseCatalogItem[] = [
  new LicenseCatalogItem(
    'SenseVoice Small', '2024-07-17', 'FunASR Model License v1.1',
    '离线语音识别模型，由 FunASR / FunAudioLLM 发布，适用《FunASR 模型开源许可协议》v1.1；保留 SenseVoice 模型名称与来源标注。',
    'Offline speech-recognition model by FunASR / FunAudioLLM under the FunASR Model Open Source License Agreement v1.1; the SenseVoice name and attribution are retained.'
  ),
  new LicenseCatalogItem(
    'Common Serif', '', 'SIL Open Font License 1.1',
    'Copyright © 2022-2024 The Common Serif Project Authors。',
    'Copyright © 2022-2024 The Common Serif Project Authors.'
  ),
  new LicenseCatalogItem(
    'Cinzel', '', 'SIL Open Font License 1.1',
    'Copyright © 2020 The Cinzel Project Authors。',
    'Copyright © 2020 The Cinzel Project Authors.'
  ),
  new LicenseCatalogItem(
    'Domine', '', 'SIL Open Font License 1.1',
    'Copyright © 2020 The Domine Project Authors；Copyright © 2012 Pablo Impallari、Rodrigo Fuenzalida、Brenda Gallo；保留字体名称 Domine。',
    'Copyright © 2020 The Domine Project Authors; Copyright © 2012 Pablo Impallari, Rodrigo Fuenzalida and Brenda Gallo; Domine is a Reserved Font Name.'
  ),
  new LicenseCatalogItem(
    'Libertinus Serif', '', 'SIL Open Font License 1.1',
    'Copyright © 2025 The Libertinus Serif Project Authors。',
    'Copyright © 2025 The Libertinus Serif Project Authors.'
  ),
  new LicenseCatalogItem(
    'JetBrains Mono', '2.304', 'SIL Open Font License 1.1',
    'Copyright © 2020 The JetBrains Mono Project Authors。',
    'Copyright © 2020 The JetBrains Mono Project Authors.'
  ),
  new LicenseCatalogItem(
    'Source Han Serif SC', '', 'SIL Open Font License 1.1',
    'Copyright © 2017-2022 Adobe；保留字体名称 Source。',
    'Copyright © 2017-2022 Adobe; Source is a Reserved Font Name.'
  ),
  new LicenseCatalogItem(
    'Computer Modern math fonts', '', 'Knuth License',
    '由公式渲染组件随附；修改版本不得沿用原始字体名称。',
    'Bundled by the formula renderer; modified versions must use a different name.'
  ),
  new LicenseCatalogItem(
    'DSROM math fonts', '', 'DSROM Font License',
    '允许使用与分发；修改时不得使用 Donald E. Knuth 为 Computer Modern 选择的字体文件名。',
    'Use and distribution are permitted; modified fonts must not use Donald E. Knuth\'s Computer Modern filenames.'
  ),
  new LicenseCatalogItem(
    'AMS math fonts', '', 'SIL Open Font License 1.1',
    'Copyright © 1997, 2009 American Mathematical Society；包含保留字体名称。',
    'Copyright © 1997, 2009 American Mathematical Society; Reserved Font Names apply.'
  )
]

export const DEVELOPMENT_LICENSES: LicenseCatalogItem[] = [
  new LicenseCatalogItem(
    '@ohos/hypium', '1.0.24', 'Apache-2.0',
    'OpenHarmony 应用单元测试框架，仅用于开发与测试。',
    'OpenHarmony unit-test framework, used only for development and testing.'
  ),
  new LicenseCatalogItem(
    '@ohos/hamock', '1.0.0', 'Apache-2.0',
    'OpenHarmony 应用 Mock 框架，仅用于开发与测试。',
    'OpenHarmony mock framework, used only for development and testing.'
  )
]
