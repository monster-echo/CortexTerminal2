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
          Text('<')
            .fontSize(20)
            .fontColor($r('app.color.terminal_primary'))
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)

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
            Text('Sessions')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_primary'))
              .width('100%')
              .margin({ bottom: 12 })

            if (this.sessions.length === 0) {
              Text('No active sessions')
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
          if (this.worker && this.worker.status === 'online') {
            Button('New Session on this Worker')
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
          .fill(this.worker!.status === 'online' ?
            $r('app.color.terminal_tertiary') :
            $r('app.color.terminal_outline_variant'))

        Text(this.worker!.status === 'online' ? 'Online' : 'Offline')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.worker!.status === 'online' ?
            $r('app.color.terminal_tertiary') :
            $r('app.color.terminal_on_surface_variant'))
          .margin({ left: 8 })
      }

      // Worker details grid
      Grid() {
        GridItem() {
          this.StatItem('Hostname', this.worker!.hostname || '-')
        }
        GridItem() {
          this.StatItem('OS', this.worker!.os || '-')
        }
        GridItem() {
          this.StatItem('CPU', `${this.worker!.cpuUsage ?? 0}%`)
        }
        GridItem() {
          this.StatItem('Memory', `${this.worker!.memoryUsage ?? 0}%`)
        }
      }
      .columnsTemplate('1fr 1fr')
      .rowsGap(12)
      .columnsGap(12)
      .width('100%')
      .margin({ top: 16 })

      // Last seen
      if (this.worker!.lastSeenAt.length > 0) {
        Text(`Last seen: ${this.formatTime(this.worker!.lastSeenAt)}`)
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

      Button('Resume')
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

  private async loadWorkerDetail() {
    this.isLoading = true

    const baseUrl = this.gatewayUrl || 'https://gateway.ct.rwecho.top'

    try {
      const httpRequest = http.createHttp()
      const headers: Record<string, string> = { 'Accept': 'application/json' }
      if (this.authToken.length > 0) {
        headers['Authorization'] = `Bearer ${this.authToken}`
      }

      // Load worker info
      const response = await httpRequest.request(`${baseUrl}/api/workers/${this.workerId}`, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 15000,
        readTimeout: 15000
      })

      if (response.responseCode === 200) {
        const data = response.result as Record<string, Object>
        const worker = new WorkerInfo()
        worker.id = (data['id'] as string) ?? ''
        worker.name = (data['name'] as string) ?? ''
        worker.hostname = (data['hostname'] as string) ?? ''
        worker.status = (data['status'] as string) ?? 'offline'
        worker.os = (data['os'] as string) ?? ''
        worker.cpuUsage = (data['cpuUsage'] as number) ?? 0
        worker.memoryUsage = (data['memoryUsage'] as number) ?? 0
        worker.lastSeenAt = (data['lastSeenAt'] as string) ?? ''
        this.worker = worker
      }

      httpRequest.destroy()

      // Load sessions
      const sessionsRequest = http.createHttp()
      const sessionsResponse = await sessionsRequest.request(
        `${baseUrl}/api/workers/${this.workerId}/sessions`, {
          method: http.RequestMethod.GET,
          header: headers,
          expectDataType: http.HttpDataType.OBJECT,
          connectTimeout: 15000,
          readTimeout: 15000
        }
      )

      if (sessionsResponse.responseCode === 200) {
        const result = sessionsResponse.result as Record<string, Object[]>
        const sessionList = result['sessions'] ?? []
        this.sessions = sessionList.map((s: Object) => {
          const d = s as Record<string, Object>
          const session = new WorkerSessionInfo()
          session.id = (d['id'] as string) ?? ''
          session.name = (d['name'] as string) ?? ''
          session.status = (d['status'] as string) ?? ''
          session.createdAt = (d['createdAt'] as string) ?? ''
          return session
        })
      }

      sessionsRequest.destroy()
    } catch (e) {
      this.errorMessage = (e as Error).message || 'Failed to load worker details'
    } finally {
      this.isLoading = false
    }
  }

  private async createNewSession() {
    const baseUrl = this.gatewayUrl || 'https://gateway.ct.rwecho.top'

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
        const sessionId = data['id'] ?? ''
        const sessionName = data['name'] ?? 'Terminal'

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
  workerId: string = ''
  name: string = ''

  constructor(workerId: string, name: string) {
    this.workerId = workerId
    this.name = name
  }
}
