import { I18n } from '@rwecho/core'

export class TimeUtils {
  static formatRelativeTime(dateStr: string): string {
    if (!dateStr) return ''
    const date = new Date(dateStr)
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffMins = Math.floor(diffMs / 60000)

    if (diffMins < 1) return I18n.get('time.just_now')
    if (diffMins < 60) return I18n.get('time.minutes_ago').replace('{n}', `${diffMins}`)
    if (diffMins < 1440) return I18n.get('time.hours_ago').replace('{n}', `${Math.floor(diffMins / 60)}`)
    return I18n.get('time.days_ago').replace('{n}', `${Math.floor(diffMins / 1440)}`)
  }
}
