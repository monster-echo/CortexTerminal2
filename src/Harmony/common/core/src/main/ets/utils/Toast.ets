import { promptAction } from '@kit.ArkUI'
import { I18n } from '../i18n/I18n'

export function showToast(message: string, duration: number = 2000) {
  promptAction.showToast({ message, duration })
}

export function showI18nToast(key: string) {
  showToast(I18n.get(key))
}
