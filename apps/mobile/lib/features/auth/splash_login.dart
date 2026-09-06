import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api/client.dart';
import '../../core/brand.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/theme/tokens.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/nf_numeric_keypad.dart';
import '../../core/widgets/nf_widgets.dart';
import '../sync/sync_service.dart';
import 'app_lock.dart';
import 'auth_provider.dart';

/// Page d'accueil publique (avant connexion).
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.ready) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Image(
                image: AssetImage('assets/branding/logo-icon.png'),
                width: 88,
                height: 88,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
              const SizedBox(height: 18),
              Text(
                kAppName,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: NfTokens.brand,
                  letterSpacing: -0.6,
                  height: 1,
                  fontFamily: 'sans-serif',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final gradientColors = <Color>[NfTokens.bgMid, NfTokens.bg, NfTokens.card2];
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: gradientColors,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: const _FeatureShowcase(),
                    ),
                  ),
                ),
                NfPrimaryButton(
                  label: auth.isAuthenticated ? 'Continuer' : 'Commencer',
                  onPressed: () {
                    if (!auth.isAuthenticated) {
                      context.push('/login');
                    } else {
                      context.go('/app');
                    }
                  },
                ),
                if (!auth.isAuthenticated) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('Créer un compte'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureShowcase extends StatelessWidget {
  const _FeatureShowcase();

  static const _items = <(IconData, String, String)>[
    (
      Icons.menu_book_rounded,
      'Cahier numérique',
      'Ventes, stock, créances — même hors ligne',
    ),
    (
      Icons.auto_graph_rounded,
      'NeoScore',
      'Solvabilité basée sur votre activité réelle',
    ),
    (
      Icons.account_balance_rounded,
      'Crédit adapté',
      'Offres liées à votre score et vos consentements',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _HomeFeature(
            icon: _items[i].$1,
            title: _items[i].$2,
            subtitle: _items[i].$3,
          ),
        ],
      ],
    );
  }
}

class _HomeFeature extends StatelessWidget {
  const _HomeFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = NfTokens.isDark;
    final wash = NfTokens.brand.withValues(alpha: isDark ? 0.14 : 0.10);
    final edge = NfTokens.brand.withValues(alpha: isDark ? 0.28 : 0.18);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: edge, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  NfTokens.brand.withValues(alpha: isDark ? 0.35 : 0.22),
                  NfTokens.brandSoft.withValues(alpha: isDark ? 0.18 : 0.12),
                ],
              ),
            ),
            child: Icon(icon, color: NfTokens.brandSoft, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.syne(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: NfTokens.text,
                    height: 1.15,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: NfTokens.textMute,
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  int step = 0;
  final phoneCtrl = TextEditingController(text: '+226 ');
  final otpCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  String phoneDigits = '';
  String? otpToken;
  String? devCode;
  String? error;
  bool loading = false;
  bool hasLocalSession = false;

  @override
  void initState() {
    super.initState();
    _checkLocalSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(uxPrefsProvider).voiceAssist) {
        ref.read(voiceServiceProvider).speakKey('phoneEnter');
      }
    });
  }

  void _setPhoneDigits(String d) {
    setState(() {
      phoneDigits = d;
      phoneCtrl.text = NfPhoneEntry.toE164(d);
      error = null;
    });
  }

  Future<void> _checkLocalSession() async {
    final session = ref.read(sessionStorageProvider);
    final token = await session.getAccessToken();
    final user = await session.getUser();
    if (!mounted) return;
    setState(() => hasLocalSession = token != null && user != null);
  }

  Future<void> _continueOffline() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final ok = await ref.read(authProvider.notifier).resumeLocalSession();
      if (!ok) {
        setState(() {
          hasLocalSession = false;
          error = ref.read(nfStringsProvider)('loginNeedsNetwork');
        });
        return;
      }
      if (!mounted) return;
      context.go('/app');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    phoneCtrl.dispose();
    otpCtrl.dispose();
    pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() {
      loading = true;
      error = null;
      devCode = null;
    });
    try {
      final res = await ref
          .read(authProvider.notifier)
          .requestOtp(phoneCtrl.text.trim(), OtpPurpose.login);
      setState(() {
        devCode = res.devCode;
        step = 1;
      });
      if (res.devCode != null) {
        // Collab / mode test : code affiché grand + lu à voix haute.
        otpCtrl.text = res.devCode!;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final voice = ref.read(voiceServiceProvider);
          await voice.speakKey('otpAgentHint');
          await voice.speakText(
            res.devCode!.split('').join(' '),
          );
        });
      }
    } on ApiException catch (e) {
      setState(() => error = e.isOffline
          ? (e.message.isNotEmpty && e.message != 'Hors ligne'
              ? e.message
              : ref.read(nfStringsProvider)('loginNeedsNetwork'))
          : e.message);
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final token = await ref
          .read(authProvider.notifier)
          .verifyOtp(
            phoneCtrl.text.trim(),
            otpCtrl.text.trim(),
            OtpPurpose.login,
          );
      setState(() {
        otpToken = token;
        step = 2;
      });
    } on ApiException catch (e) {
      setState(() => error = e.isOffline
          ? (e.message.isNotEmpty && e.message != 'Hors ligne'
              ? e.message
              : ref.read(nfStringsProvider)('loginNeedsNetwork'))
          : e.message);
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _login() async {
    if (otpToken == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .login(
            phone: phoneCtrl.text.trim(),
            pin: pinCtrl.text.trim(),
            otpToken: otpToken!,
          );
      await ref.read(appLockProvider.notifier).setupPin(pinCtrl.text.trim());
      final lock = ref.read(appLockProvider);
      if (lock.biometricAvailable) {
        await ref.read(appLockProvider.notifier).setBiometricEnabled(true);
      }
      // Précharge le cache pour un usage hors ligne immédiat.
      unawaited(ref.read(syncServiceProvider).warmCaches());
      if (!mounted) return;
      context.go('/app');
    } on ApiException catch (e) {
      setState(() => error = e.isOffline
          ? (e.message.isNotEmpty && e.message != 'Hors ligne'
              ? e.message
              : ref.read(nfStringsProvider)('loginNeedsNetwork'))
          : e.message);
    } finally {
      setState(() => loading = false);
    }
  }

  void _handleBack() {
    if (step > 0) {
      setState(() => step -= 1);
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: nfBackButton(context, onPressed: _handleBack),
          title: const Text('Connexion'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (step == 0) ...[
                Text(
                  ref.watch(nfStringsProvider)('phoneEnter'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ref.watch(nfStringsProvider)('phone'),
                        style: TextStyle(color: NfTokens.textMute),
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          ref.read(voiceServiceProvider).speakKey('phoneEnter'),
                      icon: const Icon(Icons.volume_up_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                NfPhoneEntry(
                  digits: phoneDigits,
                  onChanged: _setPhoneDigits,
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: NfTokens.danger)),
                ],
                const SizedBox(height: 16),
                NfPrimaryButton(
                  label: loading
                      ? '…'
                      : ref.watch(nfStringsProvider)('receiveCode'),
                  loading: loading,
                  onPressed: phoneDigits.length == 8 ? _sendOtp : null,
                ),
                if (hasLocalSession) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: loading ? null : _continueOffline,
                    child: Text(ref.watch(nfStringsProvider)('continueOffline')),
                  ),
                ],
              ] else if (step == 1) ...[
                Text(
                  ref.watch(nfStringsProvider)('smsCode'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  ref.watch(nfStringsProvider)('otpAgentHint'),
                  style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                ),
                if (devCode != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: NfTokens.card2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: NfTokens.sand, width: 2),
                    ),
                    child: Column(
                      children: [
                        Text(
                          ref.watch(nfStringsProvider)('otpAgentHint'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: NfTokens.sand,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          devCode!,
                          style: const TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 12,
                            color: NfTokens.brandSoft,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            ref.read(voiceServiceProvider).speakText(
                                  devCode!.split('').join(' '),
                                );
                          },
                          icon: const Icon(Icons.volume_up_outlined),
                          label: Text(ref.watch(nfStringsProvider)('otpListen')),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                NfPinEntry(
                  value: otpCtrl.text,
                  onChanged: (v) => setState(() {
                    otpCtrl.text = v;
                    error = null;
                  }),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: NfTokens.danger)),
                const SizedBox(height: 16),
                NfPrimaryButton(
                  label: ref.watch(nfStringsProvider)('continue'),
                  loading: loading,
                  onPressed: otpCtrl.text.length == 4 ? _verifyOtp : null,
                ),
                TextButton(
                  onPressed: loading
                      ? null
                      : () async {
                          setState(() => loading = true);
                          try {
                            final res = await ref
                                .read(authProvider.notifier)
                                .requestOtp(
                                  phoneCtrl.text.trim(),
                                  OtpPurpose.login,
                                );
                            setState(() {
                              devCode = res.devCode;
                              otpCtrl.clear();
                              if (res.devCode != null) {
                                otpCtrl.text = res.devCode!;
                              }
                            });
                            if (res.devCode != null) {
                              await ref.read(voiceServiceProvider).speakText(
                                    res.devCode!.split('').join(' '),
                                  );
                            }
                          } on ApiException catch (e) {
                            setState(() => error = e.message);
                          } finally {
                            setState(() => loading = false);
                          }
                        },
                  child: Text(ref.watch(nfStringsProvider)('receiveCode')),
                ),
              ] else ...[
                Text(
                  ref.watch(nfStringsProvider)('pinBigHint'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                NfPinEntry(
                  value: pinCtrl.text,
                  obscure: true,
                  onChanged: (v) => setState(() {
                    pinCtrl.text = v;
                    error = null;
                  }),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: NfTokens.danger)),
                const SizedBox(height: 16),
                NfPrimaryButton(
                  label: 'Se connecter',
                  loading: loading,
                  onPressed: pinCtrl.text.length == 4 ? _login : null,
                ),
              ],
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => context.push('/forgot-password'),
                child: const Text('Code PIN oublié ?'),
              ),
              TextButton(
                onPressed: () => context.push('/register'),
                child: const Text('Créer un compte'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
