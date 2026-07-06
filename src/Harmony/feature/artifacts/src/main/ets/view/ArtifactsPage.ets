/**
 * @file ArtifactsPage.ets
 * @brief WeChat File Helper-style chat feed for session artifacts.
 *
 * Right bubbles = Console uploads. Left bubbles = Worker syncs. Day separators
 * appear when the uploadedAt date changes. The page subscribes to the
 * ArtifactChanged SignalR event for real-time updates and refetches nothing.
 */
import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { I18n, showToast, lightHaptic, clickHaptic } from '@rwecho/core'
import { ArtifactModel, ArtifactOrigin } from '../model/ArtifactModels'
import { ArtifactsService } from '../service/ArtifactsService'
import { ArtifactsTransport } from '../service/ArtifactsTransport'
import { FilePicker, FilePickerResult } from '../service/FilePicker'
import { FileDownloader } from '../service/FileDownloader'
import { ArtifactCard } from './ArtifactCard'

interface ArtifactGroup {
  key: string;
  label: string;
  items: ArtifactModel[];
}

interface ArtifactsNavParam {
  sessionId: string;
}

@Component
export struct ArtifactsPage {
  @State sessionId: string = ''
  @State artifacts: ArtifactModel[] = []
  @State loading: boolean = true
  @State loadError: string = ''
  @State uploading: boolean = false
  @State downloadingIds: string[] = []
  @State previewUrl: string = ''
  @State showPreview: boolean = false
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('gatewayUrl') gatewayUrl: string = ''
  @StorageLink('authToken') authToken: string = ''
  private transport: ArtifactsTransport = new ArtifactsTransport()

  aboutToAppear() {
    const params = this.pageStack.getParamByName('artifacts/Page') as ArtifactsNavParam[]
    if (params && params.length > 0) {
      this.sessionId = params[params.length - 1].sessionId
    }
    if (this.sessionId.length === 0) {
      throw new Error('ArtifactsPage requires a sessionId in nav params')
    }
    this.transport.setOnChange(this.handleArtifactChanged.bind(this))
    this.loadArtifacts()
    this.connectTransport()
    // 背景跟随主题,按 colorMode 设状态栏文字,覆盖终端页留下的强制白字
    this.applyStatusBar(AppStorage.get<string>('colorMode') !== 'light')
  }

  aboutToDisappear() {
    this.transport.disconnect()
    // 唯一入口/返回目标是恒深色的终端页,恢复白字状态栏
    this.applyStatusBar(true)
  }

  private applyStatusBar(forceWhite: boolean): void {
    const context = getContext(this) as common.UIAbilityContext
    window.getLastWindow(context).then((win: window.Window) => {
      win.setWindowSystemBarProperties({
        statusBarContentColor: forceWhite ? '#ffffff' : '#000000'
      }).then(() => {
        console.info(`[ArtifactsPage] statusBar -> ${forceWhite ? 'white' : 'black'} (colorMode=${AppStorage.get<string>('colorMode')})`)
      }).catch((e: Error) => {
        console.error(`[ArtifactsPage] setWindowSystemBarProperties failed: ${e.message}`)
      })
    }).catch((e: Error) => {
      console.error(`[ArtifactsPage] getLastWindow failed: ${e.message}`)
    })
  }

  build() {
    Column() {
      this.TopBar()
      Column() {
        if (this.loadError.length > 0) {
          this.ErrorBanner()
        }
        if (this.loading) {
          this.LoadingSkeleton()
        } else if (this.artifacts.length === 0 && this.loadError.length === 0) {
          this.EmptyState()
        } else {
          Scroll() {
            Column() {
              ForEach(this.buildGroups(), (group: ArtifactGroup) => {
                Text(group.label)
                  .fontSize(12)
                  .fontColor($r('app.color.terminal_on_surface_variant'))
                  .margin({ top: 12, bottom: 8 })
                ForEach(group.items, (item: ArtifactModel) => {
                  ArtifactCard({
                    artifact: item,
                    downloading: this.isDownloading(item.id),
                    onDownload: (artifact: ArtifactModel) => { this.handleDownload(artifact) },
                    onDelete: (artifact: ArtifactModel) => { this.handleDelete(artifact) },
                    onPreview: (artifact: ArtifactModel) => { this.openPreview(artifact) },
                  })
                }, (item: ArtifactModel) => item.id)
              }, (group: ArtifactGroup) => group.key)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 100 })
            .alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1)
          .align(Alignment.TopStart)
          .scrollBar(BarState.Off)
        }
      }
      .layoutWeight(1)
      .width('100%')

      this.UploadBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface'))
    .bindSheet(this.showPreview, this.PreviewSheet(), {
      backgroundColor: $r('app.color.terminal_surface'),
      onDisappear: () => { this.showPreview = false }
    })
  }

  @Builder
  PreviewSheet() {
    Image(this.previewUrl)
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Contain)
  }

  private async openPreview(artifact: ArtifactModel) {
    try {
      const url = await ArtifactsService.getDownloadUrl(this.sessionId, artifact.id)
      if (url.length > 0) {
        this.previewUrl = url
        this.showPreview = true
      }
    } catch (e) {
      showToast((e as Error).message)
    }
  }

  @Builder
  TopBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([$r('app.color.terminal_on_surface')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        clickHaptic()
        this.pageStack.pop()
      })

      Text(I18n.get('artifacts.title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_on_surface'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 8 })
    }
    .width('100%')
    .height(52)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ErrorBanner() {
    Row() {
      Text(this.loadError)
        .fontSize(14)
        .fontColor($r('app.color.terminal_error'))
        .layoutWeight(1)
      Button(I18n.get('common.retry'))
        .fontSize(13)
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .borderRadius(8)
        .height(32)
        .onClick(() => this.loadArtifacts())
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.terminal_surface_container'))
    .margin({ left: 16, right: 16, bottom: 8 })
  }

  @Builder
  EmptyState() {
    Column() {
      SymbolGlyph($r('sys.symbol.paperplane'))
        .fontSize(40)
        .fontColor([$r('app.color.terminal_outline')])
        .margin({ bottom: 16 })
      Text(I18n.get('artifacts.description'))
        .fontSize(13)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 8 })
      Text(I18n.get('artifacts.empty'))
        .fontSize(13)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 80, left: 32, right: 32 })
  }

  @Builder
  LoadingSkeleton() {
    Column() {
      ForEach([0, 1, 2], (_: number, idx: number) => {
        Row() {
          Column() {
            Row().width(140).height(14).borderRadius(4)
              .backgroundColor($r('app.color.terminal_surface_container_high'))
            Row().width(90).height(10).borderRadius(4)
              .backgroundColor($r('app.color.terminal_surface_container_high'))
              .margin({ top: 6 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Blank()
          Row().width(40).height(40).borderRadius(8)
            .backgroundColor($r('app.color.terminal_surface_container_high'))
        }
        .width('100%')
        .height(64)
        .padding(14)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ bottom: 8 })
      }, (_: number, idx: number) => `${idx}`)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12 })
  }

  @Builder
  UploadBar() {
    Row() {
      Button(this.uploading ? I18n.get('artifacts.uploading') : I18n.get('artifacts.upload'))
        .fontSize(15)
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .borderRadius(24)
        .height(44)
        .layoutWeight(1)
        .enabled(!this.uploading)
        .onClick(() => this.handleUpload())
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.terminal_surface'))
  }

  private async loadArtifacts(): Promise<void> {
    this.loading = true
    this.loadError = ''
    try {
      const list = await ArtifactsService.listArtifacts(this.sessionId)
      list.forEach((item) => {
        if (item.sessionId.length === 0) {
          item.sessionId = this.sessionId
        }
      })
      this.artifacts = list
    } catch (e) {
      this.loadError = (e as Error).message || I18n.get('common.error')
    } finally {
      this.loading = false
    }
  }

  private async connectTransport(): Promise<void> {
    try {
      await this.transport.connect(this.authToken, this.gatewayUrl)
    } catch (e) {
      console.error(`[ArtifactsPage] transport.connect failed: ${(e as Error).message}`)
    }
  }

  private handleArtifactChanged(sessionId: string, artifactId: string, changeType: string,
    artifact: ArtifactModel | null): void {
    if (sessionId !== this.sessionId) {
      return
    }
    if (changeType === 'deleted') {
      this.artifacts = this.artifacts.filter((a) => a.id !== artifactId)
      return
    }
    if (!artifact) {
      return
    }
    artifact.sessionId = sessionId
    if (changeType === 'created') {
      if (!this.artifacts.some((a) => a.id === artifact.id)) {
        this.artifacts = [...this.artifacts, artifact]
      }
    } else {
      this.artifacts = this.artifacts.map((a) => a.id === artifact.id ? artifact : a)
    }
  }

  private async handleUpload(): Promise<void> {
    if (this.uploading) {
      return
    }
    let picked: FilePickerResult | null
    try {
      picked = await FilePicker.selectSingle()
    } catch (e) {
      showToast((e as Error).message)
      return
    }
    if (!picked) {
      return
    }
    if (picked.filename.length === 0) {
      showToast(I18n.get('common.error'))
      return
    }

    lightHaptic()
    this.uploading = true
    try {
      await ArtifactsService.uploadFromUri(getContext(this), this.sessionId, picked.uri, picked.filename)
      showToast(I18n.get('artifacts.upload_success'))
    } catch (e) {
      showToast((e as Error).message || I18n.get('artifacts.upload_failed'))
    } finally {
      this.uploading = false
    }
  }

  private async handleDownload(artifact: ArtifactModel): Promise<void> {
    if (this.isDownloading(artifact.id)) {
      return
    }
    this.downloadingIds = [...this.downloadingIds, artifact.id]
    showToast(I18n.get('artifacts.download_started'))
    try {
      const downloadUrl = await ArtifactsService.getDownloadUrl(this.sessionId, artifact.id)
      const filesDir = AppStorage.get<string>('filesDir') ?? ''
      if (filesDir.length === 0) {
        throw new Error('filesDir not available')
      }
      const safeName: string = artifact.filename.indexOf('%') >= 0
        ? decodeURIComponent(artifact.filename) : artifact.filename
      const targetPath = `${filesDir}/downloads/${safeName}`
      await FileDownloader.download(getContext(this), targetPath, downloadUrl)
      showToast(safeName)
    } catch (e) {
      showToast((e as Error).message || I18n.get('artifacts.download_failed'))
    } finally {
      this.downloadingIds = this.downloadingIds.filter((id) => id !== artifact.id)
    }
  }

  private async handleDelete(artifact: ArtifactModel): Promise<void> {
    try {
      await ArtifactsService.deleteArtifact(this.sessionId, artifact.id)
      this.artifacts = this.artifacts.filter((a) => a.id !== artifact.id)
    } catch (e) {
      showToast((e as Error).message || I18n.get('common.error'))
    }
  }

  private isDownloading(id: string): boolean {
    return this.downloadingIds.indexOf(id) >= 0
  }

  private buildGroups(): ArtifactGroup[] {
    const sorted = [...this.artifacts].sort((a, b) => a.uploadedAt - b.uploadedAt)
    const groups: ArtifactGroup[] = []
    sorted.forEach((item) => {
      const key = this.dayKey(item.uploadedAt)
      const label = this.dayLabel(item.uploadedAt)
      const last = groups.length > 0 ? groups[groups.length - 1] : null
      if (last && last.key === key) {
        last.items.push(item)
      } else {
        const freshGroup: ArtifactGroup = { key, label, items: [item] }
        groups.push(freshGroup)
      }
    })
    return groups
  }

  private dayKey(timestamp: number): string {
    if (timestamp <= 0) {
      return 'unknown'
    }
    const date = new Date(timestamp)
    return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`
  }

  private dayLabel(timestamp: number): string {
    if (timestamp <= 0) {
      return ''
    }
    const date = new Date(timestamp)
    const now = new Date()
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    const that = new Date(date.getFullYear(), date.getMonth(), date.getDate())
    const diffDays = Math.floor((today.getTime() - that.getTime()) / (24 * 3600 * 1000))
    if (diffDays <= 0) {
      return I18n.get('time.just_now')
    }
    return I18n.getWithArgs('time.days_ago', { 'n': `${diffDays}` })
  }
}
