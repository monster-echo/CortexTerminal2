import { zhStrings } from './strings/zh'
import { enStrings } from './strings/en'

type StringMap = Record<string, string>

export class I18n {
  private static maps: Record<string, StringMap> = {
    'zh': zhStrings,
    'en': enStrings,
  }

  static get(key: string): string {
    const locale = AppStorage.get<string>('language') || 'zh'
    const map = I18n.maps[locale] ?? zhStrings
    return map[key] ?? zhStrings[key] ?? key
  }

  static getWithArgs(key: string, args: Record<string, string>): string {
    let text = I18n.get(key)
    const keys = Object.keys(args)
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i]
      text = text.replace(`{${k}}`, args[k])
    }
    return text
  }

  static getLocale(): string {
    return AppStorage.get<string>('language') || 'zh'
  }

  static setLocale(locale: string): void {
    AppStorage.setOrCreate('language', locale)
  }
}
