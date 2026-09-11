import 'package:xterm/xterm.dart';

/// 单个 session 的连接状态（映射 §13 的四色圆点由 UI 完成）。
enum TerminalConnState {
  /// 已打开但未附着（LRU 被挤出后的静止态）。
  idle,

  /// 建立连接中。
  connecting,

  /// 回放 scrollback 快照中。
  replaying,

  /// 附着完成，可输入。
  live,

  /// 断线重连中（自动退避重试）。
  reconnecting,

  /// 会话已退出（exited 帧或 terminate）。
  exited,

  /// 服务端报错（session-not-found 等）。
  error,
}

/// 单个 session 的终端状态（§42：按 session 独立保存 buffer / 连接 / 输入）。
class SessionTerminalState {
  SessionTerminalState({
    required this.terminal,
    required this.epoch,
    this.connState = TerminalConnState.connecting,
    this.errorMessage,
    this.rttMs,
    this.exitReason,
    this.pendingColumns,
    this.pendingRows,
  });

  /// 每次 reattach 自增；UI 用它作为 TerminalView 的 Key 强制重建（回放前重置 buffer）。
  final int epoch;
  final Terminal terminal;
  TerminalConnState connState;

  String? errorMessage;
  int? rttMs;
  String? exitReason;

  /// live 前收到的目标尺寸，附着成功后补发。
  int? pendingColumns;
  int? pendingRows;

  /// 回放缓冲：replay 帧先攒着，replayCompleted 一次性写入（避免可见的逐步重绘，MAUI 同款）。
  final List<int> replayBuffer = [];

  /// 裸 \n → \r\n 归一化需要跨 chunk 记住上一个字符。
  int? lastCodeUnit;

  bool get canInput => connState == TerminalConnState.live;
}
