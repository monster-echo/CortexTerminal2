import { WorkerInfo, WorkspaceInfo, SessionCreateRequest, ApiService, I18n, AnalyticsService, AnalyticsEvent, clickHaptic } from '@rwecho/core'
import { NewWorkspaceFlow } from './NewWorkspaceFlow'

/**
 * 新建会话 sheet（design/02 §5）：选 worker → 从该 worker 已有工作区选一个
 * （默认工作区排最前）→ 创建。会话必须归属工作区，没有「不放入工作区」；
 * 该 worker 无工作区时内嵌引导新建工作区（NewWorkspaceFlow）。
 */
@Component
export struct CreateSessionSheet {
  @State modalWorkers: WorkerInfo[] = []
  @State modalWorkspaces: WorkspaceInfo[] = []
  @State selectedWorkerId: string = ''
  @State selectedWorkspaceId: string = ''
  @State workspaceChosen: boolean = false
  @State isModalLoading: boolean = false
  @State errorMessage: string = ''
  @State isCreating: boolean = false
  // 'pick' = 选工作区；'newWorkspace' = 内嵌新建工作区流程。
  @State mode: string = 'pick'
  @Link @Watch('onSheetVisibilityChanged') showSheet: boolean
  onSessionCreated?: (sessionId: string, sessionName: string, workerId: string) => void

  // bindSheet 内容懒构建：首次打开时组件以 showSheet=true 初始化，@Watch 不会触发
  // （它只在值变化时回调），必须由 aboutToAppear 兜住首次加载。
  aboutToAppear(): void {
    if (this.showSheet) {
      this.loadData()
    }
  }

  onSheetVisibilityChanged() {
    if (this.showSheet) {
      this.mode = 'pick'
      this.loadData()
    }
  }

  /** 该 worker 下的工作区（默认工作区排最前）。 */
  private workerWorkspaces(): WorkspaceInfo[] {
    const matched = this.modalWorkspaces.filter((ws: WorkspaceInfo) =>
      ws.workerId === this.selectedWorkerId)
    return matched.sort((a: WorkspaceInfo, b: WorkspaceInfo): number => {
      if (a.isDefault !== b.isDefault) {
        return a.isDefault ? -1 : 1
      }
      return a.name.localeCompare(b.name)
    })
  }

  build() {
    Column() {
      if (this.mode === 'newWorkspace') {
        // 内嵌新建工作区：创建成功后回到选工作区并选中新建的那个。
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(16)
            .fontColor([$r('app.color.terminal_text')])
          Text(I18n.get('workspaces.back_to_pick'))
            .fontSize(14)
            .fontColor($r('app.color.terminal_text'))
        }
        .width('100%')
        .height(36)
        .onClick(() => {
          clickHaptic()
          this.mode = 'pick'
        })

        NewWorkspaceFlow({
          lockWorkerId: this.selectedWorkerId,
          onCreated: (workspaceId: string, _workspaceName: string) => {
            this.onWorkspaceCreated(workspaceId)
          }
        })
      } else {
        Text(I18n.get('session.create.title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_text'))
          .width('100%')
          .margin({ bottom: 16 })

        if (this.isModalLoading) {
          Column() {
            LoadingProgress().width(32).height(32).color($r('app.color.terminal_secondary'))
            Text(I18n.get('session.create.loading'))
              .fontSize(13)
              .fontColor($r('app.color.terminal_text_muted'))
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
              .fontColor($r('app.color.terminal_text_muted'))
              .margin({ top: 4 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 24 })
        } else if (this.modalWorkers.filter(w => w.isOnline).length === 0) {
          Column() {
            Text(I18n.get('session.create.empty'))
              .fontSize(15)
              .fontColor($r('app.color.terminal_text_muted'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 24 })
        } else {
          this.PickerContent()
        }
      }
    }
    .padding({ left: 20, right: 20, top: 16, bottom: 20 })
    .width('100%')
  }

  @Builder
  PickerContent() {
    Column() {
      Text(I18n.get('session.create.pick_worker'))
        .fontSize(14)
        .fontColor($r('app.color.terminal_text_muted'))
        .width('100%')
        .margin({ bottom: 8 })

      List() {
        ForEach(this.modalWorkers, (worker: WorkerInfo) => {
          ListItem() {
            Row() {
              Circle().width(10).height(10)
                .fill(worker.isOnline ? $r('app.color.terminal_success') : $r('app.color.terminal_status_idle'))
                .margin({ right: 12 })

              Column() {
                Text(worker.name || worker.hostname || 'Unknown')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.terminal_text'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(worker.os || worker.operatingSystem || '')
                  .fontSize(12)
                  .fontColor($r('app.color.terminal_text_muted'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (this.selectedWorkerId === worker.id) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(16)
                  .fontColor([$r('app.color.terminal_text')])
              }
            }
            .width('100%')
            .height(56)
            .padding({ left: 12, right: 12 })
            .borderRadius(10)
            .backgroundColor(this.selectedWorkerId === worker.id
              ? $r('app.color.terminal_secondary_container')
              : $r('app.color.terminal_background_element'))
            // 离线 worker 置灰且不可选（无法启动会话）。
            .opacity(worker.isOnline ? 1 : 0.4)
            .enabled(worker.isOnline)
            .onClick(() => { this.selectWorker(worker.id) })
          }
        }, (worker: WorkerInfo) => worker.id)
      }
      .width('100%')
      .scrollBar(BarState.Off)

      Text(I18n.get('session.create.pick_workspace'))
        .fontSize(14)
        .fontColor($r('app.color.terminal_text_muted'))
        .width('100%')
        .margin({ top: 16, bottom: 8 })

      if (this.selectedWorkerId.length === 0) {
        Text(I18n.get('session.create.worker_empty_hint'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_text_tertiary'))
          .width('100%')
      } else if (this.workerWorkspaces().length === 0) {
        // 会话必须归属工作区（design/00）：该电脑没有工作区时引导新建。
        Column() {
          Text(I18n.get('workspaces.empty_for_worker'))
            .fontSize(13)
            .fontColor($r('app.color.terminal_text_muted'))
            .width('100%')

          Button(I18n.get('workspaces.create'))
            .width('100%')
            .height(40)
            .borderRadius(8)
            .backgroundColor($r('app.color.terminal_secondary_container'))
            .fontColor($r('app.color.terminal_on_secondary_container'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 12 })
            .onClick(() => {
              clickHaptic()
              this.mode = 'newWorkspace'
            })
        }
        .width('100%')
      } else {
        List() {
          ForEach(this.workerWorkspaces(), (ws: WorkspaceInfo) => {
            ListItem() {
              Row() {
                SymbolGlyph($r('sys.symbol.folder_fill'))
                  .fontSize(18)
                  .fontColor([$r('app.color.terminal_secondary')])

                Column() {
                  Text(ws.name)
                    .fontSize(15)
                    .fontColor($r('app.color.terminal_text'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (ws.rootPath.length > 0) {
                    Text(ws.rootPath)
                      .fontSize(12)
                      .fontColor($r('app.color.terminal_text_muted'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 2 })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 10 })

                if (this.workspaceChosen && this.selectedWorkspaceId === ws.id) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(16)
                    .fontColor([$r('app.color.terminal_text')])
                }
              }
              .width('100%')
              .height(52)
              .padding({ left: 12, right: 12 })
              .borderRadius(10)
              .backgroundColor(this.workspaceChosen && this.selectedWorkspaceId === ws.id
                ? $r('app.color.terminal_secondary_container')
                : $r('app.color.terminal_background_element'))
              .onClick(() => {
                this.selectedWorkspaceId = ws.id
                this.workspaceChosen = true
              })
            }
          }, (ws: WorkspaceInfo) => ws.id)
        }
        .width('100%')
        .scrollBar(BarState.Off)
      }

      // 主操作：黑白反色胶囊（对齐设计规范主按钮）。
      Button(I18n.get('common.confirm'))
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor($r('app.color.terminal_inverse_surface'))
        .fontColor($r('app.color.terminal_inverse_on_surface'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 20 })
        .enabled(!this.isCreating && this.workspaceChosen)
        .opacity(!this.isCreating && this.workspaceChosen ? 1 : 0.5)
        .onClick(() => {
          this.createSession(this.selectedWorkerId, this.selectedWorkspaceId)
        })
    }
    .width('100%')
  }

  /** 内嵌新建工作区成功：刷新列表、选中新工作区、回到选工作区。 */
  private async onWorkspaceCreated(workspaceId: string) {
    this.mode = 'pick'
    await this.loadData()
    this.selectedWorkspaceId = workspaceId
    this.workspaceChosen = true
  }

  private async loadData() {
    this.isModalLoading = true
    this.errorMessage = ''
    try {
      this.modalWorkers = await ApiService.listWorkers()
      this.modalWorkspaces = await ApiService.listWorkspaceInfos()
    } catch (e) {
      this.errorMessage = (e as Error).message
    } finally {
      this.isModalLoading = false
    }
  }

  /** 换 worker 后重置工作区选择并落到该 worker 的默认工作区。 */
  private selectWorker(workerId: string) {
    this.selectedWorkerId = workerId
    this.workspaceChosen = false
    this.selectedWorkspaceId = ''
    const matched = this.modalWorkspaces.filter((ws: WorkspaceInfo) => ws.workerId === workerId)
    for (let i = 0; i < matched.length; i++) {
      if (matched[i].isDefault) {
        this.selectedWorkspaceId = matched[i].id
        this.workspaceChosen = true
        return
      }
    }
    if (matched.length > 0) {
      this.selectedWorkspaceId = matched[0].id
      this.workspaceChosen = true
    }
  }

  private async createSession(workerId: string, workspaceId: string) {
    if (this.isCreating) {
      return
    }
    this.isCreating = true
    try {
      const request = new SessionCreateRequest()
      request.workerId = workerId
      request.workspaceId = workspaceId
      const session = await ApiService.createSession(request)
      AnalyticsService.onEvent(AnalyticsEvent.SESSION_CREATE)
      if (this.onSessionCreated) {
        this.onSessionCreated(session.id, session.name, session.workerId)
      }
    } catch (e) {
      this.errorMessage = (e as Error).message
    } finally {
      this.isCreating = false
    }
  }
}
