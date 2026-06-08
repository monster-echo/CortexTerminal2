import { ApiService, I18n, WorkerInfo, GatewayInfo, showI18nToast, showToast, AnalyticsService, AnalyticsEvent, lightHaptic, clickHaptic } from '@rwecho/core'

@Component
export struct WorkerListPage {
  @State workers: WorkerInfo[] = []
  @State isLoading: boolean = false
  @State errorMessage: string = ''
  @State isRefreshing: boolean = false
  @State selectedWorker: WorkerInfo | null = null
  @State showWorkerSheet: boolean = false
  @State latestWorkerVersion: string = ''
  @Consume('pageStack') pageStack: NavPathStack

  aboutToAppear() {
    AnalyticsService.onPageStart('worker/List')
    this.loadWorkers()
    this.loadGatewayInfo()
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color($r('app.color.terminal_secondary'))
            .margin({ top: 60 })
          Text(I18n.get('worker.list.loading'))
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 12 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }

      if (this.errorMessage.length > 0) {
        Column() {
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor($r('app.color.terminal_error'))
            .margin({ top: 40 })
            .padding({ left: 20, right: 20 })

          Button(I18n.get('common.retry'))
            .margin({ top: 12 })
            .onClick(() => { clickHaptic(); this.loadWorkers() })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }

      if (!this.isLoading && this.workers.length > 0) {
        Refresh({ refreshing: $$this.isRefreshing }) {
          List() {
            ForEach(this.workers, (worker: WorkerInfo) => {
              ListItem() {
                Row() {
                  Circle()
                    .width(10)
                    .height(10)
                    .fill(worker.isOnline ?
                      $r('app.color.terminal_tertiary') :
                      $r('app.color.terminal_outline_variant'))
                    .margin({ right: 12 })

                  Column() {
                    Text(worker.name || worker.hostname || 'Unknown Worker')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.terminal_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Row() {
                      Text(worker.os || worker.operatingSystem || 'Unknown OS')
                        .fontSize(13)
                        .fontColor($r('app.color.terminal_on_surface_variant'))

                      if (worker.version.length > 0) {
                        Text(' · ')
                          .fontSize(13)
                          .fontColor($r('app.color.terminal_on_surface_variant'))

                        Text(`v${worker.version}`)
                          .fontSize(13)
                          .fontColor($r('app.color.terminal_on_surface_variant'))
                          .fontFamily('monospace')
                      }

                      // Upgrade indicator
                      if (this.canUpgrade(worker)) {
                        SymbolGlyph($r('sys.symbol.arrow_up_circle'))
                          .fontSize(14)
                          .fontColor([$r('app.color.terminal_secondary')])
                          .margin({ left: 4 })
                      }
                    }
                    .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([$r('app.color.terminal_on_surface_variant')])
                }
                .width('100%')
                .height(64)
                .alignItems(VerticalAlign.Center)
                .padding({ left: 16, right: 16 })
                .onClick(() => {
                  lightHaptic()
                  this.selectedWorker = worker
                  this.showWorkerSheet = true
                })
              }
            }, (worker: WorkerInfo) => worker.id)
          }
          .layoutWeight(1)
          .width('100%')
          .divider({ strokeWidth: 1, color: $r('app.color.terminal_outline_variant'), startMargin: 0, endMargin: 0 })
        }
        .onRefreshing(() => { this.loadWorkers() })
        .layoutWeight(1)
        .width('100%')
      }

      if (!this.isLoading && this.workers.length === 0 && this.errorMessage.length === 0) {
        Column() {
          Text(I18n.get('worker.list.empty'))
            .fontSize(16)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 60 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.terminal_surface'))
    .bindSheet($$this.showWorkerSheet, this.WorkerSheetContent(), {
      height: SheetSize.FIT_CONTENT,
      showClose: true,
      onDisappear: () => { this.showWorkerSheet = false }
    })
  }

  @Builder
  WorkerSheetContent() {
    Column() {
      if (this.selectedWorker) {
        Row() {
          Circle()
            .width(12)
            .height(12)
            .fill(this.selectedWorker!.isOnline ?
              $r('app.color.terminal_tertiary') :
              $r('app.color.terminal_outline_variant'))

          Text(this.selectedWorker!.isOnline ?
            I18n.get('worker.detail.status_online') :
            I18n.get('worker.detail.status_offline'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.selectedWorker!.isOnline ?
              $r('app.color.terminal_tertiary') :
              $r('app.color.terminal_on_surface_variant'))
            .margin({ left: 8 })
        }

        Grid() {
          GridItem() {
            this.StatItem(I18n.get('worker.detail.hostname'), this.selectedWorker!.hostname || '-')
          }
          GridItem() {
            this.StatItem(I18n.get('worker.detail.os'), this.selectedWorker!.os || '-')
          }
          GridItem() {
            this.StatItem(I18n.get('worker.detail.cpu'), `${this.selectedWorker!.cpuUsage ?? 0}%`)
          }
          GridItem() {
            this.StatItem(I18n.get('worker.detail.memory'), `${this.selectedWorker!.memoryUsage ?? 0}%`)
          }
        }
        .columnsTemplate('1fr 1fr')
        .rowsGap(12)
        .columnsGap(12)
        .width('100%')
        .margin({ top: 16 })

        if (this.selectedWorker!.version.length > 0) {
          Text(`Version: ${this.selectedWorker!.version}`)
            .fontSize(12)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 12 })
        }

        if (this.selectedWorker!.lastSeenAt.length > 0) {
          Text(`${I18n.get('worker.detail.last_seen')}：${this.formatTime(this.selectedWorker!.lastSeenAt)}`)
            .fontSize(12)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 4 })
        }

        // Upgrade button
        if (this.canUpgrade(this.selectedWorker!)) {
          Button(`Update to v${this.latestWorkerVersion}`)
            .width('100%')
            .height(48)
            .borderRadius(24)
            .backgroundColor($r('app.color.terminal_secondary_container'))
            .fontColor($r('app.color.terminal_on_secondary_container'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20 })
            .onClick(() => { clickHaptic(); this.confirmUpgrade(this.selectedWorker!) })
        }
      }
    }
    .width('100%')
    .padding(24)
    .backgroundColor($r('app.color.terminal_surface'))
  }

  @Builder
  StatItem(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.terminal_on_surface_variant'))
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.terminal_primary'))
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Start)
  }

  private canUpgrade(worker: WorkerInfo): boolean {
    if (!worker.isOnline || worker.version.length === 0 || this.latestWorkerVersion.length === 0) {
      return false
    }
    return worker.version.replace(/(\.0)+$/, '') !== this.latestWorkerVersion.replace(/(\.0)+$/, '')
  }

  private confirmUpgrade(worker: WorkerInfo) {
    this.getUIContext()?.showAlertDialog({
      title: 'Update Worker',
      message: `Update ${worker.name || worker.hostname} from v${worker.version} to v${this.latestWorkerVersion}? The worker will restart.`,
      primaryButton: {
        value: I18n.get('common.cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: 'Update',
        fontColor: $r('app.color.terminal_secondary_container'),
        action: () => { this.upgradeWorker(worker) }
      }
    })
  }

  private async upgradeWorker(worker: WorkerInfo) {
    try {
      await ApiService.upgradeWorker(worker.id)
      this.showWorkerSheet = false
      AnalyticsService.onEvent(AnalyticsEvent.WORKER_UPGRADE)
      showToast(I18n.get('worker.update_sent').replace('{v}', worker.hostname || worker.id))
      // Reload workers after a short delay to pick up version change
      setTimeout(() => { this.loadWorkers() }, 3000)
    } catch (e) {
      this.getUIContext()?.showAlertDialog({
        title: I18n.get('common.error'),
        message: (e as Error).message,
        confirm: { value: I18n.get('common.confirm'), action: () => {} }
      })
    }
  }

  private formatTime(dateStr: string): string {
    if (!dateStr) {
      return 'Never'
    }
    const date = new Date(dateStr)
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffMins = Math.floor(diffMs / 60000)

    if (diffMins < 1) {
      return 'Just now'
    } else if (diffMins < 60) {
      return `${diffMins}m ago`
    } else if (diffMins < 1440) {
      return `${Math.floor(diffMins / 60)}h ago`
    } else {
      return date.toLocaleDateString()
    }
  }

  private async loadWorkers() {
    this.isLoading = true
    this.errorMessage = ''

    try {
      this.workers = await ApiService.listWorkers()
    } catch (e) {
      this.errorMessage = (e as Error).message || 'Network error'
    } finally {
      this.isLoading = false
      this.isRefreshing = false
    }
  }

  private async loadGatewayInfo() {
    try {
      const info = await ApiService.getGatewayInfo()
      this.latestWorkerVersion = info.latestWorkerVersion
    } catch (_e) {
      // Non-critical, version comparison silently disabled
    }
  }
}
