import 'dart:async';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

import '../api/api_exception.dart';

/// 浏览器 WebSocket 实现（Flutter web）。
class WsChannel {
  WsChannel._(this._ws) {
    // 浏览器把三条事件流（message/error/close）桥接成单一订阅契约。
    _ws.onMessage.listen((e) => _messages.add(e.data as Object?));
    _ws.onError.listen((e) => _errors.add(e));
    _ws.onClose.listen((_) {
      if (!_done.isCompleted) _done.complete();
      _messages.close();
      _errors.close();
    });
  }

  static Future<WsChannel> connect(Uri uri) async {
    final ws = html.WebSocket(uri.toString());
    // 浏览器拿不到握手状态码：open 与 close/error 竞速，失败统一抛 ApiException。
    final opened = ws.onOpen.first;
    final failed = ws.onClose.first.then((e) {
      throw ApiException(0, serverMessage: 'websocket closed (${e.code})');
    });
    final errored = ws.onError.first.then((_) {
      throw ApiException(0, serverMessage: 'websocket error');
    });
    await Future.any([opened, failed, errored]).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw ApiException(0, serverMessage: 'websocket connect timeout'),
    );
    return WsChannel._(ws);
  }

  final html.WebSocket _ws;
  final _messages = StreamController<Object?>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  final _done = Completer<void>();

  StreamSubscription<Object?> listen({
    void Function(Object? data)? onData,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) {
    if (onError != null) _errors.stream.listen(onError);
    if (onDone != null) {
      _done.future.then((_) => onDone());
    }
    return _messages.stream.listen(onData);
  }

  Future<void> get done => _done.future;

  void add(String raw) => _ws.send(raw);

  void close() => _ws.close();
}
