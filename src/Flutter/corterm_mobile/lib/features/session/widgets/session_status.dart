import 'package:flutter/material.dart';

import '../../../../app/theme/corterm_theme.dart';
import '../../../../core/models/session.dart';
import '../../../../core/models/worker.dart';
import '../../../../features/session/session_state.dart';

/// Session/Gateway 状态 → 圆点颜色（语义色，design/07）。
Color sessionDotColor(CortermColors c, SessionStatus status) =>
    switch (status) {
      SessionStatus.attached => c.success,
      SessionStatus.detachedGracePeriod => c.success,
      SessionStatus.recovering => c.warning,
      SessionStatus.exited => c.textSecondary,
      SessionStatus.expired => c.textSecondary,
    };

/// 终端连接状态 → 圆点颜色 + 是否闪烁。
(Color, bool) connDotStyle(CortermColors c, TerminalConnState state) =>
    switch (state) {
      TerminalConnState.live => (c.success, false),
      TerminalConnState.idle => (c.textSecondary, false),
      TerminalConnState.connecting ||
      TerminalConnState.replaying ||
      TerminalConnState.reconnecting ||
      TerminalConnState.workerOffline =>
        (c.warning, true),
      TerminalConnState.exited => (c.textSecondary, false),
      TerminalConnState.error => (c.danger, false),
    };

/// Worker 在线状态点。
Color workerDotColor(CortermColors c, WorkerSummary worker) =>
    worker.isOnline ? c.success : c.textSecondary;
