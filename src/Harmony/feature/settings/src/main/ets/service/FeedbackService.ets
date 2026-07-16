/**
 * @file FeedbackService.ets
 * @brief Submits feedback to the n8n webhook.
 *
 * Gateway is NOT involved in the feedback flow. The app POSTs the compact JSON
 * body directly to the n8n feedback ingestion webhook. n8n appends a row to
 * Google Sheets for audit trail and returns a ticketId. No HMAC signature —
 * the webhook URL itself is the secret; feedback is not sensitive data.
 */
import { http } from '@kit.NetworkKit'
import { AuthState } from '@rwecho/core'

export type FeedbackType = 'feedback' | 'report'

export interface FeedbackPayload {
  type: FeedbackType
  subtype: string
  content: string
  contact: string
}

export class FeedbackService {
  /**
   * Submit feedback to the n8n webhook. Resolves with the ticketId.
   * Throws on any error — UI layer catches and surfaces an error banner.
   */
  static async submit(payload: FeedbackPayload, webhookUrl: string, attachments: string[]): Promise<string> {
    const timestamp = Date.now()
    const body: Record<string, Object> = {
      'type': payload.type,
      'subtype': payload.subtype,
      'content': payload.content,
      'contact': payload.contact,
      'username': AuthState.getDisplayName(),
      'lang': (AppStorage.get<string>('language') ?? 'zh'),
      'appVersion': (AppStorage.get<string>('appVersion') ?? '1.0.0'),
      'timestamp': timestamp,
      'nonce': `fb-${timestamp}-${Math.floor(Math.random() * 1000000)}`,
      'attachments': attachments
    }
    const bodyStr = JSON.stringify(body)

    return new Promise<string>((resolve, reject) => {
      const httpRequest = http.createHttp()
      const header: Record<string, string> = {
        'Content-Type': 'application/json'
      }
      httpRequest.request(webhookUrl, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: bodyStr,
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 15000,
        readTimeout: 15000
      }, (err, data) => {
        if (err) {
          reject(new Error((err as Error).message || 'Feedback submit failed'))
          return
        }
        if (data.responseCode >= 200 && data.responseCode < 300) {
          const result = data.result as Record<string, Object>
          const ticketId = (result['ticketId'] as string) ?? ''
          if (ticketId.length === 0) {
            reject(new Error('No ticketId in response'))
            return
          }
          resolve(ticketId)
        } else {
          reject(new Error(`Feedback submit failed (${data.responseCode})`))
        }
        httpRequest.destroy()
      })
    })
  }
}
