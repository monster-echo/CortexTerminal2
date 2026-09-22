import 'dart:io';
import 'dart:typed_data';

/// 读取本地文件字节（移动/桌面端）。
Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();
