/**
 * @file EntryAbility.ets
 * @brief Application lifecycle management for CortexTerminal
 *
 * Initializes AppStorage with window dimensions, gateway URL, auth state,
 * keyboard height, color mode, and network status. Manages the main window
 * lifecycle, color mode changes, and pre-warms the Web engine for xterm.js.
 */
import { UIAbility, AbilityConstant, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AppConstants } from '@rwecho/core'

const TAG = 'EntryAbility'
const DOMAIN = 0x0001

/**
 * Entry ability for CortexTerminal HarmonyOS app.
 * Manages app lifecycle and initializes global state.
 */
export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate')

    PersistentStorage.persistProp('authToken', '')
    PersistentStorage.persistProp('refreshToken', '')
    PersistentStorage.persistProp('isLoggedIn', false)
    PersistentStorage.persistProp('userInfo', '')
    PersistentStorage.persistProp('gatewayUrl', AppConstants.DEFAULT_GATEWAY_URL)
    PersistentStorage.persistProp('themeMode', 'system')
    PersistentStorage.persistProp('language', 'en')

    // Initialize AppStorage with default values
    AppStorage.setOrCreate('authCompleted', false)
    AppStorage.setOrCreate('appVersion', '1.0.0')
    AppStorage.setOrCreate('currentBreakpoint', 'sm')
    AppStorage.setOrCreate('windowWidth', 0)
    AppStorage.setOrCreate('windowHeight', 0)
    AppStorage.setOrCreate('keyboardHeight', 0)
    AppStorage.setOrCreate('isKeyboardVisible', false)
    AppStorage.setOrCreate('colorMode', 'light')
    AppStorage.setOrCreate('isNetworkAvailable', true)
    AppStorage.setOrCreate('networkType', 'unknown')
    AppStorage.setOrCreate('terminalState', 'Disconnected')
    AppStorage.setOrCreate('navigateTo', '')
    AppStorage.setOrCreate('drawerVisible', false)
    AppStorage.setOrCreate('terminalNavStack', null)
    AppStorage.setOrCreate('workerNavStack', null)
    AppStorage.setOrCreate('authNavStack', null)

    // Pre-warm the WebView engine for faster xterm.js loading
    try {
      webview.WebviewController.initializeWebEngine()
      hilog.info(DOMAIN, TAG, 'WebView engine pre-warmed')
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `Failed to pre-warm WebView engine: ${(e as Error).message}`)
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageCreate')

    // Set main window to full screen immersive mode
    windowStage.getMainWindow().then((win: window.Window) => {
      this.mainWindow = win

      // Get initial window dimensions
      const properties = win.getWindowProperties()
      const rect = properties.windowRect
      AppStorage.setOrCreate('windowWidth', rect.width)
      AppStorage.setOrCreate('windowHeight', rect.height)

      // Track window size changes for responsive breakpoints
      win.on('windowSizeChange', (data: window.Size) => {
        AppStorage.setOrCreate('windowWidth', data.width)
        AppStorage.setOrCreate('windowHeight', data.height)

        let breakpoint = 'sm'
        if (data.width >= 840) {
          breakpoint = 'lg'
        } else if (data.width >= 600) {
          breakpoint = 'md'
        }
        AppStorage.setOrCreate('currentBreakpoint', breakpoint)
      })

      // Monitor keyboard height changes for virtual key bar adjustment
      try {
        win.on('keyboardHeightChange', (height: number) => {
          AppStorage.setOrCreate('keyboardHeight', height)
          AppStorage.setOrCreate('isKeyboardVisible', height > 0)
        })
      } catch (e) {
        hilog.warn(DOMAIN, TAG, `keyboard height monitoring not supported: ${(e as Error).message}`)
      }

      // Color mode changes are tracked via onConfigurationUpdate
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, `Failed to get main window: ${err.message}`)
    })

    // Load the main page
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, `Failed to load content: ${JSON.stringify(err)}`)
        return
      }
      hilog.info(DOMAIN, TAG, 'Loaded pages/Index')
    })
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy')
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground')
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground')
  }

  /**
   * Handle configuration changes such as color mode.
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, `onConfigurationUpdate: ${JSON.stringify(newConfig)}`)

    if (newConfig.colorMode !== undefined) {
      const systemColorMode = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? 'dark' : 'light'
      AppStorage.setOrCreate('colorMode', systemColorMode)
    }

    // Respect user theme preference override
    const themeMode = AppStorage.get<string>('themeMode') ?? 'system'
    if (themeMode !== 'system') {
      AppStorage.setOrCreate('colorMode', themeMode)
    }
  }
}
