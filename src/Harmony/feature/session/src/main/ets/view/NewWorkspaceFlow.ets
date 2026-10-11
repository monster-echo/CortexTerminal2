import { common } from '@kit.AbilityKit'
import { PreferencesUtil, AuthState, ApiService, I18n, WorkerInfo, showI18nToast, showToast, lightHaptic, clickHaptic } from '@rwecho/core'

export class WorkspaceDirectoryEntry {
  name: string = ''
  path: string = ''
}

@Component
export struct NewWorkspaceFlow {
  lockWorkerId: string = ''
  onCreated?: (workspaceId: string, workspaceName: string) => void
  onCancelled?: (() => void) | null = null

  @State workers: WorkerInfo[] = []
  @State selectedWorkerId: string = ''
  @State currentPath: string = ''
  @State folderChosen: boolean = false
  @State workspaceName: string = ''
  @State selectedWorkerName: string = ''
  @State nameAutoFilled: boolean = false
  @State isLoading: boolean = false
  @State isCreating: boolean = false
  @State errorMessage: string = ''
  @State pickerMode: string = ''
  @State showPicker: boolean = false
  private directoryRequest: number = 0
  @State pickerDirectoryEntries: WorkspaceDirectoryEntry[] = []
  @State pickerDirectoryPath: string = ''
  @State pickerDirectoryLoading: boolean = false
  @State pickerDirectoryError: string = ''
  @StorageLink('topSafeArea') topSafeArea: number = 0
  @StorageLink('bottomSafeArea') bottomSafeArea: number = 0

  aboutToAppear(): void {
    if (this.lockWorkerId.length > 0) this.selectedWorkerId = this.lockWorkerId
    this.loadWorkers()
  }

  private selectedWorker(): WorkerInfo | null {
    for (let i = 0; i < this.workers.length; i++) {
      if (this.workers[i].id === this.selectedWorkerId || this.workers[i].workerId === this.selectedWorkerId) return this.workers[i]
    }
    return null
  }

  private canCreate(): boolean {
    return this.selectedWorkerId.length > 0 && this.folderChosen && this.workspaceName.trim().length > 0 && this.selectedWorker()?.isOnline === true && !this.isCreating
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
      Text(I18n.get('workspaces.create'))
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.terminal_text'))
        .width('100%').padding({ top: 4, bottom: 16 })

      if (this.isLoading) {
        Column() { LoadingProgress().width(32).height(32).color($r('app.color.terminal_secondary')) }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.errorMessage.length > 0) {
        Column({ space: 12 }) {
          Text(this.errorMessage).fontSize(13).fontColor($r('app.color.terminal_error')).textAlign(TextAlign.Center).width('100%')
          Button(I18n.get('common.retry')).height(40).borderRadius(10)
            .backgroundColor($r('app.color.terminal_secondary_container'))
            .fontColor($r('app.color.terminal_on_secondary_container')).fontSize(14)
            .onClick(() => { clickHaptic(); this.loadWorkers() })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 12 }) {
            if (this.lockWorkerId.length === 0) {
              this.SelectionRow(I18n.get('workspaces.pick_worker'), 'worker', $r('sys.symbol.computer'), () => {
                clickHaptic()
                this.pickerMode = 'worker'
                this.showPicker = true
              })
            } else {
              this.SelectionRow(I18n.get('workspaces.pick_worker'), 'worker', $r('sys.symbol.computer'), () => {})
            }
            this.SelectionRow(I18n.get('workspaces.pick_folder'), 'folder', $r('sys.symbol.folder'), () => {
              if (this.selectedWorkerId.length === 0) return
              clickHaptic()
              this.pickerMode = 'folder'
              this.showPicker = true
              this.pickerDirectoryPath = this.currentPath
              this.loadPickerDirectory(this.currentPath)
            })

            Column({ space: 8 }) {
              Text(I18n.get('workspaces.name')).fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.terminal_text_muted'))
              TextInput({ text: this.workspaceName, placeholder: I18n.get('workspaces.name') })
                .height(48).padding({ left: 14, right: 14 }).borderRadius(12)
                .backgroundColor($r('app.color.terminal_background_element'))
                .fontColor($r('app.color.terminal_text')).placeholderColor($r('app.color.terminal_text_muted'))
                .fontSize(15)
                .onChange((value: string) => { this.workspaceName = value; this.nameAutoFilled = false })
            }.width('100%').alignItems(HorizontalAlign.Start).margin({ top: 4 })
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.TopStart)

        Button(this.isCreating ? I18n.get('common.loading') : I18n.get('workspaces.create'))
          .width('100%').height(50).borderRadius(14)
          .backgroundColor($r('app.color.terminal_inverse_surface'))
          .fontColor($r('app.color.terminal_inverse_on_surface')).fontSize(16).fontWeight(FontWeight.Medium)
          .margin({ top: 12, bottom: 4 }).enabled(this.canCreate()).opacity(this.canCreate() ? 1 : 0.48)
          .onClick(() => { this.submitCreate() })
      }
      }.width('100%').height('100%').padding(20).alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start).align(Alignment.TopStart)

    }.width('100%').height('100%').backgroundColor(Color.Transparent)
      .bindContentCover($$this.showPicker, this.PickerPage(), {
        modalTransition: ModalTransition.DEFAULT,
        onDisappear: () => { this.pickerMode = ''; this.directoryRequest++ }
      })
  }

  @Builder
  PickerPage() {
    Column() {
    if (this.pickerMode === 'worker') {
      WorkspaceWorkerPickerPage({
        workers: $workers, isLoading: $isLoading, errorMessage: $errorMessage,
        onRetry: () => { this.loadWorkers() },
        onCancel: () => { this.closePicker() },
        onSelect: (worker: WorkerInfo) => { this.applySelectedWorker(worker) }
      })
    } else {
      WorkspaceFolderPickerPage({
        workerId: this.selectedWorkerId, currentPath: $pickerDirectoryPath,
        dirEntries: $pickerDirectoryEntries, isLoading: $pickerDirectoryLoading,
        errorMessage: $pickerDirectoryError,
        onNavigate: (path: string) => { this.loadPickerDirectory(path) },
        onRetry: () => { this.loadPickerDirectory(this.pickerDirectoryPath) },
        onCancel: () => { this.closePicker() },
        onSelect: (path: string) => { this.applySelectedFolder(path) }
      })
    }
    }.width('100%').height('100%')
  }

  private closePicker() { this.showPicker = false }

  private applySelectedWorker(worker: WorkerInfo) {
    clickHaptic()
    if (this.selectedWorkerId === worker.id) { this.rememberWorker(); this.closePicker(); return }
    this.selectedWorkerId = worker.id
    this.selectedWorkerName = worker.name || worker.hostname || worker.id
    this.currentPath = ''
    this.folderChosen = false
    this.workspaceName = ''
    this.nameAutoFilled = false
    this.rememberWorker()
    this.restoreFolder()
    this.closePicker()
  }

  private applySelectedFolder(path: string) {
    clickHaptic()
    this.currentPath = path
    this.folderChosen = true
    if (this.workspaceName.trim().length === 0 || this.nameAutoFilled) {
      this.workspaceName = this.basename(path)
      this.nameAutoFilled = true
    }
    this.rememberWorker()
    PreferencesUtil.setString(this.getUIContext().getHostContext() as common.UIAbilityContext, this.memoryKey(this.selectedWorkerId), path)
    this.closePicker()
  }

  private async loadPickerDirectory(path: string) {
    const request = ++this.directoryRequest
    this.pickerDirectoryPath = path
    this.pickerDirectoryEntries = []
    this.pickerDirectoryLoading = true
    this.pickerDirectoryError = ''
    try {
      // Resolve the selected home-relative directory as the browsing root. Older Workers
      // neither expand '~' consistently nor allow a relative path through an external symlink.
      const listing = await ApiService.listFiles(this.selectedWorkerId, path.length === 0 ? '.' : `./${path}`, '') as Record<string, Object>
      if (request !== this.directoryRequest) return
      const rawEntries = listing['entries'] as Record<string, Object>[]
      const dirs: WorkspaceDirectoryEntry[] = []
      if (rawEntries) {
        for (let i = 0; i < rawEntries.length; i++) {
          const item = rawEntries[i]
          if (!((item['isDirectory'] as boolean) ?? false)) continue
          const entry = new WorkspaceDirectoryEntry()
          entry.name = (item['name'] as string) ?? ''
          entry.path = path.length === 0 ? entry.name : `${path}/${entry.name}`
          dirs.push(entry)
        }
      }
      dirs.sort((a: WorkspaceDirectoryEntry, b: WorkspaceDirectoryEntry): number => a.name.localeCompare(b.name))
      this.pickerDirectoryPath = path
      this.pickerDirectoryEntries = dirs
    } catch (e) {
      if (request === this.directoryRequest) this.pickerDirectoryError = (e as Error).message
    } finally {
      if (request === this.directoryRequest) this.pickerDirectoryLoading = false
    }
  }

  @Builder
  SelectionRow(title: string, field: string, icon: Resource, onTap: () => void) {
    Column({ space: 8 }) {
      Text(title).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.terminal_text_muted'))
      Row({ space: 12 }) {
        SymbolGlyph(icon).fontSize(19).fontColor([$r('app.color.terminal_secondary')])
        Text(field === 'worker' ? this.workerSummary() : this.folderSummary())
          .fontSize(15).fontColor($r('app.color.terminal_text')).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([$r('app.color.terminal_text_muted')])
      }.width('100%').height(56).padding({ left: 14, right: 14 }).borderRadius(12)
        .backgroundColor($r('app.color.terminal_background_element')).onClick(onTap)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private workerSummary(): string {
    const worker = this.selectedWorker()
    if (worker !== null) return worker.name || worker.hostname || worker.id
    return this.selectedWorkerName.length > 0 ? this.selectedWorkerName : I18n.get('workspaces.choose_worker')
  }

  private folderSummary(): string {
    if (this.selectedWorkerId.length === 0) return I18n.get('workspaces.folder_pick_worker_hint')
    return this.folderChosen ? this.currentDisplayPath() : I18n.get('workspaces.choose_folder')
  }

  private currentDisplayPath(): string {
    return this.currentPath.length === 0 ? I18n.get('files.home') : `~/${this.currentPath}`
  }

  private async loadWorkers() {
    this.isLoading = true
    this.errorMessage = ''
    try {
      this.workers = await ApiService.listWorkers()
      if (this.selectedWorkerId.length === 0) {
        const savedWorker = PreferencesUtil.getString(this.getUIContext().getHostContext() as common.UIAbilityContext, this.memoryKey('worker'))
        const available = this.workers.find((worker: WorkerInfo) => worker.id === savedWorker && worker.isOnline)
        if (available) this.selectedWorkerId = available.id
      }
      if (this.selectedWorkerId.length > 0 && !this.folderChosen) this.restoreFolder()
    } catch (e) {
      this.errorMessage = (e as Error).message
    } finally {
      this.isLoading = false
    }
  }

  private memoryKey(workerId: string): string {
    const gateway = AppStorage.get<string>('gatewayUrl') || ''
    return `workspace_creation_${encodeURIComponent(gateway)}_${encodeURIComponent(AuthState.getDisplayName())}_${workerId}`
  }

  private rememberWorker(): void {
    PreferencesUtil.setString(this.getUIContext().getHostContext() as common.UIAbilityContext, this.memoryKey('worker'), this.selectedWorkerId)
  }

  private restoreFolder(): void {
    const saved = PreferencesUtil.getString(this.getUIContext().getHostContext() as common.UIAbilityContext, this.memoryKey(this.selectedWorkerId), '__unset__')
    if (saved === '__unset__') return
    this.currentPath = saved
    this.folderChosen = true
    this.workspaceName = this.basename(saved)
    this.nameAutoFilled = true
  }

  private basename(path: string): string {
    const segments = path.split('/').filter((s: string) => s.length > 0)
    return segments.length > 0 ? segments[segments.length - 1] : I18n.get('files.home')
  }

  private async submitCreate() {
    if (!this.canCreate()) return
    this.isCreating = true
    try {
      lightHaptic()
      const rootPath = this.currentPath.length === 0 ? '.' : `./${this.currentPath}`
      const created = await ApiService.createWorkspace(this.selectedWorkerId, this.workspaceName.trim(), rootPath) as Record<string, Object>
      const workspaceId = (created['id'] as string) ?? ''
      showI18nToast('workspaces.create_success')
      if (this.onCreated) this.onCreated(workspaceId, this.workspaceName.trim())
    } catch (e) {
      showToast((e as Error).message || I18n.get('workspaces.create_failed'))
    } finally {
      this.isCreating = false
    }
  }
}

@Component
export struct WorkspaceWorkerPickerPage {
  @Link workers: WorkerInfo[]
  @Link isLoading: boolean
  @Link errorMessage: string
  @StorageLink('topSafeArea') topSafeArea: number = 0
  @StorageLink('bottomSafeArea') bottomSafeArea: number = 0
  onSelect?: (worker: WorkerInfo) => void
  onCancel?: () => void
  onRetry?: () => void

  build() {
    Column() {
      Column() {
        Row({ space: 8 }) {
          Button() { SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([$r('app.color.terminal_text')]) }
            .width(44).height(44).padding(0).borderRadius(22).backgroundColor(Color.Transparent)
            .accessibilityText(I18n.get('common.back'))
            .onClick(() => { if (this.onCancel) this.onCancel() })
          Text(I18n.get('workspaces.worker_picker_title')).fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_text')).layoutWeight(1)
        }.width('100%').height(52).margin({ bottom: 10 })
        if (this.isLoading) {
          Column() { LoadingProgress().width(32).height(32).color($r('app.color.terminal_secondary')) }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.errorMessage.length > 0) {
          Column({ space: 12 }) {
            Text(this.errorMessage).fontSize(13).fontColor($r('app.color.terminal_error')).textAlign(TextAlign.Center)
            Button(I18n.get('common.retry')).onClick(() => { if (this.onRetry) this.onRetry() })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.workers.length === 0) {
          Text(I18n.get('workspaces.no_computers')).fontSize(14).fontColor($r('app.color.terminal_text_muted'))
            .width('100%').layoutWeight(1).textAlign(TextAlign.Center)
        } else {
          Scroll() {
            Column({ space: 8 }) {
            ForEach(this.workers, (worker: WorkerInfo) => {
              Column() {
                Row({ space: 12 }) {
                  SymbolGlyph($r('sys.symbol.computer')).fontSize(20).fontColor([$r('app.color.terminal_secondary')])
                  Column({ space: 4 }) {
                    Text(worker.name || worker.hostname || worker.id).fontSize(15).fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.terminal_text')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Row({ space: 6 }) {
                      Circle().width(7).height(7).fill(worker.isOnline ? $r('app.color.terminal_success') : $r('app.color.terminal_status_idle'))
                      Text(worker.isOnline ? I18n.get('workspaces.worker_online') : I18n.get('workspaces.worker_offline'))
                        .fontSize(12).fontColor($r('app.color.terminal_text_muted'))
                    }
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  if (!worker.isOnline) {
                    Text(I18n.get('workspaces.worker_offline')).fontSize(11).fontColor($r('app.color.terminal_text_muted'))
                  } else {
                    SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([$r('app.color.terminal_text_muted')])
                  }
                }.width('100%').height(68).padding({ left: 15, right: 15 }).borderRadius(14)
                  .backgroundColor($r('app.color.terminal_background_element'))
                  .opacity(worker.isOnline ? 1 : 0.48)
              }.enabled(worker.isOnline)
                .onClick(() => { if (worker.isOnline) this.selectWorker(worker.id) })
            }, (worker: WorkerInfo) => worker.id)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
        }
      }.width('100%').layoutWeight(1).padding({ left: 20, right: 20, top: this.topSafeArea + 8, bottom: this.bottomSafeArea + 12 }).justifyContent(FlexAlign.Start)
    }.width('100%').height('100%').backgroundColor($r('app.color.terminal_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private selectWorker(workerId: string) {
    clickHaptic()
    for (let i = 0; i < this.workers.length; i++) {
      if (this.workers[i].id === workerId) {
        if (this.onSelect) this.onSelect(this.workers[i])
        return
      }
    }
  }
}

@Component
export struct WorkspaceFolderPickerPage {
  @State filterQuery: string = ''
  @Prop workerId: string = ''
  @Link dirEntries: WorkspaceDirectoryEntry[]
  @Link currentPath: string
  @Link isLoading: boolean
  @Link errorMessage: string
  @StorageLink('topSafeArea') topSafeArea: number = 0
  @StorageLink('bottomSafeArea') bottomSafeArea: number = 0
  onSelect?: (path: string) => void
  onCancel?: () => void
  onNavigate?: (path: string) => void
  onRetry?: () => void

  build() {
    Column() {
      Column() {
        Row({ space: 8 }) {
          Button() { SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([$r('app.color.terminal_text')]) }
            .width(44).height(44).padding(0).borderRadius(22).backgroundColor(Color.Transparent)
            .accessibilityText(I18n.get('common.back'))
            .onClick(() => { if (this.onCancel) this.onCancel() })
          Text(I18n.get('workspaces.folder_picker_title')).fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_text')).layoutWeight(1)
        }.width('100%').height(52).margin({ bottom: 6 })

        Search({ value: this.filterQuery, placeholder: I18n.get('workspaces.folder_filter') })
          .height(44).fontColor($r('app.color.terminal_text'))
          .placeholderColor($r('app.color.terminal_text_muted'))
          .backgroundColor($r('app.color.terminal_background_element'))
          .onChange((value: string) => { this.filterQuery = value })
          .margin({ bottom: 8 })

        Scroll() {
          Row({ space: 4 }) {
            Button(I18n.get('files.home'))
              .fontSize(13).fontColor($r('app.color.terminal_secondary'))
              .backgroundColor(Color.Transparent).height(40).padding({ left: 8, right: 8 })
              .onClick(() => { this.navigateTo('') })
            ForEach(this.pathSegments(), (segment: string, index: number) => {
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(10).fontColor([$r('app.color.terminal_text_muted')])
              Button(segment).fontSize(13)
                .fontColor(index === this.pathSegments().length - 1 ? $r('app.color.terminal_text') : $r('app.color.terminal_secondary'))
                .backgroundColor(Color.Transparent).height(40).padding({ left: 8, right: 8 })
                .onClick(() => { this.navigateTo(this.pathSegments().slice(0, index + 1).join('/')) })
            }, (segment: string, index: number) => `${index}:${segment}`)
          }.alignItems(VerticalAlign.Center)
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          .align(Alignment.Start).margin({ bottom: 8 })

        if (this.currentPath.length > 0) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(16).fontColor([$r('app.color.terminal_secondary')])
            Text(I18n.get('workspaces.folder_parent')).fontSize(14).fontColor($r('app.color.terminal_secondary'))
          }.width('100%').height(44).padding({ left: 12 })
            .margin({ bottom: 8 }).onClick(() => { this.goParent() })
        }
        if (this.isLoading) {
          Column() { LoadingProgress().width(30).height(30).color($r('app.color.terminal_secondary')) }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.errorMessage.length > 0) {
          Column({ space: 12 }) {
            Text(this.errorMessage).fontSize(13).fontColor($r('app.color.terminal_error')).textAlign(TextAlign.Center)
            Button(I18n.get('common.retry')).onClick(() => { if (this.onRetry) this.onRetry() })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.filteredEntries().length === 0) {
          Column() {
            SymbolGlyph($r('sys.symbol.folder')).fontSize(30).fontColor([$r('app.color.terminal_text_muted')])
            Text(I18n.get(this.filterQuery.trim().length > 0 ? 'workspaces.folder_no_matches' : 'workspaces.folder_empty')).fontSize(14).fontColor($r('app.color.terminal_text_muted')).margin({ top: 10 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 6 }) {
            ForEach(this.filteredEntries(), (entry: WorkspaceDirectoryEntry) => {
              Column() {
                Row({ space: 11 }) {
                  SymbolGlyph($r('sys.symbol.folder_fill')).fontSize(18).fontColor([$r('app.color.terminal_secondary')])
                  Text(entry.name).fontSize(14).fontColor($r('app.color.terminal_text')).layoutWeight(1)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([$r('app.color.terminal_text_muted')])
                }.width('100%').height(58).padding({ left: 14, right: 14 }).borderRadius(12)
                  .backgroundColor($r('app.color.terminal_background_element')).onClick(() => { this.navigateTo(entry.path) })
              }
            }, (entry: WorkspaceDirectoryEntry) => entry.path)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
        }

        Button(I18n.get('workspaces.folder_current'))
          .width('100%').height(50).borderRadius(14)
          .backgroundColor($r('app.color.terminal_inverse_surface'))
          .fontColor($r('app.color.terminal_inverse_on_surface')).fontSize(15).fontWeight(FontWeight.Medium)
          .margin({ top: 12, bottom: 4 }).enabled(!this.isLoading && this.errorMessage.length === 0)
          .onClick(() => { this.chooseCurrentFolder() })
      }.width('100%').layoutWeight(1).padding({ left: 20, right: 20, top: this.topSafeArea + 8, bottom: this.bottomSafeArea + 12 }).justifyContent(FlexAlign.Start)
    }.width('100%').height('100%').backgroundColor($r('app.color.terminal_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private pathSegments(): string[] {
    return this.currentPath.split('/').filter((part: string) => part.length > 0)
  }

  private filteredEntries(): WorkspaceDirectoryEntry[] {
    const query = this.filterQuery.trim().toLocaleLowerCase()
    return query.length === 0 ? this.dirEntries : this.dirEntries.filter((entry: WorkspaceDirectoryEntry) => entry.name.toLocaleLowerCase().includes(query))
  }

  private navigateTo(path: string): void {
    this.filterQuery = ''
    this.getUIContext().getFocusController().clearFocus()
    if (this.onNavigate) this.onNavigate(path)
  }

  private goParent() {
    const parts = this.currentPath.split('/').filter((part: string) => part.length > 0)
    parts.pop()
    this.navigateTo(parts.join('/'))
  }

  private chooseCurrentFolder() {
    clickHaptic()
    if (this.onSelect) this.onSelect(this.currentPath)
  }
}
