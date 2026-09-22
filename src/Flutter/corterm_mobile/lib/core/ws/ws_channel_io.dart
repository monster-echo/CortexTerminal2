import 'dart:async';
import 'dart:io';

import '../api/api_exception.dart';

/// dart:io 实现（Android/iOS/桌面）。
class WsChannel {
  WsChannel._(this._ws);

  static Future<WsChannel> connect(Uri uri) async {
    final WebSocket ws;
    try {
      ws = await WebSocket.connect(uri.toString());
    } on SocketException catch (e) {
      throw ApiException(0, serverMessage: e.message);
    } on WebSocketException catch (e) {
      throw ApiException(0, serverMessage: e.message);
    } on HttpException catch (e) {
      // WebSocket.connect 把非 101 升级响应用 HttpException 抛出。
      throw ApiException(0, serverMessage: e.message);
    }
    return WsChannel._(ws);
  }

  final WebSocket _ws;

  StreamSubscription<Object?> listen({
    void Function(Object? data)? onData,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) {
    return _ws.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: false,
    );
  }

  Future<void> get done => _ws.done;

  void add(String raw) => _ws.add(raw);

  void close() => _ws.close();
}
