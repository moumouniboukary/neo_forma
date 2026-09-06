import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/client.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/tokens.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/nf_numeric_keypad.dart';
import '../../core/widgets/nf_speak_button.dart';
import '../../core/widgets/nf_widgets.dart';
import '../sync/sync_service.dart';
import 'app_lock.dart';
import 'auth_provider.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  int step = 0;
  final phoneCtrl = TextEditingController(text: '+226 ');
  final otpCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  String phoneDigits = '';
  String language = 'fr';
  String? otpToken;
  String? devCode;
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    language = ref.read(uxPrefsProvider).language;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(uxPrefsProvider.notifier).setIconModeLocal(true);
      ref.read(uxPrefsProvider.notifier).setVoiceAssistLocal(true);
      _speakStep();
    });
  }

  void _setPhoneDigits(String d) {
    setState(() {
      phoneDigits = d;
      phoneCtrl.text = NfPhoneEntry.toE164(d);
      error = null;
    });
  }

  @override
  void dispose() {
    phoneCtrl.dispose();
    otpCtrl.dispose();
    pinCtrl.dispose();
    nameCtrl.dispose();
    super.dispose();
  }

  String get _stepKey =>
      step == 0 ? 'phoneEnter' : step == 1 ? 'smsCode' : 'displayName';

  Future<void> _speakStep() async {
    if (!mounted) return;
    if (!ref.read(uxPrefsProvider).voiceAssist) return;
    await ref.read(voiceServiceProvider).speakKey(_stepKey);
  }

  void _setStep(int next) {
    setState(() => step = next);
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakStep());
  }

  Future<void> _sendOtp() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await ref
          .read(authProvider.notifier)
          .requestOtp(phoneCtrl.text.trim(), OtpPurpose.register);
      setState(() {
        devCode = res.devCode;
        if (res.devCode != null) otpCtrl.text = res.devCode!;
      });
      _setStep(1);
      if (res.devCode != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final voice = ref.read(voiceServiceProvider);
          await voice.speakKey('otpAgentHint');
          await voice.speakText(res.devCode!.split('').join(' '));
        });
      }
    } on ApiException catch (e) {
      setState(
        () => error = e.isOffline
            ? (e.message.isNotEmpty && e.message != 'Hors ligne'
                ? e.message
                : ref.read(nfStringsProvider)('loginNeedsNetwork'))
            : e.message,
      );
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _verify() async {
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
            OtpPurpose.register,
          );
      setState(() => otpToken = token);
      _setStep(2);
    } on ApiException catch (e) {
      setState(
        () => error = e.isOffline
            ? (e.message.isNotEmpty && e.message != 'Hors ligne'
                ? e.message
                : ref.read(nfStringsProvider)('loginNeedsNetwork'))
            : e.message,
      );
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _register() async {
    if (otpToken == null) return;
    final name = nameCtrl.text.trim();
    final t = ref.read(nfStringsProvider);
    if (name.length < 2) {
      setState(() => error = t('nameRequired'));
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await ref.read(authProvider.notifier).register(
            phone: phoneCtrl.text.trim(),
            pin: pinCtrl.text.trim(),
            otpToken: otpToken!,
            displayName: name,
            language: language,
          );
      await ref.read(appLockProvider.notifier).setupPin(pinCtrl.text.trim());
      final lock = ref.read(appLockProvider);
      if (lock.biometricAvailable) {
        await ref.read(appLockProvider.notifier).setBiometricEnabled(true);
      }
      ref.read(uxPrefsProvider.notifier).setLanguageLocal(language);
      ref.read(uxPrefsProvider.notifier).setIconModeLocal(true);
      ref.read(uxPrefsProvider.notifier).setVoiceAssistLocal(true);
      unawaited(ref.read(syncServiceProvider).warmCaches());
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
      _setStep(step - 1);
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
    final t = ref.watch(nfStringsProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: nfBackButton(context, onPressed: _handleBack),
          title: Text(t('register')),
          actions: [
            NfSpeakButton(labelKey: _stepKey, alwaysShow: true),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                t('newAccount'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(t('chooseLanguage'),
                  style: TextStyle(color: NfTokens.textMute)),
              const SizedBox(height: 8),
              NfSegmented(
                value: language,
                onChanged: (v) {
                  setState(() => language = v);
                  ref.read(uxPrefsProvider.notifier).setLanguageLocal(v);
                  _speakStep();
                },
                options: NfStrings.selectableLanguages,
              ),
              const SizedBox(height: 16),
              if (step == 0) ...[
                Text(t('phoneEnter'), style: TextStyle(color: NfTokens.textMute)),
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
                  label: t('receiveCode'),
                  loading: loading,
                  onPressed: phoneDigits.length == 8 ? _sendOtp : null,
                ),
              ] else if (step == 1) ...[
                Text(
                  t('otpAgentHint'),
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
                          label: Text(t('otpListen')),
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
                  label: t('continue'),
                  loading: loading,
                  onPressed: otpCtrl.text.length == 4 ? _verify : null,
                ),
              ] else ...[
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: t('displayName'),
                    hintText: t('displayNameHint'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t('pinBigHint'),
                  style: TextStyle(color: NfTokens.textMute, fontSize: 13),
                ),
                const SizedBox(height: 10),
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
                  label: t('createAccount'),
                  loading: loading,
                  onPressed: pinCtrl.text.length == 4 &&
                          nameCtrl.text.trim().length >= 2
                      ? _register
                      : null,
                ),
              ],
              TextButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.push('/login');
                  }
                },
                child: Text(t('haveAccount')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  int step = 0;
  final phoneCtrl = TextEditingController(text: '+226 ');
  final otpCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  String? otpToken;
  String? devCode;
  String? info;
  String? error;
  bool loading = false;
  bool done = false;

  @override
  void dispose() {
    phoneCtrl.dispose();
    otpCtrl.dispose();
    pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await ref
          .read(apiClientProvider)
          .post<Map<String, dynamic>>(
            '/auth/forgot-password',
            data: {'phone': phoneCtrl.text.trim()},
            parse: (d) => Map<String, dynamic>.from(d as Map),
          );
      setState(() {
        info =
            data['message'] as String? ??
            'Si le compte existe, un code a été envoyé.';
        devCode = data['devCode'] as String?;
        step = 1;
      });
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _verify() async {
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
            OtpPurpose.reset,
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

  Future<void> _reset() async {
    if (otpToken == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/auth/reset-password',
            data: {
              'phone': phoneCtrl.text.trim(),
              'otpToken': otpToken,
              'newPin': pinCtrl.text.trim(),
            },
          );
      setState(() => done = true);
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } finally {
      setState(() => loading = false);
    }
  }

  void _handleBack() {
    if (done) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/login');
      }
      return;
    }
    if (step > 0) {
      setState(() => step -= 1);
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
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
          title: const Text('Code PIN oublié'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (done) ...[
                Text(
                  'Code PIN mis à jour',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Reconnectez-vous avec votre nouveau code.',
                  style: TextStyle(color: NfTokens.textMute),
                ),
                const SizedBox(height: 16),
                NfPrimaryButton(
                  label: 'Se connecter',
                  onPressed: () => context.go('/login'),
                ),
              ] else if (step == 0) ...[
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Téléphone'),
                ),
                if (error != null)
                  Text(error!, style: TextStyle(color: NfTokens.danger)),
                const SizedBox(height: 16),
                NfPrimaryButton(
                  label: 'Recevoir un code',
                  loading: loading,
                  onPressed: _send,
                ),
              ] else if (step == 1) ...[
                if (info != null)
                  Text(info!, style: TextStyle(color: NfTokens.textMute)),
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
                  onPressed: otpCtrl.text.length == 4 ? _verify : null,
                ),
              ] else ...[
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Nouveau code PIN',
                  ),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: NfTokens.danger)),
                const SizedBox(height: 16),
                NfPrimaryButton(
                  label: 'Enregistrer',
                  loading: loading,
                  onPressed: pinCtrl.text.length == 4 ? _reset : null,
                ),
              ],
              TextButton(onPressed: _handleBack, child: const Text('Retour')),
            ],
          ),
        ),
      ),
    );
  }
}
