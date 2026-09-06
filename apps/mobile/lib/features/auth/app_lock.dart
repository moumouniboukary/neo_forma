import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/riverpod_safe.dart';
import '../../core/theme/tokens.dart';
import '../../core/voice/voice_service.dart';
import '../../core/widgets/nf_numeric_keypad.dart';
import '../../core/widgets/nf_speak_button.dart';

/// Verrouillage applicatif : PIN local (déverrouillage rapide, indépendant du
/// PIN serveur) + biométrie optionnelle. Blocage 5 min après 5 échecs.
/// Relock uniquement après [inactivityTimeout] sans activité.
class AppLockState {
  const AppLockState({
    this.enabled = false,
    this.locked = false,
    this.failedAttempts = 0,
    this.lockedUntil,
    this.biometricAvailable = false,
    this.biometricEnabled = false,
  });

  /// Un PIN local de déverrouillage rapide a été configuré.
  final bool enabled;
  final bool locked;
  final int failedAttempts;
  final DateTime? lockedUntil;
  final bool biometricAvailable;
  final bool biometricEnabled;

  bool get isLockedOut =>
      lockedUntil != null && lockedUntil!.isAfter(DateTime.now());

  AppLockState copyWith({
    bool? enabled,
    bool? locked,
    int? failedAttempts,
    DateTime? lockedUntil,
    bool clearLockedUntil = false,
    bool? biometricAvailable,
    bool? biometricEnabled,
  }) {
    return AppLockState(
      enabled: enabled ?? this.enabled,
      locked: locked ?? this.locked,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockedUntil: clearLockedUntil ? null : (lockedUntil ?? this.lockedUntil),
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    );
  }
}

class AppLockNotifier extends StateNotifier<AppLockState> {
  AppLockNotifier() : super(const AppLockState()) {
    Future.microtask(_bootstrap);
  }

  static const maxAttempts = 5;
  static const lockDuration = Duration(minutes: 5);
  /// Délai d'inactivité avant de redemander le PIN au retour dans l'app.
  static const inactivityTimeout = Duration(minutes: 30);

  static const _pinKey = 'neoforma.applock.pin';
  static const _biometricKey = 'neoforma.applock.biometric';
  static const _failCountKey = 'neoforma.applock.failCount';
  static const _lockedUntilKey = 'neoforma.applock.lockedUntil';
  static const _lastActiveKey = 'neoforma.applock.lastActive';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();
  DateTime? _lastActiveAt;

  bool _isInactiveTooLong([DateTime? at]) {
    final last = at ?? _lastActiveAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= inactivityTimeout;
  }

  Future<void> _markActive() async {
    final now = DateTime.now();
    _lastActiveAt = now;
    await _storage.write(key: _lastActiveKey, value: now.toIso8601String());
  }

  Future<void> _bootstrap() async {
    final pin = await _storage.read(key: _pinKey);
    final bioEnabled = (await _storage.read(key: _biometricKey)) == '1';
    var bioAvailable = false;
    try {
      bioAvailable =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {
      bioAvailable = false;
    }
    final failCount =
        int.tryParse(await _storage.read(key: _failCountKey) ?? '0') ?? 0;
    final lockedUntilRaw = await _storage.read(key: _lockedUntilKey);
    final lockedUntil = lockedUntilRaw != null
        ? DateTime.tryParse(lockedUntilRaw)
        : null;
    final lastActiveRaw = await _storage.read(key: _lastActiveKey);
    _lastActiveAt =
        lastActiveRaw != null ? DateTime.tryParse(lastActiveRaw) : null;

    final shouldLock = pin != null && _isInactiveTooLong();

    final next = state.copyWith(
      enabled: pin != null,
      locked: shouldLock,
      failedAttempts: failCount,
      lockedUntil: lockedUntil,
      biometricAvailable: bioAvailable,
      biometricEnabled: bioEnabled,
    );
    scheduleProviderWrite(() => state = next);
  }

  /// Enregistre le PIN de déverrouillage rapide (appelé après login/register).
  Future<void> setupPin(String pin) async {
    if (pin.length != 4) return;
    await _storage.write(key: _pinKey, value: pin);
    await _storage.write(key: _failCountKey, value: '0');
    await _storage.delete(key: _lockedUntilKey);
    await _markActive();
    state = state.copyWith(
      enabled: true,
      locked: false,
      failedAttempts: 0,
      clearLockedUntil: true,
    );
  }

  Future<void> setBiometricEnabled(bool value) async {
    await _storage.write(key: _biometricKey, value: value ? '1' : '0');
    state = state.copyWith(biometricEnabled: value);
  }

  /// Verrouille l'app. No-op si aucun PIN local.
  void lock() {
    if (!state.enabled || state.locked) return;
    state = state.copyWith(locked: true);
  }

  /// App passe en arrière-plan : mémorise le moment (sans verrouiller tout de suite).
  Future<void> onBackgrounded() async {
    if (!state.enabled || state.locked) return;
    await _markActive();
  }

  /// Retour au premier plan : verrouille seulement après [inactivityTimeout].
  Future<void> onResumed() async {
    if (!state.enabled || state.locked) return;
    if (_isInactiveTooLong()) {
      lock();
      return;
    }
    await _markActive();
  }

  Future<bool> verifyPin(String pin) async {
    if (state.isLockedOut) return false;
    final stored = await _storage.read(key: _pinKey);
    if (stored != null && stored == pin) {
      await _storage.write(key: _failCountKey, value: '0');
      await _storage.delete(key: _lockedUntilKey);
      await _markActive();
      state = state.copyWith(
        locked: false,
        failedAttempts: 0,
        clearLockedUntil: true,
      );
      return true;
    }
    final attempts = state.failedAttempts + 1;
    if (attempts >= maxAttempts) {
      final until = DateTime.now().add(lockDuration);
      await _storage.write(key: _lockedUntilKey, value: until.toIso8601String());
      await _storage.write(key: _failCountKey, value: '0');
      state = state.copyWith(failedAttempts: 0, lockedUntil: until);
    } else {
      await _storage.write(key: _failCountKey, value: '$attempts');
      state = state.copyWith(failedAttempts: attempts);
    }
    return false;
  }

  Future<bool> authenticateBiometric() async {
    if (!state.biometricEnabled || !state.biometricAvailable) return false;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Déverrouiller NeoForma',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (ok) {
        await _markActive();
        state = state.copyWith(locked: false, failedAttempts: 0);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Purge tout état local (déconnexion / suppression compte).
  Future<void> clear() async {
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _failCountKey);
    await _storage.delete(key: _lockedUntilKey);
    await _storage.delete(key: _biometricKey);
    await _storage.delete(key: _lastActiveKey);
    _lastActiveAt = null;
    state = const AppLockState(
      biometricAvailable: false,
      biometricEnabled: false,
    );
  }
}

final appLockProvider = StateNotifierProvider<AppLockNotifier, AppLockState>((
  ref,
) {
  return AppLockNotifier();
});

/// Enveloppe le contenu applicatif : verrouille au retour de l'arrière-plan
/// et affiche l'écran de saisie PIN / biométrie tant que verrouillé.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider.notifier);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      lock.onBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      lock.onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    if (lock.enabled && lock.locked) {
      return const _AppLockScreen();
    }
    return widget.child;
  }
}

class _AppLockScreen extends ConsumerStatefulWidget {
  const _AppLockScreen();

  @override
  ConsumerState<_AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<_AppLockScreen> {
  String pin = '';
  String? error;
  bool checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryBiometric();
      final voiceOn = ref.read(uxPrefsProvider).voiceAssist;
      if (voiceOn) {
        ref.read(voiceServiceProvider).speakKey('enterPin');
      }
    });
  }

  Future<void> _tryBiometric() async {
    final lock = ref.read(appLockProvider);
    if (!lock.biometricEnabled || !lock.biometricAvailable) return;
    await ref.read(appLockProvider.notifier).authenticateBiometric();
  }

  Future<void> _submit() async {
    if (pin.length != 4 || checking) return;
    setState(() => checking = true);
    final ok = await ref.read(appLockProvider.notifier).verifyPin(pin);
    if (!mounted) return;
    final t = ref.read(nfStringsProvider);
    setState(() {
      checking = false;
      pin = '';
      error = ok ? null : t('wrongPin');
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final t = ref.watch(nfStringsProvider);
    final lockedOut = lock.isLockedOut;
    final iconMode = ref.watch(uxPrefsProvider).iconMode;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    void onDigit(String d) {
      if (pin.length >= 4 || checking) return;
      HapticFeedback.selectionClick();
      setState(() => pin += d);
      if (pin.length == 4) _submit();
    }

    void onBackspace() {
      if (pin.isEmpty) return;
      setState(() => pin = pin.substring(0, pin.length - 1));
    }

    final header = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.lock_outline,
          size: landscape ? 40 : (iconMode ? 64 : 48),
          color: NfTokens.brand,
        ),
        SizedBox(height: landscape ? 8 : 16),
        Text(
          t('appLocked'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: landscape ? 20 : (iconMode ? 28 : null),
                fontWeight: FontWeight.w800,
              ),
        ),
        const NfSpeakButton(labelKey: 'enterPin', alwaysShow: true),
        SizedBox(height: landscape ? 4 : 8),
        Text(
          t('pinBigHint'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: NfTokens.textMute,
            fontSize: landscape ? 13 : (iconMode ? 16 : 14),
          ),
        ),
        if (lockedOut)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t('lockedTryLater'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: NfTokens.danger),
            ),
          )
        else
          Padding(
            padding: EdgeInsets.symmetric(vertical: landscape ? 10 : 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final idealBox = landscape
                    ? 44.0
                    : (iconMode ? 56.0 : 48.0);
                const idealGap = 12.0;
                const count = 4;
                final needed = idealBox * count + idealGap * (count - 1);
                final scale = needed > constraints.maxWidth && needed > 0
                    ? constraints.maxWidth / needed
                    : 1.0;
                final boxW = idealBox * scale;
                final boxH =
                    (landscape ? 48.0 : (iconMode ? 64.0 : 56.0)) * scale;
                final gap = idealGap * scale;
                final fontSize =
                    ((landscape ? 24.0 : (iconMode ? 32.0 : 28.0)) * scale)
                        .clamp(16.0, 32.0);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(count, (i) {
                    final digit = i < pin.length ? pin[i] : '';
                    return Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                      child: Container(
                        width: boxW,
                        height: boxH,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: NfTokens.elevated,
                          borderRadius: BorderRadius.circular(
                            14 * scale.clamp(0.85, 1.0),
                          ),
                          border: Border.all(
                            color: digit.isNotEmpty
                                ? NfTokens.brand
                                : NfTokens.line,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          digit,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w800,
                            color: NfTokens.brandSoft,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(error!, style: const TextStyle(color: NfTokens.danger)),
        ],
      ],
    );

    final keypad = !lockedOut
        ? NfNumericKeypad(
            large: !landscape && iconMode,
            onDigit: onDigit,
            onBackspace: onBackspace,
            onClear: () => setState(() => pin = ''),
          )
        : const SizedBox.shrink();

    return Scaffold(
      backgroundColor: NfTokens.bg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(landscape ? 12 : 24),
          child: landscape
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(child: header),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: constraints.maxWidth.clamp(0, 360),
                              height: constraints.maxHeight.clamp(0, 340),
                              child: keypad,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    const SizedBox(height: 12),
                    header,
                    const SizedBox(height: 12),
                    if (!lockedOut)
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return FittedBox(
                                fit: BoxFit.contain,
                                alignment: Alignment.bottomCenter,
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight.clamp(0, 420),
                                  child: keypad,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
