import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/corterm_service.dart';
import '../core/models.dart';
import '../l10n/app_strings.dart';
import '../widgets/error_banner.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_header.dart';

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
  LoginStageData? _code;
  String? _loginMessage;
  String? _toast;

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, 'auth.logout')),
        content: Text(t(context, 'auth.wouldYouLikeToLogout')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t(context, 'common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t(context, 'auth.logout'))),
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

  Future<void> _copyUri() async {
    if (_code?.verificationUri == null) return;
    await Clipboard.setData(ClipboardData(text: _code!.verificationUri!));
    if (!mounted) return;
    setState(() => _toast = AppStrings.t(context, 'auth.copied'));
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _toast = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.t;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(title: t(context, 'auth.title')),
          const SizedBox(height: 16),
          ErrorBanner(message: _error),
          if (_toast != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_toast!, style: TextStyle(color: scheme.tertiary)),
            ),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
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
    final scheme = Theme.of(context).colorScheme;
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
              Icon(Icons.check_circle_outline, color: scheme.tertiary),
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
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: t(context, 'auth.logout'),
          onPressed: _logout,
          icon: Icons.logout,
          expanded: true,
        ),
      ],
    );
  }

  Widget _buildLogin(BuildContext context) {
    final t = AppStrings.t;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          label: t(context, 'auth.login'),
          onPressed: _loggingIn ? null : _login,
          icon: Icons.login,
          expanded: true,
        ),
        if (_code != null) ...[
          const SizedBox(height: 24),
          Text(t(context, 'auth.visit'), style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          InkWell(
            onTap: _copyUri,
            child: Text(
              _code!.verificationUri ?? '',
              style: TextStyle(color: scheme.secondary, decoration: TextDecoration.underline, fontSize: 14),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                if (_code!.verificationUri != null)
                  QrImageView(data: _code!.verificationUri!, size: 180),
                const SizedBox(height: 16),
                Text(t(context, 'auth.enterCode'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  _code!.userCode ?? '',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4),
                ),
                const SizedBox(height: 16),
                if (!_loggingIn && _loginMessage == null)
                  Text(t(context, 'auth.waiting'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14))
                else if (_loginMessage == 'success')
                  Text(t(context, 'auth.success'), style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w600))
                else if (_loginMessage != null && _loginMessage != 'success')
                  Text('${t(context, 'auth.failed')}: $_loginMessage', style: TextStyle(color: scheme.error)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
