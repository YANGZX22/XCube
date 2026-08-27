import { bundleManager, Context } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { fileIo } from '@kit.CoreFileKit'
import { socket } from '@kit.NetworkKit'
import {
  EmailAccountConfig,
  EmailAuthenticationMethod,
  EmailAttachmentPart,
  EmailConnectionTestResult,
  EmailImportResult,
  EmailListRequest,
  EmailMessageDetail,
  EmailMessageSummary,
  EmailOAuthDeviceAuthorization,
  EmailOAuthTokenResult,
  EmailOperationResult,
  EmailSendRequest,
  EmailTransportSecurity
} from '../models/EmailModels'
import { getPreferencesService, PreferenceKeys } from './PreferencesService'
import { getEmailSecretStorageService } from './EmailSecretStorageService'
import { getHttpService, HttpResponse } from './HttpService'
import { getKnowledgeDocumentService } from './KnowledgeDocumentService'

interface StoredEmailAccountJson {
  emailAddress: string
  displayName: string
  username: string
  smtpHost: string
  smtpPort: number
  smtpSecurity: string
  imapHost: string
  imapPort: number
  imapSecurity: string
  authenticationMethod?: string
  oauthClientId?: string
  configured: boolean
}

interface MicrosoftDeviceCodeJson {
  device_code?: string
  user_code?: string
  verification_uri?: string
  verification_uri_complete?: string
  expires_in?: number
  interval?: number
  message?: string
  error?: string
  error_description?: string
}

interface MicrosoftTokenJson {
  access_token?: string
  refresh_token?: string
  expires_in?: number
  error?: string
  error_description?: string
}

interface EmailReadToolOutput {
  account: string
  messages: EmailMessageSummary[]
}

interface EmailToolAttachmentOutput {
  name: string
  mimeType: string
  inline: boolean
  size: number
  parsedText: string
  parsedTextTruncated: boolean
  parseStatus: string
}

interface EmailDetailToolOutput {
  uid: string
  messageId: string
  subject: string
  from: string
  to: string
  cc: string
  replyTo: string
  date: string
  body: string
  bodyTruncated: boolean
  attachments: EmailToolAttachmentOutput[]
}

class EmailAttachmentKnowledgeContent {
  name: string = ''
  mimeType: string = ''
  text: string = ''
  truncated: boolean = false
  message: string = ''

  constructor(name: string, mimeType: string, text: string = '', truncated: boolean = false,
    message: string = '') {
    this.name = name
    this.mimeType = mimeType
    this.text = text
    this.truncated = truncated
    this.message = message
  }
}

class EmailAccountAuthorization {
  config: EmailAccountConfig
  password: string

  constructor(config: EmailAccountConfig, password: string) {
    this.config = config
    this.password = password
  }
}

class MimeEntity {
  headers: Map<string, string> = new Map()
  body: string = ''
}

class ParsedMimeMessage {
  textParts: string[] = []
  htmlParts: string[] = []
  attachments: EmailAttachmentPart[] = []
}

class ImapMessagePreview {
  uid: string = ''
  raw: string = ''
  unread: boolean = false
  size: number = 0

  constructor(uid: string, raw: string, unread: boolean, size: number) {
    this.uid = uid
    this.raw = raw
    this.unread = unread
    this.size = size
  }
}

type EmailResponsePredicate = (response: string) => boolean

const EMAIL_SOCKET_TIMEOUT_MS: number = 30000
const EMAIL_SOCKET_OPERATION_SETTLE_MS: number = 80
const EMAIL_MAX_RESPONSE_CHARACTERS: number = 28 * 1024 * 1024
const EMAIL_MAX_TOOL_BODY_CHARACTERS: number = 30000
const EMAIL_MAX_TOOL_ATTACHMENT_CHARACTERS: number = 30000
const EMAIL_MAX_COMBINED_TOOL_ATTACHMENT_CHARACTERS: number = 120000
const EMAIL_MAX_SEND_BODY_CHARACTERS: number = 200000
const EMAIL_MAX_ATTACHMENT_KNOWLEDGE_CHARACTERS: number = 240000
const EMAIL_MAX_COMBINED_ATTACHMENT_KNOWLEDGE_CHARACTERS: number = 1500000
const EMAIL_IMPORT_TEMP_DIRECTORY: string = 'email/import-tmp'
const EMAIL_MAX_RECIPIENTS: number = 50
const EMAIL_LOCAL_SEARCH_MAX_MESSAGES: number = 300
const EMAIL_LOCAL_SEARCH_BATCH_SIZE: number = 10
const EMAIL_LOCAL_SEARCH_PREVIEW_BYTES: number = 256 * 1024
const MICROSOFT_DEVICE_CODE_URL: string =
  'https://login.microsoftonline.com/common/oauth2/v2.0/devicecode'
const MICROSOFT_TOKEN_URL: string = 'https://login.microsoftonline.com/common/oauth2/v2.0/token'
const MICROSOFT_MAIL_SCOPES: string = 'offline_access https://outlook.office.com/IMAP.AccessAsUser.All ' +
  'https://outlook.office.com/SMTP.Send'
const IMAP_CLIENT_ID_NAME: string = 'XCube'
const IMAP_CLIENT_ID_VERSION: string = '1.3.6'
const IMAP_CLIENT_ID_VENDOR: string = 'YANGZX22'
const IMAP_CLIENT_ID_SUPPORT_URL: string = 'https://github.com/YANGZX22/XCube'

/** Small line-protocol client used by both SMTP and IMAP, including STARTTLS upgrades. */
class EmailSocketClient {
  private tcpSocket: socket.TCPSocket | null = null
  private tlsSocket: socket.TLSSocket | null = null
  private responseBuffer: string = ''
  private waiterPredicate: EmailResponsePredicate | null = null
  private waiterResolve: ((response: string) => void) | null = null
  private waiterReject: ((error: Error) => void) | null = null
  private waiterTimer: number = -1
  private closed: boolean = false
  private lastReceiveAt: number = 0

  async connect(host: string, port: number, security: string): Promise<void> {
    this.closed = false
    this.responseBuffer = ''
    if (security === EmailTransportSecurity.STARTTLS) {
      const tcp = socket.constructTCPSocketInstance()
      this.tcpSocket = tcp
      await tcp.bind({ address: '0.0.0.0', family: 1, port: 0 })
      // NetStack requires bind to finish before socket events are registered.
      this.attachTcpListeners(tcp)
      try {
        await tcp.connect({ address: { address: host, family: 1, port: port }, timeout: EMAIL_SOCKET_TIMEOUT_MS })
      } catch (error) {
        if (!this.isOperationInProgress(error) || !(await this.waitForTcpConnected(tcp))) {
          throw new Error(this.safeErrorMessage(error))
        }
      }
      return
    }
    const tls = socket.constructTLSSocketInstance()
    this.tlsSocket = tls
    await tls.bind({ address: '0.0.0.0', family: 1, port: 0 })
    // Register after bind but before connect, matching the Network Kit lifecycle. Registering
    // before bind produces "tlsSocket is null" and silently loses the server greeting.
    this.attachTlsListeners(tls)
    try {
      await tls.connect({
        address: { address: host, family: 1, port: port },
        secureOptions: { protocols: [socket.Protocol.TLSv12, socket.Protocol.TLSv13] },
        skipRemoteValidation: false
      })
    } catch (error) {
      if (!this.isOperationInProgress(error) || !(await this.waitForTlsConnected(tls))) {
        throw new Error(this.safeErrorMessage(error))
      }
    }
    // Do not pass TLSConnectOptions.timeout here. On affected HarmonyOS NetStack builds the
    // promise is held for the full timeout even though the TLS handshake already succeeded,
    // so SMTP/IMAP servers close the idle session before the app can read their greeting.
  }

  async upgradeToTls(host: string, port: number): Promise<void> {
    const tcp = this.tcpSocket
    if (tcp === null) {
      throw new Error('STARTTLS 连接状态无效')
    }
    tcp.off('message')
    tcp.off('error')
    const tls = socket.constructTLSSocketInstance(tcp)
    this.tlsSocket = tls
    this.tcpSocket = null
    this.responseBuffer = ''
    // A TLSSocket upgraded from an already-connected TCPSocket owns a valid native socket now,
    // so subscribe before starting the handshake to avoid missing the first encrypted response.
    this.attachTlsListeners(tls)
    await tls.connect({
      address: { address: host, family: 1, port: port },
      secureOptions: { protocols: [socket.Protocol.TLSv12, socket.Protocol.TLSv13] },
      skipRemoteValidation: false
    })
  }

  async send(data: string): Promise<void> {
    await this.settleAfterReceive()
    if (this.tlsSocket !== null) {
      await this.sendTlsWithBusyRetry(this.tlsSocket, data)
      return
    }
    if (this.tcpSocket !== null) {
      await this.sendTcpWithBusyRetry(this.tcpSocket, data)
      return
    }
    throw new Error('邮件服务器连接不可用')
  }

  async command(data: string, predicate: EmailResponsePredicate): Promise<string> {
    this.responseBuffer = ''
    await this.send(data)
    return await this.waitFor(predicate)
  }

  async waitFor(predicate: EmailResponsePredicate): Promise<string> {
    if (predicate(this.responseBuffer)) {
      return this.responseBuffer
    }
    if (this.waiterResolve !== null) {
      throw new Error('邮件协议请求重叠')
    }
    return await new Promise<string>((resolve, reject) => {
      this.waiterPredicate = predicate
      this.waiterResolve = resolve
      this.waiterReject = reject
      this.waiterTimer = setTimeout((): void => {
        this.rejectWaiter(new Error('邮件服务器响应超时'))
      }, EMAIL_SOCKET_TIMEOUT_MS)
    })
  }

  async close(): Promise<void> {
    if (this.closed) {
      return
    }
    this.closed = true
    this.rejectWaiter(new Error('邮件服务器连接已关闭'))
    const tls = this.tlsSocket
    const tcp = this.tcpSocket
    this.tlsSocket = null
    this.tcpSocket = null
    if (tls !== null) {
      try {
        tls.off('message')
        tls.off('error')
        await tls.close()
      } catch (_error) {}
    }
    if (tcp !== null) {
      try {
        tcp.off('message')
        tcp.off('error')
        await tcp.close()
      } catch (_error) {}
    }
  }

  private attachTcpListeners(target: socket.TCPSocket): void {
    target.on('message', (info: socket.SocketMessageInfo): void => {
      this.receive(info.message)
    })
    target.on('error', (error: Error): void => {
      this.rejectWaiter(new Error(this.safeErrorMessage(error)))
    })
  }

  private attachTlsListeners(target: socket.TLSSocket): void {
    target.on('message', (info: socket.SocketMessageInfo): void => {
      this.receive(info.message)
    })
    target.on('error', (error: Error): void => {
      this.rejectWaiter(new Error(this.safeErrorMessage(error)))
    })
  }

  private receive(buffer: ArrayBuffer): void {
    this.lastReceiveAt = Date.now()
    // Keep the IMAP literal byte-for-byte intact. Attachments are usually base64, but valid MIME
    // can also use 8bit/binary transfer encoding; decoding the whole socket as UTF-8 corrupts
    // those bytes before the MIME parser sees them.
    this.responseBuffer += this.binaryString(new Uint8Array(buffer))
    if (this.responseBuffer.length > EMAIL_MAX_RESPONSE_CHARACTERS) {
      this.rejectWaiter(new Error('邮件内容超过 28 MB 安全限制'))
      return
    }
    if (this.waiterPredicate !== null && this.waiterPredicate(this.responseBuffer)) {
      const response = this.responseBuffer
      const resolve = this.waiterResolve
      this.clearWaiter()
      if (resolve !== null) {
        resolve(response)
      }
    }
  }

  private binaryString(bytes: Uint8Array): string {
    let result = ''
    for (let index = 0; index < bytes.byteLength; index++) {
      result += String.fromCharCode(bytes[index])
    }
    return result
  }

  private rejectWaiter(error: Error): void {
    const reject = this.waiterReject
    this.clearWaiter()
    if (reject !== null) {
      reject(error)
    }
  }

  private clearWaiter(): void {
    if (this.waiterTimer !== -1) {
      clearTimeout(this.waiterTimer)
    }
    this.waiterTimer = -1
    this.waiterPredicate = null
    this.waiterResolve = null
    this.waiterReject = null
  }

  private async settleAfterReceive(): Promise<void> {
    const remaining = EMAIL_SOCKET_OPERATION_SETTLE_MS - (Date.now() - this.lastReceiveAt)
    if (remaining > 0) {
      await this.waitMilliseconds(remaining)
    }
  }

  private async sendTlsWithBusyRetry(target: socket.TLSSocket, data: string): Promise<void> {
    try {
      await target.send(data)
    } catch (error) {
      if (!this.isOperationInProgress(error)) {
        throw new Error(this.safeErrorMessage(error))
      }
      await this.waitMilliseconds(EMAIL_SOCKET_OPERATION_SETTLE_MS * 2)
      await target.send(data)
    }
  }

  private async sendTcpWithBusyRetry(target: socket.TCPSocket, data: string): Promise<void> {
    try {
      await target.send({ data: data })
    } catch (error) {
      if (!this.isOperationInProgress(error)) {
        throw new Error(this.safeErrorMessage(error))
      }
      await this.waitMilliseconds(EMAIL_SOCKET_OPERATION_SETTLE_MS * 2)
      await target.send({ data: data })
    }
  }

  private async waitForTcpConnected(target: socket.TCPSocket): Promise<boolean> {
    for (let i = 0; i < 30; i++) {
      await this.waitMilliseconds(100)
      try {
        if ((await target.getState()).isConnected) {
          return true
        }
      } catch (_error) {}
    }
    return false
  }

  private async waitForTlsConnected(target: socket.TLSSocket): Promise<boolean> {
    for (let i = 0; i < 30; i++) {
      await this.waitMilliseconds(100)
      try {
        if ((await target.getState()).isConnected) {
          return true
        }
      } catch (_error) {}
    }
    return false
  }

  private isOperationInProgress(error: Object): boolean {
    try {
      const json = JSON.parse(JSON.stringify(error)) as Record<string, Object>
      return json.code === 2301115 || `${json.message || ''}`.includes('Operation in progress')
    } catch (_serializationError) {
      return false
    }
  }

  private async waitMilliseconds(milliseconds: number): Promise<void> {
    await new Promise<void>((resolve): void => {
      setTimeout(resolve, milliseconds)
    })
  }

  private safeErrorMessage(error: Object): string {
    if (error instanceof Error && error.message.trim() !== '') {
      return error.message
    }
    try {
      const value = JSON.stringify(error)
      const json = JSON.parse(value) as Record<string, Object>
      if (json.code === 2301115) {
        return '网络协议栈正在完成上一项邮件操作，请稍后重试'
      }
      if (json.message !== undefined && `${json.message}`.trim() !== '') {
        return json.code !== undefined ? `${json.message} (${json.code})` : `${json.message}`
      }
      return value !== '{}' ? value : '邮件服务器连接失败'
    } catch (_serializationError) {
      return '邮件服务器连接失败'
    }
  }
}

class ImapSession {
  private client: EmailSocketClient = new EmailSocketClient()
  private nextTagNumber: number = 1
  private selected: boolean = false
  private identified: boolean = false

  async connect(config: EmailAccountConfig, credential: string): Promise<void> {
    await this.client.connect(config.imapHost, config.imapPort, config.imapSecurity)
    const greeting = await this.client.waitFor((response: string): boolean => {
      return response.startsWith('* OK') || response.startsWith('* PREAUTH') || response.startsWith('* BYE')
    })
    if (greeting.startsWith('* BYE')) {
      throw new Error('IMAP 服务器拒绝连接')
    }
    if (config.imapSecurity === EmailTransportSecurity.STARTTLS) {
      await this.execute('STARTTLS')
      await this.client.upgradeToTls(config.imapHost, config.imapPort)
    }
    if (!greeting.startsWith('* PREAUTH')) {
      try {
        await this.authenticate(config, credential)
      } catch (error) {
        // NetEase documents ID after login, but some gateways reject LOGIN itself with
        // "Unsafe Login". RFC 2971 permits ID in any state, so identify and retry once.
        if (!this.isNetEaseMailbox(config) || !this.isUnsafeLoginError(error)) {
          const message = error instanceof Error && error.message.trim() !== ''
            ? error.message
            : 'IMAP 认证失败'
          throw new Error(message)
        }
        await this.identifyClient(config)
        await this.authenticate(config, credential)
      }
    }
    await this.identifyClient(config)
  }

  async selectInbox(): Promise<void> {
    if (this.selected) {
      return
    }
    await this.execute('SELECT "INBOX"')
    this.selected = true
  }

  async execute(command: string): Promise<string> {
    const tag = this.nextTag()
    const response = await this.client.command(`${tag} ${command}\r\n`, (value: string): boolean => {
      return value.startsWith(`${tag} `) || value.includes(`\r\n${tag} `)
    })
    const status = this.parseTaggedStatus(response, tag)
    if (status !== 'OK') {
      throw new Error(this.extractTaggedMessage(response, tag))
    }
    return response
  }

  async fetchRawMessage(uid: string): Promise<string> {
    const response = await this.execute(`UID FETCH ${this.numericUid(uid)} (BODY.PEEK[])`)
    return this.extractLiteral(response)
  }

  async fetchMessagePreviews(uids: string[], maximumBytes: number): Promise<ImapMessagePreview[]> {
    if (uids.length === 0) {
      return []
    }
    const numericUids: string[] = []
    for (let i = 0; i < uids.length; i++) {
      numericUids.push(this.numericUid(uids[i]))
    }
    const safeMaximumBytes = Math.min(Math.max(Math.floor(maximumBytes), 4096), 1024 * 1024)
    const response = await this.execute(
      `UID FETCH ${numericUids.join(',')} (UID FLAGS RFC822.SIZE BODY.PEEK[]<0.${safeMaximumBytes}>)`
    )
    return this.extractMessagePreviews(response)
  }

  async close(): Promise<void> {
    try {
      await this.execute('LOGOUT')
    } catch (_error) {}
    await this.client.close()
  }

  private nextTag(): string {
    const tag = `A${this.nextTagNumber.toString().padStart(4, '0')}`
    this.nextTagNumber += 1
    return tag
  }

  private parseTaggedStatus(response: string, tag: string): string {
    const lines = response.split('\r\n')
    for (let i = lines.length - 1; i >= 0; i--) {
      if (lines[i].startsWith(`${tag} `)) {
        const parts = lines[i].split(' ')
        return parts.length > 1 ? parts[1].toUpperCase() : 'BAD'
      }
    }
    return 'BAD'
  }

  private extractTaggedMessage(response: string, tag: string): string {
    const lines = response.split('\r\n')
    for (let i = lines.length - 1; i >= 0; i--) {
      if (lines[i].startsWith(`${tag} `)) {
        const firstSpace = lines[i].indexOf(' ')
        const secondSpace = firstSpace < 0 ? -1 : lines[i].indexOf(' ', firstSpace + 1)
        return secondSpace >= 0 ? lines[i].substring(secondSpace + 1) : 'IMAP 请求失败'
      }
    }
    return 'IMAP 请求失败'
  }

  private extractLiteral(response: string): string {
    const marker = response.match(/\{[0-9]+\}\r\n/)
    if (marker === null || marker.index === undefined) {
      throw new Error('IMAP 返回的邮件格式无效')
    }
    const start = marker.index + marker[0].length
    const end = response.lastIndexOf('\r\n)\r\n')
    if (end < start) {
      throw new Error('IMAP 邮件内容不完整')
    }
    return response.substring(start, end)
  }

  private extractMessagePreviews(response: string): ImapMessagePreview[] {
    const previews: ImapMessagePreview[] = []
    let cursor = 0
    while (cursor < response.length) {
      const fetchMarker = response.indexOf(' FETCH (', cursor)
      if (fetchMarker < 0) {
        break
      }
      const lineBreakBefore = response.lastIndexOf('\r\n', fetchMarker)
      const fetchStart = lineBreakBefore >= 0 ? lineBreakBefore + 2 : 0
      const literalMarkerStart = response.indexOf('{', fetchMarker)
      if (literalMarkerStart < 0) {
        break
      }
      const literalMarkerEnd = response.indexOf('}\r\n', literalMarkerStart)
      if (literalMarkerEnd < 0) {
        break
      }
      const marker = response.substring(literalMarkerStart + 1, literalMarkerEnd).replace('+', '')
      if (!/^[0-9]+$/.test(marker)) {
        cursor = literalMarkerEnd + 3
        continue
      }
      const literalLength = Number(marker)
      const literalStart = literalMarkerEnd + 3
      const literalEnd = literalStart + literalLength
      if (literalEnd > response.length) {
        break
      }
      const suffixEndCandidate = response.indexOf('\r\n', literalEnd)
      const suffixEnd = suffixEndCandidate >= 0 ? suffixEndCandidate : response.length
      const metadata = response.substring(fetchStart, literalMarkerStart) + response.substring(literalEnd, suffixEnd)
      const uidMatch = metadata.match(/\bUID\s+([0-9]+)/i)
      if (uidMatch !== null) {
        const sizeMatch = metadata.match(/\bRFC822\.SIZE\s+([0-9]+)/i)
        const size = sizeMatch !== null ? Number(sizeMatch[1]) : literalLength
        previews.push(new ImapMessagePreview(
          uidMatch[1],
          response.substring(literalStart, literalEnd),
          !metadata.includes('\\Seen'),
          size
        ))
      }
      cursor = literalEnd
    }
    return previews
  }

  private numericUid(uid: string): string {
    const normalized = uid.trim()
    if (!/^[0-9]+$/.test(normalized)) {
      throw new Error('邮件 UID 无效')
    }
    return normalized
  }

  private quote(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/[\r\n]/g, '')
  }

  private oauth2Payload(username: string, accessToken: string): string {
    const raw = `user=${username}\u0001auth=Bearer ${accessToken}\u0001\u0001`
    return new util.Base64Helper().encodeToStringSync(new util.TextEncoder().encodeInto(raw))
  }

  private async identifyClient(config: EmailAccountConfig): Promise<void> {
    if (this.identified) {
      return
    }
    const netEaseMailbox = this.isNetEaseMailbox(config)
    let shouldSendId = netEaseMailbox
    if (!shouldSendId) {
      try {
        const capabilities = await this.execute('CAPABILITY')
        shouldSendId = /(?:^|[\s])ID(?:[\s]|$)/i.test(capabilities)
      } catch (_error) {
        return
      }
    }
    if (!shouldSendId) {
      return
    }
    const command = 'ID ' +
      `("name" "${this.quote(IMAP_CLIENT_ID_NAME)}" ` +
      `"version" "${this.quote(this.clientVersion())}" ` +
      `"vendor" "${this.quote(IMAP_CLIENT_ID_VENDOR)}" ` +
      `"support-url" "${this.quote(IMAP_CLIENT_ID_SUPPORT_URL)}")`
    try {
      await this.execute(command)
      this.identified = true
    } catch (error) {
      if (netEaseMailbox) {
        const message = error instanceof Error && error.message.trim() !== ''
          ? error.message : '服务器未接受客户端身份信息'
        throw new Error(`网易邮箱 IMAP ID 发送失败：${message}`)
      }
    }
  }

  private isNetEaseMailbox(config: EmailAccountConfig): boolean {
    const username = config.username.trim().toLowerCase()
    const domain = username.includes('@') ? username.substring(username.lastIndexOf('@') + 1) : ''
    const host = config.imapHost.trim().toLowerCase()
    return domain === '163.com' || domain === '126.com' || domain === 'yeah.net' ||
      host === 'imap.163.com' || host === 'imap.126.com' || host === 'imap.yeah.net'
  }

  private async authenticate(config: EmailAccountConfig, credential: string): Promise<void> {
    if (config.authenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2) {
      const xoauth2 = this.oauth2Payload(config.username, credential)
      await this.execute(`AUTHENTICATE XOAUTH2 ${xoauth2}`)
      return
    }
    await this.execute(`LOGIN "${this.quote(config.username)}" "${this.quote(credential)}"`)
  }

  private isUnsafeLoginError(error: Object): boolean {
    return error instanceof Error && error.message.toLowerCase().includes('unsafe login')
  }

  private clientVersion(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      return info.versionName.trim() !== '' ? info.versionName : IMAP_CLIENT_ID_VERSION
    } catch (_error) {
      return IMAP_CLIENT_ID_VERSION
    }
  }
}

export class EmailService {
  private static instance: EmailService | null = null
  private context: Context | null = null
  private config: EmailAccountConfig = new EmailAccountConfig()
  private initialized: boolean = false

  static getInstance(): EmailService {
    if (EmailService.instance === null) {
      EmailService.instance = new EmailService()
    }
    return EmailService.instance
  }

  async initialize(context: Context): Promise<void> {
    this.context = context
    this.config = await this.readStoredConfig()
    this.ensureTempDirectory()
    this.initialized = true
  }

  async loadConfig(): Promise<EmailAccountConfig> {
    if (!this.initialized) {
      this.config = await this.readStoredConfig()
    }
    return this.config.copy()
  }

  isConfigured(): boolean {
    return this.config.configured
  }

  suggestConfig(emailAddress: string): EmailAccountConfig {
    const email = emailAddress.trim().toLowerCase()
    const domain = email.includes('@') ? email.substring(email.lastIndexOf('@') + 1) : ''
    const config = new EmailAccountConfig()
    config.emailAddress = emailAddress.trim()
    config.username = emailAddress.trim()
    if (domain === 'gmail.com' || domain === 'googlemail.com') {
      config.smtpHost = 'smtp.gmail.com'
      config.imapHost = 'imap.gmail.com'
    } else if (domain === 'qq.com' || domain === 'foxmail.com') {
      config.smtpHost = 'smtp.qq.com'
      config.imapHost = 'imap.qq.com'
    } else if (domain === '163.com' || domain === '126.com' || domain === 'yeah.net') {
      config.smtpHost = `smtp.${domain}`
      config.imapHost = `imap.${domain}`
    } else if (domain === 'outlook.com' || domain === 'hotmail.com' || domain === 'live.com' ||
      domain === 'office365.com') {
      config.smtpHost = 'smtp-mail.outlook.com'
      config.smtpPort = 587
      config.smtpSecurity = EmailTransportSecurity.STARTTLS
      config.imapHost = 'outlook.office365.com'
      config.authenticationMethod = EmailAuthenticationMethod.MICROSOFT_OAUTH2
    }
    return config
  }

  async requestMicrosoftOAuthDeviceAuthorization(input: EmailAccountConfig):
    Promise<EmailOAuthDeviceAuthorization> {
    const config = this.normalizeAndValidateConfig(input)
    if (config.authenticationMethod !== EmailAuthenticationMethod.MICROSOFT_OAUTH2) {
      throw new Error('请先选择 Microsoft OAuth2 认证')
    }
    this.validateOAuthClientId(config.oauthClientId)
    const response = await getHttpService().post(
      MICROSOFT_DEVICE_CODE_URL,
      `client_id=${encodeURIComponent(config.oauthClientId)}&scope=${encodeURIComponent(MICROSOFT_MAIL_SCOPES)}`,
      { 'Content-Type': 'application/x-www-form-urlencoded' },
      { timeout: 30000 }
    )
    const json = this.parseMicrosoftDeviceCodeResponse(response)
    if (!response.success || json.device_code === undefined || json.user_code === undefined ||
      json.verification_uri === undefined) {
      throw new Error(this.microsoftOAuthError(json, response, '无法启动 Microsoft OAuth2 授权'))
    }
    const authorization = new EmailOAuthDeviceAuthorization()
    authorization.deviceCode = json.device_code
    authorization.userCode = json.user_code
    authorization.verificationUri = json.verification_uri
    authorization.verificationUriComplete = json.verification_uri_complete || json.verification_uri
    authorization.expiresInSeconds = Math.max(json.expires_in || 900, 60)
    authorization.pollingIntervalSeconds = Math.max(json.interval || 5, 5)
    return authorization
  }

  async completeMicrosoftOAuthDeviceAuthorization(input: EmailAccountConfig,
    authorization: EmailOAuthDeviceAuthorization): Promise<EmailOAuthTokenResult> {
    const config = this.normalizeAndValidateConfig(input)
    this.validateOAuthClientId(config.oauthClientId)
    const deadline = Date.now() + authorization.expiresInSeconds * 1000
    let intervalSeconds = authorization.pollingIntervalSeconds
    while (Date.now() < deadline) {
      await this.waitMilliseconds(intervalSeconds * 1000)
      const body = `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:device_code')}` +
        `&client_id=${encodeURIComponent(config.oauthClientId)}` +
        `&device_code=${encodeURIComponent(authorization.deviceCode)}`
      const response = await getHttpService().post(MICROSOFT_TOKEN_URL, body,
        { 'Content-Type': 'application/x-www-form-urlencoded' }, { timeout: 30000 })
      const json = this.parseMicrosoftTokenResponse(response)
      if (response.success && json.access_token !== undefined && json.refresh_token !== undefined) {
        const result = new EmailOAuthTokenResult()
        result.accessToken = json.access_token
        result.refreshToken = json.refresh_token
        return result
      }
      if (json.error === 'authorization_pending') {
        continue
      }
      if (json.error === 'slow_down') {
        intervalSeconds += 5
        continue
      }
      throw new Error(this.microsoftOAuthError(json, response, 'Microsoft OAuth2 授权失败'))
    }
    throw new Error('Microsoft OAuth2 授权已超时，请重新发起授权')
  }

  async testOAuthConnection(input: EmailAccountConfig, accessToken: string): Promise<EmailConnectionTestResult> {
    const config = this.normalizeAndValidateConfig(input)
    if (accessToken.trim() === '') {
      return new EmailConnectionTestResult(false, 'Microsoft OAuth2 访问令牌为空', false, false)
    }
    return await this.testConnectionCredential(config, accessToken)
  }

  async saveOAuthConfig(input: EmailAccountConfig, refreshToken: string): Promise<EmailAccountConfig> {
    if (refreshToken.trim() === '') {
      throw new Error('Microsoft OAuth2 未返回 refresh token，请重新授权')
    }
    return await this.saveAuthorizedConfig(input, refreshToken)
  }

  async saveConfig(input: EmailAccountConfig, password: string): Promise<EmailAccountConfig> {
    if (input.authenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2) {
      throw new Error('Outlook 不支持密码认证，请完成 Microsoft OAuth2 授权')
    }
    if (password === '') {
      throw new Error('请输入邮箱授权码或应用专用密码')
    }
    return await this.saveAuthorizedConfig(input, password)
  }

  async clearAuthorization(): Promise<void> {
    const preferences = getPreferencesService()
    await getEmailSecretStorageService().remove()
    await preferences.remove(PreferenceKeys.EMAIL_ACCOUNT_SECRET)
    await preferences.remove(PreferenceKeys.EMAIL_ACCOUNT_CONFIG_JSON)
    this.config = new EmailAccountConfig()
  }

  async testConnection(input: EmailAccountConfig, password: string): Promise<EmailConnectionTestResult> {
    let config: EmailAccountConfig
    try {
      config = this.normalizeAndValidateConfig(input)
    } catch (error) {
      return new EmailConnectionTestResult(false, this.safeErrorMessage(error), false, false)
    }
    if (password === '') {
      return new EmailConnectionTestResult(false, '请输入邮箱授权码或应用专用密码', false, false)
    }
    if (config.authenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2) {
      return new EmailConnectionTestResult(false,
        'Outlook 已停用密码认证，请使用 Microsoft OAuth2 授权', false, false)
    }
    return await this.testConnectionCredential(config, password)
  }

  private async testConnectionCredential(config: EmailAccountConfig,
    credential: string): Promise<EmailConnectionTestResult> {
    let imapReady = false
    let smtpReady = false
    let imapMessage = ''
    let smtpMessage = ''
    const imap = new ImapSession()
    try {
      await imap.connect(config, credential)
      await imap.selectInbox()
      imapReady = true
    } catch (error) {
      imapMessage = this.safeErrorMessage(error)
    } finally {
      await imap.close()
    }
    try {
      smtpReady = await this.testSmtp(config, credential)
    } catch (error) {
      smtpMessage = this.safeErrorMessage(error)
    }
    const ok = imapReady && smtpReady
    const message = ok ? 'SMTP 与 IMAP 均已连接' :
      `IMAP：${imapReady ? '连接成功' : imapMessage || '连接失败'}；` +
      `SMTP：${smtpReady ? '连接成功' : smtpMessage || '连接失败'}`
    return new EmailConnectionTestResult(ok, message, smtpReady, imapReady)
  }

  async listMessages(request: EmailListRequest): Promise<EmailMessageSummary[]> {
    const account = await this.requireAccount()
    const imap = new ImapSession()
    try {
      await imap.connect(account.config, account.password)
      await imap.selectInbox()
      // IMAP SEARCH handles encoded subjects, MIME bodies and UTF-8 inconsistently across
      // providers. Only use it to select the date/unread window, then search decoded content
      // locally so Outlook, NetEase and generic IMAP accounts behave the same way.
      const criteria = this.buildMailboxWindowCriteria(request)
      const response = await imap.execute(`UID SEARCH ${criteria}`)
      const uids = this.parseSearchUids(response)
      const limit = Math.min(Math.max(Math.floor(request.limit), 1), 100)
      const newestUids = uids.slice().reverse()
      const hasLocalFilter = request.query.trim() !== '' || request.from.trim() !== ''
      if (hasLocalFilter) {
        return await this.searchMessagesLocally(imap, newestUids, request, limit)
      }
      const selectedUids = newestUids.slice(0, limit)
      const messages: EmailMessageSummary[] = []
      for (let i = 0; i < selectedUids.length; i++) {
        const uid = selectedUids[i]
        const fetchResponse = await imap.execute(
          `UID FETCH ${uid} (BODY.PEEK[HEADER.FIELDS (FROM TO SUBJECT DATE MESSAGE-ID)] FLAGS RFC822.SIZE)`
        )
        messages.push(this.parseSummary(uid, fetchResponse))
      }
      return messages
    } finally {
      await imap.close()
    }
  }

  private async searchMessagesLocally(imap: ImapSession, newestUids: string[], request: EmailListRequest,
    limit: number): Promise<EmailMessageSummary[]> {
    const messages: EmailMessageSummary[] = []
    const scanCount = Math.min(newestUids.length, EMAIL_LOCAL_SEARCH_MAX_MESSAGES)
    for (let offset = 0; offset < scanCount && messages.length < limit; offset += EMAIL_LOCAL_SEARCH_BATCH_SIZE) {
      const end = Math.min(offset + EMAIL_LOCAL_SEARCH_BATCH_SIZE, scanCount)
      const batchUids = newestUids.slice(offset, end)
      let previews: ImapMessagePreview[] = []
      try {
        previews = await imap.fetchMessagePreviews(batchUids, EMAIL_LOCAL_SEARCH_PREVIEW_BYTES)
      } catch (_batchError) {
        previews = await this.fetchMessagePreviewsIndividually(imap, batchUids)
      }
      for (let i = 0; i < batchUids.length && messages.length < limit; i++) {
        let preview = this.findMessagePreview(previews, batchUids[i])
        if (preview === null) {
          try {
            const raw = await imap.fetchRawMessage(batchUids[i])
            preview = new ImapMessagePreview(batchUids[i], raw, false, raw.length)
          } catch (_singleFetchError) {
            continue
          }
        }
        try {
          const detail = this.parseMessage(preview.uid, preview.raw)
          if (!this.matchesLocalEmailFilter(detail, request)) {
            continue
          }
          messages.push(this.summaryFromDetail(detail, preview))
        } catch (_parseError) {
          // A malformed or truncated message must not prevent the rest of the mailbox from
          // being searched.
        }
      }
    }
    return messages
  }

  private async fetchMessagePreviewsIndividually(imap: ImapSession,
    uids: string[]): Promise<ImapMessagePreview[]> {
    const previews: ImapMessagePreview[] = []
    for (let i = 0; i < uids.length; i++) {
      try {
        const raw = await imap.fetchRawMessage(uids[i])
        previews.push(new ImapMessagePreview(uids[i], raw, false, raw.length))
      } catch (_error) {}
    }
    return previews
  }

  private findMessagePreview(previews: ImapMessagePreview[], uid: string): ImapMessagePreview | null {
    for (let i = 0; i < previews.length; i++) {
      if (previews[i].uid === uid) {
        return previews[i]
      }
    }
    return null
  }

  private matchesLocalEmailFilter(detail: EmailMessageDetail, request: EmailListRequest): boolean {
    const fromFilter = this.normalizeEmailSearchText(request.from)
    if (fromFilter !== '' && !this.normalizeEmailSearchText(detail.from).includes(fromFilter)) {
      return false
    }
    const query = this.normalizeEmailSearchText(request.query)
    if (query === '') {
      return true
    }
    let searchable = `${detail.subject}\n${detail.from}\n${detail.to}\n${detail.cc}\n${detail.replyTo}\n${detail.bodyText}`
    for (let i = 0; i < detail.attachments.length; i++) {
      searchable += `\n${detail.attachments[i].name}`
    }
    const normalizedSearchable = this.normalizeEmailSearchText(searchable)
    const terms = query.split(' ')
    for (let i = 0; i < terms.length; i++) {
      if (terms[i] !== '' && !normalizedSearchable.includes(terms[i])) {
        return false
      }
    }
    return true
  }

  private normalizeEmailSearchText(value: string): string {
    return value.toLowerCase().replace(/\s+/g, ' ').trim()
  }

  private summaryFromDetail(detail: EmailMessageDetail, preview: ImapMessagePreview): EmailMessageSummary {
    const summary = new EmailMessageSummary(detail.uid)
    summary.messageId = detail.messageId
    summary.subject = detail.subject
    summary.from = detail.from
    summary.to = detail.to
    summary.date = detail.date
    summary.timestamp = detail.timestamp
    summary.unread = preview.unread
    summary.size = preview.size
    return summary
  }

  async fetchMessage(uid: string): Promise<EmailMessageDetail> {
    const account = await this.requireAccount()
    const imap = new ImapSession()
    try {
      await imap.connect(account.config, account.password)
      await imap.selectInbox()
      const raw = await imap.fetchRawMessage(uid)
      return this.parseMessage(uid, raw)
    } finally {
      await imap.close()
    }
  }

  async sendMessage(request: EmailSendRequest): Promise<EmailOperationResult> {
    const normalized = this.normalizeSendRequest(request)
    const account = await this.requireAccount()
    const client = new EmailSocketClient()
    try {
      await client.connect(account.config.smtpHost, account.config.smtpPort, account.config.smtpSecurity)
      await this.expectSmtpGreeting(client, 220)
      await this.smtpEhlo(client)
      if (account.config.smtpSecurity === EmailTransportSecurity.STARTTLS) {
        await this.smtpCommand(client, 'STARTTLS\r\n', [220])
        await client.upgradeToTls(account.config.smtpHost, account.config.smtpPort)
        await this.smtpEhlo(client)
      }
      await this.smtpAuthenticate(client, account.config.username, account.password,
        account.config.authenticationMethod)
      await this.smtpCommand(client, `MAIL FROM:<${account.config.emailAddress}>\r\n`, [250])
      const recipients = normalized.to.concat(normalized.cc).concat(normalized.bcc)
      for (let i = 0; i < recipients.length; i++) {
        await this.smtpCommand(client, `RCPT TO:<${recipients[i]}>\r\n`, [250, 251])
      }
      await this.smtpCommand(client, 'DATA\r\n', [354])
      const message = this.buildMimeMessage(account.config, normalized)
      await this.smtpCommand(client, `${this.dotStuff(message)}\r\n.\r\n`, [250])
      try {
        await this.smtpCommand(client, 'QUIT\r\n', [221])
      } catch (_error) {}
      return new EmailOperationResult(true, `邮件已发送至 ${normalized.to.join(', ')}`)
    } finally {
      await client.close()
    }
  }

  async importMessagesToKnowledge(uids: string[]): Promise<EmailImportResult> {
    const uniqueUids: string[] = []
    for (let i = 0; i < uids.length; i++) {
      const uid = uids[i].trim()
      if (/^[0-9]+$/.test(uid) && !uniqueUids.includes(uid)) {
        uniqueUids.push(uid)
      }
    }
    if (uniqueUids.length === 0) {
      return new EmailImportResult(false, '请先选择要导入的邮件')
    }
    this.ensureTempDirectory()
    let importedMessages = 0
    let importedDocuments = 0
    let failedParts = 0
    const failureDetails: string[] = []
    const account = await this.requireAccount()
    const knowledgeService = getKnowledgeDocumentService()
    const imap = new ImapSession()
    try {
      await imap.connect(account.config, account.password)
      await imap.selectInbox()
      for (let i = 0; i < uniqueUids.length; i++) {
        try {
          const raw = await imap.fetchRawMessage(uniqueUids[i])
          const detail = this.parseMessage(uniqueUids[i], raw)
          const attachmentKnowledge: EmailAttachmentKnowledgeContent[] = []
          let combinedAttachmentCharacters = 0
          for (let j = 0; j < detail.attachments.length; j++) {
            const attachment = detail.attachments[j]
            const extension = this.supportedKnowledgeExtension(
              attachment.name,
              attachment.mimeType,
              attachment.bytes
            )
            if (attachment.bytes.byteLength === 0) {
              failedParts += 1
              const message = '附件内容为空或传输编码无效'
              attachmentKnowledge.push(new EmailAttachmentKnowledgeContent(
                attachment.name, attachment.mimeType, '', false, message))
              this.appendImportFailure(failureDetails, `${attachment.name}：${message}`)
              continue
            }
            if (extension === '') {
              failedParts += 1
              const message = `知识库暂不支持该附件格式 (${attachment.mimeType || '未知类型'})`
              attachmentKnowledge.push(new EmailAttachmentKnowledgeContent(
                attachment.name, attachment.mimeType, '', false, message))
              this.appendImportFailure(failureDetails, `${attachment.name}：${message}`)
              continue
            }
            const attachmentName = this.buildImportName(
              detail,
              this.fileStem(attachment.name !== '' ? attachment.name : `附件${j + 1}`),
              extension
            )
            const attachmentPath = this.tempPath(`${Date.now()}_${i}_${j}_${attachmentName}`)
            let attachmentParsed = false
            try {
              this.writeBytes(attachmentPath, attachment.bytes)
              const remainingCharacters = EMAIL_MAX_COMBINED_ATTACHMENT_KNOWLEDGE_CHARACTERS -
                combinedAttachmentCharacters
              if (remainingCharacters <= 0) {
                const message = '已达到单封邮件的附件解析内容合并上限，当前附件未写入知识条目'
                attachmentKnowledge.push(new EmailAttachmentKnowledgeContent(
                  attachment.name, attachment.mimeType, '', true, message))
                this.appendImportFailure(failureDetails, `${attachment.name}：${message}`)
              } else {
                const previewLimit = Math.min(EMAIL_MAX_ATTACHMENT_KNOWLEDGE_CHARACTERS,
                  remainingCharacters)
                try {
                  const preview = await knowledgeService.extractFileTextPreview(
                    attachmentPath,
                    attachmentName,
                    previewLimit
                  )
                  attachmentKnowledge.push(new EmailAttachmentKnowledgeContent(
                    attachment.name,
                    attachment.mimeType,
                    preview.text,
                    preview.truncated,
                    preview.truncated ? '附件内容过长，以下为合并到邮件知识条目的节选' : ''
                  ))
                  combinedAttachmentCharacters += preview.text.length
                  attachmentParsed = true
                } catch (previewError) {
                  const message = `附件解析失败：${this.safeErrorMessage(previewError)}`
                  attachmentKnowledge.push(new EmailAttachmentKnowledgeContent(
                    attachment.name, attachment.mimeType, '', false, message))
                  this.appendImportFailure(failureDetails, `${attachment.name}：${message}`)
                }
              }
            } finally {
              this.removeFileQuietly(attachmentPath)
            }
            if (!attachmentParsed) {
              failedParts += 1
            }
          }
          const bodyName = this.buildImportName(detail, '正文及附件解析', '.md')
          const bodyPath = this.tempPath(`${Date.now()}_${i}_${bodyName}`)
          let bodyImported = false
          try {
            const markdown = this.buildKnowledgeMarkdown(detail, attachmentKnowledge)
            this.writeBytes(bodyPath, new util.TextEncoder().encodeInto(markdown))
            const bodyResult = await knowledgeService.importDocument(bodyPath, bodyName)
            bodyImported = bodyResult.ok
            if (!bodyResult.ok) {
              this.appendImportFailure(failureDetails, `${detail.subject} / 正文：${bodyResult.message}`)
            }
          } finally {
            this.removeFileQuietly(bodyPath)
          }
          if (bodyImported) {
            importedDocuments += 1
          } else {
            failedParts += 1
          }
          importedMessages += 1
        } catch (error) {
          failedParts += 1
          const detail = `邮件 UID ${uniqueUids[i]}：${this.safeErrorMessage(error)}`
          this.appendImportFailure(failureDetails, detail)
          console.warn('EmailService', `Email knowledge import failed: ${detail}`)
        }
      }
    } finally {
      await imap.close()
    }
    const ok = importedMessages > 0 && importedDocuments > 0
    const failureSuffix = failureDetails.length > 0 ? `。${failureDetails.join('；')}` : ''
    const message = failedParts === 0
      ? `已将 ${importedMessages} 封邮件的正文及附件解析内容加入知识库，共 ${importedDocuments} 个知识文件`
      : `已导入 ${importedMessages} 封邮件、${importedDocuments} 个知识文件；${failedParts} 个部分无法解析${failureSuffix}`
    return new EmailImportResult(ok, message, importedMessages, importedDocuments, failedParts)
  }

  async readForTool(action: string, request: EmailListRequest, uid: string): Promise<string> {
    const normalizedAction = action.trim().toLowerCase()
    if (normalizedAction === 'view' || normalizedAction === 'read') {
      const detail = await this.fetchMessage(uid)
      const output: EmailDetailToolOutput = {
        uid: detail.uid,
        messageId: detail.messageId,
        subject: detail.subject,
        from: detail.from,
        to: detail.to,
        cc: detail.cc,
        replyTo: detail.replyTo,
        date: detail.date,
        body: detail.bodyText.substring(0, EMAIL_MAX_TOOL_BODY_CHARACTERS),
        bodyTruncated: detail.bodyText.length > EMAIL_MAX_TOOL_BODY_CHARACTERS,
        attachments: await this.buildToolAttachmentOutputs(detail)
      }
      return JSON.stringify(output)
    }
    const messages = await this.listMessages(request)
    const output: EmailReadToolOutput = {
      account: this.config.emailAddress,
      messages: messages
    }
    return JSON.stringify(output)
  }

  private async requireAccount(): Promise<EmailAccountAuthorization> {
    const config = await this.loadConfig()
    if (!config.configured) {
      throw new Error('尚未配置邮箱，请先在设置中完成邮箱授权')
    }
    const encrypted = await getPreferencesService().getString(PreferenceKeys.EMAIL_ACCOUNT_SECRET, '')
    if (encrypted === '') {
      throw new Error('邮箱授权已失效，请重新配置')
    }
    const storedSecret = await getEmailSecretStorageService().decrypt(encrypted)
    if (storedSecret === '') {
      throw new Error('邮箱授权已失效，请重新配置')
    }
    if (config.authenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2) {
      const token = await this.refreshMicrosoftOAuthToken(config, storedSecret)
      if (token.refreshToken !== '' && token.refreshToken !== storedSecret) {
        await this.persistEncryptedSecret(token.refreshToken)
      }
      return new EmailAccountAuthorization(config, token.accessToken)
    }
    return new EmailAccountAuthorization(config, storedSecret)
  }

  private async saveAuthorizedConfig(input: EmailAccountConfig, secret: string): Promise<EmailAccountConfig> {
    const config = this.normalizeAndValidateConfig(input)
    try {
      await this.persistEncryptedSecret(secret)
      await getPreferencesService().setString(PreferenceKeys.EMAIL_ACCOUNT_CONFIG_JSON,
        JSON.stringify(this.toStoredJson(config)))
    } catch (error) {
      throw new Error(`服务器连接成功，但授权信息保存失败：${this.safeErrorMessage(error)}`)
    }
    this.config = config
    return config.copy()
  }

  private async persistEncryptedSecret(secret: string): Promise<void> {
    const encryptedSecret = await getEmailSecretStorageService().encrypt(secret)
    await getPreferencesService().setString(PreferenceKeys.EMAIL_ACCOUNT_SECRET, encryptedSecret)
  }

  private async readStoredConfig(): Promise<EmailAccountConfig> {
    const raw = await getPreferencesService().getString(PreferenceKeys.EMAIL_ACCOUNT_CONFIG_JSON, '')
    if (raw.trim() === '') {
      return new EmailAccountConfig()
    }
    try {
      const json = JSON.parse(raw) as StoredEmailAccountJson
      return this.normalizeAndValidateConfig(new EmailAccountConfig(
        json.emailAddress || '',
        json.displayName || '',
        json.username || '',
        json.smtpHost || '',
        json.smtpPort || 465,
        json.smtpSecurity || EmailTransportSecurity.SSL_TLS,
        json.imapHost || '',
        json.imapPort || 993,
        json.imapSecurity || EmailTransportSecurity.SSL_TLS,
        json.configured === true,
        json.authenticationMethod || EmailAuthenticationMethod.PASSWORD,
        json.oauthClientId || ''
      ))
    } catch (error) {
      console.warn('EmailService', `Stored mail account config is invalid: ${this.safeErrorMessage(error)}`)
      return new EmailAccountConfig()
    }
  }

  private toStoredJson(config: EmailAccountConfig): StoredEmailAccountJson {
    return {
      emailAddress: config.emailAddress,
      displayName: config.displayName,
      username: config.username,
      smtpHost: config.smtpHost,
      smtpPort: config.smtpPort,
      smtpSecurity: config.smtpSecurity,
      imapHost: config.imapHost,
      imapPort: config.imapPort,
      imapSecurity: config.imapSecurity,
      authenticationMethod: config.authenticationMethod,
      oauthClientId: config.oauthClientId,
      configured: true
    }
  }

  private normalizeAndValidateConfig(input: EmailAccountConfig): EmailAccountConfig {
    const config = input.copy()
    config.emailAddress = this.normalizeEmailAddress(config.emailAddress)
    config.displayName = this.sanitizeHeader(config.displayName).trim()
    config.username = this.sanitizeHeader(config.username).trim()
    config.smtpHost = this.normalizeHost(config.smtpHost)
    config.imapHost = this.normalizeHost(config.imapHost)
    config.smtpPort = this.normalizePort(config.smtpPort, 465)
    config.imapPort = this.normalizePort(config.imapPort, 993)
    config.smtpSecurity = this.normalizeSecurity(config.smtpSecurity)
    config.imapSecurity = this.normalizeSecurity(config.imapSecurity)
    config.authenticationMethod = config.authenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2
      ? EmailAuthenticationMethod.MICROSOFT_OAUTH2 : EmailAuthenticationMethod.PASSWORD
    config.oauthClientId = config.oauthClientId.trim()
    if (config.username === '') {
      config.username = config.emailAddress
    }
    if (config.smtpHost === '' || config.imapHost === '') {
      throw new Error('请填写 SMTP 与 IMAP 服务器地址')
    }
    if (config.authenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2) {
      this.validateOAuthClientId(config.oauthClientId)
    }
    config.configured = true
    return config
  }

  private normalizeHost(value: string): string {
    const host = value.trim().toLowerCase()
    if (host === '' || host.includes('/') || host.includes(':') || /\s/.test(host)) {
      return ''
    }
    return host
  }

  private normalizePort(value: number, fallback: number): number {
    const port = Number.isFinite(value) ? Math.floor(value) : fallback
    if (port < 1 || port > 65535) {
      throw new Error('邮件服务器端口必须在 1 到 65535 之间')
    }
    return port
  }

  private normalizeSecurity(value: string): string {
    return value === EmailTransportSecurity.STARTTLS
      ? EmailTransportSecurity.STARTTLS
      : EmailTransportSecurity.SSL_TLS
  }

  private validateOAuthClientId(value: string): void {
    if (!/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(
      value.trim())) {
      throw new Error('请输入有效的 Microsoft Entra 应用 Client ID')
    }
  }

  private async refreshMicrosoftOAuthToken(config: EmailAccountConfig,
    refreshToken: string): Promise<EmailOAuthTokenResult> {
    this.validateOAuthClientId(config.oauthClientId)
    const body = `grant_type=refresh_token&client_id=${encodeURIComponent(config.oauthClientId)}` +
      `&refresh_token=${encodeURIComponent(refreshToken)}` +
      `&scope=${encodeURIComponent(MICROSOFT_MAIL_SCOPES)}`
    const response = await getHttpService().post(MICROSOFT_TOKEN_URL, body,
      { 'Content-Type': 'application/x-www-form-urlencoded' }, { timeout: 30000 })
    const json = this.parseMicrosoftTokenResponse(response)
    if (!response.success || json.access_token === undefined) {
      throw new Error(this.microsoftOAuthError(json, response,
        'Microsoft OAuth2 授权已失效，请在设置中重新授权'))
    }
    const result = new EmailOAuthTokenResult()
    result.accessToken = json.access_token
    result.refreshToken = json.refresh_token || refreshToken
    return result
  }

  private parseMicrosoftDeviceCodeResponse(response: HttpResponse): MicrosoftDeviceCodeJson {
    try {
      return JSON.parse(response.data) as MicrosoftDeviceCodeJson
    } catch (_error) {
      return {}
    }
  }

  private parseMicrosoftTokenResponse(response: HttpResponse): MicrosoftTokenJson {
    try {
      return JSON.parse(response.data) as MicrosoftTokenJson
    } catch (_error) {
      return {}
    }
  }

  private microsoftOAuthError(json: MicrosoftDeviceCodeJson | MicrosoftTokenJson,
    response: HttpResponse, fallback: string): string {
    const description = json.error_description || ''
    if (description.trim() !== '') {
      return description.replace(/[\r\n]+/g, ' ').substring(0, 500)
    }
    if (json.error !== undefined && json.error !== '') {
      return `${fallback}：${json.error}`
    }
    if (response.errorMessage !== '') {
      return `${fallback}：${response.errorMessage}`
    }
    return fallback
  }

  private async waitMilliseconds(milliseconds: number): Promise<void> {
    await new Promise<void>((resolve): void => {
      setTimeout(resolve, milliseconds)
    })
  }

  private normalizeEmailAddress(value: string): string {
    const email = this.sanitizeHeader(value).trim()
    if (!/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(email)) {
      throw new Error('邮箱地址格式无效')
    }
    return email
  }

  private normalizeSendRequest(input: EmailSendRequest): EmailSendRequest {
    const request = new EmailSendRequest()
    request.to = this.normalizeRecipients(input.to)
    request.cc = this.normalizeRecipients(input.cc)
    request.bcc = this.normalizeRecipients(input.bcc)
    request.subject = this.sanitizeHeader(input.subject).trim()
    request.body = input.body
    request.replyTo = input.replyTo.trim() === '' ? '' : this.normalizeEmailAddress(input.replyTo)
    const recipientCount = request.to.length + request.cc.length + request.bcc.length
    if (request.to.length === 0) {
      throw new Error('至少需要一个收件人')
    }
    if (recipientCount > EMAIL_MAX_RECIPIENTS) {
      throw new Error(`单封邮件最多允许 ${EMAIL_MAX_RECIPIENTS} 个收件人`)
    }
    if (request.subject === '') {
      throw new Error('邮件主题不能为空')
    }
    if (request.body.trim() === '') {
      throw new Error('邮件正文不能为空')
    }
    if (request.body.length > EMAIL_MAX_SEND_BODY_CHARACTERS) {
      throw new Error('邮件正文超过 20 万字符限制')
    }
    return request
  }

  private normalizeRecipients(values: string[]): string[] {
    const result: string[] = []
    for (let i = 0; i < values.length; i++) {
      const email = this.normalizeEmailAddress(values[i])
      if (!result.includes(email)) {
        result.push(email)
      }
    }
    return result
  }

  private buildMailboxWindowCriteria(request: EmailListRequest): string {
    const conditions: string[] = []
    if (request.unreadOnly) {
      conditions.push('UNSEEN')
    }
    const sinceDays = Math.min(Math.max(Math.floor(request.sinceDays), 0), 3650)
    if (sinceDays > 0) {
      const date = new Date(Date.now() - sinceDays * 24 * 60 * 60 * 1000)
      conditions.push(`SINCE ${this.imapDate(date)}`)
    }
    return conditions.length > 0 ? conditions.join(' ') : 'ALL'
  }

  private parseSearchUids(response: string): string[] {
    const lines = response.split('\r\n')
    for (let i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('* SEARCH')) {
        continue
      }
      const values = lines[i].substring(8).trim().split(/\s+/)
      const result: string[] = []
      for (let j = 0; j < values.length; j++) {
        if (/^[0-9]+$/.test(values[j])) {
          result.push(values[j])
        }
      }
      return result
    }
    return []
  }

  private parseSummary(uid: string, response: string): EmailMessageSummary {
    const summary = new EmailMessageSummary(uid)
    const headers = this.parseHeaders(this.extractImapHeaderLiteral(response))
    summary.messageId = this.decodeHeaderValue(headers.get('message-id') || '')
    summary.subject = this.decodeHeaderValue(headers.get('subject') || '') || '(无主题)'
    summary.from = this.decodeHeaderValue(headers.get('from') || '')
    summary.to = this.decodeHeaderValue(headers.get('to') || '')
    summary.date = this.decodeHeaderValue(headers.get('date') || '')
    const timestamp = Date.parse(summary.date)
    summary.timestamp = Number.isNaN(timestamp) ? 0 : timestamp
    summary.unread = !response.includes('\\Seen')
    const sizeMatch = response.match(/RFC822\.SIZE\s+([0-9]+)/i)
    summary.size = sizeMatch !== null ? Number(sizeMatch[1]) : 0
    return summary
  }

  private extractImapHeaderLiteral(response: string): string {
    const marker = response.match(/\{[0-9]+\}\r\n/)
    if (marker === null || marker.index === undefined) {
      return ''
    }
    const start = marker.index + marker[0].length
    const end = response.indexOf('\r\n)\r\n', start)
    return end > start ? response.substring(start, end) : response.substring(start)
  }

  private parseMessage(uid: string, raw: string): EmailMessageDetail {
    const root = this.parseMimeEntity(raw)
    const parsed = new ParsedMimeMessage()
    this.walkMimeEntity(root, parsed)
    const detail = new EmailMessageDetail(uid)
    detail.messageId = this.decodeHeaderValue(root.headers.get('message-id') || '')
    detail.subject = this.decodeHeaderValue(root.headers.get('subject') || '') || '(无主题)'
    detail.from = this.decodeHeaderValue(root.headers.get('from') || '')
    detail.to = this.decodeHeaderValue(root.headers.get('to') || '')
    detail.cc = this.decodeHeaderValue(root.headers.get('cc') || '')
    detail.replyTo = this.decodeHeaderValue(root.headers.get('reply-to') || '')
    detail.date = this.decodeHeaderValue(root.headers.get('date') || '')
    const timestamp = Date.parse(detail.date)
    detail.timestamp = Number.isNaN(timestamp) ? 0 : timestamp
    const plainBody = parsed.textParts.join('\n\n').trim()
    detail.bodyText = plainBody !== '' ? plainBody : this.htmlToText(parsed.htmlParts.join('\n'))
    detail.attachments = parsed.attachments
    return detail
  }

  private parseMimeEntity(raw: string): MimeEntity {
    const normalized = raw.replace(/\r?\n/g, '\r\n')
    const split = normalized.indexOf('\r\n\r\n')
    const entity = new MimeEntity()
    if (split < 0) {
      entity.headers = this.parseHeaders(normalized)
      return entity
    }
    entity.headers = this.parseHeaders(normalized.substring(0, split))
    entity.body = normalized.substring(split + 4)
    return entity
  }

  private walkMimeEntity(entity: MimeEntity, parsed: ParsedMimeMessage): void {
    const contentTypeHeader = entity.headers.get('content-type') || 'text/plain; charset=utf-8'
    const mimeType = contentTypeHeader.split(';')[0].trim().toLowerCase()
    const boundary = this.headerParameter(contentTypeHeader, 'boundary')
    if (mimeType.startsWith('multipart/') && boundary !== '') {
      const parts = this.splitMultipart(entity.body, boundary)
      for (let i = 0; i < parts.length; i++) {
        this.walkMimeEntity(this.parseMimeEntity(parts[i]), parsed)
      }
      return
    }
    const disposition = entity.headers.get('content-disposition') || ''
    const fileName = this.decodeHeaderValue(
      this.headerParameter(disposition, 'filename') || this.headerParameter(contentTypeHeader, 'name')
    )
    const contentId = (entity.headers.get('content-id') || '').replace(/[<>]/g, '').trim()
    const isAttachment = disposition.toLowerCase().startsWith('attachment') || fileName !== '' ||
      mimeType.startsWith('image/')
    const transferEncoding = (entity.headers.get('content-transfer-encoding') || '').trim().toLowerCase()
    const bytes = this.decodeTransfer(entity.body, transferEncoding)
    if (isAttachment) {
      const safeName = fileName !== '' ? this.safeFileName(fileName) : this.fallbackAttachmentName(mimeType)
      parsed.attachments.push(new EmailAttachmentPart(
        safeName,
        mimeType,
        contentId,
        disposition.toLowerCase().startsWith('inline') || contentId !== '',
        bytes
      ))
      return
    }
    const charset = this.headerParameter(contentTypeHeader, 'charset') || 'utf-8'
    const text = this.decodeBytes(bytes, charset).trim()
    if (text === '') {
      return
    }
    if (mimeType === 'text/html') {
      parsed.htmlParts.push(text)
    } else if (mimeType.startsWith('text/')) {
      parsed.textParts.push(text)
    }
  }

  private parseHeaders(block: string): Map<string, string> {
    const headers = new Map<string, string>()
    const unfolded = block.replace(/\r\n[\t ]+/g, ' ')
    const lines = unfolded.split('\r\n')
    for (let i = 0; i < lines.length; i++) {
      const colon = lines[i].indexOf(':')
      if (colon <= 0) {
        continue
      }
      const name = lines[i].substring(0, colon).trim().toLowerCase()
      const value = lines[i].substring(colon + 1).trim()
      const previous = headers.get(name)
      headers.set(name, previous === undefined ? value : `${previous}, ${value}`)
    }
    return headers
  }

  private headerParameter(header: string, name: string): string {
    const parameters = this.parseHeaderParameters(header)
    const normalizedName = name.trim().toLowerCase()
    let continuation = ''
    let continuationFound = false
    let continuationEncoded = false
    for (let index = 0; index < 32; index++) {
      const encodedKey = `${normalizedName}*${index}*`
      const plainKey = `${normalizedName}*${index}`
      const encodedPart = parameters.get(encodedKey)
      const plainPart = parameters.get(plainKey)
      if (encodedPart === undefined && plainPart === undefined) {
        break
      }
      continuationFound = true
      if (encodedPart !== undefined) {
        continuation += encodedPart
        continuationEncoded = true
      } else if (plainPart !== undefined) {
        continuation += plainPart
      }
    }
    if (continuationFound) {
      return continuationEncoded ? this.decodeExtendedHeaderParameter(continuation) : continuation
    }
    const extended = parameters.get(`${normalizedName}*`)
    if (extended !== undefined) {
      return this.decodeExtendedHeaderParameter(extended)
    }
    return parameters.get(normalizedName) || ''
  }

  private parseHeaderParameters(header: string): Map<string, string> {
    const parameters = new Map<string, string>()
    const segments = this.splitHeaderParameterSegments(header)
    for (let index = 1; index < segments.length; index++) {
      const segment = segments[index]
      const equals = segment.indexOf('=')
      if (equals <= 0) {
        continue
      }
      const key = segment.substring(0, equals).trim().toLowerCase()
      let value = segment.substring(equals + 1).trim()
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1).replace(/\\"/g, '"').replace(/\\\\/g, '\\')
      }
      if (key !== '') {
        parameters.set(key, value)
      }
    }
    return parameters
  }

  private splitHeaderParameterSegments(header: string): string[] {
    const segments: string[] = []
    let current = ''
    let quoted = false
    let escaped = false
    for (let index = 0; index < header.length; index++) {
      const character = header[index]
      if (escaped) {
        current += character
        escaped = false
        continue
      }
      if (quoted && character === '\\') {
        current += character
        escaped = true
        continue
      }
      if (character === '"') {
        quoted = !quoted
        current += character
        continue
      }
      if (character === ';' && !quoted) {
        segments.push(current.trim())
        current = ''
        continue
      }
      current += character
    }
    segments.push(current.trim())
    return segments
  }

  private decodeExtendedHeaderParameter(value: string): string {
    let encoded = value.trim()
    let charset = 'utf-8'
    const firstQuote = encoded.indexOf("'")
    const secondQuote = firstQuote < 0 ? -1 : encoded.indexOf("'", firstQuote + 1)
    if (firstQuote > 0 && secondQuote > firstQuote) {
      charset = encoded.substring(0, firstQuote).trim() || 'utf-8'
      encoded = encoded.substring(secondQuote + 1)
    }
    try {
      return this.decodeBytes(this.decodePercentEncodedBytes(encoded), charset)
    } catch (_error) {
      return encoded
    }
  }

  private decodePercentEncodedBytes(value: string): Uint8Array {
    const bytes: number[] = []
    for (let index = 0; index < value.length; index++) {
      if (value[index] === '%' && index + 2 < value.length &&
        /^[0-9A-Fa-f]{2}$/.test(value.substring(index + 1, index + 3))) {
        bytes.push(parseInt(value.substring(index + 1, index + 3), 16))
        index += 2
        continue
      }
      const encoded = new util.TextEncoder().encodeInto(value[index])
      for (let byteIndex = 0; byteIndex < encoded.length; byteIndex++) {
        bytes.push(encoded[byteIndex])
      }
    }
    return new Uint8Array(bytes)
  }

  private splitMultipart(body: string, boundary: string): string[] {
    const delimiter = `--${boundary}`
    const rawParts = body.split(delimiter)
    const parts: string[] = []
    for (let i = 1; i < rawParts.length; i++) {
      let part = rawParts[i]
      if (part.startsWith('--')) {
        break
      }
      part = part.replace(/^\r\n/, '').replace(/\r\n$/, '')
      if (part.trim() !== '') {
        parts.push(part)
      }
    }
    return parts
  }

  private decodeTransfer(body: string, encoding: string): Uint8Array {
    if (encoding.startsWith('base64')) {
      try {
        let compact = body.replace(/[^A-Za-z0-9+/=]/g, '')
        const remainder = compact.length % 4
        if (remainder > 0) {
          compact += '='.repeat(4 - remainder)
        }
        return new util.Base64Helper().decodeSync(compact)
      } catch (_error) {
        return new Uint8Array(0)
      }
    }
    if (encoding.startsWith('quoted-printable')) {
      return this.decodeQuotedPrintableBytes(body)
    }
    return this.binaryStringToBytes(body.replace(/\r\n$/, ''))
  }

  private decodeQuotedPrintableBytes(input: string): Uint8Array {
    const source = input.replace(/=\r\n/g, '')
    const bytes: number[] = []
    for (let i = 0; i < source.length; i++) {
      if (source[i] === '=' && i + 2 < source.length && /^[0-9A-Fa-f]{2}$/.test(source.substring(i + 1, i + 3))) {
        bytes.push(parseInt(source.substring(i + 1, i + 3), 16))
        i += 2
      } else {
        const code = source.charCodeAt(i)
        if (code <= 0xFF) {
          bytes.push(code)
        } else {
          const encoded = new util.TextEncoder().encodeInto(source[i])
          for (let j = 0; j < encoded.length; j++) {
            bytes.push(encoded[j])
          }
        }
      }
    }
    return new Uint8Array(bytes)
  }

  private binaryStringToBytes(value: string): Uint8Array {
    const bytes = new Uint8Array(value.length)
    for (let index = 0; index < value.length; index++) {
      bytes[index] = value.charCodeAt(index) & 0xFF
    }
    return bytes
  }

  private decodeHeaderValue(value: string): string {
    const pattern = /=\?([^?]+)\?([bBqQ])\?([^?]*)\?=/g
    let result = ''
    let lastIndex = 0
    let decodedWordSeen = false
    let match = pattern.exec(value)
    while (match !== null) {
      const between = value.substring(lastIndex, match.index)
      if (!decodedWordSeen || between.trim() !== '') {
        result += between
      }
      let bytes: Uint8Array
      if (match[2].toLowerCase() === 'b') {
        try {
          bytes = new util.Base64Helper().decodeSync(match[3])
        } catch (_error) {
          bytes = new Uint8Array(0)
        }
      } else {
        bytes = this.decodeQuotedPrintableBytes(match[3].replace(/_/g, ' '))
      }
      result += this.decodeBytes(bytes, match[1])
      decodedWordSeen = true
      lastIndex = match.index + match[0].length
      match = pattern.exec(value)
    }
    result += value.substring(lastIndex)
    return this.decodeRawUtf8Header(result.trim())
  }

  private decodeRawUtf8Header(value: string): string {
    let hasHighByte = false
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index)
      if (code > 0xFF) {
        return value
      }
      if (code >= 0x80) {
        hasHighByte = true
      }
    }
    if (!hasHighByte) {
      return value
    }
    const decoded = this.decodeBytes(this.binaryStringToBytes(value), 'utf-8')
    return decoded.includes('\uFFFD') ? value : decoded
  }

  private decodeBytes(bytes: Uint8Array, charset: string): string {
    const normalized = charset.trim().toLowerCase().replace(/["']/g, '') || 'utf-8'
    try {
      return util.TextDecoder.create(normalized).decodeToString(bytes, { stream: false })
    } catch (_error) {
      return util.TextDecoder.create('utf-8').decodeToString(bytes, { stream: false })
    }
  }

  private htmlToText(html: string): string {
    return html
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<(br|\/p|\/div|\/li|\/tr|h[1-6])\b[^>]*>/gi, '\n')
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/gi, ' ')
      .replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"')
      .replace(/&#39;/gi, "'")
      .replace(/[\t ]+\n/g, '\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim()
  }

  private async testSmtp(config: EmailAccountConfig, password: string): Promise<boolean> {
    const client = new EmailSocketClient()
    try {
      await client.connect(config.smtpHost, config.smtpPort, config.smtpSecurity)
      await this.expectSmtpGreeting(client, 220)
      await this.smtpEhlo(client)
      if (config.smtpSecurity === EmailTransportSecurity.STARTTLS) {
        await this.smtpCommand(client, 'STARTTLS\r\n', [220])
        await client.upgradeToTls(config.smtpHost, config.smtpPort)
        await this.smtpEhlo(client)
      }
      await this.smtpAuthenticate(client, config.username, password, config.authenticationMethod)
      try {
        await this.smtpCommand(client, 'QUIT\r\n', [221])
      } catch (_error) {}
      return true
    } finally {
      await client.close()
    }
  }

  private async expectSmtpGreeting(client: EmailSocketClient, code: number): Promise<string> {
    const response = await client.waitFor((value: string): boolean => this.hasSmtpFinalCode(value, [code]))
    this.assertSmtpCode(response, [code])
    return response
  }

  private async smtpEhlo(client: EmailSocketClient): Promise<void> {
    await this.smtpCommand(client, 'EHLO chatcube.local\r\n', [250])
  }

  private async smtpAuthenticate(client: EmailSocketClient, username: string, credential: string,
    authenticationMethod: string): Promise<void> {
    const base64 = new util.Base64Helper()
    if (authenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2) {
      const raw = `user=${username}\u0001auth=Bearer ${credential}\u0001\u0001`
      const payload = base64.encodeToStringSync(new util.TextEncoder().encodeInto(raw))
      const response = await client.command(`AUTH XOAUTH2 ${payload}\r\n`, (value: string): boolean => {
        return this.hasSmtpFinalCode(value, [235]) || /(?:^|\r\n)334 /.test(value) ||
          /(?:^|\r\n)[45][0-9]{2} /.test(value)
      })
      if (this.hasSmtpFinalCode(response, [235])) {
        return
      }
      if (/(?:^|\r\n)334 /.test(response)) {
        try {
          await client.command('\r\n', (value: string): boolean => /(?:^|\r\n)[45][0-9]{2} /.test(value))
        } catch (_error) {}
        throw new Error('Microsoft SMTP OAuth2 认证失败，请重新授权并确认已启用 SMTP AUTH')
      }
      this.assertSmtpCode(response, [235])
      return
    }
    await this.smtpCommand(client, 'AUTH LOGIN\r\n', [334])
    await this.smtpCommand(client,
      `${base64.encodeToStringSync(new util.TextEncoder().encodeInto(username))}\r\n`, [334])
    await this.smtpCommand(client,
      `${base64.encodeToStringSync(new util.TextEncoder().encodeInto(credential))}\r\n`, [235])
  }

  private async smtpCommand(client: EmailSocketClient, command: string, expectedCodes: number[]): Promise<string> {
    const response = await client.command(command, (value: string): boolean => {
      if (this.hasSmtpFinalCode(value, expectedCodes)) {
        return true
      }
      return /(?:^|\r\n)[45][0-9]{2} /.test(value)
    })
    this.assertSmtpCode(response, expectedCodes)
    return response
  }

  private hasSmtpFinalCode(response: string, codes: number[]): boolean {
    for (let i = 0; i < codes.length; i++) {
      const code = `${codes[i]}`
      if (response.startsWith(`${code} `) || response.includes(`\r\n${code} `)) {
        return true
      }
    }
    return false
  }

  private assertSmtpCode(response: string, codes: number[]): void {
    if (this.hasSmtpFinalCode(response, codes)) {
      return
    }
    const lines = response.trim().split('\r\n')
    const lastLine = lines.length > 0 ? lines[lines.length - 1] : 'SMTP 请求失败'
    throw new Error(lastLine.substring(0, 240))
  }

  private buildMimeMessage(config: EmailAccountConfig, request: EmailSendRequest): string {
    const headers: string[] = []
    const fromName = config.displayName === '' ? '' : `${this.encodeHeader(config.displayName)} `
    headers.push(`From: ${fromName}<${config.emailAddress}>`)
    headers.push(`To: ${request.to.join(', ')}`)
    if (request.cc.length > 0) {
      headers.push(`Cc: ${request.cc.join(', ')}`)
    }
    if (request.replyTo !== '') {
      headers.push(`Reply-To: ${request.replyTo}`)
    }
    headers.push(`Subject: ${this.encodeHeader(request.subject)}`)
    headers.push(`Date: ${new Date().toUTCString()}`)
    headers.push(`Message-ID: <chatcube-${Date.now()}-${Math.floor(Math.random() * 1000000)}@local>`)
    headers.push('MIME-Version: 1.0')
    headers.push('Content-Type: text/plain; charset=UTF-8')
    headers.push('Content-Transfer-Encoding: base64')
    const bodyBase64 = new util.Base64Helper().encodeToStringSync(
      new util.TextEncoder().encodeInto(request.body.replace(/\r?\n/g, '\r\n'))
    )
    return `${headers.join('\r\n')}\r\n\r\n${this.wrapBase64(bodyBase64)}`
  }

  private encodeHeader(value: string): string {
    const safe = this.sanitizeHeader(value)
    if (/^[\x20-\x7E]*$/.test(safe)) {
      return safe
    }
    const base64 = new util.Base64Helper().encodeToStringSync(new util.TextEncoder().encodeInto(safe))
    return `=?UTF-8?B?${base64}?=`
  }

  private wrapBase64(value: string): string {
    const lines: string[] = []
    for (let i = 0; i < value.length; i += 76) {
      lines.push(value.substring(i, Math.min(value.length, i + 76)))
    }
    return lines.join('\r\n')
  }

  private dotStuff(message: string): string {
    return message.replace(/(^|\r\n)\./g, '$1..')
  }

  private sanitizeHeader(value: string): string {
    return value.replace(/[\r\n]+/g, ' ')
  }

  private imapDate(date: Date): string {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
    return `${date.getDate().toString().padStart(2, '0')}-${months[date.getMonth()]}-${date.getFullYear()}`
  }

  private fallbackAttachmentName(mimeType: string): string {
    const extension = this.extensionForMimeType(mimeType)
    return `attachment${extension !== '' ? extension : '.bin'}`
  }

  private extensionForMimeType(mimeType: string): string {
    const normalized = mimeType.split(';')[0].trim().toLowerCase()
    const values: Record<string, string> = {
      'image/jpeg': '.jpg',
      'image/jpg': '.jpg',
      'image/png': '.png',
      'image/webp': '.webp',
      'image/bmp': '.bmp',
      'application/pdf': '.pdf',
      'application/x-pdf': '.pdf',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document': '.docx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': '.xlsx',
      'text/plain': '.txt',
      'text/markdown': '.md',
      'text/x-markdown': '.md',
      'application/markdown': '.md',
      'text/csv': '.csv',
      'text/tab-separated-values': '.tsv',
      'application/json': '.json',
      'text/json': '.json',
      'application/xml': '.xml',
      'text/xml': '.xml',
      'application/yaml': '.yaml',
      'text/yaml': '.yaml',
      'text/html': '.html'
    }
    return values[normalized] || ''
  }

  private supportedKnowledgeExtension(name: string, mimeType: string, bytes: Uint8Array): string {
    const lower = name.toLowerCase()
    const supported = ['.markdown', '.jpeg', '.docx', '.xlsx', '.html', '.json', '.yaml', '.pdf',
      '.csv', '.tsv', '.xml', '.yml', '.htm', '.log', '.txt', '.jpg', '.png', '.webp', '.bmp', '.md']
    for (let i = 0; i < supported.length; i++) {
      if (lower.endsWith(supported[i])) {
        return supported[i]
      }
    }
    const mimeExtension = this.extensionForMimeType(mimeType)
    return mimeExtension !== '' ? mimeExtension : this.detectKnowledgeExtension(bytes)
  }

  private detectKnowledgeExtension(bytes: Uint8Array): string {
    if (bytes.byteLength >= 5 && bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 &&
      bytes[3] === 0x46 && bytes[4] === 0x2D) {
      return '.pdf'
    }
    if (bytes.byteLength >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E &&
      bytes[3] === 0x47 && bytes[4] === 0x0D && bytes[5] === 0x0A && bytes[6] === 0x1A && bytes[7] === 0x0A) {
      return '.png'
    }
    if (bytes.byteLength >= 3 && bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) {
      return '.jpg'
    }
    if (bytes.byteLength >= 2 && bytes[0] === 0x42 && bytes[1] === 0x4D) {
      return '.bmp'
    }
    if (bytes.byteLength >= 12 && this.matchesAsciiAt(bytes, 0, 'RIFF') &&
      this.matchesAsciiAt(bytes, 8, 'WEBP')) {
      return '.webp'
    }
    if (bytes.byteLength >= 4 && bytes[0] === 0x50 && bytes[1] === 0x4B &&
      (bytes[2] === 0x03 || bytes[2] === 0x05 || bytes[2] === 0x07)) {
      if (this.containsAscii(bytes, 'word/document.xml')) {
        return '.docx'
      }
      if (this.containsAscii(bytes, 'xl/workbook.xml')) {
        return '.xlsx'
      }
    }
    return ''
  }

  private containsAscii(bytes: Uint8Array, value: string): boolean {
    if (value === '' || bytes.byteLength < value.length) {
      return false
    }
    for (let offset = 0; offset <= bytes.byteLength - value.length; offset++) {
      if (this.matchesAsciiAt(bytes, offset, value)) {
        return true
      }
    }
    return false
  }

  private matchesAsciiAt(bytes: Uint8Array, offset: number, value: string): boolean {
    if (offset < 0 || offset + value.length > bytes.byteLength) {
      return false
    }
    for (let index = 0; index < value.length; index++) {
      if (bytes[offset + index] !== value.charCodeAt(index)) {
        return false
      }
    }
    return true
  }

  private buildKnowledgeMarkdown(detail: EmailMessageDetail,
    attachmentKnowledge: EmailAttachmentKnowledgeContent[] = []): string {
    const attachmentLines: string[] = []
    for (let i = 0; i < detail.attachments.length; i++) {
      const item = detail.attachments[i]
      attachmentLines.push(`- ${item.name} (${item.mimeType || 'application/octet-stream'}, ` +
        `${item.bytes.byteLength} bytes${item.inline ? ', 内嵌图片' : ''})`)
    }
    const lines: string[] = [
      `# ${detail.subject}`,
      '',
      `- 发件人：${detail.from}`,
      `- 收件人：${detail.to}`,
      detail.cc !== '' ? `- 抄送：${detail.cc}` : '',
      `- 日期：${detail.date}`,
      detail.messageId !== '' ? `- Message-ID：${detail.messageId}` : '',
      '',
      '## 正文',
      '',
      detail.bodyText.trim() !== '' ? detail.bodyText : '(无可解析正文)',
      '',
      '## 附件与内嵌图片',
      '',
      attachmentLines.length > 0 ? attachmentLines.join('\n') : '(无附件)'
    ]
    if (attachmentKnowledge.length > 0) {
      lines.push('', '## 附件解析内容')
      for (let index = 0; index < attachmentKnowledge.length; index++) {
        const item = attachmentKnowledge[index]
        lines.push('', `### 附件 ${index + 1}：${this.markdownHeadingText(item.name)}`)
        lines.push('', `类型：${item.mimeType || 'application/octet-stream'}`)
        if (item.message !== '') {
          lines.push('', `解析说明：${item.message}`)
        }
        if (item.text.trim() !== '') {
          lines.push('', item.text.trim())
        } else {
          lines.push('', '(没有可合并的附件文字)')
        }
      }
    }
    return lines.filter((line: string, index: number): boolean => line !== '' ||
      (index > 0 && lines[index - 1] !== '')).join('\n')
  }

  private async buildToolAttachmentOutputs(detail: EmailMessageDetail): Promise<EmailToolAttachmentOutput[]> {
    const outputs: EmailToolAttachmentOutput[] = []
    if (detail.attachments.length === 0) {
      return outputs
    }
    this.ensureTempDirectory()
    const knowledgeService = getKnowledgeDocumentService()
    let combinedCharacters = 0
    for (let index = 0; index < detail.attachments.length; index++) {
      const item = detail.attachments[index]
      const displayName = item.name.trim() !== '' ? item.name : `附件${index + 1}`
      const output: EmailToolAttachmentOutput = {
        name: displayName,
        mimeType: item.mimeType,
        inline: item.inline,
        size: item.bytes.byteLength,
        parsedText: '',
        parsedTextTruncated: false,
        parseStatus: ''
      }
      if (item.bytes.byteLength === 0) {
        output.parseStatus = '附件内容为空或传输编码无效'
        outputs.push(output)
        continue
      }
      const extension = this.supportedKnowledgeExtension(displayName, item.mimeType, item.bytes)
      if (extension === '') {
        output.parseStatus = `暂不支持解析此附件格式 (${item.mimeType || '未知类型'})`
        outputs.push(output)
        continue
      }
      const remainingCharacters = EMAIL_MAX_COMBINED_TOOL_ATTACHMENT_CHARACTERS - combinedCharacters
      if (remainingCharacters < 1000) {
        output.parsedTextTruncated = true
        output.parseStatus = '已达到本次邮件读取的附件解析内容上限'
        outputs.push(output)
        continue
      }
      const attachmentName = this.buildImportName(
        detail,
        this.fileStem(displayName),
        extension
      )
      const attachmentPath = this.tempPath(`tool_${Date.now()}_${index}_${attachmentName}`)
      try {
        this.writeBytes(attachmentPath, item.bytes)
        const previewLimit = Math.min(EMAIL_MAX_TOOL_ATTACHMENT_CHARACTERS, remainingCharacters)
        const preview = await knowledgeService.extractFileTextPreview(
          attachmentPath,
          attachmentName,
          previewLimit
        )
        output.parsedText = preview.text
        output.parsedTextTruncated = preview.truncated
        output.parseStatus = preview.truncated ? '附件解析成功，返回内容为节选' : '附件解析成功'
        combinedCharacters += preview.text.length
      } catch (error) {
        output.parseStatus = `附件解析失败：${this.safeErrorMessage(error)}`
      } finally {
        this.removeFileQuietly(attachmentPath)
      }
      outputs.push(output)
    }
    return outputs
  }

  private markdownHeadingText(value: string): string {
    return value.replace(/[\r\n#]+/g, ' ').trim() || '未命名附件'
  }

  private buildImportName(detail: EmailMessageDetail, partName: string, extension: string): string {
    const subject = this.safeFileName(detail.subject).substring(0, 64) || '无主题'
    const part = this.safeFileName(partName).substring(0, 48) || '内容'
    return `邮件-${subject}-${part}${extension}`
  }

  private fileStem(name: string): string {
    const safe = this.safeFileName(name)
    const dot = safe.lastIndexOf('.')
    return dot > 0 ? safe.substring(0, dot) : safe
  }

  private safeFileName(value: string): string {
    const normalized = value.replace(/[\\/:*?"<>|\u0000-\u001F]/g, '_').replace(/\s+/g, ' ').trim()
    return normalized === '' ? 'attachment' : normalized.substring(0, 120)
  }

  private ensureTempDirectory(): void {
    const context = this.context
    if (context === null) {
      return
    }
    const emailDirectory = `${context.filesDir}/email`
    const tempDirectory = `${context.filesDir}/${EMAIL_IMPORT_TEMP_DIRECTORY}`
    try {
      fileIo.mkdirSync(emailDirectory)
    } catch (_error) {}
    try {
      fileIo.mkdirSync(tempDirectory)
    } catch (_error) {}
  }

  private tempPath(fileName: string): string {
    const context = this.context
    if (context === null) {
      throw new Error('邮件服务尚未初始化')
    }
    return `${context.filesDir}/${EMAIL_IMPORT_TEMP_DIRECTORY}/${this.safeFileName(fileName)}`
  }

  private writeBytes(path: string, bytes: Uint8Array): void {
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
    try {
      let offset = 0
      while (offset < bytes.byteLength) {
        const end = Math.min(bytes.byteLength, offset + 256 * 1024)
        const chunk = bytes.buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + end)
        const written = fileIo.writeSync(file.fd, chunk)
        if (written <= 0) {
          throw new Error(`附件写入不完整：期望 ${bytes.byteLength} 字节，实际 ${offset} 字节`)
        }
        offset += written
      }
      const stat = fileIo.statSync(file.fd)
      if (stat.size !== bytes.byteLength) {
        throw new Error(`附件写入校验失败：期望 ${bytes.byteLength} 字节，实际 ${stat.size} 字节`)
      }
    } finally {
      fileIo.closeSync(file)
    }
  }

  private removeFileQuietly(path: string): void {
    try {
      if (fileIo.accessSync(path)) {
        fileIo.unlinkSync(path)
      }
    } catch (_error) {}
  }

  private appendImportFailure(details: string[], value: string): void {
    if (details.length >= 3) {
      return
    }
    const normalized = value.replace(/[\r\n]+/g, ' ').trim()
    if (normalized !== '') {
      details.push(normalized.substring(0, 240))
    }
  }

  private safeErrorMessage(error: Object): string {
    if (error instanceof Error && error.message.trim() !== '') {
      return error.message
    }
    try {
      const serialized = JSON.stringify(error)
      const json = JSON.parse(serialized) as Record<string, Object>
      if (json.code === 2301115) {
        return '网络协议栈正在完成上一项邮件操作，请稍后重试'
      }
      if (json.message !== undefined && `${json.message}`.trim() !== '') {
        return json.code !== undefined ? `${json.message} (${json.code})` : `${json.message}`
      }
      return serialized !== '{}' ? serialized : '邮件操作失败'
    } catch (_serializationError) {
      return '邮件操作失败'
    }
  }
}

export function getEmailService(): EmailService {
  return EmailService.getInstance()
}
