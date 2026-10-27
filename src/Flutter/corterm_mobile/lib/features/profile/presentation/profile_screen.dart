import '../../../shared/layout/adaptive_page_scaffold.dart';

import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/file_reader.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
import '../../../shared/widgets/unsaved_changes_guard.dart';
import '../data/profile_repository.dart';

/// 资料页：头像（选图 → 圆形裁剪 → 上传）+ 显示名。
final profileProvider = FutureProvider<UserProfile>((ref) {
  return ref.read(profileRepositoryProvider).get();
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final c = colorsOf(context);
    final profile = ref.watch(profileProvider);
    final repo = ref.read(profileRepositoryProvider);

    return AdaptivePageScaffold(
      backgroundColor: c.background,
      appBar: CortermAppBar(
        title: l10n.profileTitle,
        leading: ShadIconButton.ghost(
          foregroundColor: c.textPrimary,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: profile.when(
        loading: () => const Center(child: ShadProgress(value: null)),
        error: (e, _) => ErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (user) => _ProfileEditor(
          initialName: user.displayName ?? '',
          avatarUrl: repo.resolveAvatarUrl(user.avatarUrl),
          onAvatar: () => _changeAvatar(context, ref, user),
          onSave: repo.updateDisplayName,
          onSaved: () => ref.invalidate(profileProvider),
        ),
      ),
    );
  }

  Future<void> _changeAvatar(
    BuildContext context,
    WidgetRef ref,
    UserProfile user,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    // Web 端 file_picker 不产生文件路径，必须 withData 拿 bytes。
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.image,
        withData: kIsWeb,
      );
      if (picked == null) return;
      if (!context.mounted) return;
      final file = picked.files.single;
      if (kIsWeb ? file.bytes == null : file.path == null) {
        throw StateError(
          Localizations.localeOf(context).languageCode == 'zh'
              ? '无法读取选择的图片。'
              : 'Cannot read selected image.',
        );
      }
      if (!context.mounted) return;

      final bytes = await showCortermSheet<Uint8List>(
        context: context,
        builder: (_) => AvatarCropSheet(path: file.path, bytes: file.bytes),
      );
      if (bytes == null || bytes.isEmpty) return;

      await ref.read(profileRepositoryProvider).uploadAvatar(bytes);
      ref.invalidate(profileProvider);
      if (context.mounted) showAppToast(context, l10n.avatarUpdated);
    } catch (e) {
      if (context.mounted) showAppToast(context, '$e', destructive: true);
    }
  }
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({
    required this.initialName,
    required this.avatarUrl,
    required this.onAvatar,
    required this.onSave,
    required this.onSaved,
  });
  final String initialName;
  final String avatarUrl;
  final VoidCallback onAvatar;
  final Future<void> Function(String) onSave;
  final VoidCallback onSaved;
  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final TextEditingController _controller;
  late String _savedName;
  bool _saving = false;
  String? _error;
  bool get _canSave =>
      !_saving &&
      _controller.text.trim().isNotEmpty &&
      _controller.text.trim() != _savedName;
  @override
  void initState() {
    super.initState();
    _savedName = widget.initialName.trim();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final name = _controller.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(name);
      if (!mounted) return;
      _savedName = name;
      FocusScope.of(context).unfocus();
      showAppToast(
        context,
        Localizations.localeOf(context).languageCode == 'zh'
            ? '资料已保存'
            : 'Profile saved',
      );
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return UnsavedChangesGuard(
      dirty: _controller.text.trim() != _savedName,
      busy: _saving,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Center(
            child: Semantics(
              button: true,
              label: zh ? '修改头像' : 'Change avatar',
              child: GestureDetector(
                onTap: _saving ? null : widget.onAvatar,
                child: _Avatar(url: widget.avatarUrl, size: 72),
              ),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: _saving ? null : widget.onAvatar,
              child: Text(zh ? '修改头像' : 'Change avatar'),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.displayNameLabel,
            style: TextStyle(fontSize: 14, color: c.textSecondary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            enabled: !_saving,
            maxLength: 32,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              hintText: l10n.displayNameLabel,
              filled: true,
              fillColor: c.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _canSave ? _save : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.save),
          ),
          if (_controller.text.trim() != _savedName)
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() {
                      _controller.text = _savedName;
                      _error = null;
                    }),
              child: Text(l10n.cancel),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final inner = ClipOval(
      child: url.isEmpty
          ? Container(
              width: size,
              height: size,
              color: c.surfaceElevated,
              child: Icon(
                LucideIcons.user,
                size: size * 0.5,
                color: c.textSecondary,
              ),
            )
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // 头像按显示尺寸降采样解码（Play Vitals: downsample bitmaps）
              cacheWidth:
                  (size * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, _, _) => Container(
                width: size,
                height: size,
                color: c.surfaceElevated,
                child: Icon(
                  LucideIcons.user,
                  size: size * 0.5,
                  color: c.textSecondary,
                ),
              ),
            ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.divider),
      ),
      child: inner,
    );
  }
}

/// 圆形头像裁剪：固定圆形取景框，图片在框内平移/缩放，确认后按变换矩阵
/// 映射回原图坐标，经 dart:ui 裁切导出 512×512 PNG。
class AvatarCropSheet extends StatefulWidget {
  const AvatarCropSheet({super.key, this.path, this.bytes});

  /// 移动端文件路径；Web 端为 null，用 [bytes]。
  final String? path;

  /// Web 端 file_picker 直接给出的图片字节。
  final Uint8List? bytes;

  @override
  State<AvatarCropSheet> createState() => _AvatarCropSheetState();
}

class _AvatarCropSheetState extends State<AvatarCropSheet> {
  final _transformation = TransformationController(Matrix4.identity());
  late final Future<ui.Image> _image;

  @override
  void initState() {
    super.initState();
    _image = _load();
  }

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  Future<ui.Image> _load() async {
    final Uint8List bytes;
    if (widget.bytes != null) {
      bytes = widget.bytes!;
    } else if (widget.path != null) {
      bytes = await readFileBytes(widget.path!);
    } else {
      throw StateError('avatar crop: no image source');
    }
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }

  Future<void> _confirm(
    BuildContext context,
    ui.Image image,
    Size viewport,
  ) async {
    const out = 512;
    // 取景框 → 原图坐标：用矩阵逆变换把视口中心/半径映射回子坐标系
    //（InteractiveViewer 的矩阵含绕心缩放，必须整体求逆）。
    final inverse = Matrix4.inverted(_transformation.value);
    final viewportCenter = Offset(viewport.width / 2, viewport.height / 2);
    final srcCenter = MatrixUtils.transformPoint(inverse, viewportCenter);
    final srcEdge = MatrixUtils.transformPoint(
      inverse,
      viewportCenter + Offset(viewport.width / 2, 0),
    );
    final srcRadius = (srcEdge.dx - srcCenter.dx).abs();
    final side = srcRadius * 2;
    final src = Rect.fromCenter(
      center: srcCenter,
      width: side.clamp(1.0, image.width.toDouble()),
      height: side.clamp(1.0, image.height.toDouble()),
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, out.toDouble(), out.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(out, out);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('avatar crop: png encode failed');
    if (context.mounted) Navigator.of(context).pop(data.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = colorsOf(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: SizedBox(
                width: 280,
                height: 280,
                child: ColoredBox(
                  color: c.surfaceElevated,
                  child: LayoutBuilder(
                    builder: (context, box) => FutureBuilder<ui.Image>(
                      future: _image,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          // 图片加载失败必须可见，绝不静默转圈。
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              '${snap.error}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.danger, fontSize: 13),
                            ),
                          );
                        }
                        if (!snap.hasData) {
                          return const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: ShadProgress(value: null),
                            ),
                          );
                        }
                        final image = snap.data!;
                        final baseScale = (box.maxWidth / image.width).clamp(
                          box.maxHeight / image.height,
                          double.infinity,
                        );
                        return InteractiveViewer(
                          transformationController: _transformation,
                          panEnabled: true,
                          scaleEnabled: true,
                          minScale: baseScale * 0.5,
                          maxScale: baseScale * 8,
                          boundaryMargin: const EdgeInsets.all(double.infinity),
                          child: RawImage(
                            image: image,
                            width: image.width.toDouble(),
                            height: image.height.toDouble(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ShadButton.outline(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FutureBuilder<ui.Image>(
                    future: _image,
                    builder: (context, snap) => ShadButton(
                      enabled: snap.hasData,
                      onPressed: () =>
                          _confirm(context, snap.data!, const Size(280, 280)),
                      child: Text(l10n.save),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
