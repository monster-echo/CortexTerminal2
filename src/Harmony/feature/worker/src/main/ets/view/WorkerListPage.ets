/**
 * @file WorkerListPage.ets
 * @brief Worker list display page
 *
 * Displays available workers as a list showing
 * name, status, OS, and session count. Allows navigation
 * to worker detail and session creation.
 */
import { ApiService, I18n, WorkerInfo } from '@rwecho/core'

@Component
export struct WorkerListPage {
  @State workers: WorkerInfo[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State isRefreshing: boolean = false
  @Consume('pageStack') pageStack: NavPathStack

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
          Text(I18n.get('worker.list.loading'))
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

          Button(I18n.get('common.retry'))
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
          Text(I18n.get('worker.list.empty'))
            .fontSize(16)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 60 })

          Text(I18n.get('session.home.empty_active_no_worker'))
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })

          Button(I18n.get('session.home.create_button'))
            .height(44)
            .borderRadius(12)
            .backgroundColor($r('app.color.terminal_secondary_container'))
            .fontColor($r('app.color.terminal_on_secondary_container'))
            .margin({ top: 18 })
            .onClick(() => {
              this.pageStack.pushPath({ name: 'auth/Login' })
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
      Button(worker.isOnline ? I18n.get('session.card.new_terminal') : I18n.get('session.card.view_detail'))
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

    try {
      this.workers = await ApiService.listWorkers()
    } catch (e) {
      this.errorMessage = (e as Error).message || 'Network error'
    } finally {
      this.isLoading = false
      this.isRefreshing = false
    }
  }
}
