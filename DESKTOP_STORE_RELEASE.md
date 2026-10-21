# 云枢终端桌面商店发布评估

## macOS App Store / Microsoft Store 上架评估（2026-10-20）

当前 `ui-v*` 工作流是 GitHub Release 直发流程，生成未商店签名的 DMG 和 Inno Setup EXE。它们适用于官网/GitHub 下载，不是商店提交包；当前仓库也没有 App Store Connect 或 Microsoft Store 上传步骤。

### 结论与优先级

建议先继续通过 GitHub Release/官网发布，补上 macOS Developer ID 签名与 notarization、Windows Authenticode 签名；再启动独立的商店适配评估。Windows 商店路径较短，可增加 MSIX/Partner Center 流程。macOS App Store 路径当前被应用架构阻塞，不能只改签名配置后提交。

| 渠道 | 当前状态 | 下一步 |
|---|---|---|
| macOS 官网/GitHub | 已有 `.app` → `.dmg`，未见 CI 签名/公证 | 使用 Developer ID Application 签名、启用 hardened runtime、提交 Apple notarization、staple 后再分发；在干净 Mac 验证 Gatekeeper |
| Mac App Store | 不可直接提交 | 需要商店专用沙盒架构，见下方阻塞项；完成后用 App Store Connect/TestFlight 验证与提交 |
| Windows 官网/GitHub | 已有 Inno Setup 用户级安装器 | 配置受信任的 Authenticode 证书并签署安装器/可执行文件；干净 Windows 验证 SmartScreen 与升级卸载 |
| Microsoft Store | 尚无 MSIX/Partner Center 配置 | 配置稳定 Package Identity/Publisher，制作 Store 专用 MSIX，Partner Center 预留应用并通过认证/Flighting 后提交 |

### Mac App Store 的产品级阻塞

- `macos/Runner/Release.entitlements` 当前是空字典，Xcode Release 构建使用它；Debug entitlement 注释也明确说明应用依赖非沙盒权限。Mac App Store 要求启用 App Sandbox。
- `lib/core/binary_locator.dart` 把随包内置的 `corterm` 安装到 `~/.corterm`，并执行 chmod；`main.dart` 和 `corterm_service.dart` 启动 `corterm` 子进程、安装/启动守护服务。普通沙盒应用不能照此写用户主目录并任意管理外部可执行文件/守护进程。
- 必须先选定可行的商店产品模型：例如将 worker 作为 App 内受沙盒约束的子进程、随容器安装并通过 App Group 容器通信；或将 worker 安装/生命周期管理拆成独立、用户显式授权的组件并评估商店规则。还需验证 worker 的本地网络监听、登录项、自动更新和终端/agent 工具调用是否能在沙盒权限下成立。不能假设单纯加入网络 entitlement 就解决。
- 商店版应与直接分发版分开 target/configuration 和更新策略。当前 `self_updater` 指向 GitHub Release 下载，不能原样用于商店管理的应用更新。

### 执行清单

1. **发布身份**：确认 Apple Developer Program/App Store Connect 的目标团队、应用记录、隐私政策/支持 URL、SKU、年龄分级、商店截图及审核联系信息；确认 Microsoft Partner Center 账号、保留应用名和 Publisher。
2. **Windows 商店原型**：在固定 Package Identity/Publisher 后用 MSIX 打包现有 Flutter Windows Release，逐项验证托盘、开机启动、登录、安装 worker、计划任务/服务、自动更新、卸载清理。若功能依赖不被商店安装模型接受，改为 Store 版 MSIX 不自动安装 worker，提供经用户确认的兼容安装引导，或先只上架独立 UI。
3. **macOS 架构验证**：先做最小 sandbox spike，验证子进程、worker 路径、网络/本地监听、login item、更新、设置文件和终端探测。验证不过就暂停 Mac App Store 目标，先走 Developer ID + notarized DMG 官网分发。
4. **签名 CI**：签名私钥/证书只放加密 CI secret 或安全签名服务；绝不提交仓库。macOS 直发包按 Developer ID + hardened runtime + notarization + stapling；Windows 直发安装器和二进制用 Authenticode。商店包分别由 Apple/Microsoft 流程签名/认证，勿混用同一个制品。
5. **验证与递交**：每个平台用干净用户/虚拟机安装、启动、登录、更新、卸载；先 TestFlight/Store flight 小范围试发，修完审核或安装问题，再完成商店元数据和正式提交。发布前 bump 版本，检查安装器、隐私说明、第三方组件清单和所有商店截图。

### 已落地：Windows Store MSIX 原型工作流

- `src/Flutter/worker_ui/pubspec.yaml` 增加 `msix` 开发依赖；商店 identity 不写入仓库。
- `.github/workflows/worker-ui-store-msix.yml` 提供手动触发的 Windows runner：构建 worker 与 Flutter Windows app，注入 `STORE_BUILD=true` 与 `WINDOWS_STORE_BUILD=true`，禁用 GitHub 的 UI/worker 更新路径，并使用 `msix:create --store` 产出未签名 MSIX artifact，由 Partner Center 上载后签名。
- 运行前需在 GitHub Actions Variables 配置 `MS_STORE_IDENTITY_NAME`、`MS_STORE_PUBLISHER`、`MS_STORE_PUBLISHER_DISPLAY_NAME`。取值必须逐字来自 Partner Center 产品身份页。触发输入版本必须为四段数字，例如 `0.2.1.0`。
- 当前 workflow 是可审阅原型，必须先在 Windows runner 实际成功构建并从 Partner Center 测试提交，再视作可发布链路。此 Mac 环境没有 Windows SDK，不能本地构建、安装或验证 MSIX。
- `STORE_BUILD=true` 会停止检查/运行 GitHub 的 UI 自更新安装器路径。Microsoft Store 应用本身由商店更新；Windows 商店版暂时关闭 worker 自更新，后续若要恢复需设计与商店版本配套的 worker 更新通道。
- MSIX 当前声明 `runFullTrust`（桌面 Flutter 桌面桥）；Partner Center 需按产品身份和包内容审核。此原型并未证明商店接受后台 worker/任务计划行为，也未证明卸载清理符合预期。

### 本机环境检查记录

本次检查到 Apple Developer ID Application 与 Apple Distribution 身份在本机 Keychain 可见，Flutter 和 Xcode 命令可用，`gh` 已登录 `monster-echo`。这只证明本机有签名身份/工具，不证明证书私钥可用于 CI、App Store Connect 权限有效或应用已在商店预留。当前环境未发现 `msstore`/`makeappx` CLI，且仓库没有 MSIX manifest。不要在此文档或 Git 中记录证书密码、API 私钥或 Partner Center 凭据。
