import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/states.dart';
import '../data/file_repository.dart';

/// 文件就地预览（对齐 ArkTS FilePreviewPage）：
/// image → 全屏 Contain；text/code（≤512KB）→ 等宽滚动；
/// 其他类型 → 图标 + 大小 + 下载按钮。
class FilePreviewScreen extends ConsumerStatefulWidget {
  const FilePreviewScreen({
    super.key,
    required this.workspaceId,
    required this.path,
    required this.name,
    required this.sizeBytes,
  });

  final String workspaceId;
  final String path;
  final String name;
  final int sizeBytes;

  @override
  ConsumerState<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends ConsumerState<FilePreviewScreen> {
  late Future<Uint8List> _future = _load();
  bool _downloading = false;

  bool get _isImage {
    const exts = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'];
    return exts.any(widget.name.toLowerCase().endsWith);
  }

  bool get _isText {
    const exts = [
      '.txt', '.log', '.json', '.js', '.ts', '.jsx', '.tsx', '.py', '.sh',
      '.md', '.conf', '.yaml', '.yml', '.toml', '.xml', '.html', '.css',
      '.ini', '.env', '.sql', '.c', '.h', '.cpp', '.hpp', '.java', '.go',
      '.rs', '.rb', '.php', '.dart',
    ];
    return widget.sizeBytes <= 512 * 1024 &&
        exts.any(widget.name.toLowerCase().endsWith);
  }

  Future<Uint8List> _load() {
    return ref
        .read(fileRepositoryProvider)
        .downloadBytes(workspaceId: widget.workspaceId, path: widget.path);
  }

  Future<void> _download() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _downloading = true);
    try {
      final file = await ref.read(fileRepositoryProvider).download(
            workspaceId: widget.workspaceId,
            path: widget.path,
            filename: widget.name,
          );
      await SharePlus.instance.share(
        ShareParams(files: [file], text: widget.name),
      );
    } catch (e) {
      if (mounted) {
        showAppToast(context, '${l10n.downloadFailed}: $e', destructive: true);
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // 文件页属于 Dark Tool Context（design/05 §8）。
    return Theme(
      data: cortermDarkToolTheme(),
      child: Builder(builder: (context) {
    final c = colorsOf(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        title: Text(
          widget.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<Uint8List>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) {
                return ErrorState(
                  message: '${snap.error}',
                  onRetry: () => setState(() => _future = _load()),
                );
              }
              if (!snap.hasData) {
                return const Center(child: ShadProgress(value: null));
              }
              final bytes = snap.data!;
              Widget content;
              if (_isImage) {
                content = Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: InteractiveViewer(
                      maxScale: 4,
                      child: Center(
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                );
              } else if (_isText) {
                content = Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.divider),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        String.fromCharCodes(bytes),
                        style: TextStyle(
                          fontFamily: 'packages/shadcn_ui/GeistMono',
                          fontSize: 13,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                );
              } else {
                content = Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.fileQuestion,
                            size: 48, color: c.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          l10n.previewUnsupported,
                          style: TextStyle(fontSize: 15, color: c.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fmtSize(widget.sizeBytes),
                          style: TextStyle(
                              fontSize: 13, color: c.textSecondary),
                        ),
                        const SizedBox(height: 20),
                        ShadButton.outline(
                          enabled: !_downloading,
                          onPressed: _download,
                          leading: _downloading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: ShadProgress(value: null))
                              : const Icon(LucideIcons.download, size: 16),
                          child: Text(l10n.download),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  content,
                  const SizedBox(height: 8),
                  Text(
                    _fmtSize(widget.sizeBytes),
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
      }),
    );
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
