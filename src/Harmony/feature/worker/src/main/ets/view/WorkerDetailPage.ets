/**
 * @file WorkerDetailPage.ets
 * @brief Worker dashboard with session management
 *
 * Displays detailed worker information including system stats,
 * active sessions, and provides actions like creating new sessions
 * or connecting to existing ones.
 */
import { ApiService, I18n, RouteName, WorkerInfo, WorkerSessionInfo, SessionCreateRequest, showI18nToast, showToast, AnalyticsService, lightHaptic, clickHaptic } from '@rwecho/core'

interface WorkspaceItem {
  id: string;
  name: string;
  rootPath: string;
  isDefault: boolean;
}

@Component
export struct WorkerDetailPage {
  @StorageLink('navWorkerId') workerId: string = ''
  @StorageLink('navWorkerName') workerName: string = 'Worker'
  @State worker: WorkerInfo | null = null
  @State sessions: WorkerSessionInfo[] = []
  @State workspaces: WorkspaceItem[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State showCreateWorkspace: boolean = false
  @State newWorkspaceName: string = ''
  @State newWorkspacePath: string = ''
  @Consume('pageStack') pageStack: NavPathStack

  aboutToAppear() {
    AnalyticsService.onPageStart('worker/Detail')
    this.loadWorkerDetail()
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          if (this.isLoading) {
            LoadingProgress()
              .width(40)
              .height(40)
              .color($r('app.color.terminal_secondary'))
              .margin({ top: 40 })
          } else if (this.errorMessage.length > 0) {
            Column() {
              Text(this.errorMessage)
                .fontSize(14)
                .fontColor($r('app.color.terminal_error'))
                .textAlign(TextAlign.Center)

              Button(I18n.get('common.retry'))
                .height(36)
                .borderRadius(8)
                .backgroundColor($r('app.color.terminal_secondary_container'))
                .fontColor($r('app.color.terminal_on_secondary_container'))
                .fontSize(13)
                .margin({ top: 16 })
                .onClick(() => {
                  clickHaptic()
                  this.errorMessage = ''
                  this.loadWorkerDetail()
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .margin({ top: 40 })
          }

          // Worker info card
          if (this.worker) {
            this.WorkerInfoCard()
          }

          // Workspaces section
          Column() {
            Row() {
              Text(I18n.get('workspaces.title'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.terminal_primary'))
                .layoutWeight(1)

              Button(I18n.get('workspaces.create'))
                .height(32)
                .borderRadius(8)
                .backgroundColor($r('app.color.terminal_secondary_container'))
                .fontColor($r('app.color.terminal_on_secondary_container'))
                .fontSize(13)
                .onClick(() => {
                  clickHaptic()
                  this.showCreateWorkspace = true
                })
            }
            .width('100%')
            .margin({ bottom: 12 })

            if (this.workspaces.length === 0) {
              Text(I18n.get('workspaces.empty'))
                .fontSize(14)
                .fontColor($r('app.color.terminal_on_surface_variant'))
            } else {
              ForEach(this.workspaces, (ws: WorkspaceItem) => {
                this.WorkspaceCard(ws)
              }, (ws: WorkspaceItem) => ws.id)
            }
          }
          .width('calc(100% - 40vp)')
          .margin({ top: 24 })

          // Active sessions section
          Column() {
            Text(I18n.get('worker.detail.sessions'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_primary'))
              .width('100%')
              .margin({ bottom: 12 })

            if (this.sessions.length === 0) {
              Text(I18n.get('session.home.empty_history'))
                .fontSize(14)
                .fontColor($r('app.color.terminal_on_surface_variant'))
            } else {
              ForEach(this.sessions, (session: WorkerSessionInfo) => {
                this.SessionCard(session)
              }, (session: WorkerSessionInfo) => session.id)
            }
          }
          .width('calc(100% - 40vp)')
          .margin({ top: 24 })

          // New Session button
          if (this.worker && this.worker.isOnline) {
            Button(I18n.get('worker.detail.new_terminal'))
              .width('calc(100% - 40vp)')
              .height(48)
              .borderRadius(12)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 24 })
              .onClick(() => {
                clickHaptic()
                this.createNewSession()
              })
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.terminal_surface'))
    .bindSheet(this.showCreateWorkspace, this.CreateWorkspaceSheet(), {
      backgroundColor: $r('app.color.terminal_surface'),
      onDisappear: () => { this.showCreateWorkspace = false }
    })
  }

  @Builder
  CreateWorkspaceSheet() {
    Column() {
      Text(I18n.get('workspaces.create'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_primary'))
        .width('100%')

      Text(I18n.get('workspaces.name'))
        .fontSize(14)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .width('100%')
        .margin({ top: 16, bottom: 8 })
      TextInput({ text: this.newWorkspaceName, placeholder: I18n.get('workspaces.name') })
        .height(48)
        .borderRadius(8)
        .backgroundColor($r('app.color.terminal_surface_container_high'))
        .fontColor($r('app.color.terminal_primary'))
        .placeholderColor($r('app.color.terminal_on_surface_variant'))
        .onChange((value: string) => { this.newWorkspaceName = value })

      Text(I18n.get('workspaces.path'))
        .fontSize(14)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .width('100%')
        .margin({ top: 16, bottom: 8 })
      TextInput({ text: this.newWorkspacePath, placeholder: I18n.get('workspaces.path') })
        .height(48)
        .borderRadius(8)
        .backgroundColor($r('app.color.terminal_surface_container_high'))
        .fontColor($r('app.color.terminal_primary'))
        .placeholderColor($r('app.color.terminal_on_surface_variant'))
        .onChange((value: string) => { this.newWorkspacePath = value })

      Button(I18n.get('workspaces.create'))
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 24 })
        .onClick(() => {
          this.submitCreateWorkspace()
        })
    }
    .width('100%')
    .padding(24)
  }

  @Builder
  WorkerInfoCard() {
    Column() {
      // Status indicator
      Row() {
        Circle()
          .width(12)
          .height(12)
          .fill(this.worker!.isOnline ?
            $r('app.color.terminal_tertiary') :
            $r('app.color.terminal_outline_variant'))

        Text(this.worker!.isOnline ? I18n.get('worker.detail.status_online') : I18n.get('worker.detail.status_offline'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.worker!.isOnline ?
            $r('app.color.terminal_tertiary') :
            $r('app.color.terminal_on_surface_variant'))
          .margin({ left: 8 })
      }

      // Worker details grid
      Grid() {
        GridItem() {
          this.StatItem(I18n.get('worker.detail.hostname'), this.worker!.hostname || '-')
        }
        GridItem() {
          this.StatItem(I18n.get('worker.detail.os'), this.worker!.os || '-')
        }
        GridItem() {
          this.StatItem(I18n.get('worker.detail.cpu'), `${this.worker!.cpuUsage ?? 0}%`)
        }
        GridItem() {
          this.StatItem(I18n.get('worker.detail.memory'), `${this.worker!.memoryUsage ?? 0}%`)
        }
      }
      .columnsTemplate('1fr 1fr')
      .rowsGap(12)
      .columnsGap(12)
      .width('100%')
      .margin({ top: 16 })

      // Last seen
      if (this.worker!.lastSeenAt.length > 0) {
        Text(`${I18n.get('worker.detail.last_seen')}：${this.formatTime(this.worker!.lastSeenAt)}`)
          .fontSize(12)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 12 })
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_surface_container'))
  }

  @Builder
  StatItem(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.terminal_on_surface_variant'))
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.terminal_primary'))
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SessionCard(session: WorkerSessionInfo) {
    Row() {
      Column() {
        Text(session.name || `Session ${session.id.substring(0, 8)}`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(session.status)
          .fontSize(12)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(I18n.get('session.card.resume'))
        .height(32)
        .borderRadius(8)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .fontSize(13)
        .onClick(() => {
          clickHaptic()
          AppStorage.setOrCreate('navSessionId', session.id)
          AppStorage.setOrCreate('navSessionName', session.name || 'Terminal')
          this.pageStack.pushPath({ name: 'TerminalSession' })
        })
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('app.color.terminal_surface_container_high'))
    .margin({ bottom: 8 })
  }

  @Builder
  WorkspaceCard(ws: WorkspaceItem) {
    Row() {
      SymbolGlyph($r('sys.symbol.folder_fill'))
        .fontSize(20)
        .fontColor([$r('app.color.terminal_secondary')])

      Column() {
        Text(ws.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(ws.rootPath)
          .fontSize(11)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })

      Button(I18n.get('workspaces.open_files'))
        .height(32)
        .borderRadius(8)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: $r('app.color.terminal_outline_variant') })
        .fontColor($r('app.color.terminal_primary'))
        .fontSize(13)
        .onClick(() => {
          clickHaptic()
          const param: Record<string, string> = { 'workspaceId': ws.id, 'workspaceName': ws.name }
          this.pageStack.pushPath({ name: RouteName.FILES_PAGE, param })
        })

      Button(I18n.get('session.card.resume'))
        .height(32)
        .borderRadius(8)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .fontSize(13)
        .margin({ left: 8 })
        .onClick(() => {
          clickHaptic()
          this.createSessionInWorkspace(ws.id)
        })
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor($r('app.color.terminal_surface_container_high'))
    .margin({ bottom: 8 })
  }

  private formatTime(dateStr: string): string {
    if (!dateStr) {
      return 'Never'
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
      return date.toLocaleDateString()
    }
  }

  private async loadWorkerDetail() {
    this.isLoading = true

    try {
      const worker = await ApiService.getWorker(this.workerId)
      this.worker = worker

      const allSessions = await ApiService.listSessions()
      this.sessions = allSessions
        .filter(s => s.workerId === this.workerId)
        .map(s => {
          const wsi = new WorkerSessionInfo()
          wsi.id = s.sessionId
          wsi.sessionId = s.sessionId
          wsi.workerId = s.workerId
          wsi.name = s.name
          wsi.status = s.status
          wsi.createdAt = s.createdAt
          wsi.updatedAt = s.updatedAt
          wsi.lastActivityAt = s.lastActivityAt
          wsi.lastActiveAt = s.lastActiveAt
          return wsi
        })
    } catch (e) {
      this.errorMessage = (e as Error).message || 'Failed to load worker details'
    } finally {
      this.isLoading = false
    }

    try {
      await this.loadWorkspaces()
    } catch (e) {
      showToast((e as Error).message || I18n.get('workspaces.empty'))
    }
  }

  private async createNewSession() {
    try {
      const request = new SessionCreateRequest()
      request.workerId = this.workerId
      request.columns = 120
      request.rows = 40

      const response = await ApiService.createSession(request)

      AppStorage.setOrCreate('navSessionId', response.sessionId)
      AppStorage.setOrCreate('navSessionName', response.name)
      this.pageStack.pushPath({ name: 'TerminalSession' })
    } catch (e) {
      showToast((e as Error).message || I18n.get('session.create_failed'))
    }
  }

  private async createSessionInWorkspace(workspaceId: string) {
    try {
      const request = new SessionCreateRequest()
      request.workerId = this.workerId
      request.workspaceId = workspaceId
      request.columns = 120
      request.rows = 40

      const response = await ApiService.createSession(request)

      AppStorage.setOrCreate('navSessionId', response.sessionId)
      AppStorage.setOrCreate('navSessionName', response.name)
      this.pageStack.pushPath({ name: 'TerminalSession' })
    } catch (e) {
      showToast((e as Error).message || I18n.get('session.create_failed'))
    }
  }

  private async loadWorkspaces() {
    const all = await ApiService.listWorkspaces() as Record<string, Object>[]
    const items: WorkspaceItem[] = []
    for (let i = 0; i < all.length; i++) {
      const item = all[i] as Record<string, Object>
      if (((item['workerId'] as string) ?? '') !== this.workerId) {
        continue
      }
      items.push({
        id: (item['id'] as string) ?? '',
        name: (item['name'] as string) ?? '',
        rootPath: (item['rootPath'] as string) ?? '',
        isDefault: (item['isDefault'] as boolean) ?? false
      })
    }
    this.workspaces = items
  }

  private async submitCreateWorkspace() {
    const name = this.newWorkspaceName.trim()
    if (name.length === 0) {
      showToast(I18n.get('workspaces.name'))
      return
    }
    try {
      lightHaptic()
      await ApiService.createWorkspace(this.workerId, name, this.newWorkspacePath.trim())
      this.showCreateWorkspace = false
      this.newWorkspaceName = ''
      this.newWorkspacePath = ''
      await this.loadWorkspaces()
    } catch (e) {
      showToast((e as Error).message || I18n.get('workspaces.create_failed'))
    }
  }
}
