/// 平台无关的 WebSocket 通道接口。
///
/// 条件导出：原生用 dart:io WebSocket，web 用浏览器 WebSocket。
/// 两个实现声明相同的 `WsChannel` API：
/// - `connect(uri)`：失败（非 101 升级/401/网络错误）统一抛 ApiException
/// - `listen(onData, onError, onDone)`：单点接管帧数据/错误/服务端关闭
/// - `done`：服务端已关闭；`add`/`close`：发送与关闭。
library;
export 'ws_channel_io.dart' if (dart.library.js_interop) 'ws_channel_web.dart';
