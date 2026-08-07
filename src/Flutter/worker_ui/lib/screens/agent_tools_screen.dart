import 'package:flutter/material.dart';

import '../core/agent_tools.dart';
import '../l10n/app_strings.dart';
import '../widgets/error_banner.dart';
import '../widgets/section_header.dart';

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
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(
            title: t(context, 'agentTools.title'),
            trailing: IconButton(onPressed: _detect, icon: const Icon(Icons.refresh)),
          ),
          const SizedBox(height: 8),
          ErrorBanner(message: _error),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (_result != null)
            ..._result!.map(
              (s) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    s.installed ? Icons.check_circle_outline : Icons.remove_circle_outline,
                    color: s.installed ? scheme.tertiary : scheme.outline,
                  ),
                  title: Text(s.tool.display, style: const TextStyle(fontSize: 15)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s.installed)
                        Text(
                          '${t(context, 'agentTools.installed')}'
                          '${s.version != null && s.version!.isNotEmpty ? '  ·  v${s.version}' : ''}',
                          style: TextStyle(color: scheme.tertiary, fontSize: 13),
                        )
                      else
                        Text(
                          '${t(context, 'agentTools.notInstalled')}'
                          '  ·  ${t(context, 'agentTools.installHint')} ${s.tool.installHint}',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                        ),
                      if (s.path != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            s.path!,
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
