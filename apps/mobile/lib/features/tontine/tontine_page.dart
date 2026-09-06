import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/client.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/offline/local_cache.dart';
import '../../core/offline/queue.dart';
import '../../core/riverpod_safe.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/nf_widgets.dart';
import '../sync/sync_service.dart';
import 'tontine_data.dart';

class TontinePage extends ConsumerStatefulWidget {
  const TontinePage({super.key});

  @override
  ConsumerState<TontinePage> createState() => _TontinePageState();
}

class _TontinePageState extends ConsumerState<TontinePage> {
  Future<void> _createTontine() async {
    final t = ref.read(nfStringsProvider);
    final nomCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String frequence = 'mensuel';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(t('newTontine')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: t('tontineName')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: t('cotisationAmount')),
              ),
              const SizedBox(height: 12),
              NfSegmented(
                value: frequence,
                onChanged: (v) => setDialogState(() => frequence = v),
                options: const [
                  ('quotidien', 'Quotidien'),
                  ('hebdo', 'Hebdo'),
                  ('mensuel', 'Mensuel'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t('save')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final nom = nomCtrl.text.trim();
    final amount = int.tryParse(amountCtrl.text) ?? 0;
    if (nom.isEmpty || amount <= 0) return;
    try {
      await ref
          .read(tontineRepositoryProvider)
          .create(nom: nom, cotisationFcfa: amount, frequence: frequence);
      bumpStateProvider(ref.read(tontineRevisionProvider.notifier));
    } on ApiException catch (e) {
      if (e.isOffline || e.isServerError) {
        final mutationId = OfflineQueue.newId();
        final createdAt = DateTime.now().toUtc().toIso8601String();
        await ref.read(offlineQueueProvider).enqueue(
          QueuedMutation(
            clientMutationId: mutationId,
            kind: 'create_tontine',
            payload: {
              'nom': nom,
              'cotisationFcfa': amount,
              'frequence': frequence,
              'membres': 1,
            },
            createdAt: createdAt,
          ),
        );
        final cache = ref.read(localCacheProvider);
        final existing = cache.getList(LocalCacheKeys.tontines);
        await cache.putList(LocalCacheKeys.tontines, [
          ...existing,
          {
            'id': mutationId,
            'nom': nom,
            'cotisationFcfa': amount,
            'frequence': frequence,
            'membres': 1,
            'actif': true,
            'cotisations': <Map<String, dynamic>>[],
          },
        ]);
        await ref.read(syncServiceProvider).refreshCount();
        bumpStateProvider(ref.read(tontineRevisionProvider.notifier));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t('savedOffline'))),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _recordCotisation(TontineInfo tontine) async {
    final t = ref.read(nfStringsProvider);
    final amountCtrl = TextEditingController(text: '${tontine.cotisationFcfa}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('recordCotisation')),
        content: TextField(
          controller: amountCtrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: t('amount')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('confirm')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final amount = int.tryParse(amountCtrl.text) ?? 0;
    if (amount <= 0) return;
    try {
      await ref
          .read(tontineRepositoryProvider)
          .addCotisation(tontine.id, amount);
      bumpStateProvider(ref.read(tontineRevisionProvider.notifier));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('cotisationSaved'))));
      }
    } on ApiException catch (e) {
      if (e.isOffline || e.isServerError) {
        final mutationId = OfflineQueue.newId();
        final createdAt = DateTime.now().toUtc().toIso8601String();
        await ref.read(offlineQueueProvider).enqueue(
          QueuedMutation(
            clientMutationId: mutationId,
            kind: 'create_tontine_cotisation',
            payload: {
              'tontineId': tontine.id,
              'montantFcfa': amount,
            },
            createdAt: createdAt,
          ),
        );
        final cache = ref.read(localCacheProvider);
        final items = cache.getList(LocalCacheKeys.tontines);
        final updated = items.map((m) {
          if (m['id']?.toString() != tontine.id) return m;
          final cotisations = List<Map<String, dynamic>>.from(
            ((m['cotisations'] as List?) ?? []).map(
              (e) => Map<String, dynamic>.from(e as Map),
            ),
          );
          cotisations.insert(0, {
            'id': mutationId,
            'montantFcfa': amount,
            'datePaiement': createdAt,
          });
          return {...m, 'cotisations': cotisations};
        }).toList();
        await cache.putList(LocalCacheKeys.tontines, updated);
        await ref.read(syncServiceProvider).refreshCount();
        bumpStateProvider(ref.read(tontineRevisionProvider.notifier));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t('savedOffline'))),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(nfStringsProvider);
    final async = ref.watch(tontinesProvider);
    final fmt = NumberFormat.decimalPattern('fr');
    final hasCache = ref.read(localCacheProvider).hasKey(LocalCacheKeys.tontines);

    return Scaffold(
      appBar: AppBar(
        leading: nfBackButton(context, fallbackLocation: '/app'),
        title: Text(t('tontine')),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: NfTokens.brand,
        foregroundColor: NfTokens.onBrand,
        onPressed: _createTontine,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          bumpStateProvider(ref.read(tontineRevisionProvider.notifier));
          await ref.read(tontinesProvider.future);
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => NfOfflineEmpty(
            message: t('offlineCanRecord'),
            actionLabel: t('newTontine'),
            onAction: _createTontine,
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 40),
                  Icon(
                    Icons.groups_2_outlined,
                    size: 48,
                    color: NfTokens.textMute,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    hasCache ? t('noTontine') : t('offlineCanRecord'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: NfTokens.textMute),
                  ),
                  const SizedBox(height: 16),
                  NfPrimaryButton(
                    label: t('newTontine'),
                    onPressed: _createTontine,
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final tontine = items[i];
                final total = tontine.cotisations.fold<int>(
                  0,
                  (s, c) => s + c.montantFcfa,
                );
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: NfTokens.elevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: NfTokens.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tontine.nom,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Text(
                            '${fmt.format(tontine.cotisationFcfa)} FCFA',
                            style: const TextStyle(
                              color: NfTokens.brandSoft,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tontine.frequence} · ${tontine.membres} membre(s)',
                        style: TextStyle(
                          color: NfTokens.textMute,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${t('totalCotise')} : ${fmt.format(total)} FCFA',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () => _recordCotisation(tontine),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(t('recordCotisation')),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
