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
    PageLayout({
      title: I18n.get('feedback.title_feedback') + (this.currentLanguage ? '' : '')
    }) {
      Column() {
        Text(I18n.get('feedback.content') + (this.currentLanguage ? '' : ''))
          .fontSize(14)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .width('100%')
          .margin({ bottom: 8 })

        TextArea({ text: this.content, placeholder: I18n.get('feedback.content_placeholder') + (this.currentLanguage ? '' : '') })
          .width('100%')
          .height(120)
          .borderRadius(8)
          .backgroundColor($r('app.color.terminal_surface_container_high'))
          .fontColor($r('app.color.terminal_primary'))
          .placeholderColor($r('app.color.terminal_on_surface_variant'))
          .fontSize(14)
          .onChange((value: string) => {
            this.content = value
          })

        Text(I18n.get('feedback.contact') + (this.currentLanguage ? '' : ''))
          .fontSize(14)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .width('100%')
          .margin({ top: 16, bottom: 8 })

        TextInput({ text: this.contact, placeholder: I18n.get('feedback.contact_placeholder') + (this.currentLanguage ? '' : '') })
          .width('100%')
          .height(44)
          .borderRadius(8)
          .backgroundColor($r('app.color.terminal_surface_container_high'))
          .fontColor($r('app.color.terminal_primary'))
          .placeholderColor($r('app.color.terminal_on_surface_variant'))
          .fontSize(14)
          .onChange((value: string) => {
            this.contact = value
          })

        Text(I18n.get('feedback.attachments') + (this.currentLanguage ? '' : ''))
          .fontSize(14)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .width('100%')
          .margin({ top: 16, bottom: 8 })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.attachments, (item: AttachmentItem, index: number) => {
            Stack({ alignContent: Alignment.TopEnd }) {
              if (this.isImageContentType(item.contentType)) {
                Image(item.url)
                  .width(72)
                  .height(72)
                  .borderRadius(8)
                  .objectFit(ImageFit.Cover)
              } else {
                Column() {
                  Text(item.name)
                    .fontSize(10)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontColor($r('app.color.terminal_on_surface_variant'))
                    .textAlign(TextAlign.Center)
                }
                .width(72)
                .height(72)
                .borderRadius(8)
                .backgroundColor($r('app.color.terminal_surface_container_high'))
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .padding(4)
              }
              Text('×')
                .fontSize(13)
                .fontColor($r('app.color.terminal_on_secondary_container'))
                .backgroundColor($r('app.color.terminal_error'))
                .width(20)
                .height(20)
                .borderRadius(10)
                .textAlign(TextAlign.Center)
                .margin({ top: -6, right: -6 })
            }
            .width(72)
            .height(72)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              clickHaptic()
              this.attachments.splice(index, 1)
            })
          })

          if (this.attachments.length < 3) {
            Column() {
              if (this.attaching) {
                LoadingProgress().width(24).height(24).color($r('app.color.terminal_on_surface_variant'))
              } else {
                Text('+')
                  .fontSize(24)
                  .fontColor($r('app.color.terminal_on_surface_variant'))
              }
            }
            .width(72)
            .height(72)
            .borderRadius(8)
            .backgroundColor($r('app.color.terminal_surface_container_high'))
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              clickHaptic()
              this.pickAttachment()
            })
          }
        }
        .width('100%')

        if (this.error.length > 0) {
          Text(this.error)
            .fontSize(13)
            .fontColor($r('app.color.terminal_error'))
            .width('100%')
            .margin({ top: 12 })
        }

        Button() {
          if (this.isSubmitting) {
            LoadingProgress().width(20).height(20).color(Color.White)
          } else {
            Text(I18n.get('feedback.submit') + (this.currentLanguage ? '' : ''))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_on_secondary_container'))
          }
        }
        .width('100%')
        .height(48)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .margin({ top: 20 })
        .enabled(!this.isSubmitting)
        .opacity(this.isSubmitting ? 0.5 : 1)
        .onClick(() => {
          clickHaptic()
          this.submit()
        })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8 })
    }
  }

  private isImageContentType(contentType: string): boolean {
    const lower = contentType.toLowerCase()
    return lower.startsWith('image/') ||
      lower.endsWith('png') || lower.endsWith('jpg') || lower.endsWith('jpeg') ||
      lower.endsWith('webp') || lower.endsWith('gif') || lower.endsWith('bmp')
  }

  private async pickAttachment() {
    this.error = ''
    try {
      const ctx = this.getUIContext()?.getHostContext() as common.UIAbilityContext
      const picked = await FeedbackFilePicker.pick(ctx)
      if (picked === null) {
        return
      }
      this.attaching = true
      const filename = `feedback-${Date.now()}-${picked.filename}`
      const uploaded = await ApiService.createFeedbackUpload(filename)
      await ApiService.putBinaryToS3(uploaded.uploadUrl, picked.bytes)
      const item: AttachmentItem = { url: uploaded.imageUrl, name: picked.filename, contentType: picked.contentType }
      this.attachments.push(item)
    } catch (e) {
      this.error = (e as Error).message || I18n.get('feedback.attach_failed')
    } finally {
      this.attaching = false
    }
  }

  private async submit() {
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
