import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../auth/token_store.dart';
import 'ws_channel.dart';
import 'ws_frames.dart';

/// 一个 session 一条 WS 连接（Gateway 单附着语义：同 session 第二次附着会挤掉旧客户端）。
///
/// 帧事件通过 [frames] 广播；连接断开通过 [onDisconnected] 通知（带错误原因，如有）。
class TerminalSocket {
  TerminalSocket._(this._channel, this.sessionId) {
    _channel.listen(
      onData: (data) {
        // /ws/terminal 全部为 text frame。
        final raw = data is String ? data : utf8.decode(data as List<int>);
        final frame = WsFrames.parseServerFrame(raw);
        if (frame is ErrorFrame && frame.code == 'session-not-found') {
          // 连接会被服务端关闭；标记原因后正常走 onDone。
          _notFound = true;
        }
        _frameController.add(frame);
      },
      onError: (Object e) {
        _frameController.addError(e);
      },
      onDone: () {
        // 服务端关闭（网络断开 / displaced / exited 收尾）：关闭帧流，
        // 让消费方的 onDone 触发重连判定。
        _closed = true;
        _doneCompleter.complete();
        if (!_frameController.isClosed) _frameController.close();
      },
    );
  }

  /// 连接并等待服务端确认升级。失败（401/400/网络）抛异常。
  /// [sinceSeq] > 0 时请求增量重放（仅重放游标之后的输出）。
  static Future<TerminalSocket> connect({
    required String gatewayBaseUrl,
    required String token,
    required String sessionId,
    int sinceSeq = 0,
  }) async {
    final uri = WsFrames.buildUri(
      gatewayBaseUrl: gatewayBaseUrl,
      token: token,
      sessionId: sessionId,
      sinceSeq: sinceSeq,
    );
    final channel = await WsChannel.connect(uri);
    return TerminalSocket._(channel, sessionId);
  }

  final WsChannel _channel;
  final String sessionId;

  bool _closed = false;
  bool _notFound = false;
  final _frameController = StreamController<ServerFrame>.broadcast();
  final _doneCompleter = Completer<void>();

  var _sentDetach = false;
  var _closedByUs = false;

  /// 是否是我方主动 detach（服务端回 detached 后关闭，不算异常断线）。
  bool get detachedByUs => _sentDetach;

  /// 是否由我方主动断开（detach/close/forceClose）。消费方据此跳过自动重连。
  bool get closedByUs => _closedByUs;

  /// 服务端对该 session 返回了 session-not-found（已过期/被删）。
  bool get sessionNotFound => _notFound;

  /// 服务端是否已关闭连接。
  Future<void> get done => _doneCompleter.future;

  Stream<ServerFrame> get frames => _frameController.stream;

  void input(String data) => _send(WsFrames.input(data));

  void resize({required int columns, required int rows}) =>
      _send(WsFrames.resize(columns: columns, rows: rows));

  /// 优雅脱离（PTY 继续跑，服务端回 detached 后关闭连接）。
  Future<void> detach() async {
    if (_closed) return;
    _sentDetach = true;
    _closedByUs = true;
    _send(WsFrames.detachFrame);
    await done.timeout(const Duration(seconds: 3), onTimeout: () {});
    _close();
  }

  /// 终止远程会话（PTY 会被 kill）。
  void close() {
    _closedByUs = true;
    _send(WsFrames.closeFrame);
    _close();
  }

  void ping(int timestamp) => _send(WsFrames.ping(timestamp));

  void latencyProbe(String probeId, int clientTime) =>
      _send(WsFrames.latencyProbe(probeId, clientTime));

  void _send(String raw) {
    if (_closed) {
      throw StateError('TerminalSocket($sessionId): already closed');
    }
    _channel.add(raw);
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _channel.close();
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
    if (!_frameController.isClosed) _frameController.close();
  }

  /// 立即关闭底层连接（切换/重连场景），不发 detach。
  void forceClose() {
    _closedByUs = true;
    _close();
  }
}

final terminalSocketFactoryProvider = Provider<TerminalSocketFactory>((ref) {
  final config = ref.watch(appConfigProvider);
  final tokenStore = ref.watch(tokenStoreProvider);
  return ({required sessionId, sinceSeq = 0}) {
    final token = tokenStore.token;
    if (token == null) {
      throw StateError('TerminalSocket: no token');
    }
    return TerminalSocket.connect(
      gatewayBaseUrl: config,
      token: token,
      sessionId: sessionId,
      sinceSeq: sinceSeq,
    );
  };
});

typedef TerminalSocketFactory = Future<TerminalSocket> Function({
  required String sessionId,
  int sinceSeq,
});
