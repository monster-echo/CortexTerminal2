import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../shared/widgets/app_bar.dart';
import '../../shared/widgets/list_group.dart';

import '../../core/legal/legal_documents.dart';
import '../../core/storage/app_preferences.dart';
import '../../l10n/app_localizations.dart';

/// 当前 locale 对应的法律文档（中文为准，英文为对照译本）。
LegalDocument privacyPolicyOf(String? localeTag) =>
    localeTag == 'zh' ? zhPrivacyPolicy : enPrivacyPolicy;

LegalDocument termsOfServiceOf(String? localeTag) =>
    localeTag == 'zh' ? zhTermsOfService : enTermsOfService;

/// 法律文档页：原生渲染结构化 sections（参考 loficompanion LegalDocumentScreen）。
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;
    final bodyMedium = TextStyle(fontSize: 14, height: 1.55, color: scheme.foreground);

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: CortermAppBar(
        leading: ShadIconButton.ghost(
          foregroundColor: scheme.foreground,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
        title: document.title,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          Text(
            l10n.legalVersionCaption(document.effectiveDate),
            style: TextStyle(fontSize: 11, color: scheme.mutedForeground),
          ),
          const SizedBox(height: 16),
          for (final section in document.sections) ...[
            if (section.title.isNotEmpty) ...[
              Text(
                section.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: scheme.foreground,
                ),
              ),
              const SizedBox(height: 6),
            ],
            for (final p in section.paragraphs) ...[
              Text(p, style: bodyMedium),
              const SizedBox(height: 6),
            ],
            if (section.bullets.isNotEmpty) ...[
              for (final b in section.bullets)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('·  '),
                      Expanded(child: Text(b, style: bodyMedium)),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

/// 「协议与政策」索引页（Settings 入口，参考 loficompanion LegalIndexScreen）。
class LegalIndexScreen extends ConsumerWidget {
  const LegalIndexScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final localeTag = ref.watch(localeProvider);

    return Scaffold(
      backgroundColor: ShadTheme.of(context).colorScheme.background,
      appBar: CortermAppBar(
        leading: ShadIconButton.ghost(
          foregroundColor: ShadTheme.of(context).colorScheme.foreground,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
        title: l10n.legal,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Text(
            l10n.legalIndexIntro,
            style: TextStyle(
              fontSize: 13,
              color: ShadTheme.of(context).colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 12),
          AppGroupCard(children: [
            AppRow(
              icon: LucideIcons.lock,
              label: l10n.privacyPolicy,
              value: l10n.privacyPolicyDesc,
              chevron: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LegalDocumentScreen(document: privacyPolicyOf(localeTag)),
                ),
              ),
            ),
            AppRow(
              icon: LucideIcons.bookOpen,
              label: l10n.termsOfService,
              value: l10n.termsOfServiceDesc,
              chevron: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LegalDocumentScreen(document: termsOfServiceOf(localeTag)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
