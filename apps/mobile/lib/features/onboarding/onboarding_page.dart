import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/client.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/nf_widgets.dart';
import '../auth/auth_provider.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  int step = 0;
  final nameCtrl = TextEditingController();
  String metier = 'commerce';
  String anciennete = '3_5';
  String caJour = '15_30k';
  bool tontine = true;
  String mobileMoney = 'regulier';
  bool shareImf = true;
  String language = 'fr';
  bool iconMode = false;
  bool voiceAssist = true;
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
    final lang = user?.language ?? ref.read(uxPrefsProvider).language;
    language = NfStrings.normalize(lang);
    iconMode = ref.read(uxPrefsProvider).iconMode;
    // Activée par défaut — cœur de l’accessibilité mooré
    voiceAssist = true;
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
          'anciennete': anciennete,
          'caJour': caJour,
          'tontine': tontine,
          'mobileMoney': mobileMoney,
          'city': 'Ouagadougou',
          'language': language,
          'consentAnonymized': true,
          'consentCreditPartners': shareImf,
          'consentMarketing': false,
        },
      );
      await api.patch(
        '/me/preferences',
        data: {
          'language': language,
          'modeIconographique': iconMode,
          'assistanceVocaleActive': voiceAssist,
        },
      );
      ref.read(uxPrefsProvider.notifier).setLanguageLocal(language);
      ref.read(uxPrefsProvider.notifier).setIconModeLocal(iconMode);
      ref.read(uxPrefsProvider.notifier).setVoiceAssistLocal(voiceAssist);
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
      ref
          .read(authProvider.notifier)
          .setUser(
            user.copyWith(
              displayName: me['displayName'] as String? ?? user.displayName,
              onboardingCompleted: true,
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (step > 0) {
          setState(() => step -= 1);
        } else {
          context.go('/app');
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'NeoForma',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: NfTokens.brand,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ton activité',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                'Étape ${step + 1} / 3 — alimente ton NeoScore',
                style: const TextStyle(color: NfTokens.textMute),
              ),
              const SizedBox(height: 20),
              if (step == 0) ...[
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Prénom / nom'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Métier',
                  style: TextStyle(color: NfTokens.textMute),
                ),
                const SizedBox(height: 8),
                NfSegmented(
                  value: metier,
                  onChanged: (v) => setState(() => metier = v),
                  options: const [
                    ('commerce', 'Commerce'),
                    ('artisanat', 'Artisanat'),
                    ('mecanique', 'Mécanique'),
                    ('restauration', 'Restauration'),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ancienneté',
                  style: TextStyle(color: NfTokens.textMute),
                ),
                const SizedBox(height: 8),
                NfSegmented(
                  value: anciennete,
                  onChanged: (v) => setState(() => anciennete = v),
                  options: const [
                    ('m1', '< 1 an'),
                    ('3_5', '3–5 ans'),
                    ('p10', '> 10 ans'),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Chiffre d’affaires journalier',
                  style: TextStyle(color: NfTokens.textMute),
                ),
                const SizedBox(height: 8),
                NfSegmented(
                  value: caJour,
                  onChanged: (v) => setState(() => caJour = v),
                  options: const [
                    ('m5k', '< 5 000'),
                    ('15_30k', '15–30 000'),
                    ('p100k', '> 100 000'),
                  ],
                ),
                const SizedBox(height: 24),
                NfPrimaryButton(
                  label: 'Suivant',
                  onPressed: () => setState(() => step = 1),
                ),
              ] else if (step == 1) ...[
                const Text(
                  'Tontine',
                  style: TextStyle(color: NfTokens.textMute),
                ),
                const SizedBox(height: 8),
                NfSegmented(
                  value: tontine ? 'oui' : 'non',
                  onChanged: (v) => setState(() => tontine = v == 'oui'),
                  options: const [('oui', 'Oui'), ('non', 'Non')],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Argent mobile',
                  style: TextStyle(color: NfTokens.textMute),
                ),
                const SizedBox(height: 8),
                NfSegmented(
                  value: mobileMoney,
                  onChanged: (v) => setState(() => mobileMoney = v),
                  options: const [
                    ('jamais', 'Jamais'),
                    ('occasionnel', 'Parfois'),
                    ('regulier', 'Souvent'),
                  ],
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => setState(() => step = 0),
                  child: const Text('Retour'),
                ),
                NfPrimaryButton(
                  label: 'Suivant',
                  onPressed: () => setState(() => step = 2),
                ),
              ] else ...[
                const Text(
                  'Tes données construisent ton NeoScore. Tu contrôles le partage avec les institutions de microfinance (IMF).',
                  style: TextStyle(color: NfTokens.textMute),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Langue',
                  style: TextStyle(color: NfTokens.textMute),
                ),
                const SizedBox(height: 8),
                NfSegmented(
                  value: language,
                  onChanged: (v) => setState(() => language = v),
                  options: NfStrings.selectableLanguages,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Mode icônes',
                  style: TextStyle(color: NfTokens.textMute),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Boutons plus grands, moins de texte — utile si on lit peu',
                  style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                ),
                const SizedBox(height: 8),
                NfSegmented(
                  value: iconMode ? 'oui' : 'non',
                  onChanged: (v) => setState(() => iconMode = v == 'oui'),
                  options: const [('oui', 'Oui'), ('non', 'Non')],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Assistance vocale',
                  style: TextStyle(color: NfTokens.textMute),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Écouter les libellés avec le bouton haut-parleur — utile en mooré',
                  style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                ),
                const SizedBox(height: 8),
                NfSegmented(
                  value: voiceAssist ? 'oui' : 'non',
                  onChanged: (v) => setState(() => voiceAssist = v == 'oui'),
                  options: const [('oui', 'Oui'), ('non', 'Non')],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Partage IMF',
                  style: TextStyle(color: NfTokens.textMute),
                ),
                const SizedBox(height: 8),
                NfSegmented(
                  value: shareImf ? 'ok' : 'later',
                  onChanged: (v) => setState(() => shareImf = v == 'ok'),
                  options: const [('ok', 'Autoriser'), ('later', 'Plus tard')],
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: NfTokens.danger)),
                ],
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => setState(() => step = 1),
                  child: const Text('Retour'),
                ),
                NfPrimaryButton(
                  label: loading ? 'Activation…' : 'Activer mon NeoScore',
                  loading: loading,
                  onPressed: loading ? null : _finish,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
