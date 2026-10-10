/**
 * @file FileBrowserPage.ets
 * @brief Workspace file manager — browsing of a workspace (the session root on the worker)
 * with on-demand upload streamed through the Relay (or a direct endpoint) and in-place
 * preview for every file (see FilePreviewPage; no separate download step).
 *
 * Navigation is a breadcrumb over path segments; listing is a live worker RPC. Transfers
 * are initiated over REST and then streamed end-to-end — the PUT/GET response is the final
 * state, there is no polling and no intermediate storage.
 */
import { common } from '@kit.AbilityKit'
import fs from '@ohos.file.fs'
import hash from '@ohos.file.hash'
import { window } from '@kit.ArkUI'
import { ApiService, I18n, RouteName, showToast, lightHaptic, clickHaptic } from '@rwecho/core'
import { FileEntryModel, FileListingModel } from '../model/FileModels'
import { FilesService } from '../service/FilesService'
import { BrowseMemory } from '../service/BrowseMemory'
import { TransferRouteLog, RouteEntry } from '../service/TransferRouteLog'
import { FilePicker, FilePickerResult } from '../service/FilePicker'

interface FileNavParam {
  workerId: string;
  rootDir: string;
  workspaceId: string;
}

interface PreviewNavParam {
  workerId: string;
  rootDir: string;
  path: string;
  name: string;
  sizeBytes: number;
}

@Component
export struct FileBrowserPage {
  @State workerId: string = ''
  @State rootDir: string = ''
  @State workspaceId: string = ''
  @Link pathSegments: string[]
  // 路由层回退信号：FilesPageRoute 在系统返回手势里自增它，页面据此回上一级目录
  @Link @Watch('onGoUpRequested') goUpTick: number
  private restoredFromMemory: boolean = false
  @State entries: FileEntryModel[] = []
  @State truncated: boolean = false
  @State loading: boolean = true
  @State loadError: string = ''
  @State refreshing: boolean = false
  @State transferActive: boolean = false
  @State transferName: string = ''
  @State transferState: string = ''
  @State transferMessage: string = ''
  @State showNameSheet: boolean = false
  @State showRouteSheet: boolean = false
  @State nameSheetMode: string = ''
  @State nameSheetValue: string = ''
  @State renameTarget: FileEntryModel | null = null
  @Consume('pageStack') pageStack: NavPathStack

  /** 有 workspaceId 时使用 workspace 级 API（浏览 + 新建文件夹/重命名/删除）。 */
  private get hasWorkspace(): boolean {
    return this.workspaceId.length > 0
  }

  aboutToAppear() {
    const params = this.pageStack.getParamByName('files/Page') as FileNavParam[]
    if (params && params.length > 0) {
      this.workerId = params[params.length - 1].workerId
      this.rootDir = params[params.length - 1].rootDir
      this.workspaceId = params[params.length - 1].workspaceId || ''
    }
    if (this.workerId.length === 0 || this.rootDir.length === 0) {
      throw new Error('FileBrowserPage requires workerId and rootDir in nav params')
    }
    this.applyStatusBar(AppStorage.get<string>('colorMode') !== 'light')
    // workspace 模式下恢复上次浏览位置；终端 cwd 入口不记忆。
    // 恢复的路径若在远端已不存在（path_not_found / path_invalid），
    // loadListing 会清掉记忆、回根加载并 toast 明确告知，不静默回退。
    if (this.hasWorkspace) {
      const restored = BrowseMemory.load(getContext(this) as common.UIAbilityContext, this.workspaceId)
      if (restored.length > 0) {
        this.pathSegments = restored
        this.restoredFromMemory = true
      }
    }
    this.loadListing()
  }

  aboutToDisappear() {
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

  /** Breadcrumb labels: [根目录名, ...segments]. */
  private breadcrumbItems(): string[] {
    const items: string[] = [FileBrowserPage.baseName(this.rootDir)]
    return items.concat(this.pathSegments)
  }

  private static baseName(path: string): string {
    const trimmed = path.length > 1 ? path.replace(/\/+$/, '') : path
    const idx = Math.max(trimmed.lastIndexOf('/'), trimmed.lastIndexOf('\\'))
    return idx < 0 || (idx === 0 && trimmed.length === 1) ? trimmed : trimmed.substring(idx + 1)
  }

  private async loadListing(): Promise<void> {
    this.loading = this.entries.length === 0
    this.loadError = ''
    try {
      const listing = this.hasWorkspace
        ? await FilesService.listWorkspaceFiles(this.workspaceId, this.currentPath())
        : await FilesService.listFiles(this.workerId, this.rootDir, this.currentPath())
      this.entries = listing.entries
      this.truncated = listing.truncated
      this.restoredFromMemory = false
      BrowseMemory.save(getContext(this) as common.UIAbilityContext, this.workspaceId, this.pathSegments)
    } catch (e) {
      const message = (e as Error).message || I18n.get('common.error')
      // 记忆的目录在远端已被删除/改名：清掉记忆、回根重新加载，并明确告知用户
      if (this.restoredFromMemory && (message === 'path_not_found' || message === 'path_invalid')) {
        this.restoredFromMemory = false
        BrowseMemory.clear(getContext(this) as common.UIAbilityContext, this.workspaceId)
        this.pathSegments = []
        showToast(I18n.get('files.last_path_gone'))
        this.loadListing()
        return
      }
      this.loadError = message
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

  /** 系统返回手势（Files RouteServiceProvider 拦截后）逐级向上；根目录时放行 pop。 */
  private onGoUpRequested(): void {
    if (this.pathSegments.length > 0) {
      this.jumpToBreadcrumb(this.pathSegments.length - 1)
    }
  }

  /** 页内返回按钮与系统手势保持一致：非根回上一级，根目录才退出页面。 */
  private handleGoBack(): void {
    if (this.pathSegments.length > 0) {
      this.onGoUpRequested()
    } else {
      this.pageStack.pop()
    }
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
                    .fontColor($r('app.color.terminal_text_muted'))
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
    .backgroundColor($r('app.color.terminal_background'))
    .bindSheet(this.showNameSheet, this.NameSheet(), {
      detents: ['40%', SheetSize.MEDIUM],
      preferType: SheetType.BOTTOM,
      backgroundColor: $r('app.color.terminal_background'),
      onDisappear: () => { this.showNameSheet = false }
    })
    .bindSheet(this.showRouteSheet, this.RouteSheet(), {
      detents: ['40%', SheetSize.MEDIUM],
      preferType: SheetType.BOTTOM,
      backgroundColor: $r('app.color.terminal_background'),
      onDisappear: () => { this.showRouteSheet = false }
    })
  }

  @Builder
  NameSheet() {
    Column() {
      Text(this.nameSheetMode === 'rename'
        ? I18n.get('files.rename_prompt_title')
        : I18n.get('files.name_prompt_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_text'))
        .width('100%')

      TextInput({
        text: this.nameSheetValue,
        placeholder: I18n.get('files.name_placeholder')
      })
        .height(48)
        .borderRadius(8)
        .backgroundColor($r('app.color.terminal_background_element'))
        .fontColor($r('app.color.terminal_text'))
        .placeholderColor($r('app.color.terminal_text_muted'))
        .fontSize(16)
        .margin({ top: 16 })
        .onChange((value: string) => { this.nameSheetValue = value })

      Button(this.nameSheetMode === 'rename'
        ? I18n.get('files.rename')
        : I18n.get('files.mkdir'))
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor($r('app.color.terminal_inverse_surface'))
        .fontColor($r('app.color.terminal_inverse_on_surface'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 24 })
        .onClick(() => {
          clickHaptic()
          this.submitNameSheet()
        })
    }
    .width('100%')
    .padding(24)
  }

  @Builder
  EntryMenu(item: FileEntryModel) {
    if (this.hasWorkspace) {
      Menu() {
        MenuItem({ content: I18n.get('files.rename') })
          .onClick(() => {
            clickHaptic()
            this.openRenameSheet(item)
          })

        MenuItem({ content: I18n.get('files.delete') })
          .onClick(() => {
            clickHaptic()
            this.confirmDeleteEntry(item)
          })
      }
    }
  }

  @Builder
  TopBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([$r('app.color.terminal_text')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        clickHaptic()
        this.handleGoBack()
      })

      Text(I18n.get('files.title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_text'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 8 })

      if (this.hasWorkspace) {
        Button() {
          SymbolGlyph($r('sys.symbol.folder_badge_plus'))
            .fontSize(18)
            .fontColor([$r('app.color.terminal_on_secondary_container')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .margin({ left: 8 })
        .onClick(() => {
          clickHaptic()
          this.openMkdirSheet()
        })
      }

      Button() {
        SymbolGlyph($r('sys.symbol.link'))
          .fontSize(18)
          .fontColor([TransferRouteLog.lastSuccessRoute() === 'p2p'
            ? $r('app.color.terminal_success')
            : $r('app.color.terminal_on_secondary_container')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.terminal_secondary_container'))
      .margin({ left: 8 })
      .onClick(() => {
        clickHaptic()
        this.showRouteSheet = true
      })

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

  /** 通道显示名。 */
  private routeLabel(route: string): string {
    if (route === 'lan') {
      return I18n.get('files.route_lan')
    }
    if (route === 'p2p') {
      return I18n.get('files.route_p2p')
    }
    if (route === 'public') {
      return I18n.get('files.route_public')
    }
    return I18n.get('files.route_relay')
  }

  private static formatTime(timeMs: number): string {
    const d = new Date(timeMs)
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`
    return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
  }

  @Builder
  RouteSheet() {
    Column() {
      Text(I18n.get('files.p2p_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_text'))
        .width('100%')

      Row() {
        Text(I18n.get('files.p2p_last'))
          .fontSize(14)
          .fontColor($r('app.color.terminal_text_muted'))
          .layoutWeight(1)
        Text(TransferRouteLog.lastSuccessRoute().length > 0
          ? this.routeLabel(TransferRouteLog.lastSuccessRoute())
          : I18n.get('files.p2p_empty'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(TransferRouteLog.lastSuccessRoute() === 'p2p'
            ? $r('app.color.terminal_success')
            : $r('app.color.terminal_text'))
      }
      .width('100%')
      .margin({ top: 16 })

      if (TransferRouteLog.history().length === 0) {
        Text(I18n.get('files.p2p_empty'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_text_muted'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 32 })
      } else {
        List() {
          ForEach(TransferRouteLog.history(), (entry: RouteEntry) => {
            ListItem() {
              Row() {
                Text(entry.ok ? '✓' : '✗')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(entry.ok
                    ? $r('app.color.terminal_success')
                    : $r('app.color.terminal_error'))
                  .width(24)
                Text(this.routeLabel(entry.route))
                  .fontSize(14)
                  .fontColor($r('app.color.terminal_text'))
                  .layoutWeight(1)
                Text(FileBrowserPage.formatTime(entry.timeMs))
                  .fontSize(12)
                  .fontColor($r('app.color.terminal_text_tertiary'))
              }
              .width('100%')
              .padding({ top: 10, bottom: 10 })
            }
          }, (entry: RouteEntry, idx: number) => `${idx}_${entry.route}_${entry.ok}`)
        }
        .width('100%')
        .scrollBar(BarState.Off)
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(24)
  }

  @Builder
  Breadcrumb() {
    Scroll() {
      Row() {
        ForEach(this.breadcrumbItems(), (label: string, idx: number) => {
          if (idx > 0) {
            Text('/')
              .fontSize(13)
              .fontColor($r('app.color.terminal_border'))
              .margin({ left: 4, right: 4 })
          }
          Text(label)
            .fontSize(13)
            .fontColor(idx === this.pathSegments.length ? $r('app.color.terminal_text') : $r('app.color.terminal_text_muted'))
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
        .fontColor([item.isDirectory ? $r('app.color.terminal_secondary') : $r('app.color.terminal_text_muted')])
        .width(40)
        .height(40)
      Column() {
        Text(item.name)
          .fontSize(15)
          .fontColor($r('app.color.terminal_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.isDirectory
          ? I18n.get('files.folder')
          : `${FileBrowserPage.formatSize(item.sizeBytes)} · ${this.formatTime(item.modifiedMs)}`)
          .fontSize(11)
          .fontColor($r('app.color.terminal_text_muted'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })

      if (!item.isDirectory) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.terminal_text_muted')])
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
        this.openPreview(item)
      }
    })
    .bindContextMenu(this.EntryMenu(item), ResponseType.LongPress)
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
      // 记忆的路径在远端已被删除时，提供显式回根入口（不静默回退）
      if (this.hasWorkspace && this.pathSegments.length > 0) {
        Button(I18n.get('files.back_to_root'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_on_secondary_container'))
          .backgroundColor($r('app.color.terminal_secondary_container'))
          .borderRadius(8)
          .height(32)
          .margin({ left: 8 })
          .onClick(() => this.jumpToBreadcrumb(0))
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.terminal_background_panel'))
    .margin({ left: 16, right: 16, bottom: 8 })
  }

  @Builder
  EmptyState() {
    Column() {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(40)
        .fontColor([$r('app.color.terminal_border')])
        .margin({ bottom: 16 })
      Text(I18n.get('files.description'))
        .fontSize(13)
        .fontColor($r('app.color.terminal_text_muted'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 8 })
      Text(I18n.get('files.empty'))
        .fontSize(13)
        .fontColor($r('app.color.terminal_text_muted'))
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
            .backgroundColor($r('app.color.terminal_background_element'))
          Column() {
            Row().width(160).height(14).borderRadius(4)
              .backgroundColor($r('app.color.terminal_background_element'))
            Row().width(90).height(10).borderRadius(4)
              .backgroundColor($r('app.color.terminal_background_element'))
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
        .backgroundColor($r('app.color.terminal_background_panel'))
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
          .fontColor([$r('app.color.terminal_success')])
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
          .fontColor($r('app.color.terminal_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.transferMessage)
          .fontSize(11)
          .fontColor(this.transferState === 'failed'
            ? $r('app.color.terminal_error')
            : $r('app.color.terminal_text_muted'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.terminal_background_panel'))
  }

  // ── Workspace file mutations (mkdir / rename / delete) ────────────

  private openMkdirSheet(): void {
    this.nameSheetMode = 'mkdir'
    this.renameTarget = null
    this.nameSheetValue = ''
    this.showNameSheet = true
  }

  private openRenameSheet(item: FileEntryModel): void {
    this.nameSheetMode = 'rename'
    this.renameTarget = item
    this.nameSheetValue = item.name
    this.showNameSheet = true
  }

  private async submitNameSheet(): Promise<void> {
    const name = this.nameSheetValue.trim()
    if (name.length === 0) {
      showToast(I18n.get('files.name_required'))
      return
    }
    try {
      if (this.nameSheetMode === 'rename' && this.renameTarget) {
        await FilesService.rename(this.workspaceId, this.entryPath(this.renameTarget.name), name)
      } else {
        const segments = this.currentPath().length > 0
          ? `${this.currentPath()}/${name}`
          : name
        await FilesService.mkdir(this.workspaceId, segments)
      }
      this.showNameSheet = false
      this.renameTarget = null
      await this.loadListing()
    } catch (e) {
      // 重命名/新建失败必须把原因展示出来，不静默
      showToast((e as Error).message || I18n.get('files.op_failed'))
    }
  }

  private confirmDeleteEntry(item: FileEntryModel): void {
    const msgArgs: Record<string, string> = { 'name': item.name }
    this.getUIContext()?.showAlertDialog({
      title: I18n.get('files.delete_confirm_title'),
      message: I18n.getWithArgs('files.delete_confirm_message', msgArgs),
      primaryButton: {
        value: I18n.get('common.cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: I18n.get('files.delete'),
        fontColor: $r('app.color.terminal_error'),
        action: () => { this.deleteEntry(item) }
      }
    })
  }

  private async deleteEntry(item: FileEntryModel): Promise<void> {
    try {
      await FilesService.deleteFile(this.workspaceId, this.entryPath(item.name))
      await this.loadListing()
    } catch (e) {
      showToast((e as Error).message || I18n.get('files.op_failed'))
    }
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

  /** One file: sandbox copy → sha256 → init transfer → stream PUT to the endpoint. Throws to abort the batch. */
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

      const init = await FilesService.beginUpload(this.workerId, this.rootDir, dirPath, picked.filename, sizeBytes, sha256)
      await FilesService.uploadViaEndpoints(init.transferId, init.endpoints, buffer)
    } finally {
      fs.unlinkSync(sandboxPath)
    }
  }

  // ── Preview ───────────────────────────────────────────────────────

  private openPreview(item: FileEntryModel): void {
    lightHaptic()
    const param: PreviewNavParam = {
      workerId: this.workerId,
      rootDir: this.rootDir,
      path: this.entryPath(item.name),
      name: item.name,
      sizeBytes: item.sizeBytes
    }
    this.pageStack.pushPath({ name: RouteName.FILE_PREVIEW, param: param })
  }

  private entryPath(name: string): string {
    const segments = [...this.pathSegments, name]
    return segments.join('/')
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
}
