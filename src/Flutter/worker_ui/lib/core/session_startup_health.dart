import 'dart:convert';
import 'dart:io';

class StartupWarning {
  const StartupWarning(this.sessionId, this.directory);
  final String sessionId;
  final String? directory;
}

/// Ignore stale records from a stopped or upgraded desktop component.
Future<List<StartupWarning>> readSessionStartupWarnings({
  String? homeDirectory,
  DateTime? now,
}) async {
  final home =
      homeDirectory ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (home == null) return const [];
  try {
    final data =
        jsonDecode(
              await File(
                '$home/.corterm/session-startup-health.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final timestamp = (data['updatedAt'] as num?)?.toInt();
    if (timestamp == null) return const [];
    final age =
        (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000 - timestamp;
    if (age < -5 || age > 15) return const [];
    return (data['sessions'] as List<dynamic>? ?? const []).map((raw) {
      final item = raw as Map<String, dynamic>;
      return StartupWarning(
        item['sessionId'] as String,
        item['directory'] as String?,
      );
    }).toList();
  } on FileSystemException {
    return const [];
  } on FormatException {
    return const [];
  } on TypeError {
    return const [];
  }
}
