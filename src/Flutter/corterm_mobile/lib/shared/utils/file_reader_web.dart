import 'dart:typed_data';

/// 读取本地文件字节（Web stub：Web 端永远走 bytes，不该到这）。
Future<Uint8List> readFileBytes(String path) async =>
    throw UnsupportedError('reading file paths is not supported on web');
