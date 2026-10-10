/// P2P 通道公共类型（不依赖 dart:io，stub 与 io 实现共用）。
///
/// 数据面：打通后的 UDP 通道 = AES-GCM 加密 + 可靠流上跑精简 HTTP（规格 §3/§4），
/// 对外行为与 HTTP 端点直传一致（同一函数签名，供端点协商回落）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'p2p_crypto.dart';
import 'reliable_stream.dart';

/// P2P 打洞/传输失败（协商逻辑据此静默落下一端点，规格 §5 的唯一回落点）。
class P2pException implements Exception {
  const P2pException(this.message);

  final String message;

  @override
  String toString() => 'P2pException: $message';
}

class P2pChannel {
  /// 由 p2p_transfer（io 实现层）在打洞打通后装配。
  P2pChannel({
    required P2pCipher cipher,
    required ReliableStream stream,
    required void Function() onClose,
  })  : _cipher = cipher,
        _stream = stream,
        _onClose = onClose;

  final P2pCipher _cipher;
  final ReliableStream _stream;
  final void Function() _onClose;

  /// 收到对端 UDP 包（io 层已区分探包/加密包）。
  Future<void> handlePacket(Uint8List packet) async {
    final frame = await _cipher.open(packet);
    if (frame != null) _stream.handleFrame(frame);
  }

  /// 精简 HTTP PUT 上传（§4）。非 2xx 抛 [P2pException]。
  Future<void> upload({
    required String transferId,
    required String token,
    required List<int> bytes,
  }) async {
    final request = 'PUT /transfer/$transferId?token=${Uri.encodeQueryComponent(token)} HTTP/1.1\r\n'
        'Host: p2p\r\n'
        'Content-Type: application/octet-stream\r\n'
        'Content-Length: ${bytes.length}\r\n\r\n';
    _stream.write(ascii.encode(request));
    _stream.write(bytes);
    _stream.closeWrite();
    final (:status, body: _) = await _readResponse();
    if (status < 200 || status >= 300) {
      throw P2pException('p2p upload: HTTP $status');
    }
  }

  /// 精简 HTTP GET 下载（§4）。非 2xx 抛 [P2pException]。
  Future<Uint8List> download({
    required String transferId,
    required String token,
  }) async {
    final request = 'GET /transfer/$transferId?token=${Uri.encodeQueryComponent(token)} HTTP/1.1\r\n'
        'Host: p2p\r\n\r\n';
    _stream.write(ascii.encode(request));
    _stream.closeWrite();
    final (:status, body: raw) = await _readResponse();
    if (status < 200 || status >= 300) {
      throw P2pException('p2p download: HTTP $status');
    }
    return Uint8List.fromList(raw);
  }

  /// 读响应到 EOF（Worker 写完响应即 FIN），解析状态行 + Content-Length，
  /// 返回头部之后的 body 原始字节。
  Future<({int status, Uint8List body})> _readResponse() async {
    final raw = await _stream.readAll();
    // 只把头部（到 \r\n\r\n 为止，字节级查找）当 ASCII 解析，body 可能是二进制。
    var sep = -1;
    for (var i = 0; i + 3 < raw.length; i++) {
      if (raw[i] == 0x0D && raw[i + 1] == 0x0A && raw[i + 2] == 0x0D && raw[i + 3] == 0x0A) {
        sep = i;
        break;
      }
    }
    final head = sep < 0 ? '' : ascii.decode(Uint8List.sublistView(raw, 0, sep));
    if (!head.startsWith('HTTP/1.1 ')) {
      throw P2pException('p2p: malformed HTTP response');
    }
    final status = int.parse(head.substring(9, 12));
    var contentLength = 0;
    for (final line in head.split('\r\n').skip(1)) {
      final i = line.indexOf(':');
      if (i > 0 && line.substring(0, i).trim().toLowerCase() == 'content-length') {
        contentLength = int.parse(line.substring(i + 1).trim());
      }
    }
    final body = Uint8List.sublistView(raw, sep + 4);
    if (body.length < contentLength) {
      throw P2pException('p2p: response body truncated (${body.length}/$contentLength)');
    }
    return (status: status, body: body);
  }

  /// 释放本地资源（关闭底层 socket；正常结束由 FIN/EOF 收尾，异常中止用 [abort]）。
  void close() {
    _stream.dispose();
    _onClose();
  }

  /// 异常中止：发 RST。
  void abort() => _stream.abort();
}
