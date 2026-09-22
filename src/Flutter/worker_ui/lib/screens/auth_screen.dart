import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/corterm_service.dart';
import '../core/models.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/error_banner.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_header.dart';
import '../widgets/states.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.service});

  final CortermService service;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
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
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.service.status();
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
      await for (final stage in widget.service.login()) {
        if (!mounted) return;
        setState(() {
          if (stage.stage == 'code') _code = stage;
          if (stage.isError) _loginMessage = stage.message ?? 'auth failed';
          if (stage.isSuccess) _loginMessage = 'success';
        });
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
      await widget.service.logout();
      if (!mounted) return;
      setState(() => _loginMessage = AppStrings.t(context, 'auth.loggedOut'));
      await _loadStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.t;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(title: t(context, 'auth.title')),
          const SizedBox(height: 16),
          ErrorBanner(message: _error),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: SmallSpinner()))
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
    final scheme = ShadTheme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.tertiary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.circleCheck, color: scheme.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${t(context, 'dashboard.authenticated')}  ·  ${_user ?? 'unknown'}',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${t(context, 'dashboard.authExpiry')}: ${_authExpiry ?? '—'}',
          style: TextStyle(color: scheme.mutedForeground, fontSize: 14),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: t(context, 'auth.logout'),
          onPressed: _logout,
          icon: LucideIcons.logOut,
          expanded: true,
        ),
      ],
    );
  }

  Widget _buildLogin(BuildContext context) {
    final t = AppStrings.t;
    final scheme = ShadTheme.of(context).colorScheme;
    final failed = _loginMessage != null && _loginMessage != 'success';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 进入页面即自动发起登录显示二维码（见 _loadStatus）；这里只在
        // 出错/过期后给一个重试入口。
        if (failed)
          PrimaryButton(
            label: t(context, 'auth.retryQr'),
            onPressed: _login,
            icon: LucideIcons.refreshCw,
            expanded: true,
          ),
        if (_code != null) ...[
          const SizedBox(height: 24),
          Text(t(context, 'auth.scan'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                // verification_uri_complete：App 扫码提取 code 参数直接授权，
                // 系统相机扫则落到网关 /activate?code= 自动确认页。
                if (_code!.verificationUri != null && _code!.userCode != null)
                  QrImageView(
                    data:
                        '${_code!.verificationUri!}?code=${_code!.userCode!}',
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                const SizedBox(height: 16),
                Text(t(context, 'auth.enterCode'), style: TextStyle(color: scheme.mutedForeground, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  _code!.userCode ?? '',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3),
                ),
                const SizedBox(height: 16),
                if (!_loggingIn && _loginMessage == null)
                  Text(t(context, 'auth.waiting'), style: TextStyle(color: scheme.mutedForeground, fontSize: 14))
                else if (_loginMessage == 'success')
                  Text(t(context, 'auth.success'), style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w600))
                else if (_loginMessage != null && _loginMessage != 'success')
                  Text('${t(context, 'auth.failed')}: $_loginMessage', style: TextStyle(color: scheme.destructive)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
