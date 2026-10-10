/**
 * @file TransferRouteLog.ets
 * @brief In-memory log of file-transfer endpoint results (LAN / P2P / public / relay).
 *
 * 端点协商每次尝试与最终成功通道都记录在这里，供 FileBrowserPage 的通道图标
 * sheet 展示"P2P 是否打通 / 最近一次走的哪条通道"。进程内生命周期，不做持久化。
 */
export interface RouteEntry {
  /** lan | p2p | public | relay */
  route: string;
  /** 尝试成功（最终承接传输的通道）/ 失败（回落到下一端点） */
  ok: boolean;
  timeMs: number;
}

export class TransferRouteLog {
  private static readonly MAX_ENTRIES = 20
  private static entries: RouteEntry[] = []

  static record(route: string, ok: boolean): void {
    TransferRouteLog.entries.push({ route: route, ok: ok, timeMs: Date.now() })
    if (TransferRouteLog.entries.length > TransferRouteLog.MAX_ENTRIES) {
      TransferRouteLog.entries = TransferRouteLog.entries.slice(TransferRouteLog.entries.length - TransferRouteLog.MAX_ENTRIES)
    }
  }

  static history(): RouteEntry[] {
    return TransferRouteLog.entries
  }

  /** 最近一次成功传输的通道；无传输返回 ''。 */
  static lastSuccessRoute(): string {
    for (let i = TransferRouteLog.entries.length - 1; i >= 0; i--) {
      if (TransferRouteLog.entries[i].ok) {
        return TransferRouteLog.entries[i].route
      }
    }
    return ''
  }
}
