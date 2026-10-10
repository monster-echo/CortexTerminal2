import { ApiService, I18n, WorkerInfo, showI18nToast, showToast, lightHaptic, clickHaptic } from '@rwecho/core'

/** 文件夹选择页里的一个目录项（只展示目录，不展示普通文件，design/02 §4）。 */
class DirEntry {
  name: string = ''
  path: string = ''
}

/**
 * @file NewWorkspaceFlow.ets
 * @brief 新建工作区流程（design/02 §3-§4）：电脑（必填）→ 文件夹 picker（必填）→
 * 名称（默认取文件夹 basename，可改）→ 创建。
 *
 * 可复用：侧边栏「+ 新建工作区」、SessionHomePage 空态引导、CreateSessionSheet
 * 无工作区引导都以本组件为内容（独立 bindSheet 或内嵌均可）；WorkerDetailPage
 * 传入 lockWorkerId 锁定电脑。
 */
@Component
export struct NewWorkspaceFlow {
  /** 非空时锁定电脑（WorkerDetailPage 场景）；空串 = 先选电脑。 */
  lockWorkerId: string = ''
  onCreated?: (workspaceId: string, workspaceName: string) => void
  onCancelled?: (() => void) | null = null

  @State workers: WorkerInfo[] = []
  @State selectedWorkerId: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''

  @State currentPath: string = ''
  @State dirEntries: DirEntry[] = []
  @State isLoadingDir: boolean = false
  @State folderChosen: boolean = false

  @State workspaceName: string = ''
  @State nameAutoFilled: boolean = false
  @State isCreating: boolean = false

  aboutToAppear(): void {
    if (this.lockWorkerId.length > 0) {
      this.selectedWorkerId = this.lockWorkerId
      this.loadDirectory('')
    }
    this.loadWorkers()
  }

  private selectedWorker(): WorkerInfo | null {
    for (let i = 0; i < this.workers.length; i++) {
      if (this.workers[i].id === this.selectedWorkerId) {
        return this.workers[i]
      }
    }
    return null
  }

  /** 创建按钮可用：电脑 + 文件夹 + 名称齐备（design/02 §3 全部必填）。 */
  private canCreate(): boolean {
    return this.selectedWorkerId.length > 0 && this.folderChosen
      && this.workspaceName.trim().length > 0 && !this.isCreating
  }

  build() {
    Scroll() {
      Column() {
        Text(I18n.get('workspaces.create'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_text'))
          .width('100%')
          .margin({ bottom: 16 })

        if (this.isLoading) {
          Column() {
            LoadingProgress().width(32).height(32).color($r('app.color.terminal_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 24 })
        } else if (this.errorMessage.length > 0) {
          Column() {
            Text(this.errorMessage)
              .fontSize(13)
              .fontColor($r('app.color.terminal_error'))
              .textAlign(TextAlign.Center)
              .width('100%')

            Button(I18n.get('common.retry'))
              .height(36)
              .borderRadius(8)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .fontSize(13)
              .margin({ top: 12 })
              .onClick(() => {
                clickHaptic()
                this.errorMessage = ''
                this.loadWorkers()
              })
          }
          .width('100%')
          .margin({ top: 16 })
        } else {
          this.WorkerSection()
          this.FolderSection()
          this.NameSection()

          Button(I18n.get('workspaces.create'))
            .width('100%')
            .height(48)
            .borderRadius(24)
            .backgroundColor($r('app.color.terminal_inverse_surface'))
            .fontColor($r('app.color.terminal_inverse_on_surface'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 24 })
            .enabled(this.canCreate())
            .opacity(this.canCreate() ? 1 : 0.5)
            .onClick(() => { this.submitCreate() })
        }
      }
      .width('100%')
    }
    .width('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  WorkerSection() {
    Text(I18n.get('workspaces.pick_worker'))
      .fontSize(14)
      .fontColor($r('app.color.terminal_text_muted'))
      .width('100%')
      .margin({ bottom: 8 })

    if (this.lockWorkerId.length > 0) {
      // 锁定电脑（WorkerDetailPage）：只展示，不可换。
      Row() {
        SymbolGlyph($r('sys.symbol.computer'))
          .fontSize(18)
          .fontColor([$r('app.color.terminal_secondary')])
        Text(this.workerDisplayName(this.selectedWorkerId))
          .fontSize(15)
          .fontColor($r('app.color.terminal_text'))
          .layoutWeight(1)
          .margin({ left: 10 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 12 })
      .borderRadius(10)
      .backgroundColor($r('app.color.terminal_background_element'))
    } else {
      List() {
        ForEach(this.workers, (worker: WorkerInfo) => {
          ListItem() {
            Row() {
              Circle().width(10).height(10)
                .fill(worker.isOnline ? $r('app.color.terminal_success') : $r('app.color.terminal_status_idle'))
                .margin({ right: 12 })

              Text(worker.name || worker.hostname || 'Unknown')
                .fontSize(15)
                .fontColor($r('app.color.terminal_text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)

              if (this.selectedWorkerId === worker.id) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(16)
                  .fontColor([$r('app.color.terminal_text')])
              }
            }
            .width('100%')
            .height(48)
            .padding({ left: 12, right: 12 })
            .borderRadius(10)
            .backgroundColor(this.selectedWorkerId === worker.id
              ? $r('app.color.terminal_secondary_container')
              : $r('app.color.terminal_background_element'))
            // 离线 worker 无法执行远端 RPC（浏览文件夹 / 创建），置灰不可选。
            .opacity(worker.isOnline ? 1 : 0.4)
            .enabled(worker.isOnline)
            .onClick(() => { this.selectWorker(worker.id) })
          }
        }, (worker: WorkerInfo) => worker.id)
      }
      .width('100%')
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  FolderSection() {
    Text(I18n.get('workspaces.pick_folder'))
      .fontSize(14)
      .fontColor($r('app.color.terminal_text_muted'))
      .width('100%')
      .margin({ top: 16, bottom: 8 })

    if (this.selectedWorkerId.length === 0) {
      Text(I18n.get('workspaces.folder_pick_worker_hint'))
        .fontSize(13)
        .fontColor($r('app.color.terminal_text_tertiary'))
        .width('100%')
    } else {
      Column() {
        // 当前位置（design/02 §4）：空路径 = 主目录。
        Row() {
          SymbolGlyph($r('sys.symbol.folder_fill'))
            .fontSize(16)
            .fontColor([$r('app.color.terminal_secondary')])
          Text(this.folderChosen ? this.currentDisplayPath() : `${I18n.get('workspaces.folder_current_position')}：${this.currentDisplayPath()}`)
            .fontSize(13)
            .fontColor($r('app.color.terminal_text_muted'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 8 })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })

        Divider().color($r('app.color.terminal_border_subtle'))

        if (this.isLoadingDir) {
          Column() {
            LoadingProgress().width(24).height(24).color($r('app.color.terminal_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding(16)
        } else if (this.dirEntries.length === 0) {
          Text(I18n.get('workspaces.folder_empty'))
            .fontSize(13)
            .fontColor($r('app.color.terminal_text_tertiary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding(16)
        } else {
          List() {
            ForEach(this.dirEntries, (entry: DirEntry) => {
              ListItem() {
                // 点击文件夹行 = 进入该目录（不承担选中动作，design/02 §4）。
                Row() {
                  SymbolGlyph($r('sys.symbol.folder'))
                    .fontSize(16)
                    .fontColor([$r('app.color.terminal_secondary')])
                  Text(entry.name)
                    .fontSize(14)
                    .fontColor($r('app.color.terminal_text'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ left: 10 })
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(12)
                    .fontColor([$r('app.color.terminal_text_muted')])
                }
                .width('100%')
                .height(44)
                .padding({ left: 12, right: 12 })
                .onClick(() => { this.enterDirectory(entry.path) })
              }
            }, (entry: DirEntry) => entry.path)
          }
          .width('100%')
          .height(160)
          .scrollBar(BarState.Off)
        }

        // 底部按钮 = 选中「当前目录」（design/02 §4）。
        Button(this.folderChosen
          ? `${I18n.get('workspaces.folder_chosen')}：${this.currentDisplayPath()}`
          : I18n.get('workspaces.folder_current'))
          .width('100%')
          .height(40)
          .borderRadius(8)
          .backgroundColor(this.folderChosen
            ? $r('app.color.terminal_secondary_container')
            : $r('app.color.terminal_background_element'))
          .fontColor($r('app.color.terminal_on_secondary_container'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 8, bottom: 12 })
          .onClick(() => { this.chooseCurrentFolder() })
      }
      .width('100%')
      .borderRadius(10)
      .backgroundColor($r('app.color.terminal_background_element'))
      .clip(true)
    }
  }

  @Builder
  NameSection() {
    Text(I18n.get('workspaces.name'))
      .fontSize(14)
      .fontColor($r('app.color.terminal_text_muted'))
      .width('100%')
      .margin({ top: 16, bottom: 8 })

    TextInput({ text: this.workspaceName, placeholder: I18n.get('workspaces.name') })
      .height(48)
      .borderRadius(8)
      .backgroundColor($r('app.color.terminal_background_element'))
      .fontColor($r('app.color.terminal_text'))
      .placeholderColor($r('app.color.terminal_text_muted'))
      .fontSize(16)
      .onChange((value: string) => {
        this.workspaceName = value
        // 用户手动改过之后不再自动覆盖。
        this.nameAutoFilled = false
      })
  }

  private currentDisplayPath(): string {
    return this.currentPath.length === 0 ? I18n.get('files.home') : this.currentPath
  }

  private workerDisplayName(workerId: string): string {
    if (workerId === this.lockWorkerId && this.workers.length === 0) {
      return workerId
    }
    for (let i = 0; i < this.workers.length; i++) {
      const w = this.workers[i]
      if (w.id === workerId || w.workerId === workerId) {
        return w.name || w.hostname || workerId
      }
    }
    return workerId
  }

  private async loadWorkers() {
    this.isLoading = true
    this.errorMessage = ''
    try {
      this.workers = await ApiService.listWorkers()
    } catch (e) {
      this.errorMessage = (e as Error).message
    } finally {
      this.isLoading = false
    }
  }

  /** 换电脑后原文件夹无效，重置文件夹与名称自动填状态（design/02 §5 同规则）。 */
  private selectWorker(workerId: string) {
    if (workerId === this.selectedWorkerId) {
      return
    }
    clickHaptic()
    this.selectedWorkerId = workerId
    this.currentPath = ''
    this.dirEntries = []
    this.folderChosen = false
    this.workspaceName = ''
    this.nameAutoFilled = false
    this.loadDirectory('')
  }

  private async loadDirectory(path: string) {
    this.isLoadingDir = true
    try {
      const listing = await ApiService.listFiles(this.selectedWorkerId, '', path) as Record<string, Object>
      const rawEntries = listing['entries'] as Record<string, Object>[]
      const dirs: DirEntry[] = []
      if (rawEntries) {
        for (let i = 0; i < rawEntries.length; i++) {
          const item = rawEntries[i]
          if (!((item['isDirectory'] as boolean) ?? false)) {
            continue
          }
          const name = (item['name'] as string) ?? ''
          const entry = new DirEntry()
          entry.name = name
          entry.path = path.length === 0 ? name : `${path}/${name}`
          dirs.push(entry)
        }
      }
      dirs.sort((a: DirEntry, b: DirEntry): number => a.name.localeCompare(b.name))
      this.currentPath = path
      this.dirEntries = dirs
    } catch (e) {
      this.errorMessage = (e as Error).message
    } finally {
      this.isLoadingDir = false
    }
  }

  private enterDirectory(path: string) {
    clickHaptic()
    this.folderChosen = false
    this.loadDirectory(path)
  }

  /** 选中当前目录，名称默认取 basename（只在首次带入时自动填）。 */
  private chooseCurrentFolder() {
    clickHaptic()
    this.folderChosen = true
    if (this.workspaceName.trim().length === 0 || this.nameAutoFilled) {
      this.workspaceName = this.basename(this.currentPath)
      this.nameAutoFilled = true
    }
  }

  private basename(path: string): string {
    const segments = path.split('/').filter((s: string) => s.length > 0)
    return segments.length > 0 ? segments[segments.length - 1] : ''
  }

  private async submitCreate() {
    if (!this.canCreate()) {
      return
    }
    this.isCreating = true
    try {
      lightHaptic()
      const created = await ApiService.createWorkspace(
        this.selectedWorkerId, this.workspaceName.trim(), this.currentPath) as Record<string, Object>
      const workspaceId = (created['id'] as string) ?? ''
      showI18nToast('workspaces.create_success')
      if (this.onCreated) {
        this.onCreated(workspaceId, this.workspaceName.trim())
      }
    } catch (e) {
      showToast((e as Error).message || I18n.get('workspaces.create_failed'))
    } finally {
      this.isCreating = false
    }
  }
}
