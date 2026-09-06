import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/client.dart';
import '../../core/offline/local_cache.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/l10n/strings.dart';
import '../../core/offline/queue.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/parse.dart';
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
  String? error;
  bool fromCache = false;
  bool offlineNoCache = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
      fromCache = false;
      offlineNoCache = false;
    });

    Map<String, dynamic>? fetched;
    ApiException? lastApiError;

    for (var attempt = 0; attempt < 3 && fetched == null; attempt++) {
      if (!mounted) return;
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: attempt * 4));
      }
      if (!mounted) return;
      try {
        fetched = await ref
            .read(apiClientProvider)
            .get<Map<String, dynamic>>(
              '/score',
              parse: (d) => Map<String, dynamic>.from(d as Map),
            );
      } on ApiException catch (e) {
        lastApiError = e;
        // 2e essai : recalcul explicite (réveille aussi le service ML)
        if (attempt == 1) {
          try {
            fetched = await ref
                .read(apiClientProvider)
                .post<Map<String, dynamic>>(
                  '/score/recalculate',
                  parse: (d) => Map<String, dynamic>.from(d as Map),
                );
          } on ApiException catch (e2) {
            lastApiError = e2;
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (!mounted) return;

    if (fetched != null) {
      await ref.read(localCacheProvider).putMap(LocalCacheKeys.score, fetched);
      if (!mounted) return;
      setState(() {
        score = fetched;
        loading = false;
      });
      return;
    }

    final cached = ref.read(localCacheProvider).getMap(LocalCacheKeys.score);
    if (!mounted) return;
    final offline = lastApiError?.isOffline == true;
    setState(() {
      score = cached;
      fromCache = cached != null;
      offlineNoCache = offline && cached == null;
      error = offline
          ? (cached == null
              ? ref.read(nfStringsProvider)('scoreOfflineNoCache')
              : 'Connexion lente ou hors ligne. Affichage du dernier score connu.')
          : (lastApiError?.message ??
              'Impossible de charger le score pour le moment.');
      loading = false;
    });
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
        body: RefreshIndicator(
          onRefresh: _load,
          color: NfTokens.brand,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 48),
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: NfTokens.textMute,
              ),
              const SizedBox(height: 16),
              Text(
                error ?? t('scoreOfflineNoCache'),
                textAlign: TextAlign.center,
                style: TextStyle(color: NfTokens.textMute),
              ),
              if (!offlineNoCache) ...[
                const SizedBox(height: 8),
                Text(
                  'L’API Render peut mettre 30–40 s à se réveiller au premier appel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              NfPrimaryButton(label: 'Réessayer', onPressed: _load),
            ],
          ),
        ),
      );
    }
    final criteria = Map<String, dynamic>.from(
      score!['criteria'] as Map? ?? {},
    );
    final history = (score!['history'] as List?) ?? [];
    final eligible = score!['eligible'] == true;
    final statusKey = eligible ? 'eligible' : 'notEligible';
    final dataQuality = score!['dataQuality'] as Map?;
    final warnings = (dataQuality?['warnings'] as List?) ?? [];
    final repayment = score!['repaymentCapacity'] as Map?;

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
      body: RefreshIndicator(
        onRefresh: _load,
        color: NfTokens.brand,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (fromCache) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: NfTokens.elevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NfTokens.brand.withValues(alpha: 0.35)),
                ),
                child: Text(
                  error ?? 'Score affiché depuis le cache local.',
                  style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                ),
              ),
            ],
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
              style: TextStyle(color: NfTokens.textMute),
            ),
          ),
          if (repayment != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Capacité remboursement : ~${asFcfaInt(repayment['maxMonthlyPaymentFcfa'])} FCFA/mois',
                style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...warnings.map(
              (w) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '• $w',
                  style: TextStyle(color: NfTokens.warn, fontSize: 13),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          ...[
            ('Régularité', criteria['regularite']),
            ('Volume d’activité', criteria['volume']),
            ('Gestion des créances', criteria['dettes']),
            ('Croissance', criteria['croissance']),
          ].map((e) {
            final pct = asNumDouble(e.$2);
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
                        style: TextStyle(color: NfTokens.textMute),
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
            Text(
              warnings.isNotEmpty
                  ? warnings.first.toString()
                  : 'Continuez d’enregistrer des ventes pour dépasser 50.',
              style: TextStyle(color: NfTokens.textMute),
            ),
          ],
        ),
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
  List<Map<String, dynamic>> applications = [];
  int amount = 150000;
  String purpose = 'stock';
  String? reference;
  String? error;
  bool needConsent = false;
  bool loading = false;

  static String _statusLabel(String? status) {
    switch (status) {
      case 'brouillon':
        return 'Brouillon';
      case 'soumise':
        return 'Soumise';
      case 'en_examen':
        return 'En examen';
      case 'approuvee':
        return 'Approuvée';
      case 'refusee':
        return 'Refusée';
      case 'decaissee':
        return 'Décaissée';
      default:
        return status ?? '—';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final o = await ref
          .read(apiClientProvider)
          .get<Map<String, dynamic>>(
            '/credit/offer',
            parse: (d) => Map<String, dynamic>.from(d as Map),
          );
      if (!mounted) return;
      setState(() {
        offer = o;
        amount = asFcfaInt(o['suggestedFcfa'], fallback: amount);
      });
    } catch (_) {
      if (mounted) setState(() => offer = null);
    }
    if (!mounted) return;
    try {
      final list = await ref.read(apiClientProvider).get<List>(
            '/credit/applications',
            parse: (d) => d as List,
          );
      if (!mounted) return;
      setState(() {
        applications = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (_) {
      // keep previous list
    }
  }

  Future<void> _grantConsent() async {
    try {
      await ref
          .read(apiClientProvider)
          .put('/me/consents', data: {'consentCreditPartners': true});
      if (mounted) setState(() => needConsent = false);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _submit() async {
    if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        reference = app['reference'] as String?;
        applications = [app, ...applications];
      });
    } on ApiException catch (e) {
      if (!mounted) return;
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
        if (!mounted) return;
        setState(() => reference = 'HORS-LIGNE');
      } else {
        final code = (e.body is Map) ? (e.body as Map)['error'] : null;
        setState(() {
          error = e.message;
          needConsent = code == 'consent_required';
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
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
                    : 'Statut · ${_statusLabel(applications.isNotEmpty ? applications.first['status']?.toString() : 'soumise')}',
                style: TextStyle(color: NfTokens.textMute),
              ),
              const Spacer(),
              NfPrimaryButton(
                label: 'Accueil',
                onPressed: () => context.go('/app'),
              ),
              TextButton(
                onPressed: () => setState(() => reference = null),
                child: const Text('Voir mes demandes'),
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
                ? '${t('credit')}. ${fmt.format(asFcfaInt(offer?['suggestedFcfa']))} FCFA. ${t('submitCredit')}.'
                : '${t('credit')}. ${t('notEligible')}.',
            alwaysShow: true,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (applications.isNotEmpty) ...[
            Text(
              'Mes demandes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...applications.take(5).map((app) {
              final status = app['status']?.toString();
              return Card(
                child: ListTile(
                  title: Text(app['reference']?.toString() ?? 'Demande'),
                  subtitle: Text(
                    '${fmt.format(asFcfaInt(app['amountFcfa']))} FCFA · ${_statusLabel(status)}',
                    style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                  ),
                  trailing: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      color: status == 'approuvee' || status == 'decaissee'
                          ? NfTokens.ok
                          : status == 'refusee'
                              ? NfTokens.danger
                              : NfTokens.brandSoft,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
          if (offer != null && !eligible)
            Text(
              'Non éligible (score ${offer?['score'] ?? '—'})',
              style: TextStyle(color: NfTokens.danger),
            ),
          if (eligible)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Montant estimé',
                      style: TextStyle(color: NfTokens.textMute),
                    ),
                    Text(
                      '${fmt.format(asFcfaInt(offer!['suggestedFcfa']))} FCFA',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      '${fmt.format(asFcfaInt(offer!['minFcfa']))} – ${fmt.format(asFcfaInt(offer!['maxFcfa']))} · ${asFcfaInt(offer!['durationMonths'])} mois',
                      style: TextStyle(color: NfTokens.textMute),
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
          Text(
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
  late TextEditingController idNumberCtrl;
  late TextEditingController addressCtrl;
  late TextEditingController birthDateCtrl;
  String idType = 'cni';
  String kycStatut = 'non_verifie';
  bool shareImf = false;
  bool consentAnonymized = true;
  bool consentMarketing = false;
  bool saving = false;
  String? message;
  String? error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    nameCtrl = TextEditingController(text: user?.displayName ?? '');
    idNumberCtrl = TextEditingController();
    addressCtrl = TextEditingController();
    birthDateCtrl = TextEditingController();
    // Chargements API / cache hors initState+build (évite écran rouge Riverpod).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadConsents();
      _loadKyc();
    });
  }

  Future<void> _loadKyc() async {
    void apply(Map<String, dynamic> me) {
      final rawBirth = me['dateNaissance']?.toString();
      String birth = '';
      if (rawBirth != null && rawBirth.length >= 10) {
        birth = rawBirth.substring(0, 10);
      }
      setState(() {
        kycStatut = me['kycStatut']?.toString() ?? 'non_verifie';
        idType = me['pieceIdentiteType']?.toString() ?? 'cni';
        idNumberCtrl.text = me['pieceIdentiteNumero']?.toString() ?? '';
        addressCtrl.text = me['adresse']?.toString() ?? '';
        birthDateCtrl.text = birth;
      });
    }

    try {
      final me = await ref.read(apiClientProvider).get<Map<String, dynamic>>(
            '/me',
            parse: (d) => Map<String, dynamic>.from(d as Map),
          );
      if (!mounted) return;
      await ref.read(localCacheProvider).putMap(LocalCacheKeys.profile, me);
      apply(me);
    } catch (_) {
      final cached = ref.read(localCacheProvider).getMap(LocalCacheKeys.profile);
      if (cached != null && mounted) apply(cached);
    }
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
      bool? imf;
      bool? anon;
      bool? marketing;
      for (final raw in items) {
        final i = Map<String, dynamic>.from(raw as Map);
        final type = i['type']?.toString();
        final accorde = i['accorde'] == true;
        if (type == 'partage_imf') imf = accorde;
        if (type == 'anonymisation_recherche') anon = accorde;
        if (type == 'marketing_partenaires') marketing = accorde;
      }
      if (!mounted) return;
      setState(() {
        if (imf != null) shareImf = imf;
        if (anon != null) consentAnonymized = anon;
        if (marketing != null) consentMarketing = marketing;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    idNumberCtrl.dispose();
    addressCtrl.dispose();
    birthDateCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
      message = null;
    });
    final displayName = nameCtrl.text.trim();
    final idNumber = idNumberCtrl.text.trim();
    final address = addressCtrl.text.trim();
    final birth = birthDateCtrl.text.trim();
    final profilePayload = <String, dynamic>{
      'displayName': displayName,
      if (idNumber.isNotEmpty) 'pieceIdentiteType': idType,
      if (idNumber.isNotEmpty) 'pieceIdentiteNumero': idNumber,
      if (address.isNotEmpty) 'adresse': address,
      if (birth.length >= 10) 'dateNaissance': birth.substring(0, 10),
    };
    final consentsPayload = {
      'consentCreditPartners': shareImf,
      'consentAnonymized': consentAnonymized,
      'consentMarketing': consentMarketing,
    };
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
      setState(() {
        message = 'Profil enregistré';
        if (me['kycStatut'] != null) {
          kycStatut = me['kycStatut'].toString();
        }
      });
      await ref.read(localCacheProvider).putMap(LocalCacheKeys.profile, me);
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
        // Brouillon KYC / profil lisible hors ligne jusqu'à la sync.
        final existing =
            ref.read(localCacheProvider).getMap(LocalCacheKeys.profile) ??
                <String, dynamic>{};
        await ref.read(localCacheProvider).putMap(LocalCacheKeys.profile, {
          ...existing,
          'displayName': displayName,
          if (idNumber.isNotEmpty) 'pieceIdentiteType': idType,
          if (idNumber.isNotEmpty) 'pieceIdentiteNumero': idNumber,
          if (address.isNotEmpty) 'adresse': address,
          if (birth.length >= 10) 'dateNaissance': birth.substring(0, 10),
          'kycStatut': kycStatut == 'non_verifie' ? 'en_cours' : kycStatut,
          'pendingSync': true,
        });
        await ref.read(syncServiceProvider).refreshCount();
        final user = ref.read(authProvider).user;
        if (user != null) {
          ref
              .read(authProvider.notifier)
              .setUser(user.copyWith(displayName: displayName));
        }
        setState(() => message = 'Enregistré hors ligne — sync au retour réseau');
      } else {
        setState(() => error = e.message);
      }
    } finally {
      setState(() => saving = false);
    }
  }

  Future<void> _sharePassport() async {
    final t = ref.read(nfStringsProvider);
    try {
      final p = await ref.read(apiClientProvider).get<Map<String, dynamic>>(
            '/me/passport',
            parse: (d) => Map<String, dynamic>.from(d as Map),
          );
      final score = p['score'] as Map? ?? {};
      final sales = p['sales30d'] as Map? ?? {};
      final debts = p['openDebts'] as Map? ?? {};
      final stock = p['stock'] as Map? ?? {};
      final profile = p['profile'] as Map? ?? {};
      final text = [
        '${NfTokens.appName} — ${t('passport')}',
        'Nom : ${profile['displayName'] ?? ''}',
        'Tél : ${profile['phone'] ?? ''}',
        'NeoScore : ${score['valeur'] ?? score['score'] ?? '—'} (${score['segment'] ?? ''})',
        'Ventes 30j : ${asFcfaInt(sales['totalFcfa'])} FCFA',
        'Créances : ${asFcfaInt(debts['totalFcfa'])} FCFA',
        'Stock : ${asFcfaInt(stock['articleCount'])} articles',
      ].join('\n');
      await SharePlus.instance.share(
        ShareParams(text: text, subject: t('passport')),
      );
    } on ApiException catch (e) {
      setState(() => error = e.message);
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

  String _kycLabel(NfStrings t, String statut) {
    switch (statut) {
      case 'en_cours':
        return t('kycPending');
      case 'verifie':
        return t('kycVerified');
      case 'refuse':
        return t('kycRejected');
      default:
        return t('kycUnverified');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final t = ref.watch(nfStringsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('profile')),
        actions: [
          IconButton(
            tooltip: t('settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/app/parametres'),
          ),
        ],
      ),
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
                color: NfTokens.onBrand,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            user?.phone ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(color: NfTokens.textMute),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_outlined, color: NfTokens.brand),
            title: Text(t('settings')),
            subtitle: Text(t('aboutHelpHint')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/app/parametres'),
          ),
          const Divider(height: 28),
          TextField(
            controller: nameCtrl,
            decoration: InputDecoration(labelText: t('displayName')),
          ),
          const SizedBox(height: 16),
          Text(
            t('kycSection'),
            style: TextStyle(
              color: NfTokens.text,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t('kycHint'),
            style: TextStyle(color: NfTokens.textMute, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            '${t('kycStatus')} : ${_kycLabel(t, kycStatut)}',
            style: TextStyle(color: NfTokens.brand, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(t('idType'), style: TextStyle(color: NfTokens.textMute)),
          const SizedBox(height: 8),
          NfSegmented(
            value: idType,
            onChanged: (v) => setState(() => idType = v),
            options: [
              ('cni', t('idCni')),
              ('passport', t('idPassport')),
              ('consulaire', t('idConsular')),
              ('autre', t('idOther')),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: idNumberCtrl,
            decoration: InputDecoration(labelText: t('idNumber')),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: birthDateCtrl,
            decoration: InputDecoration(
              labelText: t('birthDate'),
              hintText: 'AAAA-MM-JJ',
            ),
            keyboardType: TextInputType.datetime,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: addressCtrl,
            decoration: InputDecoration(labelText: t('address')),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          Text(
            t('shareImf'),
            style: TextStyle(color: NfTokens.textMute),
          ),
          NfSegmented(
            value: shareImf ? 'ok' : 'no',
            onChanged: (v) => setState(() => shareImf = v == 'ok'),
            options: [('ok', t('allow')), ('no', t('deny'))],
          ),
          const SizedBox(height: 12),
          Text(
            t('consentAnonymized'),
            style: TextStyle(color: NfTokens.textMute),
          ),
          NfSegmented(
            value: consentAnonymized ? 'ok' : 'no',
            onChanged: (v) => setState(() => consentAnonymized = v == 'ok'),
            options: [('ok', t('allow')), ('no', t('deny'))],
          ),
          const SizedBox(height: 12),
          Text(
            t('consentMarketing'),
            style: TextStyle(color: NfTokens.textMute),
          ),
          NfSegmented(
            value: consentMarketing ? 'ok' : 'no',
            onChanged: (v) => setState(() => consentMarketing = v == 'ok'),
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
            leading: const Icon(Icons.badge_outlined),
            title: Text(t('passport')),
            trailing: const Icon(Icons.ios_share),
            onTap: _sharePassport,
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(t('stock')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/app/stock'),
          ),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: Text(t('tontine')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/app/tontine'),
          ),
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
          const SizedBox(height: 12),
          Text(
            'Données & compte',
            style: TextStyle(
              color: NfTokens.text,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          _PrivacyActionsCard(
            onExport: _exportData,
            onDelete: _deleteAccount,
            onLogout: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            logoutLabel: t('logout'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PrivacyActionsCard extends StatelessWidget {
  const _PrivacyActionsCard({
    required this.onExport,
    required this.onDelete,
    required this.onLogout,
    required this.logoutLabel,
  });

  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onLogout;
  final String logoutLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: NfTokens.elevated,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: NfTokens.line),
            boxShadow: NfTokens.isDark
                ? null
                : [
                    BoxShadow(
                      color: NfTokens.text.withValues(alpha: 0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _PrivacyActionTile(
                icon: Icons.download_outlined,
                iconColor: NfTokens.brand,
                iconBg: NfTokens.brand.withValues(alpha: 0.12),
                title: 'Exporter mes données',
                subtitle: 'Droit d’accès RGPD',
                onTap: onExport,
              ),
              Divider(height: 1, thickness: 1, color: NfTokens.line),
              _PrivacyActionTile(
                icon: Icons.delete_outline_rounded,
                iconColor: NfTokens.danger,
                iconBg: NfTokens.danger.withValues(alpha: 0.12),
                title: 'Supprimer mon compte',
                titleColor: NfTokens.danger,
                subtitle: 'Droit à l’oubli — irréversible',
                onTap: onDelete,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: onLogout,
            style: OutlinedButton.styleFrom(
              foregroundColor: NfTokens.danger,
              backgroundColor: NfTokens.elevated,
              side: BorderSide(
                color: NfTokens.danger.withValues(alpha: 0.45),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 0.2,
              ),
            ),
            child: Text(logoutLabel),
          ),
        ),
      ],
    );
  }
}

class _PrivacyActionTile extends StatelessWidget {
  const _PrivacyActionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.titleColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: titleColor ?? NfTokens.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: NfTokens.textMute,
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: NfTokens.textMute.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
