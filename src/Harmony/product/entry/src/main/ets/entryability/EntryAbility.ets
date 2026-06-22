/**
 * @file EntryAbility.ets
 * @brief Application lifecycle management for CortexTerminal
 *
 * Initializes AppStorage with window dimensions, gateway URL, auth state,
 * keyboard height, color mode, and network status. Manages the main window
 * lifecycle, color mode changes, and pre-warms the Web engine for xterm.js.
 */
import { UIAbility, AbilityConstant, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit'
import { window, KeyboardAvoidMode } from '@kit.ArkUI'
import { webview } from '@kit.ArkWeb'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { bundleManager } from '@kit.AbilityKit'
import { AnalyticsService, AnalyticsEvent, CrashService } from '@rwecho/core'
import { DynamicsRouter } from 'routermodule'

const TAG = 'EntryAbility'
const DOMAIN = 0x0001

/**
 * Entry ability for CortexTerminal HarmonyOS app.
 * Manages app lifecycle and initializes global state.
 */
export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null
  private colorModeSyncing: boolean = false

  private syncColorMode(): void {
    if (this.colorModeSyncing) return
    this.colorModeSyncing = true
    try {
      const themeMode = AppStorage.get<string>('themeMode') ?? 'system'
      if (themeMode === 'system') {
        try {
          this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
        } catch (_e) {}
        const sysColorMode = this.context.config.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        const isDark = sysColorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        AppStorage.setOrCreate('colorMode', isDark ? 'dark' : 'light')
        this.applyStatusBar(isDark)
      } else {
        const colorMode = themeMode === 'dark'
          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        AppStorage.setOrCreate('colorMode', colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? 'dark' : 'light')
        this.applyStatusBar(colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
        try {
          this.context.getApplicationContext().setColorMode(colorMode)
        } catch (_e) {}
      }
    } finally {
      this.colorModeSyncing = false
    }
  }

  private applyStatusBar(isDark: boolean): void {
    if (this.mainWindow) {
      const forceDark = AppStorage.get<boolean>('terminalPageActive')
      this.mainWindow.setWindowSystemBarProperties({
        statusBarContentColor: (isDark || forceDark === true) ? '#ffffff' : '#000000'
      })
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate')

    this.syncColorMode()

    // Initialize AppStorage with default values (non-persistent)
    AppStorage.setOrCreate('authCompleted', false)
    let appVersion = '1.0.0'
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      appVersion = bundleInfo.versionName
    } catch (_e) {}
    AppStorage.setOrCreate('appVersion', appVersion)
    AppStorage.setOrCreate('currentBreakpoint', 'sm')
    AppStorage.setOrCreate('windowWidth', 0)
    AppStorage.setOrCreate('windowHeight', 0)
    AppStorage.setOrCreate('keyboardHeight', 0)
    AppStorage.setOrCreate('isKeyboardVisible', false)
    AppStorage.setOrCreate('bottomSafeArea', 0)
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

    // Initialize Analytics Kit and Crash Kit
    AnalyticsService.init()
    CrashService.init(this.context)
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageCreate')

    DynamicsRouter.routerInit({ libPrefix: '', mapPath: 'routerMap' }, this.context)

    // Set main window properties
    windowStage.getMainWindow().then((win: window.Window) => {
      this.mainWindow = win
      win.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED)
      // Apply status bar color based on current theme
      const isDark = AppStorage.get<string>('colorMode') !== 'light'
      this.applyStatusBar(isDark)

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

      // Get navigation bar (bottom avoid area) height for safe area padding
      try {
        const avoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
        AppStorage.setOrCreate('bottomSafeArea', px2vp(avoidArea.bottomRect.height))
      } catch (e) {
        AppStorage.setOrCreate('bottomSafeArea', 0)
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

      const uiContext = windowStage.getMainWindowSync().getUIContext()
      uiContext.runScopedTask(() => {
        // PersistentStorage must be called inside runScopedTask with UIContext to work
        PersistentStorage.persistProp('authToken', '')
        PersistentStorage.persistProp('isLoggedIn', false)
        PersistentStorage.persistProp('userInfo', '')
        PersistentStorage.persistProp('gatewayUrl', this.context.resourceManager.getStringByNameSync('gateway_url'))
        PersistentStorage.persistProp('themeMode', 'system')
        PersistentStorage.persistProp('language', 'en')
        PersistentStorage.persistProp('firstLaunchDone', false)

        hilog.info(DOMAIN, TAG, `[STARTUP] token=${AppStorage.get<string>('authToken') || '(empty)'} isLoggedIn=${AppStorage.get<boolean>('isLoggedIn') ?? false} language=${AppStorage.get<string>('language') || 'en'}`)

        // Fire APP_FIRST_LAUNCH on first-ever launch
        if (!AppStorage.get<boolean>('firstLaunchDone')) {
          AnalyticsService.onEvent(AnalyticsEvent.APP_FIRST_LAUNCH)
          AppStorage.setOrCreate<boolean>('firstLaunchDone', true)
        }
      })

      // RESIZE: compress page height when keyboard appears (like Android adjustResize)
      uiContext.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
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
    const themeMode = AppStorage.get<string>('themeMode') ?? 'system'
    if (themeMode === 'system' && newConfig.colorMode !== undefined) {
      const isDark = newConfig.colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      AppStorage.setOrCreate('colorMode', isDark ? 'dark' : 'light')
      this.applyStatusBar(isDark)
    } else {
      this.syncColorMode()
    }
  }
}
