import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_bar.dart';
import '../data/feedback_repository.dart';

/// 意见反馈（对齐 MAUI FeedbackPage）：类型 + 内容 + 联系方式 + 最多 3 张配图。
/// 提交链路：选图 → presigned S3 直传 → n8n webhook → ticketId。
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _content = TextEditingController();
  final _contact = TextEditingController();

  bool _isBug = true;
  final List<_PendingImage> _images = [];
  bool _submitting = false;
  String? _ticketId;
  String? _error;

  static const _maxImages = 3;

  @override
  void dispose() {
    _content.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (picked == null) return;
    for (final f in picked.files) {
      if (_images.length >= _maxImages) break;
      final path = f.path;
      if (path == null) continue;
      final bytes = await File(path).readAsBytes();
      if (mounted) {
        setState(() => _images.add(_PendingImage(name: f.name, bytes: bytes)));
      }
    }
  }

  Future<void> _submit() async {
    if (_content.text.trim().isEmpty) return;
    setState(() {
      _error = null;
      _submitting = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(feedbackRepositoryProvider);
      final attachments = <String>[];
      for (final image in _images) {
        final grant =
            await repo.requestUpload(filename: image.name);
        await repo.putToStorage(uploadUrl: grant.uploadUrl, bytes: image.bytes);
        attachments.add(grant.imageUrl);
      }
      final info = await PackageInfo.fromPlatform();
      final username = ref.read(authProvider).username ?? '';
      final lang = mounted ? Localizations.localeOf(context).languageCode : 'en';
      final ticket = await repo.submit(
        type: _isBug ? 'bug' : 'suggestion',
        subtype: 'mobile',
        content: _content.text.trim(),
        contact: _contact.text.trim(),
        username: username,
        lang: lang,
        appVersion: '${info.version} (${info.buildNumber})',
        attachments: attachments,
      );
      if (!mounted) return;
      setState(() {
        _ticketId = ticket;
        _submitting = false;
      });
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: CortermAppBar(
        title: l10n.feedbackTitle,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: scheme.foreground),
          onPressed: () => context.pop(),
        ),
      ),
      body: _ticketId != null
          ? _DoneView(ticketId: _ticketId!)
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                ShadTabs<bool>(
                  value: _isBug,
                  onChanged: (v) => setState(() => _isBug = v),
                  tabs: [
                    ShadTab(value: true, child: Text(l10n.feedbackBug)),
                    ShadTab(value: false, child: Text(l10n.feedbackSuggestion)),
                  ],
                ),
                const SizedBox(height: 16),
                ShadInputFormField(
                  controller: _content,
                  label: Text(l10n.feedbackContent),
                  placeholder: Text(l10n.feedbackContentPlaceholder),
                  minLines: 5,
                  maxLines: 8,
                  enabled: !_submitting,
                ),
                const SizedBox(height: 16),
                ShadInputFormField(
                  controller: _contact,
                  label: Text(l10n.feedbackContact),
                  placeholder: Text(l10n.feedbackContactPlaceholder),
                  enabled: !_submitting,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      l10n.feedbackAttachments(_images.length, _maxImages),
                      style: TextStyle(fontSize: 14, color: scheme.mutedForeground),
                    ),
                    const Spacer(),
                    ShadButton.outline(
                      size: ShadButtonSize.sm,
                      enabled: !_submitting && _images.length < _maxImages,
                      onPressed: _pickImages,
                      child: Text(l10n.feedbackAddImage),
                    ),
                  ],
                ),
                if (_images.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _images.length; i++)
                        Stack(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: scheme.border),
                              ),
                              child: const Icon(Icons.image_outlined),
                            ),
                            Positioned(
                              right: -6,
                              top: -6,
                              child: IconButton(
                                icon: Icon(Icons.cancel_rounded,
                                    size: 20, color: scheme.destructive),
                                onPressed: _submitting
                                    ? null
                                    : () => setState(() => _images.removeAt(i)),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.destructive, fontSize: 14)),
                ],
                const SizedBox(height: 24),
                ShadButton(
                  enabled: !_submitting && _content.text.trim().isNotEmpty,
                  onPressed: _submit,
                  child: Text(_submitting ? l10n.feedbackSubmitting : l10n.feedbackSubmit),
                ),
              ],
            ),
    );
  }
}

class _PendingImage {
  _PendingImage({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(l10n.feedbackDone,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: scheme.foreground)),
            const SizedBox(height: 8),
            Text('Ticket: $ticketId',
                style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: scheme.mutedForeground)),
          ],
        ),
      ),
    );
  }
}
