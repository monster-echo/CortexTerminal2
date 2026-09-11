/// Worker（运行在用户机器上的 agent）模型。
library;

class WorkerSummary {
  const WorkerSummary({
    required this.workerId,
    required this.name,
    this.hostname,
    this.operatingSystem,
    this.architecture,
    this.version,
    required this.isOnline,
    this.lastSeenAtUtc,
    required this.sessionCount,
    this.cpuUsagePercent,
    this.memoryUsagePercent,
  });

  final String workerId;
  final String name;
  final String? hostname;
  final String? operatingSystem;
  final String? architecture;
  final String? version;
  final bool isOnline;
  final DateTime? lastSeenAtUtc;
  final int sessionCount;
  final double? cpuUsagePercent;
  final double? memoryUsagePercent;

  String get displayName => name.isNotEmpty ? name : (hostname ?? workerId);

  factory WorkerSummary.fromJson(Map<String, dynamic> json) {
    final id = json['workerId'] as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('Worker summary missing workerId');
    }
    return WorkerSummary(
      workerId: id,
      name: (json['name'] as String?) ?? '',
      hostname: json['hostname'] as String?,
      operatingSystem: json['operatingSystem'] as String?,
      architecture: json['architecture'] as String?,
      version: json['version'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeenAtUtc: (json['lastSeenAtUtc'] as String?) != null
          ? DateTime.parse(json['lastSeenAtUtc'] as String)
          : null,
      sessionCount: (json['sessionCount'] as num?)?.toInt() ?? 0,
      cpuUsagePercent: (json['cpuUsagePercent'] as num?)?.toDouble(),
      memoryUsagePercent: (json['memoryUsagePercent'] as num?)?.toDouble(),
    );
  }
}

class GatewayInfo {
  const GatewayInfo({required this.version, this.latestGatewayVersion});

  final String version;
  final String? latestGatewayVersion;

  factory GatewayInfo.fromJson(Map<String, dynamic> json) => GatewayInfo(
        version: json['version'] as String? ?? '',
        latestGatewayVersion: json['latestGatewayVersion'] as String?,
      );
}
