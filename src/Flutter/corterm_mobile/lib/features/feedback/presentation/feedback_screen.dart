import '../../../shared/layout/adaptive_sheet.dart';
import '../../../shared/layout/adaptive_page_scaffold.dart';

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/storage/app_preferences.dart';
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

  static const _feedbackType = 'feedback';
  final List<_PendingImage> _images = [];
  bool _submitting = false;
  late final String _draftKey;
  String? _ticketId;
  String? _error;

  static const _maxImages = 3;

  @override
  void initState() {
    super.initState();
    _draftKey = '${ref.read(workspaceMemoryPrefixProvider)}.feedback_draft';
    final prefs = ref.read(sharedPreferencesProvider);
    _content.text = prefs.getString('$_draftKey.content') ?? '';
    _contact.text = prefs.getString('$_draftKey.contact') ?? '';
    _content.addListener(_contentChanged);
    _contact.addListener(_contentChanged);
  }

  Future<void> _contentChanged() async {
    if (mounted) setState(() {});
    if (_ticketId != null) return;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString('$_draftKey.content', _content.text);
      await prefs.setString('$_draftKey.contact', _contact.text);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _content.removeListener(_contentChanged);
    _content.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    // withData：web 无文件路径，统一让 picker 直接带字节（三端一致）。
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || !mounted) return;
    for (final f in picked.files) {
      if (_images.length >= _maxImages) break;
      final bytes = f.bytes;
      if (bytes == null) continue;
      if (mounted) {
        setState(() => _images.add(_PendingImage(name: f.name, bytes: bytes)));
      }
    }
  }

  Future<void> _submit() async {
    if (_submitting || _content.text.trim().length < 10) return;
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      final repo = ref.read(feedbackRepositoryProvider);
      final attachments = <String>[];
      for (final image in _images) {
        if (image.uploadedUrl == null) {
          final grant = await repo.requestUpload(filename: image.name);
          await repo.putToStorage(
            uploadUrl: grant.uploadUrl,
            bytes: image.bytes,
          );
          image.uploadedUrl = grant.imageUrl;
        }
        attachments.add(image.uploadedUrl!);
      }
      final info = await PackageInfo.fromPlatform();
      final username = ref.read(authProvider).username ?? '';
      final lang = mounted
          ? Localizations.localeOf(context).languageCode
          : 'en';
      final ticket = await repo.submit(
        type: _feedbackType,
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
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.remove('$_draftKey.content');
      await prefs.remove('$_draftKey.contact');
    } catch (e) {
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
    final theme = ShadTheme.of(context);
    final c = colorsOf(context);

    return AdaptivePageScaffold(
      backgroundColor: c.background,
      appBar: CortermAppBar(
        title: l10n.feedbackTitle,
        leading: ShadIconButton.ghost(
          foregroundColor: c.textPrimary,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: _ticketId != null
          ? _DoneView(ticketId: _ticketId!)
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Text(
                  Localizations.localeOf(context).languageCode == 'zh'
                      ? '文字草稿自动保存在本机。联系方式选填；描述发生的问题和操作步骤即可，请勿附带密码或访问密钥。'
                      : 'Text drafts are saved on this device. Contact details are optional. Describe the issue and steps without passwords or access keys.',
                ),
                const SizedBox(height: 16),
                ShadInputFormField(
                  controller: _content,
                  label: Text(l10n.feedbackContent),
                  placeholder: Text(l10n.feedbackContentPlaceholder),
                  minLines: 6,
                  maxLines: 8,
                  enabled: !_submitting,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.feedbackMinimumLength,
                        style: theme.textTheme.small.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '${_content.text.trim().length}',
                      style: theme.textTheme.small.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ShadInputFormField(
                  controller: _contact,
                  label: Text(l10n.feedbackContact),
                  placeholder: Text(l10n.feedbackContactPlaceholder),
                  enabled: !_submitting,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.feedbackAttachments(_images.length, _maxImages),
                        style: theme.textTheme.small.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                    ShadButton.outline(
                      size: ShadButtonSize.sm,
                      enabled: !_submitting && _images.length < _maxImages,
                      onPressed: _pickImages,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.imagePlus, size: 16),
                          const SizedBox(width: 6),
                          Text(l10n.feedbackAddImage),
                        ],
                      ),
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
                                border: Border.all(color: c.divider),
                              ),
                              child: GestureDetector(
                                onTap: () => showCortermDialog<void>(
                                  context: context,
                                  builder: (ctx) => Dialog(
                                    child: InteractiveViewer(
                                      child: Image.memory(_images[i].bytes),
                                    ),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    _images[i].bytes,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: -6,
                              top: -6,
                              child: ShadIconButton.ghost(
                                foregroundColor: c.danger,
                                icon: const Icon(LucideIcons.x, size: 20),
                                // shadcn 只认 enabled:，onPressed: null 不会置灰
                                enabled: !_submitting,
                                onPressed: () =>
                                    setState(() => _images.removeAt(i)),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.small.copyWith(color: c.danger),
                  ),
                ],
                const SizedBox(height: 24),
                ShadButton(
                  enabled: !_submitting && _content.text.trim().length >= 10,
                  onPressed: _submit,
                  child: Text(
                    _submitting ? l10n.feedbackSubmitting : l10n.feedbackSubmit,
                  ),
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
  String? uploadedUrl;
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final c = colorsOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.circleCheck, size: 56, color: c.accent),
            const SizedBox(height: 16),
            Text(
              l10n.feedbackDone,
              style: theme.textTheme.small.copyWith(
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ticket: $ticketId',
              style: theme.textTheme.muted.copyWith(
                fontFamily: 'monospace',
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
