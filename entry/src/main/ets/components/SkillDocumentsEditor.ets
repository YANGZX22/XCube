import { fileUri, picker } from '@kit.CoreFileKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { readSkillBytes } from '../services/SkillPackageStorage'
import { ChatMarkdownRenderer } from './ChatMarkdownRenderer'
import { ImmersiveFieldSurface } from './ImmersiveFieldSurface'
import { openSkillDeleteDialog, SkillDeleteDialog } from './SkillDeleteDialog'
import { SettingsActionButton } from './settings/SettingsActionButton'
import { getSettingsTypography } from './settings/SettingsTypography'
import { getAppUiState } from '../state/AppUiState'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { getImmersiveMenuOptions, ThinSelectModifier } from '../utils/WrappedMaterialSupport'
import { checkSkillPath, isSkillMarkdown, MAX_SKILL_BYTES, SKILL_ENTRY, SkillFile, skillFileText, skillLinkTarget } from '../utils/SkillPackage'

@ObservedV2
export class SkillDraftDocument {
  @Trace path: string
  @Trace text: string

  constructor(path: string, text: string) {
    this.path = path
    this.text = text
  }
}

@ComponentV2
export struct SkillDocumentsEditor {
  @Param documents: SkillDraftDocument[] = []
  @Param resourcePaths: string[] = []
  @Param readOnly: boolean = false
  @Event onDocumentsChange: (documents: SkillDraftDocument[]) => void = () => {}
  @Local selected: string = SKILL_ENTRY
  @Local preview: boolean = true
  @Local adding: boolean = false
  @Local showAddMenu: boolean = false
  @Local importing: boolean = false
  private active: boolean = true
  @Event onImportState: (busy: boolean) => void = () => {}
  @Local newPath: string = ''
  @Local error: string = ''

  aboutToAppear(): void {
    this.active = true
    this.preview = this.readOnly || this.documents.some((doc: SkillDraftDocument): boolean => !!doc.text)
  }

  aboutToDisappear(): void {
    this.active = false
  }

  private current(): SkillDraftDocument | undefined {
    return this.documents.find((doc: SkillDraftDocument): boolean => doc.path === this.selected)
  }

  private addDocument(): void {
    const path = this.newPath.trim()
    try {
      checkSkillPath(path)
      if (!isSkillMarkdown(path)) throw new Error(pickLocalizedText('请输入 Markdown 文件名', 'Enter a Markdown filename'))
      if (this.documents.some((doc: SkillDraftDocument): boolean => doc.path === path) || this.resourcePaths.includes(path)) {
        throw new Error(pickLocalizedText('文件已存在', 'File already exists'))
      }
      this.onDocumentsChange([...this.documents, new SkillDraftDocument(path, '')])
      this.selected = path
      this.newPath = ''
      this.error = ''
      this.preview = false
      this.adding = false
    } catch (error) {
      this.error = (error as Error).message
    }
  }

  private async pickDocuments(): Promise<void> {
    const context = this.getUIContext().getHostContext()
    if (!context || this.importing) return
    this.importing = true
    this.onImportState(true)
    try {
      const options = new picker.DocumentSelectOptions()
      options.fileSuffixFilters = ['Markdown|.md,.markdown']
      options.maxSelectNumber = 100
      const uris = await new picker.DocumentViewPicker(context).select(options)
      if (uris.length === 0) return
      const added: SkillDraftDocument[] = []
      const paths = new Set(this.documents.map((doc: SkillDraftDocument): string => doc.path))
      let remaining = MAX_SKILL_BYTES
      for (const uri of uris) {
        const path = checkSkillPath(new fileUri.FileUri(uri).name)
        if (!isSkillMarkdown(path) || paths.has(path) || this.resourcePaths.includes(path)) {
          throw new Error(pickLocalizedText('文件名无效或已存在', 'Invalid or duplicate filename') + ' · ' + path)
        }
        const bytes = await readSkillBytes(uri, remaining)
        remaining -= bytes.length
        added.push(new SkillDraftDocument(path, skillFileText(new SkillFile(path, bytes))))
        paths.add(path)
      }
      if (!this.active) return
      this.onDocumentsChange([...this.documents, ...added])
      this.selected = added[0].path
      this.preview = true
      this.adding = false
      this.error = ''
    } catch (error) {
      if (!/cancel/i.test((error as Error).message ?? '')) this.error = (error as Error).message
    } finally {
      this.importing = false
      if (this.active) this.onImportState(false)
    }
  }

  private async copyText(value: string): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value))
    } catch {
      this.error = pickLocalizedText('复制失败', 'Copy failed')
    }
  }

  private deleteDocument(): void {
    const path = this.selected
    if (this.readOnly || path === SKILL_ENTRY) return
    openSkillDeleteDialog(this.getUIContext(), (dialogId: number): void => this.DeleteDocumentDialog(path, dialogId))
  }

  @Builder
  private DeleteDocumentDialog(path: string, dialogId: number) {
    SkillDeleteDialog({
      dialogId: dialogId,
      title: pickLocalizedText('删除文档', 'Delete document'),
      message: path,
      onDelete: (): void => {
        this.selected = SKILL_ENTRY
        this.onDocumentsChange(this.documents.filter((doc: SkillDraftDocument): boolean => doc.path !== path))
      }
    })
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text(pickLocalizedText('文档', 'Documents')).font(getSettingsTypography().sectionTitle)
          .fontColor(getAppUiState().themeTextPrimary).layoutWeight(1)
        if (!this.readOnly) {
          SettingsActionButton({
            label: pickLocalizedText('添加文档', 'Add document'), compact: true, buttonHeight: 32,
            isEnabled: !this.importing,
            onActivate: (): void => { this.showAddMenu = true }
          })
          .bindMenu(this.showAddMenu, [
            { value: pickLocalizedText('新建文档', 'New document'), action: (): void => {
              this.adding = true
              this.error = ''
            } },
            { value: pickLocalizedText('从文件导入', 'Import Markdown'), action: (): void => { this.pickDocuments() } }
          ], getImmersiveMenuOptions((): void => { this.showAddMenu = false }))
        }
      }.width('100%')
      if (this.adding) {
        Row({ space: 4 }) {
          ImmersiveFieldSurface({ cornerRadius: 14, layoutWeightValue: 1 }) {
            TextInput({ text: this.newPath, placeholder: 'references/guide.md' })
              .height(40).fontSize(14).backgroundColor(Color.Transparent)
              .onChange((v: string): void => { this.newPath = v })
              .onSubmit((): void => this.addDocument())
          }
          SettingsActionButton({
            label: pickLocalizedText('添加', 'Add'), compact: true, buttonHeight: 32,
            onActivate: (): void => this.addDocument()
          })
        }.width('100%')
      }
      if (this.error) {
        Text(this.error).fontSize(12).fontColor(Color.Red)
      }
      Select(this.documents.map((doc: SkillDraftDocument): SelectOption => ({ value: doc.path })))
        .value(this.selected)
        .selected(this.documents.findIndex((doc: SkillDraftDocument): boolean => doc.path === this.selected))
        .width('100%').height(40).borderRadius(12)
        .font({ size: 14 }).fontColor(getAppUiState().themeTextPrimary)
        .attributeModifier(new ThinSelectModifier())
        .onSelect((index: number): void => {
          if (this.documents[index]) this.selected = this.documents[index].path
        })
      if (!this.readOnly) {
        Row() {
          SettingsActionButton({
            label: this.preview ? pickLocalizedText('编辑正文', 'Edit text') : pickLocalizedText('预览', 'Preview'),
            compact: true, buttonHeight: 32,
            onActivate: (): void => { this.preview = !this.preview }
          })
          Blank()
          if (this.selected !== SKILL_ENTRY) {
            SettingsActionButton({
              label: pickLocalizedText('删除文档', 'Delete document'), compact: true, buttonHeight: 32,
              foreground: $r('app.color.status_error'), onActivate: (): void => this.deleteDocument()
            })
          }
        }.width('100%')
      }
      if (this.readOnly || this.preview) {
        if (this.current()?.text) {
          ForEach([this.selected], (path: string) => {
            ChatMarkdownRenderer({
              content: this.current()?.text ?? '', isInputEnded: true, incrementalAnalysis: false,
              chatFontSize: 15, themeRenderKey: 'skill-' + path, showCodeFullScreen: false,
              onCopyText: (value: string): void => { this.copyText(value) },
              onCopyCode: (value: string): void => { this.copyText(value) },
              onOpenLink: (_title: string, url: string): void => {
                const target = skillLinkTarget(path, url)
                if (this.documents.some((doc: SkillDraftDocument): boolean => doc.path === target)) this.selected = target
              }
            })
          }, (path: string): string => path)
        } else {
          Text(pickLocalizedText('空文档', 'Empty document')).fontSize(14).fontColor($r('app.color.text_caption'))
        }
      } else {
        ImmersiveFieldSurface({ cornerRadius: 14 }) {
          TextArea({ text: this.current()?.text ?? '', placeholder: '# Markdown' })
            .width('100%').height(260).padding(12).fontSize(14).lineHeight(21)
            .fontColor(getAppUiState().themeTextPrimary).backgroundColor(Color.Transparent)
            .onChange((value: string): void => {
              const doc = this.current()
              if (doc) doc.text = value
            })
        }
      }
      if (this.resourcePaths.length > 0) {
        Text(pickLocalizedText('随附文件', 'Supporting files')).font(getSettingsTypography().fieldLabel)
          .fontColor($r('app.color.text_secondary'))
        Text(this.resourcePaths.join('\n')).fontSize(12).fontColor($r('app.color.text_caption'))
          .copyOption(CopyOptions.LocalDevice)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
