# 云枢终端：iPhone Duo 适配

2026-10-25。实现位于 `src/Flutter/corterm_mobile`。

## 依据

- [Apple — Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/)：侧边栏利用额外宽度，保留内容高度；当前页面工具和全局标签在同一侧边区域分组排列。
- [Apple — Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)：按当前可用空间、系统侧边位置、安全区和保留区域调整，折叠与旋转保持任务连续。
- 本地 MV2：`/Users/echo/workspace/V2ex.Maui2/app/lib/app/app.dart`、`app/lib/features/shell/presentation/app_shell.dart`、`app/lib/ui/components/mv2_page_scaffold.dart`，以及其 `vendor/adaptive_platform_ui`。已在同一 Duo 模拟器打开 MV2，观察真实原生工具和标签胶囊。

## 从 MV2 学到的实现结构

1. `FoldableProvider` 读取当前视图的保留区域。保持默认桥接模式，不把折叠区全局注入 `MediaQuery.displayFeatures`，避免标准弹窗被意外限制在半屏。
2. 在路由上方放一个 `AdaptiveToolbarHost`。宿主持有固定的原生玻璃胶囊；页面通过 `ToolbarRegistry` 注册标题、返回与操作。
3. `verticalBarEdge`、不对称安全区、系统摄像头/状态保留区域决定栏的位置。侧边控制使用系统留出的区域，不能再从内容里额外扣一条 48pt。
4. Toolbar 负责当前页面，Tab bar 负责一级目的地。标签由导航壳持有，详情页仍能使用同一组标签；各标签保存独立导航栈。
5. 工具过多时按可用高度收进菜单，标签保持可见。模态打开时底下的栏停止接收操作。
6. 内屏直立恢复水平栏。内容双栏是独立布局决定，不能把双栏目录当作 Duo 工具栏。

## 在云枢终端中的设计

| 层级 | 内容 |
|---|---|
| 全局标签 | 工作区、电脑、我的。三个 `StatefulShellBranch` 保留各自页面和导航状态 |
| 页面工具 | 首页新建工作区；工作区菜单；文件连接方式/新建/刷新；终端文件、键盘、更多 |
| 内容导航 | 宽度足够时左侧工作区及会话列表，右侧当前内容。电脑与账户分支使用完整内容宽度 |
| 表单与模态 | 顶部按自然顺序排列；长内容滚动；限制模态宽高，保留原页面上下文 |

宽屏导航预算为 280pt 列表和至少约 440pt 主内容；760pt 是内容断点。有效竖向折叠区上报时按该区安排两栏；两边不足时收起目录。尺寸变化不重建终端输入视图，终端连接 epoch 改变时才重建。

## 实施

- Flutter 使用该包的原生 UIKit 玻璃胶囊和系统几何桥接；这不是把整个应用改成 `UINavigationController` / `UITabBarController`，也不能声称获得系统容器的全部自动行为。
- 复用 MV2 已修改的 MIT `adaptive_platform_ui`，保留 LICENSE 和来源说明；不是直接采用上游未经 Duo 修改的版本。
- `AdaptiveWindow` 组装 fold provider 和全局 toolbar host。
- `AdaptivePageScaffold` 将现有 Material 页面标题/动作注册到宿主；Material 页面保留原正文和业务逻辑。
- `AdaptiveWorkspaceShell` 持有全局标签及宽屏目录；`router.dart` 使用三个独立分支。
- 删除首版自建 Swift 几何桥接及内容内侧操作列，恢复标准 Flutter view controller。
- 使用 iOS 27.1 SDK 构建，解决先前 26.5 安装包在内屏居中显示的兼容模式。

## 证据边界

首版已验证真实终端命令、文件页、键盘和多姿态；这些截图不能证明本次 MV2 方案已经验收。本次原生栏的构建和运行证据单独记录，最终交付需区分代码完成、模拟器观察和真机验证。未发布商店版本。
