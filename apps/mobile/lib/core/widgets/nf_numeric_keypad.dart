import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Grand clavier numérique 3×4 (1-9, effacer, 0, retour) — pensé pour la
/// faible littératie : gros boutons, pas de saisie clavier système requise.
class NfNumericKeypad extends StatelessWidget {
  const NfNumericKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    this.large = false,
    this.allowDecimal = false,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  /// Boutons plus grands (PIN / OTP accessibles).
  final bool large;

  /// Virgule à la place de C (quantités 1,5 kg).
  final bool allowDecimal;

  static const _keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    'C',
    '0',
    '⌫',
  ];

  @override
  Widget build(BuildContext context) {
    final keys = allowDecimal
        ? const [
            '1',
            '2',
            '3',
            '4',
            '5',
            '6',
            '7',
            '8',
            '9',
            ',',
            '0',
            '⌫',
          ]
        : _keys;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: large ? 12 : 10,
      crossAxisSpacing: large ? 12 : 10,
      childAspectRatio: large ? 1.35 : 1.7,
      children: keys.map((k) {
        final isAction = k == 'C' || k == '⌫';
        return _NfKeypadButton(
          label: k,
          isAction: isAction,
          large: large,
          onTap: () {
            HapticFeedback.selectionClick();
            if (k == 'C') {
              onClear();
            } else if (k == '⌫') {
              onBackspace();
            } else {
              onDigit(k);
            }
          },
        );
      }).toList(),
    );
  }
}

class _NfKeypadButton extends StatelessWidget {
  const _NfKeypadButton({
    required this.label,
    required this.onTap,
    required this.isAction,
    this.large = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isAction;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isAction ? NfTokens.card2 : NfTokens.elevated,
      borderRadius: BorderRadius.circular(large ? 20 : 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(large ? 20 : 16),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(large ? 20 : 16),
            border: Border.all(color: NfTokens.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: label == '⌫'
                  ? (large ? 32 : 26)
                  : (large ? 30 : 24),
              fontWeight: FontWeight.w800,
              color: isAction ? NfTokens.warn : NfTokens.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// Saisie téléphone BF : préfixe +226 fixe + 8 chiffres au grand pavé.
class NfPhoneEntry extends StatelessWidget {
  const NfPhoneEntry({
    super.key,
    required this.digits,
    required this.onChanged,
    this.maxDigits = 8,
    this.large = true,
  });

  /// Uniquement les 8 chiffres locaux (sans +226).
  final String digits;
  final ValueChanged<String> onChanged;
  final int maxDigits;
  final bool large;

  static String toE164(String localDigits) {
    final d = localDigits.replaceAll(RegExp(r'\D'), '');
    final eight = d.length > 8 ? d.substring(0, 8) : d;
    return '+226$eight';
  }

  static String localFromE164(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('226') && d.length >= 3) {
      final rest = d.substring(3);
      return rest.length > 8 ? rest.substring(0, 8) : rest;
    }
    return d.length > 8 ? d.substring(0, 8) : d;
  }

  @override
  Widget build(BuildContext context) {
    final shown = digits.length > maxDigits
        ? digits.substring(0, maxDigits)
        : digits;
    return Column(
      children: [
        Text(
          '+226',
          style: TextStyle(
            fontSize: large ? 28 : 22,
            fontWeight: FontWeight.w800,
            color: NfTokens.brandSoft,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final idealBox = large ? 34.0 : 30.0;
            final idealGap = large ? 6.0 : 4.0;
            final needed =
                idealBox * maxDigits + idealGap * (maxDigits - 1);
            final scale =
                needed > constraints.maxWidth && needed > 0
                    ? constraints.maxWidth / needed
                    : 1.0;
            final boxW = idealBox * scale;
            final boxH = (large ? 48.0 : 42.0) * scale;
            final gap = idealGap * scale;
            final fontSize = ((large ? 22.0 : 18.0) * scale).clamp(14.0, 22.0);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(maxDigits, (i) {
                final digit = i < shown.length ? shown[i] : '';
                return Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                  child: Container(
                    width: boxW,
                    height: boxH,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NfTokens.elevated,
                      borderRadius: BorderRadius.circular(10 * scale.clamp(0.85, 1.0)),
                      border: Border.all(
                        color:
                            digit.isNotEmpty ? NfTokens.brand : NfTokens.line,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      digit,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w800,
                        color: NfTokens.text,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
        const SizedBox(height: 16),
        NfNumericKeypad(
          large: large,
          onDigit: (d) {
            if (shown.length >= maxDigits) return;
            onChanged(shown + d);
          },
          onBackspace: () {
            if (shown.isEmpty) return;
            onChanged(shown.substring(0, shown.length - 1));
          },
          onClear: () => onChanged(''),
        ),
      ],
    );
  }
}

/// Affiche 4 cases PIN/OTP + grand clavier (faible littératie).
class NfPinEntry extends StatelessWidget {
  const NfPinEntry({
    super.key,
    required this.value,
    required this.onChanged,
    this.length = 4,
    this.obscure = false,
    this.large = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final int length;
  final bool obscure;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final shown = value.length > length ? value.substring(0, length) : value;
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final idealBox = large ? 56.0 : 48.0;
            const idealGap = 12.0;
            final needed = idealBox * length + idealGap * (length - 1);
            final scale =
                needed > constraints.maxWidth && needed > 0
                    ? constraints.maxWidth / needed
                    : 1.0;
            final boxW = idealBox * scale;
            final boxH = (large ? 64.0 : 56.0) * scale;
            final gap = idealGap * scale;
            final fontSize = ((large ? 32.0 : 28.0) * scale).clamp(18.0, 32.0);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(length, (i) {
                final digit = i < shown.length ? shown[i] : '';
                return Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                  child: Container(
                    width: boxW,
                    height: boxH,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NfTokens.elevated,
                      borderRadius: BorderRadius.circular(14 * scale.clamp(0.85, 1.0)),
                      border: Border.all(
                        color:
                            digit.isNotEmpty ? NfTokens.brand : NfTokens.line,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      digit.isEmpty ? '' : (obscure ? '•' : digit),
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w800,
                        color: NfTokens.brandSoft,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
        const SizedBox(height: 16),
        NfNumericKeypad(
          large: large,
          onDigit: (d) {
            if (shown.length >= length) return;
            onChanged(shown + d);
          },
          onBackspace: () {
            if (shown.isEmpty) return;
            onChanged(shown.substring(0, shown.length - 1));
          },
          onClear: () => onChanged(''),
        ),
      ],
    );
  }
}

/// Champ montant en lecture seule + clavier numérique intégré — combine
/// affichage grande taille et [NfNumericKeypad], relié à un [TextEditingController].
class NfKeypadAmountField extends StatelessWidget {
  const NfKeypadAmountField({
    super.key,
    required this.controller,
    required this.label,
    this.maxDigits = 9,
    this.trailing,
  });

  final TextEditingController controller;
  final String label;
  final int maxDigits;
  final Widget? trailing;

  void _append(String digit) {
    if (controller.text.length >= maxDigits) return;
    controller.text += digit;
  }

  void _backspace() {
    if (controller.text.isEmpty) return;
    controller.text = controller.text.substring(0, controller.text.length - 1);
  }

  void _clear() {
    controller.text = '';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: NfTokens.textMute, fontSize: 13)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: NfTokens.elevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NfTokens.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    final text = controller.text.isEmpty ? '0' : controller.text;
                    return Text(
                      text,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: NfTokens.brandSoft,
                      ),
                    );
                  },
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        const SizedBox(height: 14),
        NfNumericKeypad(
          onDigit: _append,
          onBackspace: _backspace,
          onClear: _clear,
        ),
      ],
    );
  }
}
