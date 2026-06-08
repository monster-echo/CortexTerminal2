import { WorkerInfo, I18n } from '@rwecho/core'

@Component
export struct WorkerCard {
  @Prop worker: WorkerInfo = new WorkerInfo()
  onCreateSession?: (worker: WorkerInfo) => void
  onViewDetail?: (worker: WorkerInfo) => void

  build() {
    Row() {
      // Status dot
      Circle()
        .width(10)
        .height(10)
        .fill(this.worker.isOnline ? $r('app.color.terminal_tertiary') : $r('app.color.terminal_outline_variant'))
        .margin({ right: 12 })

      // Worker info
      Column() {
        Text(this.worker.name || this.worker.hostname || 'Unknown')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.worker.os || this.worker.operatingSystem || '')
          .fontSize(12)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // Action button
      if (this.worker.isOnline) {
        Button(I18n.get('session.card.new_terminal'))
          .height(32)
          .borderRadius(8)
          .backgroundColor($r('app.color.terminal_secondary_container'))
          .fontColor($r('app.color.terminal_on_secondary_container'))
          .fontSize(13)
          .onClick(() => {
            if (this.onCreateSession) this.onCreateSession(this.worker)
          })
      } else {
        Text(I18n.get('session.card.view_detail'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_secondary'))
          .onClick(() => {
            if (this.onViewDetail) this.onViewDetail(this.worker)
          })
      }
    }
    .width('100%')
    .height(60)
    .padding({ left: 14, right: 14 })
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_surface_container'))
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 8 })
  }
}
