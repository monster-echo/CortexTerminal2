/// `/ws/terminal` 协议帧编解码（纯函数，可单测）。
///
/// 协议见 Gateway `WebSockets/TerminalWebSocketHandler.cs`：
/// 全部为 UTF-8 JSON text frame，二进制 payload 走 base64。
/// 服务端序列：replaying → replay×N → replayCompleted → live。
library;

import 'dart:convert';

/// 服务端 → 客户端帧。
sealed class ServerFrame {
  const ServerFrame();
}

class ReplayingFrame extends ServerFrame {
  const ReplayingFrame();
}

class ReplayFrame extends ServerFrame {
  const ReplayFrame({required this.bytes, required this.stream});

  final List<int> bytes;
  final String stream;
}

class ReplayCompletedFrame extends ServerFrame {
  const ReplayCompletedFrame();
}

/// 增量重放开始（?since=N 声明了游标的客户端）：**不重置**已绘制画面，
/// 后续 replayDelta 帧无缝续写。
class ReplayDeltaStartedFrame extends ServerFrame {
  const ReplayDeltaStartedFrame();
}

/// 增量重放块：带 Worker 分配的 per-session 序列号。
class ReplayDeltaFrame extends ServerFrame {
  const ReplayDeltaFrame({required this.bytes, required this.stream, required this.seq});

  final List<int> bytes;
  final String stream;
  final int seq;
}

/// 增量重放完成：lastSeq = 本会话流的最新序列号（客户端游标推进到此处）。
class ReplayDeltaCompletedFrame extends ServerFrame {
  const ReplayDeltaCompletedFrame({required this.lastSeq});

  final int lastSeq;
}

class OutputFrame extends ServerFrame {
  const OutputFrame({required this.bytes, required this.stream});

  final List<int> bytes;
  final String stream;
}

class LiveFrame extends ServerFrame {
  const LiveFrame();
}

class DetachedFrame extends ServerFrame {
  const DetachedFrame();
}

class ExitedFrame extends ServerFrame {
  const ExitedFrame({this.exitCode, this.reason});

  final int? exitCode;
  final String? reason;
}

class ExpiredFrame extends ServerFrame {
  const ExpiredFrame({this.reason});
  final String? reason;
}

class ErrorFrame extends ServerFrame {
  const ErrorFrame({required this.code, this.message});

  final String code;
  final String? message;
}

/// 同 session 被第二客户端附着挤掉（协议预留：Gateway 将在 WS 面新增此帧，
/// 对照 SignalR 的 SessionDisplaced；服务端发完即关闭连接）。
class DisplacedFrame extends ServerFrame {
  const DisplacedFrame({this.reason});
  final String? reason;
}

class PongFrame extends ServerFrame {
  const PongFrame({required this.timestamp});
  final int timestamp;
}

class LatencyAckFrame extends ServerFrame {
  const LatencyAckFrame({required this.probeId, required this.clientTime});

  final String probeId;
  final int clientTime;
}

class WsFrames {
  /// 解析服务端 JSON 帧。未知 type 原样抛 [FormatException]（不静默吞）。
  static ServerFrame parseServerFrame(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw FormatException('ws/terminal: malformed JSON frame: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ws/terminal: frame is not a JSON object');
    }
    switch (decoded['type'] as String?) {
      case 'replaying':
        return const ReplayingFrame();
      case 'replay':
        return ReplayFrame(
          bytes: _decodePayload(decoded['payload']),
          stream: (decoded['stream'] as String?) ?? 'stdout',
        );
      case 'replayCompleted':
        return const ReplayCompletedFrame();
      case 'replayDeltaStarted':
        return const ReplayDeltaStartedFrame();
      case 'replayDelta':
        return ReplayDeltaFrame(
          bytes: _decodePayload(decoded['payload']),
          stream: (decoded['stream'] as String?) ?? 'stdout',
          seq: (decoded['seq'] as num?)?.toInt() ?? 0,
        );
      case 'replayDeltaCompleted':
        return ReplayDeltaCompletedFrame(
          lastSeq: (decoded['lastSeq'] as num?)?.toInt() ?? 0,
        );
      case 'output':
        return OutputFrame(
          bytes: _decodePayload(decoded['payload']),
          stream: (decoded['stream'] as String?) ?? 'stdout',
        );
      case 'live':
        return const LiveFrame();
      case 'detached':
        return const DetachedFrame();
      case 'exited':
        return ExitedFrame(
          exitCode: (decoded['exitCode'] as num?)?.toInt(),
          reason: decoded['reason'] as String?,
        );
      case 'expired':
        return ExpiredFrame(reason: decoded['reason'] as String?);
      case 'error':
        return ErrorFrame(
          code: (decoded['code'] as String?) ?? 'unknown',
          message: decoded['message'] as String?,
        );
      case 'displaced':
        return DisplacedFrame(reason: decoded['reason'] as String?);
      case 'pong':
        return PongFrame(timestamp: (decoded['timestamp'] as num?)?.toInt() ?? 0);
      case 'latencyAck':
        return LatencyAckFrame(
          probeId: (decoded['probeId'] as String?) ?? '',
          clientTime: (decoded['clientTime'] as num?)?.toInt() ?? 0,
        );
      default:
        throw FormatException('ws/terminal: unknown frame type: ${decoded['type']}');
    }
  }

  static List<int> _decodePayload(Object? payload) {
    if (payload is! String || payload.isEmpty) return const [];
    return base64Decode(payload);
  }

  // ---- 客户端 → 服务端 ----

  static String input(String data) => jsonEncode({
        'type': 'input',
        'payload': base64Encode(utf8.encode(data)),
      });

  static String resize({required int columns, required int rows}) => jsonEncode({
        'type': 'resize',
        'columns': columns,
        'rows': rows,
      });

  static const detachFrame = '{"type":"detach"}';

  static const closeFrame = '{"type":"close"}';

  static String ping(int timestamp) => jsonEncode({'type': 'ping', 'timestamp': timestamp});

  static String latencyProbe(String probeId, int clientTime) => jsonEncode({
        'type': 'latencyProbe',
        'probeId': probeId,
        'clientTime': clientTime,
      });

  /// WS URL：`wss://host/ws/terminal?token=<jwt>&sessionId=<id>&caps=displaced[&since=<seq>]`。
  /// caps 声明本客户端支持的扩展能力；gateway 只向声明者发 displaced 帧
  /// （旧客户端不声明 → 维持纯关闭行为）。
  /// since = 客户端缓存的输出游标（>0 走增量重放；0/缺省 = 全量重放）。
  static Uri buildUri({
    required String gatewayBaseUrl,
    required String token,
    required String sessionId,
    int sinceSeq = 0,
  }) {
    final http = Uri.parse(gatewayBaseUrl);
    final isSecure = http.scheme == 'https';
    return Uri(
      scheme: isSecure ? 'wss' : 'ws',
      host: http.host,
      port: http.port,
      path: '/ws/terminal',
      queryParameters: {
        'token': token,
        'sessionId': sessionId,
        'caps': 'displaced',
        if (sinceSeq > 0) 'since': '$sinceSeq',
      },
    );
  }
}
