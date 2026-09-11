/// Session（Gateway 中的远程会话）领域模型。
///
/// Gateway 返回的 `status` / `attachmentState` 字符串对应
/// `SessionAttachmentState`（src/Gateway/.../Sessions/SessionAttachmentState.cs）：
/// Attached / DetachedGracePeriod / Expired / Exited / Recovering。
library;

enum SessionStatus { attached, detachedGracePeriod, recovering, exited, expired }

SessionStatus sessionStatusFrom(String raw) => switch (raw) {
      'Attached' => SessionStatus.attached,
      'DetachedGracePeriod' => SessionStatus.detachedGracePeriod,
      'Recovering' => SessionStatus.recovering,
      'Exited' => SessionStatus.exited,
      'Expired' => SessionStatus.expired,
      _ => throw FormatException('Unknown session attachment state: $raw'),
    };

extension SessionStatusX on SessionStatus {
  /// 会话进程是否仍然存活（PTY 还在跑，只是没有客户端附着）。
  bool get isAlive =>
      this == SessionStatus.attached ||
      this == SessionStatus.detachedGracePeriod ||
      this == SessionStatus.recovering;

  /// 选择器里是否归入 RUNNING 分组（§15）。
  bool get isRunning => isAlive;
}

/// Worker 端检测到的 Agent 类型（Shared/.../AgentDtos.cs）。
enum AgentKind { claudeCode, codex, opencode, none, unknown }

AgentKind agentKindFrom(String? raw) => switch (raw) {
      'claude-code' => AgentKind.claudeCode,
      'codex' => AgentKind.codex,
      'opencode' => AgentKind.opencode,
      'none' => AgentKind.none,
      _ => AgentKind.unknown,
    };

extension AgentKindX on AgentKind {
  String get label => switch (this) {
        AgentKind.claudeCode => 'Claude Code',
        AgentKind.codex => 'Codex',
        AgentKind.opencode => 'OpenCode',
        AgentKind.none => 'Shell',
        AgentKind.unknown => 'Session',
      };
}

class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.name,
    required this.workerId,
    this.workerName,
    required this.status,
    required this.createdAt,
    required this.lastActivityAt,
    this.agentKind = AgentKind.unknown,
    this.inferredTitle,
  });

  final String sessionId;

  /// 用户自定义名（PATCH 设置）。可能为空。
  final String name;
  final String workerId;
  final String? workerName;
  final SessionStatus status;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  final AgentKind agentKind;
  final String? inferredTitle;

  /// 显示名优先级（§55）：用户名 → worker 推断标题 → Agent + 短 ID。禁止裸 UUID。
  String get displayName {
    if (name.isNotEmpty) return name;
    if (inferredTitle != null && inferredTitle!.isNotEmpty) return inferredTitle!;
    if (agentKind != AgentKind.unknown) return agentKind.label;
    return 'Session ${sessionId.substring(0, 8.clamp(0, sessionId.length))}';
  }

  /// 二级信息（§12）：只挑一个最有价值的展示。
  String get subtitle => workerName ?? workerId;

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    final id = json['sessionId'] as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('Session summary missing sessionId');
    }
    return SessionSummary(
      sessionId: id,
      name: (json['name'] as String?) ?? '',
      workerId: (json['workerId'] as String?) ?? '',
      workerName: json['workerName'] as String?,
      status: sessionStatusFrom((json['status'] ?? json['attachmentState']) as String),
      createdAt: _parseDate(json['createdAtUtc'] ?? json['createdAt']),
      lastActivityAt: _parseDate(json['lastActivityAtUtc'] ?? json['lastActivityAt']),
      agentKind: agentKindFrom(json['agentKind'] as String?),
      inferredTitle: json['inferredTitle'] as String?,
    );
  }

  SessionSummary copyWith({String? name, SessionStatus? status}) => SessionSummary(
        sessionId: sessionId,
        name: name ?? this.name,
        workerId: workerId,
        workerName: workerName,
        status: status ?? this.status,
        createdAt: createdAt,
        lastActivityAt: lastActivityAt,
        agentKind: agentKind,
        inferredTitle: inferredTitle,
      );
}

DateTime _parseDate(Object? raw) {
  if (raw is String && raw.isNotEmpty) return DateTime.parse(raw);
  throw FormatException('Missing or invalid datetime: $raw');
}
