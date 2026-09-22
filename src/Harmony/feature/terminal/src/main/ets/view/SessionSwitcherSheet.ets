/**
 * @file SessionSwitcherSheet.ets
 * @brief Quick session switcher sheet, opened from the terminal title.
 *
 * Mirrors the Flutter端 SessionSelectorSheet: RUNNING sessions first, then
 * RECENT ones; tapping an entry switches the terminal to that session.
 */
import { ApiService, SessionInfo, I18n, lightHaptic } from '@rwecho/core'

@Component
export struct SessionSwitcherSheet {
  currentSessionId: string = ''
  onPick: (session: SessionInfo) => void = (_s: SessionInfo) => {}
  @State sessions: SessionInfo[] = []
  @State loadError: string = ''

  aboutToAppear() {
    this.load()
  }

  build() {
    Column() {
      Text(I18n.get('sidebar.sessions'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_on_surface'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })

      if (this.loadError.length > 0) {
        Text(this.loadError)
          .fontSize(14)
          .fontColor($r('app.color.terminal_error'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      } else if (this.sessions.length === 0) {
        Text(I18n.get('session.home.guide.no_session'))
          .fontSize(14)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      } else {
        List() {
          if (this.activeSessions().length > 0) {
            ListItem() {
              this.SectionHeader(I18n.get('session.home.tab_active'))
            }

            ForEach(this.activeSessions(), (session: SessionInfo) => {
              ListItem() {
                this.SessionRow(session)
              }
            }, (session: SessionInfo) => `active-${session.id}`)
          }

          if (this.endedSessions().length > 0) {
            ListItem() {
              this.SectionHeader(I18n.get('session.home.tab_history'))
            }

            ForEach(this.endedSessions(), (session: SessionInfo) => {
              ListItem() {
                this.SessionRow(session)
              }
            }, (session: SessionInfo) => `ended-${session.id}`)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
    }
    .width('100%')
  }

  @Builder
  SectionHeader(label: string) {
    Text(label)
      .fontSize(12)
      .fontColor($r('app.color.terminal_on_surface_variant'))
      .width('100%')
      .padding({ top: 8, bottom: 6 })
  }

  @Builder
  SessionRow(session: SessionInfo) {
    Row() {
      Circle()
        .width(7)
        .height(7)
        .fill(this.sessionStatusColor(session.status))

      Column() {
        Text(session.name || `session ${session.id.substring(0, 8)}`)
          .fontSize(14)
          .fontWeight(session.id === this.currentSessionId ? FontWeight.Medium : FontWeight.Normal)
          .fontColor($r('app.color.terminal_on_surface'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(session.status.length > 0 ? session.status : 'idle')
          .fontSize(11)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })

      if (session.id === this.currentSessionId) {
        Text('✓')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_primary'))
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 10, right: 10 })
    .borderRadius(10)
    .backgroundColor(session.id === this.currentSessionId ?
      $r('app.color.terminal_primary_container') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      lightHaptic()
      this.onPick(session)
    })
  }

  private isActive(status: string): boolean {
    const s = status.toLowerCase()
    return s === 'running' || s === 'idle' || s === 'live' || s === 'connected'
  }

  private activeSessions(): SessionInfo[] {
    return this.sessions.filter((s: SessionInfo): boolean => this.isActive(s.status))
  }

  private endedSessions(): SessionInfo[] {
    return this.sessions.filter((s: SessionInfo): boolean => !this.isActive(s.status)).slice(0, 10)
  }

  private async load() {
    this.loadError = ''
    try {
      this.sessions = await ApiService.listSessions()
    } catch (e) {
      this.loadError = (e as Error).message
      this.sessions = []
    }
  }

  private sessionStatusColor(status: string): ResourceColor {
    switch (status.toLowerCase()) {
      case 'live':
      case 'connected':
      case 'running':
        return $r('app.color.terminal_tertiary')
      case 'expired':
      case 'failed':
      case 'error':
        return $r('app.color.terminal_error')
      default:
        return $r('app.color.terminal_outline')
    }
  }
}
