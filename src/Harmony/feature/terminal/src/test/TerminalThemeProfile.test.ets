import { describe, it, expect } from '@ohos/hypium';
import { TerminalThemes, TerminalThemeProfile, TerminalChrome } from '@rwecho/core';

function makeCustomProfile(): TerminalThemeProfile {
  const p = new TerminalThemeProfile()
  p.id = 'custom-test-1'
  p.name = 'Mine'
  p.builtIn = false
  p.background = '#112233'
  p.isDark = true
  p.foreground = '#EEEEEE'
  p.cursor = '#EEEEEE'
  p.selection = '#334455'
  p.black = '#000000'
  p.red = '#FF0000'
  p.green = '#00FF00'
  p.yellow = '#FFFF00'
  p.blue = '#0000FF'
  p.magenta = '#FF00FF'
  p.cyan = '#00FFFF'
  p.white = '#FFFFFF'
  p.brightBlack = '#808080'
  p.brightRed = '#FF8080'
  p.brightGreen = '#80FF80'
  p.brightYellow = '#FFFF80'
  p.brightBlue = '#8080FF'
  p.brightMagenta = '#FF80FF'
  p.brightCyan = '#80FFFF'
  p.brightWhite = '#FFFFFF'
  return p
}

export default function terminalThemeProfileTest() {
  describe('terminalThemeProfileTest', () => {
    it('builtIn_presets_exist', 0, () => {
      const ids: string[] = TerminalThemes.BUILT_IN.map((p: TerminalThemeProfile): string => p.id)
      expect(ids.length).assertEqual(5)
      expect(ids.includes('default-dark')).assertTrue()
      expect(ids.includes('default-light')).assertTrue()
      expect(ids.includes('solarized-dark')).assertTrue()
      expect(ids.includes('solarized-light')).assertTrue()
      expect(ids.includes('nord')).assertTrue()
    })

    it('builtIn_colors_are_valid_hex', 0, () => {
      for (let i = 0; i < TerminalThemes.BUILT_IN.length; i++) {
        const p: TerminalThemeProfile = TerminalThemes.BUILT_IN[i]
        expect(TerminalThemes.isValidHex(p.background)).assertTrue()
        expect(TerminalThemes.isValidHex(p.foreground)).assertTrue()
        expect(TerminalThemes.isValidHex(p.cursor)).assertTrue()
        expect(TerminalThemes.isValidHex(p.selection)).assertTrue()
        expect(TerminalThemes.isValidHex(p.brightWhite)).assertTrue()
      }
    })

    it('isValidHex_rejects_bad_input', 0, () => {
      expect(TerminalThemes.isValidHex('#FFFFFF')).assertTrue()
      expect(TerminalThemes.isValidHex('#FFF')).assertFalse()
      expect(TerminalThemes.isValidHex('FFFFFF')).assertFalse()
      expect(TerminalThemes.isValidHex('#GGHHII')).assertFalse()
    })

    it('deriveIsDark', 0, () => {
      expect(TerminalThemes.deriveIsDark('#121414')).assertTrue()
      expect(TerminalThemes.deriveIsDark('#FAFAFA')).assertFalse()
    })

    it('toColorJson_mapsXtermKeys', 0, () => {
      const p: TerminalThemeProfile = TerminalThemes.findById('default-dark', [])
      const json: string = TerminalThemes.toColorJson(p)
      const obj: Record<string, string> = JSON.parse(json) as Record<string, string>
      expect(obj['background']).assertEqual(p.background)
      expect(obj['foreground']).assertEqual(p.foreground)
      // cursorAccent 必须等于 background（光标填充色）
      expect(obj['cursorAccent']).assertEqual(p.background)
      // selection 字段映射为 xterm 的 selectionBackground
      expect(obj['selectionBackground']).assertEqual(p.selection)
      expect(obj['brightWhite']).assertEqual(p.brightWhite)
    })

    it('customThemes_roundtrip', 0, () => {
      const json = TerminalThemes.serializeCustomThemes([makeCustomProfile()])
      const back: TerminalThemeProfile[] = TerminalThemes.parseCustomThemes(json)
      expect(back.length).assertEqual(1)
      expect(back[0].id).assertEqual('custom-test-1')
      expect(back[0].background).assertEqual('#112233')
      // 自定义主题的 isDark 由 background 亮度重新推导
      expect(back[0].isDark).assertTrue()
    })

    it('findById_unknown_throws', 0, () => {
      let threw = false
      try {
        TerminalThemes.findById('no-such-id', [])
      } catch (err) {
        threw = true
      }
      expect(threw).assertTrue()
    })

    it('resolve_followApp', 0, () => {
      const dark = TerminalThemes.resolve('followApp', 'dark', '[]')
      expect(dark.themeName).assertEqual('terminalTheme.builtin.defaultDark')
      expect(dark.colorMode).assertEqual('dark')
      const light = TerminalThemes.resolve('followApp', 'light', '[]')
      expect(light.themeName).assertEqual('terminalTheme.builtin.defaultLight')
      expect(light.colorMode).assertEqual('light')
    })

    it('resolve_specificId_and_custom', 0, () => {
      const nord = TerminalThemes.resolve('nord', 'light', '[]')
      expect(nord.themeName).assertEqual('terminalTheme.builtin.nord')
      expect(nord.colorMode).assertEqual('dark')

      const customJson = TerminalThemes.serializeCustomThemes([makeCustomProfile()])
      const custom = TerminalThemes.resolve('custom-test-1', 'dark', customJson)
      expect(custom.themeName).assertEqual('Mine')
      expect(custom.colorMode).assertEqual('dark')
    })

    it('resolve_unknownId_throws', 0, () => {
      let threw = false
      try {
        TerminalThemes.resolve('no-such-id', 'dark', '[]')
      } catch (err) {
        threw = true
      }
      expect(threw).assertTrue()
    })

    it('blend_basic', 0, () => {
      expect(TerminalThemes.blend('#000000', '#FFFFFF', 0.5)).assertEqual('#808080')
      expect(TerminalThemes.blend('#000000', '#FFFFFF', 0)).assertEqual('#000000')
      expect(TerminalThemes.blend('#000000', '#FFFFFF', 1)).assertEqual('#FFFFFF')
    })

    it('contrastRatio_blackWhite', 0, () => {
      expect(TerminalThemes.contrastRatio('#000000', '#FFFFFF')).assertEqual(21)
    })

    it('blend_invalidHex_throws', 0, () => {
      let threw = false
      try {
        TerminalThemes.blend('#12345', '#FFFFFF', 0.5)
      } catch (err) {
        threw = true
      }
      expect(threw).assertTrue()
    })

    it('deriveChrome_allColorsValidHex', 0, () => {
      for (let i = 0; i < TerminalThemes.BUILT_IN.length; i++) {
        const chrome: TerminalChrome = TerminalThemes.deriveChrome(TerminalThemes.BUILT_IN[i])
        expect(TerminalThemes.isValidHex(chrome.background)).assertTrue()
        expect(TerminalThemes.isValidHex(chrome.surface)).assertTrue()
        expect(TerminalThemes.isValidHex(chrome.surfaceHigh)).assertTrue()
        expect(TerminalThemes.isValidHex(chrome.onSurface)).assertTrue()
        expect(TerminalThemes.isValidHex(chrome.onSurfaceVariant)).assertTrue()
        expect(TerminalThemes.isValidHex(chrome.outlineVariant)).assertTrue()
        expect(TerminalThemes.isValidHex(chrome.accent)).assertTrue()
        expect(TerminalThemes.isValidHex(chrome.accentContainer)).assertTrue()
        expect(TerminalThemes.isValidHex(chrome.onAccentContainer)).assertTrue()
      }
    })

    it('deriveChrome_contrastFloors', 0, () => {
      for (let i = 0; i < TerminalThemes.BUILT_IN.length; i++) {
        const profile: TerminalThemeProfile = TerminalThemes.BUILT_IN[i]
        const chrome: TerminalChrome = TerminalThemes.deriveChrome(profile)
        expect(TerminalThemes.contrastRatio(chrome.onSurface, chrome.background) >= 4.5).assertTrue()
        expect(TerminalThemes.contrastRatio(chrome.onSurfaceVariant, chrome.background) >= 4.5).assertTrue()
        expect(TerminalThemes.contrastRatio(chrome.accent, chrome.background) >= 3).assertTrue()
        expect(TerminalThemes.contrastRatio(chrome.onAccentContainer, chrome.accentContainer) >= 3).assertTrue()
      }
    })

    it('deriveChrome_matchesProfileDarkness', 0, () => {
      const darkChrome = TerminalThemes.deriveChrome(TerminalThemes.BUILT_IN[0])
      expect(darkChrome.isDark).assertTrue()
      const lightProfile = TerminalThemes.findById('default-light', [])
      const lightChrome = TerminalThemes.deriveChrome(lightProfile)
      expect(lightChrome.isDark).assertFalse()
      expect(lightChrome.background).assertEqual(lightProfile.background)
    })

    it('chromeJson_roundtrip', 0, () => {
      const resolution = TerminalThemes.resolve('nord', 'dark', '[]')
      expect(resolution.chromeJson.length > 0).assertTrue()
      const chrome = TerminalChrome.fromJson(resolution.chromeJson)
      expect(chrome.background).assertEqual(TerminalThemes.findById('nord', []).background)
      expect(chrome.isDark).assertTrue()
    })

    it('fromJson_emptyJson_throws', 0, () => {
      let threw = false
      try {
        TerminalChrome.fromJson('')
      } catch (err) {
        threw = true
      }
      expect(threw).assertTrue()
    })
  })
}
