import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/models/session.dart';
import '../../../../core/models/worker.dart';
import '../../../../features/workspace/workspace_state.dart';

/// Session/Gateway 状态 → 圆点颜色（§13）。
Color sessionDotColor(SessionStatus status) => switch (status) {
      SessionStatus.attached => AppColors.statusRunning,
      SessionStatus.detachedGracePeriod => AppColors.statusRunning,
      SessionStatus.recovering => AppColors.statusWaiting,
      SessionStatus.exited => AppColors.statusEnded,
      SessionStatus.expired => AppColors.statusEnded,
    };

/// 终端连接状态 → AppBar 圆点颜色 + 是否闪烁。
(Color, bool) connDotStyle(TerminalConnState state) => switch (state) {
      TerminalConnState.live => (AppColors.statusRunning, false),
      TerminalConnState.idle => (AppColors.statusEnded, false),
      TerminalConnState.connecting ||
      TerminalConnState.replaying ||
      TerminalConnState.reconnecting =>
        (AppColors.statusWaiting, true),
      TerminalConnState.exited => (AppColors.statusEnded, false),
      TerminalConnState.error => (AppColors.statusError, false),
    };

/// Worker 在线状态点。
Color workerDotColor(WorkerSummary worker) =>
    worker.isOnline ? AppColors.statusRunning : AppColors.statusEnded;
