import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/locale_provider.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../utils/qty.dart';

/// Pièce, ou une mesure au choix (kg, g, l).
class NfUnitChips extends ConsumerWidget {
  const NfUnitChips({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  static const measureUnits = ['kg', 'g', 'l'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(nfStringsProvider);
    final unit = normalizeUnite(value);
    final isPiece = unit == 'u';
    final measure = measureUnits.contains(unit) ? unit : null;

    return Row(
      children: [
        ChoiceChip(
          label: Text(t('unitPiece')),
          selected: isPiece,
          onSelected: (_) => onChanged('u'),
          selectedColor: NfTokens.brand.withValues(alpha: 0.22),
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            color: isPiece ? NfTokens.brand : NfTokens.text,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(measure ?? 'none'),
            initialValue: measure,
            isExpanded: true,
            hint: Text(
              t('unitMeasureHint'),
              style: TextStyle(
                color: NfTokens.textMute,
                fontWeight: FontWeight.w700,
              ),
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: measure != null,
              fillColor: measure != null
                  ? NfTokens.brand.withValues(alpha: 0.22)
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            items: [
              for (final u in measureUnits)
                DropdownMenuItem(
                  value: u,
                  child: Text(
                    unitLabelOf(u, t),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

String unitLabelOf(String unite, NfStrings t) {
  switch (normalizeUnite(unite)) {
    case 'kg':
      return t('unitKg');
    case 'g':
      return t('unitG');
    case 'l':
      return t('unitL');
    default:
      return t('unitPiece');
  }
}

/// Libellé du champ prix : « Prix unitaire » (pièce) ou « Prix par kg/g/l ».
String unitPriceLabelOf(String unite, NfStrings t) {
  switch (normalizeUnite(unite)) {
    case 'kg':
      return t('pricePerKg');
    case 'g':
      return t('pricePerG');
    case 'l':
      return t('pricePerL');
    default:
      return t('unitPrice');
  }
}
