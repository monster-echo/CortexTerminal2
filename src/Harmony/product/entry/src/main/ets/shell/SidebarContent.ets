/**
 * @file SidebarContent.ets
 * @brief Navigation sidebar extracted from Index.ets.
 */
import { I18n, AuthState, RouteName, lightHaptic } from '@rwecho/core'

@Component
export struct SidebarContent {
  activeRoute: string = RouteName.SESSION_HOME
  onNavigate?: (() => void) | null = null
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('userInfo') userInfoSig: string = ''

  build() {
    Column() {
      // Brand area
      Row() {
        Image($r('app.media.app_icon'))
          .width(36)
          .height(36)
          .borderRadius(10)

        Column() {
          Text(I18n.get('auth.login.tagline'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_primary'))
            .maxLines(1)

          Text('云枢终端')
            .fontSize(11)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })
      }
      .width('100%')
      .height(64)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      // Nav: Terminal Sessions
      this.NavItem('⌘', I18n.get('sidebar.sessions'), RouteName.SESSION_HOME,
        this.activeRoute === RouteName.SESSION_HOME || this.activeRoute === RouteName.TERMINAL_SESSION)

      Divider()
        .color($r('app.color.terminal_outline_variant'))
        .margin({ left: 16, right: 16, top: 10, bottom: 10 })

      // Nav: Workers
      this.NavItem('▦', I18n.get('sidebar.workers'), RouteName.WORKER_LIST,
        this.activeRoute === RouteName.WORKER_LIST || this.activeRoute === RouteName.WORKER_DETAIL)

      // Nav: 扫码激活（对齐 Flutter app_shell：scanLine → /activate，push 压栈）
      this.NavItem('⌖', I18n.get('auth.activate.title'), RouteName.ACTIVATE_WORKER,
        this.activeRoute === RouteName.ACTIVATE_WORKER || this.activeRoute === RouteName.ACTIVATE_CODE,
        true)

      Blank()

      // User profile
      Row() {
        if (AuthState.getResolvedAvatarUrl().length > 0) {
          Image(AuthState.getResolvedAvatarUrl())
            .width(38)
            .height(38)
            .borderRadius(19)
        } else {
          Text(AuthState.getDisplayName().substring(0, 1).toUpperCase() || 'U')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_on_secondary_container'))
            .width(38)
            .height(38)
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.terminal_secondary_container'))
            .borderRadius(19)
        }

        Column() {
          Text(AuthState.getDisplayName() || I18n.get('auth.login.title'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.terminal_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(I18n.get('settings.account'))
            .fontSize(12)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 10 })
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.terminal_surface_container'))
      .onClick(() => {
        lightHaptic()
        this.navigate(RouteName.SETTINGS)
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.terminal_surface_container_high'))
    .borderColor($r('app.color.terminal_outline_variant'))
    .borderWidth({ right: 1 })
  }

  @Builder
  NavItem(icon: string, label: string, route: string, selected: boolean, push: boolean = false) {
    Row() {
      Text(icon)
        .fontSize(16)
        .fontColor(selected ? $r('app.color.terminal_on_secondary_container') :
          $r('app.color.terminal_on_surface_variant'))
        .width(28)
        .textAlign(TextAlign.Center)

      Text(label)
        .fontSize(14)
        .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(selected ? $r('app.color.terminal_on_secondary_container') :
          $r('app.color.terminal_primary'))
        .margin({ left: 8 })
    }
    .width('calc(100% - 24vp)')
    .height(44)
    .padding({ left: 10, right: 10 })
    .margin({ left: 12, right: 12, top: 4 })
    .borderRadius(10)
    .backgroundColor(selected ? $r('app.color.terminal_secondary_container') : Color.Transparent)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      lightHaptic()
      // 扫码页是子页面：push 压栈，返回键才有栈可弹（对齐 Flutter _push）。
      if (push) {
        if (this.onNavigate) {
          this.onNavigate()
        }
        this.pageStack.pushPath({ name: route })
        return
      }
      this.navigate(route)
    })
  }

  private navigate(route: string, param?: Object) {
    if (this.onNavigate) {
      this.onNavigate()
    }
    this.pageStack.replacePath({ name: route, param: param })
  }
}
