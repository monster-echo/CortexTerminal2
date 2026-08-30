/**
 * @file FileBrowserPage.ets
 * @brief Remote folder manager — read-only browsing of the session root (the worker's
 * PTY cwd) with on-demand upload/download through presigned S3 URLs.
 *
 * Navigation is a breadcrumb over path segments; listing is a live worker RPC. Downloads
 * poll the gateway until the worker finishes pushing the file to S3, then fetch it into
 * the app sandbox. Uploads relay the picked file: sha256 → presigned PUT → mirror ack.
 */
import { common } from '@kit.AbilityKit'
import fs from '@ohos.file.fs'
import hash from '@ohos.file.hash'
import { window } from '@kit.ArkUI'
import { ApiService, I18n, showToast, lightHaptic, clickHaptic } from '@rwecho/core'
import { FileEntryModel, FileListingModel, DownloadPollState } from '../model/FileModels'
import { FilesService } from '../service/FilesService'
import { FilePicker, FilePickerResult } from '../service/FilePicker'
import { FileDownloader } from '../service/FileDownloader'

interface FileNavParam {
  sessionId: string;
}

const POLL_INTERVAL_MS = 2000
const POLL_MAX_ATTEMPTS = 150
const IMAGE_EXTENSIONS: string[] = ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp', '.svg', '.heic']

@Component
export struct FileBrowserPage {
  @State sessionId: string = ''
  @State pathSegments: string[] = []
  @State entries: FileEntryModel[] = []
  @State truncated: boolean = false
  @State loading: boolean = true
  @State loadError: string = ''
  @State refreshing: boolean = false
  @State transferActive: boolean = false
  @State transferName: string = ''
  @State transferState: string = ''
  @State transferMessage: string = ''
  @State previewPath: string = ''
  @State showPreview: boolean = false
  @Consume('pageStack') pageStack: NavPathStack
  private pollCancelled: boolean = false

  aboutToAppear() {
    const params = this.pageStack.getParamByName('files/Page') as FileNavParam[]
    if (params && params.length > 0) {
      this.sessionId = params[params.length - 1].sessionId
    }
    if (this.sessionId.length === 0) {
      throw new Error('FileBrowserPage requires a sessionId in nav params')
    }
    this.applyStatusBar(AppStorage.get<string>('colorMode') !== 'light')
    this.loadListing()
  }

  aboutToDisappear() {
    this.pollCancelled = true
    // 唯一入口/返回目标是恒深色的终端页,恢复白字状态栏
    this.applyStatusBar(true)
  }

  private applyStatusBar(forceWhite: boolean): void {
    const context = getContext(this) as common.UIAbilityContext
    window.getLastWindow(context).then((win: window.Window) => {
      win.setWindowSystemBarProperties({
        statusBarContentColor: forceWhite ? '#ffffff' : '#000000'
      }).catch((e: Error) => {
        console.error(`[FileBrowserPage] setWindowSystemBarProperties failed: ${e.message}`)
      })
    }).catch((e: Error) => {
      console.error(`[FileBrowserPage] getLastWindow failed: ${e.message}`)
    })
  }

  /** Relative path for API calls; [] = session root. */
  private currentPath(): string {
    return this.pathSegments.join('/')
  }

  /** Breadcrumb labels: [主目录, ...segments]. */
  private breadcrumbItems(): string[] {
    const items: string[] = [I18n.get('files.home')]
    return items.concat(this.pathSegments)
  }

  private async loadListing(): Promise<void> {
    this.loading = this.entries.length === 0
    this.loadError = ''
    try {
      const listing = await FilesService.listFiles(this.sessionId, this.currentPath())
      this.entries = listing.entries
      this.truncated = listing.truncated
    } catch (e) {
      this.loadError = (e as Error).message || I18n.get('common.error')
      this.entries = []
    } finally {
      this.loading = false
      this.refreshing = false
    }
  }

  private openDirectory(name: string): void {
    clickHaptic()
    this.pathSegments = [...this.pathSegments, name]
    this.loadListing()
  }

  private jumpToBreadcrumb(index: number): void {
    clickHaptic()
    // index 0 = 主目录;index i ≥ 1 = 保留前 i-1 个段后进入第 i-1 段所在目录
    this.pathSegments = index === 0 ? [] : this.pathSegments.slice(0, index)
    this.loadListing()
  }

  build() {
    Column() {
      this.TopBar()
      this.Breadcrumb()
      Column() {
        if (this.loadError.length > 0) {
          this.ErrorBanner()
        }
        if (this.loading) {
          this.LoadingSkeleton()
        } else if (this.entries.length === 0 && this.loadError.length === 0) {
          this.EmptyState()
        } else {
          Refresh({ refreshing: this.refreshing }) {
            List() {
              ForEach(this.entries, (item: FileEntryModel) => {
                ListItem() {
                  this.FileRow(item)
                }
              }, (item: FileEntryModel) => `${item.isDirectory ? 'd' : 'f'}_${item.name}`)
              if (this.truncated) {
                ListItem() {
                  Text(I18n.get('files.list_truncated'))
                    .fontSize(12)
                    .fontColor($r('app.color.terminal_on_surface_variant'))
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding(12)
                }
              }
            }
            .width('100%')
            .scrollBar(BarState.Off)
          }
          .onRefreshing(() => {
            this.refreshing = true
            this.loadListing()
          })
          .layoutWeight(1)
        }
      }
      .layoutWeight(1)
      .width('100%')

      if (this.transferActive) {
        this.TransferBar()
      }
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
    Image(`file://${this.previewPath}`)
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Contain)
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

      Text(I18n.get('files.title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_on_surface'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 8 })

      Button() {
        SymbolGlyph($r('sys.symbol.arrow_up'))
          .fontSize(18)
          .fontColor([$r('app.color.terminal_on_secondary_container')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.terminal_secondary_container'))
      .margin({ left: 8 })
      .onClick(() => {
        this.handleUpload()
      })
    }
    .width('100%')
    .height(52)
    .padding({ left: 8, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  Breadcrumb() {
    Scroll() {
      Row() {
        ForEach(this.breadcrumbItems(), (label: string, idx: number) => {
          if (idx > 0) {
            Text('/')
              .fontSize(13)
              .fontColor($r('app.color.terminal_outline'))
              .margin({ left: 4, right: 4 })
          }
          Text(label)
            .fontSize(13)
            .fontColor(idx === this.pathSegments.length ? $r('app.color.terminal_primary') : $r('app.color.terminal_secondary'))
            .fontWeight(idx === this.pathSegments.length ? FontWeight.Medium : FontWeight.Normal)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => {
              if (idx < this.pathSegments.length) {
                this.jumpToBreadcrumb(idx)
              }
            })
        }, (label: string, idx: number) => `${idx}_${label}`)
      }
      .constraintSize({ minWidth: '100%' })
      .padding({ left: 16, right: 16, top: 4, bottom: 10 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  FileRow(item: FileEntryModel) {
    Row() {
      SymbolGlyph(item.isDirectory ? $r('sys.symbol.folder_fill') : $r('sys.symbol.doc'))
        .fontSize(22)
        .fontColor([item.isDirectory ? $r('app.color.terminal_secondary') : $r('app.color.terminal_on_surface_variant')])
        .width(40)
        .height(40)
      Column() {
        Text(item.name)
          .fontSize(15)
          .fontColor($r('app.color.terminal_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.isDirectory
          ? I18n.get('files.folder')
          : `${FileBrowserPage.formatSize(item.sizeBytes)} · ${this.formatTime(item.modifiedMs)}`)
          .fontSize(11)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })

      if (!item.isDirectory) {
        SymbolGlyph($r('sys.symbol.arrow_down_circle'))
          .fontSize(18)
          .fontColor([$r('app.color.terminal_secondary')])
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .borderRadius(10)
    .onClick(() => {
      if (item.isDirectory) {
        this.openDirectory(item.name)
      } else {
        this.handleDownload(item)
      }
    })
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
        .onClick(() => this.loadListing())
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.terminal_surface_container'))
    .margin({ left: 16, right: 16, bottom: 8 })
  }

  @Builder
  EmptyState() {
    Column() {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(40)
        .fontColor([$r('app.color.terminal_outline')])
        .margin({ bottom: 16 })
      Text(I18n.get('files.description'))
        .fontSize(13)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 8 })
      Text(I18n.get('files.empty'))
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
      ForEach([0, 1, 2, 3], (_: number, idx: number) => {
        Row() {
          Row().width(40).height(40).borderRadius(8)
            .backgroundColor($r('app.color.terminal_surface_container_high'))
          Column() {
            Row().width(160).height(14).borderRadius(4)
              .backgroundColor($r('app.color.terminal_surface_container_high'))
            Row().width(90).height(10).borderRadius(4)
              .backgroundColor($r('app.color.terminal_surface_container_high'))
              .margin({ top: 6 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 10 })
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
  TransferBar() {
    Row() {
      if (this.transferState === 'done') {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(18)
          .fontColor([$r('app.color.terminal_tertiary')])
      } else if (this.transferState === 'failed') {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(18)
          .fontColor([$r('app.color.terminal_error')])
      } else {
        LoadingProgress()
          .width(18)
          .height(18)
          .color($r('app.color.terminal_secondary'))
      }
      Column() {
        Text(this.transferName)
          .fontSize(13)
          .fontColor($r('app.color.terminal_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.transferMessage)
          .fontSize(11)
          .fontColor(this.transferState === 'failed'
            ? $r('app.color.terminal_error')
            : $r('app.color.terminal_on_surface_variant'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.terminal_surface_container'))
  }

  // ── Upload flow ───────────────────────────────────────────────────

  private async handleUpload(): Promise<void> {
    if (this.transferActive) {
      return
    }
    let picked: FilePickerResult[] = []
    try {
      picked = await FilePicker.selectMultiple(9)
    } catch (e) {
      showToast((e as Error).message)
      return
    }
    if (picked.length === 0) {
      return
    }

    lightHaptic()
    this.transferActive = true
    const dirPath = this.currentPath()
    try {
      for (let i = 0; i < picked.length; i++) {
        await this.uploadOne(dirPath, picked[i], i + 1, picked.length)
      }
    } catch (e) {
      this.transferState = 'failed'
      this.transferMessage = (e as Error).message || I18n.get('files.upload_failed')
      showToast(this.transferMessage)
    } finally {
      this.transferActive = false
      await this.loadListing()
    }
  }

  /** One file: sandbox copy → sha256 → presigned PUT → mirror ack. Throws to abort the batch. */
  private async uploadOne(dirPath: string, picked: FilePickerResult, index: number, total: number): Promise<void> {
    if (picked.filename.length === 0) {
      throw new Error(I18n.get('common.error'))
    }
    this.transferName = picked.filename
    this.transferState = 'uploading'
    this.transferMessage = total > 1 ? `${index}/${total}` : I18n.get('files.uploading')

    const context = getContext(this) as common.UIAbilityContext
    const sandboxPath = `${context.cacheDir}/${Date.now()}_${picked.filename}`
    const srcFile = fs.openSync(picked.uri, fs.OpenMode.READ_ONLY)
    const destFile = fs.openSync(sandboxPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE)
    try {
      await fs.copyFile(srcFile.fd, destFile.fd)
    } finally {
      fs.closeSync(srcFile)
      fs.closeSync(destFile)
    }

    try {
      const sha256 = await hash.hash(sandboxPath, 'sha256')
      const stat = fs.statSync(sandboxPath)
      const sizeBytes = stat.size
      const readFile = fs.openSync(sandboxPath, fs.OpenMode.READ_ONLY)
      const buffer: ArrayBuffer = new ArrayBuffer(sizeBytes)
      try {
        fs.readSync(readFile.fd, buffer)
      } finally {
        fs.closeSync(readFile)
      }

      const init = await FilesService.beginUpload(this.sessionId, dirPath, picked.filename, sizeBytes, sha256)
      await ApiService.putBinaryToS3(init.uploadUrl, buffer)
      await FilesService.completeUpload(this.sessionId, init.requestId)
    } finally {
      fs.unlinkSync(sandboxPath)
    }
  }

  // ── Download flow ─────────────────────────────────────────────────

  private async handleDownload(item: FileEntryModel): Promise<void> {
    if (this.transferActive) {
      return
    }
    lightHaptic()
    this.transferActive = true
    this.transferName = item.name
    this.transferState = 'downloading'
    this.transferMessage = I18n.get('files.download_started')
    try {
      const path = this.entryPath(item.name)
      const requestId = await FilesService.startDownload(this.sessionId, path)
      const poll = await this.pollUntilReady(requestId)

      const filesDir = AppStorage.get<string>('filesDir') ?? ''
      if (filesDir.length === 0) {
        throw new Error('filesDir not available')
      }
      const downloadDir = `${filesDir}/downloads`
      try {
        fs.mkdirSync(downloadDir, true)
      } catch (_e) {
        // 目录已存在,忽略 —— 鸿蒙 request.downloadFile 写文件要求父目录存在,否则报 get FD
      }
      const targetPath = `${downloadDir}/${item.name}`
      const context = getContext(this) as common.UIAbilityContext
      await FileDownloader.download(context, targetPath, poll.downloadUrl)

      this.transferState = 'done'
      this.transferMessage = I18n.get('files.download_done')
      showToast(item.name)
      if (FileBrowserPage.isImageName(item.name)) {
        this.previewPath = targetPath
        this.showPreview = true
      }
    } catch (e) {
      this.transferState = 'failed'
      this.transferMessage = (e as Error).message || I18n.get('files.download_failed')
      showToast(this.transferMessage)
    } finally {
      this.transferActive = false
    }
  }

  /** Poll the gateway every 2s until the worker finishes pushing to S3. */
  private async pollUntilReady(requestId: string): Promise<DownloadPollState> {
    for (let attempt = 0; attempt < POLL_MAX_ATTEMPTS; attempt++) {
      if (this.pollCancelled) {
        throw new Error(I18n.get('files.download_failed'))
      }
      await FileBrowserPage.sleep(POLL_INTERVAL_MS)
      const poll = await FilesService.pollDownload(this.sessionId, requestId)
      if (poll.status === 'ready') {
        return poll
      }
      if (poll.status === 'failed') {
        throw new Error(poll.errorMessage || I18n.get('files.download_failed'))
      }
    }
    throw new Error(I18n.get('files.download_timeout'))
  }

  private entryPath(name: string): string {
    const segments = [...this.pathSegments, name]
    return segments.join('/')
  }

  private static isImageName(name: string): boolean {
    const lower = name.toLowerCase()
    for (let i = 0; i < IMAGE_EXTENSIONS.length; i++) {
      if (lower.endsWith(IMAGE_EXTENSIONS[i])) {
        return true
      }
    }
    return false
  }

  private static formatSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`
    }
    if (bytes < 1024 * 1024 * 1024) {
      return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
    }
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`
  }

  private formatTime(ms: number): string {
    if (ms <= 0 || Number.isNaN(ms)) {
      return ''
    }
    const date = new Date(ms)
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`
    return `${date.getMonth() + 1}-${date.getDate()} ${pad(date.getHours())}:${pad(date.getMinutes())}`
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => resolve(), ms)
    })
  }
}
