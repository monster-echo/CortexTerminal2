import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Gateway 地址：纯构建期配置，不在 UI 中出现（默认国内网关）。
///
/// 覆盖方式：`flutter build/run --dart-define=CORTERM_GATEWAY_URL=https://...`
const _gatewayUrl = String.fromEnvironment(
  'CORTERM_GATEWAY_URL',
  defaultValue: 'https://corterm.rwecho.top',
);

final appConfigProvider = Provider<String>((ref) => _gatewayUrl);
