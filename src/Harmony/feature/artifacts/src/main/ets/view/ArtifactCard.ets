/**
 * @file ArtifactCard.ets
 * @brief Single WeChat-style file bubble.
 *
 * Image artifacts render as a large thumbnail bubble (ImageBubble) — the photo
 * is the focal point, like WeChat's file helper. Non-image artifacts use the
 * icon + metadata row (FileBubble). Right side = Console origin (user upload);
 * left side = Worker origin (synced from worker).
 */
import { I18n } from '@rwecho/core'
import { ArtifactModel, ArtifactOrigin, FileCategory } from '../model/ArtifactModels'
import { ArtifactsService } from '../service/ArtifactsService'
import { FileTypeIcon } from './FileTypeIcon'

@Component
export struct ArtifactCard {
  @Prop artifact: ArtifactModel = new ArtifactModel('', '', '', 0, '', '', '', 0, 0)
  @Prop downloading: boolean = false
  onDownload?: (artifact: ArtifactModel) => void
  onDelete?: (artifact: ArtifactModel) => void
  onPreview?: (artifact: ArtifactModel) => void
  @State imageUrl: string = ''

  aboutToAppear() {
    if (this.artifact.fileCategory === FileCategory.IMAGE) {
      this.loadImageUrl()
    }
  }

  private async loadImageUrl() {
    try {
      this.imageUrl = await ArtifactsService.getDownloadUrl(this.artifact.sessionId, this.artifact.id)
    } catch (_e) {}
  }

  build() {
    if (this.imageUrl.length > 0) {
      this.ImageBubble()
    } else {
      this.FileBubble()
    }
  }

  @Builder
  ImageBubble() {
    Column() {
      Image(this.imageUrl)
        .width('100%')
        .height(180)
        .borderRadius(10)
        .objectFit(ImageFit.Cover)
        .onClick(() => {
          if (this.onPreview) {
            this.onPreview(this.artifact)
          }
        })

      Row() {
        Text(this.artifact.filename)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_on_surface'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.formatSize())
          .fontSize(12)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ top: 8 })

      Row() {
        Text(this.formatUploadedAt())
          .fontSize(12)
          .fontColor($r('app.color.terminal_on_surface_variant'))
        Blank()
        this.ExpiryChip()
        if (this.isWorkerOrigin()) {
          this.DownloadButton()
        }
        this.DeleteButton()
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .padding(12)
    .borderRadius(12)
    .backgroundColor(this.bubbleColor())
  }

  @Builder
  FileBubble() {
    Row() {
      if (this.isWorkerOrigin()) {
        Column() {
          this.IconBlock()
        }
        .width(48)
        .height(48)
        .margin({ right: 8 })
      }

      Column() {
        Text(this.artifact.filename)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_on_surface'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row() {
          Text(this.formatSize())
            .fontSize(12)
            .fontColor($r('app.color.terminal_on_surface_variant'))
          Text('·')
            .fontSize(12)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ left: 4, right: 4 })
          Text(this.formatUploadedAt())
            .fontSize(12)
            .fontColor($r('app.color.terminal_on_surface_variant'))
        }
        .margin({ top: 2 })

        Row() {
          this.ExpiryChip()
          Blank()
          if (this.isWorkerOrigin()) {
            this.DownloadButton()
          }
          this.DeleteButton()
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!this.isWorkerOrigin()) {
        Column() {
          this.IconBlock()
        }
        .width(48)
        .height(48)
        .margin({ left: 8 })
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(this.bubbleColor())
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  IconBlock() {
    FileTypeIcon({ category: this.artifact.fileCategory, filename: this.artifact.filename })
  }

  @Builder
  ExpiryChip() {
    Text(this.formatExpiry())
      .fontSize(11)
      .fontColor(this.expiryColor())
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(8)
      .backgroundColor($r('app.color.terminal_surface_container'))
  }

  @Builder
  DownloadButton() {
    Button({ type: ButtonType.Normal }) {
      if (this.downloading) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color($r('app.color.terminal_on_surface_variant'))
      } else {
        Text(I18n.get('artifacts.download'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_primary'))
      }
    }
    .height(32)
    .borderRadius(8)
    .backgroundColor($r('app.color.terminal_surface_container_high'))
    .enabled(!this.downloading)
    .onClick(() => {
      if (this.onDownload) {
        this.onDownload(this.artifact)
      }
    })
  }

  @Builder
  DeleteButton() {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(16)
        .fontColor([$r('app.color.terminal_on_surface_variant')])
    }
    .height(32)
    .width(32)
    .borderRadius(8)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (this.onDelete) {
        this.onDelete(this.artifact)
      }
    })
  }

  private isWorkerOrigin(): boolean {
    return this.artifact.origin === ArtifactOrigin.WORKER
  }

  private bubbleColor(): ResourceColor {
    if (this.isWorkerOrigin()) {
      return $r('app.color.terminal_surface_container')
    }
    return $r('app.color.terminal_surface_container_high')
  }

  private expiryColor(): ResourceColor {
    const days = this.expiryDays()
    if (days <= 1) {
      return $r('app.color.terminal_error')
    }
    return $r('app.color.terminal_on_surface_variant')
  }

  private formatExpiry(): string {
    const days = this.expiryDays()
    if (days <= 1) {
      return I18n.get('artifacts.expires_today')
    }
    return I18n.getWithArgs('artifacts.expires_in_days', { 'n': `${days}` })
  }

  private formatSize(): string {
    const bytes = this.artifact.sizeBytes
    if (bytes < 1024) {
      return I18n.getWithArgs('artifacts.size_bytes', { 'n': `${bytes}` })
    }
    if (bytes < 1024 * 1024) {
      return I18n.getWithArgs('artifacts.size_kb', { 'n': `${Math.round(bytes / 1024)}` })
    }
    return I18n.getWithArgs('artifacts.size_mb', { 'n': `${(bytes / (1024 * 1024)).toFixed(1)}` })
  }

  private formatUploadedAt(): string {
    if (this.artifact.uploadedAt <= 0) {
      return ''
    }
    const date = new Date(this.artifact.uploadedAt)
    const hours = date.getHours().toString().padStart(2, '0')
    const minutes = date.getMinutes().toString().padStart(2, '0')
    return `${hours}:${minutes}`
  }

  private expiryDays(): number {
    if (this.artifact.expiresAt <= 0) {
      return 7
    }
    const diffMs = this.artifact.expiresAt - Date.now()
    if (diffMs <= 0) {
      return 0
    }
    return Math.ceil(diffMs / (24 * 3600 * 1000))
  }
}
