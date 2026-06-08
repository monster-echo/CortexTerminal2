import { WorkerInfo, ApiService, I18n } from '@rwecho/core'
import { SessionService } from '../service/SessionService'

@Component
export struct CreateSessionSheet {
  @State modalWorkers: WorkerInfo[] = []
  @State isModalLoading: boolean = false
  @State errorMessage: string = ''
  @State isCreating: boolean = false
  onSessionCreated?: (sessionId: string, sessionName: string) => void

  aboutToAppear() {
    this.loadWorkers()
  }

  build() {
    Column() {
      Text(I18n.get('session.create.title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_primary'))
        .width('100%')
        .margin({ bottom: 16 })

      if (this.isModalLoading) {
        Column() {
          LoadingProgress().width(32).height(32).color($r('app.color.terminal_secondary'))
          Text(I18n.get('session.create.loading'))
            .fontSize(13)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 8 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 24 })
      } else if (this.errorMessage.length > 0) {
        Column() {
          Text(I18n.get('session.create.error'))
            .fontSize(15)
            .fontColor($r('app.color.terminal_error'))
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 24 })
      } else if (this.modalWorkers.filter(w => w.isOnline).length === 0) {
        Column() {
          Text(I18n.get('session.create.empty'))
            .fontSize(15)
            .fontColor($r('app.color.terminal_on_surface_variant'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 24 })
      } else {
        List() {
          ForEach(this.modalWorkers.filter(w => w.isOnline), (worker: WorkerInfo) => {
            ListItem() {
              Row() {
                Circle().width(10).height(10).fill($r('app.color.terminal_tertiary')).margin({ right: 12 })

                Column() {
                  Text(worker.name || worker.hostname || 'Unknown')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.terminal_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(worker.os || worker.operatingSystem || '')
                    .fontSize(12)
                    .fontColor($r('app.color.terminal_on_surface_variant'))
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button(I18n.get('common.confirm'))
                  .height(32)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.terminal_secondary_container'))
                  .fontColor($r('app.color.terminal_on_secondary_container'))
                  .fontSize(13)
                  .enabled(!this.isCreating)
                  .opacity(this.isCreating ? 0.5 : 1)
                  .onClick(() => {
                    this.createSession(worker.id)
                  })
              }
              .width('100%')
              .height(60)
              .alignItems(VerticalAlign.Center)
            }
          }, (worker: WorkerInfo) => worker.id)
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: $r('app.color.terminal_outline_variant'), startMargin: 0, endMargin: 0 })
      }
    }
    .padding({ left: 20, right: 20, top: 16, bottom: 20 })
    .width('100%')
  }

  private async loadWorkers() {
    this.isModalLoading = true
    try {
      this.modalWorkers = await ApiService.listWorkers()
    } catch (e) {
      this.errorMessage = (e as Error).message
    } finally {
      this.isModalLoading = false
    }
  }

  private async createSession(workerId: string) {
    if (this.isCreating) return
    this.isCreating = true
    try {
      const session = await SessionService.createSessionOnWorker(workerId)
      if (this.onSessionCreated) {
        this.onSessionCreated(session.id, session.name)
      }
    } catch (e) {
      this.errorMessage = (e as Error).message
    } finally {
      this.isCreating = false
    }
  }
}
