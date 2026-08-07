# Corterm Worker UI

Worker 本机桌面控制面板（macOS / Windows / Linux）——用 UI 替代 `corterm`/`cortap` 命令行。

## 功能

- **状态**：版本 / PID / 运行时长 / 网关 / Worker ID / 认证状态 / 网关信息（含更新提示）/ worker 列表。
- **诊断**：`corterm doctor` 全项检查（✓/✗ + 计数）。
- **更新**：`corterm update --check` 查最新版，一键 `update --json` 流式更新（阶段 + 重启）。
- **服务**：start / stop / restart。
- **认证**：设备码登录（显示链接 + 二维码 + 等待轮询）/ 登出。
- **会话**：`cortap sessions` 列表 + 实时日志查看器（轮询 `cortap events --json`，自动滚底，可暂停）。
- **设置**：corterm 二进制路径覆盖、主题（系统/浅/深）、语言（zh/en）。

## 通信方式

应用通过 `Process` 调用本机 `corterm`/`cortap` 二进制，解析其 `--json` 输出。**不加** daemon 控制 API、**不走** gateway。二进制解析顺序：

1. 设置里手动指定的路径
2. `$CORTERM_HOME` / `$CORTEX_TERMINAL_HOME`
3. 默认 `~/.corterm/corterm`（GUI 启动不继承 shell PATH，这是最可靠来源）
4. PATH 查找（`which`/`where`，尽力而为）

> corterm 需带 `--json` 支持（≥ 0.5.14）。旧版本会显示错误 banner —— 在「设置」里把路径指到新版二进制即可。

## 开发

```bash
flutter analyze
flutter test
flutter run -d macos        # 本机只有 macOS 桌面可验证
```

`test/real_binary_e2e_test.dart` 用 `/tmp/corterm-test` 下发布的真实 corterm/cortap 走一遍解析（二进制缺失时自动跳过）——本地验证发布后二进制与 App 的对接。

## 目录

```
lib/
  theme/      # CLAUDE.md 设计 token → Material 主题（dark + light）
  l10n/       # zh/en 极简文案
  core/       # binary_locator / corterm_service / models / settings
  screens/    # dashboard / doctor / update / service / auth / sessions / settings / terminal(M2 stub)
  widgets/    # status_card / error_banner / primary_button / section_header
```
