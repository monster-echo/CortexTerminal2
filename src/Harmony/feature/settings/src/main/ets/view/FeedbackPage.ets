/**
 * @file FeedbackPage.ets
 * @brief Single form page for both 意见反馈 and 投诉举报.
 *
 * `type` nav param ('feedback' | 'report') decides title, subtype options and
 * the analytics event. On submit the body is HMAC-signed by FeedbackService
 * and POSTed to the n8n webhook (gateway is bypassed). Errors surface as an
 * inline banner — never silently swallowed.
 */
import { common } from '@kit.AbilityKit'
import { FeedbackService, FeedbackPayload, FeedbackType } from '../service/FeedbackService'
import { FeedbackFilePicker } from '../service/FeedbackFilePicker'
import {
  ApiService,
  I18n,
  PageLayout,
  RouteName,
  showToast,
  lightHaptic,
  clickHaptic,
  AnalyticsService,
  AnalyticsEvent
} from '@rwecho/core'

interface AttachmentItem {
  url: string
  name: string
  contentType: string
}

@Component
export struct FeedbackPage {
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('language') currentLanguage: string = 'en'
  @State feedbackType: FeedbackType = 'feedback'
  @State content: string = ''
  @State contact: string = ''
  @State error: string = ''
  @State isSubmitting: boolean = false
  @State attachments: AttachmentItem[] = []
  @State attaching: boolean = false

  aboutToAppear() {
    AnalyticsService.onPageStart('support/Feedback')
  }

  build() {
    PageLayout({ title: I18n.get('feedback.title_feedback') + (this.currentLanguage ? '' : '') }) {
      Column({ space: 20 }) {
        Column({ space: 8 }) {
          Text(I18n.get('feedback.content')).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.terminal_text')).width('100%')
          TextArea({ text: this.content, placeholder: I18n.get('feedback.content_placeholder') })
            .width('100%').height(160).padding(14).borderRadius(12).fontSize(15)
            .backgroundColor($r('app.color.terminal_background_element'))
            .fontColor($r('app.color.terminal_text')).placeholderColor($r('app.color.terminal_text_muted'))
            .enabled(!this.isSubmitting)
            .onChange((value: string) => { this.content = value; this.error = '' })
          Row() {
            Text(I18n.get('feedback.minimum_hint')).layoutWeight(1).fontSize(12).fontColor($r('app.color.terminal_text_muted'))
            Text(`${this.content.trim().length} ${I18n.get('feedback.characters')}`).fontSize(12).fontColor($r('app.color.terminal_text_muted'))
          }.width('100%')
        }.width('100%')

        Column({ space: 10 }) {
          Row() {
            Text(I18n.get('feedback.screenshots_optional')).layoutWeight(1).fontSize(14).fontColor($r('app.color.terminal_text'))
            Text(`${this.attachments.length}/3`).fontSize(12).fontColor($r('app.color.terminal_text_muted'))
          }.width('100%')
          Row({ space: 12 }) {
            ForEach(this.attachments, (item: AttachmentItem) => {
              Stack({ alignContent: Alignment.TopEnd }) {
                if (this.isImageContentType(item.contentType)) {
                  Image(item.url).width(76).height(76).borderRadius(10).objectFit(ImageFit.Cover)
                    .onClick(() => {
                      const param: Record<string, string> = { 'url': item.url }
                      this.pageStack.pushPath({ name: RouteName.IMAGE_PREVIEW, param: param })
                    })
                } else {
                  Text(item.name).width(76).height(76).padding(8).fontSize(11).maxLines(3)
                    .fontColor($r('app.color.terminal_text_muted'))
                    .backgroundColor($r('app.color.terminal_background_element')).borderRadius(10)
                }
                Button() {
                  SymbolGlyph($r('sys.symbol.xmark')).fontSize(12).fontColor([$r('app.color.terminal_text')])
                }.width(28).height(28).padding(0).borderRadius(14)
                  .backgroundColor($r('app.color.terminal_background_panel'))
                  .accessibilityText(I18n.get('feedback.remove_attachment')).enabled(!this.isSubmitting)
                  .onClick(() => { clickHaptic(); this.attachments = this.attachments.filter((a: AttachmentItem) => a.url !== item.url) })
              }.width(76).height(76)
            }, (item: AttachmentItem) => item.url)
            if (this.attachments.length < 3) {
              Button() {
                Column({ space: 4 }) {
                  if (this.attaching) {
                    LoadingProgress().width(22).height(22).color($r('app.color.terminal_secondary'))
                  } else {
                    Text('+').fontSize(24).fontColor($r('app.color.terminal_secondary'))
                    Text(I18n.get('feedback.add')).fontSize(11).fontColor($r('app.color.terminal_text_muted'))
                  }
                }
              }.width(76).height(76).padding(0).borderRadius(10)
                .backgroundColor($r('app.color.terminal_background_element'))
                .accessibilityText(I18n.get('feedback.addScreenshot'))
                .enabled(!this.attaching && !this.isSubmitting)
                .onClick(() => { clickHaptic(); this.pickAttachment() })
            }
          }.width('100%')
        }.width('100%')

        Column({ space: 8 }) {
          Text(I18n.get('feedback.contact')).fontSize(14).fontColor($r('app.color.terminal_text')).width('100%')
          TextInput({ text: this.contact, placeholder: I18n.get('feedback.contact_placeholder') })
            .width('100%').height(48).padding({ left: 14, right: 14 }).borderRadius(12).fontSize(14)
            .backgroundColor($r('app.color.terminal_background_element'))
            .fontColor($r('app.color.terminal_text')).placeholderColor($r('app.color.terminal_text_muted'))
            .enabled(!this.isSubmitting).onChange((value: string) => { this.contact = value })
        }.width('100%')

        if (this.error.length > 0) {
          Text(this.error).fontSize(13).fontColor($r('app.color.terminal_error')).width('100%')
        }
        Button() {
          if (this.isSubmitting) {
            LoadingProgress().width(20).height(20).color($r('app.color.terminal_inverse_on_surface'))
          } else {
            Text(I18n.get('feedback.submit')).fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_inverse_on_surface'))
          }
        }.width('100%').height(48).borderRadius(12)
          .backgroundColor($r('app.color.terminal_inverse_surface'))
          .enabled(this.content.trim().length >= 10 && !this.isSubmitting && !this.attaching)
          .onClick(() => { clickHaptic(); this.submit() })
      }.width('100%').padding({ left: 20, right: 20, top: 16, bottom: 24 })
    }
  }

  private isImageContentType(contentType: string): boolean {
    const lower = contentType.toLowerCase()
    return lower.startsWith('image/') ||
      lower.endsWith('png') || lower.endsWith('jpg') || lower.endsWith('jpeg') ||
      lower.endsWith('webp') || lower.endsWith('gif') || lower.endsWith('bmp')
  }

  private async pickAttachment() {
    if (this.attaching || this.isSubmitting || this.attachments.length >= 3) return
    this.attaching = true
    this.error = ''
    try {
      const ctx = this.getUIContext()?.getHostContext() as common.UIAbilityContext
      const picked = await FeedbackFilePicker.pick(ctx)
      if (picked === null) {
        return
      }
      const filename = `feedback-${Date.now()}-${picked.filename}`
      const uploaded = await ApiService.createFeedbackUpload(filename)
      await ApiService.putBinary(uploaded.uploadUrl, picked.bytes)
      const item: AttachmentItem = { url: uploaded.imageUrl, name: picked.filename, contentType: picked.contentType }
      this.attachments.push(item)
    } catch (e) {
      this.error = (e as Error).message || I18n.get('feedback.attach_failed')
    } finally {
      this.attaching = false
    }
  }

  private async submit() {
    if (this.isSubmitting || this.attaching) return
    const content = this.content.trim()
    if (content.length < 10) {
      this.error = I18n.get('feedback.content_too_short')
      return
    }
    this.isSubmitting = true
    this.error = ''
    try {
      const ctx = this.getUIContext()?.getHostContext() as common.UIAbilityContext
      const webhookUrl = ctx.resourceManager.getStringByNameSync('feedback_webhook_url')
      const payload: FeedbackPayload = {
        type: this.feedbackType,
        subtype: '',
        content: content,
        contact: this.contact.trim()
      }
      const ticketId = await FeedbackService.submit(payload, webhookUrl, this.attachments.map((a: AttachmentItem) => a.url))
      AnalyticsService.onEvent(this.feedbackType === 'report'
        ? AnalyticsEvent.SUBMIT_REPORT
        : AnalyticsEvent.SUBMIT_FEEDBACK)
      showToast(`${I18n.get('feedback.submitted')} ${ticketId}`)
      this.pageStack.pop()
    } catch (e) {
      this.error = (e as Error).message || I18n.get('feedback.failed')
    } finally {
      this.isSubmitting = false
    }
  }
}
