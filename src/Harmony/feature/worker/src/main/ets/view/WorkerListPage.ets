/**
 * @file WorkerListPage.ets
 * @brief Worker list display page
 *
 * Displays available workers as a list showing
 * name, status, OS, and session count. Allows navigation
 * to worker detail and session creation.
 */
import { http } from '@kit.NetworkKit'
import { WorkerInfo } from '../model/WorkerModels'

@Component
export struct WorkerListPage {
  @State workers: WorkerInfo[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State isRefreshing: boolean = false
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('gatewayUrl') gatewayUrl: string = ''
  @StorageLink('authToken') authToken: string = ''

  aboutToAppear() {
    this.loadWorkers()
  }

  build() {
    Column() {
      // Loading state
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color($r('app.color.terminal_secondary'))
            .margin({ top: 60 })
          Text('正在加载 Workers...')
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 12 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }

      // Error state
      if (this.errorMessage.length > 0) {
        Column() {
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor($r('app.color.terminal_error'))
            .margin({ top: 40 })
            .padding({ left: 20, right: 20 })

          Button('重试')
            .margin({ top: 12 })
            .onClick(() => {
              this.loadWorkers()
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }

      // Worker list
      if (!this.isLoading && this.workers.length > 0) {
        Refresh({ refreshing: $$this.isRefreshing }) {
          List() {
          ForEach(this.workers, (worker: WorkerInfo) => {
            ListItem() {
              this.WorkerRow(worker)
            }
          }, (worker: WorkerInfo) => worker.id)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16 })
          .divider({ strokeWidth: 1, color: $r('app.color.terminal_outline_variant'), startMargin: 0, endMargin: 0 })
        }
        .onRefreshing(() => {
          this.loadWorkers()
        })
      }

      // Empty state
      if (!this.isLoading && this.workers.length === 0 && this.errorMessage.length === 0) {
        Column() {
          Text('还没有绑定 Worker')
            .fontSize(16)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 60 })

          Text('在电脑端启动 Worker 后，输入激活码完成绑定。')
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })

          Button('激活 Worker')
            .height(44)
            .borderRadius(12)
            .backgroundColor($r('app.color.terminal_secondary_container'))
            .fontColor($r('app.color.terminal_on_secondary_container'))
            .margin({ top: 18 })
            .onClick(() => {
              this.pageStack.pushPath({ name: 'Auth' })
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
  }

  @Builder
  WorkerRow(worker: WorkerInfo) {
    Row() {
      // Status indicator
      Circle()
        .width(10)
        .height(10)
        .fill(worker.isOnline ?
          $r('app.color.terminal_tertiary') :
          $r('app.color.terminal_outline_variant'))
        .margin({ right: 12 })

      // Worker info
      Column() {
        Text(worker.name || worker.hostname || 'Unknown Worker')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(worker.os || worker.operatingSystem || 'Unknown OS')
          .fontSize(13)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // Action button
      Button(worker.isOnline ? '新建终端' : '查看')
        .height(32)
        .borderRadius(8)
        .backgroundColor(worker.isOnline ?
          $r('app.color.terminal_secondary_container') :
          $r('app.color.terminal_surface_container_high'))
        .fontColor(worker.isOnline ?
          $r('app.color.terminal_on_secondary_container') :
          $r('app.color.terminal_primary'))
        .fontSize(13)
        .margin({ left: 8 })
        .onClick(() => {
          AppStorage.setOrCreate('navWorkerId', worker.id)
          AppStorage.setOrCreate('navWorkerName', worker.name || worker.hostname || 'Worker')
          this.pageStack.pushPath({ name: 'WorkerDetail' })
        })
    }
    .width('100%')
    .height(64)
    .alignItems(VerticalAlign.Center)
  }

  private async loadWorkers() {
    this.isLoading = true
    this.errorMessage = ''

    const baseUrl = this.gatewayUrl
    const url = `${baseUrl}/api/me/workers`

    try {
      const httpRequest = http.createHttp()
      const headers: Record<string, string> = { 'Accept': 'application/json' }
      if (this.authToken.length > 0) {
        headers['Authorization'] = `Bearer ${this.authToken}`
      }

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.OBJECT,
        connectTimeout: 15000,
        readTimeout: 15000
      })

      if (response.responseCode === 200) {
        const workerList = response.result as Object[]
        this.workers = workerList.map((w: Object) => {
          const data = w as Record<string, Object>
          const worker = new WorkerInfo()
          const workerId = (data['workerId'] as string) ?? ''
          const isOnline = (data['isOnline'] as boolean) ?? false
          const sessionCount = (data['sessionCount'] as number) ?? 0
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
          worker.address = (data['address'] as string) ?? ''
          worker.activeSessions = sessionCount
          worker.sessionCount = sessionCount
          worker.maxSessions = Math.max(sessionCount, 1)
          worker.lastSeenAt = (data['lastSeenAtUtc'] as string) ?? ''
          return worker
        })
      } else {
        this.errorMessage = `Failed to load workers (${response.responseCode})`
      }

      httpRequest.destroy()
    } catch (e) {
      this.errorMessage = (e as Error).message || 'Network error'
    } finally {
      this.isLoading = false
      this.isRefreshing = false
    }
  }
}
