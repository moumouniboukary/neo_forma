import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/tokens.dart';

class NfBrandHeader extends StatelessWidget {
  const NfBrandHeader({super.key, required this.tagline, this.fontSize = 36});

  final String tagline;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'NeoForma',
            maxLines: 1,
            softWrap: false,
            style: GoogleFonts.syne(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: NfTokens.brand,
              height: 1.05,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tagline,
          style: const TextStyle(color: NfTokens.textMute, height: 1.4),
        ),
      ],
    );
  }
}

/// Bouton retour AppBar — pop si possible, sinon fallback.
Widget nfBackButton(
  BuildContext context, {
  String fallbackLocation = '/',
  VoidCallback? onPressed,
}) {
  return IconButton(
    icon: const Icon(Icons.arrow_back),
    tooltip: 'Retour',
    onPressed: onPressed ??
        () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(fallbackLocation);
          }
        },
  );
}

class NfPrimaryButton extends StatelessWidget {
  const NfPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }
}

class NfSegmented extends StatelessWidget {
  const NfSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(String value, String label)> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        final selected = o.$1 == value;
        return ChoiceChip(
          label: Text(o.$2),
          selected: selected,
          onSelected: (_) => onChanged(o.$1),
          selectedColor: NfTokens.brand.withValues(alpha: 0.35),
          labelStyle: TextStyle(
            color: selected ? NfTokens.brandSoft : NfTokens.textMute,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          side: BorderSide(
            color: selected ? NfTokens.brand : NfTokens.line,
          ),
          backgroundColor: NfTokens.card2,
        );
      }).toList(),
    );
  }
}
