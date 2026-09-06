import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/client.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/l10n/strings.dart';
import '../../core/offline/local_cache.dart';
import '../../core/theme/tokens.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/nf_speak_button.dart';
import '../../core/widgets/nf_widgets.dart';
import '../auth/auth_provider.dart';
import '../ledger/ledger_data.dart';
import '../notifications/notifications_data.dart';
import '../sync/sync_service.dart';
import '../../core/utils/parse.dart';

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
      final sync = ref.read(syncServiceProvider);
      sync.startAutoSync();
      sync.flush();
      final lang = ref.read(authProvider).user?.language;
      if (lang != null && lang.isNotEmpty) {
        ref.read(uxPrefsProvider.notifier).setLanguageLocal(lang);
      }
    });
  }

  int _indexForLocation(String loc) {
    if (loc.startsWith('/app/ventes') || loc.startsWith('/app/depenses')) {
      return 1;
    }
    if (loc.startsWith('/app/dettes')) return 2;
    if (loc.startsWith('/app/profil')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    final index = _indexForLocation(loc);
    final t = ref.watch(nfStringsProvider);
    final ux = ref.watch(uxPrefsProvider);
    final iconMode = ux.iconMode;
    // Force rebuild nav/shell quand le thème change (couleurs NfTokens).
    final _ = ux.theme;

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && index != 0) context.go('/app');
      },
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: NavigationBar(
          height: iconMode ? 78 : 64,
          labelBehavior: iconMode
              ? NavigationDestinationLabelBehavior.alwaysShow
              : NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: index,
          backgroundColor: NfTokens.surface,
          indicatorColor: NfTokens.brand.withValues(alpha: 0.25),
          onDestinationSelected: (i) {
            final keys = ['home', 'ledger', 'debts', 'profile'];
            if (ref.read(uxPrefsProvider).voiceAssist && i < keys.length) {
              ref.read(voiceServiceProvider).speakKey(keys[i]);
            }
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
              icon: Icon(Icons.home_outlined, size: iconMode ? 30 : 24),
              selectedIcon: Icon(Icons.home, size: iconMode ? 30 : 24),
              label: t('home'),
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined, size: iconMode ? 30 : 24),
              label: t('ledger'),
            ),
            NavigationDestination(
              icon: Icon(Icons.payments_outlined, size: iconMode ? 30 : 24),
              label: t('debts'),
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline, size: iconMode ? 30 : 24),
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
  bool _welcomed = false;
  bool tipVisible = false;
  ProviderSubscription<int>? _revisionSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
      _welcomeSpeak();
      final dismissed = ref
          .read(localCacheProvider)
          .getMap(LocalCacheKeys.homeTipDismissed);
      if (dismissed == null && mounted) {
        setState(() => tipVisible = true);
      }
    });
    _revisionSub = ref.listenManual<int>(ledgerRevisionProvider, (_, _) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _revisionSub?.close();
    super.dispose();
  }

  Future<void> _dismissTip() async {
    await ref.read(localCacheProvider).putMap(
          LocalCacheKeys.homeTipDismissed,
          {'done': true},
        );
    if (mounted) setState(() => tipVisible = false);
  }

  Future<void> _welcomeSpeak() async {
    if (_welcomed || !mounted) return;
    _welcomed = true;
    final prefs = ref.read(uxPrefsProvider);
    if (!prefs.voiceAssist) return;
    final voice = ref.read(voiceServiceProvider);
    final user = ref.read(authProvider).user;
    final name = user?.displayName.trim() ?? '';
    if (name.isNotEmpty && !name.startsWith('+')) {
      await voice.speakKey('helloName', vars: {'name': name});
    } else {
      await voice.speakKey('hello');
    }
    if (prefs.iconMode) {
      await voice.speakKey('tapToRecord');
    }
  }

  Future<void> _load() async {
    // Pas de flush ici : AppShell le lance déjà. Relancer flush à chaque
    // révision mute syncPending/ledgerRevision pendant les rebuilds (écran rouge).
    try {
      final d = await ref
          .read(apiClientProvider)
          .get<Map<String, dynamic>>(
            '/dashboard',
            parse: (x) => Map<String, dynamic>.from(x as Map),
          );
      if (!mounted) return;
      await ref.read(localCacheProvider).putMap(LocalCacheKeys.dashboard, d);
      if (!mounted) return;
      setState(() {
        data = d;
        loading = false;
      });
      try {
        await ref.read(notificationsPollerProvider).pollAndNotify();
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      final cached =
          ref.read(localCacheProvider).getMap(LocalCacheKeys.dashboard);
      if (!mounted) return;
      setState(() {
        data = cached;
        loading = false;
      });
    }
  }

  bool _isOutflow(String type) =>
      type == 'creance' || type == 'dette' || type == 'depense';

  List<Widget> _iconModeBody({
    required NfStrings t,
    required NumberFormat fmt,
    required int sales,
    required int debts,
  }) {
    return [
      const SizedBox(height: 20),
      Material(
        color: NfTokens.brand,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => context.push('/app/enregistrer'),
          onLongPress: () =>
              ref.read(voiceServiceProvider).speakKey('tapToRecord'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: Column(
              children: [
                const Icon(
                  Icons.add_circle_outline,
                  size: 56,
                  color: NfTokens.onBrand,
                ),
                const SizedBox(height: 12),
                Text(
                  t('record'),
                  style: GoogleFonts.syne(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: NfTokens.onBrand,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t('tapToRecord'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: NfTokens.onBrand.withValues(alpha: 0.9),
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: _StatCard(
              label: t('salesMonth'),
              labelKey: 'salesMonth',
              value: fmt.format(sales),
              valueColor: NfTokens.brandSoft,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              label: t('toCollect'),
              labelKey: 'toCollect',
              value: fmt.format(debts),
              valueColor: NfTokens.warn,
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Text(
        t('moreActions'),
        style: GoogleFonts.figtree(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.payments_outlined,
              label: t('debts'),
              labelKey: 'debts',
              iconMode: true,
              onTap: () => context.push('/app/dettes'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              icon: Icons.insights_outlined,
              label: t('neoscore'),
              labelKey: 'neoscore',
              iconMode: true,
              onTap: () => context.push('/app/score'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              icon: Icons.account_balance_wallet_outlined,
              label: t('credit'),
              labelKey: 'credit',
              iconMode: true,
              onTap: () => context.push('/app/credit'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.inventory_2_outlined,
              label: t('stock'),
              labelKey: 'stock',
              iconMode: true,
              onTap: () => context.push('/app/stock'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              icon: Icons.groups_outlined,
              label: t('tontine'),
              labelKey: 'tontine',
              iconMode: true,
              onTap: () => context.push('/app/tontine'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              icon: Icons.notifications_outlined,
              label: t('notifications'),
              labelKey: 'notifications',
              iconMode: true,
              onTap: () => context.push('/app/notifications'),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final pending = ref.watch(syncPendingProvider);
    final syncErr = ref.watch(syncErrorProvider);
    final t = ref.watch(nfStringsProvider);
    final ux = ref.watch(uxPrefsProvider);
    final iconMode = ux.iconMode;
    final _ = ux.theme;
    final fmt = NumberFormat.decimalPattern('fr');
    final needsOnboarding = !(user?.onboardingCompleted ?? false);
    final sales = asFcfaInt(data?['monthSalesFcfa']);
    final debts = asFcfaInt(data?['openDebtsFcfa']);
    final overdue = asFcfaInt(data?['overdueDebtsCount']);
    final recent = (data?['recentOperations'] as List?) ?? [];
    final last7 = (data?['last7DaysSales'] as List?) ?? [];
    final topClients = (data?['topClients'] as List?) ?? [];
    final criticalDebts = (data?['criticalDebts'] as List?) ?? [];
    final maxBar = last7.fold<int>(1, (m, e) {
      final v = asFcfaInt((e as Map)['totalFcfa']);
      return v > m ? v : m;
    });

    return Scaffold(
      floatingActionButton: iconMode
          ? null
          : FloatingActionButton(
              backgroundColor: NfTokens.brand,
              foregroundColor: NfTokens.onBrand,
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
                children: [
                  Expanded(
                    child: Text(
                      t('home'),
                      style: GoogleFonts.syne(
                        fontSize: iconMode ? 32 : 28,
                        fontWeight: FontWeight.w800,
                        color: NfTokens.text,
                        height: 1.15,
                      ),
                    ),
                  ),
                  const NfSpeakButton(labelKey: 'home', alwaysShow: true),
                ],
              ),
            ),
            if (pending > 0) ...[
              const SizedBox(height: 12),
              _Toast(text: t.format('offlinePending', {'n': '$pending'})),
            ],
            if (syncErr != null) ...[
              const SizedBox(height: 8),
              _Toast(text: 'Synchronisation · $syncErr', danger: true),
            ],
            if (tipVisible && iconMode) ...[
              const SizedBox(height: 12),
              Material(
                color: NfTokens.elevated,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app, color: NfTokens.brandSoft),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t('homeTip'),
                          style: const TextStyle(height: 1.3),
                        ),
                      ),
                      TextButton(
                        onPressed: _dismissTip,
                        child: Text(t('gotIt')),
                      ),
                    ],
                  ),
                ),
              ),
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
                      t('yourActivity'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t('onboardingHint'),
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
            if (iconMode)
              ..._iconModeBody(t: t, fmt: fmt, sales: sales, debts: debts)
            else ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      NfTokens.elevated,
                      NfTokens.surface,
                      NfTokens.bgMid,
                    ],
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
                            style: TextStyle(
                              color: NfTokens.textMute,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const NfSpeakButton(
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
                          TextSpan(
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
                  const NfSpeakButton(
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
                      onTap: () => context.push('/app/enregistrer'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.account_balance_wallet_outlined,
                      label: t('credit'),
                      labelKey: 'credit',
                      onTap: () => context.push('/app/credit'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.insights_outlined,
                      label: t('neoscore'),
                      labelKey: 'neoscore',
                      onTap: () => context.push('/app/score'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.inventory_2_outlined,
                      label: t('stock'),
                      labelKey: 'stock',
                      onTap: () => context.push('/app/stock'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.groups_outlined,
                      label: t('tontine'),
                      labelKey: 'tontine',
                      onTap: () => context.push('/app/tontine'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.notifications_outlined,
                      label: t('notifications'),
                      labelKey: 'notifications',
                      onTap: () => context.push('/app/notifications'),
                    ),
                  ),
                ],
              ),
              if (last7.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(
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
                      final total = asFcfaInt(d['totalFcfa']);
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
                                style: TextStyle(
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
              if (topClients.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(
                  'Meilleurs clients',
                  style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ...topClients.take(5).map((raw) {
                  final c = Map<String, dynamic>.from(raw as Map);
                  final name = c['clientName']?.toString() ?? 'Client';
                  final clientSales = asFcfaInt(c['monthSalesFcfa']);
                  final debt = asFcfaInt(c['openDebtFcfa']);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(name),
                    subtitle: Text(
                      debt > 0
                          ? 'Ventes ${fmt.format(clientSales)} · créances ${fmt.format(debt)}'
                          : 'Ventes ${fmt.format(clientSales)} FCFA',
                      style:
                          TextStyle(color: NfTokens.textMute, fontSize: 12),
                    ),
                    trailing: debt > 0
                        ? Text(
                            fmt.format(debt),
                            style: TextStyle(
                              color: NfTokens.warn,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  );
                }),
              ],
              if (criticalDebts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Créances critiques',
                  style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ...criticalDebts.take(5).map((raw) {
                  final d = Map<String, dynamic>.from(raw as Map);
                  final isOverdue = d['overdue'] == true;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isOverdue
                          ? Icons.warning_amber_rounded
                          : Icons.person_outline,
                      color: isOverdue ? NfTokens.danger : NfTokens.textMute,
                    ),
                    title: Text(d['clientName']?.toString() ?? 'Client'),
                    subtitle: Text(
                      isOverdue ? t('overdue') : t('toCollect'),
                      style: TextStyle(
                        color:
                            isOverdue ? NfTokens.danger : NfTokens.textMute,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Text(
                      fmt.format(asFcfaInt(d['remainingFcfa'])),
                      style: TextStyle(
                        color: isOverdue ? NfTokens.danger : NfTokens.warn,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => context.push('/app/dettes'),
                  );
                }),
              ],
              const SizedBox(height: 22),
              Text(
                t('lastOps'),
                style: TextStyle(color: NfTokens.textMute, fontSize: 13),
              ),
              const SizedBox(height: 8),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    t('noOpsYet'),
                    style: TextStyle(color: NfTokens.textMute, height: 1.4),
                  ),
                )
              else
                ...recent.take(6).map((raw) {
                  final op = Map<String, dynamic>.from(raw as Map);
                  final type = op['type']?.toString() ?? '';
                  final amount = asFcfaInt(op['amountFcfa']);
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
                                  style: TextStyle(
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
                  style: TextStyle(
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
