/// 与 corterm `--json` 输出对应的数据模型。
library;

class Status {
  const Status({
    required this.version,
    required this.pid,
    required this.uptime,
    required this.gateway,
    required this.workerId,
    required this.authenticated,
    this.user,
    this.authExpiry,
    this.gatewayVersion,
    this.latestWorkerVersion,
    required this.updateAvailable,
    required this.workers,
  });

  final String version;
  final int pid;
  final String uptime;
  final String gateway;
  final String workerId;
  final bool authenticated;
  final String? user;
  final String? authExpiry;
  final String? gatewayVersion;
  final String? latestWorkerVersion;
  final bool updateAvailable;
  final List<WorkerInfo> workers;

  factory Status.fromJson(Map<String, dynamic> json) {
    final gatewayInfo = json['gatewayInfo'];
    return Status(
      version: json['version'] as String? ?? '',
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      uptime: json['uptime'] as String? ?? 'n/a',
      gateway: json['gateway'] as String? ?? '',
      workerId: json['workerId'] as String? ?? '',
      authenticated: json['authenticated'] as bool? ?? false,
      user: json['user'] as String?,
      authExpiry: json['authExpiry'] as String?,
      gatewayVersion: gatewayInfo is Map ? gatewayInfo['version'] as String? : null,
      latestWorkerVersion: gatewayInfo is Map ? gatewayInfo['latestWorkerVersion'] as String? : null,
      updateAvailable: json['updateAvailable'] as bool? ?? false,
      workers: (json['workers'] as List? ?? const [])
          .whereType<Map>()
          .map((w) => WorkerInfo.fromJson(Map<String, dynamic>.from(w)))
          .toList(),
    );
  }
}

class WorkerInfo {
  const WorkerInfo({
    required this.workerId,
    this.name,
    this.hostname,
    this.operatingSystem,
    this.architecture,
    this.version,
    required this.isOnline,
    this.lastSeenAtUtc,
    this.sessionCount,
    this.cpuUsagePercent,
    this.memoryUsagePercent,
  });

  final String workerId;
  final String? name;
  final String? hostname;
  final String? operatingSystem;
  final String? architecture;
  final String? version;
  final bool isOnline;
  final String? lastSeenAtUtc;
  final int? sessionCount;
  final double? cpuUsagePercent;
  final double? memoryUsagePercent;

  factory WorkerInfo.fromJson(Map<String, dynamic> json) {
    return WorkerInfo(
      workerId: json['workerId'] as String? ?? '',
      name: json['name'] as String?,
      hostname: json['hostname'] as String?,
      operatingSystem: json['operatingSystem'] as String?,
      architecture: json['architecture'] as String?,
      version: json['version'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeenAtUtc: json['lastSeenAtUtc'] as String?,
      sessionCount: (json['sessionCount'] as num?)?.toInt(),
      cpuUsagePercent: (json['cpuUsagePercent'] as num?)?.toDouble(),
      memoryUsagePercent: (json['memoryUsagePercent'] as num?)?.toDouble(),
    );
  }

  String get displayName => (name?.isNotEmpty ?? false) ? name! : workerId;
}

class DoctorCheck {
  const DoctorCheck({required this.name, required this.ok, required this.detail});

  final String name;
  final bool ok;
  final String detail;

  factory DoctorCheck.fromJson(Map<String, dynamic> json) => DoctorCheck(
        name: json['name'] as String? ?? '',
        ok: json['ok'] as bool? ?? false,
        detail: json['detail'] as String? ?? '',
      );
}

class DoctorResult {
  const DoctorResult({required this.checks, required this.passedCount, required this.failedCount});

  final List<DoctorCheck> checks;
  final int passedCount;
  final int failedCount;

  factory DoctorResult.fromJson(Map<String, dynamic> json) => DoctorResult(
        checks: (json['checks'] as List? ?? const [])
            .whereType<Map>()
            .map((c) => DoctorCheck.fromJson(Map<String, dynamic>.from(c)))
            .toList(),
        passedCount: (json['passedCount'] as num?)?.toInt() ?? 0,
        failedCount: (json['failedCount'] as num?)?.toInt() ?? 0,
      );
}

class UpdateCheck {
  const UpdateCheck({
    required this.currentVersion,
    this.latestVersion,
    required this.updateAvailable,
    this.assetName,
    this.downloadUrl,
  });

  final String currentVersion;
  final String? latestVersion;
  final bool updateAvailable;
  final String? assetName;
  final String? downloadUrl;

  factory UpdateCheck.fromJson(Map<String, dynamic> json) => UpdateCheck(
        currentVersion: json['currentVersion'] as String? ?? '',
        latestVersion: json['latestVersion'] as String?,
        updateAvailable: json['updateAvailable'] as bool? ?? false,
        assetName: json['assetName'] as String?,
        downloadUrl: json['downloadUrl'] as String?,
      );
}

/// `corterm update --json` 的流式阶段。
class UpdateProgress {
  const UpdateProgress({required this.stage, this.version, this.bytes, this.message});

  final String stage; // check | download | extract | install | restart | done | error
  final String? version;
  final int? bytes;
  final String? message;

  bool get isError => stage == 'error';
  bool get isDone => stage == 'done';

  factory UpdateProgress.fromJson(Map<String, dynamic> json) => UpdateProgress(
        stage: json['stage'] as String? ?? '',
        version: json['version'] as String?,
        bytes: (json['bytes'] as num?)?.toInt(),
        message: json['message'] as String?,
      );
}

/// `corterm login --json` 的流式阶段。
class LoginStageData {
  const LoginStageData({
    required this.stage,
    this.verificationUri,
    this.userCode,
    this.expiresInSeconds,
    this.pollIntervalSeconds,
    this.message,
  });

  final String stage; // code | success | error
  final String? verificationUri;
  final String? userCode;
  final int? expiresInSeconds;
  final int? pollIntervalSeconds;
  final String? message;

  bool get isError => stage == 'error';
  bool get isSuccess => stage == 'success';

  factory LoginStageData.fromJson(Map<String, dynamic> json) => LoginStageData(
        stage: json['stage'] as String? ?? '',
        verificationUri: json['verificationUri'] as String?,
        userCode: json['userCode'] as String?,
        expiresInSeconds: (json['expiresInSeconds'] as num?)?.toInt(),
        pollIntervalSeconds: (json['pollIntervalSeconds'] as num?)?.toInt(),
        message: json['message'] as String?,
      );
}

class ServiceResult {
  const ServiceResult({required this.action, required this.ok, required this.message, this.error});

  final String action;
  final bool ok;
  final String message;
  final String? error;

  factory ServiceResult.fromJson(Map<String, dynamic> json) => ServiceResult(
        action: json['action'] as String? ?? '',
        ok: json['ok'] as bool? ?? false,
        message: json['message'] as String? ?? '',
        error: json['error'] as String?,
      );
}
