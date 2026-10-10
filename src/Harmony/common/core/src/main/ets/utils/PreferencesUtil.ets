/**
 * @file PreferencesUtil.ets
 * @brief Lightweight singleton wrapper over @ohos.data.preferences for string key-values.
 *
 * 统一 common/core 之外的模块对本地 preferences 的访问：单例持有 Preferences 实例，
 * 只暴露 string 的 get / set / delete。写入即 flushSync 落盘（putSync 只写内存）。
 */
import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'

export class PreferencesUtil {
  private static readonly STORE_NAME = 'corterm_prefs'
  private static instance: preferences.Preferences | null = null

  private static store(ctx: common.UIAbilityContext): preferences.Preferences {
    if (PreferencesUtil.instance === null) {
      PreferencesUtil.instance = preferences.getPreferencesSync(ctx, { name: PreferencesUtil.STORE_NAME })
    }
    return PreferencesUtil.instance
  }

  static getString(ctx: common.UIAbilityContext, key: string, defaultValue: string = ''): string {
    return PreferencesUtil.store(ctx).getSync(key, defaultValue) as string
  }

  static setString(ctx: common.UIAbilityContext, key: string, value: string): void {
    const store = PreferencesUtil.store(ctx)
    store.putSync(key, value)
    // putSync 只写内存，必须 flush 才会落盘
    store.flushSync()
  }

  static deleteKey(ctx: common.UIAbilityContext, key: string): void {
    const store = PreferencesUtil.store(ctx)
    store.deleteSync(key)
    store.flushSync()
  }
}
