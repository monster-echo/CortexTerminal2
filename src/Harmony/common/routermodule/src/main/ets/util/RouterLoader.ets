/**
 * @file RouterLoader.ets
 * @brief Loads router map JSON from rawfile and registers route-to-module mappings.
 */
import { resourceManager } from '@kit.LocalizationKit'
import { util } from '@kit.ArkTS'
import { AppRouterInfo } from '../model/AppRouterInfo'

export class RouterLoader {
  private static TAG = '[RouterLoader]'
  private static routerMap: Record<string, AppRouterInfo> = {}

  static async load(context: Context, mapPath: string): Promise<void> {
    try {
      const resMgr: resourceManager.ResourceManager = context.resourceManager
      const rawFileContent = resMgr.getRawFileContentSync(`${mapPath}.json`)
      const textDecoder = util.TextDecoder.create('utf-8')
      const jsonStr = textDecoder.decodeToString(rawFileContent)
      const routerArray = JSON.parse(jsonStr) as Array<Record<string, string>>

      for (const item of routerArray) {
        const info = new AppRouterInfo()
        info.name = item['name'] ?? ''
        if (info.name.length > 0) {
          RouterLoader.routerMap[info.name] = info
        }
      }
      console.info(`${RouterLoader.TAG} Loaded ${routerArray.length} routes from ${mapPath}.json`)
    } catch (e) {
      console.warn(`${RouterLoader.TAG} Failed to load router map: ${(e as Error).message}`)
    }
  }

  static getRouterMap(): Record<string, AppRouterInfo> {
    return RouterLoader.routerMap
  }
}
