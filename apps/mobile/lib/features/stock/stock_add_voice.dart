import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/brand.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/qty.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/nf_numeric_keypad.dart';
import '../../core/widgets/nf_unit_chips.dart';

/// Résultat du dialogue « Ajouter un article » guidé à la voix.
typedef StockArticleDraft = ({
  String nom,
  String unite,
  double quantite,
  int? prixUnitaireFcfa,
});

/// Bottom sheet : nom → quantité → prix → confirmation Oui/Non (orale + visuelle).
Future<StockArticleDraft?> showVoiceGuidedAddArticle(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<StockArticleDraft>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: NfTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _VoiceAddArticleSheet(),
  );
}

class _VoiceAddArticleSheet extends ConsumerStatefulWidget {
  const _VoiceAddArticleSheet();

  @override
  ConsumerState<_VoiceAddArticleSheet> createState() =>
      _VoiceAddArticleSheetState();
}

enum _Step { name, qty, price, confirm }

class _VoiceAddArticleSheetState extends ConsumerState<_VoiceAddArticleSheet> {
  _Step step = _Step.name;
  String nom = '';
  String unite = 'u';
  String qtyDigits = '1';
  String priceDigits = '';
  bool listening = false;
  bool guiding = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && kVoiceInputEnabled) unawaited(_runGuideFromCurrent());
    });
  }

  Future<void> _runGuideFromCurrent() async {
    if (!kVoiceInputEnabled) return;
    if (guiding) return;
    if (!ref.read(uxPrefsProvider).voiceAssist) return;
    setState(() {
      guiding = true;
      error = null;
    });
    final voice = ref.read(voiceServiceProvider);
    try {
      switch (step) {
        case _Step.name:
          await voice.speakKey('addArticle');
          await voice.speakKey('askArticleName');
          await _listenName();
        case _Step.qty:
          await voice.speakKey('chooseUnit');
          await voice.speakKey('askQuantity');
          // L'utilisateur tape ou dicte ; on n'écoute pas auto pour laisser le pavé.
        case _Step.price:
          await voice.speakKey('askUnitPrice');
        case _Step.confirm:
          await _speakConfirm();
      }
    } finally {
      if (mounted) setState(() => guiding = false);
    }
  }

  Future<void> _listenName() async {
    final voice = ref.read(voiceServiceProvider);
    final t = ref.read(nfStringsProvider);
    setState(() => listening = true);
    try {
      final heard = await voice.listenOnce(
        timeout: const Duration(seconds: 6),
      );
      if (!mounted) return;
      final cleaned = heard?.trim() ?? '';
      if (cleaned.isEmpty) {
        setState(() => error = t('dictNameFail'));
        await voice.speakKey('dictNameFail');
        return;
      }
      // Capitalise simplement.
      final name = cleaned[0].toUpperCase() + cleaned.substring(1);
      setState(() {
        nom = name;
        error = null;
      });
      await voice.speakText(name);
    } finally {
      if (mounted) setState(() => listening = false);
    }
  }

  Future<void> _dictateQty() async {
    final voice = ref.read(voiceServiceProvider);
    setState(() => listening = true);
    try {
      final n = await voice.listenAmountOnce();
      if (n != null && n > 0 && mounted) {
        setState(() => qtyDigits = '$n');
      }
    } finally {
      if (mounted) setState(() => listening = false);
    }
  }

  Future<void> _dictatePrice() async {
    final voice = ref.read(voiceServiceProvider);
    setState(() => listening = true);
    try {
      final n = await voice.listenAmountOnce();
      if (n != null && n > 0 && mounted) {
        setState(() => priceDigits = '$n');
      }
    } finally {
      if (mounted) setState(() => listening = false);
    }
  }

  Future<void> _speakConfirm() async {
    final voice = ref.read(voiceServiceProvider);
    final qty = parseQty(qtyDigits);
    final price = int.tryParse(priceDigits);
    final fmt = NumberFormat.decimalPattern('fr');
    final pricePart =
        price != null && price > 0 ? '${fmt.format(price)} FCFA' : '';
    await voice.speakKey('confirmArticle');
    await voice.speakText(
      '$nom. ${formatQty(qty)} ${unitLabelOf(unite, ref.read(nfStringsProvider))}. $pricePart'
          .trim(),
    );
  }

  void _goNext() {
    final t = ref.read(nfStringsProvider);
    switch (step) {
      case _Step.name:
        if (nom.trim().isEmpty) {
          setState(() => error = t('dictNameFail'));
          return;
        }
        setState(() {
          step = _Step.qty;
          error = null;
        });
      case _Step.qty:
        final q = parseQty(qtyDigits);
        if (q <= 0) {
          setState(() => error = t('dictAmountFail'));
          return;
        }
        setState(() {
          step = _Step.price;
          error = null;
        });
      case _Step.price:
        setState(() {
          step = _Step.confirm;
          error = null;
        });
      case _Step.confirm:
        return;
    }
    unawaited(_runGuideFromCurrent());
  }

  void _goBack() {
    switch (step) {
      case _Step.name:
        Navigator.of(context).pop();
      case _Step.qty:
        setState(() => step = _Step.name);
        unawaited(_runGuideFromCurrent());
      case _Step.price:
        setState(() => step = _Step.qty);
        unawaited(_runGuideFromCurrent());
      case _Step.confirm:
        setState(() => step = _Step.price);
        unawaited(_runGuideFromCurrent());
    }
  }

  void _submit() {
    final q = parseQty(qtyDigits);
    if (nom.trim().isEmpty || q <= 0) return;
    final p = int.tryParse(priceDigits);
    Navigator.of(context).pop((
      nom: nom.trim(),
      unite: normalizeUnite(unite),
      quantite: q,
      prixUnitaireFcfa: (p != null && p > 0) ? p : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(nfStringsProvider);
    final iconMode = ref.watch(uxPrefsProvider).iconMode;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    String title;
    switch (step) {
      case _Step.name:
        title = t('askArticleName');
      case _Step.qty:
        title = t('askQuantity');
      case _Step.price:
        title = unitPriceLabelOf(unite, t);
      case _Step.confirm:
        title = t('confirmArticle');
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: NfTokens.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            t('addArticle'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: iconMode ? 22 : 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: NfTokens.brandSoft,
              fontWeight: FontWeight.w700,
              fontSize: iconMode ? 18 : 15,
            ),
          ),
          const SizedBox(height: 16),
          if (step == _Step.name) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NfTokens.elevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NfTokens.line),
              ),
              child: Text(
                nom.isEmpty ? '…' : nom,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: iconMode ? 26 : 22,
                  fontWeight: FontWeight.w800,
                  color: nom.isEmpty ? NfTokens.textMute : NfTokens.text,
                ),
              ),
            ),
            if (kVoiceInputEnabled) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton.icon(
                  onPressed: listening || guiding ? null : _listenName,
                  icon: Icon(listening ? Icons.mic : Icons.mic_none, size: 28),
                  label: Text(
                    listening ? t('askArticleName') : t('dictName'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: t('articleName'),
                hintText: t('articleHint'),
              ),
              onChanged: (v) => setState(() {
                nom = v.trim();
                error = null;
              }),
            ),
          ] else if (step == _Step.qty) ...[
            Text(
              t('chooseUnit'),
              style: TextStyle(
                color: NfTokens.textMute,
                fontWeight: FontWeight.w700,
                fontSize: iconMode ? 16 : 14,
              ),
            ),
            const SizedBox(height: 8),
            NfUnitChips(
              value: unite,
              onChanged: (u) => setState(() => unite = u),
            ),
            const SizedBox(height: 14),
            Text(
              qtyDigits.isEmpty
                  ? '0 ${unitLabelOf(unite, t)}'
                  : '$qtyDigits ${unitLabelOf(unite, t)}',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: NfTokens.brandSoft,
              ),
            ),
            if (kVoiceInputEnabled) ...[
              const SizedBox(height: 8),
              IconButton(
                onPressed: listening ? null : _dictateQty,
                icon: Icon(
                  listening ? Icons.mic : Icons.mic_none,
                  size: 32,
                  color: NfTokens.brand,
                ),
                tooltip: t('dictAmount'),
              ),
            ] else
              const SizedBox(height: 8),
            NfNumericKeypad(
              large: false,
              allowDecimal: true,
              onDigit: (d) {
                setState(() => qtyDigits = appendQtyDigit(qtyDigits, d));
              },
              onBackspace: () {
                if (qtyDigits.isEmpty) return;
                setState(() {
                  qtyDigits = qtyDigits.substring(0, qtyDigits.length - 1);
                });
              },
              onClear: () => setState(() => qtyDigits = ''),
            ),
          ] else if (step == _Step.price) ...[
            Text(
              priceDigits.isEmpty ? '0' : '$priceDigits FCFA',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: NfTokens.brandSoft,
              ),
            ),
            if (kVoiceInputEnabled) ...[
              const SizedBox(height: 8),
              IconButton(
                onPressed: listening ? null : _dictatePrice,
                icon: Icon(
                  listening ? Icons.mic : Icons.mic_none,
                  size: 32,
                  color: NfTokens.brand,
                ),
              ),
            ] else
              const SizedBox(height: 8),
            NfNumericKeypad(
              large: true,
              onDigit: (d) {
                if (priceDigits.length >= 9) return;
                setState(() => priceDigits = '$priceDigits$d');
              },
              onBackspace: () {
                if (priceDigits.isEmpty) return;
                setState(() {
                  priceDigits =
                      priceDigits.substring(0, priceDigits.length - 1);
                });
              },
              onClear: () => setState(() => priceDigits = ''),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  priceDigits = '';
                  step = _Step.confirm;
                });
                unawaited(_runGuideFromCurrent());
              },
              child: Text(t('skipChoice')),
            ),
          ] else ...[
            Text(
              nom,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${t('quantity')} · $qtyDigits ${unitLabelOf(unite, t)}',
              style: TextStyle(
                fontSize: 18,
                color: NfTokens.textMute,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (priceDigits.isNotEmpty)
              Text(
                '${unitPriceLabelOf(unite, t)} · ${NumberFormat.decimalPattern('fr').format(int.tryParse(priceDigits) ?? 0)} FCFA',
                style: TextStyle(
                  fontSize: 18,
                  color: NfTokens.textMute,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 68,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: NfTokens.ok,
                        foregroundColor: NfTokens.onBrand,
                      ),
                      onPressed: _submit,
                      child: Text(
                        t('yes'),
                        style: const TextStyle(
                          fontSize: 22,
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
                      ),
                      onPressed: () {
                        setState(() => step = _Step.name);
                        unawaited(_runGuideFromCurrent());
                      },
                      child: Text(
                        t('no'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: NfTokens.danger)),
          ],
          if (step != _Step.confirm) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(onPressed: _goBack, child: Text(t('back'))),
                const Spacer(),
                FilledButton(
                  onPressed: listening ? null : _goNext,
                  child: Text(t('next')),
                ),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }
}
