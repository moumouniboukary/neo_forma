import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/client.dart';
import '../../core/brand.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/l10n/strings.dart';
import '../../core/offline/local_cache.dart';
import '../../core/offline/queue.dart';
import '../../core/riverpod_safe.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/parse.dart';
import '../../core/utils/qty.dart';
import '../../core/widgets/nf_a11y_dialogs.dart';
import '../../core/widgets/nf_numeric_keypad.dart';
import '../../core/widgets/nf_qty_stepper.dart';
import '../../core/widgets/nf_speak_button.dart';
import '../../core/widgets/nf_unit_chips.dart';
import '../../core/widgets/nf_widgets.dart';
import '../../core/voice/voice_service.dart';
import '../stock/stock_data.dart';
import '../sync/sync_service.dart';
import 'ledger_data.dart';

enum _VoiceGuidePhase {
  idle,
  pickProduct,
  pickClient,
  pickStockNature,
  pickExpenseCategory,
}

/// Article stock local (id + qty) pour un nom, ou null si absent du catalogue.
({String id, double qty, String unite})? _stockArticleByName(
  LocalCache cache,
  String nom,
) {
  final needle = nom.trim().toLowerCase();
  if (needle.isEmpty) return null;
  for (final raw in cache.getList(LocalCacheKeys.stock)) {
    final n = raw['nom']?.toString().trim().toLowerCase() ?? '';
    if (n == needle) {
      final id = raw['id']?.toString().trim() ?? '';
      if (id.isEmpty) return null;
      return (
        id: id,
        qty: asQty(raw['quantite']),
        unite: normalizeUnite(raw['unite']?.toString()),
      );
    }
  }
  return null;
}

/// Enregistre une vente produit (formulaire complet ou revente rapide).
Future<({bool ok, bool offline, String? error})> submitProductSale(
  WidgetRef ref, {
  required String productName,
  required double qty,
  required int unitPriceFcfa,
  String canal = 'especes',
}) async {
  final amount = (qty * unitPriceFcfa).round();
  if (productName.trim().isEmpty || qty <= 0 || unitPriceFcfa <= 0 || amount <= 0) {
    return (ok: false, offline: false, error: 'Indiquez produit, quantité et prix');
  }
  final mutationId = OfflineQueue.newId();
  final createdAt = DateTime.now().toUtc().toIso8601String();
  final nom = productName.trim();
  final label = '$nom · ${formatQty(qty)} × $unitPriceFcfa';
  final stock = _stockArticleByName(ref.read(localCacheProvider), nom);
  if (stock != null && stock.qty + 1e-9 < qty) {
    return (
      ok: false,
      offline: false,
      error: ref.read(nfStringsProvider).format('stockInsufficient', {
        'n': formatQty(stock.qty),
      }),
    );
  }
  final payload = <String, dynamic>{
    'type': 'vente',
    'amountFcfa': amount,
    'label': label,
    'productName': nom,
    'quantity': jsonQty(qty),
    if (stock != null && isUuid(stock.id)) 'articleStockId': stock.id.trim(),
    'canal': canal,
    'clientMutationId': mutationId,
    'createdAt': createdAt,
  };

  try {
    await ref.read(apiClientProvider).post('/operations', data: payload);
  } on ApiException catch (e) {
    if (!(e.isOffline || e.isServerError)) {
      return (ok: false, offline: false, error: e.message);
    }
    // Vente liée au stock : pas d'optimistic hors ligne (évite double décrément).
    if (stock != null) {
      return (
        ok: false,
        offline: false,
        error: ref.read(nfStringsProvider)('stockOutNeedsNetwork'),
      );
    }
    await ref.read(offlineQueueProvider).enqueue(
          QueuedMutation(
            clientMutationId: mutationId,
            kind: 'create_operation',
            payload: payload,
            createdAt: createdAt,
          ),
        );
    await ref.read(localCacheProvider).mergeListById(
      LocalCacheKeys.operations,
      [
        {
          'id': mutationId,
          'type': 'vente',
          'amountFcfa': amount,
          'montantFcfa': amount,
          'label': label,
          'productName': nom,
          'quantity': jsonQty(qty),
          'canal': canal,
          'createdAt': createdAt,
          'dateOperation': createdAt,
          'pendingSync': true,
        },
      ],
    );
    await ref.read(syncServiceProvider).refreshCount();
    await rememberSaleProduct(
      ref.read(localCacheProvider),
      nom: nom,
      unitPriceFcfa: unitPriceFcfa,
      qty: qty,
      canal: canal,
      soldAt: createdAt,
    );
    bumpStateProvider(ref.read(ledgerRevisionProvider.notifier));
    return (ok: true, offline: true, error: null);
  }

  await rememberSaleProduct(
    ref.read(localCacheProvider),
    nom: nom,
    unitPriceFcfa: unitPriceFcfa,
    qty: qty,
    canal: canal,
    soldAt: createdAt,
  );
  bumpStateProvider(ref.read(ledgerRevisionProvider.notifier));
  if (stock != null) {
    bumpStateProvider(ref.read(stockRevisionProvider.notifier));
  }
  return (ok: true, offline: false, error: null);
}

class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key, this.presetProduct});

  /// Préremplit une vente depuis « Mes produits ».
  final SaleProduct? presetProduct;

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage> {
  String type = 'vente';
  String canal = 'especes';
  String natureStock = 'entree';
  String expenseCategory = 'autre';
  DateTime dueDate = DateTime.now().add(const Duration(days: 7));
  final amountCtrl = TextEditingController();
  final clientCtrl = TextEditingController();
  final productCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final unitPriceCtrl = TextEditingController();
  String saleUnite = 'u';
  String? selectedClientId;
  bool loading = false;
  bool done = false;
  bool savedOffline = false;
  bool listening = false;
  String? error;
  List<SaleProduct> recentProducts = [];
  /// Montant proposé par la saisie vocale, en attente de confirmation oui/non.
  int? pendingConfirmAmount;
  _VoiceGuidePhase guidePhase = _VoiceGuidePhase.idle;
  Completer<void>? _guidePickCompleter;

  static const _expenseCategories = <(String, String, IconData)>[
    ('transport', 'Transport', Icons.directions_bus_outlined),
    ('marchandise', 'Marchandise', Icons.inventory_2_outlined),
    ('loyer', 'Loyer', Icons.home_outlined),
    ('nourriture', 'Nourriture', Icons.restaurant_outlined),
    ('autre', 'Autre', Icons.more_horiz),
  ];

  String _expenseLabel() {
    final motif = productCtrl.text.trim();
    String catLabel = 'Dépense';
    for (final c in _expenseCategories) {
      if (c.$1 == expenseCategory) {
        catLabel = c.$2;
        break;
      }
    }
    if (motif.isEmpty) return catLabel;
    if (expenseCategory != 'autre') return '$motif · $catLabel';
    return motif;
  }

  @override
  void initState() {
    super.initState();
    qtyCtrl.addListener(_recalcSaleTotal);
    unitPriceCtrl.addListener(_recalcSaleTotal);
    final preset = widget.presetProduct;
    if (preset != null) {
      type = 'vente';
      productCtrl.text = preset.nom;
      qtyCtrl.text = formatQty(preset.lastQty);
      unitPriceCtrl.text = '${preset.unitPriceFcfa}';
      canal = preset.canal;
      saleUnite = _stockArticleByName(ref.read(localCacheProvider), preset.nom)
              ?.unite ??
          'u';
      _recalcSaleTotal();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecentProducts();
      _speakGuide();
    });
  }

  void _loadRecentProducts() {
    if (!mounted) return;
    setState(() {
      recentProducts = loadSaleProducts(ref.read(localCacheProvider));
    });
  }

  void _applyProduct(SaleProduct p) {
    final stock = _stockArticleByName(ref.read(localCacheProvider), p.nom);
    setState(() {
      type = 'vente';
      productCtrl.text = p.nom;
      qtyCtrl.text = formatQty(p.lastQty);
      unitPriceCtrl.text = '${p.unitPriceFcfa}';
      canal = p.canal;
      saleUnite = stock?.unite ?? 'u';
      error = null;
    });
    _recalcSaleTotal();
    _completeGuidePick();
  }

  void _completeGuidePick() {
    final c = _guidePickCompleter;
    if (c != null && !c.isCompleted) c.complete();
  }

  String _normSpeak(String s) {
    var t = s.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'[àáâä]'), 'a');
    t = t.replaceAll(RegExp(r'[èéêëẽ]'), 'e');
    t = t.replaceAll(RegExp(r'[ìíîïĩɩ]'), 'i');
    t = t.replaceAll(RegExp(r'[òóôöõɔ]'), 'o');
    t = t.replaceAll(RegExp(r'[ùúûüũʋ]'), 'u');
    t = t.replaceAll('ç', 'c');
    t = t.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  bool _speakMatch(String heard, String candidate) {
    final h = _normSpeak(heard);
    final c = _normSpeak(candidate);
    if (h.isEmpty || c.isEmpty) return false;
    if (h == c) return true;
    if (h.contains(c) || c.contains(h)) return true;
    final hw = h.split(' ').where((w) => w.length >= 3).toSet();
    final cw = c.split(' ').where((w) => w.length >= 3).toSet();
    if (hw.isEmpty || cw.isEmpty) return false;
    return hw.intersection(cw).isNotEmpty;
  }

  /// Bannière micro : texte selon l’étape (pas toujours « Combien ? »).
  String _voiceGuideBanner(NfStrings t) {
    switch (guidePhase) {
      case _VoiceGuidePhase.pickProduct:
        return t('chooseProduct');
      case _VoiceGuidePhase.pickClient:
        return t('chooseClient');
      case _VoiceGuidePhase.pickStockNature:
        return t('chooseStockNature');
      case _VoiceGuidePhase.pickExpenseCategory:
        return t('chooseCategory');
      case _VoiceGuidePhase.idle:
        if (pendingConfirmAmount != null) {
          return t.format('confirmAmount', {
            'n': formatFcfa(pendingConfirmAmount!),
          });
        }
        return listening ? t('askAmount') : t('voiceGuideStart');
    }
  }

  Future<void> _awaitGuidePick({
    required _VoiceGuidePhase phase,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (!mounted) return;
    setState(() => guidePhase = phase);
    _guidePickCompleter = Completer<void>();
    final voice = ref.read(voiceServiceProvider);
    // Micro en parallèle du tap — ne termine le choix que si un match est trouvé.
    unawaited(_listenGuidePick(phase));
    try {
      await _guidePickCompleter!.future.timeout(timeout);
    } on TimeoutException {
      // Pas de choix : on continue.
    } finally {
      await voice.stop();
      if (mounted) setState(() => guidePhase = _VoiceGuidePhase.idle);
      _guidePickCompleter = null;
    }
  }

  Future<void> _listenGuidePick(_VoiceGuidePhase phase) async {
    final voice = ref.read(voiceServiceProvider);
    // Deux tentatives : le micro rate souvent le 1er essai juste après le TTS.
    for (var i = 0; i < 2; i++) {
      if (!mounted) return;
      if (_guidePickCompleter == null || _guidePickCompleter!.isCompleted) {
        return;
      }
      final heard = await voice.listenOnce(
        timeout: const Duration(seconds: 8),
        retries: 2,
      );
      if (!mounted) return;
      if (_guidePickCompleter == null || _guidePickCompleter!.isCompleted) {
        return;
      }
      if (heard == null || heard.trim().isEmpty) continue;
      switch (phase) {
        case _VoiceGuidePhase.pickProduct:
          _applySpokenProduct(heard);
        case _VoiceGuidePhase.pickClient:
          _applySpokenClient(heard);
        case _VoiceGuidePhase.pickStockNature:
          _applySpokenStockNature(heard);
        case _VoiceGuidePhase.pickExpenseCategory:
          _applySpokenExpenseCategory(heard);
        case _VoiceGuidePhase.idle:
          break;
      }
      if (_guidePickCompleter == null || _guidePickCompleter!.isCompleted) {
        return;
      }
    }
  }

  void _applySpokenProduct(String heard) {
    // 1) Produits déjà vendus
    SaleProduct? bestSale;
    for (final p in recentProducts) {
      if (_speakMatch(heard, p.nom)) {
        if (bestSale == null || p.nom.length > bestSale.nom.length) {
          bestSale = p;
        }
      }
    }
    if (bestSale != null) {
      _applyProduct(bestSale);
      return;
    }
    // 2) Articles stock
    final stock = ref
        .read(localCacheProvider)
        .getList(LocalCacheKeys.stock)
        .map(ArticleStock.fromMap);
    ArticleStock? bestStock;
    for (final a in stock) {
      if (_speakMatch(heard, a.nom)) {
        if (bestStock == null || a.nom.length > bestStock.nom.length) {
          bestStock = a;
        }
      }
    }
    if (bestStock != null) {
      setState(() {
        productCtrl.text = bestStock!.nom;
        if (bestStock.prixUnitaireFcfa != null &&
            bestStock.prixUnitaireFcfa! > 0) {
          unitPriceCtrl.text = '${bestStock.prixUnitaireFcfa}';
        }
        saleUnite = bestStock.unite;
        if (parseQty(qtyCtrl.text) <= 0) qtyCtrl.text = '1';
        error = null;
      });
      _recalcSaleTotal();
      _completeGuidePick();
      return;
    }
    // 3) Nouveau nom dicté
    final name = heard.trim();
    if (name.isEmpty) return;
    setState(() {
      productCtrl.text = name[0].toUpperCase() + name.substring(1);
      error = null;
    });
    _completeGuidePick();
  }

  void _applySpokenClient(String heard) {
    final clients = ref
        .read(localCacheProvider)
        .getList(LocalCacheKeys.clients)
        .map(ClientInfo.fromMap);
    ClientInfo? best;
    for (final c in clients) {
      if (_speakMatch(heard, c.nom)) {
        if (best == null || c.nom.length > best.nom.length) best = c;
      }
    }
    if (best != null) {
      setState(() {
        selectedClientId = best!.id;
        clientCtrl.text = best.nom;
        error = null;
      });
      _completeGuidePick();
      return;
    }
    final name = heard.trim();
    if (name.isEmpty) return;
    setState(() {
      selectedClientId = null;
      clientCtrl.text = name[0].toUpperCase() + name.substring(1);
      error = null;
    });
    _completeGuidePick();
  }

  void _applySpokenStockNature(String heard) {
    final h = _normSpeak(heard);
    if (h.contains('sort') || h.contains('out') || h.contains('yi')) {
      setState(() => natureStock = 'sortie');
      _completeGuidePick();
      return;
    }
    if (h.contains('entr') ||
        h.contains('in') ||
        h.contains('achat') ||
        h.contains('kees')) {
      setState(() => natureStock = 'entree');
      _completeGuidePick();
    }
  }

  void _applySpokenExpenseCategory(String heard) {
    for (final cat in _expenseCategories) {
      if (_speakMatch(heard, cat.$1) || _speakMatch(heard, cat.$2)) {
        setState(() => expenseCategory = cat.$1);
        _completeGuidePick();
        return;
      }
    }
  }

  bool _applySpokenOperationType(String heard) {
    final h = _normSpeak(heard);
    final t = ref.read(nfStringsProvider);
    String? next;
    if (h.contains('vent') ||
        h.contains('sale') ||
        _speakMatch(heard, t('sale')) ||
        h.contains('koees') ||
        h.contains('koeesgo') ||
        h.contains('kore')) {
      next = 'vente';
    } else if (h.contains('stock') || _speakMatch(heard, t('stock'))) {
      next = 'stock';
    } else if (h.contains('crean') ||
        h.contains('dette') ||
        h.contains('credit') ||
        _speakMatch(heard, t('receivable')) ||
        h.contains('sega')) {
      next = 'creance';
    } else if (h.contains('depens') ||
        h.contains('expense') ||
        _speakMatch(heard, t('expense')) ||
        h.contains('reem')) {
      next = 'depense';
    }
    if (next == null) return false;
    setState(() {
      type = next!;
      error = null;
      if (next == 'vente' && qtyCtrl.text.trim().isEmpty) {
        qtyCtrl.text = '1';
        _recalcSaleTotal();
      }
    });
    return true;
  }

  @override
  void dispose() {
    qtyCtrl.removeListener(_recalcSaleTotal);
    unitPriceCtrl.removeListener(_recalcSaleTotal);
    amountCtrl.dispose();
    clientCtrl.dispose();
    productCtrl.dispose();
    qtyCtrl.dispose();
    unitPriceCtrl.dispose();
    super.dispose();
  }

  int _parseInt(TextEditingController c) =>
      int.tryParse(c.text.replaceAll(RegExp(r'\s'), '')) ?? 0;

  double _qty() => parseQty(qtyCtrl.text);

  /// Total = quantité × prix unitaire (vente / stock).
  void _recalcSaleTotal() {
    if (type != 'vente' && type != 'stock') return;
    final total = (_qty() * _parseInt(unitPriceCtrl)).round();
    final next = total > 0 ? '$total' : '';
    if (amountCtrl.text == next) return;
    amountCtrl.text = next;
    if (mounted) setState(() {});
  }

  /// Stock dispo local pour un article (nom, insensible à la casse).
  double? _localStockQty(String nom) =>
      _stockArticleByName(ref.read(localCacheProvider), nom)?.qty;

  String? _localStockArticleId(String nom) =>
      _stockArticleByName(ref.read(localCacheProvider), nom)?.id;

  String _saleLabel() {
    final product = productCtrl.text.trim();
    final qty = _qty() <= 0 ? 1.0 : _qty();
    final unit = _parseInt(unitPriceCtrl);
    if (product.isEmpty) return 'Vente';
    if (unit > 0) return '$product · ${formatQty(qty)} × $unit';
    if (qty > 1) return '$product × ${formatQty(qty)}';
    return product;
  }

  String get _typeKey => type == 'vente'
      ? 'sale'
      : type == 'stock'
          ? 'stock'
          : type == 'creance'
              ? 'receivable'
              : 'expense';

  Future<void> _speakGuide() async {
    if (!mounted) return;
    if (!ref.read(uxPrefsProvider).voiceAssist) return;
    final t = ref.read(nfStringsProvider);
    await ref.read(voiceServiceProvider).speakText(
          '${t('record')}. ${t(_typeKey)}. ${t('amount')}.',
          assetKey: 'record',
        );
  }

  void _setType(String v) {
    setState(() {
      type = v;
      error = null;
      if (v == 'vente') {
        if (qtyCtrl.text.trim().isEmpty) qtyCtrl.text = '1';
        _recalcSaleTotal();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakGuide());
  }

  Future<void> _dictateAmount() async {
    if (!kVoiceInputEnabled) return;
    setState(() => listening = true);
    try {
      final voice = ref.read(voiceServiceProvider);
      var amount = await voice.listenAmountOnce(retries: 2);
      if (amount == null || amount <= 0) {
        await voice.speakKey('dictAmountFail');
        amount = await voice.listenAmountOnce(
          timeout: const Duration(seconds: 8),
          retries: 2,
        );
      }
      if (amount == null || amount <= 0) return;
      setState(() {
        if (type == 'vente' || type == 'stock') {
          unitPriceCtrl.text = '$amount';
          _recalcSaleTotal();
        } else {
          amountCtrl.text = '$amount';
        }
      });
    } finally {
      if (mounted) setState(() => listening = false);
    }
  }

  /// Flux bout-en-bout : type → produit/client → montant (FR ou mooré) → confirm.
  Future<void> _voiceGuidedFlow() async {
    if (!kVoiceInputEnabled) return;
    if (listening || loading) return;
    final voice = ref.read(voiceServiceProvider);
    final t = ref.read(nfStringsProvider);
    setState(() {
      listening = true;
      error = null;
      pendingConfirmAmount = null;
      guidePhase = _VoiceGuidePhase.idle;
    });
    try {
      // 1) Type d'opération — icônes déjà là ; on peut aussi le dire.
      await voice.speakKey('chooseType');
      final typeHeard = await voice.listenOnce(
        timeout: const Duration(seconds: 6),
        retries: 2,
      );
      if (!mounted) return;
      if (typeHeard != null && typeHeard.trim().isNotEmpty) {
        _applySpokenOperationType(typeHeard);
      }
      await voice.speakKey(_typeKey);

      // 2) Détails selon le type.
      if (type == 'vente') {
        _loadRecentProducts();
        if (recentProducts.isNotEmpty || productCtrl.text.trim().isEmpty) {
          await voice.speakKey('chooseProduct');
          await _awaitGuidePick(phase: _VoiceGuidePhase.pickProduct);
        }
      } else if (type == 'creance') {
        await voice.speakKey('chooseClient');
        await _awaitGuidePick(phase: _VoiceGuidePhase.pickClient);
      } else if (type == 'stock') {
        await voice.speakKey('chooseStockNature');
        await _awaitGuidePick(phase: _VoiceGuidePhase.pickStockNature);
        await voice.speakKey(
          natureStock == 'sortie' ? 'stockOut' : 'stockIn',
        );
        await voice.speakKey('chooseProduct');
        await _awaitGuidePick(phase: _VoiceGuidePhase.pickProduct);
      } else if (type == 'depense') {
        await voice.speakKey('chooseCategory');
        await _awaitGuidePick(phase: _VoiceGuidePhase.pickExpenseCategory);
      }

      if (!mounted) return;

      // 3) Montant — dictée (avec 2e essai si échec).
      await voice.speakKey('askAmount');
      var amount = await voice.listenAmountOnce(
        timeout: const Duration(seconds: 7),
      );
      if (!mounted) return;
      if (amount == null || amount <= 0) {
        await voice.speakKey('dictAmountFail');
        amount = await voice.listenAmountOnce(
          timeout: const Duration(seconds: 8),
          retries: 2,
        );
      }
      if (!mounted) return;
      if (amount == null || amount <= 0) {
        setState(() => error = t('dictAmountFail'));
        await voice.speakKey('dictAmountFail');
        return;
      }
      if (type == 'vente' || type == 'stock') {
        if (parseQty(qtyCtrl.text) <= 0) qtyCtrl.text = '1';
        // Si un prix unitaire produit est déjà là, on garde qty×prix ;
        // sinon le montant dicté = total (qty 1).
        if (_parseInt(unitPriceCtrl) <= 0 || productCtrl.text.trim().isEmpty) {
          qtyCtrl.text = '1';
          unitPriceCtrl.text = '$amount';
        } else {
          // Produit choisi : le montant dicté remplace le total via prix unitaire.
          qtyCtrl.text = '1';
          unitPriceCtrl.text = '$amount';
        }
        _recalcSaleTotal();
      } else {
        amountCtrl.text = '$amount';
      }
      setState(() => pendingConfirmAmount = amount);
      await voice.speakKey(
        'confirmAmount',
        vars: {'n': formatFcfa(amount)},
      );
    } finally {
      if (mounted) {
        setState(() {
          listening = false;
          guidePhase = _VoiceGuidePhase.idle;
        });
      }
    }
  }

  Future<void> _resolveVoiceConfirm(bool yes) async {
    if (!yes) {
      setState(() => pendingConfirmAmount = null);
      await _voiceGuidedFlow();
      return;
    }
    setState(() => pendingConfirmAmount = null);
    await _submit();
  }

  Future<void> _speakRecordSuccess() async {
    if (!ref.read(uxPrefsProvider).voiceAssist) return;
    await ref.read(voiceServiceProvider).speakKey('recordSuccess');
  }

  void _bumpQty(num delta) {
    final step = qtyStepForUnit(saleUnite);
    final next = roundQty((_qty() + delta).clamp(step, 9999));
    final text = formatQty(next);
    qtyCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _recalcSaleTotal();
    setState(() {});
  }

  /// Dialogue de création d'un nouveau client → sélectionné automatiquement.
  Future<void> _createClient() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final created = await showDialog<ClientInfo>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau client'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone (optionnel)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              final nom = nameCtrl.text.trim();
              if (nom.isEmpty) return;
              try {
                final client = await ref
                    .read(clientsRepositoryProvider)
                    .create(nom: nom, telephone: phoneCtrl.text);
                if (ctx.mounted) Navigator.of(ctx).pop(client);
              } on ApiException catch (e) {
                if (e.isOffline || e.isServerError) {
                  final mutationId = OfflineQueue.newId();
                  final createdAt = DateTime.now().toUtc().toIso8601String();
                  final localId = 'local-$mutationId';
                  await ref.read(offlineQueueProvider).enqueue(
                        QueuedMutation(
                          clientMutationId: mutationId,
                          kind: 'create_client',
                          payload: {
                            'nom': nom,
                            if (phoneCtrl.text.trim().isNotEmpty)
                              'telephone': phoneCtrl.text.trim(),
                            'clientMutationId': mutationId,
                          },
                          createdAt: createdAt,
                        ),
                      );
                  await ref.read(localCacheProvider).mergeListById(
                        LocalCacheKeys.clients,
                        [
                          {
                            'id': localId,
                            'nom': nom,
                            if (phoneCtrl.text.trim().isNotEmpty)
                              'telephone': phoneCtrl.text.trim(),
                            'pendingSync': true,
                          },
                        ],
                      );
                  await ref.read(syncServiceProvider).refreshCount();
                  bumpStateProvider(ref.read(ledgerRevisionProvider.notifier));
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop(
                      ClientInfo(
                        id: localId,
                        nom: nom,
                        telephone: phoneCtrl.text.trim(),
                      ),
                    );
                  }
                } else if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(e.message)),
                  );
                }
              }
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (created != null) {
      if (created.id.isNotEmpty) {
        bumpStateProvider(ref.read(ledgerRevisionProvider.notifier));
        setState(() {
          selectedClientId = created.id;
          clientCtrl.text = created.nom;
        });
      } else {
        // Client créé hors ligne — créance via clientName.
        setState(() {
          selectedClientId = null;
          clientCtrl.text = created.nom;
        });
      }
      _completeGuidePick();
    }
  }

  Future<void> _submit() async {
    setState(() {
      loading = true;
      error = null;
    });
    if (type == 'vente' || type == 'stock') _recalcSaleTotal();
    final amount = _parseInt(amountCtrl);
    final qty = _qty() <= 0 ? 1.0 : _qty();
    final product = productCtrl.text.trim();
    final unit = _parseInt(unitPriceCtrl);

    if (type == 'stock' || type == 'vente') {
      if (type == 'stock' && product.isEmpty) {
        setState(() {
          loading = false;
          error = ref.read(nfStringsProvider)('stockNeedArticle');
        });
        return;
      }
      if (type == 'stock' && unit <= 0) {
        setState(() {
          loading = false;
          error = ref.read(nfStringsProvider)('stockNeedUnitPrice');
        });
        return;
      }
      final needsStockCheck =
          (type == 'stock' && natureStock == 'sortie') || type == 'vente';
      if (needsStockCheck && product.isNotEmpty) {
        // Cache local seulement : `stockArticlesProvider` est autoDispose,
        // un `await .future` sans watcher peut ne jamais finir (spinner infini).
        final dispo = _localStockQty(product);
        if (type == 'stock' && natureStock == 'sortie') {
          if (dispo == null) {
            setState(() {
              loading = false;
              error = ref.read(nfStringsProvider)('stockArticleMissing');
            });
            return;
          }
          if (dispo + 1e-9 < qty) {
            setState(() {
              loading = false;
              error = ref.read(nfStringsProvider).format(
                    'stockInsufficient',
                    {'n': formatQty(dispo)},
                  );
            });
            return;
          }
        } else if (type == 'vente' && dispo != null && dispo + 1e-9 < qty) {
          setState(() {
            loading = false;
            error = ref.read(nfStringsProvider).format(
                  'stockInsufficient',
                  {'n': formatQty(dispo)},
                );
          });
          return;
        }
      }
    }

    if (amount <= 0) {
      setState(() {
        loading = false;
        error = type == 'vente' || type == 'stock'
            ? 'Indiquez la quantité et le prix unitaire'
            : 'Indiquez un montant';
      });
      return;
    }
    final mutationId = OfflineQueue.newId();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final venteStockId =
        type == 'vente' && product.isNotEmpty ? _localStockArticleId(product) : null;
    final linkedStockId = isUuid(venteStockId) ? venteStockId!.trim() : null;
    final payload = <String, dynamic>{
      'type': type,
      'amountFcfa': amount,
      if (type == 'vente') ...{
        'label': _saleLabel(),
        if (product.isNotEmpty) 'productName': product,
        'quantity': jsonQty(qty),
        'articleStockId': ?linkedStockId,
        'unite': saleUnite,
      },
      if (type == 'stock') ...{
        'label':
            '${natureStock == 'sortie' ? 'Sortie' : 'Entrée'} · $product · ${formatQty(qty)} × $unit',
        'natureStock': natureStock,
        'productName': product,
        'quantiteStock': jsonQty(qty),
        'unite': saleUnite,
      },
      if (type == 'depense') ...{
        'label': _expenseLabel(),
        'categorieDepense': expenseCategory,
      },
      if (type == 'creance') ...{
        if (selectedClientId != null &&
            !selectedClientId!.startsWith('local-'))
          'clientId': selectedClientId
        else
          'clientName':
              clientCtrl.text.trim().isEmpty ? 'Client' : clientCtrl.text.trim(),
        'dueAt': dueDate.toUtc().toIso8601String(),
      },
      if (type == 'vente' || type == 'depense') 'canal': canal,
      'clientMutationId': mutationId,
      'createdAt': createdAt,
    };

    try {
      await ref.read(apiClientProvider).post('/operations', data: payload);
      if (type == 'vente' && product.isNotEmpty) {
        await rememberSaleProduct(
          ref.read(localCacheProvider),
          nom: product,
          unitPriceFcfa: _parseInt(unitPriceCtrl),
          qty: qty,
          canal: canal,
          soldAt: createdAt,
        );
      }
      // Notifie les autres écrans (accueil, cahier, créances, stock) de se recharger.
      bumpStateProvider(ref.read(ledgerRevisionProvider.notifier));
      if (type == 'stock' || venteStockId != null) {
        bumpStateProvider(ref.read(stockRevisionProvider.notifier));
      }
      setState(() {
        savedOffline = false;
        done = true;
      });
      _loadRecentProducts();
      unawaited(_speakRecordSuccess());
    } on ApiException catch (e) {
      final code = (e.body is Map) ? (e.body as Map)['error']?.toString() : null;
      if (code == 'stock_missing' || code == 'stock_insufficient') {
        setState(() {
          loading = false;
          error = e.message;
        });
        return;
      }
      if (e.isOffline || e.isServerError) {
        if ((type == 'stock' && natureStock == 'sortie') ||
            (type == 'vente' && venteStockId != null)) {
          // Pas d'optimistic hors ligne : risque de stock fantôme / double décrément.
          setState(() {
            loading = false;
            error = ref.read(nfStringsProvider)('stockOutNeedsNetwork');
          });
          return;
        }
        await ref.read(offlineQueueProvider).enqueue(
              QueuedMutation(
                clientMutationId: mutationId,
                kind: 'create_operation',
                payload: payload,
                createdAt: createdAt,
              ),
            );
        // Cache optimiste : l'opération apparaît tout de suite dans le cahier.
        final optimistic = <String, dynamic>{
          'id': mutationId,
          'type': type,
          'amountFcfa': amount,
          'montantFcfa': amount,
          'label': payload['label'] ?? type,
          'createdAt': createdAt,
          'dateOperation': createdAt,
          'pendingSync': true,
          if (type == 'vente') ...{
            'productName': product,
            'quantity': jsonQty(qty),
          },
          if (type == 'depense') ...{
            'categorieDepense': expenseCategory,
          },
          if (type == 'creance') ...{
            'clientName': payload['clientName'],
            'dueAt': payload['dueAt'],
            'statutCreance': 'ouverte',
          },
        };
        await ref.read(localCacheProvider).mergeListById(
              LocalCacheKeys.operations,
              [optimistic],
            );
        if (type == 'vente' && product.isNotEmpty) {
          await rememberSaleProduct(
            ref.read(localCacheProvider),
            nom: product,
            unitPriceFcfa: _parseInt(unitPriceCtrl),
            qty: qty,
            canal: canal,
            soldAt: createdAt,
          );
        }
        if (type == 'creance' &&
            selectedClientId == null &&
            clientCtrl.text.trim().isNotEmpty) {
          final clientId = 'local-${mutationId.substring(0, 8)}';
          await ref.read(localCacheProvider).mergeListById(
                LocalCacheKeys.clients,
                [
                  {
                    'id': clientId,
                    'nom': clientCtrl.text.trim(),
                    if (payload['telephone'] != null)
                      'telephone': payload['telephone'],
                  },
                ],
              );
        }
        await ref.read(syncServiceProvider).refreshCount();
        bumpStateProvider(ref.read(ledgerRevisionProvider.notifier));
        setState(() {
          savedOffline = true;
          done = true;
        });
        unawaited(_speakRecordSuccess());
      } else {
        setState(() => error = e.message);
      }
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (done) {
      final t = ref.watch(nfStringsProvider);
      return Scaffold(
        appBar: AppBar(
          leading: nfBackButton(context, fallbackLocation: '/app'),
          title: const Text('Enregistré'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.check_circle, size: 72, color: NfTokens.ok),
              const SizedBox(height: 12),
              Text(
                savedOffline
                    ? 'Enregistré hors ligne — synchronisation au retour du réseau'
                    : 'Synchronisé',
                style: TextStyle(color: NfTokens.textMute),
              ),
              const Spacer(),
              if (type == 'vente' && productCtrl.text.trim().isNotEmpty) ...[
                NfPrimaryButton(
                  label: t('sellAgain'),
                  onPressed: () {
                    setState(() {
                      done = false;
                      error = null;
                      qtyCtrl.text = '1';
                      _recalcSaleTotal();
                    });
                  },
                ),
                const SizedBox(height: 10),
              ],
              NfPrimaryButton(
                label: 'Accueil',
                onPressed: () => context.go('/app'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  done = false;
                  amountCtrl.clear();
                  productCtrl.clear();
                  qtyCtrl.text = '1';
                  unitPriceCtrl.clear();
                  clientCtrl.clear();
                  selectedClientId = null;
                  expenseCategory = 'autre';
                  error = null;
                }),
                child: const Text('Nouvelle opération'),
              ),
            ],
          ),
        ),
      );
    }

    final t = ref.watch(nfStringsProvider);
    final iconMode = ref.watch(uxPrefsProvider).iconMode;

    return Scaffold(
      appBar: AppBar(
        leading: nfBackButton(context, fallbackLocation: '/app'),
        title: Text(t('record')),
        actions: [
          NfSpeakButton(
            text:
                '${t('record')}. ${t(_typeKey)}. ${t('amount')}.',
            alwaysShow: true,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Mode simple : icônes seules. Mode classique : segments texte.
          if (iconMode)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _TypeIcon(
                  icon: Icons.point_of_sale,
                  selected: type == 'vente',
                  onTap: () => _setType('vente'),
                  label: t('sale'),
                  large: true,
                ),
                _TypeIcon(
                  icon: Icons.handshake_outlined,
                  selected: type == 'creance',
                  onTap: () => _setType('creance'),
                  label: t('receivable'),
                  large: true,
                ),
                _TypeIcon(
                  icon: Icons.inventory_2_outlined,
                  selected: type == 'stock',
                  onTap: () => _setType('stock'),
                  label: t('stock'),
                  large: true,
                ),
                _TypeIcon(
                  icon: Icons.money_off_outlined,
                  selected: type == 'depense',
                  onTap: () => _setType('depense'),
                  label: t('expense'),
                  large: true,
                ),
              ],
            )
          else
            NfSegmented(
              value: type,
              onChanged: _setType,
              options: [
                ('vente', t('sale')),
                ('stock', t('stock')),
                ('creance', t('receivable')),
                ('depense', t('expense')),
              ],
            ),
          const SizedBox(height: 16),
          if (kVoiceInputEnabled) ...[
            // Saisie guidée à la voix.
            Material(
              color: NfTokens.brand.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: listening || loading ? null : _voiceGuidedFlow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 18,
                    horizontal: 16,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        listening ? Icons.mic : Icons.record_voice_over,
                        size: iconMode ? 36 : 28,
                        color: NfTokens.brandSoft,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _voiceGuideBanner(t),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: iconMode ? 18 : 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (kVoiceInputEnabled && pendingConfirmAmount != null) ...[
            const SizedBox(height: 16),
            Text(
              t.format(
                'confirmAmount',
                {'n': formatFcfa(pendingConfirmAmount!)},
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: iconMode ? 22 : 18,
                fontWeight: FontWeight.w800,
                color: NfTokens.brandSoft,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 68,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: NfTokens.ok,
                        foregroundColor: NfTokens.onBrand,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: loading
                          ? null
                          : () => _resolveVoiceConfirm(true),
                      child: Text(
                        t('yes'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 68,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: NfTokens.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: loading
                          ? null
                          : () => _resolveVoiceConfirm(false),
                      child: Text(
                        t('no'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (kVoiceInputEnabled &&
              (guidePhase == _VoiceGuidePhase.pickProduct ||
                  guidePhase == _VoiceGuidePhase.pickClient ||
                  guidePhase == _VoiceGuidePhase.pickStockNature ||
                  guidePhase == _VoiceGuidePhase.pickExpenseCategory)) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: NfTokens.sand.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NfTokens.sand, width: 2),
              ),
              child: Column(
                children: [
                  Text(
                    guidePhase == _VoiceGuidePhase.pickProduct
                        ? t('chooseProduct')
                        : guidePhase == _VoiceGuidePhase.pickClient
                            ? t('chooseClient')
                            : guidePhase == _VoiceGuidePhase.pickStockNature
                                ? t('chooseStockNature')
                                : t('chooseCategory'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _completeGuidePick,
                    child: Text(t('skipChoice')),
                  ),
                ],
              ),
            ),
          ],
          if (type == 'creance') ...[
            const SizedBox(height: 16),
            _ClientField(
              selectedClientId: selectedClientId,
              fallbackCtrl: clientCtrl,
              label: t('client'),
              onSelected: (id) {
                setState(() => selectedClientId = id);
                _completeGuidePick();
              },
              onCreate: _createClient,
            ),
            if (!iconMode) ...[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('dueDate')),
                subtitle: Text(
                  DateFormat.yMMMd('fr').format(dueDate),
                  style: TextStyle(color: NfTokens.textMute),
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: dueDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  );
                  if (picked != null) setState(() => dueDate = picked);
                },
              ),
            ],
          ],
          if (type == 'vente') ...[
            if (recentProducts.isNotEmpty) ...[
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: guidePhase == _VoiceGuidePhase.pickProduct
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: NfTokens.sand, width: 2),
                        color: NfTokens.sand.withValues(alpha: 0.12),
                      )
                    : const BoxDecoration(),
                child: Padding(
                  padding: EdgeInsets.all(
                    guidePhase == _VoiceGuidePhase.pickProduct ? 12 : 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('myProducts'),
                        style: TextStyle(
                          color: NfTokens.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t('myProductsHint'),
                        style: TextStyle(color: NfTokens.textMute, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in recentProducts.take(8))
                            ActionChip(
                              avatar: const Icon(Icons.replay, size: 18),
                              label: Text(
                                '${p.nom} · ${NumberFormat.decimalPattern('fr').format(p.unitPriceFcfa)}',
                              ),
                              onPressed: () => _applyProduct(p),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: productCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: t('articleName'),
                hintText: t('articleHint'),
              ),
              onChanged: (_) {
                if (guidePhase == _VoiceGuidePhase.pickProduct &&
                    productCtrl.text.trim().isNotEmpty) {
                  _completeGuidePick();
                }
              },
            ),
            const SizedBox(height: 14),
            Text(t('chooseUnit'), style: TextStyle(color: NfTokens.textMute)),
            const SizedBox(height: 6),
            NfUnitChips(
              value: saleUnite,
              onChanged: (u) => setState(() => saleUnite = u),
            ),
            const SizedBox(height: 16),
            NfQtyStepper(
              label: t('quantity'),
              unitLabel: unitLabelOf(saleUnite, t),
              step: qtyStepForUnit(saleUnite),
              controller: qtyCtrl,
              onBump: _bumpQty,
              onChanged: _recalcSaleTotal,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: unitPriceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: unitPriceLabelOf(saleUnite, t),
                suffixText: 'FCFA',
              ),
              onChanged: (_) => _recalcSaleTotal(),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: NfTokens.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: NfTokens.brand.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('totalCollected'),
                    style: TextStyle(
                      color: NfTokens.textMute,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _parseInt(amountCtrl) > 0
                        ? '${NumberFormat.decimalPattern('fr').format(_parseInt(amountCtrl))} FCFA'
                        : '—',
                    style: TextStyle(
                      color: NfTokens.brandSoft,
                      fontWeight: FontWeight.w800,
                      fontSize: iconMode ? 28 : 24,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(t('payment'), style: TextStyle(color: NfTokens.textMute)),
            const SizedBox(height: 8),
            NfSegmented(
              value: canal,
              onChanged: (v) => setState(() => canal = v),
              options: [
                ('especes', t('cash')),
                ('mobile_money', t('mobileMoney')),
              ],
            ),
          ],
          if (type == 'stock') ...[
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: guidePhase == _VoiceGuidePhase.pickStockNature
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: NfTokens.sand, width: 2),
                      color: NfTokens.sand.withValues(alpha: 0.12),
                    )
                  : const BoxDecoration(),
              child: Padding(
                padding: EdgeInsets.all(
                  guidePhase == _VoiceGuidePhase.pickStockNature ? 10 : 0,
                ),
                child: NfSegmented(
                  value: natureStock,
                  onChanged: (v) {
                    setState(() => natureStock = v);
                    if (guidePhase == _VoiceGuidePhase.pickStockNature) {
                      _completeGuidePick();
                    }
                  },
                  options: [
                    ('entree', t('stockIn')),
                    ('sortie', t('stockOut')),
                  ],
                ),
              ),
            ),
            if (natureStock == 'sortie') ...[
              const SizedBox(height: 8),
              Text(
                t('stockOutHint'),
                style: TextStyle(color: NfTokens.warn, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final stockItems = ref
                    .read(localCacheProvider)
                    .getList(LocalCacheKeys.stock);
                if (stockItems.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DecoratedBox(
                    decoration: guidePhase == _VoiceGuidePhase.pickProduct
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: NfTokens.sand, width: 2),
                            color: NfTokens.sand.withValues(alpha: 0.12),
                          )
                        : const BoxDecoration(),
                    child: Padding(
                      padding: EdgeInsets.all(
                        guidePhase == _VoiceGuidePhase.pickProduct ? 10 : 0,
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final raw in stockItems.take(10))
                            ActionChip(
                              avatar: const Icon(Icons.inventory_2_outlined,
                                  size: 18),
                              label: Text(
                                '${raw['nom']} · ${formatQty(asQty(raw['quantite']))} ${unitLabelOf(raw['unite']?.toString() ?? 'u', t)}',
                              ),
                              onPressed: () {
                                setState(() {
                                  productCtrl.text =
                                      raw['nom']?.toString() ?? '';
                                  saleUnite = normalizeUnite(
                                    raw['unite']?.toString(),
                                  );
                                  if (raw['prixUnitaireFcfa'] != null) {
                                    unitPriceCtrl.text =
                                        '${asFcfaInt(raw['prixUnitaireFcfa'])}';
                                    _recalcSaleTotal();
                                  }
                                });
                                _completeGuidePick();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            TextField(
              controller: productCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: t('articleName'),
                hintText: t('articleHint'),
              ),
              onChanged: (_) {
                if (guidePhase == _VoiceGuidePhase.pickProduct &&
                    productCtrl.text.trim().isNotEmpty) {
                  _completeGuidePick();
                }
              },
            ),
            const SizedBox(height: 12),
            Text(t('chooseUnit'), style: TextStyle(color: NfTokens.textMute)),
            const SizedBox(height: 6),
            NfUnitChips(
              value: saleUnite,
              onChanged: (u) => setState(() => saleUnite = u),
            ),
            const SizedBox(height: 12),
            NfQtyStepper(
              label: t('quantity'),
              unitLabel: unitLabelOf(saleUnite, t),
              step: qtyStepForUnit(saleUnite),
              controller: qtyCtrl,
              onBump: _bumpQty,
              onChanged: _recalcSaleTotal,
            ),
            const SizedBox(height: 12),
            NfKeypadAmountField(
              controller: unitPriceCtrl,
              label: unitPriceLabelOf(saleUnite, t),
            ),
            const SizedBox(height: 10),
            Text(
              '${t('stockValue')} · ${NumberFormat.decimalPattern('fr').format(_parseInt(amountCtrl))} FCFA',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
          if (type == 'depense') ...[
            const SizedBox(height: 20),
            TextField(
              controller: productCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: t('expenseMotif'),
                hintText: t('expenseHint'),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              t('expenseCategory'),
              style: TextStyle(color: NfTokens.textMute, fontSize: 13),
            ),
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: guidePhase == _VoiceGuidePhase.pickExpenseCategory
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: NfTokens.sand, width: 2),
                      color: NfTokens.sand.withValues(alpha: 0.12),
                    )
                  : const BoxDecoration(),
              child: Padding(
                padding: EdgeInsets.all(
                  guidePhase == _VoiceGuidePhase.pickExpenseCategory ? 10 : 0,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final cat in _expenseCategories)
                      FilterChip(
                        selected: expenseCategory == cat.$1,
                        avatar: Icon(cat.$3, size: 18),
                        label: Text(cat.$2),
                        onSelected: (_) {
                          setState(() => expenseCategory = cat.$1);
                          if (guidePhase ==
                              _VoiceGuidePhase.pickExpenseCategory) {
                            _completeGuidePick();
                          }
                        },
                        selectedColor: NfTokens.brand.withValues(alpha: 0.22),
                        checkmarkColor: NfTokens.brand,
                        side: BorderSide(
                          color: expenseCategory == cat.$1
                              ? NfTokens.brand
                              : NfTokens.line,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(t('payment'), style: TextStyle(color: NfTokens.textMute)),
            const SizedBox(height: 8),
            NfSegmented(
              value: canal,
              onChanged: (v) => setState(() => canal = v),
              options: [
                ('especes', t('cash')),
                ('mobile_money', t('mobileMoney')),
              ],
            ),
          ],
          if (type != 'vente' && type != 'stock') ...[
            const SizedBox(height: 16),
            NfKeypadAmountField(
              controller: amountCtrl,
              label: type == 'depense' ? t('expenseAmount') : t('amount'),
              trailing: kVoiceInputEnabled
                  ? IconButton(
                      tooltip: t('dictAmount'),
                      onPressed: listening ? null : _dictateAmount,
                      icon: Icon(
                        listening ? Icons.mic : Icons.mic_none,
                        color: listening ? NfTokens.brand : NfTokens.textMute,
                      ),
                    )
                  : null,
            ),
          ] else if (kVoiceInputEnabled) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: listening ? null : _dictateAmount,
                icon: Icon(
                  listening ? Icons.mic : Icons.mic_none,
                  size: 20,
                ),
                label: Text(t('dictUnitPrice')),
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: NfTokens.danger)),
          ],
          const SizedBox(height: 20),
          if (pendingConfirmAmount == null)
            NfPrimaryButton(
              label: t('confirm'),
              loading: loading,
              onPressed: _submit,
            ),
        ],
      ),
    );
  }
}

/// Sélecteur de client pour une créance : liste déroulante des clients
/// existants + option « Nouveau client ». Repli sur un champ texte libre
/// si l'API est injoignable (mode hors-ligne).
class _ClientField extends ConsumerWidget {
  const _ClientField({
    required this.selectedClientId,
    required this.fallbackCtrl,
    required this.label,
    required this.onSelected,
    required this.onCreate,
  });

  final String? selectedClientId;
  final TextEditingController fallbackCtrl;
  final String label;
  final ValueChanged<String?> onSelected;
  final Future<void> Function() onCreate;

  static const _newValue = '__new__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientsAsync = ref.watch(clientsProvider);
    return clientsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (_, _) => TextField(
        controller: fallbackCtrl,
        decoration: InputDecoration(
          labelText: label,
          helperText: ref.watch(nfStringsProvider)('offlineCache'),
        ),
      ),
      data: (clients) {
        final t = ref.watch(nfStringsProvider);
        final valid = clients.any((c) => c.id == selectedClientId)
            ? selectedClientId
            : null;
        return DropdownButtonFormField<String>(
          initialValue: valid,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          hint: Text(t('chooseClient')),
          items: [
            ...clients.map(
              (c) => DropdownMenuItem(value: c.id, child: Text(c.nom)),
            ),
            DropdownMenuItem(
              value: _newValue,
              child: Row(
                children: [
                  const Icon(Icons.add, size: 18),
                  const SizedBox(width: 8),
                  Text(t('newClient')),
                ],
              ),
            ),
          ],
          onChanged: (v) {
            if (v == _newValue) {
              onCreate();
            } else {
              onSelected(v);
            }
          },
        );
      },
    );
  }
}

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.label,
    this.large = false,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String label;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 80.0 : 72.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: size,
        padding: EdgeInsets.symmetric(vertical: large ? 14 : 12),
        decoration: BoxDecoration(
          color: selected
              ? NfTokens.brand.withValues(alpha: 0.2)
              : NfTokens.elevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? NfTokens.brand : NfTokens.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: large ? 36 : 32, color: NfTokens.brandSoft),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: large ? 12 : 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VentesPage extends ConsumerStatefulWidget {
  const VentesPage({super.key, this.initialTab = 'vente'});

  /// `vente` | `depense`
  final String initialTab;

  @override
  ConsumerState<VentesPage> createState() => _VentesPageState();
}

class _VentesPageState extends ConsumerState<VentesPage> {
  late String tab;
  List<Map<String, dynamic>> ops = [];
  List<SaleProduct> products = [];
  bool fromCache = false;
  String? busyId;
  ProviderSubscription<int>? _revisionSub;

  @override
  void initState() {
    super.initState();
    tab = widget.initialTab == 'depense' ? 'depense' : 'vente';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
      if (ref.read(uxPrefsProvider).voiceAssist) {
        ref.read(voiceServiceProvider).speakKey('ledger');
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

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final list = await ref.read(apiClientProvider).get<List>(
            '/operations?type=$tab',
            parse: (d) => d as List,
          );
      final mapped =
          list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      final cache = ref.read(localCacheProvider);
      await cache.mergeListById(LocalCacheKeys.operations, mapped);
      if (tab == 'vente') {
        await hydrateSaleProductsFromOps(cache, mapped);
      }
      if (!mounted) return;
      setState(() {
        ops = mapped;
        products = loadSaleProducts(cache);
        fromCache = false;
      });
    } catch (_) {
      if (!mounted) return;
      final cache = ref.read(localCacheProvider);
      final cached = cache
          .getList(LocalCacheKeys.operations)
          .where((o) => o['type']?.toString() == tab)
          .toList();
      if (tab == 'vente') {
        await hydrateSaleProductsFromOps(cache, cached);
      }
      if (!mounted) return;
      setState(() {
        ops = cached;
        products = loadSaleProducts(cache);
        fromCache = true;
      });
    }
  }

  Future<void> _setTab(String next) async {
    if (next == tab) return;
    setState(() {
      tab = next;
      ops = [];
    });
    await _load();
  }

  Future<void> _deleteOp(Map<String, dynamic> op) async {
    final id = op['id']?.toString();
    if (id == null || id.isEmpty) return;
    final ok = await showNfDeleteConfirm(
      context,
      ref,
      label: op['label']?.toString() ??
          (tab == 'depense'
              ? ref.read(nfStringsProvider)('expense')
              : ref.read(nfStringsProvider)('sale')),
      amountFcfa: asFcfaInt(op['amountFcfa']),
      isExpense: tab == 'depense',
    );
    if (ok != true || !mounted) return;

    setState(() => busyId = id);
    final touchesStock = tab == 'vente' &&
        (op['articleStockId'] != null ||
            (op['productName'] ?? op['articleName']) != null);

    Future<void> removeLocal() async {
      final cache = ref.read(localCacheProvider);
      final next = cache
          .getList(LocalCacheKeys.operations)
          .where((o) => o['id']?.toString() != id)
          .toList();
      await cache.putList(LocalCacheKeys.operations, next);
      setState(() => ops = ops.where((o) => o['id']?.toString() != id).toList());
      bumpStateProvider(ref.read(ledgerRevisionProvider.notifier));
      if (touchesStock) {
        bumpStateProvider(ref.read(stockRevisionProvider.notifier));
      }
    }

    // Opération encore locale (pas sync) : retire du cache + file.
    final pending = op['pendingSync'] == true;
    if (pending) {
      try {
        await ref.read(offlineQueueProvider).discard(id);
      } catch (_) {}
      await removeLocal();
      if (mounted) setState(() => busyId = null);
      return;
    }

    try {
      await ref.read(apiClientProvider).delete('/operations/$id');
      await removeLocal();
    } on ApiException catch (e) {
      if (e.isOffline || e.isServerError) {
        final mutationId = OfflineQueue.newId();
        final createdAt = DateTime.now().toUtc().toIso8601String();
        await ref.read(offlineQueueProvider).enqueue(
              QueuedMutation(
                clientMutationId: mutationId,
                kind: 'delete_operation',
                payload: {'operationId': id},
                createdAt: createdAt,
              ),
            );
        await removeLocal();
        await ref.read(syncServiceProvider).refreshCount();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.decimalPattern('fr');
    final t = ref.watch(nfStringsProvider);
    final iconMode = ref.watch(uxPrefsProvider).iconMode;
    final isExpense = tab == 'depense';
    final total = ops.fold<int>(0, (s, o) => s + asFcfaInt(o['amountFcfa']));
    return Scaffold(
      appBar: AppBar(
        title: Text(t('ledger')),
        actions: [
          const NfSpeakButton(labelKey: 'ledger', alwaysShow: true),
          if (!iconMode)
            IconButton(
              onPressed: () => context.push('/app/enregistrer'),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            NfSegmented(
              value: tab,
              onChanged: _setTab,
              options: [
                ('vente', t('sale')),
                ('depense', t('expense')),
              ],
            ),
            const SizedBox(height: 16),
            if (iconMode) ...[
              Material(
                color: NfTokens.brand,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => context.push('/app/enregistrer'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        const Icon(Icons.add_circle_outline,
                            size: 40, color: NfTokens.onBrand),
                        const SizedBox(height: 8),
                        Text(
                          isExpense ? t('recordExpense') : t('recordSale'),
                          style: const TextStyle(
                            color: NfTokens.onBrand,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (fromCache)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  ops.isEmpty ? t('offlineCanRecord') : t('offlineCache'),
                  style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                ),
              ),
            Text(
              '${fmt.format(total)} FCFA',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: isExpense ? NfTokens.warn : NfTokens.brandSoft,
                    fontWeight: FontWeight.w800,
                    fontSize: iconMode ? 32 : null,
                  ),
            ),
            if (!isExpense) ...[
              const SizedBox(height: 18),
              Material(
                color: NfTokens.elevated,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => context.push('/app/produits'),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: NfTokens.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: NfTokens.brand.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
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
                                    t('myProducts'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: iconMode ? 18 : 16,
                                    ),
                                  ),
                                  Text(
                                    products.isEmpty
                                        ? t('noProductsYet')
                                        : t.format(
                                            'productsCount',
                                            {'n': '${products.length}'},
                                          ),
                                    style: TextStyle(
                                      color: NfTokens.textMute,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: NfTokens.textMute,
                              size: iconMode ? 28 : 24,
                            ),
                          ],
                        ),
                        if (products.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          ...products.take(3).map((p) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.nom,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${fmt.format(p.unitPriceFcfa)} FCFA',
                                    style: TextStyle(
                                      color: NfTokens.brandSoft,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 4),
                          Text(
                            t('seeAllProducts'),
                            style: TextStyle(
                              color: NfTokens.brandSoft,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              t('lastOps'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: iconMode ? 18 : 16,
              ),
            ),
            const SizedBox(height: 8),
            if (ops.isEmpty) ...[
              Text(
                isExpense ? t('noExpenses') : t('noSales'),
                style: TextStyle(color: NfTokens.textMute),
              ),
              if (!iconMode) ...[
                const SizedBox(height: 12),
                NfPrimaryButton(
                  label: isExpense ? t('recordExpense') : t('recordSale'),
                  onPressed: () => context.push('/app/enregistrer'),
                ),
              ],
            ] else
              ...ops.map((op) {
                final id = op['id']?.toString() ?? '';
                final amount = asFcfaInt(op['amountFcfa']);
                final label = op['label']?.toString() ??
                    (isExpense ? t('expense') : t('sale'));
                final speakLine =
                    '$label. ${isExpense ? '-' : '+'}${fmt.format(amount)} FCFA';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(label),
                  subtitle: Text(
                    [
                      if (!isExpense &&
                          (op['quantity'] ?? op['quantiteStock']) != null)
                        '${t('quantity')} · ${formatQty(asQty(op['quantity'] ?? op['quantiteStock']))}',
                      if (isExpense && op['categorieDepense'] != null)
                        op['categorieDepense'].toString(),
                      op['dateOperation']?.toString() ??
                          op['createdAt']?.toString() ??
                          '',
                    ].where((e) => e.toString().isNotEmpty).join(' · '),
                    style: TextStyle(color: NfTokens.textMute, fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: t('listen'),
                        onPressed: () => ref
                            .read(voiceServiceProvider)
                            .speakText(speakLine),
                        icon: Icon(
                          Icons.volume_up_outlined,
                          color: NfTokens.brandSoft,
                          size: iconMode ? 28 : 24,
                        ),
                      ),
                      Text(
                        '${isExpense ? '-' : '+'}${fmt.format(amount)}',
                        style: TextStyle(
                          color: isExpense ? NfTokens.warn : NfTokens.ok,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        tooltip: t('deleteOp'),
                        onPressed:
                            busyId == id ? null : () => _deleteOp(op),
                        icon: busyId == id
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                Icons.delete_outline,
                                color: NfTokens.textMute,
                                size: iconMode ? 26 : 22,
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

class DettesPage extends ConsumerStatefulWidget {
  const DettesPage({super.key});

  @override
  ConsumerState<DettesPage> createState() => _DettesPageState();
}

class _DettesPageState extends ConsumerState<DettesPage> {
  List<Map<String, dynamic>> ops = [];
  String? busyId;
  bool fromCache = false;

  ProviderSubscription<int>? _revisionSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
      if (ref.read(uxPrefsProvider).voiceAssist) {
        ref.read(voiceServiceProvider).speakKey('debts');
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

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final list = await ref.read(apiClientProvider).get<List>(
            '/operations?type=creance',
            parse: (d) => d as List,
          );
      final mapped = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((o) {
            final s = o['statutCreance']?.toString();
            return s == null || s == 'ouverte' || s == 'en_retard';
          })
          .toList();
      if (!mounted) return;
      await ref.read(localCacheProvider).putList(
            LocalCacheKeys.operations,
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          );
      if (!mounted) return;
      setState(() {
        ops = mapped;
        fromCache = false;
      });
    } catch (_) {
      if (!mounted) return;
      final cached = ref
          .read(localCacheProvider)
          .getList(LocalCacheKeys.operations)
          .where((o) {
            if (o['type']?.toString() != 'creance') return false;
            final s = o['statutCreance']?.toString();
            return s == null || s == 'ouverte' || s == 'en_retard';
          })
          .toList();
      if (!mounted) return;
      setState(() {
        ops = cached;
        fromCache = true;
      });
    }
  }

  int _remaining(Map<String, dynamic> op) {
    final remaining = asFcfaInt(op['remainingFcfa']);
    if (op['remainingFcfa'] != null) return remaining < 0 ? 0 : remaining;
    final total = asFcfaInt(op['amountFcfa']) -
        asFcfaInt(op['montantRegleFcfa'] ?? op['amountSettledFcfa']);
    return total < 0 ? 0 : total;
  }

  Future<void> _settle(String id, {int? amountFcfa}) async {
    setState(() => busyId = id);
    final mutationId = OfflineQueue.newId();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'operationId': id,
      'amountFcfa': ?amountFcfa,
    };
    try {
      await ref.read(apiClientProvider).post(
            '/operations/$id/settle',
            data: {'amountFcfa': ?amountFcfa},
          );
      bumpStateProvider(ref.read(ledgerRevisionProvider.notifier));
      await _load();
    } on ApiException catch (e) {
      if (e.isOffline || e.isServerError) {
        await ref.read(offlineQueueProvider).enqueue(
              QueuedMutation(
                clientMutationId: mutationId,
                kind: 'settle_creance',
                payload: payload,
                createdAt: createdAt,
              ),
            );
        await ref.read(syncServiceProvider).refreshCount();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ref.read(nfStringsProvider)('savedOffline'))),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  Future<void> _settlePartial(Map<String, dynamic> op) async {
    final id = op['id']?.toString() ?? '';
    final reste = _remaining(op);
    final ctrl = TextEditingController(text: '$reste');
    final t = ref.read(nfStringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('settlePartial')),
        content: SingleChildScrollView(
          child: NfKeypadAmountField(controller: ctrl, label: t('amount')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('deny')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('confirm')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final amount = int.tryParse(ctrl.text.replaceAll(RegExp(r'\s'), '')) ?? 0;
    if (amount <= 0) return;
    await _settle(id, amountFcfa: amount);
  }

  Future<void> _remind(String id) async {
    setState(() => busyId = id);
    final t = ref.read(nfStringsProvider);
    try {
      await ref.read(apiClientProvider).post('/operations/$id/remind');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('reminderSent'))),
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  Future<void> _changeDue(Map<String, dynamic> op) async {
    final id = op['id']?.toString() ?? '';
    final current = DateTime.tryParse(op['dueAt']?.toString() ?? '') ??
        DateTime.now().add(const Duration(days: 7));
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(DateTime.now()) ? DateTime.now() : current,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() => busyId = id);
    try {
      await ref.read(apiClientProvider).patch(
            '/operations/$id/due',
            data: {'dueAt': picked.toUtc().toIso8601String()},
          );
      bumpStateProvider(ref.read(ledgerRevisionProvider.notifier));
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.decimalPattern('fr');
    final t = ref.watch(nfStringsProvider);
    final iconMode = ref.watch(uxPrefsProvider).iconMode;
    final total = ops.fold<int>(0, (s, o) => s + _remaining(o));
    return Scaffold(
      appBar: AppBar(
        title: Text(t('debts')),
        actions: const [NfSpeakButton(labelKey: 'debts', alwaysShow: true)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${t('toCollect')} · ${fmt.format(total)} FCFA',
              style: TextStyle(color: NfTokens.warn, fontWeight: FontWeight.w700),
            ),
            if (fromCache)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  t('offlineCache'),
                  style: TextStyle(color: NfTokens.textMute, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            if (ops.isEmpty) ...[
              Text(
                fromCache ? t('offlineCanRecord') : t('noOpenDebts'),
                style: TextStyle(color: NfTokens.textMute),
              ),
              const SizedBox(height: 12),
              NfPrimaryButton(
                label: t('recordDebt'),
                onPressed: () => context.push('/app/enregistrer'),
              ),
            ] else
              ...ops.map((op) {
                final id = op['id']?.toString() ?? '';
                final reste = _remaining(op);
                final overdue = op['statutCreance']?.toString() == 'en_retard';
                final due = op['dueAt']?.toString();
                final dueLabel = (due != null && due.length >= 10)
                    ? due.substring(0, 10)
                    : null;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                op['clientName']?.toString() ?? t('client'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: t('listen'),
                              onPressed: () {
                                final name =
                                    op['clientName']?.toString() ?? t('client');
                                ref.read(voiceServiceProvider).speakText(
                                      '$name. ${fmt.format(reste)} FCFA. ${overdue ? t('overdue') : t('openDebt')}',
                                    );
                              },
                              icon: Icon(
                                Icons.volume_up_outlined,
                                color: NfTokens.brandSoft,
                                size: iconMode ? 28 : 24,
                              ),
                            ),
                            Text(
                              '${fmt.format(reste)} FCFA',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          overdue
                              ? t('overdue')
                              : (dueLabel != null
                                  ? '${t('dueDate')} · $dueLabel'
                                  : t('openDebt')),
                          style: TextStyle(
                            color: overdue ? NfTokens.danger : NfTokens.textMute,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (iconMode)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed:
                                  busyId == id ? null : () => _settle(id),
                              child: Text(
                                busyId == id ? '…' : t('payDebt'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 4,
                            children: [
                              TextButton(
                                onPressed:
                                    busyId == id ? null : () => _settle(id),
                                child: Text(
                                  busyId == id ? '…' : t('payDebt'),
                                ),
                              ),
                              TextButton(
                                onPressed: busyId == id
                                    ? null
                                    : () => _settlePartial(op),
                                child: Text(t('settlePartial')),
                              ),
                              TextButton(
                                onPressed:
                                    busyId == id ? null : () => _remind(id),
                                child: Text(t('remind')),
                              ),
                              TextButton(
                                onPressed: busyId == id
                                    ? null
                                    : () => _changeDue(op),
                                child: Text(t('dueDate')),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
