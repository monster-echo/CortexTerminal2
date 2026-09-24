import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/workspace.dart';

/// 工作区管理（Gateway /api/workspaces*）：列出 / 创建 / 删除。
/// 文件浏览走 files 侧 FileRepository；这里只管工作区实体本身。
class WorkspaceRepository {
  WorkspaceRepository(this._client);

  final ApiClient _client;

  Future<List<Workspace>> list() async {
    List<Map<String, dynamic>> raw;
    try {
      final list = await _client.getList('/api/workspaces');
      raw = list.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
    return raw.map(Workspace.fromJson).toList();
  }

  Future<Workspace> create({
    required String workerId,
    required String name,
    required String rootPath,
  }) async {
    Map<String, dynamic> json;
    try {
      json = await _client.postMap('/api/workspaces', {
        'workerId': workerId,
        'name': name,
        'rootPath': rootPath,
      });
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
    return Workspace.fromJson(json);
  }

  /// 默认工作区与有绑定会话的工作区，网关会以 400 拒绝——错误原样上抛。
  Future<void> delete(String workspaceId) async {
    try {
      await _client.delete('/api/workspaces/$workspaceId');
    } on DioException catch (e) {
      ApiClient.throwFor(e);
    }
  }
}

final workspaceRepositoryProvider = Provider<WorkspaceRepository>((ref) {
  return WorkspaceRepository(ref.watch(apiClientProvider));
});

/// 按Worker 过滤的工作区列表（detail sheet / 会话创建选择器共用）。
final workerWorkspacesProvider =
    FutureProvider.family<List<Workspace>, String>((ref, workerId) async {
  final all = await ref.watch(workspaceRepositoryProvider).list();
  return all.where((w) => w.workerId == workerId).toList()
    ..sort((a, b) => b.isDefault == a.isDefault
        ? a.name.compareTo(b.name)
        : b.isDefault
            ? 1
            : -1);
});
