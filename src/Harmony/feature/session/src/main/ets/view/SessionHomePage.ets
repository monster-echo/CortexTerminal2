import { SessionInfo, WorkerInfo, ApiService, I18n, RouteName, TerminalNavParam, WorkerNavParam } from '@rwecho/core'
import { SessionCard } from './SessionCard'
import { WorkerCard } from './WorkerCard'
import { CreateSessionSheet } from './CreateSessionSheet'
import { SessionService } from '../service/SessionService'

@Component
export struct SessionHomePage {
  @State activeSessions: SessionInfo[] = []
  @State historySessions: SessionInfo[] = []
  @State workers: WorkerInfo[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State isRefreshing: boolean = false
  @State showCreateSheet: boolean = false
  @State currentTabIndex: number = 0
  @Consume('pageStack') pageStack: NavPathStack

  aboutToAppear() {
    this.loadData()
  }

  build() {
    Column() {
      // AppBar
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.open_sidebar'))
            .fontSize(22)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          // Toggle sidebar via AppStorage
          AppStorage.setOrCreate('sidebarOpen', true)
        })

        Text(I18n.get('session.home.title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_primary'))
          .layoutWeight(1)
          .margin({ left: 8 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(22)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showCreateSheet = true
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)

      // Tabs
      Tabs({ index: $$this.currentTabIndex }) {
        TabContent() {
          this.ActiveTab()
        }
        .tabBar(this.TabBar(I18n.get('session.home.tab_active'), 0))

        TabContent() {
          this.HistoryTab()
        }
        .tabBar(this.TabBar(I18n.get('session.home.tab_history'), 1))

        TabContent() {
          this.WorkersTab()
        }
        .tabBar(this.TabBar(I18n.get('session.home.tab_workers'), 2))
      }
      .width('100%')
      .layoutWeight(1)
      .barMode(BarMode.Fixed)
      .onChange((index: number) => {
        this.currentTabIndex = index
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
    .bindSheet($$this.showCreateSheet, this.CreateSheetContent(), {
      height: SheetSize.LARGE,
      showClose: true,
      onDisappear: () => { this.showCreateSheet = false }
    })
  }

  // ── Tab Bars ────────────────────────────────────────────────────────

  @Builder
  TabBar(label: string, index: number) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentTabIndex === index ? $r('app.color.terminal_primary') : $r('app.color.terminal_on_surface_variant'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  // ── Tab 1: Active Sessions ──────────────────────────────────────────

  @Builder
  ActiveTab() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      Scroll() {
        Column() {
          // Worker availability strip
          Row() {
            Row() {
              Circle().width(8).height(8).fill($r('app.color.terminal_tertiary'))
              Text(`${this.workers.filter(w => w.isOnline).length} ${I18n.get('worker.detail.status_online')}`)
                .fontSize(13)
                .fontColor($r('app.color.terminal_on_surface_variant'))
                .margin({ left: 6 })
            }

            Row() {
              Circle().width(8).height(8).fill($r('app.color.terminal_outline_variant'))
              Text(`${this.workers.filter(w => !w.isOnline).length} ${I18n.get('worker.detail.status_offline')}`)
                .fontSize(13)
                .fontColor($r('app.color.terminal_on_surface_variant'))
                .margin({ left: 6 })
            }
            .margin({ left: 16 })
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_surface_container'))
          .margin({ bottom: 16 })

          // Loading skeletons
          if (this.isLoading) {
            ForEach([0, 1, 2], (_: number) => {
              Row() {
                Row().width(60).height(12).borderRadius(4).backgroundColor($r('app.color.terminal_surface_container_high'))
                Blank()
                Column() {
                  Row().width(100).height(12).borderRadius(4).backgroundColor($r('app.color.terminal_surface_container_high'))
                  Row().width(60).height(10).borderRadius(4).backgroundColor($r('app.color.terminal_surface_container_high')).margin({ top: 6 })
                }.alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .height(60)
              .padding(14)
              .borderRadius(12)
              .backgroundColor($r('app.color.terminal_surface_container'))
              .margin({ bottom: 8 })
            }, (_: number, idx: number) => `${idx}`)
          }

          // Error state
          if (!this.isLoading && this.errorMessage.length > 0) {
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
                .onClick(() => { this.loadData() })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }

          // Session cards
          if (!this.isLoading && this.errorMessage.length === 0) {
            if (this.activeSessions.length === 0) {
              // Empty state
              Column() {
                Text(this.activeEmptyTitle())
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.terminal_on_surface_variant'))
                  .margin({ top: 40 })

                Text(this.activeEmptyDescription())
                  .fontSize(14)
                  .fontColor($r('app.color.terminal_on_surface_variant'))
                  .textAlign(TextAlign.Center)
                  .margin({ top: 8 })
                  .padding({ left: 32, right: 32 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
            } else {
              ForEach(this.activeSessions, (session: SessionInfo) => {
                SessionCard({
                  session: session,
                  onResume: (s: SessionInfo) => { this.resumeSession(s) },
                  onDelete: (s: SessionInfo) => { this.deleteSession(s) },
                  showResumeButton: true
                })
              }, (session: SessionInfo) => session.id)
            }
          }

          Blank()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 8 })
      }
      .width('100%')
      .height('100%')
    }
    .onRefreshing(() => { this.loadData() })
    .width('100%')
    .height('100%')
  }

  // ── Tab 2: History ──────────────────────────────────────────────────

  @Builder
  HistoryTab() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      Scroll() {
        Column() {
          if (!this.isLoading && this.historySessions.length === 0) {
            Column() {
              Text(I18n.get('session.home.empty_history'))
                .fontSize(16)
                .fontColor($r('app.color.terminal_on_surface_variant'))
                .margin({ top: 40 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }

          ForEach(this.historySessions, (session: SessionInfo) => {
            SessionCard({
              session: session,
              onDelete: (s: SessionInfo) => { this.deleteSession(s) },
              showResumeButton: false
            })
          }, (session: SessionInfo) => session.id)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16 })
      }
      .width('100%')
      .height('100%')
    }
    .onRefreshing(() => { this.loadData() })
    .width('100%')
    .height('100%')
  }

  // ── Tab 3: Workers ──────────────────────────────────────────────────

  @Builder
  WorkersTab() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      Scroll() {
        Column() {
          if (!this.isLoading && this.workers.length === 0) {
            Column() {
              Text(I18n.get('session.home.empty_workers'))
                .fontSize(16)
                .fontColor($r('app.color.terminal_on_surface_variant'))
                .margin({ top: 40 })

              Button(I18n.get('session.home.create_button'))
                .height(44)
                .borderRadius(12)
                .backgroundColor($r('app.color.terminal_secondary_container'))
                .fontColor($r('app.color.terminal_on_secondary_container'))
                .margin({ top: 16 })
                .onClick(() => {
                  this.pageStack.pushPath({ name: RouteName.ACTIVATE_WORKER })
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }

          ForEach(this.workers, (worker: WorkerInfo) => {
            WorkerCard({
              worker: worker,
              onCreateSession: (w: WorkerInfo) => { this.createSessionOnWorker(w.id) },
              onViewDetail: (w: WorkerInfo) => {
                const param = new WorkerNavParam()
                param.workerId = w.id
                param.workerName = w.name || w.hostname
                this.pageStack.pushPath({ name: RouteName.WORKER_DETAIL, param: param })
              }
            })
          }, (worker: WorkerInfo) => worker.id)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16 })
      }
      .width('100%')
      .height('100%')
    }
    .onRefreshing(() => { this.loadData() })
    .width('100%')
    .height('100%')
  }

  // ── Create Session Sheet ────────────────────────────────────────────

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

  // ── Actions ─────────────────────────────────────────────────────────

  private resumeSession(session: SessionInfo) {
    const param = new TerminalNavParam()
    param.sessionId = session.id
    param.sessionName = session.name || 'Terminal'
    this.pageStack.pushPath({ name: RouteName.TERMINAL_SESSION, param: param })
  }

  private async deleteSession(session: SessionInfo) {
    try {
      await SessionService.deleteSession(session.id)
      this.activeSessions = this.activeSessions.filter(s => s.id !== session.id)
      this.historySessions = this.historySessions.filter(s => s.id !== session.id)
    } catch (e) {
      AlertDialog.show({
        title: I18n.get('common.error'),
        message: (e as Error).message,
        confirm: { value: I18n.get('common.confirm'), action: () => {} }
      })
    }
  }

  private async createSessionOnWorker(workerId: string) {
    try {
      const session = await SessionService.createSessionOnWorker(workerId)
      const param = new TerminalNavParam()
      param.sessionId = session.id
      param.sessionName = session.name
      this.pageStack.pushPath({ name: RouteName.TERMINAL_SESSION, param: param })
    } catch (e) {
      AlertDialog.show({
        title: I18n.get('session.create.error'),
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
      this.activeSessions = data.activeSessions
      this.historySessions = data.historySessions
      this.workers = data.workers
    } catch (e) {
      this.errorMessage = (e as Error).message
    } finally {
      this.isLoading = false
      this.isRefreshing = false
    }
  }

  private activeEmptyTitle(): string {
    const onlineWorkers = this.workers.filter(w => w.isOnline).length
    if (this.workers.length === 0) return I18n.get('session.home.empty_active_no_worker')
    if (onlineWorkers === 0) return I18n.get('session.home.empty_active_offline')
    return I18n.get('session.home.empty_active_online')
  }

  private activeEmptyDescription(): string {
    return ''
  }
}
