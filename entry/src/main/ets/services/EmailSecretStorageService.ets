import { util } from '@kit.ArkTS'
import { asset } from '@kit.AssetStoreKit'
import { huks } from '@kit.UniversalKeystoreKit'

interface EncryptedEmailSecretJson {
  version: number
  nonce: string
  ciphertext: string
}

const EMAIL_SECRET_KEY_ALIAS: string = 'chatcube_email_account_secret_v1'
const EMAIL_SECRET_VERSION: number = 1
const EMAIL_SECRET_AE_TAG_BITS: number = 128
const EMAIL_SECRET_ASSET_ALIAS: string = 'chatcube_email_account_secret_v2'
const EMAIL_SECRET_ASSET_MARKER: string = 'asset-store://chatcube_email_account_secret_v2'
const ASSET_NOT_FOUND_CODE: number = 24000002

interface EmailStorageBusinessError {
  code?: number
  message?: string
}

/** Keeps new mail credentials in Asset Store; HUKS remains only for reading legacy ciphertext. */
export class EmailSecretStorageService {
  private static instance: EmailSecretStorageService | null = null
  private keyReadyPromise: Promise<void> | null = null

  static getInstance(): EmailSecretStorageService {
    if (EmailSecretStorageService.instance === null) {
      EmailSecretStorageService.instance = new EmailSecretStorageService()
    }
    return EmailSecretStorageService.instance
  }

  private keyProperties(): huks.HuksParam[] {
    return [
      {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
          huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
      },
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE }
    ]
  }

  private operationProperties(purpose: huks.HuksKeyPurpose, nonce: Uint8Array): huks.HuksParam[] {
    return [
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
      { tag: huks.HuksTag.HUKS_TAG_AE_TAG_LEN, value: EMAIL_SECRET_AE_TAG_BITS }
    ]
  }

  private async ensureKey(): Promise<void> {
    if (this.keyReadyPromise !== null) {
      await this.keyReadyPromise
      return
    }
    this.keyReadyPromise = this.createKeyIfNeeded()
    try {
      await this.keyReadyPromise
    } finally {
      this.keyReadyPromise = null
    }
  }

  private async createKeyIfNeeded(): Promise<void> {
    const queryOptions: huks.HuksOptions = { properties: this.keyProperties() }
    if (await huks.hasKeyItem(EMAIL_SECRET_KEY_ALIAS, queryOptions)) {
      return
    }
    await huks.generateKeyItem(EMAIL_SECRET_KEY_ALIAS, queryOptions)
  }

  async encrypt(secret: string): Promise<string> {
    if (secret === '') {
      return ''
    }
    const attributes: asset.AssetMap = this.assetAliasAttributes()
    attributes.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(secret))
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_POWERED_ON)
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER)
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE)
    try {
      // The synchronous entry point keeps this small local IPC operation on the UI executor.
      // Some devices fail direct asynchronous HUKS initialization after NetStack callbacks.
      asset.addSync(attributes)
    } catch (error) {
      throw new Error(this.assetErrorMessage(error, '邮箱授权信息安全保存失败'))
    }
    return EMAIL_SECRET_ASSET_MARKER
  }

  async decrypt(payloadJson: string): Promise<string> {
    if (payloadJson.trim() === '') {
      return ''
    }
    if (payloadJson === EMAIL_SECRET_ASSET_MARKER) {
      return this.readAssetSecret()
    }
    return await this.decryptLegacyHuksSecret(payloadJson)
  }

  async remove(): Promise<void> {
    try {
      asset.removeSync(this.assetAliasAttributes())
    } catch (error) {
      const businessError = error as EmailStorageBusinessError
      if (businessError.code !== ASSET_NOT_FOUND_CODE) {
        throw new Error(this.assetErrorMessage(error, '邮箱授权信息删除失败'))
      }
    }
  }

  private readAssetSecret(): string {
    const query = this.assetAliasAttributes()
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL)
    let results: Array<asset.AssetMap>
    try {
      results = asset.querySync(query)
    } catch (error) {
      const businessError = error as EmailStorageBusinessError
      if (businessError.code === ASSET_NOT_FOUND_CODE) {
        throw new Error('邮箱授权信息已失效，请重新配置')
      }
      throw new Error(this.assetErrorMessage(error, '邮箱授权信息读取失败'))
    }
    if (results.length !== 1) {
      throw new Error('邮箱授权信息已失效，请重新配置')
    }
    const secret = results[0].get(asset.Tag.SECRET)
    if (!(secret instanceof Uint8Array)) {
      throw new Error('邮箱授权信息已损坏，请重新配置')
    }
    return util.TextDecoder.create('utf-8').decodeToString(secret, { stream: false })
  }

  private assetAliasAttributes(): asset.AssetMap {
    const attributes: asset.AssetMap = new Map()
    attributes.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(EMAIL_SECRET_ASSET_ALIAS))
    return attributes
  }

  private assetErrorMessage(error: Object, fallback: string): string {
    const businessError = error as EmailStorageBusinessError
    const message = businessError.message === undefined ? '' : businessError.message.trim()
    if (message !== '') {
      return businessError.code === undefined ? `${fallback}：${message}` : `${fallback}：${message} (${businessError.code})`
    }
    return businessError.code === undefined ? fallback : `${fallback} (${businessError.code})`
  }

  private async decryptLegacyHuksSecret(payloadJson: string): Promise<string> {
    await this.ensureKey()
    let payload: EncryptedEmailSecretJson
    try {
      payload = JSON.parse(payloadJson) as EncryptedEmailSecretJson
    } catch (_error) {
      throw new Error('邮箱授权信息已损坏，请重新配置')
    }
    if (payload.version !== EMAIL_SECRET_VERSION || payload.nonce === '' || payload.ciphertext === '') {
      throw new Error('邮箱授权信息版本无效，请重新配置')
    }
    const base64 = new util.Base64Helper()
    const nonce = base64.decodeSync(payload.nonce)
    const ciphertext = base64.decodeSync(payload.ciphertext)
    const session = await huks.initSession(EMAIL_SECRET_KEY_ALIAS, {
      properties: this.operationProperties(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, nonce)
    })
    const result = await huks.finishSession(session.handle, { inData: ciphertext })
    if (result.outData === undefined) {
      throw new Error('邮箱授权信息解密失败，请重新配置')
    }
    return util.TextDecoder.create('utf-8').decodeToString(result.outData, { stream: false })
  }
}

export function getEmailSecretStorageService(): EmailSecretStorageService {
  return EmailSecretStorageService.getInstance()
}
