import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/ws/terminal_socket.dart';
import '../../core/ws/ws_frames.dart';
import '../sessions/data/session_repository.dart';
import 'workspace_state.dart';

/// Workspace 全局状态（§40）：当前 session + 打开过的 session + 每个 session 的终端状态。
class WorkspaceState {
  const WorkspaceState({
    this.currentSessionId,
    this.openedSessionIds = const [],
    this.entries = const {},
    this.ctrlArmed = false,
  });

  final String? currentSessionId;

  /// 打开顺序（LRU，最后为最新）。UI 不展示为 Tab，仅内部状态。
  final List<String> openedSessionIds;
  final Map<String, SessionTerminalState> entries;

  /// 粘性 CTRL（MAUI 同款）：armed 后下一个软键盘字母变成控制字符。
  final bool ctrlArmed;

  SessionTerminalState? entryOf(String? sessionId) =>
      sessionId == null ? null : entries[sessionId];

  WorkspaceState copyWith({
    String? currentSessionId,
    List<String>? openedSessionIds,
    Map<String, SessionTerminalState>? entries,
    bool? ctrlArmed,
  }) =>
      WorkspaceState(
        currentSessionId: currentSessionId ?? this.currentSessionId,
        openedSessionIds: openedSessionIds ?? this.openedSessionIds,
        entries: entries ?? this.entries,
        ctrlArmed: ctrlArmed ?? this.ctrlArmed,
      );
}

/// Workspace 控制器：
/// - 切换 session 只改 [WorkspaceState.currentSessionId]，绝不终止远程会话（§16/§17）
/// - 后台 session 的连接保持附着，输出持续写入各自 buffer（切回来不重放）
/// - 附着数上限 [maxAttached]，超出后 LRU detach（会话继续在服务端跑）
/// - 断线自动退避重连，成功后重放快照并重建 buffer（§56/§57）
class WorkspaceController extends StateNotifier<WorkspaceState> {
  WorkspaceController(this._repo, this._socketFactory) : super(const WorkspaceState());

  static const maxAttached = 4;
  static const _backoff = [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 10), Duration(seconds: 30)];

  /// 半开连接判定窗口：探测周期 10s，连续 3 个周期未收到任何服务端帧即判死。
  static const _probeInterval = Duration(seconds: 10);
  static const _serverSilenceTimeout = Duration(seconds: 30);

  final SessionRepository _repo;
  final TerminalSocketFactory _socketFactory;

  final _sockets = <String, TerminalSocket>{};
  final _timers = <String, Timer>{};
  final _probes = <String, Timer>{};
  final _lastServerActivityAt = <String, DateTime>{};

  /// 打开 / 切换到某个 session（§16）。
  Future<void> open(String sessionId) async {
    _timers.remove(sessionId)?.cancel();
    final opened = [...state.openedSessionIds]..remove(sessionId);
    opened.add(sessionId);
    if (!state.entries.containsKey(sessionId)) {
      // state.entries 初始为 const {}（不可变），必须先复制再写。
      final entries = Map.of(state.entries)
        ..[sessionId] = SessionTerminalState(terminal: _newTerminal(sessionId), epoch: 0);
      state = state.copyWith(
        currentSessionId: sessionId,
        openedSessionIds: opened,
        entries: entries,
      );
    } else {
      state = state.copyWith(currentSessionId: sessionId, openedSessionIds: opened);
    }
    unawaited(_repo.rememberCurrent(sessionId));
    _enforceAttachCap();
    await _attach(sessionId);
  }

  void _enforceAttachCap() {
    final open = state.openedSessionIds;
    if (open.length <= maxAttached) return;
    for (final id in open.take(open.length - maxAttached)) {
      final entry = state.entries[id];
      if (id == state.currentSessionId) continue;
      if (entry == null) continue;
      switch (entry.connState) {
        case TerminalConnState.live:
        case TerminalConnState.connecting:
        case TerminalConnState.replaying:
          _sockets.remove(id)?.detach();
          entry.connState = TerminalConnState.idle;
          _stopProbe(id);
        default:
          break;
      }
    }
    state = state.copyWith(entries: Map.of(state.entries));
  }

  Terminal _newTerminal(String sessionId) {
    return Terminal(
      maxLines: 64000, // MAUI web 同款 scrollback 上限
      onOutput: (data) => _onUserInput(sessionId, data),
      onResize: (w, h, _, _) => _onTerminalResized(sessionId, w, h),
    );
  }

  Future<void> _attach(String sessionId) async {
    final entry = state.entries[sessionId];
    if (entry == null) return;
    if (_sockets.containsKey(sessionId)) return; // 已附着/连接中
    entry.connState = TerminalConnState.connecting;
    entry.errorMessage = null;
    state = state.copyWith(entries: Map.of(state.entries));

    final TerminalSocket socket;
    try {
      socket = await _socketFactory(sessionId: sessionId);
    } catch (e) {
      if (!state.entries.containsKey(sessionId)) return;
      entry.connState = TerminalConnState.reconnecting;
      entry.errorMessage = e.toString();
      state = state.copyWith(entries: Map.of(state.entries));
      _scheduleReconnect(sessionId, 0);
      return;
    }
    if (!state.entries.containsKey(sessionId)) {
      socket.forceClose();
      return;
    }
    _sockets[sessionId] = socket;
    _lastServerActivityAt[sessionId] = clock.now();

    socket.frames.listen(
      (frame) => _handleFrame(sessionId, frame),
      onError: (Object e) {
        debugPrint('ws($sessionId) stream error: $e');
      },
      onDone: () => _onSocketDone(sessionId),
    );
  }

  void _handleFrame(String sessionId, ServerFrame frame) {
    final entry = state.entries[sessionId];
    if (entry == null) return;
    _lastServerActivityAt[sessionId] = clock.now();
    switch (frame) {
      case ReplayingFrame():
        // reattach 意味着重放快照 → 丢弃旧 buffer，全新 Terminal（epoch++ 触发 UI 重建）。
        final fresh = SessionTerminalState(
          terminal: _newTerminal(sessionId),
          epoch: entry.epoch + 1,
          connState: TerminalConnState.replaying,
          rttMs: entry.rttMs,
        );
        state = state.copyWith(
          entries: Map.of(state.entries)..[sessionId] = fresh,
        );
      case ReplayFrame():
        entry.replayBuffer.addAll(frame.bytes);
      case ReplayCompletedFrame():
        _flushReplay(entry);
      case LiveFrame():
        entry.connState = TerminalConnState.live;
        _sendPendingResize(sessionId, entry);
        _startProbe(sessionId);
        state = state.copyWith(entries: Map.of(state.entries));
      case OutputFrame():
        _writeNormalized(entry, frame.bytes);
      case DetachedFrame():
        break; // 我方 detach 后服务端确认；socket 随即关闭，由 _onSocketDone 收尾
      case ExitedFrame():
        _timers.remove(sessionId)?.cancel();
        _stopProbe(sessionId);
        entry.connState = TerminalConnState.exited;
        entry.exitReason = frame.reason;
        state = state.copyWith(entries: Map.of(state.entries));
      case ExpiredFrame():
        _timers.remove(sessionId)?.cancel();
        _stopProbe(sessionId);
        entry.connState = TerminalConnState.error;
        entry.errorMessage = frame.reason ?? 'expired';
        state = state.copyWith(entries: Map.of(state.entries));
      case ErrorFrame():
        switch (frame.code) {
          case 'session-not-found':
          case 'forbidden':
          case 'reattach-failed':
          case 'session-start-failed':
            _timers.remove(sessionId)?.cancel();
            _stopProbe(sessionId);
            entry.connState = TerminalConnState.error;
            entry.errorMessage = frame.message ?? frame.code;
            state = state.copyWith(entries: Map.of(state.entries));
          default:
            // invalid-frame 等协议错误：保留连接，仅记录。
            debugPrint('ws($sessionId) error frame: ${frame.code} ${frame.message}');
        }
      case DisplacedFrame():
        // 同 session 被第二客户端挤掉：终态，不自动重连（重连会与另一端互踢）。
        _timers.remove(sessionId)?.cancel();
        _stopProbe(sessionId);
        entry.connState = TerminalConnState.error;
        entry.errorMessage = 'displaced';
        state = state.copyWith(entries: Map.of(state.entries));
      case PongFrame():
        break;
      case LatencyAckFrame():
        final rtt = clock.now().millisecondsSinceEpoch - frame.clientTime;
        entry.rttMs = rtt < 0 ? 0 : rtt;
        state = state.copyWith(entries: Map.of(state.entries));
    }
  }

  void _flushReplay(SessionTerminalState entry) {
    if (entry.replayBuffer.isNotEmpty) {
      _writeNormalized(entry, entry.replayBuffer);
      entry.replayBuffer.clear();
    }
    entry.connState = TerminalConnState.live;
    state = state.copyWith(entries: Map.of(state.entries));
  }

  void _writeNormalized(SessionTerminalState entry, List<int> bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    // 裸 \n → \r\n（PTY 不开 ONLCR 时防楼梯；跨 chunk 的 \r\n 依赖 lastCodeUnit）。
    if (text.contains('\n')) {
      final sb = StringBuffer();
      var prev = entry.lastCodeUnit;
      for (final cu in text.codeUnits) {
        if (cu == 0x0A && prev != 0x0D) sb.writeCharCode(0x0D);
        sb.writeCharCode(cu);
        prev = cu;
      }
      text = sb.toString();
    }
    entry.lastCodeUnit = text.isEmpty ? entry.lastCodeUnit : text.codeUnits.last;
    entry.terminal.write(text);
  }

  void _onSocketDone(String sessionId) {
    final socket = _sockets.remove(sessionId);
    _lastServerActivityAt.remove(sessionId);
    _stopProbe(sessionId);
    // 我方主动断（detach / forceClose：退后台、心跳判死、LRU、dispose）——
    // 状态由发起方管理，此处不动 state（dispose 后访问会抛）。
    if (socket == null || socket.closedByUs) return;
    final entry = state.entries[sessionId];
    if (entry == null) return;
    if (socket.sessionNotFound) {
      entry.connState = TerminalConnState.exited;
      entry.exitReason = 'session-not-found';
      state = state.copyWith(entries: Map.of(state.entries));
      return;
    }
    switch (entry.connState) {
      case TerminalConnState.exited:
      case TerminalConnState.error:
        // exited / expired / displaced 等终态帧之后服务端关闭连接属正常收尾。
        return;
      default:
        break;
    }
    // 网络断开 → 自动重连（last-writer-wins，MAUI 同语义）。
    entry.connState = TerminalConnState.reconnecting;
    state = state.copyWith(entries: Map.of(state.entries));
    _scheduleReconnect(sessionId, 0);
  }

  void _scheduleReconnect(String sessionId, int attempt) {
    _timers.remove(sessionId)?.cancel();
    final delay = _backoff[attempt.clamp(0, _backoff.length - 1)];
    _timers[sessionId] = Timer(delay, () async {
      if (!state.entries.containsKey(sessionId)) return;
      await _attach(sessionId);
      if (state.entries[sessionId]?.connState != TerminalConnState.live) {
        _scheduleReconnect(sessionId, attempt + 1);
      }
    });
  }

  // ---- 输入（§29 键盘工具栏 + 软键盘）----

  void _onUserInput(String sessionId, String data) {
    final entry = state.entries[sessionId];
    if (entry == null) return;
    var payload = data;
    if (state.ctrlArmed) {
      payload = _applyCtrl(data);
      state = state.copyWith(ctrlArmed: false);
      if (payload.isEmpty) return;
    }
    final socket = _sockets[sessionId];
    if (socket == null || !entry.canInput) {
      throw StateError('session $sessionId is not attached for input');
    }
    socket.input(payload);
  }

  String _applyCtrl(String data) {
    final sb = StringBuffer();
    for (final cu in data.codeUnits) {
      if (cu >= 0x61 && cu <= 0x7A) {
        sb.writeCharCode(cu - 0x60); // a-z → \x01..\x1a
      } else if (cu >= 0x41 && cu <= 0x5A) {
        sb.writeCharCode(cu - 0x40); // A-Z
      } else if (cu == 0x1B) {
        sb.writeCharCode(0x03); // Ctrl+Esc → ^C
      } else {
        sb.writeCharCode(cu);
      }
    }
    return sb.toString();
  }

  void setCtrlArmed(bool armed) => state = state.copyWith(ctrlArmed: armed);

  /// 工具栏直接按键（ESC/TAB/方向键）。
  void sendKey(String seq) {
    final id = state.currentSessionId;
    if (id == null) return;
    final entry = state.entries[id];
    if (entry == null) return;
    var payload = seq;
    if (state.ctrlArmed) {
      payload = _applyCtrl(seq);
      state = state.copyWith(ctrlArmed: false);
      if (payload.isEmpty) return;
    }
    _sockets[id]?.input(payload);
  }

  /// 粘贴等原样写入（不做 CTRL 变换）。未附着时由 UI 保证不可达。
  void sendInputRaw(String text) {
    final id = state.currentSessionId;
    if (id == null) return;
    _sockets[id]?.input(text);
  }

  void _onTerminalResized(String sessionId, int columns, int rows) {
    final entry = state.entries[sessionId];
    if (entry == null) return;
    if (entry.connState == TerminalConnState.live) {
      _sockets[sessionId]?.resize(columns: columns, rows: rows);
    } else {
      entry
        ..pendingColumns = columns
        ..pendingRows = rows;
    }
  }

  void _sendPendingResize(String sessionId, SessionTerminalState entry) {
    if (entry.pendingColumns != null && entry.pendingRows != null) {
      _sockets[sessionId]?.resize(columns: entry.pendingColumns!, rows: entry.pendingRows!);
      entry
        ..pendingColumns = null
        ..pendingRows = null;
    }
  }

  // ---- 延迟探测 ----

  void _startProbe(String sessionId) {
    _stopProbe(sessionId);
    _probes[sessionId] = Timer.periodic(_probeInterval, (t) {
      final socket = _sockets[sessionId];
      if (socket == null) {
        t.cancel();
        return;
      }
      final last = _lastServerActivityAt[sessionId];
      final silentFor = last == null ? null : clock.now().difference(last);
      if (silentFor != null && silentFor > _serverSilenceTimeout) {
        // 半开连接：TCP 未感知断开但服务端帧全无。主动断开并立即重连
        // （forceClose 标记 closedByUs，onDone 只做清理不重复调度）。
        socket.forceClose();
        final entry = state.entries[sessionId];
        if (entry != null) {
          entry.connState = TerminalConnState.reconnecting;
          state = state.copyWith(entries: Map.of(state.entries));
        }
        _scheduleReconnect(sessionId, 0);
        return;
      }
      socket.latencyProbe('p$t.tick', clock.now().millisecondsSinceEpoch);
    });
    // 立即探测一次
    _sockets[sessionId]?.latencyProbe('p0', clock.now().millisecondsSinceEpoch);
  }

  void _stopProbe(String sessionId) => _probes.remove(sessionId)?.cancel();

  // ---- 生命周期 ----

  /// 退后台：立即断开所有活动连接（不发 detach——后台等 3s 服务端确认无意义）。
  /// 状态置 reconnecting，回前台 / 网络恢复由 [reattachAll] 统一接管。
  void enterBackground() {
    for (final id in state.openedSessionIds) {
      final entry = state.entries[id];
      if (entry == null) continue;
      switch (entry.connState) {
        case TerminalConnState.live:
        case TerminalConnState.connecting:
        case TerminalConnState.replaying:
          _sockets.remove(id)?.forceClose();
          _lastServerActivityAt.remove(id);
          _stopProbe(id);
          entry.connState = TerminalConnState.reconnecting;
        default:
          break;
      }
    }
    state = state.copyWith(entries: Map.of(state.entries));
  }

  /// 回前台 / 网络恢复：所有退避等待中的 session 立即重连（取消剩余退避）。
  /// MAUI 的 AppResumed → ReattachSession 同语义；终态（exited/error）留给用户手动重连。
  void reattachAll() {
    for (final id in state.openedSessionIds) {
      final entry = state.entries[id];
      if (entry == null) continue;
      if (entry.connState == TerminalConnState.reconnecting) {
        _scheduleReconnect(id, 0);
      }
    }
  }

  /// 明确关闭某个 session 的终端（terminate / 删除后调用）。
  Future<void> closeTerminal(String sessionId) async {
    _timers.remove(sessionId)?.cancel();
    _stopProbe(sessionId);
    _lastServerActivityAt.remove(sessionId);
    final socket = _sockets.remove(sessionId);
    if (socket != null) {
      await socket.detach();
    }
    final entries = Map.of(state.entries)..remove(sessionId);
    final opened = [...state.openedSessionIds]..remove(sessionId);
    String? current = state.currentSessionId;
    if (current == sessionId) {
      current = opened.isNotEmpty ? opened.last : null;
    }
    state = state.copyWith(currentSessionId: current, openedSessionIds: opened, entries: entries);
    await _repo.rememberCurrent(current);
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    for (final p in _probes.values) {
      p.cancel();
    }
    for (final s in _sockets.values) {
      s.forceClose();
    }
    super.dispose();
  }
}

final workspaceControllerProvider =
    StateNotifierProvider<WorkspaceController, WorkspaceState>((ref) {
  return WorkspaceController(
    ref.watch(sessionRepositoryProvider),
    ref.watch(terminalSocketFactoryProvider),
  );
});
