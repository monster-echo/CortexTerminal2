import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/list_group.dart';
import '../../../shared/widgets/states.dart';
import '../data/file_repository.dart';

/// 远端目录浏览器（核心复用组件）。
///
/// 三个场景共用这一份「列目录 + 导航 + 行渲染」：
/// - 工作区文件浏览（FilesScreen，workspace 通道）
/// - ungrouped 会话的终端 cwd 浏览（FilesScreen，worker 通道）
/// - 创建工作区的远端选文件夹（RemoteFolderPickerSheet，worker 通道）
///
/// 组件只管目录的呈现与导航；数据来源（哪个通道、哪个根）与文件动作
/// （上传/下载/分享）由调用方注入。Harmony 端对应物是 FileBrowserPage，
/// 后续抽 RemoteFolderPicker 时以此组件的职责划分为准。
class RemoteDirBrowser extends StatelessWidget {
  const RemoteDirBrowser({
    super.key,
    required this.future,
    required this.onRefresh,
    required this.path,
    required this.onNavigate,
    this.onFileTap,
    this.fileTrailing,
    this.dirsOnly = false,
    this.emptyHint,
  });

  /// 当前层目录数据（调用方按自己的通道/根解析后发起）。
  final Future<FileListing> future;

  /// 失败重试 / 下拉刷新（重新拉当前层）。
  final Future<void> Function() onRefresh;

  /// 当前相对路径（'' = 根）。
  final String path;

  /// 进入子目录 / 返回上级（传入目标相对路径）。
  final ValueChanged<String> onNavigate;

  /// 文件行点击（null = 文件行不可点）。
  final void Function(FileEntry entry)? onFileTap;

  /// 文件行 trailing（下载按钮等）。
  final Widget Function(FileEntry entry)? fileTrailing;

  /// true = 只显示目录（选文件夹模式）。
  final bool dirsOnly;

  /// 目录为空时的文案（缺省用通用「此文件夹为空」）。
  final String? emptyHint;

  String _join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

  String? _parentOf(String path) {
    if (path.isEmpty) return null;
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return '';
    return path.substring(0, idx);
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;
    final parent = _parentOf(path);

    return FutureBuilder<FileListing>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorState(
            message: '${snap.error}',
            onRetry: () => onRefresh(),
          );
        }
        if (!snap.hasData) {
          return const Center(child: ShadProgress(value: null));
        }
        final entries = snap
            .data!.entries
            .where((e) => !dirsOnly || e.isDirectory)
            .toList();
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: [
              if (parent != null)
                AppRow(
                  icon: LucideIcons.arrowUp,
                  label: '..',
                  onTap: () => onNavigate(parent),
                ),
              for (final e in entries)
                e.isDirectory
                    ? AppRow(
                        icon: LucideIcons.folder,
                        label: e.name,
                        chevron: true,
                        onTap: () => onNavigate(_join(path, e.name)),
                      )
                    : AppRow(
                        icon: LucideIcons.file,
                        label: e.name,
                        value: _fmtSize(e.sizeBytes),
                        trailing: fileTrailing?.call(e),
                        chevron: false,
                        onTap: onFileTap == null
                            ? null
                            : () => onFileTap!(e),
                      ),
              if (entries.isEmpty && parent == null)
                SizedBox(
                  height: 160,
                  child: Center(
                    child: Text(
                      emptyHint ?? l10n.emptyFolder,
                      style: TextStyle(color: scheme.mutedForeground),
                    ),
                  ),
                ),
              if (snap.data!.truncated)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.listTruncated,
                    style: TextStyle(color: scheme.mutedForeground),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
