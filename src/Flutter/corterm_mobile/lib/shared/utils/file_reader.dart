/// 平台条件导出：移动/桌面用 dart:io，Web 用 stub。
library;
export 'file_reader_stub.dart'
    if (dart.library.io) 'file_reader_io.dart'
    if (dart.library.js_interop) 'file_reader_web.dart';
