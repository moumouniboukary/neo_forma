import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/theme/tokens.dart';

class _Designer {
  const _Designer({required this.name, required this.phone});
  final String name;
  final String phone;
}

/// Crédits des concepteurs du projet (Paramètres / À propos).
class NfCreditsSection extends ConsumerWidget {
  const NfCreditsSection({super.key, this.showTitle = true});

  final bool showTitle;

  static const _designers = [
    _Designer(name: 'CONSEIGA Mohamed', phone: '55 30 42 01'),
    _Designer(name: 'LOARI Moumouni Boukary', phone: '79 32 71 85'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(nfStringsProvider);
    final app = NfTokens.appName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text(
            t('settingsCredits'),
            style: TextStyle(
              color: NfTokens.text,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          t.format('creditsIntro', {'app': app}),
          style: TextStyle(color: NfTokens.textMute, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          decoration: BoxDecoration(
            color: NfTokens.elevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NfTokens.line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _designers.length; i++) ...[
                if (i > 0) Divider(color: NfTokens.line, height: 8),
                ListTile(
                  isThreeLine: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: NfTokens.brand.withValues(alpha: 0.15),
                    child: const Icon(
                      Icons.person_outline,
                      color: NfTokens.brand,
                    ),
                  ),
                  title: Text(
                    _designers[i].name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('creditsRole'),
                        style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_outlined,
                            size: 14,
                            color: NfTokens.textMute,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _designers[i].phone,
                            style: TextStyle(
                              color: NfTokens.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
