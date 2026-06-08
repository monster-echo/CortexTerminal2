import { SessionInfo, I18n, RouteName, TerminalNavParam, showI18nToast, AnalyticsService, AnalyticsEvent, lightHaptic, clickHaptic } from '@rwecho/core'
import { SessionCard } from './SessionCard'
import { CreateSessionSheet } from './CreateSessionSheet'
import { SessionService } from '../service/SessionService'

@Component
export struct SessionHomePage {
  @State allSessions: SessionInfo[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State isRefreshing: boolean = false
  @State showCreateSheet: boolean = false
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('triggerCreateSession') @Watch('onCreateTriggered') createTrigger: boolean = false

  onCreateTriggered() {
    if (this.createTrigger) {
      this.showCreateSheet = true
      this.createTrigger = false
    }
  }

  aboutToAppear() {
    AnalyticsService.onPageStart('session/Home')
    this.loadData()
  }

  build() {
    Column() {
      Refresh({ refreshing: $$this.isRefreshing }) {
        if (this.isLoading) {
          Column() {
            ForEach([0, 1, 2], (_: number, idx: number) => {
              Row() {
                Column() {
                  Row().width(120).height(14).borderRadius(4)
                    .backgroundColor($r('app.color.terminal_surface_container_high'))
                  Row().width(80).height(10).borderRadius(4)
                    .backgroundColor($r('app.color.terminal_surface_container_high'))
                    .margin({ top: 6 })
                  Row().width(60).height(10).borderRadius(4)
                    .backgroundColor($r('app.color.terminal_surface_container_high'))
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Blank()
                Row().width(48).height(20).borderRadius(8)
                  .backgroundColor($r('app.color.terminal_surface_container_high'))
              }
              .width('100%')
              .height(72)
              .padding(14)
              .borderRadius(12)
              .backgroundColor($r('app.color.terminal_surface_container'))
              .margin({ bottom: 8 })
            }, (_: number, idx: number) => `${idx}`)
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 8 })
        } else if (this.errorMessage.length > 0) {
          Column() {
            Text(I18n.get('common.error'))
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

            Button(I18n.get('common.retry'))
              .height(44)
              .borderRadius(12)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .margin({ top: 16 })
              .onClick(() => { clickHaptic(); this.loadData() })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 20, right: 20 })
        } else if (this.allSessions.length === 0) {
          Column() {
            Text(I18n.get('session.home.empty_history'))
              .fontSize(16)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ top: 40 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 20, right: 20 })
        } else {
          List({ space: 8 }) {
            ForEach(this.allSessions, (session: SessionInfo) => {
              ListItem() {
                SessionCard({ session: session })
              }
              .swipeAction({ end: this.DeleteSwipeButton(session) })
              .onClick(() => { lightHaptic(); this.resumeSession(session) })
            }, (session: SessionInfo) => session.id)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 20, right: 20, top: 8 })
        }
      }
      .onRefreshing(() => { this.loadData() })
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.terminal_surface'))
    .bindSheet($$this.showCreateSheet, this.CreateSheetContent(), {
      height: SheetSize.LARGE,
      showClose: true,
      onDisappear: () => { this.showCreateSheet = false }
    })
  }

  @Builder
  DeleteSwipeButton(session: SessionInfo) {
    Button() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(18)
        .fontColor([$r('app.color.terminal_error')])
    }
    .width(64)
    .height('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_surface_container_high'))
    .onClick(() => { clickHaptic(); this.confirmDelete(session) })
  }

  @Builder
  CreateSheetContent() {
    CreateSessionSheet({
      onSessionCreated: (sessionId: string, sessionName: string) => {
        this.showCreateSheet = false
        const param = new TerminalNavParam()
        param.sessionId = sessionId
        param.sessionName = sessionName
        this.pageStack.pushPath({ name: RouteName.TERMINAL_SESSION, param: param })
      }
    })
  }

  private resumeSession(session: SessionInfo) {
    AnalyticsService.onEvent(AnalyticsEvent.SESSION_RESUME)
    const param = new TerminalNavParam()
    param.sessionId = session.id
    param.sessionName = session.name || 'Terminal'
    this.pageStack.pushPath({ name: RouteName.TERMINAL_SESSION, param: param })
  }

  private confirmDelete(session: SessionInfo) {
    this.getUIContext()?.showAlertDialog({
      title: I18n.get('session.card.delete_confirm_title'),
      message: I18n.get('session.card.delete_confirm_message'),
      primaryButton: {
        value: I18n.get('common.cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: I18n.get('common.delete'),
        fontColor: $r('app.color.terminal_error'),
        action: () => { this.deleteSession(session) }
      }
    })
  }

  private async deleteSession(session: SessionInfo) {
    try {
      await SessionService.deleteSession(session.id)
      this.allSessions = this.allSessions.filter(s => s.id !== session.id)
      AnalyticsService.onEvent(AnalyticsEvent.SESSION_DELETE)
      showI18nToast('session.deleted')
    } catch (e) {
      this.getUIContext()?.showAlertDialog({
        title: I18n.get('common.error'),
        message: (e as Error).message,
        confirm: { value: I18n.get('common.confirm'), action: () => {} }
      })
    }
  }

  private async loadData() {
    this.isLoading = true
    this.errorMessage = ''
    try {
      const data = await SessionService.loadHomeData()
      const all = data.activeSessions.concat(data.historySessions)
      all.sort((a: SessionInfo, b: SessionInfo) => {
        const timeA = new Date(a.updatedAt || a.createdAt).getTime()
        const timeB = new Date(b.updatedAt || b.createdAt).getTime()
        return timeB - timeA
      })
      this.allSessions = all
    } catch (e) {
      this.errorMessage = (e as Error).message
    } finally {
      this.isLoading = false
      this.isRefreshing = false
    }
  }
}
