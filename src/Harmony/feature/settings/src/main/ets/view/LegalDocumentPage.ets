import { I18n, PageLayout, RouteName } from '@rwecho/core'
import { LegalSection, getLegalDocument } from '../model/LegalDocuments'

@Component
export struct LegalDocumentPage {
  @Prop documentKind: string = 'terms'
  @StorageLink('language') language: string = 'en'
  @Consume('pageStack') pageStack: NavPathStack

  build() {
    PageLayout({ title: getLegalDocument(this.documentKind, this.language).title }) {
      Column({ space: 24 }) {
        Text(getLegalDocument(this.documentKind, this.language).updated).fontSize(12)
          .fontColor($r('app.color.terminal_text_muted')).width('100%')
        ForEach(getLegalDocument(this.documentKind, this.language).sections, (section: LegalSection) => {
          Column({ space: 10 }) {
            Text(section.title).fontSize(17).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_text')).width('100%')
            ForEach(section.paragraphs, (paragraph: string) => {
              Text(paragraph).fontSize(15).lineHeight(25).copyOption(CopyOptions.LocalDevice)
                .fontColor($r('app.color.terminal_text')).width('100%')
            }, (paragraph: string) => paragraph)
          }.width('100%').alignItems(HorizontalAlign.Start)
        }, (section: LegalSection) => section.title)
        if (this.documentKind !== 'account-deletion') {
          Text(I18n.get('legal.account_deletion')).fontSize(14).fontColor($r('app.color.terminal_secondary'))
            .width('100%').padding({ top: 8, bottom: 8 })
            .onClick(() => { this.openDocument('account-deletion') })
        }
        if (this.documentKind === 'terms') {
          Text(I18n.get('settings.footer_privacy')).fontSize(14).fontColor($r('app.color.terminal_secondary'))
            .width('100%').padding({ top: 8, bottom: 8 })
            .onClick(() => { this.openDocument('privacy') })
        }
      }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 20, right: 20, top: 16, bottom: 32 })
    }
  }

  private openDocument(kind: string): void {
    const param: Record<string, string> = { 'kind': kind }
    this.pageStack.pushPath({ name: RouteName.LEGAL_DOCUMENT, param: param })
  }
}
