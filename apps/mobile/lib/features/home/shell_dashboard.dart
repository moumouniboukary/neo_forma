import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/client.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/theme/tokens.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/nf_speak_button.dart';
import '../../core/widgets/nf_widgets.dart';
import '../auth/auth_provider.dart';
import '../ledger/ledger_data.dart';
import '../sync/sync_service.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncServiceProvider).flush();
      final lang = ref.read(authProvider).user?.language;
      if (lang != null && lang.isNotEmpty) {
        ref.read(uxPrefsProvider.notifier).setLanguageLocal(lang);
      }
    });
  }

  int _indexForLocation(String loc) {
    if (loc.startsWith('/app/ventes')) return 1;
    if (loc.startsWith('/app/dettes')) return 2;
    if (loc.startsWith('/app/profil')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    final index = _indexForLocation(loc);
    final t = ref.watch(nfStringsProvider);

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && index != 0) context.go('/app');
      },
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          backgroundColor: NfTokens.surface,
          indicatorColor: NfTokens.brand.withValues(alpha: 0.25),
          onDestinationSelected: (i) {
            switch (i) {
              case 0:
                context.go('/app');
              case 1:
                context.go('/app/ventes');
              case 2:
                context.go('/app/dettes');
              case 3:
                context.go('/app/profil');
            }
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: t('home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.menu_book_outlined),
              label: t('ledger'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.payments_outlined),
              label: t('debts'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              label: t('profile'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page d'accueil connectée — onglet Accueil.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Map<String, dynamic>? data;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ref.read(syncServiceProvider).flush();
    try {
      final d = await ref
          .read(apiClientProvider)
          .get<Map<String, dynamic>>(
            '/dashboard',
            parse: (x) => Map<String, dynamic>.from(x as Map),
          );
      if (!mounted) return;
      setState(() {
        data = d;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  bool _isOutflow(String type) =>
      type == 'creance' || type == 'dette' || type == 'depense';

  @override
  Widget build(BuildContext context) {
    // Recharge l'accueil dès qu'une opération change (création, règlement, sync).
    ref.listen<int>(ledgerRevisionProvider, (_, _) => _load());
    final user = ref.watch(authProvider).user;
    final pending = ref.watch(syncPendingProvider);
    final syncErr = ref.watch(syncErrorProvider);
    final t = ref.watch(nfStringsProvider);
    final iconMode = ref.watch(uxPrefsProvider).iconMode;
    final fmt = NumberFormat.decimalPattern('fr');
    final rawName = user?.displayName.trim() ?? '';
    final needsOnboarding = !(user?.onboardingCompleted ?? false);
    final displayName =
        rawName.isEmpty || rawName == user?.phone || rawName.startsWith('+')
        ? t('entrepreneur')
        : rawName;
    final sales = data?['monthSalesFcfa'] as int? ?? 0;
    final debts = data?['openDebtsFcfa'] as int? ?? 0;
    final overdue = data?['overdueDebtsCount'] as int? ?? 0;
    final recent = (data?['recentOperations'] as List?) ?? [];
    final last7 = (data?['last7DaysSales'] as List?) ?? [];
    final maxBar = last7.fold<int>(1, (m, e) {
      final v = (e as Map)['totalFcfa'] as int? ?? 0;
      return v > m ? v : m;
    });

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: NfTokens.brand,
        foregroundColor: NfTokens.bg,
        onPressed: () => context.push('/app/enregistrer'),
        child: const Icon(Icons.add, size: 28),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: NfTokens.brand,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
          children: [
            SafeArea(
              bottom: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'NeoForma',
                            maxLines: 1,
                            softWrap: false,
                            style: GoogleFonts.syne(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: NfTokens.brand,
                              height: 1.05,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.format('helloName', {'name': displayName}),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.syne(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: NfTokens.text,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            NfSpeakButton(
                              labelKey: 'helloName',
                              vars: {'name': displayName},
                              alwaysShow: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: NfTokens.elevated,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => context.push('/app/score'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Text(
                          t('neoscore'),
                          style: const TextStyle(
                            color: NfTokens.brandSoft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (pending > 0) ...[
              const SizedBox(height: 12),
              _Toast(
                text: '$pending opération(s) en attente de synchronisation',
              ),
            ],
            if (syncErr != null) ...[
              const SizedBox(height: 8),
              _Toast(text: 'Synchronisation · $syncErr', danger: true),
            ],
            if (needsOnboarding) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: NfTokens.elevated,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: NfTokens.brand),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.insights_outlined,
                      color: NfTokens.brandSoft,
                      size: 30,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Calcule ta solvabilité quand tu es prêt',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Complète les informations sur ton activité pour activer ton NeoScore.',
                      style: TextStyle(color: NfTokens.textMute),
                    ),
                    const SizedBox(height: 14),
                    NfPrimaryButton(
                      label: t('activateScore'),
                      onPressed: () => context.push('/onboarding'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [NfTokens.elevated, NfTokens.surface, NfTokens.bgMid],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: NfTokens.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('salesMonth'),
                          style: const TextStyle(
                            color: NfTokens.textMute,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      NfSpeakButton(
                        labelKey: 'salesMonth',
                        compact: true,
                        alwaysShow: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: fmt.format(sales),
                          style: GoogleFonts.syne(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: NfTokens.brandSoft,
                          ),
                        ),
                        const TextSpan(
                          text: '  FCFA',
                          style: TextStyle(
                            color: NfTokens.textMute,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: t('toCollect'),
                    labelKey: 'toCollect',
                    value: fmt.format(debts),
                    valueColor: NfTokens.warn,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    label: t('overdue'),
                    labelKey: 'overdue',
                    value: '$overdue',
                    valueColor: NfTokens.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t('quickActions'),
                    style: GoogleFonts.figtree(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                NfSpeakButton(
                  labelKey: 'quickActions',
                  compact: true,
                  alwaysShow: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: Icons.add_circle_outline,
                    label: t('record'),
                    labelKey: 'record',
                    iconMode: iconMode,
                    onTap: () => context.push('/app/enregistrer'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.account_balance_wallet_outlined,
                    label: t('credit'),
                    labelKey: 'credit',
                    iconMode: iconMode,
                    onTap: () => context.push('/app/credit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.insights_outlined,
                    label: t('neoscore'),
                    labelKey: 'neoscore',
                    iconMode: iconMode,
                    onTap: () => context.push('/app/score'),
                  ),
                ),
              ],
            ),
            if (last7.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text(
                '7 derniers jours',
                style: TextStyle(color: NfTokens.textMute, fontSize: 13),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 100,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: last7.map((raw) {
                    final d = Map<String, dynamic>.from(raw as Map);
                    final total = d['totalFcfa'] as int? ?? 0;
                    final day = d['day']?.toString() ?? '';
                    final h = total == 0
                        ? 6.0
                        : (6 + (total / maxBar) * 72).clamp(6.0, 78.0);
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: h,
                              decoration: BoxDecoration(
                                color: NfTokens.brand.withValues(
                                  alpha: total == 0 ? 0.28 : 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              day.length > 3 ? day.substring(0, 3) : day,
                              style: const TextStyle(
                                fontSize: 10,
                                color: NfTokens.textMute,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 22),
            const Text(
              'Dernières opérations',
              style: TextStyle(color: NfTokens.textMute, fontSize: 13),
            ),
            const SizedBox(height: 8),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Aucune opération pour l’instant.\nEnregistrez votre première vente.',
                  style: TextStyle(color: NfTokens.textMute, height: 1.4),
                ),
              )
            else
              ...recent.take(6).map((raw) {
                final op = Map<String, dynamic>.from(raw as Map);
                final type = op['type']?.toString() ?? '';
                final amount = op['amountFcfa'] as int? ?? 0;
                final out = _isOutflow(type);
                final when = op['dateOperation'] ?? op['createdAt'];
                String whenLabel = '';
                if (when != null) {
                  try {
                    whenLabel = DateFormat(
                      'dd MMM · HH:mm',
                      'fr_FR',
                    ).format(DateTime.parse(when.toString()).toLocal());
                  } catch (_) {
                    whenLabel = when.toString();
                  }
                }
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: NfTokens.elevated.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: NfTokens.line),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              op['label']?.toString() ??
                                  op['clientName']?.toString() ??
                                  type,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (whenLabel.isNotEmpty)
                              Text(
                                whenLabel,
                                style: const TextStyle(
                                  color: NfTokens.textMute,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${out ? '−' : '+'}${fmt.format(amount)}',
                        style: TextStyle(
                          color: out ? NfTokens.warn : NfTokens.ok,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// Alias pour compatibilité router existant.
typedef DashboardPage = HomePage;

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.valueColor,
    this.labelKey,
  });

  final String label;
  final String value;
  final Color valueColor;
  final String? labelKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
      decoration: BoxDecoration(
        color: NfTokens.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NfTokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: NfTokens.textMute,
                    fontSize: 12,
                  ),
                ),
              ),
              if (labelKey != null)
                NfSpeakButton(
                  labelKey: labelKey,
                  compact: true,
                  alwaysShow: true,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends ConsumerWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelKey,
    this.iconMode = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? labelKey;
  final bool iconMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceOn = ref.watch(uxPrefsProvider).voiceAssist;
    void speak() {
      if (labelKey != null) {
        ref.read(voiceServiceProvider).speakKey(labelKey!);
      }
    }

    return Material(
      color: NfTokens.elevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: labelKey != null ? speak : null,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: iconMode ? 20 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NfTokens.line),
          ),
          child: Column(
            children: [
              Icon(icon, color: NfTokens.brandSoft, size: iconMode ? 36 : 22),
              if (!iconMode) ...[
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (voiceOn && labelKey != null) ...[
                const SizedBox(height: 2),
                InkWell(
                  onTap: speak,
                  borderRadius: BorderRadius.circular(999),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.volume_up_rounded,
                      color: NfTokens.brandSoft,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger
            ? NfTokens.danger.withValues(alpha: 0.12)
            : NfTokens.elevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: danger
              ? NfTokens.danger.withValues(alpha: 0.45)
              : NfTokens.line,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: danger ? NfTokens.danger : NfTokens.text,
          fontSize: 13,
        ),
      ),
    );
  }
}
