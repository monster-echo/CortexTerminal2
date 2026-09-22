import 'dart:typed_data';

/// 平台条件导出的兜底 stub（理论上 io 或 web 总会命中其一）。
Future<Uint8List> readFileBytes(String path) async =>
    throw UnsupportedError('no file reader for this platform');
