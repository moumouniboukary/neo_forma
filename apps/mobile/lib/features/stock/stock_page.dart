import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/client.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/offline/local_cache.dart';
import '../../core/offline/queue.dart';
import '../../core/riverpod_safe.dart';
import '../../core/theme/tokens.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/nf_speak_button.dart';
import '../../core/widgets/nf_widgets.dart';
import '../../core/utils/qty.dart';
import '../../core/widgets/nf_unit_chips.dart';
import '../sync/sync_service.dart';
import 'stock_add_voice.dart';
import 'stock_data.dart';

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(uxPrefsProvider).voiceAssist) {
        ref.read(voiceServiceProvider).speakKey('stock');
      }
    });
  }

  Future<void> _speakArticle(ArticleStock a, NumberFormat fmt) async {
    final voice = ref.read(voiceServiceProvider);
    final t = ref.read(nfStringsProvider);
    final price = a.prixUnitaireFcfa != null
        ? '${fmt.format(a.prixUnitaireFcfa)} FCFA'
        : '';
    final low = a.quantite <= 2 ? t('stockLow') : '';
    await voice.speakText(
      '${a.nom}. ${formatQty(a.quantite)} ${unitLabelOf(a.unite, t)}. $price. $low'.trim(),
    );
  }

  Future<void> _addArticle() async {
    final t = ref.read(nfStringsProvider);
    final draft = await showVoiceGuidedAddArticle(context, ref);
    if (draft == null || !mounted) return;
    final nom = draft.nom.trim();
    if (nom.isEmpty) return;
    final quantite = draft.quantite;
    final prix = draft.prixUnitaireFcfa;

    try {
        await ref
          .read(stockRepositoryProvider)
          .create(
            nom: nom,
            unite: draft.unite,
            quantite: quantite,
            prixUnitaireFcfa: prix,
          );
      bumpStateProvider(ref.read(stockRevisionProvider.notifier));
      if (ref.read(uxPrefsProvider).voiceAssist) {
        unawaited(ref.read(voiceServiceProvider).speakKey('recordSuccess'));
      }
    } on ApiException catch (e) {
      if (e.isOffline || e.isServerError) {
        final mutationId = OfflineQueue.newId();
        final createdAt = DateTime.now().toUtc().toIso8601String();
        final optimistic = {
          'id': mutationId,
          'nom': nom,
          'unite': draft.unite,
          'quantite': jsonQty(quantite),
          if (prix != null) 'prixUnitaireFcfa': prix,
        };
        await ref.read(offlineQueueProvider).enqueue(
          QueuedMutation(
            clientMutationId: mutationId,
            kind: 'upsert_stock',
            payload: {
              'nom': nom,
              'unite': draft.unite,
              'quantite': jsonQty(quantite),
              if (prix != null) 'prixUnitaireFcfa': prix,
            },
            createdAt: createdAt,
          ),
        );
        await ref.read(localCacheProvider).mergeListById(
          LocalCacheKeys.stock,
          [optimistic],
        );
        await ref.read(syncServiceProvider).refreshCount();
        bumpStateProvider(ref.read(stockRevisionProvider.notifier));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t('savedOffline'))),
          );
        }
        if (ref.read(uxPrefsProvider).voiceAssist) {
          unawaited(ref.read(voiceServiceProvider).speakKey('recordSuccess'));
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
    final iconMode = ref.watch(uxPrefsProvider).iconMode;

    return Scaffold(
      appBar: AppBar(
        leading: nfBackButton(context, fallbackLocation: '/app'),
        title: Text(t('stock')),
        actions: const [
          NfSpeakButton(labelKey: 'stock', alwaysShow: true),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NfTokens.brand,
        foregroundColor: NfTokens.onBrand,
        onPressed: _addArticle,
        icon: Icon(Icons.add, size: iconMode ? 28 : 24),
        label: Text(
          t('addArticle'),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: iconMode ? 16 : 14,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          bumpStateProvider(ref.read(stockRevisionProvider.notifier));
          await ref.read(stockArticlesProvider.future);
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => NfOfflineEmpty(
            message: t('offlineCanRecord'),
            actionLabel: t('addArticle'),
            onAction: _addArticle,
          ),
          data: (items) {
            final hasCache =
                ref.read(localCacheProvider).hasKey(LocalCacheKeys.stock);
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                    hasCache ? t('noArticles') : t('offlineCanRecord'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: NfTokens.textMute),
                  ),
                  const SizedBox(height: 16),
                  NfPrimaryButton(
                    label: t('addArticle'),
                    onPressed: _addArticle,
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
                return Material(
                  color: NfTokens.elevated,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _speakArticle(a, fmt),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (a.prixUnitaireFcfa != null)
                                  Text(
                                    '${fmt.format(a.prixUnitaireFcfa)} FCFA / ${unitLabelOf(a.unite, t)}',
                                    style: TextStyle(
                                      color: NfTokens.textMute,
                                      fontSize: 12,
                                    ),
                                  ),
                                if (low)
                                  Text(
                                    t('stockLow'),
                                    style: const TextStyle(
                                      color: NfTokens.warn,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: t('listen'),
                            onPressed: () => _speakArticle(a, fmt),
                            icon: Icon(
                              Icons.volume_up_outlined,
                              color: NfTokens.brandSoft,
                              size: iconMode ? 28 : 24,
                            ),
                          ),
                          Text(
                            '${formatQty(a.quantite)} ${unitLabelOf(a.unite, t)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: iconMode ? 18 : 16,
                              color: low ? NfTokens.warn : NfTokens.text,
                            ),
                          ),
                        ],
                      ),
                    ),
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
