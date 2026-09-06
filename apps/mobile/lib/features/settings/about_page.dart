import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/nf_widgets.dart';
import 'credits_section.dart';

/// À propos / Aide : explique le fonctionnement de NeoForma.
class AboutHelpPage extends ConsumerWidget {
  const AboutHelpPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(nfStringsProvider);
    final support = NfTokens.supportPhone;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('aboutHelp')),
        leading: nfBackButton(context, fallbackLocation: '/app/parametres'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/branding/logo-icon.png',
                  width: 52,
                  height: 52,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.storefront,
                    size: 48,
                    color: NfTokens.brand,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      NfTokens.appName.isNotEmpty ? NfTokens.appName : kAppName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: NfTokens.brand,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t('aboutVersion'),
                      style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            t('aboutIntro'),
            style: TextStyle(color: NfTokens.textMute, height: 1.45),
          ),
          const SizedBox(height: 20),
          _HelpSection(
            icon: Icons.menu_book_outlined,
            title: t('helpWhatTitle'),
            body: t('helpWhatBody'),
          ),
          _HelpSection(
            icon: Icons.point_of_sale_outlined,
            title: t('helpLedgerTitle'),
            body: t('helpLedgerBody'),
          ),
          _HelpSection(
            icon: Icons.handshake_outlined,
            title: t('helpDebtsTitle'),
            body: t('helpDebtsBody'),
          ),
          _HelpSection(
            icon: Icons.inventory_2_outlined,
            title: t('helpStockTitle'),
            body: t('helpStockBody'),
          ),
          _HelpSection(
            icon: Icons.insights_outlined,
            title: t('helpScoreTitle'),
            body: t('helpScoreBody'),
          ),
          _HelpSection(
            icon: Icons.account_balance_outlined,
            title: t('helpCreditTitle'),
            body: t('helpCreditBody'),
          ),
          _HelpSection(
            icon: Icons.groups_outlined,
            title: t('helpTontineTitle'),
            body: t('helpTontineBody'),
          ),
          _HelpSection(
            icon: Icons.cloud_off_outlined,
            title: t('helpOfflineTitle'),
            body: t('helpOfflineBody'),
          ),
          _HelpSection(
            icon: Icons.accessibility_new_outlined,
            title: t('helpAccessTitle'),
            body: t('helpAccessBody'),
          ),
          _HelpSection(
            icon: Icons.lock_outline,
            title: t('helpSecurityTitle'),
            body: t('helpSecurityBody'),
          ),
          _HelpSection(
            icon: Icons.badge_outlined,
            title: t('helpProfileTitle'),
            body: t('helpProfileBody'),
          ),
          if (support != null && support.isNotEmpty) ...[
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.support_agent, color: NfTokens.brand),
              title: Text(t('helpSupport')),
              subtitle: Text(support),
            ),
          ],
          const SizedBox(height: 16),
          const NfCreditsSection(),
          const SizedBox(height: 16),
          Text(
            t('aboutFooter'),
            style: TextStyle(
              color: NfTokens.textMute,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: NfTokens.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: NfTokens.line),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Icon(icon, color: NfTokens.brand),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  body,
                  style: TextStyle(
                    color: NfTokens.textMute,
                    height: 1.45,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
