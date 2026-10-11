import { common } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { TerminalChrome } from '../model/TerminalThemeProfile'

/** Resolve both system bars from the currently visible page's theme. */
export class SystemBarTheme {
  static apply(context: common.UIAbilityContext): void {
    window.getLastWindow(context).then((win: window.Window) => {
      // Resolve after the asynchronous lookup so a departing page cannot apply stale colors.
      const terminal = AppStorage.get<boolean>('terminalPageActive') === true
      const chrome = terminal
        ? TerminalChrome.fromJson(AppStorage.get<string>('terminalChromeJson') ?? '') : null
      const background = chrome ? chrome.background
        : SystemBarTheme.resourceColor(context, $r('app.color.terminal_background').id)
      const foreground = chrome ? chrome.onSurface
        : SystemBarTheme.resourceColor(context, $r('app.color.terminal_text').id)
      return win.setWindowSystemBarProperties({
        statusBarColor: background,
        statusBarContentColor: foreground,
        navigationBarColor: background,
        navigationBarContentColor: foreground
      })
    }).catch((e: Error) => console.warn('[SystemBarTheme] ' + e.message))
  }

  private static resourceColor(context: common.UIAbilityContext, id: number): string {
    return '#' + (context.resourceManager.getColorSync(id) >>> 0).toString(16).padStart(8, '0')
  }
}
