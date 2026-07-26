import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/client.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/l10n/strings.dart';
import '../../core/offline/queue.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/nf_speak_button.dart';
import '../../core/widgets/nf_widgets.dart';
import 'auth/auth_provider.dart';
import 'sync/sync_service.dart';

class ScorePage extends ConsumerStatefulWidget {
  const ScorePage({super.key});

  @override
  ConsumerState<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends ConsumerState<ScorePage> {
  Map<String, dynamic>? score;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref
          .read(apiClientProvider)
          .get<Map<String, dynamic>>(
            '/score',
            parse: (d) => Map<String, dynamic>.from(d as Map),
          );
      setState(() {
        score = s;
        loading = false;
      });
    } catch (_) {
      setState(() {
        score = null;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final t = ref.watch(nfStringsProvider);
    if (score == null) {
      return Scaffold(
        appBar: AppBar(
          leading: nfBackButton(context, fallbackLocation: '/app'),
          title: Text(t('neoscore')),
          actions: const [NfSpeakButton(labelKey: 'neoscore')],
        ),
        body: const Center(child: Text('Score indisponible pour le moment')),
      );
    }
    final criteria = Map<String, dynamic>.from(
      score!['criteria'] as Map? ?? {},
    );
    final history = (score!['history'] as List?) ?? [];
    final eligible = score!['eligible'] == true;
    final statusKey = eligible ? 'eligible' : 'notEligible';

    return Scaffold(
      appBar: AppBar(
        leading: nfBackButton(context, fallbackLocation: '/app'),
        title: Text(t('neoscore')),
        actions: [
          NfSpeakButton(
            text: '${t('neoscore')}. ${score!['score']}. ${t(statusKey)}.',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Text(
              '${score!['score']}',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: NfTokens.brand,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Center(
            child: Text(
              '${t(statusKey)} · segment ${score!['segment']}',
              style: const TextStyle(color: NfTokens.textMute),
            ),
          ),
          const SizedBox(height: 20),
          ...[
            ('Régularité', criteria['regularite']),
            ('Volume d’activité', criteria['volume']),
            ('Gestion des créances', criteria['dettes']),
            ('Croissance', criteria['croissance']),
          ].map((e) {
            final pct = (e.$2 as num?)?.toDouble() ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(e.$1)),
                      Text(
                        '${pct.round()}%',
                        style: const TextStyle(color: NfTokens.textMute),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: (pct / 100).clamp(0, 1),
                    color: NfTokens.brand,
                    backgroundColor: NfTokens.card2,
                  ),
                ],
              ),
            );
          }),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Historique', style: Theme.of(context).textTheme.titleMedium),
            ...history.map((h) {
              final m = Map<String, dynamic>.from(h as Map);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(m['month']?.toString() ?? ''),
                trailing: Text(
                  '${m['score']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              );
            }),
          ],
          const SizedBox(height: 16),
          if (eligible)
            NfPrimaryButton(
              label: 'Demander un crédit',
              onPressed: () => context.push('/app/credit'),
            )
          else
            const Text(
              'Continuez d’enregistrer des ventes pour dépasser 50.',
              style: TextStyle(color: NfTokens.textMute),
            ),
        ],
      ),
    );
  }
}

class CreditPage extends ConsumerStatefulWidget {
  const CreditPage({super.key});

  @override
  ConsumerState<CreditPage> createState() => _CreditPageState();
}

class _CreditPageState extends ConsumerState<CreditPage> {
  Map<String, dynamic>? offer;
  int amount = 150000;
  String purpose = 'stock';
  String? reference;
  String? error;
  bool needConsent = false;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await ref
          .read(apiClientProvider)
          .get<Map<String, dynamic>>(
            '/credit/offer',
            parse: (d) => Map<String, dynamic>.from(d as Map),
          );
      setState(() {
        offer = o;
        amount = o['suggestedFcfa'] as int? ?? amount;
      });
    } catch (_) {
      setState(() => offer = null);
    }
  }

  Future<void> _grantConsent() async {
    try {
      await ref
          .read(apiClientProvider)
          .put('/me/consents', data: {'consentCreditPartners': true});
      setState(() => needConsent = false);
    } on ApiException catch (e) {
      setState(() => error = e.message);
    }
  }

  Future<void> _submit() async {
    setState(() {
      loading = true;
      error = null;
      needConsent = false;
    });
    final payload = {
      'amountFcfa': amount,
      'purpose': purpose,
      'repayment': 'mensuel',
    };
    try {
      final app = await ref
          .read(apiClientProvider)
          .post<Map<String, dynamic>>(
            '/credit/applications',
            data: payload,
            parse: (d) => Map<String, dynamic>.from(d as Map),
          );
      setState(() => reference = app['reference'] as String?);
    } on ApiException catch (e) {
      if (e.isOffline || e.isServerError) {
        final mutationId = OfflineQueue.newId();
        final createdAt = DateTime.now().toUtc().toIso8601String();
        await ref.read(offlineQueueProvider).enqueue(
              QueuedMutation(
                clientMutationId: mutationId,
                kind: 'submit_credit',
                payload: payload,
                createdAt: createdAt,
              ),
            );
        await ref.read(syncServiceProvider).refreshCount();
        setState(() => reference = 'HORS-LIGNE');
      } else {
        final code = (e.body is Map) ? (e.body as Map)['error'] : null;
        setState(() {
          error = e.message;
          needConsent = code == 'consent_required';
        });
      }
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.decimalPattern('fr');
    if (reference != null) {
      return Scaffold(
        appBar: AppBar(
          leading: nfBackButton(context, fallbackLocation: '/app'),
          title: const Text('Demande envoyée'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                reference == 'HORS-LIGNE'
                    ? 'Demande enregistrée hors ligne — envoi au retour du réseau'
                    : 'Réf. $reference',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              Text(
                reference == 'HORS-LIGNE'
                    ? 'Synchronisation automatique'
                    : 'Statut · En cours · 24–48 h',
                style: const TextStyle(color: NfTokens.textMute),
              ),
              const Spacer(),
              NfPrimaryButton(
                label: 'Accueil',
                onPressed: () => context.go('/app'),
              ),
            ],
          ),
        ),
      );
    }

    final eligible = offer?['eligible'] == true;

    final t = ref.watch(nfStringsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: nfBackButton(context, fallbackLocation: '/app'),
        title: Text(t('credit')),
        actions: [
          NfSpeakButton(
            text: eligible
                ? '${t('credit')}. ${fmt.format(offer?['suggestedFcfa'] ?? 0)} FCFA. ${t('submitCredit')}.'
                : '${t('credit')}. ${t('notEligible')}.',
            alwaysShow: true,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (offer != null && !eligible)
            Text(
              'Non éligible (score ${offer?['score'] ?? '—'})',
              style: const TextStyle(color: NfTokens.danger),
            ),
          if (eligible)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Montant estimé',
                      style: TextStyle(color: NfTokens.textMute),
                    ),
                    Text(
                      '${fmt.format(offer!['suggestedFcfa'])} FCFA',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      '${fmt.format(offer!['minFcfa'])} – ${fmt.format(offer!['maxFcfa'])} · ${offer!['durationMonths']} mois',
                      style: const TextStyle(color: NfTokens.textMute),
                    ),
                  ],
                ),
              ),
            ),
          if (needConsent) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: const Text(
                  'Consentement institutions de microfinance requis',
                ),
                trailing: TextButton(
                  onPressed: _grantConsent,
                  child: const Text('Autoriser'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            initialValue: '$amount',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Montant demandé (FCFA)',
            ),
            enabled: eligible,
            onChanged: (v) => amount = int.tryParse(v) ?? amount,
          ),
          const SizedBox(height: 12),
          const Text(
            'Objet du crédit',
            style: TextStyle(color: NfTokens.textMute),
          ),
          const SizedBox(height: 8),
          NfSegmented(
            value: purpose,
            onChanged: (v) => setState(() => purpose = v),
            options: const [
              ('stock', 'Stock'),
              ('equipement', 'Équipement'),
              ('fonds_roulement', 'Fonds de roulement'),
              ('autre', 'Autre'),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: NfTokens.danger)),
          ],
          const SizedBox(height: 20),
          NfPrimaryButton(
            label: 'Soumettre la demande',
            loading: loading,
            onPressed: eligible ? _submit : null,
          ),
        ],
      ),
    );
  }
}

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late TextEditingController nameCtrl;
  bool shareImf = false;
  String language = 'fr';
  bool iconMode = false;
  bool voiceAssist = false;
  bool saving = false;
  String? message;
  String? error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    nameCtrl = TextEditingController(text: user?.displayName ?? '');
    language = NfStrings.normalize(
      user?.language ?? ref.read(uxPrefsProvider).language,
    );
    iconMode = ref.read(uxPrefsProvider).iconMode;
    voiceAssist = ref.read(uxPrefsProvider).voiceAssist;
    _loadConsents();
  }

  Future<void> _loadConsents() async {
    try {
      final res = await ref
          .read(apiClientProvider)
          .get<Map<String, dynamic>>(
            '/me/consents',
            parse: (d) => Map<String, dynamic>.from(d as Map),
          );
      final items = (res['items'] as List?) ?? [];
      final imf = items.cast<Map>().where((i) => i['type'] == 'partage_imf');
      if (imf.isNotEmpty) {
        setState(() => shareImf = imf.first['accorde'] == true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
      message = null;
    });
    final displayName = nameCtrl.text.trim();
    final profilePayload = {'displayName': displayName};
    final consentsPayload = {'consentCreditPartners': shareImf};
    try {
      final me = await ref
          .read(apiClientProvider)
          .patch<Map<String, dynamic>>(
            '/me',
            data: profilePayload,
            parse: (d) => Map<String, dynamic>.from(d as Map),
          );
      final user = ref.read(authProvider).user!;
      ref
          .read(authProvider.notifier)
          .setUser(
            user.copyWith(
              displayName: me['displayName'] as String? ?? displayName,
              onboardingCompleted: me['onboardingCompleted'] == true,
            ),
          );
      await ref
          .read(apiClientProvider)
          .put('/me/consents', data: consentsPayload);
      await ref
          .read(uxPrefsProvider.notifier)
          .persist(
            language: language,
            iconMode: iconMode,
            voiceAssist: voiceAssist,
          );
      setState(() => message = 'Profil enregistré');
    } on ApiException catch (e) {
      if (e.isOffline || e.isServerError) {
        final createdAt = DateTime.now().toUtc().toIso8601String();
        final queue = ref.read(offlineQueueProvider);
        await queue.enqueue(
          QueuedMutation(
            clientMutationId: OfflineQueue.newId(),
            kind: 'update_profile',
            payload: profilePayload,
            createdAt: createdAt,
          ),
        );
        await queue.enqueue(
          QueuedMutation(
            clientMutationId: OfflineQueue.newId(),
            kind: 'update_consents',
            payload: consentsPayload,
            createdAt: createdAt,
          ),
        );
        await ref.read(syncServiceProvider).refreshCount();
        final user = ref.read(authProvider).user;
        if (user != null) {
          ref
              .read(authProvider.notifier)
              .setUser(user.copyWith(displayName: displayName));
        }
        await ref.read(uxPrefsProvider.notifier).persist(
              language: language,
              iconMode: iconMode,
              voiceAssist: voiceAssist,
            );
        setState(() => message = 'Enregistré hors ligne — sync au retour réseau');
      } else {
        setState(() => error = e.message);
      }
    } finally {
      setState(() => saving = false);
    }
  }

  Future<void> _exportData() async {
    setState(() {
      error = null;
      message = null;
    });
    try {
      final data = await ref.read(apiClientProvider).get<Map<String, dynamic>>(
            '/me/export',
            parse: (d) => Map<String, dynamic>.from(d as Map),
          );
      if (!mounted) return;
      final ops = (data['operations'] as List?)?.length ?? 0;
      final clients = (data['clients'] as List?)?.length ?? 0;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Export de mes données'),
          content: Text(
            'Export généré le ${data['exportedAt'] ?? '—'}.\n'
            '• $ops opération(s)\n'
            '• $clients client(s)\n\n'
            'Les données complètes sont disponibles via l’API '
            'GET /me/export (JSON portable RGPD).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      setState(() => message = 'Export prêt');
    } on ApiException catch (e) {
      setState(() => error = e.message);
    }
  }

  Future<void> _deleteAccount() async {
    final pinCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer mon compte'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Action irréversible : toutes vos données seront effacées '
              '(cahier, score, crédits, consentements).',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'Confirmer avec votre PIN',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NfTokens.danger),
            onPressed: () {
              if (pinCtrl.text.length == 4) Navigator.of(ctx).pop(true);
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiClientProvider).delete(
            '/me',
            data: {'pin': pinCtrl.text, 'confirm': true},
          );
      await ref.read(authProvider.notifier).logout();
      if (mounted) context.go('/login');
    } on ApiException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final pending = ref.watch(syncPendingProvider);
    final t = ref.watch(nfStringsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t('profile'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: NfTokens.brand,
            child: Text(
              (user?.displayName ?? 'N').substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontSize: 28,
                color: NfTokens.bg,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            user?.phone ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: NfTokens.textMute),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: nameCtrl,
            decoration: InputDecoration(labelText: t('displayName')),
          ),
          const SizedBox(height: 12),
          Text(t('language'), style: const TextStyle(color: NfTokens.textMute)),
          const SizedBox(height: 8),
          NfSegmented(
            value: language,
            onChanged: (v) => setState(() => language = v),
            options: [for (final e in NfStrings.selectableLanguages) e],
          ),
          const SizedBox(height: 12),
          Text(t('iconMode'), style: const TextStyle(color: NfTokens.textMute)),
          const SizedBox(height: 4),
          Text(
            t('iconModeHint'),
            style: const TextStyle(color: NfTokens.textMute, fontSize: 13),
          ),
          const SizedBox(height: 8),
          NfSegmented(
            value: iconMode ? 'oui' : 'non',
            onChanged: (v) => setState(() => iconMode = v == 'oui'),
            options: const [('oui', 'Oui'), ('non', 'Non')],
          ),
          const SizedBox(height: 12),
          Text(
            t('voiceAssist'),
            style: const TextStyle(color: NfTokens.textMute),
          ),
          const SizedBox(height: 4),
          Text(
            t('voiceAssistHint'),
            style: const TextStyle(color: NfTokens.textMute, fontSize: 13),
          ),
          const SizedBox(height: 8),
          NfSegmented(
            value: voiceAssist ? 'oui' : 'non',
            onChanged: (v) => setState(() => voiceAssist = v == 'oui'),
            options: const [('oui', 'Oui'), ('non', 'Non')],
          ),
          if (voiceAssist) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  t('listen'),
                  style: const TextStyle(color: NfTokens.textMute),
                ),
                NfSpeakButton(labelKey: 'voiceAssist', alwaysShow: true),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(t('shareImf'), style: const TextStyle(color: NfTokens.textMute)),
          NfSegmented(
            value: shareImf ? 'ok' : 'no',
            onChanged: (v) => setState(() => shareImf = v == 'ok'),
            options: [('ok', t('allow')), ('no', t('deny'))],
          ),
          if (message != null)
            Text(message!, style: const TextStyle(color: NfTokens.ok)),
          if (error != null)
            Text(error!, style: const TextStyle(color: NfTokens.danger)),
          const SizedBox(height: 12),
          NfPrimaryButton(label: t('save'), loading: saving, onPressed: _save),
          const SizedBox(height: 16),
          ListTile(
            title: Text(t('neoscore')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/app/score'),
          ),
          ListTile(
            title: Text(t('credit')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/app/credit'),
          ),
          ListTile(
            title: Text(
              pending > 0
                  ? '${t('offlineQueue')} · ${t.format('offlinePending', {'n': '$pending'})}'
                  : '${t('offlineQueue')} · ${t('offlineUpToDate')}',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Exporter mes données'),
            subtitle: const Text('Droit d’accès RGPD'),
            onTap: _exportData,
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: NfTokens.danger),
            title: const Text(
              'Supprimer mon compte',
              style: TextStyle(color: NfTokens.danger),
            ),
            subtitle: const Text('Droit à l’oubli — irréversible'),
            onTap: _deleteAccount,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            style: OutlinedButton.styleFrom(foregroundColor: NfTokens.danger),
            child: Text(t('logout')),
          ),
        ],
      ),
    );
  }
}
