import '../../core/api/api_exception.dart';
import '../../l10n/app_localizations.dart';

/// 把异常转成用户可读的提示（不暴露 ApiException 类名 / 原始堆栈）：
/// - 优先取 Gateway 返回的 serverMessage（本身即面向用户的文案）；
/// - 已知场景映射为更友好的本地化文案（如端口未监听）；
/// - 其余异常退回通用失败提示。
String errorText(Object error, AppLocalizations l10n) {
  if (error is ApiException) {
    final msg = error.serverMessage ?? '';
    // "Port 5172 is not listening on worker: Connection refused"
    // → 引导用户先在 worker 上把服务跑起来。
    final notListening =
        RegExp(r'Port (\d+) is not listening on worker').firstMatch(msg);
    if (notListening != null) {
      return l10n.tunnelPortNotListening(notListening.group(1)!);
    }
    if (msg.isNotEmpty) return msg;
    return l10n.apiErrorFallback('${error.statusCode}');
  }
  return '$error';
}
