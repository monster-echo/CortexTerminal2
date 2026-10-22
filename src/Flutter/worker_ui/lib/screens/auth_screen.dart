import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/corterm_service.dart';
import '../core/app_scope.dart';
import '../core/models.dart';
import '../core/worker_process_controller.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/error_banner.dart';
import '../widgets/list_group.dart';
import '../widgets/primary_button.dart';
import '../widgets/states.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late CortermService _service;
  bool _started = false;
  bool _loading = true;
  bool? _authenticated;
  String? _user;
  String? _authExpiry;
  String? _error;
  bool _loggingIn = false;
  bool _autoLoginStarted = false;
  LoginStageData? _code;
  String? _loginMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _service = AppScope.of(context).service;
    if (!_started) {
      _started = true;
      _loadStatus();
    }
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _service.status();
      if (!mounted) return;
      setState(() {
        _authenticated = s.authenticated;
        _user = s.user;
        _authExpiry = s.authExpiry;
        _loading = false;
      });
      // 未认证时自动发起登录：进入页面即显示二维码，不用再点一次「登录」。
      if (!s.authenticated && !_autoLoginStarted) {
        _autoLoginStarted = true;
        await _login();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _login() async {
    setState(() {
      _loggingIn = true;
      _error = null;
      _loginMessage = null;
      _code = null;
    });
    try {
      await for (final stage in _service.login()) {
        if (!mounted) return;
        setState(() {
          if (stage.stage == 'code') _code = stage;
          if (stage.isError) _loginMessage = stage.message ?? 'auth failed';
          if (stage.isSuccess) _loginMessage = 'success';
        });
        if (stage.isSuccess) await WorkerProcessController.instance.restart();
        if (stage.isError || stage.isSuccess) break;
      }
      if (!mounted) return;
      setState(() => _loggingIn = false);
      await _loadStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loggingIn = false;
      });
    }
  }

  Future<void> _logout() async {
    final t = AppStrings.t;
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: Text(t(context, 'auth.logout')),
        description: Text(t(context, 'auth.wouldYouLikeToLogout')),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t(context, 'common.cancel')),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t(context, 'auth.logout')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _error = null);
    try {
      await _service.logout();
      await WorkerProcessController.instance.restart();
      if (!mounted) return;
      setState(() => _loginMessage = AppStrings.t(context, 'auth.loggedOut'));
      await _loadStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// 切换账号：登出后立即重新发起登录（进入扫码页）。
  Future<void> _switchAccount() async {
    setState(() => _error = null);
    try {
      await _service.logout();
      await WorkerProcessController.instance.restart();
      if (!mounted) return;
      setState(() {
        _authenticated = false;
        _user = null;
        _authExpiry = null;
      });
      await _login();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ErrorBanner(message: _error),
          const SizedBox(height: 8),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: SmallSpinner(),
              ),
            )
          else if (_authenticated == true)
            _buildAuthenticated(context)
          else
            _buildLogin(context),
        ],
      ),
    );
  }

  Widget _buildAuthenticated(BuildContext context) {
    final t = AppStrings.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppGroupCard(
          children: [
            AppRow(
              leadingWidget: _statusDot(context, true),
              label: t(context, 'panel.connected'),
              value: _user,
            ),
            const Divider(height: 1),
            AppRow(label: t(context, 'auth.expiry'), value: _authExpiry ?? '—'),
            const Divider(height: 1),
            AppRow(
              icon: LucideIcons.logOut,
              label: t(context, 'auth.logout'),
              destructive: true,
              onTap: _logout,
            ),
            const Divider(height: 1),
            AppRow(
              icon: LucideIcons.userRoundPlus,
              label: t(context, 'auth.switchAccount'),
              onTap: _switchAccount,
            ),
          ],
        ),
      ],
    );
  }

  Widget _statusDot(BuildContext context, bool online) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: online ? scheme.tertiary : scheme.mutedForeground,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildLogin(BuildContext context) {
    final t = AppStrings.t;
    final scheme = ShadTheme.of(context).colorScheme;
    final failed = _loginMessage != null && _loginMessage != 'success';
    // 单一任务页：二维码是唯一主角，整体居中排版，
    // 说明文字降级为辅助色，设备码收敛成 chip。
    return Column(
      children: [
        // 进入页面即自动发起登录显示二维码（见 _loadStatus）；这里只在
        // 出错/过期后给一个重试入口。
        if (failed) ...[
          Center(
            child: SizedBox(
              width: 240,
              child: PrimaryButton(
                label: t(context, 'auth.retryQr'),
                onPressed: _login,
                icon: LucideIcons.refreshCw,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (_code != null) ...[
          const SizedBox(height: 40),
          // verification_uri_complete：App 扫码提取 code 参数直接授权，
          // 系统相机扫则落到网关 /activate?code= 自动确认页。
          if (_code!.verificationUri != null && _code!.userCode != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.border),
              ),
              child: QrImageView(
                data: '${_code!.verificationUri!}?code=${_code!.userCode!}',
                size: 168,
                backgroundColor: Colors.white,
              ),
            ),
          const SizedBox(height: 16),
          Text(
            t(context, 'auth.scan'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.mutedForeground),
          ),
          const SizedBox(height: 20),
          Text(
            t(context, 'auth.enterCode'),
            style: TextStyle(color: scheme.mutedForeground, fontSize: 12),
          ),
          const SizedBox(height: 6),
          // 设备码 chip：给无法扫码的场景手动输入用。
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _code!.userCode ?? '',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!_loggingIn && _loginMessage == null)
            Text(
              t(context, 'auth.waiting'),
              style: TextStyle(color: scheme.mutedForeground, fontSize: 13),
            )
          else if (_loginMessage == 'success')
            Text(
              t(context, 'auth.success'),
              style: TextStyle(
                color: scheme.tertiary,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (_loginMessage != null && _loginMessage != 'success')
            Text(
              '${t(context, 'auth.failed')}: $_loginMessage',
              style: TextStyle(color: scheme.destructive),
              textAlign: TextAlign.center,
            ),
        ],
      ],
    );
  }
}
