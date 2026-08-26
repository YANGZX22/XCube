import { uiMaterial } from '@kit.ArkUI'
import { common, Want } from '@kit.AbilityKit'
import {
  EmailAccountConfig,
  EmailAuthenticationMethod,
  EmailConnectionTestResult,
  EmailOAuthDeviceAuthorization,
  EmailOAuthTokenResult,
  EmailTransportSecurity
} from '../models/EmailModels'
import { EmailService } from '../services/EmailService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { getAppUiState } from '../state/AppUiState'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { ChatFloatingImmersiveButton } from './ChatFloatingImmersiveButton'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'

interface EmailConfigurationError {
  code?: number
  message?: string
}

/** Account authorization belongs to Settings; knowledge only consumes the authorized mailbox. */
@ComponentV2
export struct EmailAccountSettingsCard {
  @Local account: EmailAccountConfig = new EmailAccountConfig()
  @Local isLoading: boolean = true
  @Local isWorking: boolean = false
  @Local showConfigSheet: boolean = false
  @Local formEmail: string = ''
  @Local formDisplayName: string = ''
  @Local formUsername: string = ''
  @Local formPassword: string = ''
  @Local formSmtpHost: string = ''
  @Local formSmtpPort: string = '465'
  @Local formSmtpSecurity: string = EmailTransportSecurity.SSL_TLS
  @Local formImapHost: string = ''
  @Local formImapPort: string = '993'
  @Local formImapSecurity: string = EmailTransportSecurity.SSL_TLS
  @Local formAuthenticationMethod: string = EmailAuthenticationMethod.PASSWORD
  @Local formOauthClientId: string = ''
  @Local oauthUserCode: string = ''
  @Local oauthVerificationUri: string = ''
  @Local connectionMessage: string = ''
  @Local connectionOk: boolean = false

  private service: EmailService = ServiceRegistry.email()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    this.loadAccount()
  }

  private loadAccount(): void {
    this.service.loadConfig()
      .then((config: EmailAccountConfig): void => {
        this.account = config
        this.isLoading = false
      })
      .catch((error: Object): void => {
        this.isLoading = false
        this.showEmailSnack(this.errorMessage(error), SnackBarTone.ERROR)
      })
  }

  private openConfig(): void {
    const config = this.account.configured ? this.account : this.service.suggestConfig(this.account.emailAddress)
    this.formEmail = config.emailAddress
    this.formDisplayName = config.displayName
    this.formUsername = config.username
    this.formSmtpHost = config.smtpHost
    this.formSmtpPort = `${config.smtpPort}`
    this.formSmtpSecurity = config.smtpSecurity
    this.formImapHost = config.imapHost
    this.formImapPort = `${config.imapPort}`
    this.formImapSecurity = config.imapSecurity
    this.formAuthenticationMethod = this.isMicrosoftAccount(config)
      ? EmailAuthenticationMethod.MICROSOFT_OAUTH2 : config.authenticationMethod
    this.formOauthClientId = config.oauthClientId
    this.formPassword = ''
    this.oauthUserCode = ''
    this.oauthVerificationUri = ''
    this.connectionMessage = ''
    this.connectionOk = false
    this.showConfigSheet = true
  }

  private applySuggestedServers(): void {
    const suggested = this.service.suggestConfig(this.formEmail)
    if (!this.formEmail.includes('@')) {
      this.connectionOk = false
      this.connectionMessage = pickLocalizedText('请先输入完整的邮箱地址',
        'Enter a complete email address first.')
      return
    }
    if (suggested.smtpHost === '' || suggested.imapHost === '') {
      this.connectionOk = false
      this.connectionMessage = pickLocalizedText('未识别该邮箱服务商，请手动填写 SMTP 和 IMAP 地址',
        'This provider is not recognized. Enter the SMTP and IMAP addresses manually.')
      return
    }
    this.formUsername = suggested.username
    this.formSmtpHost = suggested.smtpHost
    this.formSmtpPort = `${suggested.smtpPort}`
    this.formSmtpSecurity = suggested.smtpSecurity
    this.formImapHost = suggested.imapHost
    this.formImapPort = `${suggested.imapPort}`
    this.formImapSecurity = suggested.imapSecurity
    this.formAuthenticationMethod = suggested.authenticationMethod
    this.connectionOk = true
    this.connectionMessage = pickLocalizedText('已自动填充常用服务器配置',
      'Common server settings filled in.')
  }

  private isMicrosoftAccount(config: EmailAccountConfig): boolean {
    const email = config.emailAddress.trim().toLowerCase()
    const domain = email.includes('@') ? email.substring(email.lastIndexOf('@') + 1) : ''
    return domain === 'outlook.com' || domain === 'hotmail.com' || domain === 'live.com' ||
      domain === 'office365.com' || config.imapHost.trim().toLowerCase() === 'outlook.office365.com'
  }

  private buildFormConfig(): EmailAccountConfig {
    return new EmailAccountConfig(
      this.formEmail,
      this.formDisplayName,
      this.formUsername,
      this.formSmtpHost,
      Number(this.formSmtpPort),
      this.formSmtpSecurity,
      this.formImapHost,
      Number(this.formImapPort),
      this.formImapSecurity,
      true,
      this.formAuthenticationMethod,
      this.formOauthClientId
    )
  }

  private testAndSaveAccount(): void {
    if (this.isWorking) {
      return
    }
    this.performTestAndSaveAccount().catch((error: Object): void => {
      this.connectionOk = false
      this.connectionMessage = this.errorMessage(error)
      this.isWorking = false
    })
  }

  private async performTestAndSaveAccount(): Promise<void> {
    this.isWorking = true
    const config = this.buildFormConfig()
    if (config.authenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2) {
      await this.performMicrosoftOAuthAndSave(config)
      return
    }
    this.connectionMessage = pickLocalizedText('正在验证 SMTP 与 IMAP...', 'Testing SMTP and IMAP...')
    const result: EmailConnectionTestResult = await this.service.testConnection(config, this.formPassword)
    this.connectionOk = result.ok
    this.connectionMessage = result.message
    if (!result.ok) {
      this.isWorking = false
      return
    }
    this.connectionMessage = pickLocalizedText('连接成功，正在安全保存授权信息...',
      'Connected. Securely saving authorization...')
    this.account = await this.service.saveConfig(config, this.formPassword)
    this.formPassword = ''
    this.isWorking = false
    this.showConfigSheet = false
    this.showEmailSnack(
      pickLocalizedText('邮箱授权已保存；AI 每次读取或发送仍需批准',
        'Mailbox authorization saved; every AI read or send still requires your approval.'),
      SnackBarTone.SUCCESS,
      3800
    )
  }

  private async performMicrosoftOAuthAndSave(config: EmailAccountConfig): Promise<void> {
    this.oauthUserCode = ''
    this.oauthVerificationUri = ''
    this.connectionMessage = pickLocalizedText('正在申请 Microsoft OAuth2 授权码...',
      'Requesting a Microsoft OAuth2 code...')
    const authorization: EmailOAuthDeviceAuthorization =
      await this.service.requestMicrosoftOAuthDeviceAuthorization(config)
    this.oauthUserCode = authorization.userCode
    this.oauthVerificationUri = authorization.verificationUriComplete
    this.connectionOk = true
    this.connectionMessage = pickLocalizedText(
      `请在 Microsoft 页面输入代码 ${authorization.userCode} 并完成授权，APP 正在等待结果...`,
      `Enter code ${authorization.userCode} on the Microsoft page. The app is waiting for authorization...`
    )
    this.openMicrosoftAuthorizationPage(authorization.verificationUriComplete).catch((_error: Object): void => {})
    const token: EmailOAuthTokenResult =
      await this.service.completeMicrosoftOAuthDeviceAuthorization(config, authorization)
    this.connectionMessage = pickLocalizedText('授权成功，正在验证 SMTP 与 IMAP...',
      'Authorized. Testing SMTP and IMAP...')
    const result = await this.service.testOAuthConnection(config, token.accessToken)
    this.connectionOk = result.ok
    this.connectionMessage = result.message
    if (!result.ok) {
      this.isWorking = false
      return
    }
    this.connectionMessage = pickLocalizedText('连接成功，正在安全保存授权信息...',
      'Connected. Securely saving authorization...')
    this.account = await this.service.saveOAuthConfig(config, token.refreshToken)
    this.oauthUserCode = ''
    this.oauthVerificationUri = ''
    this.isWorking = false
    this.showConfigSheet = false
    this.showEmailSnack(
      pickLocalizedText('Microsoft OAuth2 邮箱授权已保存；AI 每次读取或发送仍需批准',
        'Microsoft OAuth2 authorization saved; every AI read or send still requires approval.'),
      SnackBarTone.SUCCESS,
      3800
    )
  }

  private async openMicrosoftAuthorizationPage(url: string): Promise<void> {
    const hostContext = this.getUIContext().getHostContext()
    if (hostContext === undefined || hostContext === null) {
      throw new Error('UI context unavailable')
    }
    const context = hostContext as common.UIAbilityContext
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    }
    await context.startAbility(want)
  }

  private requestClearAuthorization(): void {
    if (this.isWorking || !this.account.configured) {
      return
    }
    this.getUIContext().showAlertDialog({
      title: pickLocalizedText('撤销邮箱授权？', 'Revoke Mailbox Authorization?'),
      backgroundColor: Color.Transparent,
      backgroundBlurStyle: BlurStyle.NONE,
      systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK }),
      message: pickLocalizedText(
        '将删除本机保存的邮箱配置和加密授权码，AI 将无法继续查看或发送邮件。',
        'This removes the local mailbox configuration and encrypted app password. AI will no longer be able to read or send email.'
      ),
      primaryButton: { value: pickLocalizedText('取消', 'Cancel'), action: (): void => {} },
      secondaryButton: {
        value: pickLocalizedText('撤销授权', 'Revoke'),
        fontColor: Color.Red,
        action: (): void => { this.clearAuthorization() }
      }
    })
  }

  private clearAuthorization(): void {
    this.isWorking = true
    this.service.clearAuthorization()
      .then((): void => {
        this.account = new EmailAccountConfig()
        this.formPassword = ''
        this.showConfigSheet = false
        this.isWorking = false
        this.showEmailSnack(pickLocalizedText('已撤销邮箱授权', 'Mailbox authorization revoked'),
          SnackBarTone.SUCCESS)
      })
      .catch((error: Object): void => {
        this.isWorking = false
        this.showEmailSnack(this.errorMessage(error), SnackBarTone.ERROR)
      })
  }

  private showEmailSnack(message: string | Resource, tone: SnackBarTone = SnackBarTone.DEFAULT,
    duration: number = 2800): void {
    const options = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  private errorMessage(error: Object): string {
    if (error instanceof Error && error.message.trim() !== '') {
      return error.message
    }
    const businessError = error as EmailConfigurationError
    if (businessError.message !== undefined && businessError.message.trim() !== '') {
      return businessError.code === undefined ? businessError.message :
        `${businessError.message} (${businessError.code})`
    }
    return pickLocalizedText('邮箱配置失败', 'Mailbox configuration failed')
  }

  @Builder
  private EmailAddressInput() {
    Column({ space: 6 }) {
      Text(pickLocalizedText('邮箱地址', 'Email address'))
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ text: this.formEmail, placeholder: 'name@example.com' })
        .height(44)
        .fontSize(14)
        .backgroundColor(getAppUiState().themeBackground)
        .borderRadius(12)
        .onChange((value: string): void => {
          this.formEmail = value
          this.connectionMessage = ''
        })
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DisplayNameInput() {
    Column({ space: 6 }) {
      Text(pickLocalizedText('显示名称', 'Display name'))
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ text: this.formDisplayName, placeholder: pickLocalizedText('可选', 'Optional') })
        .height(44).fontSize(14).backgroundColor(getAppUiState().themeBackground).borderRadius(12)
        .onChange((value: string): void => { this.formDisplayName = value })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private UsernameInput() {
    Column({ space: 6 }) {
      Text(pickLocalizedText('登录用户名', 'Username'))
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ text: this.formUsername,
        placeholder: pickLocalizedText('通常与邮箱地址相同', 'Usually the email address') })
        .height(44).fontSize(14).backgroundColor(getAppUiState().themeBackground).borderRadius(12)
        .onChange((value: string): void => { this.formUsername = value })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private PasswordInput() {
    Column({ space: 6 }) {
      Text(pickLocalizedText('授权码 / 应用专用密码', 'Authorization code / app password'))
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ text: this.formPassword,
        placeholder: pickLocalizedText('不会提供给模型', 'Never shared with the model') })
        .type(InputType.Password).height(44).fontSize(14)
        .backgroundColor(getAppUiState().themeBackground).borderRadius(12)
        .onChange((value: string): void => { this.formPassword = value })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private selectAuthenticationMethod(value: string): void {
    this.formAuthenticationMethod = value
    this.connectionMessage = ''
    this.oauthUserCode = ''
    this.oauthVerificationUri = ''
    if (value === EmailAuthenticationMethod.MICROSOFT_OAUTH2) {
      this.formSmtpSecurity = EmailTransportSecurity.STARTTLS
      if (this.formSmtpPort.trim() === '465') {
        this.formSmtpPort = '587'
      }
    }
  }

  @Builder
  private AuthenticationSelector() {
    Column({ space: 6 }) {
      Text(pickLocalizedText('认证方式', 'Authentication'))
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 8 }) {
        Button(pickLocalizedText('授权码 / 密码', 'App password'))
          .type(ButtonType.Capsule).height(34).fontSize(12)
          .backgroundColor(this.formAuthenticationMethod === EmailAuthenticationMethod.PASSWORD
            ? this.themePrimary : Color.Transparent)
          .fontColor(this.formAuthenticationMethod === EmailAuthenticationMethod.PASSWORD
            ? Color.White : $r('app.color.text_secondary'))
          .border({ width: 1,
            color: this.formAuthenticationMethod === EmailAuthenticationMethod.PASSWORD
              ? this.themePrimary : $r('app.color.divider') })
          .onClick(() => this.selectAuthenticationMethod(EmailAuthenticationMethod.PASSWORD))
        Button('Microsoft OAuth2')
          .type(ButtonType.Capsule).height(34).fontSize(12)
          .backgroundColor(this.formAuthenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2
            ? this.themePrimary : Color.Transparent)
          .fontColor(this.formAuthenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2
            ? Color.White : $r('app.color.text_secondary'))
          .border({ width: 1,
            color: this.formAuthenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2
              ? this.themePrimary : $r('app.color.divider') })
          .onClick(() => this.selectAuthenticationMethod(EmailAuthenticationMethod.MICROSOFT_OAUTH2))
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private OAuthClientIdInput() {
    Column({ space: 6 }) {
      Text('Microsoft Entra Client ID')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ text: this.formOauthClientId, placeholder: '00000000-0000-0000-0000-000000000000' })
        .height(44).fontSize(14).backgroundColor(getAppUiState().themeBackground).borderRadius(12)
        .onChange((value: string): void => { this.formOauthClientId = value.trim() })
      Text(pickLocalizedText(
        '需在 Microsoft Entra 将应用设为公共客户端并启用设备代码流；Client ID 不是密码。',
        'Register a public client in Microsoft Entra and enable device code flow. A Client ID is not a secret.'
      )).fontSize(11).lineHeight(17).fontColor($r('app.color.text_tertiary')).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SmtpHostInput() {
    Column({ space: 6 }) {
      Text(pickLocalizedText('服务器', 'Server'))
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ text: this.formSmtpHost, placeholder: 'smtp.example.com' })
        .height(44).fontSize(14).backgroundColor(getAppUiState().themeBackground).borderRadius(12)
        .onChange((value: string): void => { this.formSmtpHost = value })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SmtpPortInput() {
    Column({ space: 6 }) {
      Text(pickLocalizedText('端口', 'Port'))
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ text: this.formSmtpPort, placeholder: '465' })
        .type(InputType.Number).height(44).fontSize(14)
        .backgroundColor(getAppUiState().themeBackground).borderRadius(12)
        .onChange((value: string): void => { this.formSmtpPort = value })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ImapHostInput() {
    Column({ space: 6 }) {
      Text(pickLocalizedText('服务器', 'Server'))
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ text: this.formImapHost, placeholder: 'imap.example.com' })
        .height(44).fontSize(14).backgroundColor(getAppUiState().themeBackground).borderRadius(12)
        .onChange((value: string): void => { this.formImapHost = value })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ImapPortInput() {
    Column({ space: 6 }) {
      Text(pickLocalizedText('端口', 'Port'))
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ text: this.formImapPort, placeholder: '993' })
        .type(InputType.Number).height(44).fontSize(14)
        .backgroundColor(getAppUiState().themeBackground).borderRadius(12)
        .onChange((value: string): void => { this.formImapPort = value })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private selectSmtpSecurity(value: string): void {
    this.formSmtpSecurity = value
    if (value === EmailTransportSecurity.STARTTLS && this.formSmtpPort.trim() === '465') {
      this.formSmtpPort = '587'
    } else if (value === EmailTransportSecurity.SSL_TLS && this.formSmtpPort.trim() === '587') {
      this.formSmtpPort = '465'
    }
  }

  private selectImapSecurity(value: string): void {
    this.formImapSecurity = value
    if (value === EmailTransportSecurity.STARTTLS && this.formImapPort.trim() === '993') {
      this.formImapPort = '143'
    } else if (value === EmailTransportSecurity.SSL_TLS && this.formImapPort.trim() === '143') {
      this.formImapPort = '993'
    }
  }

  @Builder
  private SmtpSecuritySelector() {
    Row({ space: 8 }) {
      Button('SSL/TLS')
        .type(ButtonType.Capsule).height(34).fontSize(12)
        .backgroundColor(this.formSmtpSecurity === EmailTransportSecurity.SSL_TLS
          ? this.themePrimary : Color.Transparent)
        .fontColor(this.formSmtpSecurity === EmailTransportSecurity.SSL_TLS
          ? Color.White : $r('app.color.text_secondary'))
        .border({ width: 1, color: this.formSmtpSecurity === EmailTransportSecurity.SSL_TLS ? this.themePrimary :
          $r('app.color.divider') })
        .onClick(() => this.selectSmtpSecurity(EmailTransportSecurity.SSL_TLS))
      Button('STARTTLS')
        .type(ButtonType.Capsule).height(34).fontSize(12)
        .backgroundColor(this.formSmtpSecurity === EmailTransportSecurity.STARTTLS
          ? this.themePrimary : Color.Transparent)
        .fontColor(this.formSmtpSecurity === EmailTransportSecurity.STARTTLS
          ? Color.White : $r('app.color.text_secondary'))
        .border({ width: 1, color: this.formSmtpSecurity === EmailTransportSecurity.STARTTLS ? this.themePrimary :
          $r('app.color.divider') })
        .onClick(() => this.selectSmtpSecurity(EmailTransportSecurity.STARTTLS))
    }
    .width('100%')
  }

  @Builder
  private ImapSecuritySelector() {
    Row({ space: 8 }) {
      Button('SSL/TLS')
        .type(ButtonType.Capsule).height(34).fontSize(12)
        .backgroundColor(this.formImapSecurity === EmailTransportSecurity.SSL_TLS
          ? this.themePrimary : Color.Transparent)
        .fontColor(this.formImapSecurity === EmailTransportSecurity.SSL_TLS
          ? Color.White : $r('app.color.text_secondary'))
        .border({ width: 1, color: this.formImapSecurity === EmailTransportSecurity.SSL_TLS ? this.themePrimary :
          $r('app.color.divider') })
        .onClick(() => this.selectImapSecurity(EmailTransportSecurity.SSL_TLS))
      Button('STARTTLS')
        .type(ButtonType.Capsule).height(34).fontSize(12)
        .backgroundColor(this.formImapSecurity === EmailTransportSecurity.STARTTLS
          ? this.themePrimary : Color.Transparent)
        .fontColor(this.formImapSecurity === EmailTransportSecurity.STARTTLS
          ? Color.White : $r('app.color.text_secondary'))
        .border({ width: 1, color: this.formImapSecurity === EmailTransportSecurity.STARTTLS ? this.themePrimary :
          $r('app.color.divider') })
        .onClick(() => this.selectImapSecurity(EmailTransportSecurity.STARTTLS))
    }
    .width('100%')
  }

  @Builder
  private ConfigSheetContent() {
    Column() {
      ImmersiveSheetHeader({
        title: pickLocalizedText('邮箱授权', 'Mailbox Authorization'),
        onLeadingClick: (): void => {
          if (!this.isWorking) {
            this.showConfigSheet = false
          }
        }
      })
      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 12 }) {
            this.EmailAddressInput()
            Row() {
              Blank()
              Button(pickLocalizedText('自动填充常用服务器', 'Suggest common servers'))
                .height(32)
                .fontSize(12)
                .type(ButtonType.Capsule)
                .backgroundColor(Color.Transparent)
                .fontColor(this.themePrimary)
                .border({ width: 1, color: this.themePrimary })
                .onClick(() => this.applySuggestedServers())
            }.width('100%')
            this.DisplayNameInput()
            this.UsernameInput()
            this.AuthenticationSelector()
            if (this.formAuthenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2) {
              this.OAuthClientIdInput()
              if (this.oauthUserCode !== '') {
                Column({ space: 8 }) {
                  Text(pickLocalizedText('Microsoft 设备授权代码', 'Microsoft device authorization code'))
                    .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
                  Text(this.oauthUserCode).fontSize(24).fontWeight(FontWeight.Bold)
                    .fontColor(this.themePrimary).letterSpacing(2).width('100%')
                  Button(pickLocalizedText('重新打开 Microsoft 授权页', 'Reopen Microsoft authorization page'))
                    .height(34).fontSize(12).type(ButtonType.Capsule)
                    .backgroundColor(Color.Transparent).fontColor(this.themePrimary)
                    .border({ width: 1, color: this.themePrimary })
                    .onClick((): void => {
                      this.openMicrosoftAuthorizationPage(this.oauthVerificationUri)
                        .catch((_error: Object): void => {})
                    })
                }.width('100%').alignItems(HorizontalAlign.Start)
              }
            } else {
              this.PasswordInput()
            }
          }
          .width('100%').padding(16).borderRadius(18).backgroundColor($r('app.color.surface'))

          Column({ space: 12 }) {
            Text('SMTP · ' + pickLocalizedText('发送', 'Send'))
              .fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            this.SmtpHostInput()
            this.SmtpPortInput()
            this.SmtpSecuritySelector()
          }
          .width('100%').padding(16).borderRadius(18).backgroundColor($r('app.color.surface'))

          Column({ space: 12 }) {
            Text('IMAP · ' + pickLocalizedText('查看', 'Read'))
              .fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            this.ImapHostInput()
            this.ImapPortInput()
            this.ImapSecuritySelector()
          }
          .width('100%').padding(16).borderRadius(18).backgroundColor($r('app.color.surface'))

          Text(pickLocalizedText(
            '仅支持加密连接并校验服务器证书。授权码保存在系统沙箱存储',
            'Encrypted connections and certificate validation are required. The app password is protected by the system secure asset store.'
          )).fontSize(12).lineHeight(18).fontColor($r('app.color.text_secondary')).width('100%')

          if (this.connectionMessage !== '') {
            Text(this.connectionMessage).fontSize(12).lineHeight(18)
              .fontColor(this.connectionOk ? this.themePrimary : $r('app.color.status_error')).width('100%')
          }

          Button(this.isWorking
            ? (this.formAuthenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2
              ? pickLocalizedText('等待 Microsoft 授权...', 'Waiting for Microsoft authorization...')
              : pickLocalizedText('正在验证...', 'Testing...'))
            : (this.formAuthenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2
              ? pickLocalizedText('Microsoft OAuth2 授权并保存', 'Authorize Microsoft OAuth2')
              : pickLocalizedText('验证并保存授权', 'Test and Save Authorization')))
            .width('100%').height(46).type(ButtonType.Capsule).enabled(!this.isWorking)
            .backgroundColor(this.themePrimary).fontColor(Color.White).onClick(() => this.testAndSaveAccount())

          if (this.account.configured) {
            Button(pickLocalizedText('撤销当前邮箱授权', 'Revoke Current Mailbox Authorization'))
              .width('100%').height(42).type(ButtonType.Capsule).enabled(!this.isWorking)
              .backgroundColor(Color.Transparent).fontColor($r('app.color.status_error'))
              .border({ width: 1, color: $r('app.color.status_error') })
              .onClick(() => this.requestClearAuthorization())
          }
        }
        .width('100%').padding({ left: 16, right: 16, bottom: 28 })
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor(getAppUiState().themeBackground)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        ChatFloatingImmersiveButton({
          barWidth: 44,
          barHeight: 44,
          iconResource: $r('sys.symbol.envelope'),
          iconSize: 20,
          iconColor: [this.themePrimary],
          responsePadding: 0
        }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.envelope')).fontSize(20).fontColor([this.themePrimary])
          }.width(44).height(44)
        }
        Column({ space: 5 }) {
          Text(pickLocalizedText('邮件', 'Email')).fontSize(17).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary')).width('100%')
          Text(this.isLoading ? pickLocalizedText('正在读取配置...', 'Loading configuration...') :
            this.account.configured
              ? pickLocalizedText(`已授权 ${this.account.emailAddress}`, `Authorized ${this.account.emailAddress}`)
              : pickLocalizedText('未配置 SMTP / IMAP 授权', 'SMTP / IMAP authorization not configured'))
            .fontSize(12).lineHeight(18).fontColor($r('app.color.text_secondary')).width('100%')
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button(pickLocalizedText('配置', 'Configure'))
          .height(32).fontSize(12).type(ButtonType.Capsule).stateEffect(false)
          .backgroundColor(this.themePrimary).fontColor(Color.White).onClick(() => this.openConfig())
      }.width('100%').alignItems(VerticalAlign.Center)

    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor(Color.Transparent)
    .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: Color.Transparent,
      applyShadow: true,
      interactive: false,
      lightEffect: { color: undefined }
    }))
    .bindSheet($$this.showConfigSheet, this.ConfigSheetContent(), {
      height: SheetSize.LARGE,
      detents: [SheetSize.LARGE],
      dragBar: true,
      showClose: false
    })
  }
}
