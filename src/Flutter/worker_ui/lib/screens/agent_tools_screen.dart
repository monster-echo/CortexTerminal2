import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/agent_tools.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/error_banner.dart';
import '../widgets/list_group.dart';
import '../widgets/section_header.dart';
import '../widgets/states.dart';

/// 常见 AI agent CLI 安装检测（Claude Code / Codex / Gemini CLI / OpenCode / Aider）。
class AgentToolsScreen extends StatefulWidget {
  const AgentToolsScreen({super.key});

  @override
  State<AgentToolsScreen> createState() => _AgentToolsScreenState();
}

class _AgentToolsScreenState extends State<AgentToolsScreen> {
  List<AgentToolStatus>? _result;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await detectAgentTools();
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.t;
    final scheme = ShadTheme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(
            title: t(context, 'agentTools.title'),
            trailing: ShadIconButton.ghost(
              onPressed: _detect,
              icon: Icon(LucideIcons.refreshCw, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          ErrorBanner(message: _error),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: SmallSpinner()))
          else if (_result != null)
            AppGroupCard(
              children: [
                for (var i = 0; i < _result!.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Builder(
                    builder: (context) {
                      final s = _result![i];
                      return AppRow(
                        icon: s.installed ? LucideIcons.circleCheck : LucideIcons.circleMinus,
                        iconColor: s.installed ? scheme.tertiary : scheme.mutedForeground,
                        label: s.tool.display,
                        value: s.installed
                            ? '${t(context, 'agentTools.installed')}'
                                '${s.version != null && s.version!.isNotEmpty ? '  ·  v${s.version}' : ''}'
                            : '${t(context, 'agentTools.notInstalled')}'
                                '  ·  ${t(context, 'agentTools.installHint')} ${s.tool.installHint}',
                        valueColor: s.installed ? scheme.tertiary : scheme.mutedForeground,
                      );
                    },
                  ),
                  if (_result![i].path != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
                      child: Text(
                        _result![i].path!,
                        style: TextStyle(color: scheme.mutedForeground, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
