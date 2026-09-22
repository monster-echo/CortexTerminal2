/**
 * @file TerminalThemeProfile.ets
 * @brief 终端主题档案数据模型 + 内置预设 + 解析工具。
 *
 * 放在 core（不依赖任何 feature），settings / terminal 共用。
 * cursorAccent 不落档案：webview 端用 background 派生。
 */

/** xterm.js ITheme JSON 载体（仅供 JSON.stringify）。 */
class XtermThemeJson {
  background: string = ''
  foreground: string = ''
  cursor: string = ''
  cursorAccent: string = ''
  selectionBackground: string = ''
  black: string = ''
  red: string = ''
  green: string = ''
  yellow: string = ''
  blue: string = ''
  magenta: string = ''
  cyan: string = ''
  white: string = ''
  brightBlack: string = ''
  brightRed: string = ''
  brightGreen: string = ''
  brightYellow: string = ''
  brightBlue: string = ''
  brightMagenta: string = ''
  brightCyan: string = ''
  brightWhite: string = ''
}

/** 解析结果：terminalColorMode（深浅归类）+ 完整 theme JSON。 */
export class TerminalThemeResolution {
  colorMode: string = 'dark'
  themeJson: string = ''
  themeName: string = ''
}

export class TerminalThemeProfile {
  id: string = ''
  name: string = ''
  builtIn: boolean = false
  /** 内置预设写死深浅归属；自定义主题由 background 亮度推导。 */
  isDark: boolean = true
  background: string = ''
  foreground: string = ''
  cursor: string = ''
  selection: string = ''
  black: string = ''
  red: string = ''
  green: string = ''
  yellow: string = ''
  blue: string = ''
  magenta: string = ''
  cyan: string = ''
  white: string = ''
  brightBlack: string = ''
  brightRed: string = ''
  brightGreen: string = ''
  brightYellow: string = ''
  brightBlue: string = ''
  brightMagenta: string = ''
  brightCyan: string = ''
  brightWhite: string = ''
}

export class TerminalThemes {
  /** 20 色档案字段顺序（编辑器/序列化共用）。 */
  static readonly COLOR_KEYS: string[] = [
    'background', 'foreground', 'cursor', 'selection',
    'black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white',
    'brightBlack', 'brightRed', 'brightGreen', 'brightYellow',
    'brightBlue', 'brightMagenta', 'brightCyan', 'brightWhite'
  ]

  /** 内置预设 5 套（静态只读）。 */
  static readonly BUILT_IN: TerminalThemeProfile[] = TerminalThemes.createBuiltIn()

  private static createBuiltIn(): TerminalThemeProfile[] {
    const defaultDark = new TerminalThemeProfile()
    defaultDark.id = 'default-dark'
    defaultDark.name = 'terminalTheme.builtin.defaultDark'
    defaultDark.builtIn = true
    defaultDark.isDark = true
    defaultDark.background = '#121414'
    defaultDark.foreground = '#E3E2E2'
    defaultDark.cursor = '#9FCAFF'
    defaultDark.selection = '#3A95E8'
    defaultDark.black = '#3A3D3D'
    defaultDark.red = '#FFB4AB'
    defaultDark.green = '#A2D489'
    defaultDark.yellow = '#FFD180'
    defaultDark.blue = '#9FCAFF'
    defaultDark.magenta = '#F5A8D0'
    defaultDark.cyan = '#80CBC4'
    defaultDark.white = '#E3E2E2'
    defaultDark.brightBlack = '#8E9192'
    defaultDark.brightRed = '#FFB4AB'
    defaultDark.brightGreen = '#A2D489'
    defaultDark.brightYellow = '#FFD180'
    defaultDark.brightBlue = '#9FCAFF'
    defaultDark.brightMagenta = '#F5A8D0'
    defaultDark.brightCyan = '#80CBC4'
    defaultDark.brightWhite = '#E3E2E2'

    const defaultLight = new TerminalThemeProfile()
    defaultLight.id = 'default-light'
    defaultLight.name = 'terminalTheme.builtin.defaultLight'
    defaultLight.builtIn = true
    defaultLight.isDark = false
    defaultLight.background = '#FAFAFA'
    defaultLight.foreground = '#383A42'
    defaultLight.cursor = '#0184BC'
    defaultLight.selection = '#BFCEFF'
    defaultLight.black = '#383A42'
    defaultLight.red = '#E45649'
    defaultLight.green = '#50A14F'
    defaultLight.yellow = '#C18301'
    defaultLight.blue = '#0184BC'
    defaultLight.magenta = '#A626A4'
    defaultLight.cyan = '#0997B3'
    defaultLight.white = '#FAFAFA'
    defaultLight.brightBlack = '#4F525D'
    defaultLight.brightRed = '#E06C75'
    defaultLight.brightGreen = '#98C379'
    defaultLight.brightYellow = '#E5C07B'
    defaultLight.brightBlue = '#61AFEF'
    defaultLight.brightMagenta = '#C678DD'
    defaultLight.brightCyan = '#56B6C2'
    defaultLight.brightWhite = '#FFFFFF'

    const solarizedDark = new TerminalThemeProfile()
    solarizedDark.id = 'solarized-dark'
    solarizedDark.name = 'terminalTheme.builtin.solarizedDark'
    solarizedDark.builtIn = true
    solarizedDark.isDark = true
    solarizedDark.background = '#002B36'
    solarizedDark.foreground = '#93A1A1'
    solarizedDark.cursor = '#93A1A1'
    solarizedDark.selection = '#274642'
    solarizedDark.black = '#073642'
    solarizedDark.red = '#DC322F'
    solarizedDark.green = '#859900'
    solarizedDark.yellow = '#B58900'
    solarizedDark.blue = '#268BD2'
    solarizedDark.magenta = '#D33682'
    solarizedDark.cyan = '#2AA198'
    solarizedDark.white = '#EEE8D5'
    solarizedDark.brightBlack = '#002B36'
    solarizedDark.brightRed = '#CB4B16'
    solarizedDark.brightGreen = '#586E75'
    solarizedDark.brightYellow = '#657B83'
    solarizedDark.brightBlue = '#839496'
    solarizedDark.brightMagenta = '#6C71C4'
    solarizedDark.brightCyan = '#93A1A1'
    solarizedDark.brightWhite = '#FDF6E3'

    const solarizedLight = new TerminalThemeProfile()
    solarizedLight.id = 'solarized-light'
    solarizedLight.name = 'terminalTheme.builtin.solarizedLight'
    solarizedLight.builtIn = true
    solarizedLight.isDark = false
    solarizedLight.background = '#FDF6E3'
    solarizedLight.foreground = '#657B83'
    solarizedLight.cursor = '#586E75'
    solarizedLight.selection = '#EEE8D5'
    solarizedLight.black = '#073642'
    solarizedLight.red = '#DC322F'
    solarizedLight.green = '#859900'
    solarizedLight.yellow = '#B58900'
    solarizedLight.blue = '#268BD2'
    solarizedLight.magenta = '#D33682'
    solarizedLight.cyan = '#2AA198'
    solarizedLight.white = '#EEE8D5'
    solarizedLight.brightBlack = '#839496'
    solarizedLight.brightRed = '#CB4B16'
    solarizedLight.brightGreen = '#586E75'
    solarizedLight.brightYellow = '#657B83'
    solarizedLight.brightBlue = '#839496'
    solarizedLight.brightMagenta = '#6C71C4'
    solarizedLight.brightCyan = '#93A1A1'
    solarizedLight.brightWhite = '#FDF6E3'

    const nord = new TerminalThemeProfile()
    nord.id = 'nord'
    nord.name = 'terminalTheme.builtin.nord'
    nord.builtIn = true
    nord.isDark = true
    nord.background = '#2E3440'
    nord.foreground = '#D8DEE9'
    nord.cursor = '#D8DEE9'
    nord.selection = '#434C5E'
    nord.black = '#3B4252'
    nord.red = '#BF616A'
    nord.green = '#A3BE8C'
    nord.yellow = '#EBCB8B'
    nord.blue = '#81A1C1'
    nord.magenta = '#B48EAD'
    nord.cyan = '#88C0D0'
    nord.white = '#E5E9F0'
    nord.brightBlack = '#4C566A'
    nord.brightRed = '#BF616A'
    nord.brightGreen = '#A3BE8C'
    nord.brightYellow = '#EBCB8B'
    nord.brightBlue = '#81A1C1'
    nord.brightMagenta = '#B48EAD'
    nord.brightCyan = '#8FBCBB'
    nord.brightWhite = '#ECEFF4'

    const list: TerminalThemeProfile[] = []
    list.push(defaultDark)
    list.push(defaultLight)
    list.push(solarizedDark)
    list.push(solarizedLight)
    list.push(nord)
    return list
  }

  /** #RRGGBB 合法性校验。 */
  static isValidHex(value: string): boolean {
    return /^#[0-9A-Fa-f]{6}$/.test(value)
  }

  /** 由 background 亮度推导深浅归属（自定义主题用）。 */
  static deriveIsDark(background: string): boolean {
    const hex = background.replace('#', '')
    const r = parseInt(hex.substring(0, 2), 16)
    const g = parseInt(hex.substring(2, 4), 16)
    const b = parseInt(hex.substring(4, 6), 16)
    return (r * 299 + g * 587 + b * 114) / 1000 < 128
  }

  /** 生成传给 webview 的 xterm.js ITheme JSON（cursorAccent = background）。 */
  static toColorJson(profile: TerminalThemeProfile): string {
    const t = new XtermThemeJson()
    t.background = profile.background
    t.foreground = profile.foreground
    t.cursor = profile.cursor
    t.cursorAccent = profile.background
    t.selectionBackground = profile.selection
    t.black = profile.black
    t.red = profile.red
    t.green = profile.green
    t.yellow = profile.yellow
    t.blue = profile.blue
    t.magenta = profile.magenta
    t.cyan = profile.cyan
    t.white = profile.white
    t.brightBlack = profile.brightBlack
    t.brightRed = profile.brightRed
    t.brightGreen = profile.brightGreen
    t.brightYellow = profile.brightYellow
    t.brightBlue = profile.brightBlue
    t.brightMagenta = profile.brightMagenta
    t.brightCyan = profile.brightCyan
    t.brightWhite = profile.brightWhite
    return JSON.stringify(t)
  }

  /** 解析自定义主题持久化字符串（JSON 数组）。格式非法直接抛错，由 UI 层展示。 */
  static parseCustomThemes(json: string): TerminalThemeProfile[] {
    const parsed: object = JSON.parse(json) as object
    const arr = parsed as Array<object>
    const list: TerminalThemeProfile[] = []
    for (let i = 0; i < arr.length; i++) {
      const item = arr[i] as Record<string, string>
      const p = new TerminalThemeProfile()
      p.id = item['id'] as string
      p.name = item['name'] as string
      p.builtIn = false
      p.background = item['background'] as string
      p.isDark = TerminalThemes.deriveIsDark(p.background)
      p.foreground = item['foreground'] as string
      p.cursor = item['cursor'] as string
      p.selection = item['selection'] as string
      p.black = item['black'] as string
      p.red = item['red'] as string
      p.green = item['green'] as string
      p.yellow = item['yellow'] as string
      p.blue = item['blue'] as string
      p.magenta = item['magenta'] as string
      p.cyan = item['cyan'] as string
      p.white = item['white'] as string
      p.brightBlack = item['brightBlack'] as string
      p.brightRed = item['brightRed'] as string
      p.brightGreen = item['brightGreen'] as string
      p.brightYellow = item['brightYellow'] as string
      p.brightBlue = item['brightBlue'] as string
      p.brightMagenta = item['brightMagenta'] as string
      p.brightCyan = item['brightCyan'] as string
      p.brightWhite = item['brightWhite'] as string
      list.push(p)
    }
    return list
  }

  /** 自定义主题列表 → 持久化 JSON 字符串。 */
  static serializeCustomThemes(list: TerminalThemeProfile[]): string {
    return JSON.stringify(list)
  }

  /** 在内置 + 自定义列表中按 id 找档案。 */
  static findById(id: string, customList: TerminalThemeProfile[]): TerminalThemeProfile {
    for (let i = 0; i < TerminalThemes.BUILT_IN.length; i++) {
      if (TerminalThemes.BUILT_IN[i].id === id) {
        return TerminalThemes.BUILT_IN[i]
      }
    }
    for (let i = 0; i < customList.length; i++) {
      if (customList[i].id === id) {
        return customList[i]
      }
    }
    throw new Error(`terminal theme profile not found: ${id}`)
  }

  /**
   * terminalTheme 选择 → { terminalColorMode, terminalThemeJson }。
   * @param selection 'followApp' 或 profile id（存量 'system'/'dark'/'light' 由调用方先迁移）
   * @param appColorMode 应用当前深浅（'dark'/'light'），followApp 时使用
   */
  static resolve(selection: string, appColorMode: string, customThemesJson: string): TerminalThemeResolution {
    const resolution = new TerminalThemeResolution()
    const customList: TerminalThemeProfile[] =
      customThemesJson.length > 0 ? TerminalThemes.parseCustomThemes(customThemesJson) : []
    let profile: TerminalThemeProfile
    if (selection === 'followApp') {
      profile = TerminalThemes.findById(appColorMode === 'light' ? 'default-light' : 'default-dark', customList)
    } else {
      profile = TerminalThemes.findById(selection, customList)
    }
    const dark = profile.builtIn ? profile.isDark : TerminalThemes.deriveIsDark(profile.background)
    resolution.colorMode = dark ? 'dark' : 'light'
    resolution.themeJson = TerminalThemes.toColorJson(profile)
    resolution.themeName = profile.name
    return resolution
  }
}

/** 便捷别名：生成传给 webview 的 xterm.js theme JSON。 */
export function profilesToColorJson(profile: TerminalThemeProfile): string {
  return TerminalThemes.toColorJson(profile)
}
