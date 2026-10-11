# HarmonyOS 导航检查 — 2026-10-11

## 范围与规则

检查 `src/Harmony` 的全部 25 个 RouteName、Index 页面映射、各 feature 的 push / replace / pop / 返回拦截和异步跳转。工作区列表是应用首页；业务子页压栈进入，返回恢复来源页面。登录、退出登录重置认证边界。Session 切换与 fork 替换当前 Session，保留原来的父页面。

## 修复的问题

| 位置 | 原问题 | 修正 |
|---|---|---|
| TerminalPage.handleBack | 用首页替换 Session，跳过工作区并在栈中制造重复首页 | pop 回来源；仅孤立 Session 无父页面时回首页 |
| TerminalPage expired / exited | 延迟 2 秒强制替换首页，离页后旧计时器仍可能改变导航 | 返回来源；离页清除计时器，执行前核对栈顶路由和 sessionId |
| WorkerDetailPage | 恢复、新建、新建工作区会话共 3 个入口使用未注册 `TerminalSession`，只写旧 AppStorage 参数 | 使用 `RouteName.TERMINAL_SESSION` 和 `TerminalNavParam` |
| worker/List | 是否允许返回由是否带 param 决定，无参压栈会被视为顶层页面 | 电脑列表统一为可返回子页 |
| ActivateWorkerPage / EnterActivationCodePage | 激活成功调用登录的 navigateHome，跳首页 | 结束激活流程，返回流程之前的来源页；延迟回调核对当前路由 |
| AuthService.navigateHome | 仅 replace 顶部，可能保留认证前的历史页面 | 登录成功清栈后建立首页 |
| AccountSecurityPage | 退出登录/注销后，与 Index 认证监听重复替换登录页 | 统一由 Index 认证监听清栈跳转 |
| 首页侧边栏 | ShellScaffold 内未连接到 NavDestination 的返回方法无法关闭抽屉 | 首页 NavDestination 系统返回优先关闭侧边栏 |
| 旧 AuthComponent | 已登录时激活页面仍被无条件禁止系统返回 | 仅未登录状态拦截返回 |

上一轮已修正工作区详情和我的为可返回子页；本轮继续保留。

## 模拟器复查

Mate 60，HarmonyOS 6.0.2 API 22，1216×2688。使用真实现有会话，未发送终端命令。

- 工作区 → Session → 标题栏返回：回到原工作区。
- 工作区 → Session → 系统返回：回到原工作区。
- CortexTerminal2 工作区 → Session → 会话切换器切换另一个会话 → 返回：仍回到进入时的 CortexTerminal2 工作区。
- 未分组 → Session → 返回：回到未分组列表。
- 工作区 → 文件 → docs 子目录 → 系统返回：先回文件根目录；再返回工作区。
- 首页侧边栏 → 系统返回：关闭侧边栏，保留首页。
- 首页 → 计算机 → 系统返回：回首页。
- 首页 → 连接计算机 → 返回：回首页。
- 我的 → 设置 → 终端主题 → 系统返回：回设置；标题栏返回回我的。
- 我的 → 会员 → 兑换码 → 系统返回：回会员。
- 会员 → 服务条款 Web → 返回：回会员；再返回我的。
- 我的 → 账号安全 → 修改密码 → 返回：回账号安全；再返回我的。
- 我的 → 联系客服 / 意见反馈 / 关于我们 → 返回：均回我的。
- 我的 → 编辑资料 Sheet → 系统返回：只关闭 Sheet，保留我的。

证据：`review/nav-session-back-workspace.jpeg`、`review/nav-system-back-workspace.jpeg`、`review/nav-switched-session-back-workspace.jpeg`、`review/nav-session-back-ungrouped.jpeg`、`review/nav-drawer-back-closed.jpeg`、`review/nav-redeem-back-membership.jpeg`。静态路由检查输出：`review/navigation-route-audit.json`，25 个路由均有 Index 映射，未发现未知字面量跳转目标。

## 验证边界

Hvigor assembleHap 成功，最新构建耗时 7.140 秒。`git diff --check` 通过。

本次进行静态导航审查和模拟器交互回归，没有运行完整单元/集成测试。未实际触发过期、进程退出、登录/退出登录、激活成功、电脑详情新建/fork、购买、兑换提交、注销账号等会修改真实状态的流程。相关返回分支已审查并通过编译。电脑详情、手动激活码、Referral、独立 Preferences、图片预览等已注册但本轮未由可见入口逐一运行的页面，只完成代码检查。
