/**
 * @file FeedbackService.ets
 * @brief Submits feedback / report to the n8n webhook with HMAC-SHA256 signature.
 *
 * Gateway is NOT involved in the feedback flow. The app signs the compact JSON
 * body with a shared secret (compiled into string.json) and POSTs directly to
 * the n8n feedback ingestion webhook. n8n verifies the signature, appends a row
 * to Google Sheets for audit trail, and returns a ticketId.
 *
 * Signature must match n8n exactly: HMAC-SHA256(secret, JSON.stringify(body))
 * with no whitespace / indentation in the body string.
 */
import { http } from '@kit.NetworkKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { util } from '@kit.ArkTS'
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
   * Submit feedback / report to the n8n webhook. Resolves with the ticketId.
   * Throws on any error — UI layer catches and surfaces an error banner.
   */
  static async submit(payload: FeedbackPayload, webhookUrl: string, secret: string, attachments: string[]): Promise<string> {
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
    const signature = await FeedbackService.hmacSha256Hex(secret, bodyStr)

    return new Promise<string>((resolve, reject) => {
      const httpRequest = http.createHttp()
      const header: Record<string, string> = {
        'Content-Type': 'application/json',
        'X-Signature': signature
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

  private static async hmacSha256Hex(secret: string, message: string): Promise<string> {
    const mac = cryptoFramework.createMac('SHA256')
    const symKeyGenerator = cryptoFramework.createSymKeyGenerator('SHA256')
    const keyBlob: cryptoFramework.DataBlob = { data: FeedbackService.toUtf8(secret) }
    const symKey = await symKeyGenerator.convertKey(keyBlob)
    await mac.init(symKey)
    await mac.update({ data: FeedbackService.toUtf8(message) })
    const macOutput: cryptoFramework.DataBlob = mac.doFinalSync()
    return FeedbackService.toHex(macOutput.data)
  }

  private static toUtf8(str: string): Uint8Array {
    const encoder = new util.TextEncoder('utf-8')
    return encoder.encodeInto(str)
  }

  private static toHex(bytes: Uint8Array): string {
    let hex = ''
    for (let i = 0; i < bytes.length; i++) {
      const b = bytes[i]
      hex += (b < 16 ? '0' : '') + b.toString(16)
    }
    return hex
  }
}
