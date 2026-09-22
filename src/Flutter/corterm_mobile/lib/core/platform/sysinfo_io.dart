import 'dart:io';

/// 原生平台：操作系统 + 版本。
String platformLabel() =>
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
