import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/layout/adaptive_page_scaffold.dart';
import '../../../shared/widgets/states.dart';
import '../data/file_repository.dart';
import '../data/file_transfer_control.dart';
import 'file_error_message.dart';

/// Downloads supported previews only; other files wait for an explicit download.
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
  late Future<Uint8List> _future;
  bool _downloading = false;
  FileTransferControl? _downloadControl;
  @override
  void dispose() {
    _downloadControl?.cancel();
    super.dispose();
  }

  String _query = '';
  String? _text;
  bool get _isImage =>
      widget.sizeBytes <= 20 * 1024 * 1024 &&
      [
        '.png',
        '.jpg',
        '.jpeg',
        '.gif',
        '.webp',
        '.bmp',
      ].any(widget.name.toLowerCase().endsWith);
  bool get _isText =>
      widget.sizeBytes <= 512 * 1024 &&
      [
        '.txt',
        '.log',
        '.json',
        '.js',
        '.ts',
        '.jsx',
        '.tsx',
        '.py',
        '.sh',
        '.md',
        '.conf',
        '.yaml',
        '.yml',
        '.toml',
        '.xml',
        '.html',
        '.css',
        '.ini',
        '.env',
        '.sql',
        '.c',
        '.h',
        '.cpp',
        '.hpp',
        '.java',
        '.go',
        '.rs',
        '.rb',
        '.php',
        '.dart',
      ].any(widget.name.toLowerCase().endsWith);
  @override
  void initState() {
    super.initState();
    if (_isText || _isImage) _future = _load();
  }

  Future<Uint8List> _load() => ref
      .read(fileRepositoryProvider)
      .downloadBytes(workspaceId: widget.workspaceId, path: widget.path);
  Future<void> _download() async {
    if (_downloading) return;
    final control = FileTransferControl();
    setState(() {
      _downloading = true;
      _downloadControl = control;
    });
    try {
      final file = await ref
          .read(fileRepositoryProvider)
          .download(
            workspaceId: widget.workspaceId,
            path: widget.path,
            filename: widget.name,
            control: control,
          );
      control.checkCancelled();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [file], text: widget.name),
      );
    } catch (error) {
      if (mounted) {
        final cancelled = error is DioException && CancelToken.isCancel(error);
        showAppToast(
          context,
          cancelled
              ? (Localizations.localeOf(context).languageCode == 'zh'
                    ? '下载已取消'
                    : 'Download cancelled')
              : fileErrorMessage(context, error),
          destructive: !cancelled,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadControl = null;
        });
      }
      control.dispose();
    }
  }

  Widget _unsupported(BuildContext context, String reason) => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 48),
          const SizedBox(height: 16),
          Text(reason, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _downloading ? null : _download,
            icon: const Icon(Icons.download_outlined),
            label: Text(AppLocalizations.of(context)!.download),
          ),
        ],
      ),
    ),
  );
  Widget _preview(BuildContext context, Uint8List bytes) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final c = colorsOf(context);
    if (_isImage) {
      return InteractiveViewer(
        maxScale: 4,
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, error, stack) => _unsupported(
              context,
              zh
                  ? '图片无法解码，可下载后打开。'
                  : 'Cannot decode this image. Download it to open elsewhere.',
            ),
          ),
        ),
      );
    }
    try {
      _text = utf8.decode(bytes);
    } on FormatException {
      _text = null;
      return _unsupported(
        context,
        zh ? '此文件不是有效的 UTF-8 文本，请下载后选择正确编码打开。' : 'This file is not valid UTF-8. Download it and open with the correct encoding.',
      );
    }
    final text = _text!;
    final matches = _query.isEmpty
        ? <RegExpMatch>[]
        : RegExp(
            RegExp.escape(_query),
            caseSensitive: false,
          ).allMatches(text).toList();
    final spans = <TextSpan>[];
    var offset = 0;
    for (final match in matches) {
      spans.add(TextSpan(text: text.substring(offset, match.start)));
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            backgroundColor: c.surfaceSelected,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      offset = match.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: zh ? '在文件中查找' : 'Find in file',
            helperText: _query.isEmpty
                ? null
                : (zh ? '${matches.length} 处匹配' : '${matches.length} matches'),
          ),
        ),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              showAppToast(context, AppLocalizations.of(context)!.copied);
            }
          },
          icon: const Icon(Icons.copy),
          label: Text(zh ? '复制全文' : 'Copy all'),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: SelectableText.rich(
              TextSpan(children: spans),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: c.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Theme(
      data: cortermToolTheme(context),
      child: Builder(
        builder: (context) => AdaptivePageScaffold(
          appBar: AppBar(
            title: Text(
              widget.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (_downloading)
                IconButton(
                  tooltip: zh ? '取消下载' : 'Cancel download',
                  icon: const Icon(Icons.close),
                  onPressed: () => _downloadControl!.cancel(),
                ),
              IconButton(
                tooltip: l10n.download,
                icon: const Icon(Icons.download_outlined),
                onPressed: _downloading ? null : _download,
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_downloading) const LinearProgressIndicator(),
                Expanded(
                  child: !_isImage && !_isText
                      ? _unsupported(context, l10n.previewUnsupported)
                      : FutureBuilder<Uint8List>(
                          future: _future,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return ErrorState(
                                message: fileErrorMessage(
                                  context,
                                  snapshot.error,
                                ),
                                onRetry: () =>
                                    setState(() => _future = _load()),
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            return _preview(context, snapshot.data!);
                          },
                        ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  widget.path,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorsOf(context).textSecondary,
                  ),
                ),
                Text(
                  '${widget.sizeBytes} B · ${zh ? '只读' : 'Read only'}${_isText ? ' · UTF-8 preview' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorsOf(context).textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
