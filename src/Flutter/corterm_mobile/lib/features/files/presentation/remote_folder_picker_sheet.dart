import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
import '../data/file_repository.dart';
import 'remote_dir_browser.dart';

/// 远端文件夹选择器（创建工作区时必须选定远端机器上的一个 folder）。
/// 浏览根固定为 [initialRoot]（可往下钻、可回跳，不能越出根——与 Worker 端
/// 「root 须在用户 home 内」的校验一致），确认后返回根下所选目录的绝对路径。
Future<String?> showRemoteFolderPickerSheet(
  BuildContext context, {
  required String workerId,
  String? initialRoot,
}) {
  if (initialRoot == null || initialRoot.isEmpty) {
    // 无法定位浏览起点（无默认工作区根，也无会话 cwd）：如实报错，不猜。
    showAppToast(
      context,
      AppLocalizations.of(context)!.pickerNoStartPoint,
      destructive: true,
    );
    return Future.value(null);
  }
  return showCortermSheet<String>(
    context: context,
    builder: (_) => _RemoteFolderPickerSheet(
      workerId: workerId,
      startRoot: initialRoot,
    ),
  );
}

class _RemoteFolderPickerSheet extends ConsumerStatefulWidget {
  const _RemoteFolderPickerSheet({required this.workerId, required this.startRoot});

  final String workerId;
  final String startRoot;

  @override
  ConsumerState<_RemoteFolderPickerSheet> createState() =>
      _RemoteFolderPickerSheetState();
}

class _RemoteFolderPickerSheetState
    extends ConsumerState<_RemoteFolderPickerSheet> {
  String _path = '';
  late Future<FileListing> _future = _load();
  FileRepository get _repo => ref.read(fileRepositoryProvider);

  /// 浏览起点（absolute），确认时拼接出完整路径。
  String get _startRoot => widget.startRoot;

  Future<FileListing> _load() => _repo.listForWorker(
        workerId: widget.workerId,
        root: _startRoot,
        path: _path,
      );

  void _open(String path) {
    setState(() {
      _path = path;
      _future = _load();
    });
  }

  String get _absolute {
    final rel = _path.isEmpty ? '' : '/$_path';
    final root = _startRoot.endsWith('/') && _startRoot.length > 1
        ? _startRoot.substring(0, _startRoot.length - 1)
        : _startRoot;
    return '$root$rel';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.workspacePickTitle,
          style: theme.textTheme.large.copyWith(
            color: scheme.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _absolute,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.small.copyWith(
            color: scheme.mutedForeground,
            fontFamily: 'packages/shadcn_ui/GeistMono',
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: RemoteDirBrowser(
            future: _future,
            onRefresh: () async {
              setState(() => _future = _load());
              await _future;
            },
            path: _path,
            onNavigate: _open,
            dirsOnly: true,
            emptyHint: l10n.pickerNoSubfolders,
          ),
        ),
        const SizedBox(height: 20),
        ShadButton(
          onPressed: () => context.pop(_absolute),
          child: Text(l10n.workspacePickFolder),
        ),
      ],
    );
  }
}
