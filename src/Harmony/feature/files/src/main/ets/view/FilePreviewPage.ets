/**
 * @file FilePreviewPage.ets
 * @brief In-place preview for workspace files (no download step for the user).
 *
 * Pushed when a file row is tapped. The bytes are streamed once into the app cache
 * (LAN-direct or Relay, same transfer plumbing as uploads) and then rendered by kind:
 *   image → PixelMap, video → Video component, audio → AVPlayer, text/code → scrollable
 *   monospace text, anything else → metadata card.
 */
import { common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import fs, { ReadTextOptions } from '@ohos.file.fs'
import { image } from '@kit.ImageKit'
import { media } from '@kit.MediaKit'
import { I18n, PageLayout } from '@rwecho/core'
import { FilesService } from '../service/FilesService'

interface PreviewNavParam {
  workspaceId: string
  path: string
  name: string
  sizeBytes: number
}

const IMAGE_EXTENSIONS: string[] = ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp', '.svg', '.heic', '.avif']
const VIDEO_EXTENSIONS: string[] = ['.mp4', '.mov', '.mkv', '.webm', '.avi', '.m4v', '.3gp', '.ts']
const AUDIO_EXTENSIONS: string[] = ['.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.opus', '.wma']
const TEXT_EXTENSIONS: string[] = [
  '.txt', '.md', '.json', '.log', '.yml', '.yaml', '.xml', '.csv', '.ini', '.conf', '.cfg',
  '.sh', '.ps1', '.bat', '.py', '.js', '.ts', '.ets', '.java', '.kt', '.cs', '.c', '.h',
  '.cpp', '.go', '.rs', '.sql', '.html', '.css', '.scss', '.toml', '.gradle', '.properties'
]

/** 文本预览上限：超过则只读前 512KB 并提示截断。 */
const TEXT_PREVIEW_CAP_BYTES: number = 512 * 1024
/** 未知扩展名但体积很小 —— 按文本尝试（.bashrc 这类无扩展名配置文件没有扩展名）。 */
const UNKNOWN_AS_TEXT_CAP_BYTES: number = 256 * 1024

@Component
export struct FilePreviewPage {
  @Consume('pageStack') pageStack: NavPathStack
  @State isLoading: boolean = true
  @State loadError: string = ''
  @State kind: string = ''
  @State textContent: string = ''
  @State textTruncated: boolean = false
  @State imagePixels: image.PixelMap | undefined = undefined
  private workspaceId: string = ''
  private remotePath: string = ''
  private fileName: string = ''
  private fileSize: number = 0
  private localPath: string = ''
  private videoController: VideoController = new VideoController()
  private player: media.AVPlayer | undefined = undefined

  async aboutToAppear() {
    const params = this.pageStack.getParamByName('files/Preview') as PreviewNavParam[]
    if (params && params.length > 0) {
      const last = params[params.length - 1]
      this.workspaceId = last.workspaceId
      this.remotePath = last.path
      this.fileName = last.name
      this.fileSize = last.sizeBytes
    }
    if (this.workspaceId.length === 0 || this.remotePath.length === 0) {
      throw new Error('FilePreviewPage requires workspaceId and path in nav params')
    }
    await this.prepare()
  }

  aboutToDisappear() {
    if (this.player !== undefined) {
      this.player.release()
      this.player = undefined
    }
  }

  private async prepare(): Promise<void> {
    this.isLoading = true
    this.loadError = ''
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext
      const previewDir = `${context.cacheDir}/preview`
      if (!fs.accessSync(previewDir)) {
        fs.mkdirSync(previewDir)
      }

      const init = await FilesService.startDownload(this.workspaceId, this.remotePath)
      this.localPath = `${previewDir}/${this.fileName}`
      await FilesService.downloadViaEndpoints(context, this.localPath, init.endpoints)

      this.kind = FilePreviewPage.classify(this.fileName, this.fileSize)
      if (this.kind === 'image') {
        await this.loadImage()
      } else if (this.kind === 'text') {
        this.loadText()
      } else if (this.kind === 'audio') {
        await this.startAudio()
      }
    } catch (e) {
      this.loadError = (e as Error).message || I18n.get('files.preview_failed')
    } finally {
      this.isLoading = false
    }
  }

  private async loadImage(): Promise<void> {
    const source = image.createImageSource(this.localPath)
    try {
      this.imagePixels = await source.createPixelMap()
    } finally {
      source.release()
    }
  }

  private loadText(): void {
    const stat = fs.statSync(this.localPath)
    this.textTruncated = stat.size > TEXT_PREVIEW_CAP_BYTES
    const options: ReadTextOptions = {
      offset: 0,
      length: Math.min(stat.size, TEXT_PREVIEW_CAP_BYTES)
    }
    this.textContent = fs.readTextSync(this.localPath, options)
  }

  private async startAudio(): Promise<void> {
    const file = fs.openSync(this.localPath, fs.OpenMode.READ_ONLY)
    const descriptor: media.AVFileDescriptor = { fd: file.fd }
    const player = await media.createAVPlayer()
    this.player = player
    player.on('stateChange', (state: string) => {
      if (state === 'initialized') {
        player.prepare()
      } else if (state === 'prepared') {
        player.play()
      }
    })
    player.on('error', (err: BusinessError) => {
      this.loadError = `${err.message}`
    })
    player.fdSrc = descriptor
  }

  private static classify(name: string, sizeBytes: number): string {
    const lower = name.toLowerCase()
    if (FilePreviewPage.hasExtension(lower, IMAGE_EXTENSIONS)) {
      return 'image'
    }
    if (FilePreviewPage.hasExtension(lower, VIDEO_EXTENSIONS)) {
      return 'video'
    }
    if (FilePreviewPage.hasExtension(lower, AUDIO_EXTENSIONS)) {
      return 'audio'
    }
    if (FilePreviewPage.hasExtension(lower, TEXT_EXTENSIONS)) {
      return 'text'
    }
    // 无扩展名的配置文件（.bashrc / Makefile 之类）体积小，按文本读
    const dotIndex = lower.lastIndexOf('.')
    if ((dotIndex <= 0 || dotIndex === lower.length - 1) && sizeBytes <= UNKNOWN_AS_TEXT_CAP_BYTES) {
      return 'text'
    }
    return 'other'
  }

  private static hasExtension(name: string, extensions: string[]): boolean {
    for (let i = 0; i < extensions.length; i++) {
      if (name.endsWith(extensions[i])) {
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

  build() {
    PageLayout({ title: this.fileName }) {
      Column() {
        if (this.isLoading) {
          Column() {
            LoadingProgress().width(40).height(40).color($r('app.color.terminal_on_surface_variant'))
          }
          .width('100%')
          .padding({ top: 80 })
          .alignItems(HorizontalAlign.Center)
        } else if (this.loadError.length > 0) {
          this.ErrorState()
        } else if (this.kind === 'image') {
          this.ImagePreview()
        } else if (this.kind === 'video') {
          this.VideoPreview()
        } else if (this.kind === 'audio') {
          this.AudioPreview()
        } else if (this.kind === 'text') {
          this.TextPreview()
        } else {
          this.MetadataCard()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8 })
    }
  }

  @Builder
  ErrorState() {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(40)
        .fontColor([$r('app.color.terminal_error')])
      Text(I18n.get('files.preview_failed'))
        .fontSize(14)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 12 })
      Text(this.loadError)
        .fontSize(12)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 4 })
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 60 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ImagePreview() {
    Column() {
      if (this.imagePixels !== undefined) {
        Image(this.imagePixels)
          .width('100%')
          .layoutWeight(1)
          .objectFit(ImageFit.Contain)
          .borderRadius(12)
      }
      Text(`${FilePreviewPage.formatSize(this.fileSize)}`)
        .fontSize(12)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 8 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  VideoPreview() {
    Column() {
      Video({
        src: `file://${this.localPath}`,
        controller: this.videoController
      })
        .width('100%')
        .layoutWeight(1)
        .controls(true)
        .autoPlay(false)
        .objectFit(ImageFit.Contain)
        .borderRadius(12)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  AudioPreview() {
    Column() {
      SymbolGlyph($r('sys.symbol.paperplane'))
        .fontSize(56)
        .fontColor([$r('app.color.terminal_secondary')])
      Text(this.fileName)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.terminal_primary'))
        .margin({ top: 16 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(FilePreviewPage.formatSize(this.fileSize))
        .fontSize(12)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 4 })
      Text(I18n.get('files.preview_audio_playing'))
        .fontSize(12)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 20 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  TextPreview() {
    Column() {
      Scroll() {
        Text(this.textContent)
          .fontSize(13)
          .fontFamily('monospace')
          .fontColor($r('app.color.terminal_primary'))
          .textAlign(TextAlign.Start)
          .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)

      if (this.textTruncated) {
        Text(I18n.get('files.preview_truncated'))
          .fontSize(11)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  MetadataCard() {
    Column() {
      SymbolGlyph($r('sys.symbol.doc'))
        .fontSize(48)
        .fontColor([$r('app.color.terminal_outline')])
      Text(I18n.get('files.preview_unsupported'))
        .fontSize(14)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 16 })
        .textAlign(TextAlign.Center)
      Row() {
        Text(I18n.get('files.preview_size'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .layoutWeight(1)
        Text(FilePreviewPage.formatSize(this.fileSize))
          .fontSize(13)
          .fontColor($r('app.color.terminal_primary'))
      }
      .width('100%')
      .margin({ top: 24 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}