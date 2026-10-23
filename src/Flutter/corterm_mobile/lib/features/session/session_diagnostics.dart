import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

class SessionDiagnostic {
  const SessionDiagnostic({
    required this.state,
    required this.hasOutput,
    required this.directoryAccess,
    required this.platform,
    this.directory,
  });
  final String state;
  final bool hasOutput;
  final String directoryAccess;
  final String platform;
  final String? directory;
  factory SessionDiagnostic.fromJson(Map<String, dynamic> json) =>
      SessionDiagnostic(
        state: json['state'] as String? ?? 'diagnostics-unavailable',
        hasOutput: json['hasOutput'] == true,
        directoryAccess: json['directoryAccess'] as String? ?? 'not-checked',
        platform: json['platform'] as String? ?? 'unknown',
        directory: json['directory'] as String?,
      );
}

final sessionDiagnosticsProvider = Provider(
  (ref) => SessionDiagnostics(ref.watch(apiClientProvider)),
);

class SessionDiagnostics {
  SessionDiagnostics(this._client);
  final ApiClient _client;
  Future<SessionDiagnostic> check(String sessionId) async =>
      SessionDiagnostic.fromJson(
        await _client
            .getMap(
              '/api/me/sessions/${Uri.encodeComponent(sessionId)}/diagnostics',
            )
            .timeout(const Duration(seconds: 10)),
      );
}
