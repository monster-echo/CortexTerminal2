import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/states.dart';
import '../data/membership_repository.dart';

/// 兑换会员码（对齐 HarmonyOS RedeemPage / Gateway POST /api/billing/redeem）。
/// 成功后提示并返回上一页。
class RedeemScreen extends ConsumerStatefulWidget {
  const RedeemScreen({super.key});

  @override
  ConsumerState<RedeemScreen> createState() => _RedeemScreenState();
}

class _RedeemScreenState extends ConsumerState<RedeemScreen> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final l10n = AppLocalizations.of(context)!;
    final code = _controller.text.trim();
    if (code.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ref.read(membershipRepositoryProvider).redeemCode(code);
      if (mounted) {
        showAppToast(context, l10n.redeemSuccess);
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, '${l10n.redeemFailed}: ${e.serverMessage ?? e.statusCode}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: CortermAppBar(
        title: l10n.redeemCode,
        leading: ShadIconButton.ghost(
          foregroundColor: scheme.foreground,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          ShadInput(
            controller: _controller,
            placeholder: Text(l10n.redeemPlaceholder),
          ),
          const SizedBox(height: 16),
          ShadButton(
            onPressed: _submitting ? null : _redeem,
            child: _submitting
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.redeemButton),
          ),
        ],
      ),
    );
  }
}
