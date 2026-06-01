/**
 * @file WorkerDetailPage.ets
 * @brief Worker dashboard with session management
 *
 * Displays detailed worker information including system stats,
 * active sessions, and provides actions like creating new sessions
 * or connecting to existing ones.
 */
import { http } from '@kit.NetworkKit'
import { WorkerInfo, WorkerSessionInfo } from '../model/WorkerModels'

@Component
export struct WorkerDetailPage {
  @StorageLink('navWorkerId') workerId: string = ''
  @StorageLink('navWorkerName') workerName: string = 'Worker'
  @State worker: WorkerInfo | null = null
  @State sessions: WorkerSessionInfo[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('gatewayUrl') gatewayUrl: string = ''
  @StorageLink('authToken') authToken: string = ''

  aboutToAppear() {
    this.loadWorkerDetail()
  }

  build() {
    Column() {
      // Header
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([$r('app.color.terminal_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.pageStack.pop()
        })

        Text(this.workerName)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_primary'))
          .layoutWeight(1)
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 8, bottom: 8 })

      Scroll() {
        Column() {
          if (this.isLoading) {
            LoadingProgress()
              .width(40)
              .height(40)
              .color($r('app.color.terminal_secondary'))
              .margin({ top: 40 })
          }

          // Worker info card
          if (this.worker) {
            this.WorkerInfoCard()
          }

          // Active sessions section
          Column() {
            Text('会话')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_primary'))
              .width('100%')
              .margin({ bottom: 12 })

            if (this.sessions.length === 0) {
              Text('暂无活跃会话')
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
            Button('在此 Worker 新建终端')
              .width('calc(100% - 40vp)')
              .height(48)
              .borderRadius(12)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 24 })
              .onClick(() => {
                this.createNewSession()
              })
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
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

        Text(this.worker!.isOnline ? '在线' : '离线')
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
          this.StatItem('主机名', this.worker!.hostname || '-')
        }
        GridItem() {
          this.StatItem('系统', this.worker!.os || '-')
        }
        GridItem() {
          this.StatItem('CPU', `${this.worker!.cpuUsage ?? 0}%`)
        }
        GridItem() {
          this.StatItem('内存', `${this.worker!.memoryUsage ?? 0}%`)
        }
      }
      .columnsTemplate('1fr 1fr')
      .rowsGap(12)
      .columnsGap(12)
      .width('100%')
      .margin({ top: 16 })

      // Last seen
      if (this.worker!.lastSeenAt.length > 0) {
        Text(`最后在线：${this.formatTime(this.worker!.lastSeenAt)}`)
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

      Button('恢复')
        .height(32)
        .borderRadius(8)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .fontSize(13)
        .onClick(() => {
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

  private mapSessionStatus(status: string): string {
    switch (status) {
      case 'Attached':
        return 'running'
      case 'DetachedGracePeriod':
        return 'idle'
      case 'Exited':
      case 'Expired':
        return 'failed'
      default:
        return status.length > 0 ? status.toLowerCase() : 'idle'
    }
  }

  private async loadWorkerDetail() {
    this.isLoading = true

    const baseUrl = this.gatewayUrl

    try {
      const httpRequest = http.createHttp()
      const headers: Record<string, string> = { 'Accept': 'application/json' }
      if (this.authToken.length > 0) {
        headers['Authorization'] = `Bearer ${this.authToken}`
      }

      // Load worker info
      const response = await httpRequest.request(`${baseUrl}/api/me/workers/${encodeURIComponent(this.workerId)}`, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 15000,
        readTimeout: 15000
      })

      if (response.responseCode === 200) {
        const data = response.result as Record<string, Object>
        const worker = new WorkerInfo()
        const workerId = (data['workerId'] as string) ?? this.workerId
        const isOnline = (data['isOnline'] as boolean) ?? false
        worker.id = workerId
        worker.workerId = workerId
        worker.name = (data['name'] as string) ?? ''
        worker.hostname = (data['hostname'] as string) ?? ''
        worker.isOnline = isOnline
        worker.status = isOnline ? 'online' : 'offline'
        worker.operatingSystem = (data['operatingSystem'] as string) ?? ''
        worker.os = worker.operatingSystem
        worker.architecture = (data['architecture'] as string) ?? ''
        worker.arch = worker.architecture
        worker.version = (data['version'] as string) ?? ''
        worker.lastSeenAt = (data['lastSeenAtUtc'] as string) ?? ''
        worker.sessionCount = (data['sessionCount'] as number) ?? 0
        worker.activeSessions = worker.sessionCount
        this.worker = worker

        const sessionList = (data['sessions'] as Object[]) ?? []
        this.sessions = sessionList.map((s: Object) => {
          const d = s as Record<string, Object>
          const session = new WorkerSessionInfo()
          const sessionId = (d['sessionId'] as string) ?? ''
          session.id = sessionId
          session.sessionId = sessionId
          session.workerId = (d['workerId'] as string) ?? this.workerId
          session.name = sessionId.length > 8 ? `session ${sessionId.substring(0, 8)}` : sessionId
          session.status = this.mapSessionStatus((d['status'] as string) ?? '')
          session.createdAt = (d['createdAt'] as string) ?? ''
          session.lastActivityAt = (d['lastActivityAt'] as string) ?? ''
          session.lastActiveAt = session.lastActivityAt
          return session
        })
      }

      httpRequest.destroy()
    } catch (e) {
      this.errorMessage = (e as Error).message || 'Failed to load worker details'
    } finally {
      this.isLoading = false
    }
  }

  private async createNewSession() {
    const baseUrl = this.gatewayUrl

    try {
      const httpRequest = http.createHttp()
      const headers: Record<string, string> = {
        'Accept': 'application/json',
        'Content-Type': 'application/json'
      }
      if (this.authToken.length > 0) {
        headers['Authorization'] = `Bearer ${this.authToken}`
      }

      const response = await httpRequest.request(`${baseUrl}/api/sessions`, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(new SessionCreateBody(this.workerId, `Terminal on ${this.workerName}`)),
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 15000,
        readTimeout: 15000
      })

      if (response.responseCode === 200 || response.responseCode === 201) {
        const data = response.result as Record<string, string>
        const sessionId = data['sessionId'] ?? ''
        const sessionName = sessionId.length > 8 ? `session ${sessionId.substring(0, 8)}` : 'Terminal'

        AppStorage.setOrCreate('navSessionId', sessionId)
        AppStorage.setOrCreate('navSessionName', sessionName)
        this.pageStack.pushPath({ name: 'TerminalSession' })
      }

      httpRequest.destroy()
    } catch (e) {
      console.error('Failed to create session: ' + (e as Error).message)
    }
  }
}

/**
 * Request body for creating a session on a worker.
 */
class SessionCreateBody {
  runtime: string = 'shell'
  workerId: string = ''
  columns: number = 120
  rows: number = 40
  clientRequestId: string = ''

  constructor(workerId: string, _name: string) {
    this.workerId = workerId
    this.clientRequestId = `harmony-worker-${Date.now()}-${Math.floor(Math.random() * 100000)}`
  }
}
