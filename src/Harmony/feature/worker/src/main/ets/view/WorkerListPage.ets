/**
 * @file WorkerListPage.ets
 * @brief Worker card grid display page
 *
 * Displays available workers as a grid of cards showing
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
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('gatewayUrl') gatewayUrl: string = ''
  @StorageLink('authToken') authToken: string = ''

  aboutToAppear() {
    this.loadWorkers()
  }

  build() {
    Column() {
      // Header
      Row() {
        Text('Workers')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_primary'))
          .layoutWeight(1)

        Text(`${this.workers.filter(w => w.status === 'online').length} online`)
          .fontSize(14)
          .fontColor($r('app.color.terminal_tertiary'))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 16 })

      // Loading state
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color($r('app.color.terminal_secondary'))
            .margin({ top: 60 })
          Text('Loading workers...')
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

          Button('Retry')
            .margin({ top: 12 })
            .onClick(() => {
              this.loadWorkers()
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }

      // Worker grid
      if (!this.isLoading && this.workers.length > 0) {
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.workers, (worker: WorkerInfo) => {
              this.WorkerCard(worker)
            }, (worker: WorkerInfo) => worker.id)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .layoutWeight(1)
      }

      // Empty state
      if (!this.isLoading && this.workers.length === 0 && this.errorMessage.length === 0) {
        Column() {
          Text('No workers found')
            .fontSize(16)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 60 })

          Text('Activate a worker to get started')
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 8 })
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
  WorkerCard(worker: WorkerInfo) {
    Column() {
      // Worker header with status indicator
      Row() {
        Text(worker.name || worker.hostname || 'Unknown Worker')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // Status badge
        Row() {
          Circle()
            .width(8)
            .height(8)
            .fill(worker.status === 'online' ?
              $r('app.color.terminal_tertiary') :
              $r('app.color.terminal_outline_variant'))
          Text(worker.status)
            .fontSize(12)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ left: 4 })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(8)
        .backgroundColor($r('app.color.terminal_surface_container'))
      }
      .width('100%')

      // Worker details
      Row() {
        Text(worker.os || 'Unknown OS')
          .fontSize(13)
          .fontColor($r('app.color.terminal_on_surface_variant'))

        Text(`${worker.activeSessions}/${worker.maxSessions} sessions`)
          .fontSize(13)
          .fontColor($r('app.color.terminal_on_surface_variant'))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ top: 8 })

      // Action button
      Button(worker.status === 'online' ? 'Connect' : 'View')
        .width('100%')
        .height(36)
        .borderRadius(8)
        .backgroundColor(worker.status === 'online' ?
          $r('app.color.terminal_secondary_container') :
          $r('app.color.terminal_surface_container_high'))
        .fontColor(worker.status === 'online' ?
          $r('app.color.terminal_on_secondary_container') :
          $r('app.color.terminal_primary'))
        .fontSize(14)
        .margin({ top: 12 })
        .onClick(() => {
          AppStorage.setOrCreate('navWorkerId', worker.id)
          AppStorage.setOrCreate('navWorkerName', worker.name || worker.hostname || 'Worker')
          this.pageStack.pushPath({ name: 'WorkerDetail' })
        })
    }
    .width('calc(50% - 12vp)')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_surface_container'))
    .margin({ left: 4, right: 4, top: 4, bottom: 4 })
  }

  private async loadWorkers() {
    this.isLoading = true
    this.errorMessage = ''

    const baseUrl = this.gatewayUrl || 'https://gateway.ct.rwecho.top'
    const url = `${baseUrl}/api/workers`

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
        const result = response.result as Record<string, Object[]>
        const workerList = result['workers'] ?? []
        this.workers = workerList.map((w: Object) => {
          const data = w as Record<string, Object>
          const worker = new WorkerInfo()
          worker.id = (data['id'] as string) ?? ''
          worker.name = (data['name'] as string) ?? ''
          worker.hostname = (data['hostname'] as string) ?? ''
          worker.status = (data['status'] as string) ?? 'offline'
          worker.os = (data['os'] as string) ?? ''
          worker.activeSessions = (data['activeSessions'] as number) ?? 0
          worker.maxSessions = (data['maxSessions'] as number) ?? 1
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
    }
  }
}
