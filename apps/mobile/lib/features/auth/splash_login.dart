import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/client.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/nf_widgets.dart';
import 'auth_provider.dart';

/// Page d'accueil publique (avant connexion).
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [NfTokens.bgMid, NfTokens.bg, Color(0xFF04110C)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const NfBrandHeader(
                  tagline:
                      'Cahier numérique & passeport financier pour le secteur informel.',
                ),
                const SizedBox(height: 36),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Votre activité,\nvisible.',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Enregistrez ventes et créances, construisez votre NeoScore, accédez au microcrédit.',
                        style: TextStyle(
                          color: NfTokens.textMute,
                          height: 1.45,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const _HomeFeature(
                        icon: Icons.menu_book_outlined,
                        title: 'Cahier numérique',
                        subtitle: 'Ventes, stock, créances — même hors ligne',
                      ),
                      const SizedBox(height: 14),
                      const _HomeFeature(
                        icon: Icons.insights_outlined,
                        title: 'NeoScore',
                        subtitle: 'Solvabilité basée sur votre activité réelle',
                      ),
                      const SizedBox(height: 14),
                      const _HomeFeature(
                        icon: Icons.account_balance_outlined,
                        title: 'Crédit adapté',
                        subtitle:
                            'Offres liées à votre score et vos consentements',
                      ),
                    ],
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: NfTokens.elevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NfTokens.line),
          ),
          child: Icon(icon, color: NfTokens.brandSoft, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: NfTokens.textMute,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
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
  String? otpToken;
  String? devCode;
  String? error;
  bool loading = false;

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
    } on ApiException catch (e) {
      setState(() => error = e.message);
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
      setState(() => error = e.message);
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
      if (!mounted) return;
      context.go('/app');
    } on ApiException catch (e) {
      setState(() => error = e.message);
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
              const NfBrandHeader(
                tagline:
                    'Votre activité, visible. Votre solvabilité, accessible.',
              ),
              const SizedBox(height: 28),
              if (step == 0) ...[
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Téléphone'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: NfTokens.danger)),
                ],
                const SizedBox(height: 16),
                NfPrimaryButton(
                  label: loading ? 'Envoi…' : 'Recevoir le code',
                  loading: loading,
                  onPressed: _sendOtp,
                ),
              ] else if (step == 1) ...[
                Text(
                  'Code SMS',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Code SMS'),
                ),
                if (devCode != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: NfTokens.card2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: NfTokens.line),
                    ),
                    child: Text(
                      'Mode test · votre code est $devCode',
                      style: const TextStyle(color: NfTokens.sand),
                    ),
                  ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: NfTokens.danger)),
                const SizedBox(height: 16),
                NfPrimaryButton(
                  label: 'Continuer',
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
                            });
                          } on ApiException catch (e) {
                            setState(() => error = e.message);
                          } finally {
                            setState(() => loading = false);
                          }
                        },
                  child: const Text('Renvoyer le code'),
                ),
              ] else ...[
                Text(
                  'Votre code PIN',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Code PIN'),
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
