# 云枢终端 (Corterm)

本机桌面连接面板（macOS / Windows / Linux）——装在用户自己的电脑上，让手机上的云枢终端 App 可以远程访问这台电脑。用 UI 替代 `corterm` 命令行。

## 功能

- **概览面板**（Tailscale 式单列）：连接状态 hero → 我的计算机 → 此设备（设备 ID / 服务版本 / 网关 / 运行时长）→ 功能入口。
- **诊断**：`corterm doctor` 全项检查（✓/✗ + 计数）。
- **更新**：`corterm update --check` 查最新版，一键 `update --json` 流式更新（阶段 + 重启）。
- **认证**：设备码登录（显示链接 + 二维码 + 等待轮询）/ 登出。
- **设置**：corterm 二进制路径覆盖、主题（系统/浅/深）、语言（zh/en）。

> 命名说明：对用户统一叫「云枢终端 / Corterm」，视角是"这台电脑"（此设备、我的计算机）；
> "worker" 只保留在代码与协议层（Gateway 角色名），不再出现在任何界面文案里。

## 通信方式

应用通过 `Process` 调用本机 `corterm` 二进制，解析其 `--json` 输出。**不加** daemon 控制 API、**不走** gateway。二进制解析顺序：

1. `$CORTERM_HOME` / `$CORTEX_TERMINAL_HOME`
2. 默认 `~/.corterm/corterm`（内置 worker 自动装到这，GUI 启动不继承 shell PATH，这是最可靠来源）
3. PATH 查找（`which`/`where`，尽力而为）

> corterm 需带 `--json` 支持（≥ 0.5.16）。旧版本会被内置 worker 自动覆盖修复。

## worker 托管（谁拉起守护进程）

- **macOS**：App 直接托管 worker 子进程（`core/worker_process_controller.dart`）。裸调用 `corterm`（无参数）= 前台守护进程，App 监控退出、封顶退避重启、日志落 `~/.corterm/corterm.log`。启动时一次性迁移旧 LaunchAgent（unload + 删 plist）。**托盘退出 = 停止远程访问**；开机自启 App 时随之拉起 worker。
- **Windows**：计划任务（`corterm start` → schtasks），托盘退出不影响。
- **Linux**：systemd user 服务（`corterm start` → systemctl --user），托盘退出不影响。
- `corterm start/stop/restart` CLI 语义不变（无头 install.sh 用户不受影响）；App 在 macOS 上不再调用它们。`corterm update --no-service-restart` 供 App 托管模式使用（旧 worker 不认识该选项时自动探测降级）。

## 本地开发

```bash
flutter analyze
flutter test
tool/fetch_worker.sh         # 拉最新 worker release 进 assets/bin（需 gh；代理见文件头注释）
flutter run -d macos        # 本机只有 macOS 桌面可验证
```

`test/real_binary_e2e_test.dart` 用 `/tmp/corterm-test` 下发布的真实 corterm 走一遍解析（二进制缺失时自动跳过）——本地验证发布后二进制与 App 的对接。

## 目录

```
lib/
  theme/      # CLAUDE.md 设计 token → Material 主题（dark + light）
  l10n/       # zh/en 极简文案
  core/       # binary_locator / corterm_service / worker_process_controller / models / settings
  screens/    # dashboard(概览面板) / auth / sessions / session_detail / doctor / update / agent_tools / settings / about
  widgets/    # app_bar / list_group / error_banner / primary_button / section_header / states
tool/
  fetch_worker.sh  # 本地拉最新 worker release 进 assets/bin
```
