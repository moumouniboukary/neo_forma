import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/locale_provider.dart';
import '../theme/tokens.dart';
import '../voice/voice_service.dart';

/// Bouton écoute — visible si assistance vocale activée (ou [alwaysShow]).
class NfSpeakButton extends ConsumerWidget {
  const NfSpeakButton({
    super.key,
    this.labelKey,
    this.text,
    this.vars = const {},
    this.alwaysShow = false,
    this.tooltip,
    this.compact = false,
  }) : assert(labelKey != null || text != null);

  final String? labelKey;
  final String? text;
  final Map<String, String> vars;
  final bool alwaysShow;
  final String? tooltip;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceOn = ref.watch(uxPrefsProvider).voiceAssist;
    if (!voiceOn && !alwaysShow) return const SizedBox.shrink();

    final t = ref.watch(nfStringsProvider);
    return IconButton(
      tooltip: tooltip ?? t('listen'),
      iconSize: compact ? 22 : 28,
      color: NfTokens.brandSoft,
      onPressed: () async {
        final voice = ref.read(voiceServiceProvider);
        if (!voiceOn) {
          await ref.read(uxPrefsProvider.notifier).persist(voiceAssist: true);
        }
        if (labelKey != null) {
          await voice.speakKey(labelKey!, vars: vars);
        } else {
          await voice.speakText(text!);
        }
      },
      icon: const Icon(Icons.volume_up_rounded),
    );
  }
}

/// En-tête avec titre + bouton écoute.
class NfSpeakHeader extends ConsumerWidget {
  const NfSpeakHeader({
    super.key,
    required this.titleKey,
    this.vars = const {},
    this.style,
  });

  final String titleKey;
  final Map<String, String> vars;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(nfStringsProvider);
    final title =
        vars.isEmpty ? t(titleKey) : t.format(titleKey, vars);
    return Row(
      children: [
        Expanded(
          child: Text(title, style: style ?? Theme.of(context).textTheme.titleLarge),
        ),
        NfSpeakButton(labelKey: titleKey, vars: vars),
      ],
    );
  }
}
