/**
 * @file MarketLauncher.ets
 * @brief Opens the app's detail page in Huawei AppGallery so the user can rate the app.
 */
import { common, Want } from '@kit.AbilityKit'

export class MarketLauncher {
  static async openAppDetail(context: common.UIAbilityContext): Promise<void> {
    const bundleName = context.abilityInfo.bundleName
    const want: Want = {
      uri: `store://appgallery.huawei.com/app/detail?id=${bundleName}`
    }
    await context.startAbility(want)
  }
}
