/**
 * @file TerminalHome.ets
 * @brief Home screen with recent session card and new terminal actions
 *
 * Displays the most recent session as a resumable card, provides
 * a "New Terminal" primary action, and shows worker availability.
 */
import { RestApiClient } from '../service/RestApiClient'
import { TerminalStateManager } from '../service/TerminalStateManager'
import { SessionInfo, SessionCreateRequest } from '../model/SessionModels'

@Component
export struct TerminalHome {
  @State recentSessions: SessionInfo[] = []
  @State isLoading: boolean = false
  @State onlineWorkers: number = 0
  @State offlineWorkers: number = 0
  @Consume('pageStack') pageStack: NavPathStack
  private apiClient: RestApiClient = new RestApiClient()

  aboutToAppear() {
    this.loadData()
  }

  build() {
    Scroll() {
      Column() {
        // Header
        Row() {
          Column() {
            Text($r('app.string.app_name'))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.terminal_primary'))

            Text('Your terminal sessions')
              .fontSize(14)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 16 })

        // Worker availability summary strip
        Row() {
          Row() {
            Circle()
              .width(8)
              .height(8)
              .fill($r('app.color.terminal_tertiary'))
            Text(`${this.onlineWorkers} Online`)
              .fontSize(13)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ left: 6 })
          }

          Row() {
            Circle()
              .width(8)
              .height(8)
              .fill($r('app.color.terminal_outline_variant'))
            Text(`${this.offlineWorkers} Offline`)
              .fontSize(13)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ left: 6 })
          }
          .margin({ left: 16 })
        }
        .width('calc(100% - 40vp)')
        .margin({ top: 8 })
        .padding(12)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))

        // Recent session card
        if (this.recentSessions.length > 0) {
          Column() {
            Text('Recent Session')
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

        // Empty state
        if (!this.isLoading && this.recentSessions.length === 0) {
          Column() {
            Text('No active sessions')
              .fontSize(16)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ top: 40 })

            Text('Start a new terminal session to begin')
              .fontSize(14)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ top: 8 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }

        Blank()

        // New Terminal primary action button
        Button('New Terminal')
          .width('calc(100% - 40vp)')
          .height(52)
          .borderRadius(14)
          .backgroundColor($r('app.color.terminal_secondary_container'))
          .fontColor($r('app.color.terminal_on_secondary_container'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 16 })
          .onClick(() => {
            this.createNewSession()
          })

        // Choose Worker secondary action
        Button('Choose Worker')
          .width('calc(100% - 40vp)')
          .height(48)
          .borderRadius(14)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.terminal_secondary'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .borderWidth(1)
          .borderColor($r('app.color.terminal_outline_variant'))
          .margin({ top: 8, bottom: 20 })
          .onClick(() => {
            AppStorage.setOrCreate('navigateTo', 'Workers')
          })
      }
      .width('100%')
      .height('100%')
    }
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
      Button('Resume')
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
    try {
      const sessions = await this.apiClient.listSessions()
      this.recentSessions = sessions
      const workers = await this.apiClient.listWorkers()
      this.onlineWorkers = workers.filter(w => w.status === 'online').length
      this.offlineWorkers = workers.filter(w => w.status !== 'online').length
    } catch (e) {
      console.warn('Failed to load terminal home data: ' + (e as Error).message)
    } finally {
      this.isLoading = false
    }
  }

  private async createNewSession() {
    this.isLoading = true
    try {
      const request = new SessionCreateRequest()
      request.name = `Terminal ${new Date().toLocaleTimeString()}`
      const session = await this.apiClient.createSession(request)
      AppStorage.setOrCreate('navSessionId', session.id)
      AppStorage.setOrCreate('navSessionName', session.name)
      this.pageStack.pushPath({ name: 'TerminalSession' })
    } catch (e) {
      console.error('Failed to create session: ' + (e as Error).message)
    } finally {
      this.isLoading = false
    }
  }
}
