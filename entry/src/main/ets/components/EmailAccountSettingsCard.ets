import { getSettingsTypography, SETTINGS_HEADING_CONTENT_GAP, SETTINGS_SUBTITLE_LINE_HEIGHT } from './settings/SettingsTypography'
import { ImmersiveListSurface, LIST_MATERIAL_CARD_RADIUS } from './ImmersiveListSurface'
import { ImmersiveFieldSurface } from './ImmersiveFieldSurface'
import { SettingsActionButton } from './settings/SettingsActionButton'
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
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { getSettingsSheetContentMaxHeight } from '../utils/SettingsPageLayoutHelper'
import { shouldUseWrappedMaterial } from '../utils/WrappedMaterialSupport'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { ChatFloatingImmersiveButton } from './ChatFloatingImmersiveButton'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'
import { SETTINGS_FORM_VALUE_FONT_SIZE, SettingsFormSelect } from './settings/SettingsFormSelect'

interface EmailConfigurationError {
  code?: number
  message?: string
}

/** Account authorization belongs to Settings; knowledge only consumes the authorized mailbox. */
@ComponentV2
export struct EmailAccountSettingsCard {
  @Param embedded: boolean = false
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
  private readonly transportSecurityOptions: SelectOption[] = [{ value: 'SSL/TLS' }, { value: 'STARTTLS' }]

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
    Column({ space: SETTINGS_HEADING_CONTENT_GAP }) {
      Text(pickLocalizedText('邮箱地址', 'Email address'))
        .font(getSettingsTypography().fieldLabel)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      ImmersiveFieldSurface({ cornerRadius: 10 }) {
        Row() {
          TextInput({ text: this.formEmail, placeholder: 'name@example.com' })
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .height(40)
            .fontSize(SETTINGS_FORM_VALUE_FONT_SIZE)
            .placeholderFont({ size: SETTINGS_FORM_VALUE_FONT_SIZE })
            .borderRadius(10)
            .padding({ left: 12, right: 4 })
            .onChange((value: string): void => {
              this.formEmail = value
              this.connectionMessage = ''
            })
          SettingsActionButton({
            label: pickLocalizedText('自动填充', 'Autofill'),
            accessibilityLabel: pickLocalizedText('自动填充常用服务器', 'Autofill common mail servers'),
            compact: true,
            buttonHeight: 30,
            maxWidth: '45%',
            foreground: this.themePrimary,
            onActivate: (): void => this.applySuggestedServers()
          })
        }
        .width('100%')
        .height(40)
        .alignItems(VerticalAlign.Center)
        .padding({ right: 5 })
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private DisplayNameInput() {
    Column({ space: SETTINGS_HEADING_CONTENT_GAP }) {
      Text(pickLocalizedText('显示名称', 'Display name'))
        .font(getSettingsTypography().fieldLabel)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      ImmersiveFieldSurface({ cornerRadius: 10 }) {
        TextInput({ text: this.formDisplayName, placeholder: pickLocalizedText('可选', 'Optional') })
          .width('100%')
          .backgroundColor(Color.Transparent)
          .height(40)
          .fontSize(SETTINGS_FORM_VALUE_FONT_SIZE)
          .placeholderFont({ size: SETTINGS_FORM_VALUE_FONT_SIZE })
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .onChange((value: string): void => { this.formDisplayName = value })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private UsernameInput() {
    Column({ space: SETTINGS_HEADING_CONTENT_GAP }) {
      Text(pickLocalizedText('登录用户名', 'Username'))
        .font(getSettingsTypography().fieldLabel)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      ImmersiveFieldSurface({ cornerRadius: 10 }) {
        TextInput({ text: this.formUsername,
          placeholder: pickLocalizedText('通常与邮箱地址相同', 'Usually the email address') })
          .width('100%')
          .backgroundColor(Color.Transparent)
          .height(40)
          .fontSize(SETTINGS_FORM_VALUE_FONT_SIZE)
          .placeholderFont({ size: SETTINGS_FORM_VALUE_FONT_SIZE })
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .onChange((value: string): void => { this.formUsername = value })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private PasswordInput() {
    Column({ space: SETTINGS_HEADING_CONTENT_GAP }) {
      Text(pickLocalizedText('授权码 / 应用专用密码', 'Authorization code / app password'))
        .font(getSettingsTypography().fieldLabel)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      ImmersiveFieldSurface({ cornerRadius: 10 }) {
        TextInput({ text: this.formPassword,
          placeholder: pickLocalizedText('不会提供给模型', 'Never shared with the model') })
          .width('100%')
          .backgroundColor(Color.Transparent)
          .type(InputType.Password)
          .height(40)
          .fontSize(SETTINGS_FORM_VALUE_FONT_SIZE)
          .placeholderFont({ size: SETTINGS_FORM_VALUE_FONT_SIZE })
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .onChange((value: string): void => { this.formPassword = value })
      }
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
    SettingsFormSelect({
      label: pickLocalizedText('认证方式', 'Authentication'),
      options: [{ value: pickLocalizedText('授权码 / 密码', 'App password') }, { value: 'Microsoft OAuth2' }],
      selectedIndex: this.formAuthenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2 ? 1 : 0,
      onSelect: (index: number): void => this.selectAuthenticationMethod(index === 1
        ? EmailAuthenticationMethod.MICROSOFT_OAUTH2 : EmailAuthenticationMethod.PASSWORD)
    })
  }

  @Builder
  private OAuthClientIdInput() {
    Column({ space: SETTINGS_HEADING_CONTENT_GAP }) {
      Text('Microsoft Entra Client ID')
        .font(getSettingsTypography().fieldLabel)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      ImmersiveFieldSurface({ cornerRadius: 10 }) {
        TextInput({ text: this.formOauthClientId, placeholder: '00000000-0000-0000-0000-000000000000' })
          .width('100%')
          .backgroundColor(Color.Transparent)
          .height(40)
          .fontSize(SETTINGS_FORM_VALUE_FONT_SIZE)
          .placeholderFont({ size: SETTINGS_FORM_VALUE_FONT_SIZE })
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .onChange((value: string): void => { this.formOauthClientId = value.trim() })
      }
      Text(pickLocalizedText(
        '需在 Microsoft Entra 将应用设为公共客户端并启用设备代码流；Client ID 不是密码。',
        'Register a public client in Microsoft Entra and enable device code flow. A Client ID is not a secret.'
      ))
        .font(getSettingsTypography().subtitle)
        .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
        .fontColor($r('app.color.text_caption'))
        .width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SmtpHostInput() {
    Column({ space: SETTINGS_HEADING_CONTENT_GAP }) {
      Text(pickLocalizedText('服务器', 'Server'))
        .font(getSettingsTypography().fieldLabel)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      ImmersiveFieldSurface({ cornerRadius: 10 }) {
        TextInput({ text: this.formSmtpHost, placeholder: 'smtp.example.com' })
          .width('100%')
          .backgroundColor(Color.Transparent)
          .height(40)
          .fontSize(SETTINGS_FORM_VALUE_FONT_SIZE)
          .placeholderFont({ size: SETTINGS_FORM_VALUE_FONT_SIZE })
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .onChange((value: string): void => { this.formSmtpHost = value })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private SmtpPortInput() {
    Column({ space: SETTINGS_HEADING_CONTENT_GAP }) {
      Text(pickLocalizedText('端口', 'Port'))
        .font(getSettingsTypography().fieldLabel)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      ImmersiveFieldSurface({ cornerRadius: 10 }) {
        TextInput({ text: this.formSmtpPort, placeholder: '465' })
          .width('100%')
          .backgroundColor(Color.Transparent)
          .type(InputType.Number)
          .height(40)
          .fontSize(SETTINGS_FORM_VALUE_FONT_SIZE)
          .placeholderFont({ size: SETTINGS_FORM_VALUE_FONT_SIZE })
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .onChange((value: string): void => { this.formSmtpPort = value })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ImapHostInput() {
    Column({ space: SETTINGS_HEADING_CONTENT_GAP }) {
      Text(pickLocalizedText('服务器', 'Server'))
        .font(getSettingsTypography().fieldLabel)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      ImmersiveFieldSurface({ cornerRadius: 10 }) {
        TextInput({ text: this.formImapHost, placeholder: 'imap.example.com' })
          .width('100%')
          .backgroundColor(Color.Transparent)
          .height(40)
          .fontSize(SETTINGS_FORM_VALUE_FONT_SIZE)
          .placeholderFont({ size: SETTINGS_FORM_VALUE_FONT_SIZE })
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .onChange((value: string): void => { this.formImapHost = value })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ImapPortInput() {
    Column({ space: SETTINGS_HEADING_CONTENT_GAP }) {
      Text(pickLocalizedText('端口', 'Port'))
        .font(getSettingsTypography().fieldLabel)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      ImmersiveFieldSurface({ cornerRadius: 10 }) {
        TextInput({ text: this.formImapPort, placeholder: '993' })
          .width('100%')
          .backgroundColor(Color.Transparent)
          .type(InputType.Number)
          .height(40)
          .fontSize(SETTINGS_FORM_VALUE_FONT_SIZE)
          .placeholderFont({ size: SETTINGS_FORM_VALUE_FONT_SIZE })
          .borderRadius(10)
          .padding({ left: 12, right: 12 })
          .onChange((value: string): void => { this.formImapPort = value })
      }
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
    SettingsFormSelect({
      label: pickLocalizedText('连接加密方式', 'Connection security'),
      options: this.transportSecurityOptions,
      selectedIndex: this.formSmtpSecurity === EmailTransportSecurity.STARTTLS ? 1 : 0,
      onSelect: (index: number): void => this.selectSmtpSecurity(index === 1
        ? EmailTransportSecurity.STARTTLS : EmailTransportSecurity.SSL_TLS)
    })
  }

  @Builder
  private ImapSecuritySelector() {
    SettingsFormSelect({
      label: pickLocalizedText('连接加密方式', 'Connection security'),
      options: this.transportSecurityOptions,
      selectedIndex: this.formImapSecurity === EmailTransportSecurity.STARTTLS ? 1 : 0,
      onSelect: (index: number): void => this.selectImapSecurity(index === 1
        ? EmailTransportSecurity.STARTTLS : EmailTransportSecurity.SSL_TLS)
    })
  }

  @Builder
  private ConfigSheetContent() {
    Column() {
      ImmersiveSheetHeader({
        titleFont: getSettingsTypography().pageTitle,
        titleColor: getAppUiState().themeTextPrimary,
        title: pickLocalizedText('邮箱授权', 'Mailbox Authorization'),
        leadingButtonEnabled: !this.isWorking,
        onLeadingClick: (): void => {
          if (!this.isWorking) {
            this.showConfigSheet = false
          }
        }
      })
      Scroll() {
        Column({ space: 12 }) {
          this.EmailAddressInput()
          this.DisplayNameInput()
          this.UsernameInput()
          this.AuthenticationSelector()
          if (this.formAuthenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2) {
            this.OAuthClientIdInput()
            if (this.oauthUserCode !== '') {
              Column({ space: SETTINGS_HEADING_CONTENT_GAP }) {
                Text(pickLocalizedText('Microsoft 设备授权代码', 'Microsoft device authorization code'))
                  .font(getSettingsTypography().fieldLabel)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                Text(this.oauthUserCode).fontSize(24).fontWeight(FontWeight.Bold)
                  .fontColor(this.themePrimary).letterSpacing(2).width('100%')
                SettingsActionButton({
                  label: pickLocalizedText('重新打开 Microsoft 授权页', 'Reopen Microsoft authorization page'),
                  compact: true,
                  buttonHeight: 34,
                  foreground: this.themePrimary,
                  onActivate: (): void => {
                    this.openMicrosoftAuthorizationPage(this.oauthVerificationUri)
                      .catch((_error: Object): void => {})
                  }
                })
              }.width('100%').alignItems(HorizontalAlign.Start)
            }
          } else {
            this.PasswordInput()
          }

          Text('SMTP · ' + pickLocalizedText('发送', 'Send'))
            .font(getSettingsTypography().sectionTitle)
            .fontColor(getAppUiState().themeTextPrimary)
            .margin({ top: 4 })
          this.SmtpHostInput()
          this.SmtpPortInput()
          this.SmtpSecuritySelector()

          Text('IMAP · ' + pickLocalizedText('查看', 'Read'))
            .font(getSettingsTypography().sectionTitle)
            .fontColor(getAppUiState().themeTextPrimary)
            .margin({ top: 4 })
          this.ImapHostInput()
          this.ImapPortInput()
          this.ImapSecuritySelector()

          Text(pickLocalizedText(
            '通过加密连接收发邮件，授权信息仅保存在本机。',
            'Email uses encrypted connections, with credentials stored only on this device.'
          ))
            .font(getSettingsTypography().subtitle)
            .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
            .fontColor($r('app.color.text_caption'))
            .width('100%')

          if (this.connectionMessage !== '') {
            Text(this.connectionMessage)
              .font(getSettingsTypography().subtitle)
              .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
              .fontColor(this.connectionOk ? this.themePrimary : $r('app.color.status_error'))
              .width('100%')
          }

          SettingsActionButton({
            label: this.isWorking
              ? (this.formAuthenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2
                ? pickLocalizedText('等待 Microsoft 授权...', 'Waiting for Microsoft authorization...')
                : pickLocalizedText('正在验证...', 'Testing...'))
              : (this.formAuthenticationMethod === EmailAuthenticationMethod.MICROSOFT_OAUTH2
                ? pickLocalizedText('Microsoft OAuth2 授权并保存', 'Authorize Microsoft OAuth2')
                : pickLocalizedText('验证并保存授权', 'Test and Save Authorization')),
            buttonHeight: 46,
            foreground: this.themePrimary,
            tint: withColorAlpha(this.themePrimary, '40'),
            isEnabled: !this.isWorking,
            onActivate: (): void => this.testAndSaveAccount()
          })

          if (this.account.configured) {
            SettingsActionButton({
              label: pickLocalizedText('撤销当前邮箱授权', 'Revoke Current Mailbox Authorization'),
              foreground: $r('app.color.status_error'),
              isEnabled: !this.isWorking,
              onActivate: (): void => this.requestClearAuthorization()
            })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .constraintSize({ maxHeight: getSettingsSheetContentMaxHeight(getAppUiState().windowHeightVp) })
      .flexShrink(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }

  build() {
    ImmersiveListSurface({ isImmersive: !this.embedded, cornerRadius: LIST_MATERIAL_CARD_RADIUS }) {
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
            Text(pickLocalizedText('邮件', 'Email'))
              .font(getSettingsTypography().itemTitle)
              .fontColor(getAppUiState().themeTextPrimary)
              .width('100%')
            Text(this.isLoading ? pickLocalizedText('正在加载…', 'Loading…') :
              this.account.configured
                ? pickLocalizedText(`已连接 ${this.account.emailAddress}`, `Connected to ${this.account.emailAddress}`)
                : pickLocalizedText('连接邮箱，收发邮件。', 'Connect your mailbox to send and receive email.'))
              .font(getSettingsTypography().subtitle)
              .lineHeight(SETTINGS_SUBTITLE_LINE_HEIGHT)
              .fontColor($r('app.color.text_caption'))
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').alignItems(VerticalAlign.Center)

        Row({ space: 4 }) {
          Blank()
          Text(pickLocalizedText('配置', 'Configure'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .fontSize(12)
            .fontColor([this.themePrimary])
        }
        .width('100%')
        .onClick(() => this.openConfig())
      }
      .width('100%')
      .padding(16)
      .borderRadius(LIST_MATERIAL_CARD_RADIUS)
      .backgroundColor(Color.Transparent)
      .bindSheet($$this.showConfigSheet, this.ConfigSheetContent(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        backgroundColor: Color.Transparent,
        blurStyle: shouldUseWrappedMaterial() ? undefined : BlurStyle.Regular,
        systemMaterial: shouldUseWrappedMaterial() ? new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR
        }) : undefined,
        preferType: SheetType.BOTTOM,
        keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE
      })
    }
  }
}
