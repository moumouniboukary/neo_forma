import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/locale_provider.dart';
import '../theme/tokens.dart';
import '../voice/voice_service.dart';

export '../voice/spoken_amount.dart';

/// Confirmation visuelle + orale : 2 gros boutons (vert = oui, rouge = non).
Future<bool> showNfYesNoConfirm(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String message,
  String? speakKey,
  Map<String, String> speakVars = const {},
  String? speakText,
  String? yesLabel,
  String? noLabel,
}) async {
  final t = ref.read(nfStringsProvider);
  final voice = ref.read(voiceServiceProvider);
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (speakText != null && speakText.trim().isNotEmpty) {
      await voice.speakText(speakText);
    } else if (speakKey != null) {
      await voice.speakKey(speakKey, vars: speakVars);
    } else {
      await voice.speakText('$title. $message');
    }
  });

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NfTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: NfTokens.textMute,
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 72,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: NfTokens.ok,
                          foregroundColor: NfTokens.onBrand,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(
                          yesLabel ?? t('allow'),
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
                      height: 72,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: NfTokens.danger,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(
                          noLabel ?? t('deny'),
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
          ),
        ),
      );
    },
  );
  return result == true;
}

/// Confirmation de suppression d’opération (orale + boutons verts/rouges).
Future<bool> showNfDeleteConfirm(
  BuildContext context,
  WidgetRef ref, {
  required String label,
  required int amountFcfa,
  bool isExpense = false,
}) {
  final t = ref.read(nfStringsProvider);
  final fmt = NumberFormat.decimalPattern('fr');
  final amount = fmt.format(amountFcfa);
  final kind = isExpense ? t('expense') : t('sale');
  return showNfYesNoConfirm(
    context,
    ref,
    title: t('deleteOp'),
    message: '$kind · $label · $amount FCFA\n\n${t('confirmDeleteOp')}',
    speakKey: 'confirmDeleteOp',
    yesLabel: t('deleteOp'),
    noLabel: t('keepOp'),
  );
}
