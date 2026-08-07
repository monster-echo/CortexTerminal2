import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // 托盘应用：关闭最后一个窗口不退出（Dart 侧 window_manager setPreventClose 会把关闭转成
  // 隐藏到托盘；这里兜底保证即使窗口真被关掉，App 也不终止，托盘菜单还能重新显示窗口）。
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
