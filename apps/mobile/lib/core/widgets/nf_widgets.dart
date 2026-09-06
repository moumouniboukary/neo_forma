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
    final logoUrl = NfTokens.logoUrl;
    final logoSize = fontSize * 0.95;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(logoSize * 0.22),
                child: logoUrl != null && logoUrl.isNotEmpty
                    ? Image.network(
                        logoUrl,
                        width: logoSize,
                        height: logoSize,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _NfLocalLogo(size: logoSize),
                      )
                    : _NfLocalLogo(size: logoSize),
              ),
              const SizedBox(width: 10),
              Text(
                NfTokens.appName,
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
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tagline,
          style: TextStyle(color: NfTokens.textMute, height: 1.4),
        ),
      ],
    );
  }
}

class _NfLocalLogo extends StatelessWidget {
  const _NfLocalLogo({this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/logo-icon.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(
          'assets/branding/app-icon-512.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
        );
      },
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

/// État vide / hors ligne sans cache local (première sync manquante).
class NfOfflineEmpty extends StatelessWidget {
  const NfOfflineEmpty({
    super.key,
    required this.message,
    this.icon = Icons.cloud_off_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 48),
        Icon(icon, size: 48, color: NfTokens.textMute),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: NfTokens.textMute, height: 1.4),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 20),
          NfPrimaryButton(label: actionLabel!, onPressed: onAction),
        ],
      ],
    );
  }
}
