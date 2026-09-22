import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/file_reader.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/list_group.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
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
    final scheme = ShadTheme.of(context).colorScheme;
    final profile = ref.watch(profileProvider);
    final repo = ref.read(profileRepositoryProvider);

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: CortermAppBar(
        title: l10n.profileTitle,
        leading: ShadIconButton.ghost(
          foregroundColor: scheme.foreground,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: profile.when(
        loading: () => const Center(child: ShadProgress(value: null)),
        error: (e, _) => ErrorState(message: '$e'),
        data: (user) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            Center(
              child: GestureDetector(
                onTap: () => _changeAvatar(context, ref, user),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _Avatar(url: repo.resolveAvatarUrl(user.avatarUrl), size: 96),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: scheme.primary,
                        child: Icon(LucideIcons.camera,
                            size: 16, color: scheme.background),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            AppRow(
              icon: LucideIcons.user,
              label: l10n.username,
              value: user.username,
            ),
            if (_isRealEmail(user.email))
              AppRow(
                icon: LucideIcons.atSign,
                label: l10n.email,
                value: user.email!,
              ),
            AppRow(
              icon: LucideIcons.badge,
              label: l10n.displayNameLabel,
              value: (user.displayName?.isNotEmpty ?? false) ? user.displayName! : l10n.unknown,
              chevron: true,
              onTap: () => _editDisplayName(context, ref, user),
            ),
            const SizedBox(height: 16),
            AppRow(
              icon: LucideIcons.keyRound,
              label: l10n.hasPassword,
              value: user.hasPassword ? l10n.yes : l10n.no,
            ),
          ],
        ),
      ),
    );
  }

  /// 系统生成的临时邮箱（如 @corterm.dev）不属于用户真实资料，不展示。
  bool _isRealEmail(String? email) {
    if (email == null || email.isEmpty) return false;
    return !email.endsWith('@corterm.dev');
  }

  Future<void> _changeAvatar(
      BuildContext context, WidgetRef ref, UserProfile user) async {
    final l10n = AppLocalizations.of(context)!;
    // Web 端 file_picker 不产生文件路径，必须 withData 拿 bytes。
    final picked =
        await FilePicker.pickFiles(type: FileType.image, withData: kIsWeb);
    if (picked == null) return;
    final file = picked.files.single;
    if (kIsWeb ? file.bytes == null : file.path == null) return;
    if (!context.mounted) return;

    final bytes = await showCortermSheet<Uint8List>(
      context: context,
      builder: (_) => AvatarCropSheet(path: file.path, bytes: file.bytes),
    );
    if (bytes == null || bytes.isEmpty) return;

    try {
      await ref.read(profileRepositoryProvider).uploadAvatar(bytes);
      ref.invalidate(profileProvider);
      if (context.mounted) showAppToast(context, l10n.avatarUpdated);
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, '$e', destructive: true);
      }
    }
  }

  Future<void> _editDisplayName(
      BuildContext context, WidgetRef ref, UserProfile user) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: user.displayName ?? '');
    final name = await showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(l10n.displayNameLabel),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
        child: ShadInputFormField(
          controller: controller,
          placeholder: Text(l10n.displayNameLabel),
          maxLength: 32,
        ),
      ),
    );
    if (name == null) return;
    try {
      await ref.read(profileRepositoryProvider).updateDisplayName(name);
      ref.invalidate(profileProvider);
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, '$e', destructive: true);
      }
    }
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    final inner = ClipOval(
      child: url.isEmpty
          ? Container(
              width: size,
              height: size,
              color: scheme.muted,
              child: Icon(LucideIcons.user, size: size * 0.5, color: scheme.mutedForeground),
            )
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: size,
                height: size,
                color: scheme.muted,
                child:
                    Icon(LucideIcons.user, size: size * 0.5, color: scheme.mutedForeground),
              ),
            ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.border),
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

  Future<void> _confirm(BuildContext context, ui.Image image, Size viewport) async {
    const out = 512;
    // 取景框 → 原图坐标：用矩阵逆变换把视口中心/半径映射回子坐标系
    //（InteractiveViewer 的矩阵含绕心缩放，必须整体求逆）。
    final inverse = Matrix4.inverted(_transformation.value);
    final viewportCenter = Offset(viewport.width / 2, viewport.height / 2);
    final srcCenter = MatrixUtils.transformPoint(inverse, viewportCenter);
    final srcEdge = MatrixUtils.transformPoint(inverse, viewportCenter + Offset(viewport.width / 2, 0));
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
    if (data == null) {
      throw StateError('avatar crop: png encode failed');
    }
    if (context.mounted) {
      Navigator.of(context).pop(data.buffer.asUint8List());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;

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
                  color: scheme.muted,
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
                              style: TextStyle(
                                  color: scheme.destructive, fontSize: 13),
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
                        final baseScale = (box.maxWidth / image.width)
                            .clamp(box.maxHeight / image.height, double.infinity);
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
                      onPressed: () => _confirm(context, snap.data!, const Size(280, 280)),
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
