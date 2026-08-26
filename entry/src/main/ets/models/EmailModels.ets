export enum EmailTransportSecurity {
  SSL_TLS = 'ssl_tls',
  STARTTLS = 'starttls'
}

export enum EmailAuthenticationMethod {
  PASSWORD = 'password',
  MICROSOFT_OAUTH2 = 'microsoft_oauth2'
}

export class EmailAccountConfig {
  emailAddress: string = ''
  displayName: string = ''
  username: string = ''
  smtpHost: string = ''
  smtpPort: number = 465
  smtpSecurity: string = EmailTransportSecurity.SSL_TLS
  imapHost: string = ''
  imapPort: number = 993
  imapSecurity: string = EmailTransportSecurity.SSL_TLS
  authenticationMethod: string = EmailAuthenticationMethod.PASSWORD
  oauthClientId: string = ''
  configured: boolean = false

  constructor(
    emailAddress: string = '',
    displayName: string = '',
    username: string = '',
    smtpHost: string = '',
    smtpPort: number = 465,
    smtpSecurity: string = EmailTransportSecurity.SSL_TLS,
    imapHost: string = '',
    imapPort: number = 993,
    imapSecurity: string = EmailTransportSecurity.SSL_TLS,
    configured: boolean = false,
    authenticationMethod: string = EmailAuthenticationMethod.PASSWORD,
    oauthClientId: string = ''
  ) {
    this.emailAddress = emailAddress
    this.displayName = displayName
    this.username = username
    this.smtpHost = smtpHost
    this.smtpPort = smtpPort
    this.smtpSecurity = smtpSecurity
    this.imapHost = imapHost
    this.imapPort = imapPort
    this.imapSecurity = imapSecurity
    this.authenticationMethod = authenticationMethod
    this.oauthClientId = oauthClientId
    this.configured = configured
  }

  copy(): EmailAccountConfig {
    return new EmailAccountConfig(
      this.emailAddress,
      this.displayName,
      this.username,
      this.smtpHost,
      this.smtpPort,
      this.smtpSecurity,
      this.imapHost,
      this.imapPort,
      this.imapSecurity,
      this.configured,
      this.authenticationMethod,
      this.oauthClientId
    )
  }
}

export class EmailOAuthDeviceAuthorization {
  deviceCode: string = ''
  userCode: string = ''
  verificationUri: string = ''
  verificationUriComplete: string = ''
  expiresInSeconds: number = 0
  pollingIntervalSeconds: number = 5
}

export class EmailOAuthTokenResult {
  accessToken: string = ''
  refreshToken: string = ''
}

export class EmailMessageSummary {
  uid: string = ''
  messageId: string = ''
  subject: string = ''
  from: string = ''
  to: string = ''
  date: string = ''
  timestamp: number = 0
  unread: boolean = false
  size: number = 0

  constructor(uid: string = '') {
    this.uid = uid
  }
}

export class EmailAttachmentPart {
  name: string = ''
  mimeType: string = ''
  contentId: string = ''
  inline: boolean = false
  bytes: Uint8Array = new Uint8Array(0)

  constructor(
    name: string = '',
    mimeType: string = '',
    contentId: string = '',
    inline: boolean = false,
    bytes: Uint8Array = new Uint8Array(0)
  ) {
    this.name = name
    this.mimeType = mimeType
    this.contentId = contentId
    this.inline = inline
    this.bytes = bytes
  }
}

export class EmailMessageDetail extends EmailMessageSummary {
  cc: string = ''
  replyTo: string = ''
  bodyText: string = ''
  attachments: EmailAttachmentPart[] = []

  constructor(uid: string = '') {
    super(uid)
  }
}

export class EmailListRequest {
  query: string = ''
  from: string = ''
  unreadOnly: boolean = false
  sinceDays: number = 30
  limit: number = 20
}

export class EmailSendRequest {
  to: string[] = []
  cc: string[] = []
  bcc: string[] = []
  subject: string = ''
  body: string = ''
  replyTo: string = ''
}

export class EmailOperationResult {
  ok: boolean = false
  message: string = ''

  constructor(ok: boolean = false, message: string = '') {
    this.ok = ok
    this.message = message
  }
}

export class EmailImportResult extends EmailOperationResult {
  importedMessages: number = 0
  importedDocuments: number = 0
  failedParts: number = 0

  constructor(
    ok: boolean = false,
    message: string = '',
    importedMessages: number = 0,
    importedDocuments: number = 0,
    failedParts: number = 0
  ) {
    super(ok, message)
    this.importedMessages = importedMessages
    this.importedDocuments = importedDocuments
    this.failedParts = failedParts
  }
}

export class EmailConnectionTestResult extends EmailOperationResult {
  smtpReady: boolean = false
  imapReady: boolean = false

  constructor(ok: boolean = false, message: string = '', smtpReady: boolean = false,
    imapReady: boolean = false) {
    super(ok, message)
    this.smtpReady = smtpReady
    this.imapReady = imapReady
  }
}
