/**
 * @file TerminalHome.ets
 * @brief Home screen with recent session card and new terminal actions
 *
 * Displays the most recent session as a resumable card, provides
 * a "New Terminal" primary action, and shows worker availability.
 */
import { RestApiClient } from '../service/RestApiClient'
import { SessionInfo } from '../model/SessionModels'

@Component
export struct TerminalHome {
  @State recentSessions: SessionInfo[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State onlineWorkers: number = 0
  @State offlineWorkers: number = 0
  @State isRefreshing: boolean = false
  @Consume('pageStack') pageStack: NavPathStack
  private apiClient: RestApiClient = new RestApiClient()

  aboutToAppear() {
    console.info('[TerminalHome] aboutToAppear')
    this.loadData()
  }

  build() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      Scroll() {
        Column() {
        // Worker availability summary strip
        Row() {
          Row() {
            Circle()
              .width(8)
              .height(8)
              .fill($r('app.color.terminal_tertiary'))
            Text(`${this.onlineWorkers} 在线`)
              .fontSize(13)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ left: 6 })
          }

          Row() {
            Circle()
              .width(8)
              .height(8)
              .fill($r('app.color.terminal_outline_variant'))
            Text(`${this.offlineWorkers} 离线`)
              .fontSize(13)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ left: 6 })
          }
          .margin({ left: 16 })
        }
        .width('calc(100% - 40vp)')
        .margin({ top: 16 })
        .padding(12)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))

        // Recent session card
        if (this.recentSessions.length > 0) {
          Column() {
            Text('最近会话')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .width('100%')
              .margin({ bottom: 12 })

            ForEach(this.recentSessions.slice(0, 3), (session: SessionInfo) => {
              this.SessionCard(session)
            }, (session: SessionInfo) => session.id)
          }
          .width('calc(100% - 40vp)')
          .margin({ top: 20 })
        }

        // Loading indicator
        if (this.isLoading) {
          LoadingProgress()
            .width(32)
            .height(32)
            .color($r('app.color.terminal_secondary'))
            .margin({ top: 40 })
        }

        // Error state
        if (!this.isLoading && this.errorMessage.length > 0) {
          Column() {
            Text('连接网关失败')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_error'))
              .margin({ top: 40 })

            Text(this.errorMessage)
              .fontSize(13)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .textAlign(TextAlign.Center)
              .margin({ top: 8 })
              .padding({ left: 28, right: 28 })

            Button('重试')
              .height(44)
              .borderRadius(12)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .margin({ top: 16 })
              .onClick(() => {
                this.loadData()
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }

        // Empty state
        if (!this.isLoading && this.errorMessage.length === 0 && this.recentSessions.length === 0) {
          Column() {
            Text(this.emptyTitle())
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ top: 40 })

            Text(this.emptyDescription())
              .fontSize(14)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .textAlign(TextAlign.Center)
              .margin({ top: 8 })
              .padding({ left: 32, right: 32 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }

        Blank()
      }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .onRefreshing(() => {
      this.loadData()
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
  }

  @Builder
  SessionCard(session: SessionInfo) {
    Row() {
      // Status chip
      Row() {
        Circle()
          .width(8)
          .height(8)
          .fill(this.getStatusColor(session.status))
        Text(session.status)
          .fontSize(11)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ left: 6 })
      }
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(8)
      .backgroundColor($r('app.color.terminal_surface_container'))

      Blank()

      // Session info
      Column() {
        Text(session.name || `Session ${session.id.substring(0, 8)}`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.formatTime(session.updatedAt))
          .fontSize(12)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.End)
      .layoutWeight(1)

      // Resume button
      Button('恢复')
        .height(32)
        .borderRadius(8)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .fontSize(13)
        .margin({ left: 12 })
        .onClick(() => {
          AppStorage.setOrCreate('navSessionId', session.id)
          AppStorage.setOrCreate('navSessionName', session.name || 'Terminal')
          this.pageStack.pushPath({ name: 'TerminalSession' })
        })
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_surface_container'))
    .margin({ bottom: 8 })
  }

  private getStatusColor(status: string): ResourceColor {
    switch (status.toLowerCase()) {
      case 'live':
      case 'connected':
      case 'running':
        return $r('app.color.terminal_tertiary')
      case 'reconnecting':
      case 'connecting':
        return '#FFC107'
      case 'expired':
        return $r('app.color.terminal_error')
      default:
        return $r('app.color.terminal_outline_variant')
    }
  }

  private formatTime(dateStr: string): string {
    if (!dateStr) {
      return ''
    }
    const date = new Date(dateStr)
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffMins = Math.floor(diffMs / 60000)

    if (diffMins < 1) {
      return 'Just now'
    } else if (diffMins < 60) {
      return `${diffMins}m ago`
    } else if (diffMins < 1440) {
      return `${Math.floor(diffMins / 60)}h ago`
    } else {
      return `${Math.floor(diffMins / 1440)}d ago`
    }
  }

  private async loadData() {
    this.isLoading = true
    this.errorMessage = ''
    try {
      const sessions = await this.apiClient.listSessions()
      this.recentSessions = sessions
      const workers = await this.apiClient.listWorkers()
      this.onlineWorkers = workers.filter(w => w.status.toLowerCase() === 'online' || w.isOnline === true).length
      this.offlineWorkers = workers.length - this.onlineWorkers
    } catch (e) {
      this.errorMessage = (e as Error).message || '网络请求失败'
    } finally {
      this.isLoading = false
      this.isRefreshing = false
    }
  }

  private totalWorkers(): number {
    return this.onlineWorkers + this.offlineWorkers
  }

  private emptyTitle(): string {
    if (this.totalWorkers() === 0) {
      return '还没有可用 Worker'
    }
    if (this.onlineWorkers === 0) {
      return 'Worker 当前离线'
    }
    return '暂无活跃会话'
  }

  private emptyDescription(): string {
    if (this.totalWorkers() === 0) {
      return '激活或选择一个 Worker 后，就可以从手机打开云端终端。'
    }
    if (this.onlineWorkers === 0) {
      return '打开 Workers 查看节点状态，等节点在线后再创建终端。'
    }
    return '创建一个新终端会话，或从侧边栏恢复最近会话。'
  }

}
