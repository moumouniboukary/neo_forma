import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/client.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/tokens.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/nf_speak_button.dart';
import '../../core/widgets/nf_widgets.dart';
import '../auth/auth_provider.dart';

/// Onboarding terrain : 1 écran (langue, nom, métier) + défauts sensés.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final nameCtrl = TextEditingController();
  String metier = 'commerce';
  String language = 'fr';
  bool shareImf = true;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    final existing = user?.displayName.trim() ?? '';
    if (existing.isNotEmpty &&
        existing != user?.phone &&
        !existing.startsWith('+')) {
      nameCtrl.text = existing;
    }
    language = NfStrings.normalize(
      user?.language ?? ref.read(uxPrefsProvider).language,
    );
    // Pas de mutation de provider dans initState (erreur Riverpod).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(uxPrefsProvider.notifier).setIconModeLocal(true);
      ref.read(uxPrefsProvider.notifier).setVoiceAssistLocal(true);
      ref.read(voiceServiceProvider).speakKey('onboardingQuick');
    });
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() {
      loading = true;
      error = null;
    });
    final api = ref.read(apiClientProvider);
    try {
      await api.patch(
        '/me',
        data: {
          'displayName': nameCtrl.text.trim().isEmpty
              ? 'Entrepreneur NeoForma'
              : nameCtrl.text.trim(),
          'metier': metier,
          // Défauts métier — évitent un long questionnaire
          'anciennete': '3_5',
          'caJour': '15_30k',
          'tontine': true,
          'tontineCotis': 5000,
          'chargesFixesMensuelles': 15000,
          'saisonnalite': 'stable',
          'garantieSolidaire': false,
          'mobileMoney': 'regulier',
          'city': 'Ouagadougou',
        },
      );
      await api.patch(
        '/me/preferences',
        data: {
          'language': language,
          'modeIconographique': true,
          'assistanceVocaleActive': true,
          // Conserve le thème actuel (souvent « system » au 1er lancement).
          'theme': ref.read(uxPrefsProvider).theme,
        },
      );
      ref.read(uxPrefsProvider.notifier).setLanguageLocal(language);
      ref.read(uxPrefsProvider.notifier).setIconModeLocal(true);
      ref.read(uxPrefsProvider.notifier).setVoiceAssistLocal(true);
      await api.put(
        '/me/consents',
        data: {
          'consentAnonymized': true,
          'consentCreditPartners': shareImf,
          'consentMarketing': false,
        },
      );
      final me = await api.post<Map<String, dynamic>>(
        '/me/onboarding/complete',
        parse: (d) => Map<String, dynamic>.from(d as Map),
      );
      final user = ref.read(authProvider).user!;
      ref.read(authProvider.notifier).setUser(
            user.copyWith(
              displayName: me['displayName'] as String? ?? user.displayName,
              onboardingCompleted: true,
              language: language,
            ),
          );
      await ref.read(authProvider.notifier).refreshMe().catchError((_) {});
      if (!mounted) return;
      context.go('/app');
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(nfStringsProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/app');
      },
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      NfTokens.appName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: NfTokens.brand,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const NfSpeakButton(
                    labelKey: 'onboardingQuick',
                    alwaysShow: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                t('onboardingQuick'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                t('onboardingQuickHint'),
                style: TextStyle(color: NfTokens.textMute, height: 1.35),
              ),
              const SizedBox(height: 24),
              Text(t('language'), style: TextStyle(color: NfTokens.textMute)),
              const SizedBox(height: 8),
              NfSegmented(
                value: language,
                onChanged: (v) {
                  setState(() => language = v);
                  ref.read(uxPrefsProvider.notifier).setLanguageLocal(v);
                  ref.read(voiceServiceProvider).speakKey('chooseLanguage');
                },
                options: NfStrings.selectableLanguages,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: t('displayName'),
                  hintText: t('displayNameHint'),
                ),
              ),
              const SizedBox(height: 20),
              Text(t('job'), style: TextStyle(color: NfTokens.textMute)),
              const SizedBox(height: 8),
              NfSegmented(
                value: metier,
                onChanged: (v) {
                  setState(() => metier = v);
                  ref.read(voiceServiceProvider).speakKey('job');
                },
                options: [
                  ('commerce', t('commerce')),
                  ('artisanat', t('craft')),
                  ('mecanique', t('mechanic')),
                  ('restauration', t('food')),
                ],
              ),
              const SizedBox(height: 20),
              Text(t('shareImf'), style: TextStyle(color: NfTokens.textMute)),
              const SizedBox(height: 8),
              NfSegmented(
                value: shareImf ? 'ok' : 'later',
                onChanged: (v) => setState(() => shareImf = v == 'ok'),
                options: [('ok', t('allow')), ('later', t('later'))],
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: NfTokens.danger)),
              ],
              const SizedBox(height: 28),
              NfPrimaryButton(
                label: loading ? t('activating') : t('activateScore'),
                loading: loading,
                onPressed: loading ? null : _finish,
              ),
              TextButton(
                onPressed: loading ? null : () => context.go('/app'),
                child: Text(t('later')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
