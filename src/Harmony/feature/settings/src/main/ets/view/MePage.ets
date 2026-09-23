import { ApiService, I18n, AuthState, WorkerInfo, RouteName, AnalyticsService, lightHaptic, clickHaptic } from '@rwecho/core'

/**
 * MePage（我的，对齐 Flutter MeScreen）：
 * 用户头 + 右上角齿轮进设置（压栈、可返回）；
 * 会员权益 hero 卡（管理会员(IAP) / 兑换码入口）；
 * 下半部分 Worker 概况与统计（查看全部压栈进入，可返回）。
 */
@Component
export struct MePage {
  @StorageLink('language') currentLanguage: string = 'en'
  @State displayName: string = ''
  @State avatarDisplayUrl: string = ''
  @State workers: WorkerInfo[] = []
  @State isLoadingWorkers: boolean = false
  @State errorMessage: string = ''
  @Consume('pageStack') pageStack: NavPathStack

  aboutToAppear() {
    AnalyticsService.onPageStart('me/Page')
    this.displayName = AuthState.getDisplayName()
    this.avatarDisplayUrl = AuthState.getResolvedAvatarUrl()
    this.loadWorkers()
  }

  /** 响应式 i18n：引用 currentLanguage 让 Text 订阅 language，切语言时自动刷新 */
  private tr(key: string): string {
    return I18n.get(key) + (this.currentLanguage ? '' : '')
  }

  private async loadWorkers() {
    this.isLoadingWorkers = true
    this.errorMessage = ''
    try {
      this.workers = await ApiService.listWorkers()
    } catch (e) {
      this.errorMessage = (e as Error).message || I18n.get('common.error')
    } finally {
      this.isLoadingWorkers = false
    }
  }

  private onlineCount(): number {
    let count = 0
    for (let i = 0; i < this.workers.length; i++) {
      if (this.workers[i].isOnline) {
        count++
      }
    }
    return count
  }

  private totalSessions(): number {
    let sum = 0
    for (let i = 0; i < this.workers.length; i++) {
      sum += this.workers[i].sessionCount
    }
    return sum
  }

  private avgUsage(pickCpu: boolean): string {
    let sum = 0
    let count = 0
    for (let i = 0; i < this.workers.length; i++) {
      if (!this.workers[i].isOnline) {
        continue
      }
      sum += pickCpu ? this.workers[i].cpuUsage : this.workers[i].memoryUsage
      count++
    }
    if (count === 0) {
      return '-'
    }
    return `${Math.round(sum / count)}%`
  }

  build() {
    Scroll() {
      Column() {
        // ── 用户头 + 右上角设置齿轮 ────────────────────────────
        Row() {
          if (this.avatarDisplayUrl.length > 0) {
            Image(this.avatarDisplayUrl)
              .width(56)
              .height(56)
              .borderRadius(28)
          } else {
            Text(this.displayName.length > 0 ? this.displayName.substring(0, 1).toUpperCase() : 'U')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.terminal_on_secondary_container'))
              .width(56)
              .height(56)
              .textAlign(TextAlign.Center)
              .backgroundColor($r('app.color.terminal_secondary_container'))
              .borderRadius(28)
          }

          Text(this.displayName || this.tr('me.title'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_on_surface'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 12 })
            .layoutWeight(1)

          Button() {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(22)
              .fontColor([$r('app.color.terminal_primary')])
          }
          .width(44)
          .height(44)
          .padding(0)
          .borderRadius(22)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            lightHaptic()
            this.pageStack.pushPath({ name: RouteName.SETTINGS_ROOT })
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8, bottom: 16 })

        // ── 会员权益 hero 卡 ──────────────────────────────────
        Column() {
          Row() {
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(20)
              .fontColor([$r('app.color.terminal_primary')])

            Text(I18n.get('membership.title'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.terminal_on_primary_container'))
              .margin({ left: 8 })
              .layoutWeight(1)
          }
          .width('100%')

          Text(this.tr('me.benefits_hint'))
            .fontSize(13)
            .fontColor($r('app.color.terminal_on_primary_container'))
            .width('100%')
            .margin({ top: 6 })

          Row() {
            Button() {
              Text(this.tr('me.open_membership'))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.terminal_on_primary'))
            }
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.terminal_primary'))
            .onClick(() => {
              clickHaptic()
              // IAP / 会员购买页：定价与升级（购买在 web 控制台完成）。
              this.pageStack.pushPath({ name: RouteName.MEMBERSHIP })
            })

            Button() {
              Text(I18n.get('membership.menu_redeem'))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.terminal_on_primary_container'))
            }
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.terminal_primary') })
            .margin({ left: 10 })
            .onClick(() => {
              clickHaptic()
              this.pageStack.pushPath({ name: RouteName.REDEEM })
            })
          }
          .width('100%')
          .margin({ top: 16 })

        }
        .width('100%')
        .padding(20)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_primary_container'))
        .margin({ bottom: 8 })

        // ── Worker 概况与统计 ─────────────────────────────────
        Row() {
          Text(this.tr('me.worker_section'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .layoutWeight(1)

          if (this.workers.length > 0) {
            Row() {
              Text(this.tr('me.view_all'))
                .fontSize(13)
                .fontColor($r('app.color.terminal_on_primary_container'))
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(14)
                .fontColor([$r('app.color.terminal_on_primary_container')])
            }
            .onClick(() => {
              lightHaptic()
              // 带 param 压栈：Worker 列表页显示返回键、系统返回可 pop。
              const fromMe: Record<string, boolean> = { 'fromMe': true }
              this.pageStack.pushPath({ name: RouteName.WORKER_LIST, param: fromMe })
            })
          }
        }
        .width('100%')
        .margin({ top: 20, bottom: 8 })

        if (this.isLoadingWorkers) {
          Column() {
            LoadingProgress()
              .width(32)
              .height(32)
              .color($r('app.color.terminal_on_surface_variant'))
          }
          .width('100%')
          .padding({ top: 24, bottom: 24 })
          .meCardStyle()
        } else if (this.errorMessage.length > 0) {
          Column() {
            Text(this.errorMessage)
              .fontSize(14)
              .fontColor($r('app.color.terminal_error'))
              .width('100%')
            Button(I18n.get('common.retry'))
              .height(32)
              .borderRadius(8)
              .backgroundColor($r('app.color.terminal_surface_container_high'))
              .fontColor($r('app.color.terminal_on_surface'))
              .margin({ top: 8 })
              .onClick(() => {
                clickHaptic()
                this.loadWorkers()
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .meCardStyle()
        } else if (this.workers.length === 0) {
          Column() {
            Text(I18n.get('worker.list.empty'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_on_surface_variant'))
          }
          .width('100%')
          .padding(16)
          .meCardStyle()
        } else {
          Column() {
            Row() {
              this.StatCell(`${this.onlineCount()}/${this.workers.length}`, 'worker.list.title')
              this.StatCell(`${this.totalSessions()}`, 'me.total_sessions')
            }
            .width('100%')

            Divider()
              .color($r('app.color.terminal_outline_variant'))
              .margin({ top: 14, bottom: 14 })

            Row() {
              this.StatCell(this.avgUsage(true), 'me.avg_cpu')
              this.StatCell(this.avgUsage(false), 'me.avg_memory')
            }
            .width('100%')

            ForEach(this.workers.slice(0, 3), (worker: WorkerInfo) => {
              Row() {
                Circle()
                  .width(8)
                  .height(8)
                  .fill(worker.isOnline ?
                    $r('app.color.terminal_tertiary') :
                    $r('app.color.terminal_status_idle'))

                Text(worker.name || worker.hostname || worker.id)
                  .fontSize(14)
                  .fontColor($r('app.color.terminal_on_surface'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ left: 8 })
                  .layoutWeight(1)

                Text(worker.isOnline ?
                  I18n.get('worker.detail.status_online') :
                  I18n.get('worker.detail.status_offline'))
                  .fontSize(12)
                  .fontColor(worker.isOnline ?
                    $r('app.color.terminal_tertiary') :
                    $r('app.color.terminal_on_surface_variant'))
              }
              .width('100%')
              .height(40)
              .alignItems(VerticalAlign.Center)
              .margin({ top: 4 })
            }, (worker: WorkerInfo) => worker.id)
          }
          .width('100%')
          .padding(20)
          .meCardStyle()
        }

        Blank().height(24)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.terminal_surface'))
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  StatCell(value: string, labelKey: string) {
    Column() {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_on_surface'))
      Text(this.tr(labelKey))
        .fontSize(12)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding({ top: 2, bottom: 2 })
  }
}

/** 分组卡片容器样式：surface_container 背景 + 12dp 圆角（对齐 SettingsPage.cardStyle） */
@Extend(Column)
function meCardStyle() {
  .width('100%')
  .borderRadius(12)
  .backgroundColor($r('app.color.terminal_surface_container'))
  .margin({ bottom: 8 })
}
