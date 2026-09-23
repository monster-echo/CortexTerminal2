/**
 * @file TerminalThemesPage.ets
 * @brief 终端主题管理页：内置预设 + 自定义主题（新建/编辑/删除）。
 */
import { I18n, PageLayout, showToast, clickHaptic, TerminalThemeProfile, TerminalThemes } from '@rwecho/core'

const PREVIEW_KEYS: string[] = ['background', 'foreground', 'red', 'green', 'blue', 'yellow']

@Component
export struct TerminalThemesPage {
  @StorageLink('terminalTheme') terminalTheme: string = 'followApp'
  @StorageLink('terminalCustomThemes') customThemesJson: string = '[]'
  @StorageLink('language') currentLanguage: string = 'en'
  @State customList: TerminalThemeProfile[] = []
  @State showEditor: boolean = false
  @State editingId: string = ''
  @State editorName: string = ''
  @State editorColors: string[] = []
  @State editorValid: boolean[] = []

  aboutToAppear() {
    this.reloadCustom()
    if (this.editorColors.length === 0) {
      this.editorColors = this.defaultEditorColors()
      this.editorValid = this.defaultEditorValid()
    }
  }

  private reloadCustom() {
    try {
      this.customList = TerminalThemes.parseCustomThemes(this.customThemesJson)
    } catch (e) {
      throw new Error('terminalCustomThemes parse failed: ' + (e as Error).message)
    }
  }

  private defaultEditorColors(): string[] {
    const colors: string[] = []
    for (let i = 0; i < TerminalThemes.COLOR_KEYS.length; i++) {
      colors.push('#000000')
    }
    return colors
  }

  private defaultEditorValid(): boolean[] {
    const valid: boolean[] = []
    for (let i = 0; i < TerminalThemes.COLOR_KEYS.length; i++) {
      valid.push(true)
    }
    return valid
  }

  /** 响应式 i18n：引用 currentLanguage 让 Text 订阅 language。 */
  private tr(key: string): string {
    return I18n.get(key) + (this.currentLanguage ? '' : '')
  }

  private displayName(profile: TerminalThemeProfile): string {
    return profile.builtIn ? this.tr(profile.name) : profile.name
  }

  private colorOf(profile: TerminalThemeProfile, key: string): string {
    if (key === 'background') {
      return profile.background
    }
    if (key === 'foreground') {
      return profile.foreground
    }
    if (key === 'cursor') {
      return profile.cursor
    }
    if (key === 'selection') {
      return profile.selection
    }
    if (key === 'black') {
      return profile.black
    }
    if (key === 'red') {
      return profile.red
    }
    if (key === 'green') {
      return profile.green
    }
    if (key === 'yellow') {
      return profile.yellow
    }
    if (key === 'blue') {
      return profile.blue
    }
    if (key === 'magenta') {
      return profile.magenta
    }
    if (key === 'cyan') {
      return profile.cyan
    }
    if (key === 'white') {
      return profile.white
    }
    if (key === 'brightBlack') {
      return profile.brightBlack
    }
    if (key === 'brightRed') {
      return profile.brightRed
    }
    if (key === 'brightGreen') {
      return profile.brightGreen
    }
    if (key === 'brightYellow') {
      return profile.brightYellow
    }
    if (key === 'brightBlue') {
      return profile.brightBlue
    }
    if (key === 'brightMagenta') {
      return profile.brightMagenta
    }
    if (key === 'brightCyan') {
      return profile.brightCyan
    }
    return profile.brightWhite
  }

  private applySelection(selection: string) {
    this.terminalTheme = selection
    AppStorage.setOrCreate('terminalTheme', selection)
    this.syncResolvedTheme(selection)
  }

  /** 与 EntryAbility.syncTerminalColorMode 同一规则：写 terminalColorMode / terminalThemeJson / terminalThemeName / terminalChromeJson。 */
  private syncResolvedTheme(selection: string) {
    const appColorMode = (AppStorage.get<string>('colorMode') ?? 'dark') === 'light' ? 'light' : 'dark'
    const resolution = TerminalThemes.resolve(selection, appColorMode, this.customThemesJson)
    AppStorage.setOrCreate('terminalColorMode', resolution.colorMode)
    AppStorage.setOrCreate('terminalThemeJson', resolution.themeJson)
    AppStorage.setOrCreate('terminalThemeName', resolution.themeName)
    AppStorage.setOrCreate('terminalChromeJson', resolution.chromeJson)
  }

  private persistCustomList() {
    const json = TerminalThemes.serializeCustomThemes(this.customList)
    this.customThemesJson = json
    AppStorage.setOrCreate('terminalCustomThemes', json)
  }

  private openNewEditor() {
    this.editingId = ''
    this.editorName = ''
    this.editorColors = this.defaultEditorColors()
    this.editorValid = this.defaultEditorValid()
    this.showEditor = true
  }

  private openEditEditor(profile: TerminalThemeProfile) {
    this.editingId = profile.id
    this.editorName = profile.name
    const colors: string[] = []
    const valid: boolean[] = []
    for (let i = 0; i < TerminalThemes.COLOR_KEYS.length; i++) {
      colors.push(this.colorOf(profile, TerminalThemes.COLOR_KEYS[i]))
      valid.push(true)
    }
    this.editorColors = colors
    this.editorValid = valid
    this.showEditor = true
  }

  private closeEditor() {
    this.showEditor = false
  }

  private onEditorColorChange(index: number, value: string) {
    const trimmed = value.trim()
    this.editorColors[index] = trimmed
    const valid = TerminalThemes.isValidHex(trimmed)
    this.editorValid[index] = valid
  }

  private onEditorColorSubmit(index: number) {
    if (!this.editorValid[index]) {
      showToast(I18n.get('terminalTheme.invalidColor'))
    }
  }

  private saveEditor() {
    const name = this.editorName.trim()
    if (name.length === 0) {
      showToast(I18n.get('terminalTheme.invalidName'))
      return
    }
    for (let i = 0; i < this.editorValid.length; i++) {
      if (!this.editorValid[i] || !TerminalThemes.isValidHex(this.editorColors[i])) {
        showToast(I18n.get('terminalTheme.invalidColor'))
        return
      }
    }
    let profile: TerminalThemeProfile
    if (this.editingId.length > 0) {
      profile = TerminalThemes.findById(this.editingId, this.customList)
    } else {
      profile = new TerminalThemeProfile()
      profile.id = 'custom-' + Date.now().toString()
      profile.builtIn = false
      this.customList.push(profile)
    }
    profile.name = name
    profile.background = this.editorColors[0]
    profile.foreground = this.editorColors[1]
    profile.cursor = this.editorColors[2]
    profile.selection = this.editorColors[3]
    profile.black = this.editorColors[4]
    profile.red = this.editorColors[5]
    profile.green = this.editorColors[6]
    profile.yellow = this.editorColors[7]
    profile.blue = this.editorColors[8]
    profile.magenta = this.editorColors[9]
    profile.cyan = this.editorColors[10]
    profile.white = this.editorColors[11]
    profile.brightBlack = this.editorColors[12]
    profile.brightRed = this.editorColors[13]
    profile.brightGreen = this.editorColors[14]
    profile.brightYellow = this.editorColors[15]
    profile.brightBlue = this.editorColors[16]
    profile.brightMagenta = this.editorColors[17]
    profile.brightCyan = this.editorColors[18]
    profile.brightWhite = this.editorColors[19]
    profile.isDark = TerminalThemes.deriveIsDark(profile.background)
    this.persistCustomList()
    this.applySelection(profile.id)
    this.closeEditor()
    showToast(I18n.get('terminalTheme.saved'))
  }

  private confirmDelete(profile: TerminalThemeProfile) {
    this.getUIContext()?.showAlertDialog({
      title: I18n.get('terminalTheme.deleteConfirmTitle'),
      message: I18n.get('terminalTheme.deleteConfirmMessage').replace('{v}', profile.name),
      primaryButton: {
        value: I18n.get('common.cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: I18n.get('terminalTheme.custom.delete'),
        action: () => {
          this.deleteCustom(profile)
        }
      }
    })
  }

  private deleteCustom(profile: TerminalThemeProfile) {
    const remaining: TerminalThemeProfile[] = []
    for (let i = 0; i < this.customList.length; i++) {
      if (this.customList[i].id !== profile.id) {
        remaining.push(this.customList[i])
      }
    }
    this.customList = remaining
    this.persistCustomList()
    if (this.terminalTheme === profile.id) {
      this.applySelection('followApp')
    }
    showToast(I18n.get('terminalTheme.deleted'))
  }

  build() {
    PageLayout({ title: I18n.get('terminalTheme.title') }) {
      Column() {
        if (this.showEditor) {
          this.EditorView()
        } else {
          this.ThemeListView()
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
  SwatchRow(profile: TerminalThemeProfile, keys: string[]) {
    Row({ space: 6 }) {
      ForEach(keys, (key: string) => {
        Row()
          .width(24)
          .height(24)
          .borderRadius(6)
          .backgroundColor(this.colorOf(profile, key))
          .border({ width: 1, color: $r('app.color.terminal_outline_variant') })
      }, (key: string) => key)
    }
  }

  @Builder
  ThemeItem(profile: TerminalThemeProfile, custom: boolean) {
    Row() {
      Column() {
        Text(this.displayName(profile))
          .fontSize(16)
          .fontColor($r('app.color.terminal_on_surface'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        this.SwatchRow(profile, PREVIEW_KEYS)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.terminalTheme === profile.id) {
        Text('✓')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_primary'))
          .margin({ right: custom ? 4 : 0 })
      }
      if (custom) {
        Text(this.tr('terminalTheme.custom.edit'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_on_primary_container'))
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            clickHaptic()
            this.openEditEditor(profile)
          })
        Text(this.tr('terminalTheme.custom.delete'))
          .fontSize(13)
          .fontColor($r('app.color.terminal_error'))
          .padding({ left: 8, right: 4, top: 6, bottom: 6 })
          .onClick(() => {
            clickHaptic()
            this.confirmDelete(profile)
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 12, bottom: 12 })
    .borderRadius(10)
    .backgroundColor($r('app.color.terminal_surface_container'))
    .border({
      width: this.terminalTheme === profile.id ? 2 : 1,
      color: this.terminalTheme === profile.id
        ? $r('app.color.terminal_primary')
        : $r('app.color.terminal_outline_variant')
    })
    .margin({ bottom: 8 })
    .onClick(() => {
      clickHaptic()
      this.applySelection(profile.id)
    })
  }

  @Builder
  ThemeListView() {
    Scroll() {
      Column() {
        this.SectionHeader('terminalTheme.custom.builtinSection')
        Column({ space: 8 }) {
          ForEach(TerminalThemes.BUILT_IN, (profile: TerminalThemeProfile) => {
            this.ThemeItem(profile, false)
          }, (profile: TerminalThemeProfile) => profile.id)
        }
        .width('calc(100% - 32vp)')

        if (this.customList.length > 0) {
          this.SectionHeader('terminalTheme.custom.customSection')
          Column({ space: 8 }) {
            ForEach(this.customList, (profile: TerminalThemeProfile) => {
              this.ThemeItem(profile, true)
            }, (profile: TerminalThemeProfile) => profile.id)
          }
          .width('calc(100% - 32vp)')
        }

        Button(this.tr('terminalTheme.custom.new'))
          .width('calc(100% - 32vp)')
          .height(48)
          .margin({ top: 16 })
          .backgroundColor($r('app.color.terminal_primary'))
          .fontColor($r('app.color.terminal_on_primary'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .borderRadius(24)
          .onClick(() => {
            clickHaptic()
            this.openNewEditor()
          })
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  ColorField(index: number) {
    Row() {
      Text(this.tr('terminalTheme.color.' + TerminalThemes.COLOR_KEYS[index]))
        .fontSize(14)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .layoutWeight(1)

      Row()
        .width(24)
        .height(24)
        .borderRadius(6)
        .backgroundColor(this.editorValid[index]
          ? this.editorColors[index]
          : Color.Transparent)
        .border({ width: 1, color: $r('app.color.terminal_outline') })

      TextInput({ text: this.editorColors[index] })
        .width(120)
        .height(40)
        .fontSize(14)
        .fontColor(this.editorValid[index]
          ? $r('app.color.terminal_on_surface')
          : $r('app.color.terminal_error'))
        .backgroundColor($r('app.color.terminal_surface_container_high'))
        .borderRadius(8)
        .onChange((value: string) => {
          this.onEditorColorChange(index, value)
        })
        .onSubmit(() => {
          this.onEditorColorSubmit(index)
        })
        .onBlur(() => {
          this.onEditorColorSubmit(index)
        })
    }
    .width('100%')
    .height(48)
  }

  @Builder
  EditorView() {
    Scroll() {
      Column() {
        Text(this.editingId.length > 0
          ? this.tr('terminalTheme.custom.edit')
          : this.tr('terminalTheme.custom.new'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_on_surface'))
          .width('calc(100% - 32vp)')
          .margin({ top: 16, bottom: 12 })

        Column() {
          Text(this.tr('terminalTheme.custom.nameLabel'))
            .fontSize(14)
            .fontColor($r('app.color.terminal_on_surface_variant'))
            .margin({ bottom: 8 })
          TextInput({ text: this.editorName, placeholder: this.tr('terminalTheme.custom.namePlaceholder') })
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor($r('app.color.terminal_on_surface'))
            .placeholderColor($r('app.color.terminal_on_surface_variant'))
            .placeholderFont({ size: 14 })
            .backgroundColor($r('app.color.terminal_surface_container_high'))
            .borderRadius(8)
            .onChange((value: string) => {
              this.editorName = value
            })
        }
        .alignItems(HorizontalAlign.Start)
        .width('calc(100% - 32vp)')
        .margin({ bottom: 16 })

        Column({ space: 4 }) {
          ForEach(TerminalThemes.COLOR_KEYS, (_key: string, index: number) => {
            this.ColorField(index)
          }, (key: string) => key)
        }
        .width('calc(100% - 32vp)')

        Button(this.tr('terminalTheme.custom.save'))
          .width('calc(100% - 32vp)')
          .height(48)
          .margin({ top: 24 })
          .backgroundColor($r('app.color.terminal_primary'))
          .fontColor($r('app.color.terminal_on_primary'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .borderRadius(24)
          .onClick(() => {
            clickHaptic()
            this.saveEditor()
          })

        Button(this.tr('common.cancel'))
          .width('calc(100% - 32vp)')
          .height(48)
          .margin({ top: 8 })
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: $r('app.color.terminal_outline_variant') })
          .fontColor($r('app.color.terminal_on_surface'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .borderRadius(8)
          .onClick(() => {
            clickHaptic()
            this.closeEditor()
          })
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}
