import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/models/session.dart';
import '../../../../core/models/worker.dart';
import '../../../../features/session/session_state.dart';

/// Session/Gateway 状态 → 圆点颜色（§13）。颜色一律来自主题的 custom 状态槽。
Color sessionDotColor(ShadColorScheme scheme, SessionStatus status) =>
    switch (status) {
      SessionStatus.attached => scheme.success,
      SessionStatus.detachedGracePeriod => scheme.success,
      SessionStatus.recovering => scheme.warning,
      SessionStatus.exited => scheme.idle,
      SessionStatus.expired => scheme.idle,
    };

/// 终端连接状态 → AppBar 圆点颜色 + 是否闪烁。
(Color, bool) connDotStyle(ShadColorScheme scheme, TerminalConnState state) =>
    switch (state) {
      TerminalConnState.live => (scheme.success, false),
      TerminalConnState.idle => (scheme.idle, false),
      TerminalConnState.connecting ||
      TerminalConnState.replaying ||
      TerminalConnState.reconnecting ||
      TerminalConnState.workerOffline =>
        (scheme.warning, true),
      TerminalConnState.exited => (scheme.idle, false),
      TerminalConnState.error => (scheme.destructive, false),
    };

/// Worker 在线状态点。
Color workerDotColor(ShadColorScheme scheme, WorkerSummary worker) =>
    worker.isOnline ? scheme.success : scheme.idle;
