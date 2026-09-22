/**
 * @file PreferencesPage.ets
 * @brief 通用设置二级页：外观主题 / 语言 / 终端回滚 / GPU 加速（开发者）
 */
import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { ApiService, I18n, PageLayout, showToast, clickHaptic } from '@rwecho/core'

@Component
export struct PreferencesPage {
  @StorageLink('themeMode') currentTheme: string = 'system'
  @StorageLink('language') currentLanguage: string = 'en'
  @StorageLink('webglEnabled') webglEnabled: boolean = true
  @Consume('pageStack') pageStack: NavPathStack
  @State scrollbackBytes: number = 524288
  @State scrollbackSaving: boolean = false
  @State showDevOptions: boolean = false

  aboutToAppear() {
    this.loadScrollback()
    this.showDevOptions = AppStorage.get<boolean>('showDevOptions') ?? false
  }

  private async loadScrollback() {
    try {
      this.scrollbackBytes = await ApiService.getScrollbackMaxBytes()
    } catch (e) {
      console.warn('[Preferences] loadScrollback failed: ' + (e as Error).message)
    }
  }

  private async saveScrollback(bytes: number, label: string) {
    if (this.scrollbackSaving || bytes === this.scrollbackBytes) {
      return
    }
    this.scrollbackSaving = true
    const previous = this.scrollbackBytes
    this.scrollbackBytes = bytes
    try {
      await ApiService.updateScrollbackMaxBytes(bytes)
      showToast(I18n.get('settings.scrollback_changed').replace('{v}', label))
    } catch (e) {
      this.scrollbackBytes = previous
      showToast((e as Error).message || I18n.get('common.error'))
    } finally {
      this.scrollbackSaving = false
    }
  }

  private isActiveScrollback(value: number): boolean {
    const v = this.scrollbackBytes
    if (v >= 5242880) {
      return value === 5242880
    }
    if (v >= 2097152) {
      return value === 2097152
    }
    if (v >= 1048576) {
      return value === 1048576
    }
    return value === 524288
  }

  /** 响应式 i18n：引用 currentLanguage 让 Text 订阅 language，切语言时自动刷新 */
  private tr(key: string): string {
    return I18n.get(key) + (this.currentLanguage ? '' : '')
  }

  build() {
    PageLayout({ title: I18n.get('settings.general') }) {
      Column() {
        this.SectionHeader('settings.appearance')

        Column() {
          Row() {
            Text(this.tr('settings.theme'))
              .fontSize(16)
              .fontColor($r('app.color.terminal_on_surface'))
              .layoutWeight(1)

            Row() {
              this.ThemeOption('settings.theme_light', 'light')
              this.ThemeOption('settings.theme_dark', 'dark')
              this.ThemeOption('settings.theme_system', 'system')
            }
          }
          .width('100%')
          .height(52)

          Divider()
            .color($r('app.color.terminal_outline_variant'))
            .margin({ left: 16 })

          Row() {
            Text(this.tr('settings.language'))
              .fontSize(16)
              .fontColor($r('app.color.terminal_on_surface'))
              .layoutWeight(1)

            Row() {
              this.LanguageOption('settings.language_zh', 'zh')
              this.LanguageOption('settings.language_en', 'en')
            }
          }
          .width('100%')
          .height(52)
        }
        .prefCardStyle()

        this.SectionHeader('settings.terminal')

        Column() {
          Row() {
            Text(this.tr('settings.scrollback'))
              .fontSize(16)
              .fontColor($r('app.color.terminal_on_surface'))
              .layoutWeight(1)

            Row() {
              this.ScrollbackOption('512K', 524288)
              this.ScrollbackOption('1M', 1048576)
              this.ScrollbackOption('2M', 2097152)
              this.ScrollbackOption('5M', 5242880)
            }
          }
          .width('100%')

          Text(this.tr('settings.scrollback_desc'))
            .width('100%')
            .maxLines(2)
            .fontSize(12)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ top: 4, bottom: 8 })
        }
        .prefCardStyle()

        if (this.showDevOptions) {
          this.SectionHeader('Developer Options')

          Row() {
            Text('GPU Acceleration (WebGL)')
              .fontSize(16)
              .fontColor($r('app.color.terminal_on_surface'))
              .layoutWeight(1)

            Checkbox()
              .width(20)
              .height(20)
              .select(this.webglEnabled)
              .onChange((value: boolean) => {
                this.webglEnabled = value
                AppStorage.setOrCreate('webglEnabled', value)
              })
          }
          .prefCardStyle()
        }

        Blank().height(24)
      }
      .width('100%')
    }
  }

  @Builder
  SectionHeader(key: string) {
    Text(this.tr(key))
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.terminal_on_surface_variant'))
      .textCase(TextCase.UpperCase)
      .width('calc(100% - 32vp)')
      .padding({ left: 16 })
      .margin({ top: 20, bottom: 8 })
  }

  @Builder
  ThemeOption(key: string, value: string) {
    Text(this.tr(key))
      .fontSize(13)
      .fontWeight(this.currentTheme === value ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.currentTheme === value ?
        $r('app.color.terminal_on_secondary_container') :
        $r('app.color.terminal_on_surface_variant'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(8)
      .backgroundColor(this.currentTheme === value ?
        $r('app.color.terminal_secondary_container') :
        Color.Transparent)
      .onClick(() => {
        clickHaptic()
        this.currentTheme = value
        this.applyTheme(this.currentTheme)
        showToast(I18n.get('settings.theme_changed').replace('{v}', I18n.get(`settings.theme_${value}`)))
      })
  }

  @Builder
  LanguageOption(key: string, code: string) {
    Text(this.tr(key))
      .fontSize(13)
      .fontWeight(this.currentLanguage === code ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.currentLanguage === code ?
        $r('app.color.terminal_on_secondary_container') :
        $r('app.color.terminal_on_surface_variant'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(8)
      .backgroundColor(this.currentLanguage === code ?
        $r('app.color.terminal_secondary_container') :
        Color.Transparent)
      .onClick(() => {
        clickHaptic()
        this.currentLanguage = code
        showToast(I18n.get('settings.language_changed').replace('{v}', I18n.get(`settings.language_${code}`)))
      })
  }

  @Builder
  ScrollbackOption(label: string, value: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.isActiveScrollback(value) ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.isActiveScrollback(value) ?
        $r('app.color.terminal_on_secondary_container') :
        $r('app.color.terminal_on_surface_variant'))
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(8)
      .backgroundColor(this.isActiveScrollback(value) ?
        $r('app.color.terminal_secondary_container') :
        Color.Transparent)
      .onClick(() => {
        clickHaptic()
        this.saveScrollback(value, label)
      })
  }

  private applyTheme(theme: string) {
    const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext
    try {
      if (theme === 'system') {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      } else {
        const colorMode = theme === 'dark'
          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        context.getApplicationContext().setColorMode(colorMode)
      }
    } catch (_e) {}
  }
}

/** 分组卡片容器样式：surface_container 背景 + 12dp 圆角 + 16dp 水平内边距 */
@Extend(Column)
function prefCardStyle() {
  .width('calc(100% - 32vp)')
  .padding({ left: 16, right: 16, top: 4, bottom: 4 })
  .borderRadius(12)
  .backgroundColor($r('app.color.terminal_surface_container'))
  .margin({ bottom: 8 })
}
