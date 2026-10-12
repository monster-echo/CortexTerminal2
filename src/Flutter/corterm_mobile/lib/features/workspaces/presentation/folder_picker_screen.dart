import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../files/data/file_repository.dart';
import '../../sessions/data/sessions_providers.dart';

/// 远端文件夹选择页（design/02 §4）：点文件夹行进入目录，底部确认返回当前目录绝对路径。
///
/// 记忆每台电脑上次选择的目录；上级、主目录和搜索在错误状态下也可用。
class FolderPickerScreen extends ConsumerStatefulWidget {
  const FolderPickerScreen({super.key, required this.workerId});

  final String workerId;

  @override
  ConsumerState<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends ConsumerState<FolderPickerScreen> {
  String _rel = '';
  String _query = '';
  final _search = TextEditingController();
  bool _creatingDir = false;
  int _loadSeq = 0; // 丢弃过期请求的响应（快速连续导航时）
  FileListing? _listing;
  Object? _error;
  bool _loading = true;

  String _root = '.';

  @override
  void initState() {
    super.initState();
    final remembered = ref
        .read(sharedPreferencesProvider)
        .getString('workspace.last_folder.${widget.workerId}');
    if (remembered != null &&
        (remembered == '.' || remembered.startsWith('./'))) {
      _rel = remembered == '.' ? '' : remembered.substring(2);
    } else if (remembered != null && remembered.startsWith('/')) {
      _root = remembered;
    }
    _load();
  }

  /// 加载当前目录；结果写入显式状态（loading/error/data）。
  /// 错误是页面状态而不是 future 异常——错误态要保留导航出口，且可测试。
  Future<void> _load() async {
    final seq = ++_loadSeq;
    if (mounted) setState(() => _loading = true);
    try {
      final listing = await ref
          .read(fileRepositoryProvider)
          .listForWorker(
            workerId: widget.workerId,
            root: _rel.isEmpty ? _root : '$_root/$_rel',
            path: '',
          );
      if (seq != _loadSeq || !mounted) return;
      setState(() {
        _listing = listing;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (seq != _loadSeq || !mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(String rel) {
    _search.clear();
    setState(() {
      _rel = rel;
      _query = '';
    });
    _load();
  }

  void _back() {
    if (_rel.isEmpty) {
      if (_root == '.') return;
      _root = _root.substring(0, _root.lastIndexOf('/'));
      if (_root.isEmpty) _root = '/';
      _open('');
      return;
    }
    _open(_rel.contains('/') ? _rel.substring(0, _rel.lastIndexOf('/')) : '');
  }

  void _toStart() {
    _root = '.';
    _open('');
  }

  bool get _canUp => _rel.isNotEmpty || (_root != '.' && _root != '/');

  String get _absolute {
    final root = _root;
    final trimmed = root.endsWith('/') && root.length > 1
        ? root.substring(0, root.length - 1)
        : root;
    return _rel.isEmpty ? trimmed : '$trimmed/$_rel';
  }

  Future<void> _jumpPath() async {
    final l10n = AppLocalizations.of(context)!;
    final input = TextEditingController(text: _absolute);
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.folderGo),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.folderPathHint),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, input.text),
            child: Text(l10n.jump),
          ),
        ],
      ),
    );
    input.dispose();
    if (!mounted || selected == null || selected.trim().isEmpty) return;
    final path = selected.trim().replaceFirst(RegExp(r'^~(?=/|$)'), '.');
    if (path.startsWith('/')) {
      _root = path;
      _open('');
    } else {
      _root = '.';
      _open(path == '.' ? '' : path.replaceFirst(RegExp(r'^\./'), ''));
    }
  }

  Future<void> _createDirectory() async {
    final l10n = AppLocalizations.of(context)!;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(l10n.folderNew),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.folderName),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                final v = controller.text.trim();
                if (v.isNotEmpty) Navigator.pop(dialogContext, v);
              },
              child: Text(l10n.create),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    if (!mounted) return;

    final fullRel = _rel.isEmpty ? name : '$_rel/$name';
    setState(() => _creatingDir = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(fileRepositoryProvider)
          .mkdirForWorker(
            workerId: widget.workerId,
            root: _absolute,
            path: name,
          );
      if (!mounted) return;
      _open(fullRel);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _creatingDir = false);
    }
  }

  /// 目录列表主体：loading / error / data 三态。错误态保留导航出口
  /// （返回上级 / 回到起点 / 重试），不存在走不出来的目录。
  Widget _buildBody(CortermColors colors) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_error',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.danger, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_canUp)
                  TextButton(onPressed: _back, child: Text(l10n.folderUp)),
                TextButton(onPressed: _toStart, child: Text(l10n.folderStart)),
                TextButton(onPressed: _load, child: Text(l10n.retry)),
              ],
            ),
          ],
        ),
      );
    }
    final q = _query.trim().toLowerCase();
    final dirs =
        (_listing?.entries ?? const [])
            .where((e) => e.isDirectory)
            .where((e) => q.isEmpty || e.name.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return RefreshIndicator(
      onRefresh: () async => _open(_rel),
      child: ListView(
        children: [
          if (_canUp)
            ListRow(
              title: l10n.folderUp,
              leading: Icon(Icons.arrow_upward, color: colors.accent),
              onTap: _back,
            ),
          if (dirs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: EmptyState(
                icon: Icons.folder_open,
                message: q.isEmpty
                    ? l10n.pickerNoSubfolders
                    : l10n.folderNoMatches,
              ),
            ),
          for (final d in dirs)
            ListRow(
              title: d.name,
              leading: const Icon(Icons.folder, size: 18),
              onTap: () => _open(_rel.isEmpty ? d.name : '$_rel/${d.name}'),
              trailing: const Icon(Icons.chevron_right, size: 18),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final workersAsync = ref.watch(workersProvider);
    final worker = (workersAsync.value ?? const [])
        .where((w) => w.workerId == widget.workerId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(l10n.selectFolderTitle),
        actions: [
          IconButton(
            tooltip: l10n.folderGo,
            icon: const Icon(Icons.drive_file_move_outline),
            onPressed: _jumpPath,
          ),
          IconButton(
            tooltip: l10n.folderNew,
            icon: _creatingDir
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.create_new_folder_outlined),
            onPressed: _creatingDir ? null : _createDirectory,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              worker?.displayName ?? l10n.computersTitle,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(fontSize: 14, color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.folderSearch,
                hintStyle: TextStyle(fontSize: 14, color: colors.textSecondary),
                prefixIcon: Icon(
                  Icons.search,
                  size: 20,
                  color: colors.textSecondary,
                ),
                isDense: true,
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _toStart,
                  icon: const Icon(Icons.home_outlined, size: 16),
                  label: Text(l10n.folderStart),
                ),
                if (_absolute != '.') ...[
                  Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                  TextButton(
                    onPressed: _jumpPath,
                    child: Text(_absolute, maxLines: 1),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody(colors)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: PrimaryButton(
                label: l10n.useCurrentFolder,
                onPressed: _loading || _error != null || _creatingDir
                    ? null
                    : () => Navigator.pop(context, _absolute),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
