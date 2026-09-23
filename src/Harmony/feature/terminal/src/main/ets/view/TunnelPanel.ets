/**
 * @file TunnelPanel.ets
 * @brief Port forwarding bindSheet panel for a terminal session.
 *
 * Lists the session's active tunnels, lets the user create a new forward
 * from a local port, copy the public link, preview it in a web page, or
 * revoke an existing forward. Mirrors ArtifactsPage / SessionHomePage
 * styling. Failures surface in the in-panel error banner, never silently.
 */
import { pasteboard } from '@kit.BasicServicesKit'
import { I18n, ApiService, RouteName, TunnelInfo, showToast, clickHaptic, TerminalChrome } from '@rwecho/core'

@Component
export struct TunnelPanel {
  sessionId: string = ''
  @State tunnels: TunnelInfo[] = []
  @State portInput: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('terminalChromeJson') chromeJson: string = ''

  private chrome(): TerminalChrome {
    return TerminalChrome.fromJson(this.chromeJson)
  }

  aboutToAppear() {
    this.loadTunnels()
  }

  async loadTunnels(): Promise<void> {
    this.isLoading = true
    this.errorMessage = ''
    try {
      this.tunnels = await ApiService.listTunnels(this.sessionId)
    } catch (e) {
      this.errorMessage = (e as Error).message || I18n.get('common.error')
    } finally {
      this.isLoading = false
    }
  }

  async createTunnel(): Promise<void> {
    const port = parseInt(this.portInput.trim(), 10)
    if (Number.isNaN(port) || port < 1 || port > 65535) {
      this.errorMessage = I18n.get('tunnel.port_invalid')
      return
    }
    this.isLoading = true
    this.errorMessage = ''
    try {
      await ApiService.createTunnel(this.sessionId, port)
      this.portInput = ''
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
                action: () => {
                  clickHaptic()
                  this.confirmRevoke(t)
                },
                // 左滑露出的删除区域：红色块 + 删除图标
                builder: () => {
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
    Row({ space: 8 }) {
      TextInput({
        text: $$this.portInput,
        placeholder: I18n.get('tunnel.port_placeholder')
      })
        .type(InputType.Number)
        .layoutWeight(1)
        .height(48)
        .borderRadius(8)
        .backgroundColor(this.chrome().surfaceHigh)
        .fontColor(this.chrome().accent)
        .placeholderColor(this.chrome().onSurfaceVariant)
        .fontSize(16)

      Button(I18n.get('tunnel.create'))
        .height(48)
        .padding({ left: 24, right: 24 })
        .borderRadius(24)
        .backgroundColor(this.chrome().accentContainer)
        .fontColor(this.chrome().onAccentContainer)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .enabled(!this.isLoading)
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
          this.loadTunnels()
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
        Text(`${t.port}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.chrome().accent)
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
