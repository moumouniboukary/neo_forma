import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import '../utils/qty.dart';

/// Saisie de quantité : grand chiffre, unité visible, + / − tactiles.
class NfQtyStepper extends StatelessWidget {
  const NfQtyStepper({
    super.key,
    required this.label,
    required this.unitLabel,
    required this.step,
    required this.onBump,
    this.controller,
    this.value,
    this.onChanged,
  });

  final String label;
  final String unitLabel;
  final double step;
  final void Function(num delta) onBump;
  final TextEditingController? controller;
  final double? value;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label ($unitLabel)',
          style: TextStyle(
            color: NfTokens.textMute,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: NfTokens.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: NfTokens.brand.withValues(alpha: 0.4),
              width: 1.6,
            ),
          ),
          child: Row(
            children: [
              _RoundQtyBtn(
                icon: Icons.remove,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onBump(-step);
                },
              ),
              Expanded(
                child: controller != null
                    ? TextField(
                        controller: controller,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                        ],
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: NfTokens.text,
                          height: 1.15,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (_) => onChanged?.call(),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          formatQty(value ?? 0),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: NfTokens.text,
                            height: 1.15,
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  unitLabel,
                  style: TextStyle(
                    color: NfTokens.brand,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              _RoundQtyBtn(
                icon: Icons.add,
                filled: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onBump(step);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoundQtyBtn extends StatelessWidget {
  const _RoundQtyBtn({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? NfTokens.brand : NfTokens.brand.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 54,
          height: 54,
          child: Icon(
            icon,
            size: 28,
            color: filled ? NfTokens.onBrand : NfTokens.brand,
          ),
        ),
      ),
    );
  }
}
