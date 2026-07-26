import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/client.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/offline/queue.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/nf_widgets.dart';
import '../sync/sync_service.dart';
import 'stock_data.dart';

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage> {
  Future<void> _addArticle() async {
    final t = ref.read(nfStringsProvider);
    final nomCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('addArticle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: t('articleName')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: t('quantity')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: '${t('amount')} (u.)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('save')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final nom = nomCtrl.text.trim();
    if (nom.isEmpty) return;
    final quantite = int.tryParse(qtyCtrl.text) ?? 0;
    final prix = int.tryParse(priceCtrl.text);

    try {
      await ref
          .read(stockRepositoryProvider)
          .create(nom: nom, quantite: quantite, prixUnitaireFcfa: prix);
      ref.read(stockRevisionProvider.notifier).state++;
    } on ApiException catch (e) {
      if (e.isOffline || e.isServerError) {
        final mutationId = OfflineQueue.newId();
        final createdAt = DateTime.now().toUtc().toIso8601String();
        await ref.read(offlineQueueProvider).enqueue(
          QueuedMutation(
            clientMutationId: mutationId,
            kind: 'create_operation',
            payload: {
              'type': 'stock',
              'amountFcfa': 0,
              'label': 'Stock',
              'natureStock': 'entree',
              'articleName': nom,
              'quantity': quantite,
              'clientMutationId': mutationId,
              'createdAt': createdAt,
            },
            createdAt: createdAt,
          ),
        );
        await ref.read(syncServiceProvider).refreshCount();
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
    final async = ref.watch(stockArticlesProvider);
    final fmt = NumberFormat.decimalPattern('fr');

    return Scaffold(
      appBar: AppBar(
        leading: nfBackButton(context, fallbackLocation: '/app'),
        title: Text(t('stock')),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: NfTokens.brand,
        foregroundColor: NfTokens.onBrand,
        onPressed: _addArticle,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(stockRevisionProvider.notifier).state++;
          await ref.read(stockArticlesProvider.future);
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                t('offlineQueue'),
                style: TextStyle(color: NfTokens.textMute),
              ),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 40),
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 48,
                    color: NfTokens.textMute,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t('noArticles'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: NfTokens.textMute),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final a = items[i];
                final low = a.quantite <= 2;
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: NfTokens.elevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: low ? NfTokens.warn : NfTokens.line,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: NfTokens.card2,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          color: NfTokens.brandSoft,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.nom,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (a.prixUnitaireFcfa != null)
                              Text(
                                '${fmt.format(a.prixUnitaireFcfa)} FCFA / ${a.unite}',
                                style: TextStyle(color: NfTokens.textMute,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${a.quantite} ${a.unite}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: low ? NfTokens.warn : NfTokens.text,
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
