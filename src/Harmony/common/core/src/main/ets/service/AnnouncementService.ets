/**
 * @file AnnouncementService.ets
 * @brief Fetches gateway announcements and tracks locally-dismissed ids.
 *
 * 公告由网关配置下发（/api/announcements），客户端用本地 preferences 记录
 * 已关闭的公告 Id：每条公告对每台设备只弹一次。pending() 返回第一条未关闭的公告。
 */
import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { ApiService } from './ApiService'
import { AnnouncementInfo } from '../model/SharedModels'

export class AnnouncementService {
  private static readonly STORE_NAME = 'corterm_announcements'
  private static readonly KEY_DISMISSED = 'dismissedIds'

  static async pending(ctx: common.UIAbilityContext): Promise<AnnouncementInfo | null> {
    const dismissed = AnnouncementService.readDismissed(ctx)
    const announcements = await ApiService.listAnnouncements()
    for (let i = 0; i < announcements.length; i++) {
      if (!dismissed.includes(announcements[i].id)) {
        return announcements[i]
      }
    }
    return null
  }

  static dismiss(ctx: common.UIAbilityContext, id: string): void {
    const dismissed = AnnouncementService.readDismissed(ctx)
    if (dismissed.includes(id)) {
      return
    }
    dismissed.push(id)
    const store = preferences.getPreferencesSync(ctx, { name: AnnouncementService.STORE_NAME })
    store.putSync(AnnouncementService.KEY_DISMISSED, JSON.stringify(dismissed))
  }

  private static readDismissed(ctx: common.UIAbilityContext): string[] {
    const store = preferences.getPreferencesSync(ctx, { name: AnnouncementService.STORE_NAME })
    const raw = store.getSync(AnnouncementService.KEY_DISMISSED, '') as string
    if (raw.length === 0) {
      return []
    }
    return JSON.parse(raw) as string[]
  }
}
