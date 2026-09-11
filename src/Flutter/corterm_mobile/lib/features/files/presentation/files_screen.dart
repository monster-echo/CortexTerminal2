import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../shared/widgets/app_bar.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/states.dart';
import '../data/file_repository.dart';

/// 远程文件浏览（阶段4）：目录导航 + 上传 + 下载分享。
/// 入口：Workspace More Menu → Files。
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key, required this.sessionId, this.initialPath = '/'});

  final String sessionId;
  final String initialPath;

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  late String _path = widget.initialPath;
  late Future<FileListing> _future = _load(_path);

  bool _busy = false;

  Future<FileListing> _load(String path) {
    return ref.read(fileRepositoryProvider).list(sessionId: widget.sessionId, path: path);
  }

  void _open(String path) {
    setState(() {
      _path = path;
      _future = _load(path);
    });
  }

  Future<void> _refresh() async {
    setState(() => _future = _load(_path));
    await _future;
  }

  String _join(String dir, String name) =>
      dir.endsWith('/') ? '$dir$name' : '$dir/$name';

  Future<void> _download(FileEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final file = await ref.read(fileRepositoryProvider).download(
            sessionId: widget.sessionId,
            path: _join(_path, entry.name),
            filename: entry.name,
          );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: entry.name),
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '${l10n.downloadFailed}: $e', destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await FilePicker.pickFiles(withData: true);
    final picked = result?.files.firstOrNull;
    if (picked == null || picked.bytes == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(fileRepositoryProvider).upload(
            sessionId: widget.sessionId,
            dirPath: _path,
            filename: picked.name,
            bytes: picked.bytes ?? Uint8List(0),
          );
      if (!mounted) return;
      showAppToast(context, l10n.uploadDone);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '${l10n.uploadFailed}: $e', destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: CortermAppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: scheme.foreground),
          onPressed: () => context.pop(),
        ),
        title: l10n.filesTitle,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
              child: Text(
                _path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.mutedForeground),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: ShadButton(
        onPressed: _busy ? null : _upload,
        leading: _busy
            ? const SizedBox(width: 14, height: 14, child: ShadProgress())
            : const Icon(Icons.upload_file_outlined, size: 18),
        child: Text(l10n.upload),
      ),
      body: FutureBuilder<FileListing>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SmallSpinner();
          }
          if (snap.hasError) {
            return ErrorState(message: '${snap.error}', onRetry: _refresh);
          }
          final listing = snap.data!;
          // 目录在前、名称排序（与网关无关的稳定展示）。
          final entries = [...listing.entries]
            ..sort((a, b) {
              if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          final parent = _parentOf(_path);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (parent != null)
                  ListTile(
                    iconColor: scheme.mutedForeground,
                    textColor: scheme.foreground,
                    leading: const Icon(Icons.arrow_upward_rounded, size: 20),
                    title: const Text('..'),
                    onTap: () => _open(parent),
                  ),
                for (final e in entries)
                  ListTile(
                    iconColor: scheme.mutedForeground,
                    textColor: scheme.foreground,
                    leading: Icon(
                      e.isDirectory
                          ? Icons.folder_outlined
                          : Icons.insert_drive_file_outlined,
                      size: 20,
                    ),
                    title: Text(e.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: e.isDirectory
                        ? null
                        : Text(_fmtSize(e.sizeBytes),
                            style: TextStyle(
                                fontSize: 11, color: scheme.mutedForeground)),
                    trailing: e.isDirectory
                        ? Icon(Icons.chevron_right_rounded,
                            size: 20, color: scheme.mutedForeground)
                        : (_busy
                            ? null
                            : IconButton(
                                icon: Icon(Icons.download_outlined,
                                    size: 20, color: scheme.foreground),
                                onPressed: () => _download(e),
                              )),
                    onTap: e.isDirectory ? () => _open(_join(_path, e.name)) : null,
                  ),
                if (entries.isEmpty && parent != null)
                  SizedBox(
                    height: 160,
                    child: Center(
                      child: Text(
                        l10n.emptyFolder,
                        style: TextStyle(color: scheme.mutedForeground),
                      ),
                    ),
                  ),
                if (listing.truncated)
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
      ),
    );
  }

  String? _parentOf(String path) {
    if (path.isEmpty || path == '/') return null;
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return '/';
    return path.substring(0, idx);
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
