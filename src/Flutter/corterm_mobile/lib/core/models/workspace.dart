/// 工作区（产品概念：Worker 上的命名根目录，会话与文件管理的边界）。
library;

class Workspace {
  const Workspace({
    required this.workspaceId,
    required this.workerId,
    required this.name,
    this.rootPath,
    this.isDefault = false,
  });

  final String workspaceId;
  final String workerId;
  final String name;
  final String? rootPath;
  final bool isDefault;

  String get displayName => name.isNotEmpty ? name : (rootPath ?? workspaceId);

  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
        workspaceId:
            (json['workspaceId'] ?? json['id']) as String? ?? '',
        workerId: json['workerId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        rootPath: json['rootPath'] as String?,
        isDefault: json['isDefault'] as bool? ?? false,
      );
}
