/**
 * @file TunnelPanel.ets
 * @brief Port forwarding bindSheet panel, workspace-scoped.
 *
 * 面板从所在会话解析出 workspaceId，再走 workspace 级 tunnels API
 * （GET/POST /api/me/workspaces/{id}/tunnels、DELETE /api/me/tunnels/{id}）。
 * 创建表单支持 name（可选）/localPort/remoteAddress（可选）/remotePort。
 * Failures surface in the in-panel error banner, never silently.
 */
import { pasteboard } from '@kit.BasicServicesKit'
import { I18n, ApiService, RouteName, TunnelInfo, showToast, clickHaptic, TerminalChrome } from '@rwecho/core'

@Component
export struct TunnelPanel {
  sessionId: string = ''
  @State workspaceId: string = ''
  @State tunnels: TunnelInfo[] = []
  @State nameInput: string = ''
  @State localPortInput: string = ''
  @State remotePortInput: string = ''
  @State remoteAddressInput: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('terminalChromeJson') chromeJson: string = ''

  private chrome(): TerminalChrome {
    return TerminalChrome.fromJson(this.chromeJson)
  }

  aboutToAppear() {
    this.initWorkspace()
  }

  /** 会话已绑定 workspace：解析 workspaceId 后加载该工作区的转发规则。 */
  private async initWorkspace(): Promise<void> {
    this.isLoading = true
    this.errorMessage = ''
    try {
      const session = await ApiService.getSession(this.sessionId)
      this.workspaceId = session.workspaceId
      if (this.workspaceId.length === 0) {
        this.errorMessage = I18n.get('tunnel.no_workspace')
        this.isLoading = false
        return
      }
      await this.loadTunnels()
    } catch (e) {
      this.errorMessage = (e as Error).message || I18n.get('common.error')
      this.isLoading = false
    }
  }

  async loadTunnels(): Promise<void> {
    this.isLoading = true
    this.errorMessage = ''
    try {
      this.tunnels = await ApiService.listWorkspaceTunnels(this.workspaceId)
    } catch (e) {
      this.errorMessage = (e as Error).message || I18n.get('common.error')
    } finally {
      this.isLoading = false
    }
  }

  private static parsePort(text: string): number {
    const port = parseInt(text.trim(), 10)
    return Number.isNaN(port) || port < 1 || port > 65535 ? 0 : port
  }

  async createTunnel(): Promise<void> {
    const localPort = TunnelPanel.parsePort(this.localPortInput)
    const remotePort = TunnelPanel.parsePort(this.remotePortInput)
    if (localPort === 0 || remotePort === 0) {
      this.errorMessage = I18n.get('tunnel.port_invalid')
      return
    }
    this.isLoading = true
    this.errorMessage = ''
    try {
      await ApiService.createWorkspaceTunnel(
        this.workspaceId, this.nameInput.trim(), localPort, this.remoteAddressInput.trim(), remotePort)
      this.nameInput = ''
      this.localPortInput = ''
      this.remotePortInput = ''
      this.remoteAddressInput = ''
      showToast(I18n.get('tunnel.created'))
      await this.loadTunnels()
    } catch (e) {
      this.errorMessage = (e as Error).message || I18n.get('common.error')
    } finally {
      this.isLoading = false
    }
  }

  copyLink(url: string): void {
    const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url)
    const systemPasteboard = pasteboard.getSystemPasteboard()
    systemPasteboard.setData(pasteboardData)
    showToast(I18n.get('tunnel.copied'))
  }

  preview(url: string): void {
    const param: Record<string, string> = { 'url': url, 'title': I18n.get('tunnel.title') }
    this.pageStack.pushPath({ name: RouteName.WEB_PAGE, param: param })
  }

  confirmRevoke(t: TunnelInfo): void {
    this.getUIContext()?.showAlertDialog({
      title: I18n.get('tunnel.revoke_confirm_title'),
      message: I18n.get('tunnel.revoke_confirm_message'),
      primaryButton: {
        value: I18n.get('common.cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: I18n.get('tunnel.revoke'),
        fontColor: $r('app.color.terminal_error'),
        action: () => { this.revokeTunnel(t) }
      }
    })
  }

  private async revokeTunnel(t: TunnelInfo): Promise<void> {
    this.errorMessage = ''
    try {
      await ApiService.revokeTunnel(t.tunnelId)
      await this.loadTunnels()
    } catch (e) {
      this.errorMessage = (e as Error).message || I18n.get('common.error')
    }
  }

  private localTime(utc: string): string {
    if (utc.length === 0) {
      return ''
    }
    return new Date(utc).toLocaleString()
  }

  build() {
    Column() {
      this.TitleBar()
      this.CreateBar()
      if (this.errorMessage.length > 0) {
        this.ErrorBanner()
      }
      if (this.isLoading) {
        this.LoadingState()
      } else if (this.tunnels.length === 0 && this.errorMessage.length === 0) {
        this.EmptyState()
      } else {
        List({ space: 8 }) {
          ForEach(this.tunnels, (t: TunnelInfo) => {
            ListItem() {
              this.TunnelCard(t)
            }
            .swipeAction({
              end: {
                onAction: () => {
                  clickHaptic()
                  this.confirmRevoke(t)
                },
                // 左滑露出的删除区域：红色块 + 删除图标
                builder: () => {
                  this.RevokeAction()
                }
              }
            })
          }, (t: TunnelInfo) => t.tunnelId)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 4, bottom: 24 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.chrome().background)
  }

  @Builder
  RevokeAction() {
    Row() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(22)
        .fontColor([$r('app.color.terminal_on_primary')])
    }
    .width(64)
    .height('100%')
    .borderRadius(10)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.terminal_error'))
  }

  @Builder
  TitleBar() {
    Row() {
      Text(I18n.get('tunnel.title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.chrome().onSurface)
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
  CreateBar() {
    Column({ space: 8 }) {
      TextInput({
        text: $$this.nameInput,
        placeholder: I18n.get('tunnel.name_placeholder')
      })
        .height(48)
        .borderRadius(8)
        .backgroundColor(this.chrome().surfaceHigh)
        .fontColor(this.chrome().onSurface)
        .placeholderColor(this.chrome().onSurfaceVariant)
        .fontSize(16)

      Row({ space: 8 }) {
        TextInput({
          text: $$this.localPortInput,
          placeholder: I18n.get('tunnel.local_port')
        })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(48)
          .borderRadius(8)
          .backgroundColor(this.chrome().surfaceHigh)
          .fontColor(this.chrome().accent)
          .placeholderColor(this.chrome().onSurfaceVariant)
          .fontSize(16)

        TextInput({
          text: $$this.remotePortInput,
          placeholder: I18n.get('tunnel.remote_port')
        })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(48)
          .borderRadius(8)
          .backgroundColor(this.chrome().surfaceHigh)
          .fontColor(this.chrome().accent)
          .placeholderColor(this.chrome().onSurfaceVariant)
          .fontSize(16)
      }
      .width('100%')

      TextInput({
        text: $$this.remoteAddressInput,
        placeholder: I18n.get('tunnel.remote_address')
      })
        .height(48)
        .borderRadius(8)
        .backgroundColor(this.chrome().surfaceHigh)
        .fontColor(this.chrome().onSurface)
        .placeholderColor(this.chrome().onSurfaceVariant)
        .fontSize(16)

      Button(I18n.get('tunnel.create'))
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor(this.chrome().accentContainer)
        .fontColor(this.chrome().onAccentContainer)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .enabled(!this.isLoading && this.workspaceId.length > 0)
        .onClick(() => {
          clickHaptic()
          this.createTunnel()
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 12 })
  }

  @Builder
  ErrorBanner() {
    Row() {
      Text(this.errorMessage)
        .fontSize(14)
        .fontColor($r('app.color.terminal_error'))
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Button(I18n.get('common.retry'))
        .fontSize(13)
        .fontColor(this.chrome().onAccentContainer)
        .backgroundColor(this.chrome().accentContainer)
        .borderRadius(8)
        .height(32)
        .onClick(() => {
          clickHaptic()
          if (this.workspaceId.length === 0) {
            this.initWorkspace()
          } else {
            this.loadTunnels()
          }
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.chrome().surface)
    .margin({ left: 16, right: 16, bottom: 8 })
  }

  @Builder
  LoadingState() {
    Column() {
      LoadingProgress()
        .width(32)
        .height(32)
        .color(this.chrome().accent)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  EmptyState() {
    Column() {
      SymbolGlyph($r('sys.symbol.link'))
        .fontSize(40)
        .fontColor([this.chrome().outlineVariant])
        .margin({ bottom: 16 })
      Text(I18n.get('tunnel.empty'))
        .fontSize(13)
        .fontColor(this.chrome().onSurfaceVariant)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 32, right: 32 })
  }

  @Builder
  TunnelCard(t: TunnelInfo) {
    Column() {
      Row() {
        Text(t.name.length > 0 ? t.name : `${t.localPort > 0 ? t.localPort : t.port} → ${t.remotePort}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.chrome().accent)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.localTime(t.expiresAtUtc))
          .fontSize(12)
          .fontColor(this.chrome().onSurfaceVariant)
          .margin({ left: 10 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(`${t.localPort > 0 ? t.localPort : t.port} → ${t.remoteAddress}:${t.remotePort}`)
        .fontSize(12)
        .fontColor(this.chrome().onSurfaceVariant)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })

      Text(t.url)
        .fontSize(12)
        .fontColor(this.chrome().accent)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })

      Row({ space: 8 }) {
        Button(I18n.get('tunnel.copy_link'))
          .layoutWeight(1)
          .height(32)
          .borderRadius(8)
          .backgroundColor(this.chrome().accentContainer)
          .fontColor(this.chrome().onAccentContainer)
          .fontSize(13)
          .onClick(() => {
            clickHaptic()
            this.copyLink(t.url)
          })
        Button(I18n.get('tunnel.preview'))
          .layoutWeight(1)
          .height(32)
          .borderRadius(8)
          .backgroundColor(Color.Transparent)
          .fontColor(this.chrome().accent)
          .border({ width: 1, color: this.chrome().outlineVariant })
          .fontSize(13)
          .onClick(() => {
            clickHaptic()
            this.preview(t.url)
          })
        Button(I18n.get('tunnel.revoke'))
          .layoutWeight(1)
          .height(32)
          .borderRadius(8)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.terminal_error'))
          .fontSize(13)
          .onClick(() => {
            clickHaptic()
            this.confirmRevoke(t)
          })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor(this.chrome().surface)
    .alignItems(HorizontalAlign.Start)
  }
}
