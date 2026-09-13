import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/models/session.dart';
import '../../../../shared/widgets/connection_status_dot.dart';
import 'session_status.dart';

/// Session 列表项（Selector / Home / All Sessions 共用，§11/§12）。
/// 一级信息：Session Name；二级信息：Project/Worker 单行；左侧状态点；当前项右侧 ✓。
class SessionListItem extends StatelessWidget {
  const SessionListItem({
    super.key,
    required this.session,
    this.isCurrent = false,
    this.onTap,
    this.onLongPress,
  });

  final SessionSummary session;
  final bool isCurrent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            ConnectionStatusDot(
              color: sessionDotColor(session.status),
              pulse: session.status == SessionStatus.recovering,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: scheme.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    session.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: scheme.mutedForeground),
                  ),
                ],
              ),
            ),
            if (isCurrent)
              const Icon(LucideIcons.check, size: 20, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
