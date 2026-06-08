import { ApiService, AuthService, AuthState, I18n, PageLayout, RouteName, showI18nToast } from '@rwecho/core'

@Component
export struct AccountSecurityPage {
  @Consume('pageStack') pageStack: NavPathStack
  @State showDeleteSheet: boolean = false
  @State confirmUsername: string = ''
  @State isDeleting: boolean = false
  @State deleteError: string = ''
  @State currentUsername: string = ''

  aboutToAppear() {
    this.currentUsername = AuthState.getDisplayName()
    if (this.currentUsername.length === 0) {
      this.loadProfile()
    }
  }

  private async loadProfile() {
    try {
      const profile = await ApiService.getProfile()
      this.currentUsername = (profile['username'] as string) || ''
    } catch (_e) {}
  }

  build() {
    PageLayout({ title: I18n.get('security.title') }) {
        Column() {
          // Change Password
          Row() {
            Text(I18n.get('security.change_password'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_primary'))
              .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.terminal_on_surface_variant')])
          }
          .width('100%')
          .padding(14)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_surface_container'))
          .margin({ bottom: 8 })
          .onClick(() => {
            this.pageStack.pushPath({ name: RouteName.CHANGE_PASSWORD })
          })

          // Delete Account
          Row() {
            Text(I18n.get('security.delete_account'))
              .fontSize(14)
              .fontColor($r('app.color.terminal_error'))
              .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.terminal_on_surface_variant')])
          }
          .width('100%')
          .padding(14)
          .borderRadius(12)
          .backgroundColor($r('app.color.terminal_surface_container'))
          .onClick(() => {
            this.confirmUsername = ''
            this.deleteError = ''
            this.showDeleteSheet = true
          })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 8 })
        .bindSheet(this.showDeleteSheet, this.DeleteSheetContent(), {
          height: SheetSize.FIT_CONTENT,
          showClose: true,
          backgroundColor: $r('app.color.terminal_surface'),
          onDisappear: () => { this.showDeleteSheet = false }
        })
    }
  }

  @Builder
  DeleteSheetContent() {
    Column() {
      Column() {
        Text(I18n.get('security.delete_account'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_error'))
          .width('100%')
          .margin({ bottom: 12 })

        Text(I18n.get('security.delete_desc'))
          .fontSize(14)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .width('100%')
          .margin({ bottom: 16 })

        TextInput({ placeholder: I18n.get('security.type_username_confirm').replace('{n}', this.currentUsername), text: this.confirmUsername })
          .width('100%')
          .height(48)
          .borderRadius(8)
          .backgroundColor($r('app.color.terminal_surface_container_high'))
          .fontColor($r('app.color.terminal_primary'))
          .placeholderColor($r('app.color.terminal_on_surface_variant'))
          .onChange((value: string) => {
            this.confirmUsername = value
            this.deleteError = ''
          })

        if (this.deleteError.length > 0) {
          Text(this.deleteError)
            .fontSize(13)
            .fontColor($r('app.color.terminal_error'))
            .width('100%')
            .margin({ top: 8 })
        }

        Button() {
          if (this.isDeleting) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(Color.White)
          } else {
            Text(I18n.get('security.delete_button'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
          }
        }
        .width('100%')
        .height(48)
        .borderRadius(12)
        .backgroundColor($r('app.color.terminal_error'))
        .margin({ top: 20 })
        .enabled(this.confirmUsername === this.currentUsername && !this.isDeleting)
        .opacity(this.confirmUsername === this.currentUsername ? 1 : 0.5)
        .onClick(() => {
          this.deleteAccount()
        })
      }
      .width('100%')
      .padding(20)
    }
    .width('100%')
    .padding({ top: 16, bottom: 24 })
    .backgroundColor($r('app.color.terminal_surface'))
  }

  private async deleteAccount() {
    this.isDeleting = true
    this.deleteError = ''
    try {
      await ApiService.deleteAccount()
      this.isDeleting = false
      this.showDeleteSheet = false
      showI18nToast('security.account_deleted')
      AuthService.logout()
      this.pageStack.clear()
      AppStorage.setOrCreate('navigateTo', RouteName.AUTH_LOGIN)
    } catch (e) {
      this.deleteError = (e as Error).message || I18n.get('common.error')
      this.isDeleting = false
    }
  }
}
