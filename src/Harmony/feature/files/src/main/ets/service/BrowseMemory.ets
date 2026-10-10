/**
 * @file BrowseMemory.ets
 * @brief Per-workspace file browser position memory.
 *
 * 每个 workspace 记住上次浏览到的相对路径（本地 preferences，各设备独立），
 * key 为 `files_last_path_{workspaceId}`，值为 '/' 分隔的相对路径；根目录记空串。
 * 终端 cwd 入口（无 workspaceId）不参与记忆——该入口语义是"看会话当前目录"。
 * 记忆路径失效（远端已删除，错误码 path_not_found / path_invalid）时由页面显式
 * toast 告知并回根，不做静默回退。
 */
import { common } from '@kit.AbilityKit'
import { PreferencesUtil } from '@rwecho/core'

export class BrowseMemory {
  private static key(workspaceId: string): string {
    return `files_last_path_${workspaceId}`
  }

  /** 返回记忆的路径段；无记忆或根目录返回 []。 */
  static load(ctx: common.UIAbilityContext, workspaceId: string): string[] {
    if (workspaceId.length === 0) {
      return []
    }
    const raw = PreferencesUtil.getString(ctx, BrowseMemory.key(workspaceId))
    if (raw.length === 0) {
      return []
    }
    return raw.split('/')
  }

  /** segments 为空（根目录）时写空串。 */
  static save(ctx: common.UIAbilityContext, workspaceId: string, segments: string[]): void {
    if (workspaceId.length === 0) {
      return
    }
    PreferencesUtil.setString(ctx, BrowseMemory.key(workspaceId), segments.join('/'))
  }

  static clear(ctx: common.UIAbilityContext, workspaceId: string): void {
    if (workspaceId.length === 0) {
      return
    }
    PreferencesUtil.deleteKey(ctx, BrowseMemory.key(workspaceId))
  }
}
